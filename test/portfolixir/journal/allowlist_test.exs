defmodule Portfolixir.Journal.AllowlistTest do
  use Portfolixir.DataCase, async: true

  # User story:
  # As a maintainer guarding the audit journal's completeness,
  # I want the set of write paths exempt from journaling to be a closed list
  # that can only shrink, and to match the tables actually left un-armed,
  # so that a new write path cannot silently escape the audit trail (ADR-0017).

  alias Portfolixir.Journal.Allowlist

  # Market-data ingestion only: quote sync and FX-rate sync. Shrinking this set
  # is fine; growing it is a deliberate ADR amendment, not a silent change.
  @expected_non_journaled MapSet.new(~w(security_quotes exchange_rates))

  test "the non-journaled allowlist is exactly the closed market-data set" do
    assert MapSet.new(Allowlist.non_journaled_tables()) == @expected_non_journaled
  end

  test "non_journaled?/1 reflects the list" do
    assert Allowlist.non_journaled?("security_quotes")
    assert Allowlist.non_journaled?("exchange_rates")
    refute Allowlist.non_journaled?("securities")
    refute Allowlist.non_journaled?("transactions")
  end

  test "allowlisted tables exist and are never guard-armed" do
    for table <- Allowlist.non_journaled_tables() do
      assert table_exists?(table), "allowlisted table #{table} does not exist"

      refute guard_armed?(table),
             "allowlisted table #{table} must not carry the journal-actor guard trigger"
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
