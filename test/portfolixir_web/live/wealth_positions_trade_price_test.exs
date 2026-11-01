defmodule PortfolixirWeb.WealthPositionsTradePriceTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Valuation
  alias Portfolixir.WorldFixtures

  @columns ["depot", "security", "quantity", "latest_price", "market_value", "unrealized_pnl_abs"]

  setup do
    Classifications.ensure_builtins()

    world = WorldFixtures.base_world(name: "Figures World", depot_name: "Demo Depot")

    %{cash: dollars, depot: us_depot} =
      WorldFixtures.add_depot(world.portfolio,
        cash_name: "Dollar Cash",
        depot_name: "US Depot",
        currency: "USD"
      )

    us_world = %{world | cash: dollars, depot: us_depot}

    WorldFixtures.deposit!(world, "10000", ~D[2025-01-02])
    WorldFixtures.deposit!(us_world, "5000", ~D[2025-01-02], currency: "USD")

    # A quoted EUR position: 10 x 120.00 = 1,200.00 EUR.
    quoted = WorldFixtures.create_security!(name: "Quoted Equity AG", ticker: "QEA")
    WorldFixtures.buy!(world, quoted, quantity: "10", price: "100", date: ~D[2025-01-05])
    WorldFixtures.put_quote!(quoted, ~D[2025-06-30], "120.00")

    # A EUR position with no quote: 5 x its last trade price 19.20 = 96.00 EUR.
    helios = WorldFixtures.create_security!(name: "Helios Example SE", ticker: "HLX")
    WorldFixtures.buy!(world, helios, quantity: "4", price: "18.00", date: ~D[2025-01-10])
    WorldFixtures.buy!(world, helios, quantity: "1", price: "19.20", date: ~D[2025-03-14])

    # A USD position: 10 x 121.00 USD = 1,210.00 USD. The rate moved: 1 EUR
    # was 1.25 USD in January, 1.10 USD at the latest, so the position is
    # 1,100.00 EUR today (968.00 at the old rate).
    arbolia =
      WorldFixtures.create_security!(name: "Arbolia Example Inc", ticker: "ARB", currency: "USD")

    WorldFixtures.buy!(us_world, arbolia,
      quantity: "10",
      price: "110",
      date: ~D[2025-01-06],
      currency: "USD"
    )

    WorldFixtures.put_quote!(arbolia, ~D[2025-06-30], "121.00")

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2025-01-06],
          rate: "1.25",
          source: "manual"
        },
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2025-06-30],
          rate: "1.10",
          source: "manual"
        }
      ])

    # A position with no price at all: delivered in, never traded, no quote.
    dark = WorldFixtures.create_security!(name: "Placeholder Bond", ticker: "PLB")

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: dark.id,
        type: "inbound_delivery",
        date: ~D[2025-02-01],
        quantity: "5",
        currency_code: "EUR"
      })

    %{world: world, quoted: quoted, helios: helios, arbolia: arbolia, dark: dark}
  end

  defp row_cells(view, security) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(~s(#holdings-positions-table tbody tr[data-security-id="#{security.id}"] td))
    |> Map.new(fn td ->
      {td |> Floki.attribute("data-column") |> List.first(),
       td |> Floki.text() |> String.split() |> Enum.join(" ")}
    end)
  end

  # User story (#1332, and the D-9 finding that rides it; ADR-0010's
  # amendment of 2026-06-10; Sprint 22 plan D-1 and D-6, board 02 ①):
  # As a local portfolio maintainer,
  # I want Wealth's positions to show the price, value and gain of a
  # holding valued at its last trade price, with the source named, and the
  # market value in the currency the total is in,
  # so that the rows add up to the total shown above them, a USD row
  # included, whatever the rate did since the purchase.
  #
  # Acceptance criteria:
  # - A position with no quote reads its last own trade price with
  #   "Trade price · <date>", its market value and its P&L, never "—".
  # - The market value is the base-currency figure the total sums (the
  #   valuation's own), a USD row converted at the latest rate.
  # - A position with no price reads "no price · not in the total".
  # - The rows' market values sum to the valuation total, Decimal-exactly.
  test "every row is valued by the total's rule and the base column adds up to the total",
       %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)
    render_change(view, "set_holdings_columns", %{"columns" => @columns})

    helios = row_cells(view, ctx.helios)
    assert helios["latest_price"] == "19.20 EUR Trade price · 2025-03-14"
    assert helios["market_value"] == "96.00 EUR"
    assert helios["unrealized_pnl_abs"] == "+4.80 EUR"

    quoted = row_cells(view, ctx.quoted)
    assert quoted["latest_price"] == "120.00 EUR"
    assert quoted["market_value"] == "1,200.00 EUR"

    # The USD row's market value is in EUR at today's rate; its price and
    # P&L stay in the security's own currency, each with its suffix.
    arbolia = row_cells(view, ctx.arbolia)
    assert arbolia["latest_price"] == "121.00 USD"
    assert arbolia["market_value"] == "1,100.00 EUR"
    assert arbolia["unrealized_pnl_abs"] == "+110.00 USD"

    dark = row_cells(view, ctx.dark)
    assert dark["latest_price"] == "— no price · not in the total"
    assert dark["market_value"] == "—"

    # The identity (plan D-1): the rows add up to the total.
    valuation = Valuation.for_view(nil, base_currency: "EUR")
    assert Decimal.equal?(valuation.total_value, Decimal.new("2396.00"))

    rows_sum =
      [Decimal.new("96.00"), Decimal.new("1200.00"), Decimal.new("1100.00")]
      |> Enum.reduce(&Decimal.add/2)

    assert Decimal.equal?(rows_sum, valuation.total_value)

    basis = view |> element(~s([data-role="positions-basis"])) |> render()
    assert basis =~ "without a quote, at the last own trade price"
    assert basis =~ "Market value in EUR"
  end

  # The board's German words (02 ①): the source in the price cell, the row
  # with no price, and the separators of the base column.
  test "the rows read in German as the board draws them", %{conn: conn} = ctx do
    {:ok, view, _html} =
      conn
      |> PortfolixirWeb.PreferenceCookieHelpers.put_preference_cookie("portfolixir_locale", "de")
      |> live("/portfolio")

    render_async(view)
    render_change(view, "set_holdings_columns", %{"columns" => @columns})

    assert row_cells(view, ctx.helios)["latest_price"] == "19,20 EUR Handelspreis · 14.03.2025"
    assert row_cells(view, ctx.arbolia)["market_value"] == "1.100,00 EUR"
    assert row_cells(view, ctx.dark)["latest_price"] == "— kein Preis · nicht in der Summe"

    basis = view |> element(~s([data-role="positions-basis"])) |> render()
    assert basis =~ "oder, ohne Kurs, zum letzten eigenen Handelspreis"
  end
end
