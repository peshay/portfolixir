defmodule Portfolixir.LifecycleTest do
  # ADR-0050 §3, §12 and §13 (risk-tier: audit, ADR-0036): the two records a
  # merge leaves behind. A merge record says what was merged into what, by
  # whom and under which approved plan; a retired import hash keeps the
  # content hash of every row a merge removed, so a re-import can never book
  # that row again (obligation O1). Both are append-only at the database and
  # journal-armed from the migration that creates them; the unboxed half of
  # that (a raw write without a journal actor) is pinned in
  # test/portfolixir/journal/append_only_test.exs.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Derived.BlastRadius
  alias Portfolixir.Journal
  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.MergeRecord
  alias Portfolixir.Lifecycle.RetiredImportHash
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

  describe "what a survivor was merged from (ADR-0050 §12, L5a)" do
    # User story:
    # As the operator looking at an account that absorbed others,
    # I want to read which accounts were merged into it and when,
    # so that a merge is visible on the survivor and not only as a former
    # name.
    #
    # Acceptance criteria:
    # - merged_from/2 answers, per target id, the direct merges into it,
    #   oldest first, each with the source id, the name its snapshot recorded
    #   and the host's calendar date of the merge.
    # - A target nothing was merged into is absent; another kind's merge of
    #   the same ids is not counted.
    # - A security's merge also names the ISIN the source carried then (its
    #   snapshot's), for the survivor's "merged from … (then <ISIN>)" (L5b,
    #   board 03); an account's names none.
    test "lists the direct merges into each target, oldest first" do
      world = world()
      first = merge_record!(world)

      {:ok, second} =
        Lifecycle.record_merge(
          agent(),
          cash_merge_attrs(world, %{
            source_id: world.old_cash.id + 1_000_000,
            source_snapshot: %{"id" => world.old_cash.id + 1_000_000, "name" => "Savings 2"}
          })
        )

      {:ok, _other_kind} =
        Lifecycle.record_merge(
          agent(),
          cash_merge_attrs(world, %{kind: "securities_account", source_id: 42})
        )

      target = world.cash.id

      assert %{^target => [a, b]} =
               Lifecycle.merged_from(:cash_account, [target, target + 1_000_000])

      assert a == %{
               source_id: world.old_cash.id,
               source_name: "Savings (old)",
               source_isin: nil,
               merged_on: Portfolixir.Clock.local_date(first.inserted_at)
             }

      assert b.source_id == second.source_id
      assert b.source_name == "Savings 2"
      assert Lifecycle.merged_from(:security, [target]) == %{}

      {:ok, _security_merge} =
        Lifecycle.record_merge(agent(), %{
          kind: "security",
          source_id: 77,
          target_id: 78,
          source_snapshot: %{"id" => 77, "name" => "Fund X", "isin" => "XS0000000002"},
          manifest: %{},
          plan_digest: "sha256:synthetic-plan"
        })

      assert %{78 => [%{source_name: "Fund X", source_isin: "XS0000000002"}]} =
               Lifecycle.merged_from(:security, [78])
    end
  end

  describe "retired import hashes (ADR-0050 §3)" do
    # User story:
    # As the operator re-importing a Portfolio Performance export after a
    # merge removed an internal transfer or a collapsed duplicate,
    # I want the removed row's content hash kept as retired,
    # so that the same export can never book that row a second time.
    #
    # Acceptance criteria:
    # - A retirement keeps the hash, the removed row's id, the merge record,
    #   the reason and (for a collapse) the surviving row, and its create is
    #   journaled under the resource code `retired_import_hash`.
    # - A hash is retired at most once.
    test "a retired hash is written once and journaled" do
      record = merge_record!(world())

      attrs = %{
        import_hash: "synthetic-hash-transfer",
        former_transaction_id: 4_101,
        merge_record_id: record.id,
        reason: "internal_transfer"
      }

      assert {:ok, %RetiredImportHash{} = retired} = Lifecycle.retire_import_hash(agent(), attrs)

      assert retired.import_hash == "synthetic-hash-transfer"
      assert retired.former_transaction_id == 4_101
      assert retired.merge_record_id == record.id
      assert retired.reason == :internal_transfer
      assert retired.superseded_by_transaction_id == nil
      assert %DateTime{} = retired.inserted_at

      assert [entry] =
               Journal.list_entries(
                 resource_type: "retired_import_hash",
                 resource_id: "#{retired.id}"
               )

      assert entry.operation == :create
      assert entry.after["import_hash"] == "synthetic-hash-transfer"

      assert {:error, changeset} = Lifecycle.retire_import_hash(agent(), attrs)
      assert %{import_hash: ["has already been retired"]} = errors_on(changeset)
    end

    # Acceptance criteria (ADR-0050 §3, §5, §8):
    # - The reason is `internal_transfer` or `collapsed_duplicate`.
    # - A collapsed duplicate names the target row that superseded it; an
    #   internal transfer is void and names none.
    test "a retirement says why: a void transfer supersedes nothing, a collapse names its survivor" do
      record = merge_record!(world())

      base = %{
        import_hash: "synthetic-hash-pair",
        former_transaction_id: 4_102,
        merge_record_id: record.id
      }

      assert {:error, changeset} =
               Lifecycle.retire_import_hash(agent(), Map.put(base, :reason, "moved"))

      assert {"is invalid", _opts} = changeset.errors[:reason]

      assert {:error, changeset} =
               Lifecycle.retire_import_hash(
                 agent(),
                 Map.put(base, :reason, "collapsed_duplicate")
               )

      assert %{superseded_by_transaction_id: ["can't be blank"]} = errors_on(changeset)

      assert {:error, changeset} =
               Lifecycle.retire_import_hash(
                 agent(),
                 Map.merge(base, %{reason: "internal_transfer", superseded_by_transaction_id: 7})
               )

      assert %{superseded_by_transaction_id: ["must be empty for an internal transfer"]} =
               errors_on(changeset)

      assert {:ok,
              %RetiredImportHash{reason: :collapsed_duplicate, superseded_by_transaction_id: 7}} =
               Lifecycle.retire_import_hash(
                 agent(),
                 Map.merge(base, %{reason: "collapsed_duplicate", superseded_by_transaction_id: 7})
               )
    end

    # Acceptance criteria (ADR-0050 §3, §12):
    # - Every retirement belongs to a merge record that exists. The check is
    #   deferred to the commit, so a merge may retire hashes before it writes
    #   its record (ADR-0050 §7's step order); forced immediate here.
    test "a retirement belongs to a merge record that exists" do
      parent = self()

      Repo.transaction(fn ->
        Repo.query!("SET CONSTRAINTS retired_import_hashes_merge_record_id_fkey IMMEDIATE")

        result =
          Lifecycle.retire_import_hash(agent(), %{
            import_hash: "synthetic-hash-orphan",
            former_transaction_id: 4_103,
            merge_record_id: -1,
            reason: "internal_transfer"
          })

        send(parent, {:retired, result})
      end)

      assert_received {:retired, {:error, changeset}}
      assert %{merge_record_id: ["does not exist"]} = errors_on(changeset)
    end

    # Acceptance criteria (ADR-0050 §3, §16 invariant 11):
    # - A retired hash is never updated or deleted, and the table is never
    #   truncated: the database refuses all three.
    test "a retired hash is never updated or deleted, at the database" do
      record = merge_record!(world())

      {:ok, retired} =
        Lifecycle.retire_import_hash(agent(), %{
          import_hash: "synthetic-hash-kept",
          former_transaction_id: 4_104,
          merge_record_id: record.id,
          reason: "internal_transfer"
        })

      assert_raise Postgrex.Error, ~r/retired_import_hashes is append-only/, fn ->
        raw_write!("UPDATE retired_import_hashes SET import_hash = 'freed' WHERE id = $1", [
          retired.id
        ])
      end

      assert_raise Postgrex.Error, ~r/retired_import_hashes is append-only/, fn ->
        raw_write!("DELETE FROM retired_import_hashes WHERE id = $1", [retired.id])
      end

      # The sandbox never commits, so the deferred merge-record check of the
      # insert above is still pending, and PostgreSQL refuses a TRUNCATE with
      # pending trigger events before any trigger runs. Firing the check first
      # puts the table where a committed merge leaves it.
      assert_raise Postgrex.Error, ~r/retired_import_hashes is append-only/, fn ->
        Repo.transaction(fn ->
          Repo.query!("SET CONSTRAINTS retired_import_hashes_merge_record_id_fkey IMMEDIATE")
          Repo.query!("SELECT set_config('portfolixir.journal_actor', 'owner_ui', true)")
          Repo.query!("TRUNCATE retired_import_hashes")
        end)
      end

      assert Repo.get!(RetiredImportHash, retired.id).import_hash == "synthetic-hash-kept"
    end
  end

  describe "the derived-value radius of the two resource codes (ADR-0050 §13, ADR-0039)" do
    # Acceptance criteria:
    # - Neither record feeds a portfolio walk or a security's own series: the
    #   rows a merge moves or deletes bump their own radius, so the record of
    #   the merge answers "none" — resolved per struct, never as a default.
    test "a merge record and a retired hash bump no derived basis of their own" do
      record = %MergeRecord{id: 1, kind: :cash_account, portfolio_id: 1}
      retired = %RetiredImportHash{id: 1, import_hash: "synthetic", merge_record_id: 1}

      assert BlastRadius.for_write("merge_record", record) == []
      assert BlastRadius.for_write("retired_import_hash", retired) == []
      assert BlastRadius.securities_for_write("merge_record", record) == []
      assert BlastRadius.securities_for_write("retired_import_hash", retired) == []

      # An unresolvable record of either code still widens.
      assert BlastRadius.for_write("merge_record", %{id: nil}) == :all
    end
  end
end
