defmodule PortfolixirWeb.SecuritiesSplitBasisTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Repo

  defp insert_quote!(security, date, close, source) do
    {:ok, _} =
      %SecurityQuote{}
      |> SecurityQuote.changeset(%{
        security_id: security.id,
        date: date,
        close: Decimal.new(close),
        source: source
      })
      |> Repo.insert()
  end

  defp world_with_split do
    world = base_world(name: "Web World", cash_name: "Web Cash", depot_name: "Web Depot")
    security = create_security!(name: "Web Co", ticker: "WEB", asset_class: "equity")
    today = Date.utc_today()
    buy!(world, security, quantity: "10", price: "100", date: Date.add(today, -40))

    insert_quote!(security, Date.add(today, -20), "110", "manual")
    insert_quote!(security, Date.add(today, -5), "11", "manual")

    {:ok, _} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: Date.add(today, -10),
        ratio_numerator: 10,
        ratio_denominator: 1
      })

    {world, security}
  end

  # User story (ADR-0028 §2, UX-DR10/11, issue #590):
  # As a local portfolio maintainer viewing a security's chart after a split,
  # I want the chart to render the split-adjusted series with the basis
  # stated,
  # so that the price history is continuous and I know which basis I look at.
  test "the detail chart renders the split-adjusted series and states the basis", %{conn: conn} do
    {_world, security} = world_with_split()

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=chart")

    html = render(view)

    # The basis is stated next to the chart (UX-DR11).
    assert has_element?(view, "[data-role='chart-basis']")
    assert html =~ "split-adjusted"

    # The crosshair payload carries the adjusted closes: the raw pre-split
    # 110 is displayed as 11 — no phantom 10x cliff in the series.
    payload =
      view
      |> element("script[data-chart-payload]")
      |> render()

    assert payload =~ "11"
    refute payload =~ "110.000000"
  end

  # User story (ADR-0028 §2, UX-DR10/11, issue #590):
  # As a user of the chart-as-table (Quotes tab),
  # I want each row to show the displayed (adjusted) close with the stored
  # value still reachable and the basis stated,
  # so that the table matches the chart while the auditable input stays
  # visible.
  test "the quotes tab states the basis and keeps stored values reachable", %{conn: conn} do
    {_world, security} = world_with_split()

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=quotes")

    assert has_element?(view, "#detail-tab-panel-quotes [data-role='quotes-basis']")
    html = view |> element("#detail-tab-panel-quotes") |> render()
    assert html =~ "split-adjusted"

    # Displayed close 11.00 (adjusted) with the stored 110.00 still shown.
    assert html =~ "11.00"
    assert html =~ "110.00"
  end

  # User story (ADR-0028 §2 escape hatch, issue #590):
  # As a maintainer of a security whose provider never back-adjusts,
  # I want a "treat synced quotes as raw" toggle on the security's overview,
  # so that I can force the raw basis for its synced rows.
  test "the overview form toggles treat_quotes_as_raw", %{conn: conn} do
    {_world, security} = world_with_split()

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=overview")

    assert has_element?(view, "input[name='security[treat_quotes_as_raw]'][type='checkbox']")

    view
    |> form("#overview-details-form", %{
      "security" => %{"name" => security.name, "treat_quotes_as_raw" => "true"}
    })
    |> render_submit()

    assert Catalog.get_security(security.id).treat_quotes_as_raw

    view
    |> form("#overview-details-form", %{
      "security" => %{"name" => security.name, "treat_quotes_as_raw" => "false"}
    })
    |> render_submit()

    refute Catalog.get_security(security.id).treat_quotes_as_raw
  end
end
