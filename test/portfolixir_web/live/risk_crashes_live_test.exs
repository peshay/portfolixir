defmodule PortfolixirWeb.RiskCrashesLiveTest do
  # Sprint 29 C6 (FR-54, #1421; ADR-0058 §9 and its amendment's F1 to F4;
  # board ux-design-2026-11-12-sprint29/01 and 02 ④, plan D-5 P1 to P9 and
  # Q2): the Crashes section on Wealth's Risk tab, driven as the operator
  # drives it — the window chosen in the select, the list and the universe
  # switched, the crash benchmark chosen inline, a window named, an
  # overlapping manual window drawn and deleted, a name without a window
  # made manual, „Im Depot ansehen“ followed — and every list it shows
  # compared with the API's answer for the same window, list and universe
  # (plan D-1, item 7). Every name and figure is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PortfolixirWeb.PreferenceCookieHelpers

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Crashes
  alias Portfolixir.Journal
  alias Portfolixir.Settings
  alias PortfolixirWeb.Format

  defp day(offset), do: Date.add(Date.utc_today(), offset)

  # The index falls four times: spring 2020 (before the depot's first
  # booking on 2021-05-04), 2022 (recovered 2023-06-01, its rebound span
  # complete), a recent fall recovered 20 days ago (its rebound span still
  # open) and one still falling.
  defp crash_world! do
    world = base_world()

    index = create_security!(name: "Synthetic Crash Index", ticker: "SCI")

    put_quotes!(index, [
      {~D[2020-02-19], "100"},
      {~D[2020-03-23], "70"},
      {~D[2020-08-18], "101"},
      {~D[2022-01-03], "120"},
      {~D[2022-10-12], "90"},
      {~D[2023-01-12], "100"},
      {~D[2023-06-01], "125"},
      {day(-60), "130"},
      {day(-40), "110"},
      {day(-20), "131"},
      {day(-5), "115"},
      {day(-1), "118"}
    ])

    faller = create_security!(name: "Synthetic Faller", ticker: "SFL", isin: "DE000CRSH6F1")

    put_quotes!(faller, [
      {~D[2020-02-19], "40"},
      {~D[2020-03-23], "20"},
      {~D[2021-05-04], "45"},
      {~D[2022-01-03], "50"},
      {~D[2022-10-12], "30"},
      {~D[2023-01-12], "45"},
      {~D[2023-03-01], "50"},
      {day(-60), "60"},
      {day(-40), "48"},
      {day(-20), "58"},
      {day(-5), "50"},
      {day(-1), "52"}
    ])

    riser = create_security!(name: "Synthetic Riser", ticker: "SRS", isin: "DE000CRSH6R1")

    put_quotes!(riser, [
      {~D[2020-02-19], "18"},
      {~D[2020-03-23], "19"},
      {~D[2021-05-04], "19"},
      {~D[2022-01-03], "20"},
      {~D[2022-10-12], "22"},
      {~D[2023-01-12], "25"},
      {day(-60), "25"},
      {day(-40), "26"},
      {day(-20), "27"},
      {day(-5), "28"}
    ])

    # In the catalogue only: never held.
    other = create_security!(name: "Synthetic Outsider", ticker: "SOU", isin: "DE000CRSH6O1")

    put_quotes!(other, [
      {~D[2020-02-19], "10"},
      {~D[2020-03-23], "9"},
      {~D[2022-01-03], "10"},
      {~D[2022-10-12], "8"},
      {~D[2023-01-12], "9"}
    ])

    deposit!(world, "10000", ~D[2021-05-04])
    buy!(world, faller, quantity: "10", price: "45", date: ~D[2021-05-04])
    buy!(world, riser, quantity: "10", price: "19", date: ~D[2021-05-04])

    {:ok, bucket} =
      Buckets.create_bucket(Actor.owner_ui(), %{
        name: "Synthetic Crash Bucket #{System.unique_integer([:positive])}"
      })

    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), world.depot, [bucket.id])

    {:ok, view} =
      Buckets.create_view(Actor.owner_ui(), %{
        name: "Synthetic Crash View #{System.unique_integer([:positive])}",
        include_all: false
      })

    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])

    {:ok, _index} = Settings.set_crash_benchmark(Actor.owner_ui(), index.id)

    Map.merge(world, %{
      index: index,
      faller: faller,
      riser: riser,
      other: other,
      view: view,
      spring: "d:#{index.id}:2020-02-19",
      bear: "d:#{index.id}:2022-01-03",
      recent: "d:#{index.id}:#{Date.to_iso8601(day(-60))}",
      ongoing: "d:#{index.id}:#{Date.to_iso8601(day(-20))}"
    })
  end

  defp risk_path(world, pairs \\ []),
    do: "/risk?" <> URI.encode_query([{"view", world.view.id} | pairs])

  defp authed(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  # The API's answer for the same window, list and universe.
  defp api(key, list, universe) do
    build_conn()
    |> authed()
    |> get(
      "/api/v1/crashes/#{URI.encode_www_form(key)}/rankings?" <>
        URI.encode_query(list: list, universe: universe)
    )
    |> json_response(200)
    |> Map.fetch!("data")
  end

  # The rows the section shows: rank, security id, the exact return it
  # draws, and the figure it prints.
  defp screen_rows(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#risk-crashes table.crash-table tbody tr")
    |> Enum.map(fn row ->
      [rank] = LazyHTML.attribute(row, "data-rank")
      [id] = LazyHTML.attribute(row, "data-security-id")
      [return] = LazyHTML.attribute(row, "data-return")
      figure = row |> LazyHTML.query("[data-role=crash-figure]") |> LazyHTML.text() |> squish()
      {String.to_integer(rank), String.to_integer(id), Decimal.new(return), figure}
    end)
  end

  defp squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  # The screen's list equals the API's, figure for figure, in its order.
  defp assert_same_as_api(view, key, list, universe) do
    data = api(key, list, universe)
    rows = screen_rows(view)

    assert length(rows) == length(data["entries"]),
           "the screen shows #{length(rows)} rows, the API #{length(data["entries"])}"

    for {{rank, id, return, figure}, entry} <- Enum.zip(rows, data["entries"]) do
      assert rank == entry["rank"]
      assert id == entry["security"]["id"]
      assert Decimal.equal?(return, Decimal.new(entry["return"]))
      assert figure == Format.signed_percent(Decimal.new(entry["return"])) <> " %"
    end

    data
  end

  defp section(view),
    do: view |> element("#risk-crashes") |> render()

  # User story (ADR-0058 §9; board 01 ①, plan D-5 P1 to P4):
  # As the operator,
  # I want a Crashes section on Wealth's Risk tab that opens on the newest
  # crash window, my view's holdings and the losers,
  # so that I see at once what the latest fall did to what I hold.
  #
  # Acceptance criteria:
  # - The section sits after „Kennzahlen des Portfolios“ (P1).
  # - One bar of labelled controls, the window's select its first control
  #   (P2), then the list and the universe.
  # - It opens on the newest window (P4), „Im Depot“ (P3) and Verlierer,
  #   and the list it shows is the API's for view:<id>, figure for figure.
  # - Beside each figure the difference to the crash benchmark in points.
  test "opens after the portfolio metrics on the newest window, the view's holdings and the losers",
       %{conn: conn} do
    world = crash_world!()
    {:ok, view, html} = live(conn, risk_path(world))

    {metrics_at, _} = :binary.match(html, ~s(id="risk-metrics"))
    {crashes_at, _} = :binary.match(html, ~s(id="risk-crashes"))
    assert metrics_at < crashes_at

    controls =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(
        "#risk-crashes [data-role=crash-bar] select, #risk-crashes [data-role=crash-bar] [role=group]"
      )

    assert [first | _] = Enum.to_list(controls)
    assert LazyHTML.attribute(first, "id") == ["crash-window"]

    assert has_element?(view, "#crash-window option[selected][value='#{world.ongoing}']")
    assert has_element?(view, "[data-role=crash-list] a.is-active[data-list=losers]")
    assert has_element?(view, "[data-role=crash-universe] a.is-active[data-universe=depot]")

    data = assert_same_as_api(view, world.ongoing, "losers", "view:#{world.view.id}")
    assert [%{"security" => %{"name" => "Synthetic Faller"}}, _riser] = data["entries"]

    faller = hd(data["entries"])

    assert has_element?(
             view,
             "tr[data-security-id='#{world.faller.id}'] .crash-pp",
             Format.plain_signed_decimal(Decimal.new(faller["vs_benchmark_pp"]), 1) <> " pp"
           )
  end

  # User story (ADR-0058 §5, §9; board 01 ①, ②, ④; plan D-5 P4, P5):
  # As the operator,
  # I want to pick a window in the select and switch the list and the
  # universe, the choice kept in the address,
  # so that a reload or a link shows the same list.
  #
  # Acceptance criteria:
  # - Choosing a window patches the address (crash=<key>) and shows its
  #   list; Gewinner and „Ganzer Katalog“ patch too; each list equals the
  #   API's for the same window, list and universe.
  # - In the catalogue a held security carries „im Depot“, the API's held.
  # - The address alone opens the same choice.
  test "the window, the list and the universe are chosen as the operator does, each list the API's",
       %{conn: conn} do
    world = crash_world!()
    {:ok, view, _html} = live(conn, risk_path(world))

    view |> element("#crash-window-form") |> render_change(%{"crash" => world.bear})

    assert_patch(
      view,
      risk_path(world, crash: world.bear, crash_list: "losers", crash_universe: "depot")
    )

    assert_same_as_api(view, world.bear, "losers", "view:#{world.view.id}")

    view |> element("[data-role=crash-list] a[data-list=winners]") |> render_click()

    assert_patch(
      view,
      risk_path(world, crash: world.bear, crash_list: "winners", crash_universe: "depot")
    )

    assert_same_as_api(view, world.bear, "winners", "view:#{world.view.id}")

    view |> element("[data-role=crash-universe] a[data-universe=catalogue]") |> render_click()

    assert_patch(
      view,
      risk_path(world, crash: world.bear, crash_list: "winners", crash_universe: "catalogue")
    )

    data = assert_same_as_api(view, world.bear, "winners", "catalogue")

    for entry <- data["entries"] do
      held? =
        has_element?(
          view,
          "tr[data-security-id='#{entry["security"]["id"]}'] [data-role=crash-held]"
        )

      assert held? == entry["held"],
             "#{entry["security"]["name"]}: im Depot #{held?}, API #{entry["held"]}"
    end

    assert Enum.any?(data["entries"], & &1["held"])
    refute Enum.all?(data["entries"], & &1["held"])

    # The address alone opens the same choice.
    {:ok, again, _html} =
      live(
        conn,
        risk_path(world, crash: world.bear, crash_list: "winners", crash_universe: "catalogue")
      )

    assert has_element?(again, "#crash-window option[selected][value='#{world.bear}']")
    assert_same_as_api(again, world.bear, "winners", "catalogue")
  end

  # User story (ADR-0058 §5, F3; board 01 ④):
  # As the operator,
  # I want the rebounders with the days each needed to its pre-crash close,
  # complete or provisional,
  # so that I see who recovered and whether the span is over.
  #
  # Acceptance criteria:
  # - Erholer of the 2022 window: the API's list; days back in calendar
  #   days, „noch nicht“ where the API answers not_yet; the window line
  #   names the end of the span.
  # - Erholer of the recent window, its span still open: the API's list,
  #   „vorläufig“ and the day the span completes.
  test "the rebounders, complete and provisional, with the days back or not yet", %{conn: conn} do
    world = crash_world!()

    {:ok, view, _html} =
      live(
        conn,
        risk_path(world, crash: world.bear, crash_list: "rebounders", crash_universe: "catalogue")
      )

    data = assert_same_as_api(view, world.bear, "rebounders", "catalogue")
    assert data["provisional"] == false

    for entry <- data["entries"] do
      days = if entry["not_yet"], do: "not yet", else: Integer.to_string(entry["days_back"])

      assert has_element?(
               view,
               "tr[data-security-id='#{entry["security"]["id"]}'] [data-role=crash-days]",
               days
             )
    end

    assert Enum.any?(data["entries"], & &1["not_yet"])
    assert view |> element("[data-role=crash-window]") |> render() =~ Format.date(~D[2023-01-12])

    {:ok, open, _html} =
      live(
        conn,
        risk_path(world, crash: world.recent, crash_list: "rebounders", crash_universe: "depot")
      )

    data = assert_same_as_api(open, world.recent, "rebounders", "view:#{world.view.id}")
    assert data["provisional"] == true
    completes = Date.from_iso8601!(data["completes_on"])

    line = open |> element("[data-role=crash-window]") |> render()
    assert line =~ "provisional"
    assert line =~ "complete on #{Format.date(completes)}"
  end

  # User story (ADR-0058 §2.5, §9, F4; board 01 ⑤, ⑧):
  # As the operator,
  # I want an ongoing window marked as such, and „Im Depot ansehen“ to open
  # Holdings over exactly the window's days, or to say why it cannot,
  # so that a link never opens a different period than it names.
  #
  # Acceptance criteria:
  # - The ongoing window: „läuft“ in its option, „vorläufig“ beside its low,
  #   the hint that the low and the lists move; the link's range ends today.
  # - The 2022 window links /portfolio?from=<start>&to=<trough>.
  # - The 2020 window ends before the view's first booking: no link, one
  #   line naming the view's first day; the list still answers.
  test "an ongoing window, and „Im Depot ansehen“ with the window as the range or a line why not",
       %{conn: conn} do
    world = crash_world!()
    {:ok, view, _html} = live(conn, risk_path(world))

    assert view |> element("#crash-window option[value='#{world.ongoing}']") |> render() =~
             "ongoing"

    line = view |> element("[data-role=crash-window]") |> render()
    assert line =~ "provisional"
    assert has_element?(view, "[data-role=crash-ongoing-hint]")

    assert has_element?(
             view,
             "a[data-role=crash-holdings-link][href='/portfolio?from=#{Date.to_iso8601(day(-20))}&to=#{Date.to_iso8601(Date.utc_today())}']"
           )

    view |> element("#crash-window-form") |> render_change(%{"crash" => world.bear})

    assert has_element?(
             view,
             "a[data-role=crash-holdings-link][href='/portfolio?from=2022-01-03&to=2022-10-12']"
           )

    # The link opens Holdings over that range, no fallback line.
    {:ok, holdings, _html} = live(conn, "/portfolio?from=2022-01-03&to=2022-10-12")
    refute has_element?(holdings, "[data-role=period-fallback]")

    view |> element("#crash-window-form") |> render_change(%{"crash" => world.spring})
    refute has_element?(view, "a[data-role=crash-holdings-link]")

    assert has_element?(
             view,
             "[data-role=crash-holdings-none]",
             "The view begins on #{Format.date(~D[2021-05-04])}"
           )

    assert_same_as_api(view, world.spring, "losers", "view:#{world.view.id}")
  end

  # User story (ADR-0058 §1, F2; board 01 ⑦, board 02 ④ Q2):
  # As the operator,
  # I want the section to say when no crash benchmark is chosen, keep my
  # manual windows working without a reference, and let me choose the
  # benchmark right there,
  # so that I never need another page to start detecting crashes.
  #
  # Acceptance criteria:
  # - Unset and no manual window: one note with „Crash-Benchmark wählen“
  #   and the empty state.
  # - Unset with a manual window: its lists are the API's, no Pp. column,
  #   the basis says there is no comparison.
  # - „Crash-Benchmark wählen“ opens the disclosure with the picker's
  #   groups „Benchmarks“ and „Im Bestand“; saving stores the setting,
  #   journaled under the operator, and the detected windows appear.
  test "no crash benchmark: the note, manual windows without a reference, and the inline choice",
       %{conn: conn} do
    world = crash_world!()
    {:ok, _cleared} = Settings.set_crash_benchmark(Actor.owner_ui(), nil)

    {:ok, empty, _html} = live(conn, risk_path(world))
    assert has_element?(empty, "[data-role=crash-no-benchmark]")
    assert has_element?(empty, "#risk-crashes [data-role=crash-empty]")
    refute has_element?(empty, "#risk-crashes table.crash-table")

    {:ok, manual} =
      Crashes.create_manual_window(Actor.owner_ui(), %{
        "name" => "Synthetic Hand Window",
        "start" => "2022-01-03",
        "trough" => "2022-10-12"
      })

    key = "m:#{manual.id}"
    {:ok, view, _html} = live(conn, risk_path(world))
    assert has_element?(view, "[data-role=crash-no-benchmark]")
    assert has_element?(view, "#crash-window option[selected][value='#{key}']", "manual")

    data = assert_same_as_api(view, key, "losers", "view:#{world.view.id}")
    assert data["reference"] == nil
    refute has_element?(view, "#risk-crashes .crash-pp")
    assert view |> element("[data-role=crash-basis]") |> render() =~ "no crash benchmark chosen"

    # A flagged security, so the picker shows both groups.
    {:ok, _flagged} =
      Catalog.update_security(Actor.owner_ui(), world.index, %{is_benchmark: true})

    {:ok, view, _html} = live(conn, risk_path(world))

    view |> element("[data-role=crash-choose-benchmark]") |> render_click()
    assert has_element?(view, "details#crash-windows[open] form#crash-benchmark-form")
    assert has_element?(view, "#crash-benchmark-form optgroup[label='Benchmarks']")
    assert has_element?(view, "#crash-benchmark-form optgroup[label='In holdings']")

    view
    |> element("#crash-benchmark-form")
    |> render_submit(%{"crash_benchmark" => Integer.to_string(world.index.id)})

    assert Settings.crash_benchmark_security_id() == world.index.id

    assert [%{resource_type: "setting", actor_type: :owner_ui, operation: :upsert} | _] =
             Journal.list_entries(resource_type: "setting")

    refute has_element?(view, "[data-role=crash-no-benchmark]")
    assert has_element?(view, "#crash-window option[value='#{world.ongoing}']")
    assert has_element?(view, "[data-role=crash-rule]", "Synthetic Crash Index")
  end

  # User story (ADR-0058 §3, §4, F1; board 01 ⑥):
  # As the operator,
  # I want to name a detected window, draw a manual window that overlaps
  # it, delete what I drew, and turn a name that lost its window into a
  # manual window by giving its low,
  # so that every window I talk about has a name and an honest kind.
  #
  # Acceptance criteria:
  # - „Benennen“ names the window: the select and the window line read the
  #   name, the write journaled as a crash window name.
  # - „Fenster anlegen“ draws a manual window overlapping the 2022 one; a
  #   low before the high is refused in the form and writes nothing; the
  #   window reads „manuell“ and its lists are the API's.
  # - „Löschen“ (with a confirmation) deletes it.
  # - A name given for another benchmark is listed without a window, its
  #   benchmark named; „Als manuelles Fenster anlegen …“ asks for the low,
  #   and saving makes a manual window and drops the name.
  test "name a window, draw and delete an overlapping manual one, make a lost name manual",
       %{conn: conn} do
    world = crash_world!()
    {:ok, view, _html} = live(conn, risk_path(world, crash: world.bear))

    view
    |> element("button[data-role=crash-name-open][phx-value-key='#{world.bear}']")
    |> render_click()

    view
    |> element("#crash-window-edit-form")
    |> render_submit(%{"window" => %{"name" => "Synthetic Bear 2022"}})

    assert has_element?(
             view,
             "#crash-window option[value='#{world.bear}']",
             "Synthetic Bear 2022"
           )

    assert has_element?(view, "[data-role=crash-window]", "Synthetic Bear 2022")

    assert [%{resource_type: "crash_window_name"}] =
             Journal.list_entries(resource_type: "crash_window_name")

    view |> element("button[data-role=crash-add-window]") |> render_click()

    refused =
      view
      |> element("#crash-window-edit-form")
      |> render_submit(%{
        "window" => %{
          "name" => "Synthetic War",
          "start" => "2022-03-01",
          "trough" => "2022-02-01"
        }
      })

    assert refused =~ "must be after start"
    assert Crashes.list_windows().manual == []

    view
    |> element("#crash-window-edit-form")
    |> render_submit(%{
      "window" => %{"name" => "Synthetic War", "start" => "2022-02-16", "trough" => "2022-03-07"}
    })

    assert [%{key: manual_key}] = Crashes.list_windows().manual

    assert_patch(
      view,
      risk_path(world, crash: manual_key, crash_list: "losers", crash_universe: "depot")
    )

    assert has_element?(view, "#crash-window option[selected][value='#{manual_key}']", "manual")
    assert has_element?(view, "[data-role=crash-window] .badge", "manual")
    assert has_element?(view, "#crash-windows-table tr[data-key='#{manual_key}']", "manual")
    assert_same_as_api(view, manual_key, "losers", "view:#{world.view.id}")

    delete = element(view, "button[data-role=crash-manual-delete][phx-value-key='#{manual_key}']")
    assert render(delete) =~ "data-confirm"
    render_click(delete)
    assert Crashes.list_windows().manual == []
    refute has_element?(view, "#crash-window option[value='#{manual_key}']")

    # A name given while another security was the crash benchmark.
    other_index = create_security!(name: "Synthetic Old Index", ticker: "SOI")
    put_quotes!(other_index, [{~D[2023-07-31], "100"}, {~D[2023-10-27], "85"}])
    {:ok, _old} = Settings.set_crash_benchmark(Actor.owner_ui(), other_index.id)
    old_key = "d:#{other_index.id}:2023-07-31"

    {:ok, _name} =
      Crashes.name_window(Actor.owner_ui(), old_key, %{"name" => "Synthetic Correction"})

    {:ok, _back} = Settings.set_crash_benchmark(Actor.owner_ui(), world.index.id)

    {:ok, view, _html} = live(conn, risk_path(world))
    row = element(view, "#crash-unmatched tr[data-key='#{old_key}']")
    assert render(row) =~ "Synthetic Correction"
    assert render(row) =~ "Synthetic Old Index"
    assert render(row) =~ "returns when it is the crash benchmark again"

    view
    |> element("button[data-role=crash-from-name-open][phx-value-key='#{old_key}']")
    |> render_click()

    assert has_element?(view, "#crash-from-name-form input[name='window[trough]'][required]")

    view
    |> element("#crash-from-name-form")
    |> render_submit(%{"window" => %{"name" => "Synthetic Correction", "trough" => "2023-10-27"}})

    assert [%{name: "Synthetic Correction", start: ~D[2023-07-31], trough: ~D[2023-10-27]}] =
             Crashes.list_windows().manual

    assert Crashes.list_windows().unmatched_names == []
    refute has_element?(view, "#crash-unmatched")
  end

  # User story (FR-51; plan D-5; board 01 ⑨):
  # As the operator showing the screen to someone,
  # I want the privacy mode to leave the Crashes section as it is,
  # so that percentages, dates and day counts stay readable while amounts
  # elsewhere hide.
  #
  # Acceptance criteria:
  # - The section renders the same with the privacy mode on and off, for
  #   the losers and the rebounders.
  test "the privacy mode leaves the section unchanged", %{conn: conn} do
    world = crash_world!()

    for list <- ~w(losers rebounders) do
      path = risk_path(world, crash: world.bear, crash_list: list, crash_universe: "catalogue")
      {:ok, plain, _html} = live(conn, path)
      {:ok, private, _html} = live(put_preference_cookie(conn, "portfolixir_privacy", "on"), path)

      assert section(private) == section(plain)
      refute section(private) =~ "pf-mask"
    end
  end

  # User story (board 01, German copy; plan D-5 P2, P3):
  # As the operator reading the app in German,
  # I want the section in the board's words,
  # so that it reads as the rest of the page.
  #
  # Acceptance criteria:
  # - „Crashes“, „Fenster“, „Liste“, „Verlierer“, „Im Depot“, „Ganzer
  #   Katalog“, „Im Depot ansehen“, „Crash-Fenster“ and „erkannt“ read in
  #   German.
  test "reads in German", %{conn: conn} do
    world = crash_world!()
    german = put_preference_cookie(conn, "portfolixir_locale", "de")
    {:ok, view, _html} = live(german, risk_path(world, crash: world.bear))
    html = section(view)

    for word <- [
          "Crashes",
          "Fenster",
          "Liste",
          "Verlierer",
          "Gewinner",
          "Erholer",
          "Im Depot",
          "Ganzer Katalog",
          "Im Depot ansehen",
          "Crash-Fenster",
          "erkannt",
          "Kursrendite Hoch → Tief, EUR",
          "Grundlage"
        ] do
      assert html =~ word, "missing „#{word}“"
    end
  end

  # User story (board 01 P3; ADR-0058 §5; the closing act, #1421):
  # As the operator who has chosen no view (Everything),
  # I want „Im Depot“ to list what I hold today in any depot,
  # so that the section opens on my holdings as it does with a view, and
  # the list is one the API reproduces.
  #
  # Acceptance criteria:
  # - With no view: „Im Depot“ is active and lists the API's universe
  #   `held`; the catalogue is one click away; no line says a view is
  #   needed.
  test "with no view chosen „Im Depot“ lists today's holdings in any depot", %{conn: conn} do
    world = crash_world!()
    {:ok, view, _html} = live(conn, "/risk?view=total")

    assert has_element?(view, "[data-role=crash-universe] .is-active[data-universe=depot]")
    assert has_element?(view, "[data-role=crash-universe] a[data-universe=catalogue]")
    refute has_element?(view, "[data-role=crash-depot-needs-view]")
    data = assert_same_as_api(view, world.ongoing, "losers", "held")
    refute Enum.any?(data["entries"], &(&1["security"]["name"] == "Synthetic Outsider"))

    view |> element("[data-role=crash-universe] a[data-universe=catalogue]") |> render_click()
    assert_same_as_api(view, world.ongoing, "losers", "catalogue")
  end

  # User story (ADR-0058 §5: no answer is never a zero; board 01 ①):
  # As the operator,
  # I want the securities without an answer counted under the list, per
  # reason, and named on request,
  # so that a short list never hides who could not be measured.
  #
  # Acceptance criteria:
  # - The line counts the shown, the answered and the unanswered with
  #   their reasons as the API answers them.
  # - „anzeigen“ names each unanswered security with its reason.
  test "the unanswered are counted per reason and named on request", %{conn: conn} do
    world = crash_world!()

    {:ok, view, _html} =
      live(conn, risk_path(world, crash: world.ongoing, crash_universe: "catalogue"))

    data = api(world.ongoing, "losers", "catalogue")
    missing = data["unanswered"] |> Map.values() |> Enum.sum()
    assert missing > 0

    line = view |> element("[data-role=crash-unanswered]") |> render() |> squish()
    total = data["answered"] + missing
    assert line =~ "#{length(data["entries"])} of #{total} securities with an answer shown"
    assert line =~ "#{missing} without an answer"
    assert line =~ "#{data["unanswered"]["no_close_at_start"]} without a close at the window"

    view |> element("[data-role=crash-unanswered] button") |> render_click()
    assert has_element?(view, "[data-role=crash-unanswered-list] li", "Synthetic Outsider")
  end

  # The closing act (#1416, #1421; UAT-13's rule): two securities of one
  # name read the same in the crash list and in the crash benchmark's
  # select. A list row carries the identifier that tells its twin apart
  # (SecurityNames.put_twin_ids/2), the select's option the picker's tag.
  test "same-named securities are told apart in the list and in the benchmark select",
       %{conn: conn} do
    world = crash_world!()

    for {isin, low} <- [{"DE000TWIN011", "25"}, {"LU000TWIN022", "30"}] do
      twin = create_security!(name: "Synthetic Twin", ticker: nil, isin: isin)
      put_quotes!(twin, [{~D[2020-02-19], "50"}, {~D[2020-03-23], low}, {~D[2021-05-04], "40"}])
      buy!(world, twin, quantity: "1", price: "40", date: ~D[2021-05-04])
    end

    {:ok, view, _html} =
      live(conn, risk_path(world, crash: world.spring, crash_universe: "catalogue"))

    names =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#risk-crashes table.crash-table tbody td.crash-name")
      |> Enum.map(&(&1 |> LazyHTML.text() |> squish()))
      |> Enum.filter(&String.starts_with?(&1, "Synthetic Twin"))

    assert [first, second] = names
    assert first =~ "Synthetic Twin ISIN DE000TWIN011"
    assert second =~ "Synthetic Twin ISIN LU000TWIN022"

    view |> element("button[data-role=crash-change-benchmark]") |> render_click()

    options =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#crash-benchmark option")
      |> Enum.map(&(&1 |> LazyHTML.text() |> squish()))
      |> Enum.filter(&String.starts_with?(&1, "Synthetic Twin"))

    assert options == ["Synthetic Twin · DE000TWIN011", "Synthetic Twin · LU000TWIN022"]
  end

  # The closing act (#1421): a write refused because the window is gone (an
  # agent deleted it, or switched the crash benchmark away under an open
  # name form) says "the section was read again". It now is: the deleted
  # window leaves the select and the windows table, and the old benchmark's
  # window is no longer offered.
  test "a refused write reads the section again, as its message says", %{conn: conn} do
    world = crash_world!()

    {:ok, manual} =
      Crashes.create_manual_window(Actor.owner_ui(), %{
        "name" => "Synthetic War",
        "start" => "2022-02-24",
        "trough" => "2022-03-09"
      })

    key = "m:#{manual.id}"
    {:ok, view, _html} = live(conn, risk_path(world, crash: key))

    view
    |> element("button[data-role=crash-manual-edit][phx-value-key='#{key}']")
    |> render_click()

    {:ok, _deleted} = Crashes.delete_window(Actor.api_token_rw("mcp"), key)

    html =
      view
      |> element("#crash-window-edit-form")
      |> render_submit(%{"window" => %{"name" => "Synthetic War, renamed"}})

    assert html =~ "the section was read again"
    refute has_element?(view, "#crash-window option[value='#{key}']")
    refute has_element?(view, "#crash-windows-table tr[data-key='#{key}']")

    view
    |> element("button[data-role=crash-name-open][phx-value-key='#{world.bear}']")
    |> render_click()

    other = create_security!(name: "Synthetic Other Index", ticker: "SOI")
    put_quotes!(other, [{~D[2024-01-03], "100"}, {~D[2024-10-12], "80"}])
    {:ok, _other} = Settings.set_crash_benchmark(Actor.api_token_rw("mcp"), other.id)

    html =
      view
      |> element("#crash-window-edit-form")
      |> render_submit(%{"window" => %{"name" => "Synthetic Bear"}})

    assert html =~ "the section was read again"
    refute has_element?(view, "#crash-window option[value='#{world.bear}']")
  end
end
