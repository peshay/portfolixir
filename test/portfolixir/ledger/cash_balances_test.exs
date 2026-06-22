defmodule Portfolixir.Ledger.CashBalancesTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  # User story:
  # As a local portfolio maintainer (and the LLM working a depot),
  # I want each cash account's balance derived from the ledger,
  # so that I can reason about cash quote and floors without storing balances.

  defp setup_world do
    world = base_world(name: "Test Portfolio", cash_name: "Cash", depot_name: "Depot")
    security = create_security!(name: "Test Security", ticker: nil, asset_class: "equity")

    {:ok, cash_b} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "Cash 2",
        currency_code: "EUR"
      })

    Map.merge(world, %{security: security, cash_b: cash_b})
  end

  defp create!(w, attrs) do
    base = %{portfolio_id: w.portfolio.id, date: ~D[2026-04-01], currency_code: "EUR"}
    {:ok, _} = Ledger.create_transaction(Portfolixir.Actor.owner_ui(), Map.merge(base, attrs))
  end

  defp dec(value), do: Decimal.new(value)

  test "sums every cash-affecting kind with the direction implied by the type" do
    w = setup_world()

    create!(w, %{type: "deposit", cash_account_id: w.cash.id, gross_amount: dec("1000")})

    create!(w, %{
      type: "buy",
      security_id: w.security.id,
      securities_account_id: w.depot.id,
      cash_account_id: w.cash.id,
      quantity: dec("10"),
      price: dec("50"),
      fees: dec("5"),
      taxes: dec("2"),
      gross_amount: dec("507")
    })

    create!(w, %{
      type: "sell",
      security_id: w.security.id,
      securities_account_id: w.depot.id,
      cash_account_id: w.cash.id,
      quantity: dec("4"),
      price: dec("60"),
      fees: dec("3"),
      taxes: dec("1"),
      gross_amount: dec("236")
    })

    create!(w, %{
      type: "dividend",
      security_id: w.security.id,
      cash_account_id: w.cash.id,
      gross_amount: dec("30")
    })

    create!(w, %{type: "interest", cash_account_id: w.cash.id, gross_amount: dec("8")})
    create!(w, %{type: "fee", cash_account_id: w.cash.id, gross_amount: dec("4")})
    create!(w, %{type: "tax", cash_account_id: w.cash.id, gross_amount: dec("6")})
    create!(w, %{type: "tax_refund", cash_account_id: w.cash.id, gross_amount: dec("2")})
    create!(w, %{type: "removal", cash_account_id: w.cash.id, gross_amount: dec("100")})

    create!(w, %{
      type: "cash_transfer",
      cash_account_id: w.cash.id,
      counter_cash_account_id: w.cash_b.id,
      gross_amount: dec("50")
    })

    # A delivery moves shares only and must not touch cash.
    create!(w, %{
      type: "inbound_delivery",
      security_id: w.security.id,
      securities_account_id: w.depot.id,
      quantity: dec("3")
    })

    balances = Ledger.cash_balances(portfolio_id: w.portfolio.id)

    # 1000 - 507 + 236 + 30 + 8 - 4 - 6 + 2 - 100 - 50
    assert Decimal.equal?(Map.fetch!(balances, w.cash.id), dec("609"))
    assert Decimal.equal?(Map.fetch!(balances, w.cash_b.id), dec("50"))
  end

  test "reconstructs buy/sell cash from quantity*price when gross_amount is absent" do
    w = setup_world()

    create!(w, %{type: "deposit", cash_account_id: w.cash.id, gross_amount: dec("1000")})

    create!(w, %{
      type: "buy",
      security_id: w.security.id,
      securities_account_id: w.depot.id,
      cash_account_id: w.cash.id,
      quantity: dec("2"),
      price: dec("100"),
      fees: dec("1"),
      taxes: dec("1")
    })

    create!(w, %{
      type: "sell",
      security_id: w.security.id,
      securities_account_id: w.depot.id,
      cash_account_id: w.cash.id,
      quantity: dec("1"),
      price: dec("50"),
      fees: dec("1"),
      taxes: dec("1")
    })

    balances = Ledger.cash_balances(portfolio_id: w.portfolio.id)

    # 1000 - (2*100 + 1 + 1) + (1*50 - 1 - 1) = 1000 - 202 + 48
    assert Decimal.equal?(Map.fetch!(balances, w.cash.id), dec("846"))
  end
end
