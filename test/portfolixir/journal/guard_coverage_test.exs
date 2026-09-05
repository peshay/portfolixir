defmodule Portfolixir.Journal.GuardCoverageTest do
  # Issue #767: the tables the journal guard deliberately does not cover are a
  # closed, named list (ADR-0018 §5 scope tables), not a comment in the
  # migration that created them — so "guarded at the database" and the
  # documented exemptions together account for every table the code writes.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Journal.Allowlist
  alias Portfolixir.Repo

  # ADR-0018 §5 scope tables plus the ADR-0027 snapshot markers. Shrinking this
  # set (arming a table) is fine; growing it is an ADR amendment.
  @expected_unarmed MapSet.new(
                      ~w(views view_include_buckets view_exclude_buckets securities_account_buckets
                         cash_account_buckets position_bucket_overrides depot_snapshots)
                    )

  # User story:
  # As the operator relying on the audit journal,
  # I want every table the guard leaves uncovered named in one closed list with its reason,
  # so that an unguarded table is a decision on record, never an omission.
  #
  # Acceptance criteria:
  # - The unarmed scope set is exactly the seven ADR-0018 §5 / ADR-0027 tables.
  # - Each exists and carries no journal-actor guard.
  # - The two exemption sets do not overlap.
  test "the unarmed scope set is exactly the closed ADR-0018 list" do
    assert MapSet.new(Allowlist.unarmed_scope_tables()) == @expected_unarmed
    assert MapSet.disjoint?(@expected_unarmed, MapSet.new(Allowlist.non_journaled_tables()))
  end

  test "each unarmed scope table exists and carries no guard" do
    for table <- Allowlist.unarmed_scope_tables() do
      assert table_exists?(table), "scope table #{table} does not exist"
      refute guard_armed?(table), "scope table #{table} must not carry the journal-actor guard"
    end
  end

  defp table_exists?(table) do
    %{rows: [[exists]]} =
      Repo.query!(
        "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = $1)",
        [table]
      )

    exists
  end

  defp guard_armed?(table) do
    %{rows: [[count]]} =
      Repo.query!(
        """
        SELECT count(*)
        FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_proc p ON p.oid = t.tgfoid
        WHERE c.relname = $1
          AND p.proname = 'portfolixir_require_journal_actor'
          AND NOT t.tgisinternal
        """,
        [table]
      )

    count > 0
  end
end
