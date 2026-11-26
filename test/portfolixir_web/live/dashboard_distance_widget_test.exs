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
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Clock
  alias Portfolixir.Dashboards
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Dashboard.Widgets.DistanceToHigh
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

  # A view that holds one depot of two: Overseas Depot's securities, two
  # at the same distance, two with too few closes and two more, so that
  # L shows five of six; Home Depot holds one the view does not.
  defp view_world do
    Classifications.ensure_builtins()
    today = Clock.today()
    home = base_world(name: "Home", cash_name: "Home Cash", depot_name: "Home Depot")

    overseas =
      base_world(name: "Overseas", cash_name: "Overseas Cash", depot_name: "Overseas Depot")

    for world <- [home, overseas], do: deposit!(world, "100000", Date.add(today, -420))

    hold = fn world, name, closes ->
      security = create_security!(name: name)
      put_quotes!(security, closes)
      {first_day, first} = hd(closes)
      buy!(world, security, quantity: "1", price: first, date: first_day)
      security
    end

    year = fn first, high, last ->
      [
        {Date.add(today, -400), first},
        {Date.add(today, -200), high},
        {Date.add(today, -100), first},
        {today, last}
      ]
    end

    short = [{Date.add(today, -3), "10"}, {today, "11"}]

    hold.(home, "Outside Home", year.("100", "200", "50"))

    # Made in an order the list's is not: a refused one first.
    held = [
      hold.(overseas, "Zulu Kurz", short),
      hold.(overseas, "Uniform Tie", year.("100", "125", "100")),
      hold.(overseas, "Bravo Tie", year.("100", "125", "100")),
      hold.(overseas, "Steep Fall", year.("100", "200", "60")),
      hold.(overseas, "Near High", year.("100", "110", "108")),
      hold.(overseas, "Kilo Kurz", short)
    ]

    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Overseas tag"})
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), overseas.depot, [bucket.id])
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Overseas", include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])

    %{view: view, held: held}
  end

  # User story:
  # As the operator whose dashboard reads one view,
  # I want „Abstand zum Hoch“ to list only what that view holds, equal
  # distances by name and the refused ones last by name, and to say how
  # many more the tile leaves out,
  # so that the list is the view's and reads the same each time.
  #
  # Acceptance criteria:
  # - On a dashboard scoped to the view, L lists five of the view's six
  #   securities and none of the other depot's: the farthest below its
  #   high first, two at one distance by name, two whose distance the
  #   route refuses (too few closes) last by name; each distance the one
  #   GET /api/v1/securities/:id/metrics answers.
  # - „1 weiteres in der Liste“ stands under it; the footer names the view.
  test "„Abstand zum Hoch“ reads the dashboard's view, ties by name, the refused last",
       %{conn: conn} do
    %{view: view, held: held} = view_world()

    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{
        "name" => "Übersee",
        "view_id" => view.id,
        "layout" => [%{"kind" => "distance_to_high", "size" => "L", "col" => 1, "row" => 1}]
      })

    {:ok, live_view, _html} = live(conn, "/dashboards/#{dashboard.id}?locale=de")
    render_async(live_view)
    doc = live_view |> render() |> Floki.parse_document!()

    by_name = Map.new(held, &{&1.name, &1})

    distance = fn name ->
      api("/api/v1/securities/#{by_name[name].id}/metrics")["metrics"]["distance_to_extremes"][
        "distance_to_high_pct"
      ]
    end

    order = ["Steep Fall", "Bravo Tie", "Uniform Tie", "Near High", "Kilo Kurz", "Zulu Kurz"]

    # The order the route's distances give: ascending, ties by name, the
    # refused last by name.
    assert distance.("Bravo Tie") == distance.("Uniform Tie")
    assert distance.("Kilo Kurz") == nil and distance.("Zulu Kurz") == nil

    assert Decimal.lt?(Decimal.new(distance.("Steep Fall")), Decimal.new(distance.("Bravo Tie")))
    assert Decimal.lt?(Decimal.new(distance.("Uniform Tie")), Decimal.new(distance.("Near High")))

    rows = Floki.find(doc, "#dashboard-distance [data-form='wide'] [data-role='distance-row']")
    assert Enum.map(rows, &text(Floki.find(&1, "th"))) == Enum.take(order, 5)

    for row <- rows do
      name = text(Floki.find(row, "th"))
      assert text(Floki.find(row, "[data-role='distance-value']")) == percent(distance.(name))
    end

    assert text(Floki.find(doc, "#dashboard-distance [data-role='distance-more']")) ==
             "1 weiteres in der Liste"

    refute text(Floki.find(doc, "#dashboard-distance")) =~ "Outside Home"
    assert text(Floki.find(doc, "#dashboard-distance [data-role='widget-scope']")) =~ "Overseas"
  end

  # User story:
  # As the operator whose view was deleted while the page read it, or
  # holds nothing today,
  # I want the widget to say which of the two it is,
  # so that an empty list never stands for a failed read.
  #
  # Acceptance criteria:
  # - The read of a view that no longer exists answers no rows but
  #   :no_view, drawn „Die Abstände konnten nicht geladen werden.“.
  # - A view that holds nothing answers no rows, drawn „Kein Wertpapier in
  #   dieser Ansicht im Bestand.“; neither draws a table.
  test "„Abstand zum Hoch“ tells a deleted view from an empty one" do
    {:ok, empty} = Buckets.create_view(Actor.owner_ui(), %{name: "Leer", include_all: false})
    {:ok, gone} = Buckets.create_view(Actor.owner_ui(), %{name: "Weg", include_all: false})
    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), gone)

    [item] =
      [%{"kind" => "distance_to_high", "size" => "L", "col" => 1, "row" => 1}]
      |> Widget.items(nil, [])

    draw = fn card ->
      Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
        render_component(&DistanceToHigh.widget/1, item: item, card: card)
      end)
      |> Floki.parse_document!()
    end

    assert DistanceToHigh.read(gone.id) == %{state: :no_view}
    failed = draw.(DistanceToHigh.read(gone.id))

    assert text(Floki.find(failed, "[data-role='distance-failed']")) ==
             "Die Abstände konnten nicht geladen werden."

    assert DistanceToHigh.read(empty.id) == %{state: :ok, rows: []}
    none = draw.(DistanceToHigh.read(empty.id))

    assert text(Floki.find(none, "[data-role='distance-empty']")) ==
             "Kein Wertpapier in dieser Ansicht im Bestand."

    for doc <- [failed, none], do: assert(Floki.find(doc, "[data-role='distance-table']") == [])
  end
end
