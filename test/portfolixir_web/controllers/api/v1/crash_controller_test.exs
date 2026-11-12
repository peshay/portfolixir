defmodule PortfolixirWeb.Api.V1.CrashControllerTest do
  # Sprint 29 C5 (FR-54, #1421; ADR-0058 §9): the crash windows over the API —
  # GET /api/v1/crashes, GET /api/v1/crashes/:key/rankings, and the writes
  # PUT /api/v1/crashes/:key, POST /api/v1/crashes and DELETE
  # /api/v1/crashes/:key. Every name and figure is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Crashes
  alias Portfolixir.Journal
  alias Portfolixir.Settings

  defp authed(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp path(key), do: "/api/v1/crashes/" <> URI.encode_www_form(key)

  defp choose!(security) do
    {:ok, _security} = Settings.set_crash_benchmark(Actor.owner_ui(), security && security.id)
  end

  # A fall of 30 % from 19 February to 23 March 2020, recovered on 18 August,
  # and two securities priced on both ends of it.
  defp crash_world! do
    index = create_security!(name: "Synthetic Crash Index", ticker: "SCI")

    put_quotes!(index, [
      {~D[2020-02-19], "100"},
      {~D[2020-03-23], "70"},
      {~D[2020-08-18], "101"}
    ])

    faller = create_security!(name: "Synthetic Faller", ticker: "SFL", isin: "DE000CRSH101")
    put_quotes!(faller, [{~D[2020-02-19], "50"}, {~D[2020-03-23], "40"}])

    riser = create_security!(name: "Synthetic Riser", ticker: "SRS", isin: "DE000CRSH119")
    put_quotes!(riser, [{~D[2020-02-19], "20"}, {~D[2020-03-23], "22"}, {~D[2020-06-23], "30"}])

    young = create_security!(name: "Synthetic Young", ticker: "SYG")
    put_quotes!(young, [{~D[2020-03-20], "9"}])

    choose!(index)
    %{index: index, faller: faller, riser: riser, key: "d:#{index.id}:2020-02-19"}
  end

  defp manual!(attrs \\ %{}) do
    {:ok, window} =
      Crashes.create_manual_window(
        Actor.owner_ui(),
        Map.merge(
          %{"name" => "Synthetic Spring", "start" => "2020-02-19", "trough" => "2020-03-23"},
          attrs
        )
      )

    window
  end

  # No float anywhere: every financial figure travels as a string.
  defp floats(value) when is_float(value), do: [value]
  defp floats(%{} = map), do: map |> Map.values() |> Enum.flat_map(&floats/1)
  defp floats(list) when is_list(list), do: Enum.flat_map(list, &floats/1)
  defp floats(_value), do: []

  # User story (ADR-0058 §1, §3, §9):
  # As the agent the operator runs,
  # I want one read of the crash windows — the detected ones with their
  # names, the manual ones, the names that lost their window, the crash
  # benchmark and the rule's basis,
  # so that I read the same windows the operator sees and know how they
  # were found.
  #
  # Acceptance criteria:
  # - Without a crash benchmark: detected [] with reason no_crash_benchmark,
  #   benchmark null; manual windows are listed regardless, kind manual,
  #   dates ISO, the creating token named.
  # - With one: each detected window with its key, kind detected, its name,
  #   its dates, its closes and decline as decimal strings, provisional,
  #   recovered_on and max_gap_days; the benchmark with its standing.
  # - A name given for another benchmark is listed under unmatched_names.
  # - The computation basis names the rule and its threshold.
  test "lists the detected and manual windows and the unmatched names", %{conn: conn} do
    window = manual!()

    assert %{"data" => data} = conn |> authed() |> get("/api/v1/crashes") |> json_response(200)

    assert %{
             "benchmark" => nil,
             "reason" => "no_crash_benchmark",
             "detected" => [],
             "unmatched_names" => [],
             "computation_basis" => %{"rule" => "peak_trough_v1", "threshold" => "0.10"}
           } = data

    manual_key = "m:#{window.id}"

    assert [
             %{
               "key" => ^manual_key,
               "kind" => "manual",
               "name" => "Synthetic Spring",
               "start" => "2020-02-19",
               "trough" => "2020-03-23",
               "author" => "operator",
               "created_at" => created_at
             }
           ] = data["manual"]

    assert {:ok, _at, 0} = DateTime.from_iso8601(created_at)

    %{index: index, key: key} = crash_world!()
    {:ok, _name} = Crashes.name_window(Actor.owner_ui(), key, %{"name" => "Synthetic Covid Fall"})

    assert %{"data" => data} = conn |> authed() |> get("/api/v1/crashes") |> json_response(200)
    index_id = index.id

    assert %{
             "reason" => nil,
             "benchmark" => %{
               "id" => ^index_id,
               "name" => "Synthetic Crash Index",
               "currency_code" => "EUR",
               "benchmark_security" => "unheld"
             },
             "detected" => [
               %{
                 "key" => ^key,
                 "kind" => "detected",
                 "name" => "Synthetic Covid Fall",
                 "start" => "2020-02-19",
                 "trough" => "2020-03-23",
                 "peak_close" => "100",
                 "trough_close" => "70",
                 "decline" => "-0.3",
                 "recovered_on" => "2020-08-18",
                 "provisional" => false,
                 "max_gap_days" => 148
               }
             ],
             "computation_basis" => %{"currency" => "EUR", "gaps" => gaps}
           } = data

    assert gaps =~ "max_gap_days"
    assert floats(data) == []

    other = create_security!(name: "Synthetic Other Index", ticker: "SOI")
    put_quotes!(other, [{~D[2021-01-04], "10"}])
    choose!(other)

    assert %{"data" => %{"detected" => [], "unmatched_names" => [unmatched]}} =
             conn |> authed() |> get("/api/v1/crashes") |> json_response(200)

    assert %{
             "key" => ^key,
             "name" => "Synthetic Covid Fall",
             "benchmark_security_id" => ^index_id,
             "benchmark_name" => "Synthetic Crash Index",
             "start" => "2020-02-19",
             "for_current_benchmark" => false
           } = unmatched
  end

  # Acceptance criteria (ADR-0058 §9; the closed reads of ADR-0056 §9):
  # - The list takes no parameter: one it is sent answers 422 naming it.
  test "the list read refuses a parameter it does not take", %{conn: conn} do
    assert %{"errors" => %{"benchmark" => [message]}} =
             conn |> authed() |> get("/api/v1/crashes?benchmark=security:1") |> json_response(422)

    assert message =~ "is unknown"
  end

  # User story (ADR-0058 §5, §6, §9; amendment F2, F3):
  # As the agent the operator runs,
  # I want a crash window's lists over the API, each figure a decimal string
  # beside the crash benchmark's, with the basis that produced them,
  # so that I can quote who fell, who rose and who came back, and say how.
  #
  # Acceptance criteria:
  # - losers (the default) and winners answer the window, the list, the
  #   universe, the limit applied, both ends of the span, the entries
  #   ranked with their EUR returns, the benchmark's return and the
  #   difference in points as strings, the answered and unanswered counts
  #   and the computation basis (survivorship named).
  # - include_unanswered=true lists the securities without an answer with
  #   their reason; rebounders answer days_back in calendar days.
  # - No figure is a JSON number.
  test "ranks a window's lists with the benchmark's return beside each", %{conn: conn} do
    %{index: index, key: key} = crash_world!()

    assert %{"data" => losers} =
             conn |> authed() |> get(path(key) <> "/rankings") |> json_response(200)

    index_id = index.id

    assert %{
             "window" => %{"key" => ^key, "kind" => "detected", "start" => "2020-02-19"},
             "list" => "losers",
             "universe" => "catalogue",
             "limit" => 8,
             "provisional" => false,
             "from" => "2020-02-19",
             "to" => "2020-03-23",
             "benchmark" => %{"id" => ^index_id, "benchmark_security" => "unheld"},
             "reference" => %{"return" => "-0.3", "security_id" => ^index_id},
             "reference_reason" => nil,
             "answered" => 2,
             "unanswered" => %{
               "no_close_at_start" => 1,
               "no_close_at_end" => 0,
               "no_fx_rate" => 0
             },
             "entries" => [faller_row, riser_row],
             "computation_basis" => %{
               "rule" => "peak_trough_v1",
               "survivorship" => survivorship,
               "days_back_unit" => "calendar_days",
               "benchmark" => %{"id" => ^index_id}
             }
           } = losers

    refute Map.has_key?(losers, "unanswered_entries")
    assert survivorship =~ "still tracked"

    assert %{
             "rank" => 1,
             "security" => %{"name" => "Synthetic Faller", "isin" => "DE000CRSH101"},
             "return" => "-0.2",
             "benchmark_return" => "-0.3",
             "vs_benchmark_pp" => "10",
             "start" => %{"date" => "2020-02-19", "close" => "50"},
             "held" => false
           } = faller_row

    assert %{"rank" => 2, "return" => "0.1", "vs_benchmark_pp" => "40"} = riser_row
    assert floats(losers) == []

    assert %{"data" => winners} =
             conn
             |> authed()
             |> get(path(key) <> "/rankings?list=winners&limit=1&include_unanswered=true")
             |> json_response(200)

    assert %{
             "list" => "winners",
             "limit" => 1,
             "entries" => [%{"security" => %{"name" => "Synthetic Riser"}}],
             "unanswered_entries" => [
               %{"security" => %{"name" => "Synthetic Young"}, "reason" => "no_close_at_start"}
             ]
           } = winners

    assert %{"data" => rebounders} =
             conn
             |> authed()
             |> get(path(key) <> "/rankings?list=rebounders&universe=catalogue")
             |> json_response(200)

    assert %{
             "list" => "rebounders",
             "span_end" => "2020-06-23",
             "entries" => [%{"security" => %{"name" => "Synthetic Riser"}} = rebound | _rest]
           } = rebounders

    assert %{"return" => "0.5", "days_back" => 0, "not_yet" => false, "low" => low} = rebound
    assert %{"date" => "2020-02-19", "close" => "20"} = low
    assert floats(rebounders) == []
  end

  # The closing act (#1421): universe=held, today's holdings in any depot,
  # what the screen's „Im Depot“ lists when no view is chosen.
  test "universe=held ranks the securities held today in any depot", %{conn: conn} do
    %{key: key, riser: riser} = crash_world!()
    world = base_world(name: "Synthetic Held World")
    buy!(world, riser, quantity: "1", price: "20", date: ~D[2020-01-02])

    assert %{"data" => held} =
             conn
             |> authed()
             |> get(path(key) <> "/rankings?universe=held")
             |> json_response(200)

    assert %{
             "universe" => "held",
             "answered" => 1,
             "entries" => [%{"security" => %{"name" => "Synthetic Riser"}, "held" => true}],
             "computation_basis" => %{"universe" => universe}
           } = held

    assert universe =~ "any depot"
  end

  # Acceptance criteria (ADR-0058 §9; the repo's limit contract, #771):
  # - A limit above 50 is capped and echoed; zero or text answers 422.
  # - An unknown list, universe or include_unanswered value answers 422
  #   naming it; an unknown parameter answers 422 naming it.
  # - A key that names no window, in either spelling or none, answers 404;
  #   a view that does not exist answers 404.
  test "refuses a bad parameter with 422 and an unknown window or view with 404",
       %{conn: conn} do
    %{key: key} = crash_world!()
    rankings = path(key) <> "/rankings"

    assert %{"data" => %{"limit" => 50}} =
             conn |> authed() |> get(rankings <> "?limit=500") |> json_response(200)

    for {query, field} <- [
          {"list=fallers", "list"},
          {"universe=holdings", "universe"},
          {"universe=view:01", "universe"},
          {"limit=0", "limit"},
          {"limit=ten", "limit"},
          {"include_unanswered=yes", "include_unanswered"},
          {"lists=winners", "lists"}
        ] do
      assert %{"errors" => %{^field => [_message]}} =
               conn |> authed() |> get(rankings <> "?" <> query) |> json_response(422),
             query
    end

    for unknown <- ["d:1:2020-02-19", "m:999999", "m:01", "crash", key <> "x"] do
      assert %{"errors" => %{"detail" => "not found"}} =
               conn |> authed() |> get(path(unknown) <> "/rankings") |> json_response(404),
             unknown
    end

    assert %{"errors" => %{"detail" => "not found"}} =
             conn
             |> authed()
             |> get(rankings <> "?universe=view:999999")
             |> json_response(404)
  end

  # User story (ADR-0058 §3, §4, §9; amendment F1):
  # As the agent the operator runs,
  # I want to name a detected window, draw, edit and delete a manual one,
  # and make a name that lost its window into a manual one with a trough I
  # give, each with my own token,
  # so that every write the screen offers is mine to make as well.
  #
  # Acceptance criteria:
  # - POST {"window": {name, start, trough}} answers 201 with the manual
  #   window (key m:<id>, kind manual, the creating token).
  # - PUT on a detected key with {"window": {name}} names it, 200; on a
  #   manual key edits its fields, 200.
  # - POST {"window": {from_name, trough}} makes an unmatched name a manual
  #   window from its stored start, 201, and the name is gone.
  # - DELETE on a detected key removes its name, on a manual key the
  #   window, 200 with what was deleted; again, 404.
  # - Every write is journaled under the request's token.
  test "names, draws, edits and deletes windows, journaled under the token",
       %{conn: conn} do
    %{key: key} = crash_world!()

    assert %{"data" => created} =
             conn
             |> authed()
             |> post(
               "/api/v1/crashes",
               Jason.encode!(%{
                 window: %{name: "Synthetic War Leg", start: "2020-03-02", trough: "2020-03-16"}
               })
             )
             |> json_response(201)

    assert %{
             "key" => "m:" <> _id = manual_key,
             "kind" => "manual",
             "name" => "Synthetic War Leg",
             "start" => "2020-03-02",
             "trough" => "2020-03-16",
             "author" => "agent"
           } = created

    assert %{"data" => %{"name" => "Synthetic Late Leg", "trough" => "2020-03-18"}} =
             conn
             |> authed()
             |> put(
               path(manual_key),
               Jason.encode!(%{window: %{name: "Synthetic Late Leg", trough: "2020-03-18"}})
             )
             |> json_response(200)

    assert %{"data" => %{"key" => ^key, "kind" => "detected", "name" => "Synthetic Covid Fall"}} =
             conn
             |> authed()
             |> put(path(key), Jason.encode!(%{window: %{name: "Synthetic Covid Fall"}}))
             |> json_response(200)

    assert %{"data" => %{"key" => ^key, "deleted" => "name", "name" => "Synthetic Covid Fall"}} =
             conn |> authed() |> delete(path(key)) |> json_response(200)

    assert %{"errors" => %{"detail" => "not found"}} =
             conn |> authed() |> delete(path(key)) |> json_response(404)

    assert %{"data" => %{"key" => ^manual_key, "deleted" => "manual_window"}} =
             conn |> authed() |> delete(path(manual_key)) |> json_response(200)

    assert %{"errors" => %{"detail" => "not found"}} =
             conn |> authed() |> delete(path(manual_key)) |> json_response(404)

    # A name for another benchmark's window is unmatched; it becomes a
    # manual window from its stored start and the trough given.
    {:ok, _name} = Crashes.name_window(Actor.owner_ui(), key, %{"name" => "Synthetic Old Name"})
    other = create_security!(name: "Synthetic Other Index", ticker: "SOI")
    put_quotes!(other, [{~D[2021-01-04], "10"}])
    choose!(other)

    assert %{"data" => made} =
             conn
             |> authed()
             |> post(
               "/api/v1/crashes",
               Jason.encode!(%{window: %{from_name: key, trough: "2020-03-23"}})
             )
             |> json_response(201)

    assert %{"kind" => "manual", "name" => "Synthetic Old Name", "start" => "2020-02-19"} = made
    assert Crashes.list_windows().unmatched_names == []

    resources =
      Journal.list_entries(actor_type: :api_token_rw)
      |> Enum.map(&{&1.resource_type, &1.operation})
      |> Enum.reject(&(elem(&1, 0) == "setting"))

    assert {"crash_manual_window", :create} in resources
    assert {"crash_manual_window", :update} in resources
    assert {"crash_manual_window", :delete} in resources
    assert {"crash_window_name", :create} in resources
    assert {"crash_window_name", :delete} in resources
  end

  # Acceptance criteria (ADR-0058 §4, §9; F1):
  # - A field the write does not take answers 422 naming it, inside the
  #   wrapper and beside it; a wrapper that is not an object 422 naming it.
  # - A manual window under §4's rules: a trough before the start, a date
  #   in the future, a name over 80 characters answer 422 naming the field.
  # - A detected key takes only a name: start answers 422 naming it.
  # - from_name naming no stored name, or a name whose window the rule still
  #   detects, answers 422 naming from_name; start beside it 422 naming it.
  # - PUT or DELETE on a key that names nothing answers 404.
  # - Nothing is written on a refusal.
  test "refuses an unknown field, a bad window and an unknown key", %{conn: conn} do
    %{key: key} = crash_world!()
    {:ok, _name} = Crashes.name_window(Actor.owner_ui(), key, %{"name" => "Synthetic Kept Name"})

    post_window = fn body ->
      conn |> authed() |> post("/api/v1/crashes", Jason.encode!(body))
    end

    good = %{name: "Synthetic Leg", start: "2020-03-02", trough: "2020-03-16"}

    assert %{"errors" => %{"kind" => [inside]}} =
             post_window.(%{window: Map.put(good, :kind, "detected")}) |> json_response(422)

    assert inside =~ "is unknown"

    assert %{"errors" => %{"name" => [_beside]}} =
             post_window.(Map.put(%{window: good}, :name, "x")) |> json_response(422)

    assert %{"errors" => %{"window" => ["must be an object"]}} =
             post_window.(%{window: "spring"}) |> json_response(422)

    assert %{"errors" => %{"trough" => _}} =
             post_window.(%{window: %{good | trough: "2020-03-01"}}) |> json_response(422)

    assert %{"errors" => %{"trough" => _}} =
             post_window.(%{window: %{good | trough: "2999-01-01"}}) |> json_response(422)

    assert %{"errors" => %{"name" => _}} =
             post_window.(%{window: %{good | name: String.duplicate("x", 81)}})
             |> json_response(422)

    assert %{"errors" => %{"from_name" => [still_detected]}} =
             post_window.(%{window: %{from_name: key, trough: "2020-03-23"}})
             |> json_response(422)

    assert still_detected =~ "still detects"

    assert %{"errors" => %{"from_name" => _}} =
             post_window.(%{window: %{from_name: 12, trough: "2020-03-23"}}) |> json_response(422)

    assert %{"errors" => %{"from_name" => _}} =
             post_window.(%{window: %{from_name: "d:1:2020-02-19", trough: "2020-03-23"}})
             |> json_response(422)

    assert %{"errors" => %{"start" => _}} =
             post_window.(%{window: %{from_name: key, trough: "2020-03-23", start: "2020-02-19"}})
             |> json_response(422)

    assert %{"errors" => %{"start" => [only_name]}} =
             conn
             |> authed()
             |> put(path(key), Jason.encode!(%{window: %{name: "x", start: "2020-02-18"}}))
             |> json_response(422)

    assert only_name =~ "takes only name"

    for unknown <- ["d:1:2020-02-19", "m:999999", "crash"] do
      assert %{"errors" => %{"detail" => "not found"}} =
               conn
               |> authed()
               |> put(path(unknown), Jason.encode!(%{window: %{name: "x"}}))
               |> json_response(404),
             unknown

      assert %{"errors" => %{"detail" => "not found"}} =
               conn |> authed() |> delete(path(unknown)) |> json_response(404),
             unknown
    end

    assert %{manual: [], detected: [%{name: "Synthetic Kept Name"}]} = Crashes.list_windows()
    assert Journal.list_entries(actor_type: :api_token_rw) == []
  end

  test "every crash route requires the token", %{conn: conn} do
    for {verb, route} <- [
          {:get, "/api/v1/crashes"},
          {:get, "/api/v1/crashes/m:1/rankings"},
          {:post, "/api/v1/crashes"},
          {:put, "/api/v1/crashes/m:1"},
          {:delete, "/api/v1/crashes/m:1"}
        ] do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> dispatch(@endpoint, verb, route, %{})

      assert conn.status == 401, "#{verb} #{route}"
    end
  end
end
