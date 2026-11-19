defmodule PortfolixirWeb.ApiV1MoversTest do
  # Sprint 30 Lane T, T2 (FR-59, idea I32; ADR-0061 §9): the tops and flops
  # over the API, `GET /api/v1/views/:view_id/movers` and `GET
  # /api/v1/movers`, each the answer of
  # `Portfolixir.Portfolios.Performance.Movers.read/3` for the same window,
  # every figure a string and every date ISO 8601.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Clock
  alias Portfolixir.Portfolios.Performance.Movers

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    today = Clock.today()
    world = base_world(name: "Movers API")
    deposit!(world, "10000", Date.add(today, -60))

    # Three securities priced every day of the last 40, each on its own
    # slope, so every short window has a figure and the halves are 2 and 1;
    # a fourth has no close at all and is counted, never ranked.
    climber = create_security!(name: "Movers Climber", ticker: "MVC")
    steady = create_security!(name: "Movers Steady", ticker: "MVS")
    faller = create_security!(name: "Movers Faller", ticker: "MVF")
    unpriced = create_security!(name: "Movers Unpriced", ticker: "MVU")

    for {security, step} <- [{climber, "1.5"}, {steady, "0.25"}, {faller, "-0.75"}] do
      put_quotes!(
        security,
        for(back <- 40..0//-1, do: {Date.add(today, -back), price(step, 40 - back)})
      )
    end

    for security <- [climber, steady, faller, unpriced],
        do: buy!(world, security, quantity: "3", price: "100", date: Date.add(today, -30))

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Movers view"})

    %{
      conn: conn,
      today: today,
      view: view,
      climber: climber,
      steady: steady,
      faller: faller,
      unpriced: unpriced
    }
  end

  # 100 + step × day: a close that moves by `step` every day.
  defp price(step, day), do: step |> Decimal.new() |> Decimal.mult(day) |> Decimal.add(100)

  defp get_data(conn, path, status \\ 200),
    do: conn |> get(path) |> json_response(status) |> then(&(&1["data"] || &1))

  defp errors(conn, path), do: conn |> get(path) |> json_response(422) |> Map.fetch!("errors")

  defp string(%Decimal{} = decimal),
    do: decimal |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp iso(nil), do: nil
  defp iso(%Date{} = date), do: Date.to_iso8601(date)

  # The API's half against the read's, entry by entry and in order: the same
  # security, the same figure to the last digit, the same dates.
  defp assert_same_price_half(api, read) do
    assert length(api) == length(read)

    for {from_api, from_read} <- Enum.zip(api, read) do
      assert from_api["security"]["id"] == from_read.security.id
      assert from_api["security"]["name"] == from_read.security.name
      assert from_api["return"] == string(from_read.return)
      assert from_api["start"]["date"] == iso(from_read.start.date)
      assert from_api["end"]["date"] == iso(from_read.end.date)
      assert from_api["start"]["close"] == string(from_read.start.close)
      assert from_api["end"]["close"] == string(from_read.end.close)
      assert from_api["start"]["eur_value"] == string(from_read.start.eur_value)
      assert from_api["end"]["eur_value"] == string(from_read.end.eur_value)
    end
  end

  defp assert_same_contribution_half(api, read) do
    assert length(api) == length(read)

    for {from_api, from_read} <- Enum.zip(api, read) do
      assert from_api["security"]["id"] == from_read.security.id

      for term <- ~w(contribution start_value end_value net_flows income costs)a do
        assert from_api[Atom.to_string(term)] == string(Map.fetch!(from_read, term)),
               Atom.to_string(term)
      end

      assert from_api["held_at_end"] == from_read.held_at_end
      assert from_api["unvalued_days"] == from_read.unvalued_days
    end
  end

  defp assert_same_answer(api, read) do
    assert api["view_id"] == read.view_id
    assert api["window"] == read.window
    assert api["start_on"] == iso(read.start_on)
    assert api["end_on"] == iso(read.end_on)
    assert api["limit"] == read.limit

    for side <- [:price_return, :contribution] do
      from_api = api[Atom.to_string(side)]
      from_read = Map.fetch!(read, side)

      assert from_api["answered"] == from_read.answered

      assert from_api["unanswered"] ==
               Map.new(from_read.unanswered, fn {reason, n} -> {Atom.to_string(reason), n} end)

      assert from_api["computation_basis"]["window"]["key"] == read.window
      assert Map.has_key?(from_api["computation_basis"], "reference")
      assert from_api["computation_basis"]["reference"] == nil
    end

    assert_same_price_half(api["price_return"]["highest"], read.price_return.highest)
    assert_same_price_half(api["price_return"]["lowest"], read.price_return.lowest)
    assert_same_contribution_half(api["contribution"]["highest"], read.contribution.highest)
    assert_same_contribution_half(api["contribution"]["lowest"], read.contribution.lowest)
  end

  # User story (FR-59, ADR-0061 §9):
  # As the operator's agent asking what moved this week in a view, or in
  # everything,
  # I want both rankings over the API, every figure as the read derives it,
  # so that I tell the operator the same tops and flops the screen shows.
  #
  # Acceptance criteria:
  # - GET /api/v1/views/:view_id/movers and GET /api/v1/movers answer
  #   view_id, window, start_on, end_on, limit, price_return and
  #   contribution, each ranking with highest, lowest, answered, unanswered
  #   and computation_basis; the view read echoes its view.
  # - For the same window every figure equals Movers.read/3's to the last
  #   digit, as a string; every date is ISO 8601.
  # - include_unanswered=true adds unanswered_entries with each reason.
  test "both reads answer Movers.read/3's figures, as strings", %{
    conn: conn,
    view: view,
    today: today,
    climber: climber,
    steady: steady,
    faller: faller,
    unpriced: unpriced
  } do
    for window <- Movers.windows() do
      view_api = get_data(conn, "/api/v1/views/#{view.id}/movers?window=#{window}")
      assert {:ok, view_read} = Movers.read(view.id, window, today: today)
      assert_same_answer(view_api, view_read)
      assert view_api["view"]["id"] == view.id
      refute Map.has_key?(view_api["price_return"], "unanswered_entries")

      total_api = get_data(conn, "/api/v1/movers?window=#{window}")
      assert {:ok, total_read} = Movers.read(nil, window, today: today)
      assert_same_answer(total_api, total_read)
      assert total_api["view_id"] == nil
      refute Map.has_key?(total_api, "view")
    end

    # The week by hand: three securities answered, split two and one, the
    # one without a close counted under its reason.
    week = get_data(conn, "/api/v1/movers?window=week&include_unanswered=true")

    assert Enum.map(week["price_return"]["highest"], & &1["security"]["id"]) == [
             climber.id,
             steady.id
           ]

    assert Enum.map(week["price_return"]["lowest"], & &1["security"]["id"]) == [faller.id]
    assert week["price_return"]["answered"] == 3
    assert week["price_return"]["unanswered"]["no_close_at_start"] == 1

    assert [%{"security" => %{"id" => unpriced_id}, "reason" => "no_close_at_start"}] =
             week["price_return"]["unanswered_entries"]

    assert unpriced_id == unpriced.id
    assert week["start_on"] == iso(Movers.start_on("week", today))
    assert week["end_on"] == iso(today)
    assert is_binary(hd(week["price_return"]["highest"])["return"])
    assert is_binary(hd(week["contribution"]["highest"])["contribution"])
  end

  # Acceptance criteria (ADR-0061 §4, §9; the limit family's contract, #771):
  # - Without window the read answers the day, the window the Overview
  #   reads; without limit it answers five per half.
  # - A limit above 50 is capped at 50 and echoed; an empty one is the
  #   default.
  test "the defaults and the limit's cap", %{conn: conn, view: view} do
    plain = get_data(conn, "/api/v1/views/#{view.id}/movers")
    assert plain["window"] == "day"
    assert plain["start_on"] == nil
    assert plain["limit"] == Movers.default_limit()

    assert get_data(conn, "/api/v1/movers?limit=999")["limit"] == Movers.max_limit()
    assert get_data(conn, "/api/v1/movers?limit=")["limit"] == Movers.default_limit()

    one = get_data(conn, "/api/v1/movers?window=month&limit=1")
    assert one["limit"] == 1
    assert length(one["price_return"]["highest"]) == 1
    assert length(one["price_return"]["lowest"]) == 1
  end

  # User story (ADR-0061 §9):
  # As the operator's agent that misspelt a window or a parameter,
  # I want the read refused with a 422 naming what it does not take,
  # so that a typo costs one round trip and never answers another window.
  #
  # Acceptance criteria:
  # - An unknown window, a limit of zero or text, an include_unanswered other
  #   than true or false, and any parameter the read does not take answer
  #   422 naming it, on both routes.
  # - A view that does not exist, or an id that is no id, answers 404.
  test "an unknown window, a bad limit or an unknown field answers 422 naming it", %{
    conn: conn,
    view: view
  } do
    for base <- ["/api/v1/views/#{view.id}/movers", "/api/v1/movers"] do
      assert %{"window" => [window]} = errors(conn, base <> "?window=fortnight")
      assert window =~ "day, week, month, quarter, ytd or 1y"
      assert %{"window" => [_]} = errors(conn, base <> "?window[]=week")
      assert %{"limit" => [_]} = errors(conn, base <> "?limit=0")
      assert %{"limit" => [_]} = errors(conn, base <> "?limit=five")
      assert %{"include_unanswered" => [_]} = errors(conn, base <> "?include_unanswered=yes")
      assert %{"as_of" => [unknown]} = errors(conn, base <> "?window=week&as_of=2026-01-01")
      assert unknown =~ "window, limit, include_unanswered"
      assert %{"view_id" => [_]} = errors(conn, base <> "?view_id=#{view.id}")
    end

    for path <- [
          "/api/v1/views/0/movers",
          "/api/v1/views/abc/movers",
          "/api/v1/views/999999999/movers"
        ] do
      assert %{"errors" => %{"detail" => "not found"}} =
               conn |> get(path) |> json_response(404),
             path
    end
  end

  # User story (ADR-0061 §5; Sprint 30 closing act, agent's lens, finding 1):
  # As the operator's agent reading why the money ranking is what it is,
  # I want the contribution ranking's basis to describe this ranking only,
  # so that it never tells me there is no rank, that the rows are sorted
  # largest first, or that they sum to a total the answer does not carry.
  #
  # Acceptance criteria:
  # - The contribution basis no longer nests ADR-0051's whole table basis:
  #   no `table_basis`, and none of that table's claims about its own shape
  #   (one list largest first, no share, rank or label, totals.result).
  # - It still states the computation basis whole: the input series, the
  #   window, the figure (its terms, in EUR), the reference and the gaps,
  #   prices and rates carried forward included.
  test "the contribution basis says nothing the movers payload contradicts", %{conn: conn} do
    data = get_data(conn, "/api/v1/movers?window=week")
    basis = data["contribution"]["computation_basis"]
    text = Jason.encode!(basis)

    refute Map.has_key?(data["contribution"], "totals")
    refute Map.has_key?(basis, "table_basis")

    for claim <- [
          "there is no share, rank or label",
          "Positions are sorted by contribution, largest first",
          "sum to totals.result"
        ] do
      refute text =~ claim,
             "the movers' contribution basis says #{inspect(claim)}, which its own payload " <>
               "(highest descending, lowest ascending, no totals) contradicts"
    end

    for key <- ["input_series", "window", "figure", "currency", "gaps"],
        do: assert(is_binary(basis[key]) or is_map(basis[key]), key)

    assert Map.has_key?(basis, "reference") and basis["reference"] == nil
    assert basis["figure"] =~ "net_flows"
    assert basis["figure"] =~ "income"
    assert basis["figure"] =~ "costs"
    assert basis["gaps"] =~ "most recent stored point on or before each day"
  end
end
