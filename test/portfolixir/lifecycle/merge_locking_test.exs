defmodule Portfolixir.Lifecycle.MergeLockingTest do
  # ADR-0050 §10, "every race ends in a clean 409, never a 500", for the
  # locks a merge takes (the L3–L5 review round, finding R-L-4; risk-tier,
  # ADR-0036). The importer takes its portfolio's account-identity lock
  # before any row lock, and every row it inserts takes a key-share lock on
  # its security, in file order; the position-override writers lock the
  # depot before the security. A security merge that locked the two
  # securities first could close a cycle with either, which PostgreSQL
  # breaks by aborting one side with deadlock_detected. So the security merge
  # now takes the account-identity lock of every portfolio first — the lock
  # every importer and every cash or depot merge takes first — then the ISIN
  # lock, the depots, the securities; and every merge answers a lock cycle it
  # still loses with a fresh preview (plan_changed), never an exception.
  #
  # A real cycle needs two connections, which the SQL sandbox serializes, so
  # the first test reads the locks the merge holds (an advisory transaction
  # lock stays held until the test's own transaction ends), and the second
  # raises the database's own deadlock error inside a merge transaction.
  #
  # Every name and amount is synthetic.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.AccountNames
  alias Portfolixir.Lifecycle.MergeFlow
  alias Portfolixir.Portfolios

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  # User story:
  # As the operator who starts an import while an agent merges two
  # securities,
  # I want the two to wait for each other in one order,
  # so that neither fails with a database error half-way.
  #
  # Acceptance criteria:
  # - After a security merge, the transaction holds the account-identity
  #   lock of a portfolio none of whose accounts the test touched: the merge
  #   took it for every portfolio, as the importer's first lock.
  test "a security merge takes the account-identity lock of every portfolio first" do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Lock World",
        base_currency_code: "EUR"
      })

    {:ok, elsewhere} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Lock World (untouched)",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Broker cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot 1"
      })

    target = security!("Synthetic Lock Fund")
    source = security!("Synthetic Lock Fund")
    buy!(portfolio, depot, cash, target, ~D[2025-01-05])
    buy!(portfolio, depot, cash, source, ~D[2025-01-10])

    refute identity_lock_held?(elsewhere.id)

    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    assert {:ok, _record, :applied} =
             Lifecycle.merge_security(agent(), source.id, target.id, %{
               plan_digest: preview.plan_digest,
               collapse_key_equal: false
             })

    assert identity_lock_held?(elsewhere.id)
  end

  # User story:
  # As the agent whose merge lost a lock cycle to a concurrent import,
  # I want a clean answer I can act on,
  # so that I show the operator a fresh preview instead of a server error.
  #
  # Acceptance criteria:
  # - A merge transaction the database aborts with deadlock_detected answers
  #   {:error, :raced} (which each merge turns into plan_changed with a
  #   fresh preview), and writes nothing.
  # - Any other database error still raises.
  test "a lock cycle the merge loses answers raced, anything else raises" do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Cycle World",
        base_currency_code: "EUR"
      })

    assert {:error, :raced} =
             MergeFlow.transaction(fn ->
               {:ok, _} =
                 Portfolios.create_cash_account(Actor.owner_ui(), %{
                   portfolio_id: portfolio.id,
                   name: "Written before the cycle",
                   currency_code: "EUR"
                 })

               Repo.query!(
                 "DO $$ BEGIN RAISE EXCEPTION 'synthetic lock cycle' USING ERRCODE = '40P01'; END $$"
               )
             end)

    assert Portfolios.list_cash_accounts() |> Enum.filter(&(&1.portfolio_id == portfolio.id)) ==
             []

    assert_raise Postgrex.Error, fn ->
      MergeFlow.transaction(fn ->
        Repo.query!(
          "DO $$ BEGIN RAISE EXCEPTION 'another failure' USING ERRCODE = '22012'; END $$"
        )
      end)
    end
  end

  # --- world ------------------------------------------------------------------

  defp identity_lock_held?(portfolio_id) do
    %{rows: [[held]]} =
      Repo.query!(
        """
        SELECT count(*) > 0 FROM pg_locks
        WHERE locktype = 'advisory' AND pid = pg_backend_pid() AND granted
          AND classid::bigint = $1 AND objid::bigint = $2 AND objsubid = 2
        """,
        [AccountNames.lock_key(), AccountNames.lock_portfolio_key(portfolio_id)]
      )

    held
  end

  defp security!(name) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{name: name, currency_code: "EUR"})

    security
  end

  defp buy!(portfolio, depot, cash, security, date) do
    {:ok, tx} =
      Ledger.create_transaction(agent(), %{
        portfolio_id: portfolio.id,
        type: "buy",
        date: date,
        security_id: security.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        quantity: "1",
        price: "10.00",
        currency_code: "EUR"
      })

    tx
  end
end
