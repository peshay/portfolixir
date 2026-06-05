defmodule Portfolixir.Portfolios.ValuationFxTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Valuation

  # User story:
  # As a maintainer with holdings in several currencies,
  # I want each position converted into my portfolio base currency before the
  # total and weights are computed,
  # so that a EUR portfolio holding a USD security is valued correctly instead
  # of summing raw closes.
  #
  # Acceptance criteria:
  # - A position's market value is its native value converted to the base currency.
  # - The total and weights are in the base currency.
  # - A position whose currency has no rate path to the base is unvalued.

  defp setup_world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "EUR Portfolio", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot"
      })

    %{portfolio: portfolio, cash: cash, depot: depot}
  end

  defp security!(name, ticker, currency) do
    {:ok, security} =
      Catalog.create_security(%{
        name: name,
        ticker_symbol: ticker,
        currency_code: currency,
        asset_class: "equity"
      })

    security
  end

  defp buy!(%{portfolio: p, depot: d, cash: c}, security, qty, price) do
    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: p.id,
        securities_account_id: d.id,
        cash_account_id: c.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-02],
        quantity: qty,
        price: price,
        fees: "0",
        taxes: "0",
        currency_code: currency_of(security)
      })
  end

  defp currency_of(security), do: security.currency_code

  test "values each position in the portfolio base currency" do
    world = setup_world()

    usd = security!("US Co.", "USCO", "USD")
    eur = security!("EU Co.", "EUCO", "EUR")
    jpy = security!("JP Co.", "JPCO", "JPY")

    buy!(world, usd, "10", "100")
    buy!(world, eur, "5", "100")
    buy!(world, jpy, "3", "1000")

    # 1 EUR = 1.25 USD, so 1 USD = 0.8 EUR. No JPY rate on purpose.
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-06-04],
          rate: "1.25",
          source: "manual"
        }
      ])

    valuation =
      Valuation.for_portfolio(world.portfolio.id,
        prices: %{
          usd.id => Decimal.new("100"),
          eur.id => Decimal.new("100"),
          jpy.id => Decimal.new("1000")
        }
      )

    assert valuation.base_currency == "EUR"

    by_security = Map.new(valuation.positions, &{&1.security_id, &1})

    usd_row = by_security[usd.id]
    assert usd_row.security_currency == "USD"
    assert usd_row.valued
    # 10 * 100 USD = 1000 USD -> 800 EUR
    assert Decimal.equal?(usd_row.market_value, Decimal.new("800"))

    eur_row = by_security[eur.id]
    assert Decimal.equal?(eur_row.market_value, Decimal.new("500"))

    jpy_row = by_security[jpy.id]
    refute jpy_row.valued
    assert is_nil(jpy_row.market_value)

    # Total is base-currency, valued positions only: 800 + 500 = 1300 EUR.
    assert Decimal.equal?(valuation.total_value, Decimal.new("1300"))
    assert valuation.unvalued_count == 1
  end
end
