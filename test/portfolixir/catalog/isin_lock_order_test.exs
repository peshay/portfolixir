defmodule Portfolixir.Catalog.IsinLockOrderTest do
  # E25 S6 (#891) review round, F49: the journal's lock step re-reads a row
  # under the write's lock ahead of the business steps. In a security edit
  # that changes the ISIN, that put the security's row lock ahead of the ISIN
  # write lock (a transaction-scoped advisory lock), while an ISIN change and
  # an import take the ISIN write lock first and the row lock after it. Two
  # writers taking the same two locks in opposite orders can deadlock, and
  # the database then aborts one of them. Every ISIN writer now takes the
  # ISIN write lock first. Real two-connection concurrency cannot run under
  # the SQL sandbox, so the order is pinned by capturing the queries, as the
  # other lock tests of this batch do.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.IdentifierAliases

  defp owner, do: Actor.owner_ui()

  defp security! do
    {:ok, security} =
      Catalog.create_security(owner(), %{
        name: "Lock Order AG",
        isin: "DE00000000A3",
        currency_code: "EUR"
      })

    security
  end

  # User story:
  # As the operator editing a security's ISIN while an ISIN change or an
  # import runs on the same security,
  # I want both writes to take their locks in one order,
  # so that neither is aborted by a deadlock.
  #
  # Acceptance criteria:
  # - A security edit carrying an ISIN takes the ISIN write lock before it
  #   reads the security's row under a lock, as the ISIN change does.
  # - An edit that carries no ISIN takes no ISIN write lock.
  test "an ISIN edit takes the ISIN write lock before the security's row lock" do
    security = security!()

    edit =
      capture_queries(fn ->
        assert {:ok, _} = Catalog.update_security(owner(), security, %{isin: "DE00000000B1"})
      end)

    assert_advisory_first(edit, "the security edit")

    change =
      capture_queries(fn ->
        assert {:ok, _} =
                 IdentifierAliases.record_isin_change(
                   owner(),
                   Catalog.get_security(security.id),
                   "DE00000000A3"
                 )
      end)

    assert_advisory_first(change, "the ISIN change")

    rename =
      capture_queries(fn ->
        assert {:ok, _} = Catalog.update_security(owner(), security, %{name: "Renamed AG"})
      end)

    refute Enum.any?(rename, &(&1 =~ "pg_advisory_xact_lock"))
  end

  defp assert_advisory_first(queries, writer) do
    advisory = Enum.find_index(queries, &(&1 =~ "pg_advisory_xact_lock"))
    row = Enum.find_index(queries, &(&1 =~ ~r/FROM "securities".*FOR (NO KEY )?UPDATE/s))

    assert advisory, "#{writer} takes no ISIN write lock"
    assert row, "#{writer} reads no security under a lock"
    assert advisory < row, "#{writer} locks the security before the ISIN write lock"
  end

  defp capture_queries(fun) do
    test_pid = self()
    handler = "isin-lock-order-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:portfolixir, :repo, :query],
        fn _event, _measurements, %{query: query}, _config ->
          if self() == test_pid, do: send(test_pid, {:query, query})
        end,
        nil
      )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    collect_queries([])
  end

  defp collect_queries(acc) do
    receive do
      {:query, query} -> collect_queries([query | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
