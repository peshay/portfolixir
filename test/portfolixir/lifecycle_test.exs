defmodule Portfolixir.LifecycleTest do
  # ADR-0050 §12 and §13 (risk-tier: audit, ADR-0036): the record a merge
  # leaves behind. A merge record says what was merged into what, by whom and
  # under which approved plan. It is append-only at the database and
  # journal-armed from the migration that creates it; the unboxed half of
  # that (a raw write without a journal actor) is pinned in
  # test/portfolixir/journal/append_only_test.exs.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Derived.BlastRadius
  alias Portfolixir.Journal
  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.MergeRecord
  alias Portfolixir.Portfolios
  alias Portfolixir.WorldFixtures

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  defp world do
    world = WorldFixtures.base_world(cash_name: "Savings")

    {:ok, old} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "Savings (old)",
        currency_code: "EUR"
      })

    Map.put(world, :old_cash, old)
  end

  defp cash_merge_attrs(world, overrides \\ %{}) do
    Map.merge(
      %{
        kind: "cash_account",
        source_id: world.old_cash.id,
        target_id: world.cash.id,
        portfolio_id: world.portfolio.id,
        source_snapshot: %{"name" => "Savings (old)", "currency_code" => "EUR"},
        manifest: %{"transactions" => %{"deleted" => [], "moved" => []}},
        plan_digest: "sha256:synthetic-plan"
      },
      overrides
    )
  end

  defp merge_record!(world) do
    {:ok, record} = Lifecycle.record_merge(agent(), cash_merge_attrs(world))
    record
  end

  # A raw write with the journal actor set, so the journal guard is not what
  # refuses it: the append-only trigger is.
  defp raw_write!(sql, params) do
    Repo.transaction(fn ->
      Repo.query!("SELECT set_config('portfolixir.journal_actor', 'owner_ui', true)")
      Repo.query!(sql, params)
    end)
  end

  describe "merge records (ADR-0050 §12)" do
    # User story:
    # As the operator (or the agent) who merged an account away,
    # I want one record per merge that names the source, the target, the
    # approved plan and who ran it,
    # so that a retry can return it, a merged-away id can answer where it
    # went, and the merge stays reconstructable by inspection.
    #
    # Acceptance criteria:
    # - The record keeps kind, source, target, portfolio, snapshot, manifest,
    #   plan digest and the actor, and its create is journaled under the
    #   resource code `merge_record`.
    # - A source is merged at most once per kind: a second record for the same
    #   kind and source is refused.
    test "a merge record is written once per source and journaled with its actor" do
      world = world()

      assert {:ok, %MergeRecord{} = record} =
               Lifecycle.record_merge(agent(), cash_merge_attrs(world))

      assert record.kind == :cash_account
      assert record.source_id == world.old_cash.id
      assert record.target_id == world.cash.id
      assert record.portfolio_id == world.portfolio.id
      assert record.plan_digest == "sha256:synthetic-plan"
      assert record.source_snapshot == %{"name" => "Savings (old)", "currency_code" => "EUR"}
      assert record.manifest == %{"transactions" => %{"deleted" => [], "moved" => []}}
      assert record.actor_type == :api_token_rw
      assert record.actor_label == "synthetic-agent"
      assert %DateTime{} = record.inserted_at

      assert [entry] =
               Journal.list_entries(resource_type: "merge_record", resource_id: "#{record.id}")

      assert entry.operation == :create
      assert entry.actor_type == :api_token_rw
      assert entry.after["plan_digest"] == "sha256:synthetic-plan"
      assert entry.after["kind"] == "cash_account"

      assert {:error, changeset} =
               Lifecycle.record_merge(agent(), cash_merge_attrs(world, %{target_id: -1}))

      assert %{source_id: ["has already been merged"]} = errors_on(changeset)

      # Ids are per table: the same number merged as a security is another source.
      assert {:ok, %MergeRecord{kind: :security}} =
               Lifecycle.record_merge(
                 agent(),
                 cash_merge_attrs(world, %{kind: "security", portfolio_id: nil})
               )
    end

    # Acceptance criteria (ADR-0050 §12):
    # - The kind is one of the three entities a merge exists for.
    # - Source and target are two different rows.
    # - An account merge names its portfolio; a security merge names none.
    test "a merge record names its kind, two different rows and, for an account, its portfolio" do
      world = world()

      assert {:error, changeset} =
               Lifecycle.record_merge(agent(), cash_merge_attrs(world, %{kind: "portfolio"}))

      # An Ecto.Enum cast error carries its type, which errors_on/1 cannot render.
      assert {"is invalid", _opts} = changeset.errors[:kind]

      assert {:error, changeset} =
               Lifecycle.record_merge(
                 agent(),
                 cash_merge_attrs(world, %{target_id: world.old_cash.id})
               )

      assert %{target_id: ["must differ from the source"]} = errors_on(changeset)

      assert {:error, changeset} =
               Lifecycle.record_merge(agent(), cash_merge_attrs(world, %{portfolio_id: nil}))

      assert %{portfolio_id: ["can't be blank"]} = errors_on(changeset)

      assert {:error, changeset} =
               Lifecycle.record_merge(agent(), cash_merge_attrs(world, %{kind: "security"}))

      assert %{portfolio_id: ["must be empty for a security merge"]} = errors_on(changeset)

      assert {:error, changeset} =
               Lifecycle.record_merge(agent(), cash_merge_attrs(world, %{plan_digest: nil}))

      assert %{plan_digest: ["can't be blank"]} = errors_on(changeset)

      assert Repo.aggregate(MergeRecord, :count) == 0
    end

    # Acceptance criteria (ADR-0050 §12, §16 invariant 11):
    # - A merge record is never updated or deleted, and the table is never
    #   truncated: the database refuses all three, not only the context.
    test "a merge record is never updated or deleted, at the database" do
      record = merge_record!(world())

      assert_raise Postgrex.Error, ~r/merge_records is append-only/, fn ->
        raw_write!("UPDATE merge_records SET target_id = 1 WHERE id = $1", [record.id])
      end

      assert_raise Postgrex.Error, ~r/merge_records is append-only/, fn ->
        raw_write!("DELETE FROM merge_records WHERE id = $1", [record.id])
      end

      assert_raise Postgrex.Error, ~r/merge_records is append-only/, fn ->
        raw_write!("TRUNCATE merge_records CASCADE", [])
      end

      assert Repo.get!(MergeRecord, record.id).target_id == record.target_id
    end
  end

  describe "the derived-value radius of the merge_record code (ADR-0050 §13, ADR-0039)" do
    # Acceptance criteria:
    # - A merge record feeds no portfolio walk and no security's own series:
    #   the rows a merge moves or deletes bump their own radius, so the record
    #   of the merge answers "none" — resolved per struct, never as a default.
    test "a merge record bumps no derived basis of its own" do
      record = %MergeRecord{id: 1, kind: :cash_account, portfolio_id: 1}

      assert BlastRadius.for_write("merge_record", record) == []
      assert BlastRadius.securities_for_write("merge_record", record) == []

      # An unresolvable record still widens.
      assert BlastRadius.for_write("merge_record", %{id: nil}) == :all
    end
  end
end
