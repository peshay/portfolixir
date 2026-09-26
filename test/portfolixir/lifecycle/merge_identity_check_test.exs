defmodule Portfolixir.Lifecycle.MergeIdentityCheckTest do
  # ADR-0050 §7 step 6 and §9, §16 invariants 9 and 10 (the closing act's
  # patch-coverage pass, #328 and #608; risk-tier: money and quantity
  # identity, ADR-0036). Every merge reads the target back after its writes
  # and compares it with the plan: the cash merge the target's balance on
  # every date with the sum of both accounts' kept rows, the depot and the
  # security merge the merged quantity with the fold of both sides' kept
  # rows. A difference is a bug in the merge, never an expected answer, so
  # it rolls the whole merge back with `identity_check_failed`.
  #
  # Nothing in a correct merge makes the check fail, so these tests make one
  # write land other than planned (`Portfolixir.MisplannedWrite`): a
  # trigger, created inside the test's own transaction and rolled back with
  # it, changes the amount or the quantity of every row the merge re-points.
  # The merge must notice, answer identity_check_failed naming the date and
  # both figures, and leave every table as it was. The API half (a 409, the
  # figures as strings) is merge_identity_check_controller_test.exs.
  #
  # async: false — creating a trigger on `transactions` takes a lock every
  # concurrent test on the ledger would wait on.
  #
  # Every name, amount and quantity is synthetic.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Lifecycle
  alias Portfolixir.MisplannedWrite
  alias Portfolixir.Portfolios

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Identity World",
        base_currency_code: "EUR"
      })

    %{portfolio: portfolio}
  end

  # User story:
  # As the operator merging two cash accounts,
  # I want a merge whose writes do not add up to the two accounts' sum
  # rolled back whole,
  # so that a bug in the merge can never leave a balance I did not approve.
  #
  # Acceptance criteria:
  # - A re-pointed row's amount changed by the write: the apply answers
  #   {:identity_check_failed, %{date, expected, actual}} with the planned
  #   and the written balance, and every table is unchanged.
  test "a cash merge whose write changes an amount rolls back", ctx do
    target = cash!(ctx.portfolio, "Savings")
    source = cash!(ctx.portfolio, "Savings (old)")
    deposit!(ctx.portfolio, target, "500.00", ~D[2025-01-02])
    deposit!(ctx.portfolio, source, "250.00", ~D[2025-01-03])
    {:ok, preview} = Lifecycle.preview_cash_merge(source.id, target.id)

    MisplannedWrite.install!("cash_account_id", "gross_amount")
    before = fingerprint()

    assert {:error, {:identity_check_failed, %{date: date, expected: expected, actual: actual}}} =
             Lifecycle.merge_cash_account(agent(), source.id, target.id, consent(preview))

    assert date == ~D[2025-01-03]
    assert {n(expected), n(actual)} == {dec("750"), dec("751")}
    assert fingerprint() == before
  end

  # User story:
  # As the operator merging two depots,
  # I want a merge whose writes do not fold to the planned position rolled
  # back whole,
  # so that a bug in the merge can never leave a quantity I did not approve.
  #
  # Acceptance criteria:
  # - A re-pointed row's quantity changed by the write: the apply answers
  #   {:identity_check_failed, %{date, security_id, expected, actual}}, and
  #   every table is unchanged.
  test "a depot merge whose write changes a quantity rolls back", ctx do
    cash = cash!(ctx.portfolio, "Broker cash")
    target = depot!(ctx.portfolio, cash, "Depot 1")
    source = depot!(ctx.portfolio, cash, "Depot 2")
    security = security!("Synthetic Identity ETF")
    delivery!(ctx.portfolio, target, security, "10", ~D[2025-01-02])
    delivery!(ctx.portfolio, source, security, "4", ~D[2025-01-03])
    {:ok, preview} = Lifecycle.preview_depot_merge(source.id, target.id)

    MisplannedWrite.install!("securities_account_id", "quantity")
    before = fingerprint()

    assert {:error,
            {:identity_check_failed,
             %{date: date, security_id: security_id, expected: expected, actual: actual}}} =
             Lifecycle.merge_depot(agent(), source.id, target.id, consent(preview))

    assert {date, security_id} == {~D[2025-01-03], security.id}
    assert {n(expected), n(actual)} == {dec("14"), dec("15")}
    assert fingerprint() == before
  end

  # User story:
  # As the operator merging a duplicate security into the one I keep,
  # I want a merge whose writes do not fold to the planned position rolled
  # back whole,
  # so that a bug in the merge can never leave a quantity I did not approve.
  #
  # Acceptance criteria:
  # - A re-pointed row's quantity changed by the write: the apply answers
  #   {:identity_check_failed, %{date, securities_account_id, security_id,
  #   expected, actual}}, and every table is unchanged.
  test "a security merge whose write changes a quantity rolls back", ctx do
    cash = cash!(ctx.portfolio, "Broker cash")
    depot = depot!(ctx.portfolio, cash, "Depot 1")
    target = security!("Synthetic Identity Fund")
    source = security!("Synthetic Identity Fund")
    delivery!(ctx.portfolio, depot, target, "10", ~D[2025-01-02])
    delivery!(ctx.portfolio, depot, source, "4", ~D[2025-01-03])
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    MisplannedWrite.install!("security_id", "quantity")
    before = fingerprint()

    assert {:error, {:identity_check_failed, failure}} =
             Lifecycle.merge_security(agent(), source.id, target.id, consent(preview))

    assert Map.take(failure, [:date, :securities_account_id, :security_id]) ==
             %{date: ~D[2025-01-03], securities_account_id: depot.id, security_id: target.id}

    assert {n(failure.expected), n(failure.actual)} == {dec("14"), dec("15")}
    assert fingerprint() == before
  end

  # --- world ----------------------------------------------------------------------

  defp consent(preview), do: %{plan_digest: preview.plan_digest, collapse_key_equal: false}

  defp cash!(portfolio, name) do
    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: "EUR"
      })

    cash
  end

  defp depot!(portfolio, cash, name) do
    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: name
      })

    depot
  end

  defp security!(name) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{name: name, currency_code: "EUR"})

    security
  end

  defp deposit!(portfolio, cash, amount, date) do
    {:ok, tx} =
      Ledger.create_transaction(agent(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        type: "deposit",
        date: date,
        gross_amount: amount,
        currency_code: "EUR"
      })

    tx
  end

  defp delivery!(portfolio, depot, security, quantity, date) do
    {:ok, tx} =
      Ledger.create_transaction(agent(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        security_id: security.id,
        type: "inbound_delivery",
        date: date,
        quantity: quantity,
        currency_code: "EUR"
      })

    tx
  end

  # Every table's content, hashed: a rolled-back merge leaves each as it was.
  defp fingerprint do
    %{rows: tables} =
      Repo.query!("""
      SELECT tablename FROM pg_tables
      WHERE schemaname = 'public' AND tablename <> 'schema_migrations'
      ORDER BY tablename
      """)

    Map.new(tables, fn [table] ->
      %{rows: [[digest]]} =
        Repo.query!(
          "SELECT md5(coalesce(string_agg(t::text, '|' ORDER BY t::text), '')) " <>
            ~s(FROM "#{table}" t)
        )

      {table, digest}
    end)
  end

  defp dec(value), do: value |> Decimal.new() |> Decimal.normalize()
  defp n(%Decimal{} = value), do: Decimal.normalize(value)
end
