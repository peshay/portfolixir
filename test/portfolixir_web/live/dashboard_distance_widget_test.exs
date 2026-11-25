defmodule PortfolixirWeb.DashboardDistanceWidgetTest do
  # Sprint 32 S5 (I61; boards ux-design-2026-11-25-sprint32/03 ①, 05): the
  # widget „Abstand zum Hoch“, every figure it draws, in its wide form and
  # its compact form, compared with GET /api/v1/securities/:id/metrics for
  # the same security and day, and its order with the distances that route
  # answers. Synthetic data only.
  #
  # group: :dashboards -- a create takes the count lock (LockTable row 30).
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Dashboards
  alias PortfolixirWeb.Format

  defp api(path) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp percent(nil), do: "—"
  defp percent(value), do: Format.signed_percent(Decimal.new(value)) <> "%"

  # A year and more of closes for three held securities that stand at
  # different distances from their highs, and one with too few closes.
  defp seed do
    world = base_world()
    today = Clock.today()
    deposit!(world, "100000", Date.add(today, -420))

    for {name, closes} <- [
          {"Alpha Werke", ["100", "140", "120"]},
          {"Beta Linien", ["50", "55", "54"]},
          {"Gamma Netz", ["80", "120", "60"]}
        ] do
      security = create_security!(name: name)
      [first, high, last] = closes

      put_quotes!(security, [
        {Date.add(today, -400), first},
        {Date.add(today, -200), high},
        {Date.add(today, -100), first},
        {today, last}
      ])

      buy!(world, security, quantity: "10", price: first, date: Date.add(today, -390))
      security
    end
    |> then(fn securities ->
      short = create_security!(name: "Delta Kurz")
      put_quotes!(short, [{Date.add(today, -3), "10"}, {today, "11"}])
      buy!(world, short, quantity: "1", price: "10", date: Date.add(today, -3))
      securities ++ [short]
    end)
  end

  # User story:
  # As the operator who looks at how far each holding stands below its
  # high,
  # I want the widget to list them with the distance and the largest
  # drawdown the metrics read gives, the farthest below first,
  # so that I see the same figures an agent reads, and nothing said about
  # them.
  #
  # Acceptance criteria:
  # - L lists the held securities, the farthest below its 52-week high
  #   first, one with a refused distance last; each row's 52-week high,
  #   distance and 365-day largest drawdown equal the route's for that
  #   security today.
  # - The compact form draws the same securities with the same distance and
  #   drawdown.
  # - Its ⓘ states the computation basis: the 365-day window, latest ÷
  #   high − 1, own currency, a day without a close skipped.
  test "„Abstand zum Hoch“ draws the metrics read's figures, the farthest below first",
       %{conn: conn} do
    securities = seed()

    {:ok, _} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{
        "name" => "Hoch",
        "layout" => [%{"kind" => "distance_to_high", "size" => "L", "col" => 1, "row" => 1}]
      })

    {:ok, view, _html} = live(conn, "/")
    render_async(view)
    doc = view |> render() |> Floki.parse_document!()

    metrics =
      Map.new(securities, fn security ->
        {security.id, api("/api/v1/securities/#{security.id}/metrics")}
      end)

    expected_order =
      securities
      |> Enum.map(
        &{&1.id, metrics[&1.id]["metrics"]["distance_to_extremes"]["distance_to_high_pct"]}
      )
      |> Enum.sort_by(fn {_id, d} -> {is_nil(d), d && Decimal.to_float(Decimal.new(d))} end)
      |> Enum.map(fn {id, _d} -> to_string(id) end)

    rows = Floki.find(doc, "#dashboard-distance [data-form='wide'] [data-role='distance-row']")
    assert Enum.map(rows, &hd(Floki.attribute(&1, "data-security-id"))) == expected_order
    assert List.last(expected_order) == to_string(List.last(securities).id)

    for row <- rows do
      id = String.to_integer(hd(Floki.attribute(row, "data-security-id")))
      payload = metrics[id]
      extremes = payload["metrics"]["distance_to_extremes"]
      drawdown = payload["metrics"]["max_drawdown"]["365d"]

      assert text(Floki.find(row, "th")) == payload["security_name"]

      assert text(Floki.find(row, "[data-role='distance-value']")) ==
               percent(extremes["distance_to_high_pct"])

      assert text(Floki.find(row, "[data-role='distance-drawdown']")) ==
               percent(drawdown["value"])

      high = extremes["high"] && Format.money(Decimal.new(extremes["high"]["close"]))

      assert text(Floki.find(row, "[data-role='distance-high']")) ==
               if(high, do: high <> " " <> payload["currency_code"], else: "—")
    end

    compact =
      Floki.find(
        doc,
        "#dashboard-distance [data-form='compact'] [data-compact-role='distance-row']"
      )

    assert Enum.map(compact, &hd(Floki.attribute(&1, "data-security-id"))) == expected_order

    for row <- compact do
      id = String.to_integer(hd(Floki.attribute(row, "data-security-id")))
      extremes = metrics[id]["metrics"]["distance_to_extremes"]
      assert text(row) =~ percent(extremes["distance_to_high_pct"])
    end

    info = doc |> Floki.find("#dashboard-distance [data-role='section-info']") |> text()
    assert info =~ "365 days"
    assert info =~ "latest ÷ high − 1"
    assert info =~ "own currency"
  end
end
