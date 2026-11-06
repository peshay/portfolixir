defmodule PortfolixirWeb.PredictionsLiveTest do
  # Sprint 26 V2 (F1, ADR-0055 §§4-5; board
  # `ux-design-2026-11-06-sprint26-f1`, part 2, pick A): the calibration
  # report as Wealth's seventh tab, "Predictions" (`/predictions`). The
  # report reads `Predictions.calibration_report/2`, the read
  # `GET /api/v1/predictions/calibration` answers from, so every figure here
  # is compared with the API's answer for the same filter. Every name, date
  # and figure is synthetic and relative to the instance's today.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [create_security!: 1, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Clock
  alias Portfolixir.Predictions
  alias PortfolixirWeb.Format

  defp day(offset), do: Date.add(Clock.today(), offset)

  defp agent, do: Actor.api_token_rw("research-agent")
  defp operator, do: Actor.owner_ui()

  defp predict!(actor, security, made, attrs) do
    {:ok, made_at} = DateTime.new(day(made), ~T[12:00:00.000000], "Etc/UTC")

    attrs =
      Map.merge(
        %{
          "security_id" => security.id,
          "direction" => "outperform",
          "probability" => "0.70",
          "benchmark" => "rate:0",
          "resolves_on" => Date.to_iso8601(day(-10))
        },
        attrs
      )

    {:ok, prediction} = Predictions.create_prediction(actor, attrs, now: made_at)
    prediction
  end

  defp world do
    gear = create_security!(name: "Synthetic Gearworks AG", ticker: nil, currency: "EUR")
    harbor = create_security!(name: "Synthetic Harbor Co", ticker: nil, currency: "EUR")

    {:ok, index} =
      Catalog.create_security(operator(), %{
        name: "Synthetic Industrial Index",
        currency_code: "EUR",
        asset_class: "etf",
        is_benchmark: true
      })

    # Gearworks +10 %, Harbor -5 %, the index +3 %, from -100 to -10.
    put_quotes!(gear, [{day(-100), "100"}, {day(-10), "110"}])
    put_quotes!(harbor, [{day(-100), "100"}, {day(-10), "95"}])
    put_quotes!(index, [{day(-100), "200"}, {day(-10), "206"}])

    hit_a2 =
      predict!(agent(), gear, -100, %{"model" => "model-alpha-2", "probability" => "0.70"})

    miss_a3 =
      predict!(agent(), harbor, -99, %{"model" => "model-alpha-3", "probability" => "0.60"})

    miss_index =
      predict!(agent(), gear, -98, %{
        "model" => "model-alpha-3",
        "direction" => "underperform",
        "probability" => "0.55",
        "benchmark" => "security:#{index.id}"
      })

    hit_op =
      predict!(operator(), harbor, -97, %{"direction" => "underperform", "probability" => "0.80"})

    # Unresolved: Gearworks has no close within 7 days of -80.
    unresolved =
      predict!(agent(), gear, -80, %{"model" => "model-alpha-3", "probability" => "0.90"})

    # Due: past its day, waiting for Harbor's close.
    due =
      predict!(agent(), harbor, -40, %{
        "model" => "model-alpha-2",
        "probability" => "0.75",
        "resolves_on" => Date.to_iso8601(day(-2))
      })

    open =
      predict!(operator(), gear, -2, %{
        "probability" => "0.65",
        "resolves_on" => Date.to_iso8601(day(60))
      })

    %{
      gear: gear,
      harbor: harbor,
      index: index,
      hit_a2: hit_a2,
      miss_a3: miss_a3,
      miss_index: miss_index,
      hit_op: hit_op,
      unresolved: unresolved,
      due: due,
      open: open
    }
  end

  defp api(path, query \\ %{}) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path, query)
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp text(html), do: html |> Floki.parse_fragment!() |> Floki.text(sep: " ") |> squish()
  defp squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()
  defp text_of(view, selector), do: view |> element(selector) |> render() |> text()

  defp d(string), do: Decimal.new(string)

  # The calibration cards as the API's answer should read on the page.
  defp assert_cards(view, data) do
    brier = data["brier"]
    hit = data["hit_rate"]

    assert text_of(view, "[data-role='prediction-brier']") =~
             "Brier score #{Format.decimal(d(brier["score"]), 3)} ± #{Format.decimal(d(brier["standard_error"]), 3)}"

    assert text_of(view, "[data-role='prediction-brier']") =~
             "reference #{Format.decimal(d(brier["reference"]), 2)} = always 50 %"

    assert text_of(view, "[data-role='prediction-sharpness']") =~
             "Sharpness #{Format.decimal(d(data["sharpness"]), 2)}"

    assert text_of(view, "[data-role='prediction-hit-rate']") =~
             "Hit rate #{Format.percent(d(hit["rate"]))} %"

    assert text_of(view, "[data-role='prediction-hit-rate']") =~
             "± #{Format.percent(d(hit["standard_error"]))} pp standard error · mean stated #{Format.percent(d(hit["mean_probability"]))} %"

    unresolved = data["counts"]["unresolved"] |> Map.values() |> Enum.sum()

    assert text_of(view, "[data-role='prediction-counts']") ==
             "Resolved #{data["counts"]["resolved"]} #{data["counts"]["open"]} open and #{unresolved} not resolved count in no score"
  end

  # User story (V2, F1; ADR-0055 §4, board 02 part 2, pick A ① ③ ④):
  # As the operator asking how much weight the agent's calls deserve,
  # I want the calibration report on its own Wealth tab, filtered by author
  # and model,
  # so that I read the Brier score with its uncertainty, the sharpness and
  # the hit rate without the API.
  #
  # Acceptance criteria:
  # - "Predictions" is Wealth's seventh tab (`/predictions`), current on
  #   the page; the subtitle says it spans every security, whatever the view.
  # - "Calibration" with its counts; the Brier score ± its standard error
  #   with the 0.25 reference, the sharpness, the hit rate ± its standard
  #   error beside the mean stated probability, the resolved count: each
  #   the API's /calibration figure for the same filter.
  # - A click on an author chip filters the report and puts the filter in
  #   the URL; a link handed over with author and model opens filtered.
  test "the report is Wealth's seventh tab and reads the API's calibration", %{conn: conn} do
    world()
    {:ok, view, _html} = live(conn, "/predictions")

    tabs =
      view
      |> element("nav[data-role='area-tabs']")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("a.area-tab")

    assert length(tabs) == 7
    assert tabs |> List.last() |> Floki.attribute("href") == ["/predictions"]
    assert tabs |> List.last() |> Floki.attribute("aria-current") == ["page"]

    assert render(view) =~
             "How well the recorded predictions have scored · across all securities, independent of the view"

    assert text_of(view, "#prediction-calibration-title") ==
             "Calibration · 4 resolved · 2 open · 1 not resolved"

    assert_cards(view, api("/api/v1/predictions/calibration"))

    view |> element("#prediction-chip-author-agent") |> render_click()
    assert_patch(view, "/predictions?author=agent")
    assert view |> element("#prediction-chip-author-agent") |> render() =~ ~s(aria-pressed="true")
    assert_cards(view, api("/api/v1/predictions/calibration", %{"author" => "agent"}))

    view |> element("#prediction-chip-model-model-alpha-3") |> render_click()
    assert_patch(view, "/predictions?author=agent&model=model-alpha-3")

    {:ok, view, _html} = live(conn, "/predictions?author=agent&model=model-alpha-3")

    assert_cards(
      view,
      api("/api/v1/predictions/calibration", %{"author" => "agent", "model" => "model-alpha-3"})
    )

    # A second click on the pressed model chip clears it.
    view |> element("#prediction-chip-model-model-alpha-3") |> render_click()
    assert_patch(view, "/predictions?author=agent")
  end

  # User story (V2, ADR-0055 §4 condition 1; board 02 part 2 ⑤, judgment
  # call 7):
  # As the operator with a small sample,
  # I want the bands to say why they show no hit rate yet, and to show it
  # once a band has enough calls,
  # so that two calls in a band never read as a calibration.
  #
  # Acceptance criteria:
  # - Below the payload's minimum count in every band: the sentence why,
  #   naming the minimum, and one line with the count per band.
  # - From the minimum in one band: the table, that band with its hit rate,
  #   the others "too few · n of 20".
  test "the bands say why below 20 and show a hit rate from 20", %{conn: conn} do
    world()
    {:ok, view, _html} = live(conn, "/predictions")

    bands = text_of(view, "[data-role='prediction-bands']")

    assert bands =~
             "A hit rate per band shows from 20 resolved predictions in the band; none has reached 20 yet. Until then the Brier score with its standard error carries the finding."

    assert bands =~
             "Resolved per band: 0.50–0.59: 1 · 0.60–0.69: 1 · 0.70–0.79: 1 · 0.80–0.89: 1 · 0.90–0.99: 0"

    refute has_element?(view, "[data-role='prediction-bands'] table")

    full = create_security!(name: "Synthetic Fullband Co", ticker: nil, currency: "EUR")
    put_quotes!(full, [{day(-100), "100"}, {day(-10), "110"}])

    for _ <- 1..19,
        do: predict!(agent(), full, -100, %{"model" => "model-alpha-2", "probability" => "0.72"})

    {:ok, view, _html} = live(conn, "/predictions")
    data = api("/api/v1/predictions/calibration")
    seventy = Enum.at(data["bands"], 2)
    assert seventy["count"] == 20

    rows =
      view
      |> element("[data-role='prediction-bands'] table tbody")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("tr")
      |> Enum.map(&(&1 |> Floki.text(sep: " ") |> squish()))

    assert Enum.at(rows, 2) ==
             "0.70–0.79 20 #{Format.percent(d(seventy["mean_probability"]))} % #{Format.percent(d(seventy["hit_rate"]))} %"

    assert Enum.at(rows, 0) == "0.50–0.59 1 55.0 % too few · 1 of 20"
  end

  # User story (V2, ADR-0055 §4 "groups"; board 02 part 2 ⑥):
  # As the operator comparing my calls with the agent's, and one model's
  # with another's,
  # I want the same block per author and per model,
  # so that a change of model is visible in the figures.
  #
  # Acceptance criteria:
  # - Rows: Operator, Agent (all models), then each model the agent named,
  #   each with its resolved count, Brier score ± standard error,
  #   sharpness, hit rate ± standard error and mean stated probability, as
  #   the API's groups answer them.
  test "the groups by author and model are the API's", %{conn: conn} do
    world()
    {:ok, view, _html} = live(conn, "/predictions")
    groups = api("/api/v1/predictions/calibration")["groups"]

    rows =
      view
      |> element("#prediction-groups-table tbody")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("tr")
      |> Enum.map(&(&1 |> Floki.text(sep: " ") |> squish()))

    agent = Enum.find(groups["author"], &(&1["author"] == "agent"))
    a3 = Enum.find(groups["model"], &(&1["model"] == "model-alpha-3"))

    assert [operator_row, agent_row, a2_row, a3_row] = rows
    assert operator_row =~ ~r/^Operator — 1 /
    assert a2_row =~ ~r/^Agent model-alpha-2 1 /

    assert agent_row ==
             "Agent all models #{agent["counts"]["resolved"]} " <>
               "#{Format.decimal(d(agent["brier"]["score"]), 3)} ± #{Format.decimal(d(agent["brier"]["standard_error"]), 3)} " <>
               "#{Format.decimal(d(agent["sharpness"]), 2)} " <>
               "#{Format.percent(d(agent["hit_rate"]["rate"]))} % ± #{Format.percent(d(agent["hit_rate"]["standard_error"]))} " <>
               "#{Format.percent(d(agent["hit_rate"]["mean_probability"]))} %"

    assert a3_row =~
             "Agent model-alpha-3 2 #{Format.decimal(d(a3["brier"]["score"]), 3)} ± #{Format.decimal(d(a3["brier"]["standard_error"]), 3)}"

    # One resolved call has no standard error: the row says so, never ± 0.
    assert operator_row =~ "#{Format.decimal(d("0.04"), 3)} ± —"
  end

  # User story (V2, ADR-0055 §5 "the due query"; board 02 part 2 ⑦):
  # As the operator checking which calls are due,
  # I want every prediction across securities in one list, newest first,
  # with status chips and the due query,
  # so that I find the calls the agent should look at without opening each
  # security.
  #
  # Acceptance criteria:
  # - "All predictions": made day and author, the security (a link to its
  #   Predictions tab) and the claim, the probability, the status (an
  #   unresolved call with its reason), the excess once resolved.
  # - Chips All, Open, Due, Resolved, Not resolved with their counts; Due
  #   is the API's `due_before` today; a chip puts `status` in the URL.
  # - The author and model chips narrow the list too.
  # - Under 560 px the list and the groups are two-line rows (app.css).
  test "the list across securities, with the status chips and the due query", %{conn: conn} do
    w = world()
    {:ok, view, _html} = live(conn, "/predictions")

    ids = fn view ->
      view
      |> element("#prediction-list-table tbody")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("tr[data-role='prediction-row']")
      |> Enum.flat_map(&Floki.attribute(&1, "data-prediction-id"))
    end

    assert ids.(view) ==
             Enum.map(
               [w.open, w.due, w.unresolved, w.hit_op, w.miss_index, w.miss_a3, w.hit_a2],
               &"#{&1.id}"
             )

    assert text_of(view, "#prediction-status-chips") ==
             "All 7 Open 2 Due 1 Resolved 4 Not resolved 1"

    row = text_of(view, "tr[data-prediction-id='#{w.miss_index.id}']")
    assert row =~ "#{Format.date(day(-98))} Agent · model-alpha-3"
    assert row =~ "Synthetic Gearworks AG"
    assert row =~ "Underperforms Synthetic Industrial Index by #{Format.date(day(-10))}"
    assert row =~ "55 % missed +7.0 pp"

    assert has_element?(
             view,
             "tr[data-prediction-id='#{w.miss_index.id}'] a[href='/securities/#{w.gear.id}?tab=predictions']"
           )

    assert text_of(view, "tr[data-prediction-id='#{w.unresolved.id}']") =~
             "not resolved no start close"

    view |> element("#prediction-chip-status-due") |> render_click()
    assert_patch(view, "/predictions?status=due")

    due_ids =
      api("/api/v1/predictions", %{"due_before" => Date.to_iso8601(Clock.today())})["predictions"]
      |> Enum.map(&"#{&1["id"]}")

    assert ids.(view) == due_ids
    assert due_ids == ["#{w.due.id}"]
    assert text_of(view, "tr[data-prediction-id='#{w.due.id}']") =~ "open · waiting for the close"

    {:ok, view, _html} = live(conn, "/predictions?author=operator&status=resolved")
    assert ids.(view) == ["#{w.hit_op.id}"]

    # The phone rows carry the same calls.
    assert has_element?(
             view,
             "#prediction-list-phone-rows li[data-prediction-id='#{w.hit_op.id}']"
           )

    css = File.read!("priv/static/app.css")

    assert css =~
             ~r/@media \(max-width: 560px\) \{[^}]*#prediction-list-table-wrap,\s*#prediction-groups-table-wrap \{\s*display: none;/s
  end

  # User story (V2, board 02 part 2; ADR-0055 §5):
  # As the operator before the first call is recorded,
  # I want the page to say there is none yet and how one is recorded,
  # so that an empty report is not mistaken for a broken one.
  #
  # Acceptance criteria:
  # - With no prediction stored: the empty state, no cards, no list.
  # - In German, the tab reads "Prognosen".
  test "the empty report says how a prediction is recorded", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/predictions")

    assert text_of(view, "[data-role='predictions-empty']") ==
             "No prediction is recorded yet. Predictions are recorded over the API or MCP."

    refute has_element?(view, "[data-role='prediction-brier']")
    refute has_element?(view, "#prediction-list-table")

    conn =
      PortfolixirWeb.PreferenceCookieHelpers.put_preference_cookie(
        conn,
        "portfolixir_locale",
        "de"
      )

    {:ok, view, _html} = live(conn, "/predictions")
    assert text_of(view, ".area-tab[href='/predictions']") == "Prognosen"
  end

  # --- Sprint 26 fix P begin ---
  # The privacy mode (P1) on the report (closing act, P-fix 2): a
  # probability is a percentage, the Brier score, its error, its reference,
  # the sharpness and a band's bounds are ratios; all stay, and the list
  # that crashed on a masked probability renders.

  # User story (P1 x V2, the closing act's finding 2):
  # As the operator who switched the privacy mode on before sharing my
  # screen,
  # I want the calibration report and the list to render as they do
  # without it,
  # so that the mode hides amounts, not the scores of my predictions.
  #
  # Acceptance criteria:
  # - /predictions renders with the mode on; its cards read the API's
  #   Brier score ± standard error, the 0.25 reference and the sharpness.
  # - Each listed call shows its probability ("70 %"), on the table row and
  #   the phone row, and the excess in percentage points stays.
  # - No figure of the page is the bar: it shows no amount.
  test "the report and the list render with the privacy mode on and keep their ratios",
       %{conn: conn} do
    %{hit_a2: hit} = world()

    {:ok, view, _html} =
      conn
      |> PortfolixirWeb.PreferenceCookieHelpers.put_preference_cookie("portfolixir_privacy", "on")
      |> live("/predictions")

    # The test process rendered the first page in the mode; the expected
    # figures are formatted outside it.
    PortfolixirWeb.PrivacyMode.put(false)

    assert_cards(view, api("/api/v1/predictions/calibration"))

    assert text_of(view, "tr[data-role='prediction-row'][data-prediction-id='#{hit.id}']") =~
             "70 %"

    assert text_of(view, "#prediction-list-phone-rows li[data-prediction-id='#{hit.id}']") =~
             "70 %"

    refute view |> element("main") |> render() =~ "pf-mask"
  end

  test "a model filter that is no text a model can be opens the unfiltered report",
       %{conn: conn} do
    world()

    # Invalid UTF-8 is refused before the page, by Plug's query parser.
    for raw <- ["%00", "model%01x", "a%0Ab", "a%E2%80%8Bb"] do
      {:ok, view, _html} = live(conn, "/predictions?model=" <> raw)

      assert text_of(view, "#prediction-calibration-title") ==
               "Calibration · 4 resolved · 2 open · 1 not resolved",
             raw
    end
  end

  # --- Sprint 26 fix P end ---

  # --- Sprint 26 fix D begin ---
  # The closing act's design critic and UAT persona on the report.

  # User story (closing act, design critic V2):
  # As the operator on Wealth's Predictions tab, on a desktop or a phone,
  # I want the author and model chips to keep the gutter the other Wealth
  # tabs' control rows keep,
  # so that the chips do not start at the screen's edge.
  #
  # Acceptance criteria:
  # - The chips sit in Wealth's control band (`.workspace-section
  #   .workspace-section--controls`), the band that carries the section's
  #   inline padding (16 px floor), as the view switcher does.
  test "the author and model chips sit in Wealth's control band", %{conn: conn} do
    world()
    {:ok, view, _html} = live(conn, "/predictions")

    assert has_element?(
             view,
             ".workspace-section.workspace-section--controls > #prediction-filters"
           )
  end

  # --- Sprint 26 fix D end ---
end
