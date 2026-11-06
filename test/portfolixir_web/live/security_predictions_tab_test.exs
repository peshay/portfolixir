defmodule PortfolixirWeb.SecurityPredictionsTabTest do
  # Sprint 26 V1 (F1, ADR-0055 §5; board
  # `ux-design-2026-11-06-sprint26-f1`, part 1): the security page's tab
  # "Predictions", the human view of the calls the agent and the operator
  # recorded on a security over the API or MCP. The tab reads through the
  # same context read the API answers from (`list_with_resolution/2`), so a
  # figure on the tab is the API's figure, formatted. Every name, date and
  # figure here is synthetic and relative to the instance's today.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [create_security!: 1, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Clock
  alias Portfolixir.Knowledge
  alias Portfolixir.Predictions
  alias PortfolixirWeb.Format

  defp day(offset), do: Date.add(Clock.today(), offset)

  defp benchmark!(name) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        currency_code: "EUR",
        asset_class: "etf",
        is_benchmark: true
      })

    security
  end

  # A call made `made` days from today (negative: in the past) through the
  # context's clock seam, never the API.
  defp predict!(actor, security, made, attrs) do
    {:ok, made_at} = DateTime.new(day(made), ~T[12:00:00.000000], "Etc/UTC")

    attrs =
      Map.merge(
        %{"security_id" => security.id, "direction" => "outperform", "probability" => "0.70"},
        attrs
      )

    {:ok, prediction} = Predictions.create_prediction(actor, attrs, now: made_at)
    prediction
  end

  defp world do
    agent = Actor.api_token_rw("research-agent")
    operator = Actor.owner_ui()

    security = create_security!(name: "Synthetic Gearworks AG", ticker: nil, currency: "EUR")
    index = benchmark!("Synthetic Industrial Index")

    # The security: 100 at -100 and -90, 105 at -80, 110 at -10.
    put_quotes!(security, [
      {day(-100), "100"},
      {day(-90), "100"},
      {day(-80), "105"},
      {day(-10), "110"}
    ])

    # The index: 200 at -100, 206 at -10; nothing near -80.
    put_quotes!(index, [{day(-100), "200"}, {day(-10), "206"}])

    {:ok, thesis} =
      Knowledge.append_note(Actor.api_token_rw(nil), %{
        security_id: security.id,
        author: "agent",
        kind: "thesis",
        body: "Synthetic thesis: the new line ramps up through the year.",
        source_quality: "primary",
        as_of: day(-100)
      })

    # Hit: +10 % against the index's +3 %, an excess of +7 pp.
    hit =
      predict!(agent, security, -100, %{
        "benchmark" => "security:#{index.id}",
        "resolves_on" => Date.to_iso8601(day(-10)),
        "model" => "model-alpha-2",
        "note_id" => thesis.id,
        "rationale" => "Synthetic rationale: the ramp-up is not in the index."
      })

    # Miss: an underperform call against rate:0 on a +10 % move.
    miss =
      predict!(agent, security, -90, %{
        "direction" => "underperform",
        "probability" => "0.55",
        "benchmark" => "rate:0",
        "resolves_on" => Date.to_iso8601(day(-10)),
        "model" => "model-alpha-3"
      })

    # Unresolved: the index has no close within 7 days of -80.
    unresolved =
      predict!(operator, security, -80, %{
        "probability" => "0.80",
        "benchmark" => "security:#{index.id}",
        "resolves_on" => Date.to_iso8601(day(-10))
      })

    # Open, its date passed two days ago, waiting for its end close.
    waiting =
      predict!(agent, security, -40, %{
        "benchmark" => "rate:0.02",
        "resolves_on" => Date.to_iso8601(day(-2)),
        "model" => "model-alpha-3"
      })

    # Open, 145 days left.
    open =
      predict!(agent, security, -2, %{
        "probability" => "0.65",
        "benchmark" => "security:#{index.id}",
        "resolves_on" => Date.to_iso8601(day(145)),
        "model" => "model-alpha-3"
      })

    %{
      security: security,
      index: index,
      thesis: thesis,
      hit: hit,
      miss: miss,
      unresolved: unresolved,
      waiting: waiting,
      open: open
    }
  end

  defp entry(view, prediction), do: view |> element("#prediction-#{prediction.id}") |> render()

  defp text(html), do: html |> Floki.parse_fragment!() |> Floki.text(sep: " ") |> squish()
  defp squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  # User story (V1, F1; ADR-0055 §5, board 02 part 1 ① to ⑦):
  # As the operator reading one security,
  # I want the calls recorded on it in a tab after Research, newest first,
  # each with its day, author and model, the claim, its probability and its
  # status,
  # so that I read what the agent and I said about it and how it turned out,
  # without the API.
  #
  # Acceptance criteria:
  # - The tab "Predictions" is the ninth of ten, right after "Research";
  #   a click opens its panel and puts `tab=predictions` in the URL.
  # - The entries are newest first, each headed by its status, "#id · day
  #   made · Agent · model" (or "Operator"), then the claim in one sentence
  #   beside its probability.
  # - Open: "open · 145 days left"; past its date and waiting for the
  #   close: "open · waiting for the close" with the day by which it is
  #   scored. No figure on an open or unresolved call.
  # - Hit and miss show the return, the benchmark return, the excess in pp
  #   (sign-coloured) and the dates of the closes used; "missed" is muted
  #   (`badge--retired`), never red; "hit" takes the intact thesis outline.
  # - Unresolved names its reason as a word and as a sentence.
  # - The rationale and the research entry the call belongs to, linked.
  test "the tab lists the security's predictions, newest first, with their status",
       %{conn: conn} do
    w = world()
    {:ok, view, _html} = live(conn, "/securities/#{w.security.id}?tab=research")

    tabs =
      view
      |> element("#detail-pane-tabs")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("button[role=tab]")
      |> Enum.map(&Floki.attribute(&1, "phx-value-tab"))
      |> List.flatten()

    assert Enum.drop(tabs, 7) == ["research", "predictions", "events"]

    view |> element("#detail-tab-predictions") |> render_click()
    assert_patch(view, "/securities/#{w.security.id}?tab=predictions")

    assert has_element?(
             view,
             ~s(#detail-tab-panel-predictions[role="tabpanel"][aria-labelledby="detail-tab-predictions"])
           )

    ids =
      view
      |> element("[data-role='prediction-timeline']")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("li[data-role='prediction-entry']")
      |> Enum.flat_map(&Floki.attribute(&1, "id"))

    assert ids ==
             Enum.map([w.open, w.waiting, w.unresolved, w.miss, w.hit], &"prediction-#{&1.id}")

    open = entry(view, w.open)
    assert open =~ "prediction-entry--open"
    assert open =~ ~s(class="badge badge--neutral")
    assert text(open) =~ "open · 145 days left"

    assert text(open) =~
             "##{w.open.id} · #{Format.date(day(-2))} · Agent · model-alpha-3"

    assert text(open) =~
             "Outperforms Synthetic Industrial Index by #{Format.date(day(145))} Probability 65 %"

    refute open =~ "prediction-entry__facts"

    waiting = entry(view, w.waiting)
    assert text(waiting) =~ "open · waiting for the close"
    assert text(waiting) =~ "Outperforms 2.0 % a year by #{Format.date(day(-2))}"

    assert text(waiting) =~
             "The resolution day has passed; it is scored once a close from #{Format.date(day(-2))} on is in, at the latest on #{Format.date(day(5))}."

    hit = entry(view, w.hit)
    assert hit =~ "prediction-entry--hit"
    assert hit =~ ~s(class="badge badge--thesis-intact")
    assert text(hit) =~ "Hit"
    assert text(hit) =~ "Return +10.0 %"
    assert text(hit) =~ "Benchmark return +3.0 %"
    assert text(hit) =~ "Excess +7.0 pp"
    assert hit =~ ~s(class="is-positive")
    assert text(hit) =~ "Closes #{Format.date(day(-100))} → #{Format.date(day(-10))}"
    assert text(hit) =~ "Synthetic rationale: the ramp-up is not in the index."
    assert text(hit) =~ "Research ##{w.thesis.id} · Thesis"

    assert hit =~
             ~s(href="/securities/#{w.security.id}?tab=research#research-entry-#{w.thesis.id}")

    miss = entry(view, w.miss)
    assert miss =~ "prediction-entry--miss"
    assert miss =~ ~s(class="badge badge--retired")
    refute miss =~ "badge--danger"
    assert text(miss) =~ "missed"
    assert text(miss) =~ "Falls by #{Format.date(day(-10))}"
    # The excess keeps its sign colour beside "missed" (board, call 5).
    assert text(miss) =~ "Excess +10.0 pp"

    unresolved = entry(view, w.unresolved)
    assert unresolved =~ "prediction-entry--unresolved"
    assert unresolved =~ ~s(class="badge badge--undetermined")
    assert text(unresolved) =~ "##{w.unresolved.id} · #{Format.date(day(-80))} · Operator"
    assert text(unresolved) =~ "not resolved"

    assert text(unresolved) =~
             "no benchmark close: The benchmark has no close on or up to 7 days before #{Format.date(day(-80))} or #{Format.date(day(-10))}."

    refute unresolved =~ "prediction-entry__facts"
  end

  # User story (V1, ADR-0055 §5: one derivation, read at every surface):
  # As the operator checking a figure the agent quotes,
  # I want the tab to show the figure the API answers for the same call,
  # so that the screen and the agent never disagree.
  #
  # Acceptance criteria:
  # - The tab's return, benchmark return and excess are the API's
  #   `resolution` figures for the same prediction, formatted.
  test "a figure on the tab is the API's figure for the same prediction", %{conn: conn} do
    w = world()

    data =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")
      |> get("/api/v1/predictions/#{w.hit.id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["resolution"]["status"] == "resolved"

    {:ok, view, _html} = live(conn, "/securities/#{w.security.id}?tab=predictions")
    hit = view |> entry(w.hit) |> text()

    for {label, value} <- [
          {"Return", data["resolution"]["security"]["return"]},
          {"Benchmark return", data["resolution"]["benchmark"]["return"]}
        ] do
      assert hit =~ "#{label} #{Format.signed_percent(Decimal.new(value))} %"
    end

    assert hit =~ "Excess #{Format.signed_percent(Decimal.new(data["resolution"]["excess"]))} pp"
  end

  # User story (V1, board 02 part 1 ②, the ⓘ):
  # As the operator wondering how a call is scored,
  # I want the rule behind the tab's ⓘ, in sentences,
  # so that I can check a status without reading the ADR.
  #
  # Acceptance criteria:
  # - The line says the calls are newest first and that none is changed or
  #   deleted, and ends in the ⓘ.
  # - The ⓘ states permanence, the reading at read in EUR, the start and
  #   end close, the staleness bound from the read's computation_basis
  #   (7 days), the excess rule, price only, and that calls are recorded
  #   over the API or MCP.
  test "the line and its ⓘ carry the computation basis in sentences", %{conn: conn} do
    w = world()
    {:ok, view, _html} = live(conn, "/securities/#{w.security.id}?tab=predictions")

    basis = view |> element("[data-role='predictions-basis']") |> render() |> text()

    assert basis =~
             "Recorded predictions on this security, newest first. None is ever changed or deleted."

    tip =
      view |> element("[data-role='predictions-basis'] [role='tooltip']") |> render() |> text()

    for sentence <- [
          "A prediction stays as it was made: it is never changed, withdrawn or deleted. A corrected prediction is a new one, and both count.",
          "It is scored at read from stored closes, both sides in EUR at the stored exchange rate of their day; no result is ever stored.",
          "A close more than 7 days before its date does not count; the prediction then stays unresolved, with its reason, and is never estimated.",
          "Price return only: distributions count on neither side.",
          "Predictions are recorded over the API or MCP."
        ] do
      assert tip =~ sentence
    end
  end

  # User story (V1, board 02 part 1, the empty state):
  # As the operator opening a security nobody has made a call on,
  # I want the tab to say so and how one is recorded,
  # so that an empty tab is not mistaken for a failed read.
  #
  # Acceptance criteria:
  # - "No prediction is recorded for this security. Predictions are
  #   recorded over the API or MCP." and no timeline.
  test "the empty state says how a prediction is recorded", %{conn: conn} do
    security = create_security!(name: "Synthetic Freight Inc", ticker: nil, currency: "USD")
    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=predictions")

    assert view |> element("#detail-tab-panel-predictions .empty-state") |> render() |> text() ==
             "No prediction is recorded for this security. Predictions are recorded over the API or MCP."

    refute has_element?(view, "[data-role='prediction-timeline']")
  end

  # User story (V1, board 02 part 1, judgment call 9; UX-DR27):
  # As the operator reading a resolved call on a phone,
  # I want its four facts two abreast, not stacked one per line,
  # so that the figures stay together.
  #
  # Acceptance criteria:
  # - Under 480 px the shipped facts grid stacks to one column; the
  #   prediction's facts keep two columns under 560 px (app.css).
  test "a resolved call's facts stay two abreast at phone width" do
    css = File.read!("priv/static/app.css")

    assert css =~
             ~r/@media \(max-width: 560px\) \{[^}]*\.research-entry__facts\.prediction-entry__facts \{\s*grid-template-columns: repeat\(2, minmax\(0, 1fr\)\);/s

    assert css =~
             ~r/\.research-entry\.prediction-entry--hit \{\s*border-left-color: var\(--color-positive\);/s
  end

  defp german(conn),
    do:
      PortfolixirWeb.PreferenceCookieHelpers.put_preference_cookie(
        conn,
        "portfolixir_locale",
        "de"
      )

  defp unflag(view, security) do
    render_click(view, "row_action", %{"action" => "benchmark", "id" => "#{security.id}"})
    view |> element("#securities-action-result-status") |> render() |> text()
  end

  # User story (V1, #1365 line 2; board 02 part 3 ②, judgment call 8):
  # As the operator removing a security's benchmark flag,
  # I want the note to say how many recorded predictions keep measuring
  # against it, and that a new one can no longer name it,
  # so that I do not believe the flag rewrites recorded calls.
  #
  # Acceptance criteria:
  # - With predictions measuring against it: "… is no longer a benchmark.
  #   3 recorded predictions keep measuring against it; a new prediction
  #   can no longer name it as its benchmark." (1: "1 recorded prediction
  #   keeps …"); in German as the board writes it.
  # - Without: the shipped sentence alone.
  test "unflagging a benchmark counts the predictions that keep measuring against it",
       %{conn: conn} do
    w = world()
    quiet = benchmark!("Synthetic Quiet Index")

    {:ok, view, _html} = live(conn, "/securities")

    assert unflag(view, w.index) =~
             "Synthetic Industrial Index is no longer a benchmark. 3 recorded predictions keep measuring against it; a new prediction can no longer name it as its benchmark."

    refute Catalog.get_security(w.index.id).is_benchmark

    note = unflag(view, quiet)
    assert note =~ "Synthetic Quiet Index is no longer a benchmark"
    refute note =~ "prediction"

    # German, and the singular: one more benchmark with one call against it.
    single = benchmark!("Synthetic Single Index")

    predict!(Actor.api_token_rw("research-agent"), w.security, -2, %{
      "benchmark" => "security:#{single.id}",
      "resolves_on" => Date.to_iso8601(day(30)),
      "model" => "model-alpha-3"
    })

    {:ok, view, _html} = live(german(conn), "/securities")

    assert unflag(view, single) =~
             "Synthetic Single Index ist keine Benchmark mehr. 1 festgehaltene Prognose misst weiter an ihr; eine neue Prognose kann sie nicht mehr als Benchmark nennen."
  end
end
