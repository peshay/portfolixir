defmodule Portfolixir.Portfolios.PolicyRulesTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Derived.DataVersion
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios.PolicyRule
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Portfolios.PolicyRuleVersion

  # Relative to the real calendar day, never a fixed date: the immutability
  # trigger reads the database's CURRENT_DATE, so a fixed "today" would turn
  # these tests into a time bomb the day it falls into the past.
  defp today, do: Portfolixir.Clock.today()

  defp weight_cap(security, attrs \\ %{}) do
    Map.merge(
      %{
        subject_type: "security",
        security_id: security.id,
        measure: "weight",
        kind: "cap",
        threshold: "10",
        severity: "hard"
      },
      attrs
    )
  end

  defp rule!(portfolio, version_attrs, opts \\ []) do
    {:ok, rule} =
      PolicyRules.create_rule(
        Actor.owner_ui(),
        %{
          portfolio_id: portfolio.id,
          view_id: Keyword.get(opts, :view_id),
          name: Keyword.get(opts, :name, "Single name at most 10 %"),
          version: version_attrs
        },
        today: Keyword.get(opts, :today, today())
      )

    rule
  end

  defp versions(rule) do
    rule.id |> PolicyRules.get_rule() |> Map.fetch!(:versions)
  end

  setup do
    world = base_world(name: "Rules Portfolio")
    security = create_security!(name: "Nordic Timber Holdings AB", ticker: "NTH")
    %{world: world, security: security}
  end

  # User story (FR-43, ADR-0049 §1, §4, §8):
  # As the operator whose caps and floors today live as prose in a prompt,
  # I want to store a rule as an object with a first version in force from a
  # date,
  # so that the standard is read from the instance instead of restated, and
  # drifting, on every call.
  #
  # Acceptance criteria:
  # - The rule is stored with its context (portfolio, optional view) and its
  #   name; its first version carries the predicate and `valid_from`.
  # - Both writes are journaled (the tables are guard-armed from their first
  #   migration), and the closed sets come back as atoms, never as new atoms
  #   minted from input.
  # - The rules counter of the portfolio is bumped, so a findings read keyed
  #   on it can never outlive the edit.
  test "creates a rule with its first version, journaled, bumping the rules counter",
       %{world: world, security: security} do
    before_counter = DataVersion.current(DataVersion.rules_basis(world.portfolio.id))
    before_entries = length(Journal.list_entries())

    rule = rule!(world.portfolio, weight_cap(security, %{note: "the operator's words"}))

    assert %PolicyRule{name: "Single name at most 10 %", view_id: nil} = rule
    assert [%PolicyRuleVersion{} = version] = versions(rule)
    assert version.subject_type == :security
    assert version.measure == :weight
    assert version.kind == :cap
    assert version.severity == :hard
    assert Decimal.equal?(version.threshold, Decimal.new("10"))
    assert version.valid_from == today()
    assert version.valid_until == nil
    assert version.note == "the operator's words"

    entries = Journal.list_entries()
    assert length(entries) == before_entries + 2

    assert Enum.map(Enum.take(entries, 2), & &1.resource_type) |> Enum.sort() ==
             ["policy_rule", "policy_rule_version"]

    assert DataVersion.current(DataVersion.rules_basis(world.portfolio.id)) > before_counter
  end

  # Acceptance criteria (ADR-0049 §4, the invariant this family exists for,
  # mutation-verified in the closing act):
  # - A version that has been in force is never updated and never deleted —
  #   not through the context, and not through a raw write that bypasses it:
  #   the database refuses both.
  test "a version in force is immutable, in the context and at the database",
       %{world: world, security: security} do
    rule =
      rule!(world.portfolio, weight_cap(security, %{valid_from: Date.add(today(), -22)}),
        today: Date.add(today(), -22)
      )

    [version] = versions(rule)

    assert {:error, :in_force} = PolicyRules.delete_rule(Actor.owner_ui(), rule, today: today())

    # A raw update of the predicate, journal actor set so the guard trigger is
    # not what refuses it: the immutability trigger is.
    assert_raise Postgrex.Error, ~r/in force/, fn ->
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'owner_ui', true)")

        Repo.query!("UPDATE policy_rule_versions SET threshold = 12 WHERE id = $1", [
          version.id
        ])
      end)
    end

    assert_raise Postgrex.Error, ~r/in force/, fn ->
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'owner_ui', true)")
        Repo.query!("DELETE FROM policy_rule_versions WHERE id = $1", [version.id])
      end)
    end

    [unchanged] = versions(rule)
    assert Decimal.equal?(unchanged.threshold, Decimal.new("10"))
  end

  # Acceptance criteria (ADR-0049 §4):
  # - Two versions of one rule never overlap, and that is a database
  #   constraint, not only a changeset check: a raw insert of an overlapping
  #   period is refused by the exclusion constraint.
  test "two versions of one rule cannot overlap, at the database",
       %{world: world, security: security} do
    rule = rule!(world.portfolio, weight_cap(security))

    assert_raise Postgrex.Error, ~r/policy_rule_versions_no_overlap/, fn ->
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'owner_ui', true)")

        Repo.query!(
          """
          INSERT INTO policy_rule_versions
            (policy_rule_id, subject_type, security_id, measure, kind, threshold, severity,
             valid_from, inserted_at, updated_at)
          VALUES ($1, 'security', $2, 'weight', 'cap', 12, 'warn', $3, now(), now())
          """,
          [rule.id, security.id, Date.add(today(), 10)]
        )
      end)
    end
  end

  # User story (ADR-0049 §4):
  # As the operator raising a cap,
  # I want an edit to create a new version rather than overwrite the old one,
  # so that "what was the standard on date D" stays a read.
  #
  # Acceptance criteria:
  # - Adding a version from a date closes the previous version the day
  #   before; both stay readable.
  # - The standard on a date before the edit is the old version; on or after,
  #   the new one.
  # - A version cannot start before today (that would rewrite a period that
  #   already had a standard, and replay a rule over it: ladder level (d)).
  test "an edit adds a version and closes the previous one the day before",
       %{world: world, security: security} do
    rule =
      rule!(world.portfolio, weight_cap(security, %{valid_from: Date.add(today(), -114)}),
        today: Date.add(today(), -114)
      )

    assert {:ok, _version} =
             PolicyRules.add_version(
               Actor.owner_ui(),
               rule,
               weight_cap(security, %{threshold: "12"}),
               today: today()
             )

    [old, new] = versions(rule)
    assert old.valid_until == Date.add(today(), -1)
    assert new.valid_from == today()
    assert new.valid_until == nil

    assert %{threshold: t_old} = PolicyRules.version_on(rule.id, Date.add(today(), -22))
    assert Decimal.equal?(t_old, Decimal.new("10"))
    assert %{threshold: t_new} = PolicyRules.version_on(rule.id, today())
    assert Decimal.equal?(t_new, Decimal.new("12"))

    assert {:error, %Ecto.Changeset{} = changeset} =
             PolicyRules.add_version(
               Actor.owner_ui(),
               rule,
               weight_cap(security, %{valid_from: Date.add(today(), -3)}),
               today: today()
             )

    assert %{valid_from: [_ | _]} = errors_on(changeset)
  end

  # Acceptance criteria (ADR-0049 §4, pinned per guard — the closing act's
  # mutation pass found the two context guards masking each other in the
  # test above, so each is exercised here where the other one is silent):
  # - A new version may not start in the past, even after the version in
  #   force started: that would rewrite a period already evaluated.
  # - A new version may not start on or before the start of the version in
  #   force, even today: the version that started today is in force.
  test "each context guard refuses a rewrite of a period in force on its own",
       %{world: world, security: security} do
    long_running =
      rule!(world.portfolio, weight_cap(security, %{valid_from: Date.add(today(), -22)}),
        today: Date.add(today(), -22)
      )

    # Only the backdating guard can refuse this: the version in force started
    # 22 days ago, before the proposed start 3 days ago.
    assert {:error, %Ecto.Changeset{} = changeset} =
             PolicyRules.add_version(
               Actor.owner_ui(),
               long_running,
               weight_cap(security, %{valid_from: Date.add(today(), -3), threshold: "11"}),
               today: today()
             )

    assert %{valid_from: [_ | _]} = errors_on(changeset)
    assert [_one] = versions(long_running)

    started_today =
      rule!(world.portfolio, weight_cap(security, %{valid_from: today()}), today: today())

    # Only the in-force guard can refuse this: today is not in the past.
    assert {:error, %Ecto.Changeset{} = changeset} =
             PolicyRules.add_version(
               Actor.owner_ui(),
               started_today,
               weight_cap(security, %{valid_from: today(), threshold: "11"}),
               today: today()
             )

    assert %{valid_from: [_ | _]} = errors_on(changeset)
    assert [%{threshold: threshold}] = versions(started_today)
    assert Decimal.equal?(threshold, Decimal.new("10"))
  end

  # Acceptance criteria (ADR-0049 §4):
  # - A version whose valid_from is still in the future may be replaced:
  #   adding a version from the same date replaces the scheduled one, and
  #   the version in force is closed the day before the new one.
  test "a scheduled version is replaced by a version from the same date",
       %{world: world, security: security} do
    rule = rule!(world.portfolio, weight_cap(security))
    later = Date.add(today(), 10)

    {:ok, _} =
      PolicyRules.add_version(
        Actor.owner_ui(),
        rule,
        weight_cap(security, %{threshold: "11", valid_from: later}),
        today: today()
      )

    {:ok, _} =
      PolicyRules.add_version(
        Actor.owner_ui(),
        rule,
        weight_cap(security, %{threshold: "9", valid_from: later}),
        today: today()
      )

    [current, scheduled] = versions(rule)
    assert current.valid_until == Date.add(later, -1)
    assert scheduled.valid_from == later
    assert Decimal.equal?(scheduled.threshold, Decimal.new("9"))
  end

  # Acceptance criteria (ADR-0049 §4, closing act — correctness and edge-case
  # hunters):
  # - Retiring drops every version that has not started, whatever end date it
  #   is given: a retirement is the end of the rule, planned changes included
  #   (before, an end date past a scheduled start answered an overlap error).
  # - Retiring a rule that is already retired but scheduled to restart cancels
  #   the restart (before, nothing could: retire answered already_retired and
  #   delete answered in_force). With nothing scheduled it stays an error.
  test "a retirement cancels what is scheduled, even for a retired rule",
       %{world: world, security: security} do
    rule =
      rule!(world.portfolio, weight_cap(security, %{valid_from: Date.add(today(), -20)}),
        today: Date.add(today(), -20)
      )

    {:ok, _} =
      PolicyRules.add_version(
        Actor.owner_ui(),
        rule,
        weight_cap(security, %{threshold: "11", valid_from: Date.add(today(), 3)}),
        today: today()
      )

    until = Date.add(today(), 10)

    assert {:ok, closed} =
             PolicyRules.retire_rule(Actor.owner_ui(), rule, %{valid_until: until},
               today: today()
             )

    assert closed.valid_until == until
    assert [only] = versions(rule)
    assert Decimal.equal?(only.threshold, Decimal.new("10"))

    # Retired for good now (yesterday), then a restart is planned…
    other =
      rule!(world.portfolio, weight_cap(security, %{valid_from: Date.add(today(), -20)}),
        today: Date.add(today(), -20)
      )

    {:ok, _} = PolicyRules.retire_rule(Actor.owner_ui(), other, %{}, today: today())

    {:ok, _} =
      PolicyRules.add_version(
        Actor.owner_ui(),
        other,
        weight_cap(security, %{threshold: "12", valid_from: Date.add(today(), 5)}),
        today: today()
      )

    assert %{status: :scheduled} = PolicyRules.get_rule(other.id)

    # …and cancelled by retiring again.
    assert {:ok, _} = PolicyRules.retire_rule(Actor.owner_ui(), other, %{}, today: today())
    assert %{status: :retired} = PolicyRules.get_rule(other.id)
    assert [_one] = versions(other)

    assert {:error, :already_retired} =
             PolicyRules.retire_rule(Actor.owner_ui(), other, %{}, today: today())
  end

  # User story (ADR-0049 §4, §8):
  # As the operator dropping a rule,
  # I want retiring to end its version in force without deleting anything,
  # so that the rule and its history stay readable.
  #
  # Acceptance criteria:
  # - Retiring sets valid_until on the version in force (yesterday by
  #   default); the rule is no longer in force today but still listed with
  #   include_retired.
  # - A rule none of whose versions has ever been in force is deleted, not
  #   retired — and only such a rule can be deleted.
  test "retiring ends the version in force; only a never-in-force rule is deleted",
       %{world: world, security: security} do
    rule =
      rule!(world.portfolio, weight_cap(security, %{valid_from: Date.add(today(), -22)}),
        today: Date.add(today(), -22)
      )

    assert {:ok, _} = PolicyRules.retire_rule(Actor.owner_ui(), rule, %{}, today: today())
    assert [%{valid_until: until}] = versions(rule)
    assert until == Date.add(today(), -1)

    assert PolicyRules.list_rules(world.portfolio.id, as_of: today()) == []

    assert [%{id: id, status: :retired}] =
             PolicyRules.list_rules(world.portfolio.id, as_of: today(), include_retired: true)

    assert id == rule.id

    scheduled =
      rule!(world.portfolio, weight_cap(security, %{valid_from: Date.add(today(), 5)}),
        name: "Scheduled"
      )

    assert {:error, :never_in_force} =
             PolicyRules.retire_rule(Actor.owner_ui(), scheduled, %{}, today: today())

    assert {:ok, _} = PolicyRules.delete_rule(Actor.owner_ui(), scheduled, today: today())
    assert PolicyRules.get_rule(scheduled.id) == nil
  end

  # User story (ADR-0049 §2, §8):
  # As the agent writing a rule,
  # I want a predicate that does not fit its measure refused with the field
  # named,
  # so that a stored rule is always one the engine can evaluate.
  #
  # Acceptance criteria:
  # - The subject must fit the measure (the §2 matrix).
  # - The window is present exactly for the metric measures.
  # - A band carries lower ≤ upper and no threshold; a cap or floor carries a
  #   threshold and no band.
  # - Thresholds lie on the measure's scale: weight [0, 100], drift
  #   [−100, 100], HHI [0, 10000], volatility ≥ 0, max_drawdown [−100, 0].
  # - An unknown closed-set value is "is invalid", never a new atom.
  test "validates the predicate per measure", %{security: security} do
    cases = [
      {%{subject_type: "basis", measure: "weight", kind: "cap", threshold: "5"}, :subject_type},
      {%{subject_type: "basis", measure: "volatility", kind: "cap", threshold: "5"}, :window},
      {%{subject_type: "basis", measure: "hhi", kind: "cap", threshold: "5", window: "90d"},
       :window},
      {%{subject_type: "basis", measure: "hhi", kind: "band", lower: "5", upper: "1"}, :upper},
      {%{subject_type: "basis", measure: "hhi", kind: "band", threshold: "5"}, :lower},
      {%{subject_type: "basis", measure: "hhi", kind: "cap"}, :threshold},
      {%{subject_type: "basis", measure: "hhi", kind: "cap", threshold: "10001"}, :threshold},
      {%{subject_type: "cash", measure: "weight", kind: "floor", threshold: "101"}, :threshold},
      {%{subject_type: "cash", measure: "weight", kind: "floor", threshold: "-1"}, :threshold},
      {%{
         subject_type: "basis",
         measure: "volatility",
         window: "90d",
         kind: "cap",
         threshold: "-1"
       }, :threshold},
      {%{
         subject_type: "basis",
         measure: "max_drawdown",
         window: "90d",
         kind: "floor",
         threshold: "5"
       }, :threshold},
      {%{subject_type: "security", measure: "weight", kind: "cap", threshold: "5"}, :security_id},
      {%{subject_type: "category", measure: "weight", kind: "cap", threshold: "5"}, :category_id},
      {%{subject_type: "view", measure: "weight", kind: "cap", threshold: "5"}, :subject_view_id},
      {%{subject_type: "basis", measure: "entropy", kind: "cap", threshold: "5"}, :measure},
      {%{subject_type: "basis", measure: "hhi", kind: "cap", threshold: "5", severity: "panic"},
       :severity},
      {%{
         subject_type: "security",
         security_id: security.id,
         measure: "drift",
         kind: "cap",
         threshold: "5"
       }, :classification_id}
    ]

    for {attrs, field} <- cases do
      changeset =
        PolicyRuleVersion.changeset(
          %PolicyRuleVersion{},
          Map.merge(%{severity: "warn", valid_from: today(), policy_rule_id: 1}, attrs)
        )

      refute changeset.valid?, "expected #{inspect(attrs)} to be refused"

      assert Map.has_key?(errors_on(changeset), field),
             "expected #{inspect(attrs)} to name #{field}, got #{inspect(errors_on(changeset))}"
    end

    ok =
      PolicyRuleVersion.changeset(%PolicyRuleVersion{}, %{
        policy_rule_id: 1,
        subject_type: "basis",
        measure: "max_drawdown",
        window: "365d",
        kind: "floor",
        threshold: "-20",
        severity: "warn",
        valid_from: today()
      })

    assert ok.valid?
  end

  # Acceptance criteria (ADR-0049 §1, §2):
  # - A category subject names a category of its own classification; a view
  #   subject and a context view must exist.
  test "a category subject must belong to its classification", %{world: world} do
    {:ok, tree} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy", key: nil})

    {:ok, other} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Other", key: nil})

    {:ok, bonds} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: other.id,
        name: "Bonds"
      })

    assert {:error, {:version, %Ecto.Changeset{} = changeset}} =
             PolicyRules.create_rule(
               Actor.owner_ui(),
               %{
                 portfolio_id: world.portfolio.id,
                 name: "Bonds in band",
                 version: %{
                   subject_type: "category",
                   classification_id: tree.id,
                   category_id: bonds.id,
                   measure: "drift",
                   kind: "band",
                   lower: "-3",
                   upper: "3",
                   severity: "warn"
                 }
               },
               today: today()
             )

    assert %{category_id: [_ | _]} = errors_on(changeset)

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Spekulativ"})

    rule =
      rule!(
        world.portfolio,
        %{
          subject_type: "view",
          subject_view_id: view.id,
          measure: "weight",
          kind: "cap",
          threshold: "5",
          severity: "hard"
        },
        name: "Play money stays small"
      )

    assert [%{subject_view_id: view_id}] = versions(rule)
    assert view_id == view.id
  end

  # User story (#872, ADR-0049 §4 and §8 as amended by the Sprint 16 plan D-6):
  # As the operator whose raised floor still carries its old figure in its
  # name,
  # I want to rename the rule without retiring it,
  # so that the name says what the standard is while the history stays on the
  # rule it belongs to.
  #
  # Acceptance criteria:
  # - A rename changes the rule's name and nothing else: no version is added
  #   or changed, and the context (portfolio, view) stays, whatever else the
  #   attrs carry.
  # - It is journaled under the actor with the previous name in the entry's
  #   before-image, and it bumps the rules counter, because a finding carries
  #   the rule's name.
  # - A retired rule can be renamed, and two rules may share a name.
  # - A blank or over-long name is refused on the name, and nothing is
  #   written; resending the stored name writes nothing.
  test "a rename is a journaled rule-level edit outside the versioning",
       %{world: world, security: security} do
    {:ok, context} = Buckets.create_view(Actor.owner_ui(), %{name: "Langfristig"})

    rule =
      rule!(world.portfolio, weight_cap(security, %{valid_from: Date.add(today(), -30)}),
        today: Date.add(today(), -30),
        view_id: context.id,
        name: "Cash at least 1 %"
      )

    {:ok, _raised} =
      PolicyRules.add_version(
        Actor.owner_ui(),
        rule,
        weight_cap(security, %{threshold: "12"}),
        today: today()
      )

    before_versions = versions(rule)
    before_counter = DataVersion.current(DataVersion.rules_basis(world.portfolio.id))

    assert {:ok, %PolicyRule{} = renamed} =
             PolicyRules.rename_rule(Actor.api_token_rw(), rule, %{
               "name" => "  Cash at least 2 %  ",
               "view_id" => nil,
               "portfolio_id" => world.portfolio.id + 1
             })

    assert renamed.name == "Cash at least 2 %"
    stored = PolicyRules.get_rule(rule.id)
    assert stored.name == "Cash at least 2 %"
    assert stored.view_id == context.id
    assert stored.portfolio_id == world.portfolio.id
    assert stored.versions == before_versions

    assert [entry | _] = Journal.list_entries(resource_type: "policy_rule")
    assert entry.operation == :update
    assert entry.actor_type == :api_token_rw
    assert entry.resource_id == to_string(rule.id)
    assert entry.before["name"] == "Cash at least 1 %"
    assert entry.after["name"] == "Cash at least 2 %"
    assert DataVersion.current(DataVersion.rules_basis(world.portfolio.id)) > before_counter

    # Retired, and sharing its name with another rule: both allowed.
    {:ok, _closed} = PolicyRules.retire_rule(Actor.owner_ui(), stored, %{}, today: today())
    rule!(world.portfolio, weight_cap(security), name: "Single name capped")

    assert {:ok, %PolicyRule{name: "Single name capped"}} =
             PolicyRules.rename_rule(Actor.owner_ui(), stored, %{"name" => "Single name capped"})

    # Refused on the name, nothing written.
    entries = length(Journal.list_entries())

    assert {:error, %Ecto.Changeset{} = blank} =
             PolicyRules.rename_rule(Actor.owner_ui(), stored, %{"name" => "   "})

    assert %{name: ["can't be blank"]} = errors_on(blank)

    assert {:error, %Ecto.Changeset{} = missing} =
             PolicyRules.rename_rule(Actor.owner_ui(), stored, %{})

    assert %{name: ["can't be blank"]} = errors_on(missing)

    assert {:error, %Ecto.Changeset{} = long} =
             PolicyRules.rename_rule(Actor.owner_ui(), stored, %{
               "name" => String.duplicate("x", 256)
             })

    assert %{name: [_too_long]} = errors_on(long)

    assert {:ok, %PolicyRule{name: "Single name capped"}} =
             PolicyRules.rename_rule(Actor.owner_ui(), stored, %{"name" => "Single name capped"})

    assert length(Journal.list_entries()) == entries
    assert PolicyRules.get_rule(rule.id).name == "Single name capped"
  end

  # Acceptance criteria (#872, board 07 Part 1, the dialog's combined save):
  # - A rename together with a new version is one write: a refused version
  #   leaves the name as it was, and a refused name adds no version.
  test "a rename with a new version is one write", %{world: world, security: security} do
    rule =
      rule!(world.portfolio, weight_cap(security, %{valid_from: Date.add(today(), -30)}),
        today: Date.add(today(), -30)
      )

    entries = length(Journal.list_entries())

    assert {:error, %Ecto.Changeset{} = backdated} =
             PolicyRules.rename_and_add_version(
               Actor.owner_ui(),
               rule,
               %{"name" => "Single name at most 12 %"},
               weight_cap(security, %{threshold: "12", valid_from: Date.add(today(), -1)}),
               today: today()
             )

    assert %{valid_from: [_]} = errors_on(backdated)

    assert {:error, %Ecto.Changeset{} = blank} =
             PolicyRules.rename_and_add_version(
               Actor.owner_ui(),
               rule,
               %{"name" => ""},
               weight_cap(security, %{threshold: "12"}),
               today: today()
             )

    assert %{name: ["can't be blank"]} = errors_on(blank)
    assert PolicyRules.get_rule(rule.id).name == "Single name at most 10 %"
    assert length(versions(rule)) == 1
    assert length(Journal.list_entries()) == entries

    assert {:ok, %PolicyRuleVersion{}} =
             PolicyRules.rename_and_add_version(
               Actor.owner_ui(),
               rule,
               %{"name" => "Single name at most 12 %"},
               weight_cap(security, %{threshold: "12"}),
               today: today()
             )

    both = PolicyRules.get_rule(rule.id)
    assert both.name == "Single name at most 12 %"
    assert length(both.versions) == 2
  end

  # The S3/S4/D review round (LD-3):
  # Acceptance criteria:
  # - A rename of a rule deleted since it was read answers
  #   {:error, :not_found}, as its sibling writers answer a vanished rule,
  #   and never raises; the combined save answers the same.
  test "a rename of a rule deleted in the meantime is not found, never a raise",
       %{world: world, security: security} do
    rule =
      rule!(world.portfolio, weight_cap(security, %{valid_from: Date.add(today(), 5)}),
        name: "Scheduled cap"
      )

    {:ok, _deleted} = PolicyRules.delete_rule(Actor.owner_ui(), rule)

    assert {:error, :not_found} =
             PolicyRules.rename_rule(Actor.owner_ui(), rule, %{"name" => "Gone"})

    assert {:error, :not_found} =
             PolicyRules.rename_and_add_version(
               Actor.owner_ui(),
               rule,
               %{"name" => "Gone"},
               weight_cap(security, %{threshold: "12"})
             )
  end
end
