defmodule PortfolixirWeb.WealthHoldingsColumnsTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3]

  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Classifications

  # User story (#814; AGENTS.md → "API And MCP Coverage", the two-way rule and
  # its deadline):
  # As a local portfolio maintainer,
  # I want the holdings projection's valuation fields on the Wealth Holdings
  # positions table, behind a column picker,
  # so that the fields an agent reads over `fields=` are readable by me too —
  # the picker left with the Transactions holdings panel in #803 and the
  # projection has been agent-only since.
  #
  # Acceptance criteria:
  # - The Holdings tab carries a positions table over
  #   `Ledger.holdings_for_portfolio/1` — the API's own projection, so the
  #   columns are the figures the agent reads rather than a second
  #   calculation.
  # - A column picker offers the projection's fields; checking one shows that
  #   column, and an empty selection falls back to the defaults rather than
  #   rendering a table with no columns.

  setup do
    Classifications.ensure_builtins()
    world = base_world(name: "Columns World", cash_name: "CW Cash", depot_name: "CW Depot")
    security = create_security!(name: "Column Co", ticker: "COL", isin: "DE000COLUMN1")
    deposit!(world, "10000", ~D[2026-01-01])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])

    {:ok, _} =
      Quotes.upsert_many(security.id, [
        %{date: ~D[2026-01-06], close: Decimal.new("120"), source: "manual"}
      ])

    %{world: world, security: security}
  end

  test "the Holdings tab lists the positions of the API's own projection", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/portfolio")

    assert render_async(view) =~ "Column Co"
    assert has_element?(view, "#holdings-positions-table")

    # The defaults: depot, security, quantity.
    head = view |> element("#holdings-positions-table thead") |> render()
    assert head =~ "Depot"
    assert head =~ "Security"
    assert head =~ "Quantity"
    refute head =~ "ISIN"
  end

  test "the picker adds the projection's valuation fields", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    assert has_element?(view, "#holdings-column-picker")

    view
    |> form("#holdings-column-form", %{
      "columns" => ["security", "isin", "latest_price", "market_value", "unrealized_pnl_abs"]
    })
    |> render_change()

    head = view |> element("#holdings-positions-table thead") |> render()
    assert head =~ "ISIN"
    assert head =~ "Latest price"
    assert head =~ "Market value"

    body = view |> element("#holdings-positions-table tbody") |> render()
    assert body =~ "DE000COLUMN1"
    assert body =~ "120"
  end

  test "an empty selection falls back to the defaults", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    view |> form("#holdings-column-form", %{"columns" => [""]}) |> render_change()

    head = view |> element("#holdings-positions-table thead") |> render()
    assert head =~ "Security"
    assert head =~ "Quantity"
  end
end
