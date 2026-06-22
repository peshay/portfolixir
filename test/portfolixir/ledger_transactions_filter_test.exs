defmodule Portfolixir.LedgerTransactionsFilterTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  # User story:
  # As an API client (and the LLM I connect over MCP),
  # I want to list transactions scoped to one securities account,
  # so that a growing ledger does not force me to fetch every booking to read one
  # depot.
  #
  # Acceptance criteria:
  # - list_transactions/1 with securities_account_id returns only that depot's
  #   transactions.

  test "filters transactions by securities_account_id" do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Local Portfolio",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Local Cash",
        currency_code: "EUR"
      })

    {:ok, depot_one} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot One"
      })

    {:ok, depot_two} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot Two"
      })

    {:ok, security} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Sec",
        currency_code: "EUR",
        asset_class: "equity"
      })

    for depot <- [depot_one, depot_two, depot_one] do
      {:ok, _} =
        Ledger.create_transaction(%{
          portfolio_id: portfolio.id,
          securities_account_id: depot.id,
          cash_account_id: cash.id,
          security_id: security.id,
          type: "buy",
          date: ~D[2026-01-02],
          quantity: "1",
          price: "10",
          currency_code: "EUR"
        })
    end

    scoped = Ledger.list_transactions(securities_account_id: depot_one.id)

    assert length(scoped) == 2
    assert Enum.all?(scoped, &(&1.securities_account_id == depot_one.id))
  end
end
