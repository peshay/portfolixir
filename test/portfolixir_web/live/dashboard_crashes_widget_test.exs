defmodule PortfolixirWeb.DashboardCrashesWidgetTest do
  # Sprint 31 D4 (FR-60; ADR-0062 §12; ADR-0058; plan D-1 exit criterion
  # 1; planning board ux-design-2026-11-21-sprint31/01 ①, idea board
  # ux-design-2026-11-21-idea-i56/03): the widget „Crashes im Vergleich“
  # on the template (M), every figure it draws compared with the crash
  # routes' answers for the same window and universe, „Im Depot“ and
  # „Katalog“. Every name and figure is synthetic.
  #
  # group: :crash_benchmark -- the modules that choose the crash benchmark
  # never run at the same time (risk_crashes_live_test.exs says why). It
  # reads the template, so it stores no dashboard.
  use PortfolixirWeb.ConnCase, async: true, group: :crash_benchmark

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Settings
  alias PortfolixirWeb.Format

  defp day(offset), do: Date.add(Portfolixir.Clock.today(), offset)

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
  # One percent format across the dashboard, as the other widgets write it
  # (Sprint 31 closing act, DS5).
  defp percent(value), do: Format.signed_percent(Decimal.new(value)) <> "%"

  # The index falls three times; one held security and one only in the
  # catalogue fall with it, by different amounts.
  defp crash_world! do
    world = base_world()
    index = create_security!(name: "Synthetic Crash Index", ticker: "SCI")

    put_quotes!(index, [
      {~D[2022-01-03], "120"},
      {~D[2022-10-12], "90"},
      {~D[2023-06-01], "125"},
      {day(-60), "130"},
      {day(-40), "110"},
      {day(-20), "131"},
      {day(-5), "115"},
      {day(-1), "118"}
    ])

    held = create_security!(name: "Synthetic Holding", ticker: "SHD")

    put_quotes!(held, [
      {~D[2022-01-03], "50"},
      {~D[2022-10-12], "35"},
      {day(-60), "60"},
      {day(-40), "51"},
      {day(-20), "58"},
      {day(-5), "50"}
    ])

    outsider = create_security!(name: "Synthetic Outsider", ticker: "SOU")

    put_quotes!(outsider, [
      {~D[2022-01-03], "10"},
      {~D[2022-10-12], "6"},
      {day(-60), "12"},
      {day(-40), "9"},
      {day(-20), "11"},
      {day(-5), "10"}
    ])

    deposit!(world, "10000", ~D[2021-05-04])
    buy!(world, held, quantity: "10", price: "45", date: ~D[2021-05-04])
    {:ok, _} = Settings.set_crash_benchmark(Actor.owner_ui(), index.id)
    Map.put(world, :index, index)
  end

  defp rows(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("#dashboard-crashes [data-form='wide'] [data-role='crash-window']")
  end

  defp assert_matches_route(rows, universe) do
    windows = api("/api/v1/crashes")
    keys = Enum.map(rows, &hd(Floki.attribute(&1, "data-key")))

    newest_first =
      (windows["detected"] ++ windows["manual"])
      |> Enum.sort_by(& &1["start"], :desc)
      |> Enum.map(& &1["key"])
      |> Enum.take(5)

    assert keys == newest_first

    for row <- rows do
      key = hd(Floki.attribute(row, "data-key"))

      ranking =
        api(
          "/api/v1/crashes/#{URI.encode_www_form(key)}/rankings?list=losers&universe=#{universe}&limit=1"
        )

      assert text(Floki.find(row, "[data-role='crash-benchmark']")) ==
               percent(ranking["reference"]["return"])

      case ranking["entries"] do
        [lowest] ->
          assert text(Floki.find(row, "[data-role='crash-lowest'] bdi")) ==
                   lowest["security"]["name"]

          assert text(Floki.find(row, "[data-role='crash-lowest-return']")) ==
                   percent(lowest["return"])

        [] ->
          assert text(Floki.find(row, "[data-role='crash-lowest']")) == "—"
      end
    end
  end

  # User story:
  # As the operator reading „Crashes im Vergleich“ on the dashboard,
  # I want each window's benchmark return and the lowest return of my
  # depot, or of the catalogue, to be what the crash routes answer,
  # so that the widget and the Risk tab compare the same prices.
  #
  # Acceptance criteria:
  # - The rows are GET /api/v1/crashes' windows, newest first, five at M.
  # - Per window, the benchmark's return is the losers' list's
  #   reference.return and the lowest entry its first entry, over
  #   universe=held for „Im Depot“ and universe=catalogue for „Katalog“.
  # - The compact rows carry the same windows and benchmark returns.
  # - Each percentage is written as the other widgets write it („−3,1%“)
  #   and never breaks across lines (the width walk measures the break).
  # - „Alle Fenster →“ opens the Risk tab.
  test "„Crashes im Vergleich“ draws the crash routes' answers", %{conn: conn} do
    crash_world!()
    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    rows = rows(view)
    assert length(rows) == 3
    assert_matches_route(rows, "held")

    assert has_element?(
             view,
             "#dashboard-crashes [data-role='crash-lowest'] bdi",
             "Synthetic Holding"
           )

    refute has_element?(
             view,
             "#dashboard-crashes [data-role='crash-lowest'] bdi",
             "Synthetic Outsider"
           )

    view |> element("#dashboard-crashes [data-universe='catalogue']") |> render_click()
    render_async(view)

    assert has_element?(
             view,
             "#dashboard-crashes [data-universe='catalogue'][aria-pressed='true']"
           )

    assert_matches_route(rows(view), "catalogue")

    assert has_element?(
             view,
             "#dashboard-crashes [data-role='crash-lowest'] bdi",
             "Synthetic Outsider"
           )

    compact =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("#dashboard-crashes [data-form='compact'] [data-compact-role='crash-window']")

    assert Enum.map(compact, &hd(Floki.attribute(&1, "data-key"))) ==
             Enum.map(rows(view), &hd(Floki.attribute(&1, "data-key")))

    assert has_element?(
             view,
             "#dashboard-crashes [data-role='crashes-all-windows'][href='/risk']"
           )
  end

  # User story:
  # As the operator who has chosen no crash benchmark,
  # I want the widget to say why it has no windows,
  # so that its frame is never empty without a word.
  #
  # Acceptance criteria:
  # - Without a crash benchmark the widget draws its frame and one quiet
  #   line, no table, and no word for a benchmark in its footer.
  test "without a crash benchmark the widget says so", %{conn: conn} do
    world = base_world()
    security = create_security!(name: "Synthetic Plain", ticker: "SPL")
    deposit!(world, "1000", day(-30))
    buy!(world, security, quantity: "1", price: "100", date: day(-20))

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert has_element?(
             view,
             "#dashboard-crashes [data-role='crashes-empty']",
             "No crash benchmark"
           )

    refute has_element?(view, "#dashboard-crashes [data-role='crashes-table']")

    # The footer names no benchmark it does not have (found on the review
    # seed's screenshot: a footer reading "false" while the read ran).
    refute has_element?(view, "#dashboard-crashes [data-role='widget-scope']", "false")
  end
end
