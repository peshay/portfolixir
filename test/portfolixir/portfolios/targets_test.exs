defmodule Portfolixir.Portfolios.TargetsTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor

  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets

  # User story:
  # As a local portfolio maintainer (and the LLM I connect over MCP),
  # I want to store my target weights per strategy category in Portfolixir,
  # so that the single source of truth carries my SOLL allocation instead of an
  # external document I have to keep in sync by hand.
  #
  # Acceptance criteria:
  # - Targets can be set, listed (optionally scoped to one classification), and
  #   deleted per portfolio and category.
  # - Setting a target again upserts the weight rather than duplicating it.
  # - A weight outside [0, 1] is rejected.
  # - A category from another classification cannot be targeted.

  defp setup_world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Local Portfolio",
        base_currency_code: "EUR"
      })

    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    {:ok, satellite} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Satellite"
      })

    %{portfolio: portfolio, classification: classification, core: core, satellite: satellite}
  end

  test "sets, lists, and scopes target weights per portfolio" do
    %{portfolio: portfolio, classification: classification, core: core, satellite: satellite} =
      setup_world()

    {:ok, targets} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.6"},
        %{"category_id" => satellite.id, "target_weight" => "0.4"}
      ])

    assert length(targets) == 2

    listed = Targets.list_targets(portfolio.id)
    assert length(listed) == 2

    scoped = Targets.list_targets(portfolio.id, classification_id: classification.id)
    assert length(scoped) == 2

    assert Targets.list_targets(portfolio.id, classification_id: classification.id + 999) == []
  end

  test "upserts an existing target instead of duplicating it" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.5"}
      ])

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.7"}
      ])

    [target] = Targets.list_targets(portfolio.id)
    assert Decimal.equal?(target.target_weight, Decimal.new("0.7"))
  end

  test "rejects a weight outside the unit interval" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    assert {:error, %Ecto.Changeset{} = changeset} =
             Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
               %{"category_id" => core.id, "target_weight" => "1.5"}
             ])

    assert %{target_weight: [_ | _]} = errors_on(changeset)
    assert Targets.list_targets(portfolio.id) == []
  end

  test "rejects a category from a different classification" do
    %{portfolio: portfolio, classification: classification} = setup_world()

    {:ok, other} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Regions"})

    {:ok, foreign} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: other.id,
        name: "Europe"
      })

    assert {:error, :category_mismatch} =
             Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
               %{"category_id" => foreign.id, "target_weight" => "0.5"}
             ])
  end

  test "deletes a target for one category" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.5"}
      ])

    assert {:ok, 1} = Targets.delete_target(Actor.owner_ui(), portfolio.id, core.id)
    assert Targets.list_targets(portfolio.id) == []
    assert {:ok, 0} = Targets.delete_target(Actor.owner_ui(), portfolio.id, core.id)
  end

  test "rejects a non-map target entry instead of crashing" do
    %{portfolio: portfolio, classification: classification} = setup_world()

    assert {:error, :invalid_entry} =
             Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [1])

    assert Targets.list_targets(portfolio.id) == []
  end

  # User story:
  # As a maintainer (or the MCP client) reading and editing one target,
  # I want to fetch a single portfolio/category target and to get clear errors
  # for unknown trees or malformed entries,
  # so that the SOLL editor never silently mis-files a weight.
  #
  # Acceptance criteria:
  # - get_target/2 returns the stored target, or nil when none exists.
  # - set_targets/3 against an unknown classification returns {:error, :not_found}.
  # - An entry whose category_id is a numeric string is matched to its category;
  #   a non-numeric id is treated as "no id" and left to the changeset.
  test "get_target/2 returns the stored target or nil" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    assert Targets.get_target(portfolio.id, core.id) == nil

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.6"}
      ])

    target = Targets.get_target(portfolio.id, core.id)
    assert target.category_id == core.id
    assert Decimal.equal?(target.target_weight, Decimal.new("0.6"))
  end

  test "set_targets/3 reports an unknown classification as :not_found" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    assert {:error, :not_found} =
             Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id + 999, [
               %{"category_id" => core.id, "target_weight" => "0.5"}
             ])
  end

  test "set_targets/3 accepts a numeric-string category id" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    # The string id matches the in-tree category (normalize_id parses it), so
    # the foreign-category guard passes and the weight is upserted.
    assert {:ok, [target]} =
             Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
               %{"category_id" => Integer.to_string(core.id), "target_weight" => "0.5"}
             ])

    assert target.category_id == core.id
  end

  test "set_targets/3 leaves a missing category id to the changeset" do
    %{portfolio: portfolio, classification: classification} = setup_world()

    # No category_id: the foreign-category guard treats it as "no id" and the
    # changeset rejects the row for the missing required category.
    assert {:error, %Ecto.Changeset{} = changeset} =
             Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
               %{"target_weight" => "0.5"}
             ])

    assert %{category_id: [_ | _]} = errors_on(changeset)
    assert Targets.list_targets(portfolio.id) == []
  end

  # User story:
  # As a local portfolio maintainer who steers per individual position (#481),
  # I want to store SOLL weights down to the individual security under a
  # category, with the category's effective target rolling up from its
  # positions,
  # so that categories become a derived pivot over positions instead of a
  # figure I have to hand-maintain.
  #
  # Acceptance criteria (ADR-0030, #481 slice 1):
  # - A per-position target is stored and read back with the exact Decimal.
  # - Category-only reads never see position rows (back-compat).
  # - A category's effective target rolls up from its position rows.
  # - When both a category row and position rows carry explicit weights, both
  #   are stored non-destructively; the position sum wins as the steering
  #   number and the mismatch is surfaced (never silently dropped).
  # - A position target for a security not under the category is rejected.
  # - Both partial unique indexes are enforced: a category row and N position
  #   rows coexist, and each upserts independently.
  # - Position-target writes are journaled (ADR-0017).

  defp create_assigned_security(classification, category, name) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, _} =
      Classifications.assign_security(
        Actor.owner_ui(),
        security.id,
        classification.id,
        category.id
      )

    security
  end

  test "sets a per-position target and reads it back with an exact Decimal" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()
    security = create_assigned_security(classification, core, "Alpha")

    assert {:ok, [target]} =
             Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
               %{"category_id" => core.id, "security_id" => security.id, "target_weight" => "0.3"}
             ])

    assert target.security_id == security.id
    assert target.category_id == core.id

    got = Targets.get_position_target(portfolio.id, core.id, security.id)
    assert got.security_id == security.id
    assert Decimal.equal?(got.target_weight, Decimal.new("0.3"))

    # Category-only reads never see the position row (back-compat with callers
    # like the allocation engine, which key targets by category_id).
    assert Targets.list_targets(portfolio.id) == []
    assert Targets.get_target(portfolio.id, core.id) == nil

    assert [listed] = Targets.list_position_targets(portfolio.id)
    assert listed.security_id == security.id
  end

  test "a category's effective target rolls up from its position rows" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()
    alpha = create_assigned_security(classification, core, "Alpha")
    beta = create_assigned_security(classification, core, "Beta")

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{"category_id" => core.id, "security_id" => alpha.id, "target_weight" => "0.3"},
        %{"category_id" => core.id, "security_id" => beta.id, "target_weight" => "0.2"}
      ])

    effective = Targets.effective_target(portfolio.id, core.id)
    assert effective.explicit == nil
    assert Decimal.equal?(effective.position_sum, Decimal.new("0.5"))
    assert Decimal.equal?(effective.effective, Decimal.new("0.5"))
    refute effective.conflict
  end

  test "stores and surfaces a category/position conflict instead of dropping either" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()
    alpha = create_assigned_security(classification, core, "Alpha")
    beta = create_assigned_security(classification, core, "Beta")

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.6"},
        %{"category_id" => core.id, "security_id" => alpha.id, "target_weight" => "0.3"},
        %{"category_id" => core.id, "security_id" => beta.id, "target_weight" => "0.2"}
      ])

    # Non-destructive: the explicit category row AND both position rows survive.
    assert [category_row] = Targets.list_targets(portfolio.id)
    assert Decimal.equal?(category_row.target_weight, Decimal.new("0.6"))
    assert length(Targets.list_position_targets(portfolio.id)) == 2

    effective = Targets.effective_target(portfolio.id, core.id)
    assert Decimal.equal?(effective.explicit, Decimal.new("0.6"))
    assert Decimal.equal?(effective.position_sum, Decimal.new("0.5"))
    # The position sum wins as the steering number (positions are the source of
    # truth, #481), and the mismatch is surfaced.
    assert Decimal.equal?(effective.effective, Decimal.new("0.5"))
    assert effective.conflict
  end

  test "rejects a position target for a security not under the category" do
    %{portfolio: portfolio, classification: classification, core: core, satellite: satellite} =
      setup_world()

    # Assigned to Satellite, not under Core. The error names the offending
    # (security, category) pair so the caller can render an actionable message
    # (UAT polish round).
    foreign = create_assigned_security(classification, satellite, "Beta")

    assert {:error, {:security_category_mismatch, security_id, category_id}} =
             Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
               %{"category_id" => core.id, "security_id" => foreign.id, "target_weight" => "0.3"}
             ])

    assert security_id == foreign.id
    assert category_id == core.id

    assert Targets.list_position_targets(portfolio.id) == []

    # An unassigned security is likewise rejected — a position target must name a
    # category the security actually sits in.
    {:ok, floating} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Floating",
        currency_code: "EUR",
        asset_class: "equity"
      })

    assert {:error, {:security_category_mismatch, floating_id, _category_id}} =
             Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
               %{"category_id" => core.id, "security_id" => floating.id, "target_weight" => "0.3"}
             ])

    assert floating_id == floating.id
  end

  test "accepts a position target on an ancestor category the security sits under" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    {:ok, tech} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Tech",
        parent_id: core.id
      })

    # Assigned to the child Tech; steering it at the ancestor Core is valid.
    security = create_assigned_security(classification, tech, "Alpha")

    assert {:ok, [target]} =
             Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
               %{"category_id" => core.id, "security_id" => security.id, "target_weight" => "0.4"}
             ])

    assert target.category_id == core.id
    assert target.security_id == security.id
  end

  test "enforces both partial unique indexes: category and position rows coexist and upsert" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()
    alpha = create_assigned_security(classification, core, "Alpha")

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.6"},
        %{"category_id" => core.id, "security_id" => alpha.id, "target_weight" => "0.3"}
      ])

    assert length(Targets.list_targets(portfolio.id)) == 1
    assert length(Targets.list_position_targets(portfolio.id)) == 1

    # Re-setting upserts each index independently rather than duplicating.
    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.7"},
        %{"category_id" => core.id, "security_id" => alpha.id, "target_weight" => "0.4"}
      ])

    assert [category_row] = Targets.list_targets(portfolio.id)
    assert Decimal.equal?(category_row.target_weight, Decimal.new("0.7"))
    assert [position_row] = Targets.list_position_targets(portfolio.id)
    assert Decimal.equal?(position_row.target_weight, Decimal.new("0.4"))
  end

  test "journals a position-target write" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()
    alpha = create_assigned_security(classification, core, "Alpha")

    {:ok, [target]} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{"category_id" => core.id, "security_id" => alpha.id, "target_weight" => "0.3"}
      ])

    entries = Journal.list_entries(resource_type: "target")

    assert Enum.any?(entries, fn entry ->
             entry.resource_id == to_string(target.id) and entry.after["security_id"] == alpha.id
           end)
  end

  test "deletes a single position target and leaves the category row" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()
    alpha = create_assigned_security(classification, core, "Alpha")

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.6"},
        %{"category_id" => core.id, "security_id" => alpha.id, "target_weight" => "0.3"}
      ])

    assert {:ok, 1} =
             Targets.delete_position_target(Actor.owner_ui(), portfolio.id, core.id, alpha.id)

    assert Targets.list_position_targets(portfolio.id) == []
    # The category row is untouched.
    assert [_category_row] = Targets.list_targets(portfolio.id)

    assert {:ok, 0} =
             Targets.delete_position_target(Actor.owner_ui(), portfolio.id, core.id, alpha.id)
  end

  # User story:
  # As a local portfolio maintainer steering per position (#481 fix round),
  # I want an entry whose security_id is present but garbage to be rejected,
  # so that a typo can never be silently coerced into a category-level write
  # that overwrites my category target.
  #
  # Acceptance criteria:
  # - A present security_id that does not normalize to a positive integer
  #   (non-numeric string, float, boolean, zero, negative) rejects the batch.
  # - Nothing is written: no position row and no silently coerced category row.
  # - An explicit nil security_id (JSON null) stays a category write.
  test "rejects a present-but-invalid security_id instead of coercing to a category write" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    for bad <- ["abc", "12x", 12.5, 12.0, true, 0, -3, "-3"] do
      assert {:error, :invalid_security_id} =
               Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
                 %{"category_id" => core.id, "security_id" => bad, "target_weight" => "0.3"}
               ]),
             "expected #{inspect(bad)} to be rejected as an invalid security_id"
    end

    # Nothing was written — neither a position row nor a coerced category row.
    assert Targets.list_targets(portfolio.id) == []
    assert Targets.list_position_targets(portfolio.id) == []

    # An explicit nil (JSON null) keeps meaning "category row" (back-compat).
    assert {:ok, [target]} =
             Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
               %{"category_id" => core.id, "security_id" => nil, "target_weight" => "0.5"}
             ])

    assert target.security_id == nil
  end

  # User story:
  # As a local portfolio maintainer steering per position (#481 fix round),
  # I want a plan to carry at most one position row per security,
  # so that a security can never steer two categories at once and the roll-up
  # stays interpretable.
  #
  # Acceptance criteria:
  # - A position entry for a security that already has a position row under a
  #   DIFFERENT category in the same plan is rejected with a clear error.
  # - Re-writing the same (category, security) row stays a legitimate upsert.
  # - Two entries for the same security under different categories within one
  #   batch are rejected.
  # - A batch naming the same (category, security) twice is rejected, not
  #   silently last-wins.
  test "rejects a second position row for the same security under a different category" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    {:ok, tech} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Tech",
        parent_id: core.id
      })

    alpha = create_assigned_security(classification, tech, "Alpha")

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{"category_id" => tech.id, "security_id" => alpha.id, "target_weight" => "0.3"}
      ])

    # Filing the same security a second time under the ancestor Core (a valid
    # placement on its own) is rejected: one position row per (plan, security).
    assert {:error, {:duplicate_position, sid}} =
             Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
               %{"category_id" => core.id, "security_id" => alpha.id, "target_weight" => "0.2"}
             ])

    assert sid == alpha.id
    assert [row] = Targets.list_position_targets(portfolio.id)
    assert row.category_id == tech.id
    assert Decimal.equal?(row.target_weight, Decimal.new("0.3"))

    # The same (category, security) pair stays a legitimate upsert.
    assert {:ok, _} =
             Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
               %{"category_id" => tech.id, "security_id" => alpha.id, "target_weight" => "0.4"}
             ])

    assert [row] = Targets.list_position_targets(portfolio.id)
    assert Decimal.equal?(row.target_weight, Decimal.new("0.4"))
  end

  test "rejects one batch filing the same security under two different categories" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    {:ok, tech} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Tech",
        parent_id: core.id
      })

    alpha = create_assigned_security(classification, tech, "Alpha")

    assert {:error, {:duplicate_position, sid}} =
             Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
               %{"category_id" => tech.id, "security_id" => alpha.id, "target_weight" => "0.3"},
               %{"category_id" => core.id, "security_id" => alpha.id, "target_weight" => "0.2"}
             ])

    assert sid == alpha.id
    assert Targets.list_position_targets(portfolio.id) == []
  end

  test "rejects one batch naming the same (category, security) position twice" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()
    alpha = create_assigned_security(classification, core, "Alpha")

    assert {:error, {:duplicate_position, sid}} =
             Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
               %{"category_id" => core.id, "security_id" => alpha.id, "target_weight" => "0.3"},
               %{"category_id" => core.id, "security_id" => alpha.id, "target_weight" => "0.4"}
             ])

    assert sid == alpha.id
    # Rejected outright — no silent last-wins write.
    assert Targets.list_position_targets(portfolio.id) == []
  end

  # User story:
  # As a local portfolio maintainer auditing my SOLL history (#481 fix round),
  # I want deleting a security to remove its position-target rows explicitly and
  # journaled, in every plan version,
  # so that the audit journal shows why a SOLL row vanished instead of a silent
  # FK cascade.
  #
  # Acceptance criteria:
  # - Deleting a security removes its position rows from active AND archived
  #   plans in the same transaction.
  # - Each removed row gets its own "target" journal delete entry.
  test "deleting a security journals the removal of its position rows in every plan" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()
    alpha = create_assigned_security(classification, core, "Alpha")

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{"category_id" => core.id, "security_id" => alpha.id, "target_weight" => "0.3"}
      ])

    # Duplicate into a draft (copies the position row) and activate it, so the
    # original plan is archived — the security now has a position row in an
    # active AND an archived plan.
    [original] = Targets.list_plans(portfolio.id, classification_id: classification.id)
    {:ok, copy} = Targets.duplicate_plan(Actor.owner_ui(), original)
    {:ok, _} = Targets.activate_plan(Actor.owner_ui(), copy)

    assert length(Targets.list_position_targets(portfolio.id, plan: original.id)) == 1
    assert length(Targets.list_position_targets(portfolio.id, plan: copy.id)) == 1

    assert {:ok, _} = Catalog.delete_security(Actor.owner_ui(), alpha)

    # Both rows are gone...
    assert Targets.list_position_targets(portfolio.id, plan: original.id) == []
    assert Targets.list_position_targets(portfolio.id, plan: copy.id) == []

    # ...and each removal is journaled as its own "target" delete entry.
    deletes =
      Journal.list_entries(resource_type: "target")
      |> Enum.filter(fn entry ->
        entry.operation == :delete and entry.before["security_id"] == alpha.id
      end)

    assert length(deletes) == 2
  end

  # User story:
  # As a local portfolio maintainer reclassifying securities (#481 fix round),
  # I want a position row whose security no longer sits under its stored
  # category to be flagged as stale,
  # so that the "never silently dropped" promise holds: the row keeps counting
  # where it was filed, and I see that re-filing it is my move.
  #
  # Acceptance criteria:
  # - A position row is flagged stale: true when its security is reassigned to a
  #   category outside the stored one, and stale: false while it still sits
  #   under it.
  # - An unassigned security's row is stale.
  # - The category roll-up carries has_stale.
  # - The math is unchanged: the stale row keeps counting in the position sum.
  test "flags position rows as stale when their security is reassigned or unassigned" do
    %{portfolio: portfolio, classification: classification, core: core, satellite: satellite} =
      setup_world()

    alpha = create_assigned_security(classification, core, "Alpha")
    beta = create_assigned_security(classification, core, "Beta")

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{"category_id" => core.id, "security_id" => alpha.id, "target_weight" => "0.3"},
        %{"category_id" => core.id, "security_id" => beta.id, "target_weight" => "0.2"}
      ])

    assert [a, b] = Targets.list_position_targets(portfolio.id)
    refute a.stale
    refute b.stale
    effective = Targets.effective_target(portfolio.id, core.id)
    refute effective.has_stale

    # Reassign Alpha out from under Core: its row now steers the old category.
    {:ok, _} =
      Classifications.assign_security(Actor.owner_ui(), alpha.id, classification.id, satellite.id)

    assert [a, b] = Targets.list_position_targets(portfolio.id)
    stale_by_security = %{a.security_id => a.stale, b.security_id => b.stale}
    assert stale_by_security[alpha.id] == true
    assert stale_by_security[beta.id] == false

    effective = Targets.effective_target(portfolio.id, core.id)
    assert effective.has_stale
    # No math change: the stale row keeps counting where it is (auditability).
    assert Decimal.equal?(effective.position_sum, Decimal.new("0.5"))

    # An unassigned security's row is stale too.
    {:ok, _} = Classifications.unassign_security(Actor.owner_ui(), beta.id, classification.id)

    assert [a, b] = Targets.list_position_targets(portfolio.id)
    assert a.stale
    assert b.stale
  end
end
