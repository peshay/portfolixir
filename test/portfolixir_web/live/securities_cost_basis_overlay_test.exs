defmodule PortfolixirWeb.SecuritiesCostBasisOverlayTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger.Splits

  @plot_top 16.0
  @plot_bottom 332.0

  defp book_split!(security, date, numerator, denominator) do
    {:ok, _} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: date,
        ratio_numerator: numerator,
        ratio_denominator: denominator
      })
  end

  defp cost_basis_ys(view) do
    html =
      view
      |> element("button[phx-click='toggle_detail_cost_basis']")
      |> render_click()

    assert [_, points] = Regex.run(~r/class="chart-cost-basis"[^>]*points="([^"]*)"/s, html),
           "cost-basis overlay polyline not rendered"

    points
    |> String.split(" ", trim: true)
    |> Enum.map(fn pair ->
      [_x, y] = String.split(pair, ",")
      String.to_float(y)
    end)
  end

  # User story (E17 closing-act review, finding 1b):
  # As a local portfolio maintainer inspecting the cost-basis overlay after
  # a split,
  # I want pre-split cost points transformed to the same display basis as
  # the price series,
  # so that a pre-split average of 100 with a later 10:1 split renders as 10
  # on the ~9-11 adjusted price scale instead of shooting off the chart.
  #
  # Acceptance criteria:
  # - Every overlay point of a constant display-basis cost of 10 renders at
  #   one and the same y coordinate.
  # - All overlay points lie inside the plot area (a raw 100 against the
  #   adjusted scale would land far outside).
  test "cost-basis overlay renders pre-split points in display basis", %{conn: conn} do
    world = base_world(name: "CB World", cash_name: "CB Cash", depot_name: "CB Depot")
    security = create_security!(name: "CB Co", ticker: "CBB", asset_class: "equity")
    today = Date.utc_today()

    put_quote!(security, Date.add(today, -45), "110")
    put_quote!(security, Date.add(today, -5), "9")
    buy!(world, security, quantity: "10", price: "100", date: Date.add(today, -40))
    book_split!(security, Date.add(today, -10), 10, 1)

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=chart")

    ys = cost_basis_ys(view)
    assert length(ys) >= 2

    [reference | rest] = ys

    for y <- ys do
      assert y >= @plot_top - 1.0 and y <= @plot_bottom + 1.0,
             "cost point rendered outside the plot at y=#{y} (raw-basis point on adjusted scale)"
    end

    for y <- rest do
      assert abs(y - reference) < 0.5,
             "cost overlay is not flat: y=#{y} vs #{reference} — pre-split point not rebased"
    end
  end

  # User story (E17 closing-act review, finding 1a):
  # As a maintainer whose split fanned out to several portfolios,
  # I want the overlay to apply the ratio once per security-level EVENT, not
  # once per fan-out row,
  # so that a 10:1 split held in two portfolios leaves the post-split
  # average at 10, not 1.
  #
  # Acceptance criteria:
  # - With two portfolios holding, the overlay stays one flat display-basis
  #   line (double application would drop the post-split points tenfold).
  test "cost-basis overlay applies a fanned-out split once per event", %{conn: conn} do
    world_a = base_world(name: "DA World", cash_name: "DA Cash", depot_name: "DA Depot")
    world_b = base_world(name: "DB World", cash_name: "DB Cash", depot_name: "DB Depot")
    security = create_security!(name: "DD Co", ticker: "DDD", asset_class: "equity")
    today = Date.utc_today()

    put_quote!(security, Date.add(today, -45), "110")
    put_quote!(security, Date.add(today, -5), "9")
    buy!(world_a, security, quantity: "10", price: "100", date: Date.add(today, -40))
    buy!(world_b, security, quantity: "10", price: "100", date: Date.add(today, -40))
    book_split!(security, Date.add(today, -10), 10, 1)

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=chart")

    ys = cost_basis_ys(view)
    assert length(ys) >= 3

    [reference | rest] = ys

    for y <- ys do
      assert y >= @plot_top - 1.0 and y <= @plot_bottom + 1.0,
             "cost point rendered outside the plot at y=#{y}"
    end

    for y <- rest do
      assert abs(y - reference) < 0.5,
             "cost overlay is not flat: y=#{y} vs #{reference} — split applied per fan-out row"
    end
  end

  # User story (E17 closing-act review, finding 7):
  # As a maintainer reading a security's transaction list,
  # I want a split row to show its ratio instead of dashes with a stray
  # currency code and zero fees/taxes,
  # so that the corporate action is recognisable at a glance.
  #
  # Acceptance criteria:
  # - The split row renders the ratio as "10:1".
  # - The split row shows no currency code and no 0.00 fee/tax clutter.
  test "the transactions tab renders a split row with its ratio, without money clutter", %{
    conn: conn
  } do
    world = base_world(name: "TxTab World", cash_name: "TT Cash", depot_name: "TT Depot")
    security = create_security!(name: "TxTab Co", ticker: "TTB", asset_class: "equity")
    today = Date.utc_today()

    buy!(world, security, quantity: "10", price: "100", date: Date.add(today, -40))
    book_split!(security, Date.add(today, -10), 10, 1)

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=transactions")

    row = view |> element("tr.tx-row--split") |> render()
    assert row =~ "10:1"
    refute row =~ "EUR"
    refute row =~ "0.00"

    # The trade rows keep their money columns untouched.
    buy_row = view |> element("tr.tx-row--buy") |> render()
    assert buy_row =~ "EUR"
    assert buy_row =~ "100.00"
  end

  # User story (E17 closing-act review, finding 11):
  # As a maintainer of a security without any booked split,
  # I want the chart/quotes basis hint to say the prices are shown as
  # recorded,
  # so that the UI never claims a split adjustment that cannot have
  # happened.
  #
  # Acceptance criteria:
  # - With zero split events the chart and quotes hints do not contain
  #   "split-adjusted" and use the as-recorded wording instead.
  test "the basis hint does not claim split-adjusted without split events", %{conn: conn} do
    world = base_world(name: "NoSplit World", cash_name: "NS Cash", depot_name: "NS Depot")
    security = create_security!(name: "NoSplit Co", ticker: "NSP", asset_class: "equity")
    today = Date.utc_today()

    put_quote!(security, Date.add(today, -10), "100")
    buy!(world, security, quantity: "1", price: "100", date: Date.add(today, -20))

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=chart")
    chart_hint = view |> element("[data-role='chart-basis']") |> render()
    refute chart_hint =~ "split-adjusted"
    assert chart_hint =~ "as recorded"

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=quotes")
    quotes_hint = view |> element("[data-role='quotes-basis']") |> render()
    refute quotes_hint =~ "split-adjusted"
    assert quotes_hint =~ "as recorded"
  end
end
