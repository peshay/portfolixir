defmodule PortfolixirWeb.Api.V1.IncomePaymentCurrencyTest do
  # #1274 and #1293 (Sprint 22 R9, board ux-design-2026-11-01-sprint22/02 ③):
  # Income's drilled-year and per-position tables printed a converted
  # payment's base-currency gross, tax and net beside a Currency column that
  # named the payment's own currency, so a USD dividend read "USD" beside
  # euros. Each table now prints the payment's own figures in the currency
  # its column names, and the converted net beside them in its own column;
  # "Per position" has one row per payment currency. A year whose payments
  # are all unconverted keeps its annual row, with zero totals and its
  # excluded count, so the page can drill into the payments its note counts.
  # Synthetic data only.
  use PortfolixirWeb.ConnCase, async: false

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

  # The API carries financial decimals as strings (ADR-0003).
  defp assert_api_dec(value, expected, label) do
    assert is_binary(value), "#{label}: expected a decimal string, got #{inspect(value)}"
    assert_dec(dec(value), expected, label)
  end

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp book!(portfolio, cash, attrs) do
    {:ok, tx} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        Map.merge(
          %{
            portfolio_id: portfolio.id,
            cash_account_id: cash.id,
            currency_code: cash.currency_code,
            taxes: "0"
          },
          attrs
        )
      )

    tx
  end

  # A EUR portfolio with a EUR and a USD cash account. EUR/USD is 1.25 from
  # 2025-04-01 and 1.10 from 2025-10-01; no rate is stored before, so 2024's
  # two USD payments have no rate path to EUR.
  #
  # 2025, one USD security:
  #   15.04. USD account, net 100.00 + tax 25.00 = 125.00 USD -> 100 / 20 / 80 EUR
  #   02.06. EUR account, net  30.00                         ->  30 /  0 / 30 EUR
  #   15.10. USD account, net  44.00 + tax 11.00 =  55.00 USD ->  50 / 10 / 40 EUR
  # 2024, unconverted:
  #   01.03. USD dividend of the same security, net 20.00
  #   30.09. USD account interest naming no security, net 5.00
  setup do
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
          rate: "1.10",
          source: "manual"
        }
      ])

    world = WorldFixtures.base_world(name: "Synthetic Dollar Book", currency: "EUR")

    usd =
      WorldFixtures.add_depot(world.portfolio,
        cash_currency: "USD",
        cash_name: "Synthetic USD Cash",
        depot_name: "Synthetic USD Depot"
      )

    payer =
      WorldFixtures.create_security!(
        name: "Synthetic Dollar Payer",
        ticker: "SDP",
        currency: "USD"
      )

    dividend = %{type: "dividend", security_id: payer.id}

    book!(
      world.portfolio,
      usd.cash,
      Map.merge(dividend, %{date: ~D[2025-04-15], gross_amount: "100.00", taxes: "25.00"})
    )

    book!(
      world.portfolio,
      world.cash,
      Map.merge(dividend, %{date: ~D[2025-06-02], gross_amount: "30.00"})
    )

    book!(
      world.portfolio,
      usd.cash,
      Map.merge(dividend, %{date: ~D[2025-10-15], gross_amount: "44.00", taxes: "11.00"})
    )

    book!(
      world.portfolio,
      usd.cash,
      Map.merge(dividend, %{date: ~D[2024-03-01], gross_amount: "20.00"})
    )

    book!(world.portfolio, usd.cash, %{
      type: "interest",
      date: ~D[2024-09-30],
      gross_amount: "5.00"
    })

    %{portfolio: world.portfolio, payer: payer}
  end

  # User story (#1274, #1293):
  # As the operator or the agent reading the income report,
  # I want each per-position row in one payment currency, with its own
  # gross, tax and net in that currency and the converted figures beside,
  # and a year whose payments are all unconverted kept as a year,
  # so that a figure never stands under a currency it is not in, and every
  # payment the excluded note counts has a year to be found in.
  #
  # Acceptance criteria:
  # - The USD security paid into a USD and a EUR account has two position
  #   rows: USD 180.00 / 36.00 / 144.00 native and 150 / 30 / 120 EUR
  #   (two dates, two rates), and EUR 30.00 / 0 / 30.00 both ways.
  # - 2024 is an annual row with zero totals and excluded_count 2; 2025's
  #   excluded_count is 0.
  # - excluded names USD with its security and its one interest payment.
  test "the report: one position row per payment currency, and a year of unconverted payments",
       %{portfolio: portfolio, payer: payer} do
    report = Income.for_portfolio(portfolio.id)

    assert [usd_row, eur_row] = report.positions

    assert usd_row.security_id == payer.id
    assert usd_row.currency == "USD"
    assert usd_row.security_currency == "USD"
    assert_dec(usd_row.native_gross, "180.00", "USD row native gross")
    assert_dec(usd_row.native_tax, "36.00", "USD row native tax")
    assert_dec(usd_row.native_net, "144.00", "USD row native net")
    assert_dec(usd_row.gross, "150", "USD row base gross")
    assert_dec(usd_row.tax, "30", "USD row base tax")
    assert_dec(usd_row.net, "120", "USD row base net")
    assert usd_row.payment_count == 2
    assert usd_row.last_payment == ~D[2025-10-15]

    assert eur_row.security_id == payer.id
    assert eur_row.currency == "EUR"
    assert eur_row.security_currency == "USD"
    assert_dec(eur_row.native_gross, "30.00", "EUR row native gross")
    assert_dec(eur_row.native_tax, "0", "EUR row native tax")
    assert_dec(eur_row.native_net, "30.00", "EUR row native net")
    assert_dec(eur_row.net, "30.00", "EUR row base net")
    assert eur_row.payment_count == 1

    assert [y2025, y2024] = report.annual
    assert y2025.year == 2025
    assert_dec(y2025.total, "180", "2025 total")
    assert y2025.excluded_count == 0

    assert y2024.year == 2024
    assert_dec(y2024.total, "0", "2024 total")
    assert_dec(y2024.dividends_total, "0", "2024 dividends")
    assert_dec(y2024.interest_total, "0", "2024 interest")
    assert_dec(y2024.months[3].dividends, "0", "2024 March")
    assert y2024.excluded_count == 2

    assert report.excluded == %{
             count: 2,
             currencies: [
               %{
                 currency_code: "USD",
                 count: 2,
                 securities: ["Synthetic Dollar Payer"],
                 interest_count: 1
               }
             ]
           }
  end

  test "the API serves the per-currency position rows and the unconverted year", %{
    conn: conn,
    portfolio: portfolio
  } do
    data =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{portfolio.id}/income")
      |> json_response(200)
      |> Map.fetch!("data")

    assert [usd_row, eur_row] = data["positions"]
    assert usd_row["currency"] == "USD"
    assert usd_row["security_currency"] == "USD"
    assert_api_dec(usd_row["native_gross"], "180.00", "API USD native gross")
    assert_api_dec(usd_row["native_tax"], "36.00", "API USD native tax")
    assert_api_dec(usd_row["native_net"], "144.00", "API USD native net")
    assert_api_dec(usd_row["net"], "120", "API USD base net")
    assert eur_row["currency"] == "EUR"
    assert_api_dec(eur_row["native_net"], "30.00", "API EUR native net")

    assert [%{"year" => 2025, "excluded_count" => 0}, y2024] = data["annual"]
    assert y2024["year"] == 2024
    assert y2024["excluded_count"] == 2
    assert_api_dec(y2024["total"], "0", "API 2024 total")

    assert [%{"currency_code" => "USD", "interest_count" => 1}] = data["excluded"]["currencies"]
    assert data["computation_basis"]["gaps"] =~ "keeps its annual row"
  end

  # User story (#1274, board 02 ③):
  # As the operator reading a drilled year's payments for tax,
  # I want Gross, Tax and Net in the currency the Currency column names and
  # the converted net in a column of its own,
  # so that 25.00 withheld reads as 25.00 USD and never as euros labelled
  # USD.
  #
  # Acceptance criteria:
  # - 2025's 15.04. row reads 125.00 / 25.00 / 100.00, USD, and 80.00 under
  #   "Net (EUR)"; the purpose line says the net is also in EUR.
  # - "Per position" reads the USD row 180.00 / 36.00 / 144.00, USD, 120.00
  #   and the EUR row 30.00 / 0.00 / 30.00, EUR, 30.00.
  test "the page: native figures under their currency, the converted net beside them", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/cashflow")
    render_click(view, "select_year", %{"year" => "2025"})

    assert has_element?(view, "#income-detail thead th", "Net (EUR)")

    assert has_element?(
             view,
             "#income-detail [data-role='disclosure-purpose']",
             "Every payment of the year with gross, tax and net in its currency, the net also in EUR."
           )

    april = row_cells(view, "#income-detail tbody tr", "2025-04-15")
    assert Enum.drop(april, 3) == ["125.00", "25.00", "100.00", "USD", "80.00"]

    assert has_element?(view, "#income-positions thead th", "Net (EUR)")

    assert [usd_row, eur_row] = rows_cells(view, "#income-positions tbody tr")

    assert usd_row ==
             ["Synthetic Dollar Payer", "USD", "180.00", "36.00", "144.00", "120.00", "2"] ++
               ["2025-10-15"]

    assert eur_row ==
             ["Synthetic Dollar Payer", "EUR", "30.00", "0.00", "30.00", "30.00", "1"] ++
               ["2025-06-02"]
  end

  # User story (#1293):
  # As the operator whose 2024 payments have no stored rate,
  # I want 2024 kept as a year I can drill into, its payments listed in
  # their own currency with no converted figure,
  # so that the note's count points at rows I can see.
  #
  # Acceptance criteria:
  # - 2024 has a year button; drilling it lists the 20.00 USD dividend and
  #   the 5.00 USD interest, each "—" with "not convertible" under
  #   "Net (EUR)".
  # - The excluded note names "USD (Synthetic Dollar Payer, Interest)".
  test "the page: a year of unconverted payments keeps its row and drills", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/cashflow")

    assert has_element?(view, "#income-chart .income-bar-label[data-year='2024']")

    # Two payments take ngettext's plural, "currencies", for one currency.
    assert has_element?(
             view,
             "#income-excluded",
             "Affected currencies: USD (Synthetic Dollar Payer, Interest)."
           )

    render_click(view, "select_year", %{"year" => "2024"})

    dividend = row_cells(view, "#income-detail tbody tr", "2024-03-01")

    assert Enum.slice(dividend, 2..6) == [
             "Synthetic Dollar Payer",
             "20.00",
             "0.00",
             "20.00",
             "USD"
           ]

    assert List.last(dividend) =~ "—"
    assert List.last(dividend) =~ "not convertible"

    interest = row_cells(view, "#income-detail tbody tr", "2024-09-30")
    assert Enum.slice(interest, 2..6) == ["Interest", "5.00", "0.00", "5.00", "USD"]
    assert List.last(interest) =~ "not convertible"
  end

  defp row_cells(view, selector, text) do
    view
    |> element(selector, text)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("td")
    |> Enum.map(&cell_text/1)
  end

  defp rows_cells(view, selector) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(selector)
    |> Enum.map(fn row -> row |> Floki.find("td") |> Enum.map(&cell_text/1) end)
  end

  defp cell_text(cell), do: cell |> Floki.text(sep: " ") |> String.split() |> Enum.join(" ")
end
