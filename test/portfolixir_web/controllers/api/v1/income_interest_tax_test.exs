defmodule PortfolixirWeb.Api.V1.IncomeInterestTaxTest do
  # #1309, D-5 (Sprint 22 plan): Income reads the withheld tax on an interest
  # row as it does on a dividend. The ledger stores an interest booking's
  # net cash in gross_amount and its withheld tax in taxes, exactly as it
  # stores a dividend's; the report used to drop the tax for interest, so
  # its gross, tax and net disagreed with what the ledger holds. Nothing
  # stored changes: the same rows now read gross = net + tax, coupons (an
  # interest booking naming its bond, #928) included. Synthetic data only.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Income
  alias Portfolixir.WorldFixtures

  defp dec(value), do: Decimal.new(value)

  defp assert_dec(actual, expected, label) do
    assert %Decimal{} = actual, "#{label}: expected a Decimal, got #{inspect(actual)}"
    assert Decimal.equal?(actual, dec(expected)), "#{label}: expected #{expected}, got #{actual}"
  end

  # The API carries financial decimals as strings (ADR-0003); each is
  # compared as a Decimal, whatever scale the column stores.
  defp assert_api_row(row, {gross, tax, net}, label) do
    for {key, expected} <- [{"gross", gross}, {"tax", tax}, {"net", net}] do
      assert is_binary(row[key]), "#{label} #{key}: expected a decimal string"
      assert_dec(dec(row[key]), expected, "#{label} #{key}")
    end
  end

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp book!(world, attrs) do
    {:ok, tx} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        Map.merge(
          %{
            portfolio_id: world.portfolio.id,
            cash_account_id: world.cash.id,
            currency_code: world.cash.currency_code
          },
          attrs
        )
      )

    tx
  end

  # One EUR year booked alike: a dividend and an account interest row with
  # the same net 73.62 and tax 26.38, a coupon naming its bond (net 36.81,
  # tax 13.19) and an untaxed account interest row (15.00).
  defp eur_world do
    world = WorldFixtures.base_world(name: "Synthetic Interest Book", currency: "EUR")
    payer = WorldFixtures.create_security!(name: "Synthetic Payer", ticker: "SYP")

    bond =
      WorldFixtures.create_security!(
        name: "Synthetic Bond 2030",
        ticker: "SYB",
        asset_class: "bond"
      )

    book!(world, %{
      type: "dividend",
      security_id: payer.id,
      date: ~D[2025-03-14],
      gross_amount: "73.62",
      taxes: "26.38"
    })

    book!(world, %{type: "interest", date: ~D[2025-06-30], gross_amount: "73.62", taxes: "26.38"})

    book!(world, %{
      type: "interest",
      security_id: bond.id,
      date: ~D[2025-09-15],
      gross_amount: "36.81",
      taxes: "13.19"
    })

    book!(world, %{type: "interest", date: ~D[2025-12-31], gross_amount: "15.00"})

    Map.merge(world, %{payer: payer, bond: bond})
  end

  # User story:
  # As the operator or the agent reading the income report,
  # I want the withheld tax on an interest booking read as it is on a
  # dividend (gross = net + tax), a bond's coupon included,
  # so that the report's gross, tax and net agree with what the ledger holds.
  #
  # Acceptance criteria:
  # - A taxed interest row reads gross = net + tax, tax = the stored taxes,
  #   net = the cash credited; a coupon naming its bond likewise.
  # - A dividend reads as before; an untaxed interest row reads gross = net.
  # - The year's interest total and the per-position tax totals include the
  #   taxed interest; the API returns the same figures as Decimal strings.
  # - The computation basis no longer says interest carries no withholding.
  test "a taxed interest row and a taxed coupon read gross = net + tax, as a dividend does" do
    world = eur_world()
    report = Income.for_portfolio(world.portfolio.id)

    by_date = Map.new(report.transactions, &{&1.date, &1})

    dividend = by_date[~D[2025-03-14]]
    assert_dec(dividend.gross, "100.00", "dividend gross")
    assert_dec(dividend.tax, "26.38", "dividend tax")
    assert_dec(dividend.net, "73.62", "dividend net")

    interest = by_date[~D[2025-06-30]]
    assert interest.kind == "interest"
    assert_dec(interest.gross, "100.00", "interest gross")
    assert_dec(interest.tax, "26.38", "interest tax")
    assert_dec(interest.net, "73.62", "interest net")
    assert_dec(interest.native_gross, "100.00", "interest native gross")
    assert_dec(interest.native_tax, "26.38", "interest native tax")
    assert_dec(interest.native_net, "73.62", "interest native net")

    coupon = by_date[~D[2025-09-15]]
    assert coupon.security_id == world.bond.id
    assert_dec(coupon.gross, "50.00", "coupon gross")
    assert_dec(coupon.tax, "13.19", "coupon tax")
    assert_dec(coupon.net, "36.81", "coupon net")

    untaxed = by_date[~D[2025-12-31]]
    assert_dec(untaxed.gross, "15.00", "untaxed interest gross")
    assert_dec(untaxed.tax, "0", "untaxed interest tax")
    assert_dec(untaxed.net, "15.00", "untaxed interest net")

    [year] = report.annual
    assert year.year == 2025
    assert_dec(year.dividends_total, "100.00", "dividends total")
    # 100.00 + 50.00 + 15.00
    assert_dec(year.interest_total, "165.00", "interest total")
    assert_dec(year.total, "265.00", "year total")
    assert_dec(year.months[6].interest, "100.00", "June interest")
    assert_dec(year.months[9].interest, "50.00", "September interest")

    positions = Map.new(report.positions, &{&1.security_id, &1})

    account_interest = positions[nil]
    assert_dec(account_interest.gross, "115.00", "account interest gross")
    assert_dec(account_interest.tax, "26.38", "account interest tax")
    assert_dec(account_interest.net, "88.62", "account interest net")
    assert account_interest.payment_count == 2

    bond_row = positions[world.bond.id]
    assert_dec(bond_row.gross, "50.00", "bond gross")
    assert_dec(bond_row.tax, "13.19", "bond tax")
    assert_dec(bond_row.net, "36.81", "bond net")

    payer_row = positions[world.payer.id]
    assert_dec(payer_row.gross, "100.00", "payer gross")
    assert_dec(payer_row.tax, "26.38", "payer tax")
    assert_dec(payer_row.net, "73.62", "payer net")

    tax_total = Enum.reduce(report.positions, dec("0"), &Decimal.add(&2, &1.tax))
    assert_dec(tax_total, "65.95", "tax total over positions")

    refute report.computation_basis.series =~ "no withholding"
    assert report.computation_basis.series =~ "interest"
  end

  test "the income API reads the taxed interest and coupon rows the same way", %{conn: conn} do
    world = eur_world()

    body =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/income")
      |> json_response(200)

    data = body["data"]
    refute data["computation_basis"]["series"] =~ "no withholding"

    by_date = Map.new(data["transactions"], &{&1["date"], &1})

    assert_api_row(by_date["2025-06-30"], {"100.00", "26.38", "73.62"}, "API interest")
    assert_api_row(by_date["2025-09-15"], {"50.00", "13.19", "36.81"}, "API coupon")
    assert_api_row(by_date["2025-12-31"], {"15.00", "0", "15.00"}, "API untaxed interest")
    assert_api_row(by_date["2025-03-14"], {"100.00", "26.38", "73.62"}, "API dividend")

    [year] = data["annual"]
    assert_dec(dec(year["interest_total"]), "165.00", "API interest total")
    assert_dec(dec(year["total"]), "265.00", "API year total")

    account_interest = Enum.find(data["positions"], &is_nil(&1["security_id"]))
    assert_api_row(account_interest, {"115.00", "26.38", "88.62"}, "API account interest")
  end

  test "the Income page shows the taxed interest row's gross, tax and net", %{conn: conn} do
    eur_world()

    {:ok, view, _html} = live(conn, "/cashflow")

    row =
      view
      |> element("#income-positions tbody tr", "Interest")
      |> render()

    assert row =~ "115.00"
    assert row =~ "26.38"
    assert row =~ "88.62"

    bond_row =
      view
      |> element("#income-positions tbody tr", "Synthetic Bond 2030")
      |> render()

    assert bond_row =~ "50.00"
    assert bond_row =~ "13.19"
    assert bond_row =~ "36.81"
  end

  # User story:
  # As the operator of a portfolio whose interest is credited in another
  # currency,
  # I want a taxed interest row converted as a taxed dividend is, at its own
  # booking date's rate,
  # so that gross, tax and net stay consistent across the two kinds.
  #
  # Acceptance criteria:
  # - With EUR/USD 1.25 in April and 1.60 in October, a USD dividend of net
  #   100 and tax 25 reads 100 / 20 / 80 EUR, and a USD interest row of net
  #   64 and tax 16 reads 50 / 10 / 40 EUR, each at its own date's rate.
  test "a foreign-currency taxed interest row converts at its own date's rate, as a dividend does" do
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2025-04-01],
          rate: "1.25",
          source: "manual"
        },
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2025-10-01],
          rate: "1.60",
          source: "manual"
        }
      ])

    world = WorldFixtures.base_world(currency: "EUR", cash_currency: "USD")

    payer =
      WorldFixtures.create_security!(name: "Synthetic US Payer", ticker: "SUP", currency: "USD")

    book!(world, %{
      type: "dividend",
      security_id: payer.id,
      date: ~D[2025-04-15],
      gross_amount: "100",
      taxes: "25"
    })

    book!(world, %{type: "interest", date: ~D[2025-10-15], gross_amount: "64", taxes: "16"})

    report = Income.for_portfolio(world.portfolio.id)
    by_kind = Map.new(report.transactions, &{&1.kind, &1})

    dividend = by_kind["dividend"]
    assert dividend.currency == "USD"
    assert_dec(dividend.gross, "100", "USD dividend gross in EUR")
    assert_dec(dividend.tax, "20", "USD dividend tax in EUR")
    assert_dec(dividend.net, "80", "USD dividend net in EUR")

    interest = by_kind["interest"]
    assert interest.currency == "USD"
    assert_dec(interest.native_gross, "80", "USD interest native gross")
    assert_dec(interest.native_tax, "16", "USD interest native tax")
    assert_dec(interest.gross, "50", "USD interest gross in EUR")
    assert_dec(interest.tax, "10", "USD interest tax in EUR")
    assert_dec(interest.net, "40", "USD interest net in EUR")

    [year] = report.annual
    assert_dec(year.dividends_total, "100", "EUR dividends total")
    assert_dec(year.interest_total, "50", "EUR interest total")
    assert_dec(year.total, "150", "EUR year total")

    account_interest = Enum.find(report.positions, &is_nil(&1.security_id))
    assert_dec(account_interest.tax, "10", "EUR account interest tax")
  end
end
