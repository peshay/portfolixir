defmodule Portfolixir.Portfolios.IncomeTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Income
  alias Portfolixir.WorldFixtures

  # User story:
  # As a local portfolio maintainer,
  # I want a retrospective income report of the dividends and interest already
  # booked in my ledger, split by year and per position with gross, withheld
  # tax and net,
  # so that I can see what my holdings actually paid without leaving the app.
  #
  # Acceptance criteria:
  # - The annual matrix splits dividends and interest per month with a yearly
  #   total, all as Decimal amounts in the portfolio base currency.
  # - The per-position table reports security, gross, withheld tax, net, number
  #   of payments and the last payment date; gross = net + withheld tax.
  # - Foreign-currency income is converted via the EUR hub at the booking date's
  #   stored rate while the original currency stays visible.

  defp dividend!(%{portfolio: portfolio, cash: cash}, security, opts) do
    {:ok, tx} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        security_id: WorldFixtures.security_id_for(security),
        type: "dividend",
        date: Keyword.fetch!(opts, :date),
        gross_amount: Keyword.fetch!(opts, :net),
        taxes: Keyword.get(opts, :tax, "0"),
        currency_code: Keyword.get(opts, :currency, "EUR")
      })

    tx
  end

  defp interest!(%{portfolio: portfolio, cash: cash}, opts) do
    {:ok, tx} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        type: "interest",
        date: Keyword.fetch!(opts, :date),
        gross_amount: Keyword.fetch!(opts, :amount),
        currency_code: Keyword.get(opts, :currency, "EUR")
      })

    tx
  end

  test "aggregates dividends and interest into an annual matrix in the base currency" do
    world = WorldFixtures.base_world(currency: "EUR")
    security = WorldFixtures.create_security!(name: "Payer Inc", ticker: "PAY")

    dividend!(world, security, date: ~D[2025-03-15], net: "80", tax: "20")
    dividend!(world, security, date: ~D[2025-09-15], net: "90", tax: "10")
    interest!(world, date: ~D[2025-06-30], amount: "15")
    dividend!(world, security, date: ~D[2024-03-15], net: "40", tax: "0")

    income = Income.for_portfolio(world.portfolio.id)

    assert income.base_currency == "EUR"
    assert income.conversion_note =~ "EUR"

    years = Map.new(income.annual, &{&1.year, &1})

    y2025 = years[2025]
    # March + September dividends, gross of withheld tax: (80+20)+(90+10) = 200
    assert Decimal.equal?(y2025.dividends_total, Decimal.new("200"))
    assert Decimal.equal?(y2025.interest_total, Decimal.new("15"))
    assert Decimal.equal?(y2025.total, Decimal.new("215"))
    assert Decimal.equal?(y2025.months[3].dividends, Decimal.new("100"))
    assert Decimal.equal?(y2025.months[6].interest, Decimal.new("15"))
    assert Decimal.equal?(y2025.months[9].dividends, Decimal.new("100"))

    y2024 = years[2024]
    assert Decimal.equal?(y2024.dividends_total, Decimal.new("40"))
  end

  test "per-position table reports gross, withheld tax, net, count and last payment" do
    world = WorldFixtures.base_world(currency: "EUR")
    security = WorldFixtures.create_security!(name: "Payer Inc", ticker: "PAY")

    dividend!(world, security, date: ~D[2025-03-15], net: "80", tax: "20")
    dividend!(world, security, date: ~D[2025-09-15], net: "90", tax: "10")

    income = Income.for_portfolio(world.portfolio.id)

    row = Enum.find(income.positions, &(&1.security_id == security.id))
    assert row.security_name == "Payer Inc"
    assert Decimal.equal?(row.gross, Decimal.new("200"))
    assert Decimal.equal?(row.tax, Decimal.new("30"))
    assert Decimal.equal?(row.net, Decimal.new("170"))
    assert row.payment_count == 2
    assert row.last_payment == ~D[2025-09-15]
  end

  test "converts a foreign-currency dividend via the EUR hub at the booking date" do
    # 1 EUR = 1.25 USD on the booking date.
    {:ok, _} =
      Fx.upsert_many([
        %{base_currency: "EUR", quote_currency: "USD", date: ~D[2025-04-01], rate: "1.25"}
      ])

    world = WorldFixtures.base_world(currency: "EUR", cash_currency: "USD")
    security = WorldFixtures.create_security!(name: "US Payer", ticker: "USP", currency: "USD")

    # 100 USD net + 25 USD tax => 125 USD gross => /1.25 = 100 EUR gross.
    dividend!(world, security, date: ~D[2025-04-01], net: "100", tax: "25", currency: "USD")

    income = Income.for_portfolio(world.portfolio.id)

    row = Enum.find(income.positions, &(&1.security_id == security.id))
    assert row.security_currency == "USD"
    assert Decimal.equal?(row.gross, Decimal.new("100"))
    assert Decimal.equal?(row.tax, Decimal.new("20"))
    assert Decimal.equal?(row.net, Decimal.new("80"))

    years = Map.new(income.annual, &{&1.year, &1})
    assert Decimal.equal?(years[2025].dividends_total, Decimal.new("100"))
  end

  test "lists per-transaction detail for a year drilldown" do
    world = WorldFixtures.base_world(currency: "EUR")
    security = WorldFixtures.create_security!(name: "Payer Inc", ticker: "PAY")

    dividend!(world, security, date: ~D[2025-03-15], net: "80", tax: "20")
    interest!(world, date: ~D[2025-06-30], amount: "15")

    income = Income.for_portfolio(world.portfolio.id)

    detail = Enum.filter(income.transactions, &(&1.year == 2025))
    assert length(detail) == 2

    dividend_detail = Enum.find(detail, &(&1.kind == "dividend"))
    assert Decimal.equal?(dividend_detail.gross, Decimal.new("100"))
    assert Decimal.equal?(dividend_detail.tax, Decimal.new("20"))
    assert Decimal.equal?(dividend_detail.net, Decimal.new("80"))
    assert dividend_detail.security_name == "Payer Inc"

    interest_detail = Enum.find(detail, &(&1.kind == "interest"))
    assert Decimal.equal?(interest_detail.gross, Decimal.new("15"))
  end
end
