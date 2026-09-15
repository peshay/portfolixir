defmodule PortfolixirWeb.ApiV1ListLimitsTest do
  # Issue #771: every list read has a default and a maximum row count, and
  # the quote upsert a row cap, so one authenticated call cannot ask the
  # instance to materialise an unbounded table.
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, buy!: 3, create_security!: 1, deposit!: 3, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Knowledge
  alias Portfolixir.Portfolios.Snapshots
  alias PortfolixirWeb.Api.V1.ListLimit

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  # User story:
  # As the operator whose agent reads lists over the API,
  # I want a missing limit to mean a generous default and an oversized limit to be capped,
  # so that a routine read never changes and a hostile one is bounded.
  #
  # Acceptance criteria:
  # - Absent or blank: the default. An integer or numeric string: itself, capped at the maximum.
  # - Zero, negative, non-numeric: an error naming the field.
  test "parses, defaults and caps the limit parameter" do
    assert ListLimit.parse(%{}, 100, 1_000) == {:ok, 100}
    assert ListLimit.parse(%{"limit" => ""}, 100, 1_000) == {:ok, 100}
    assert ListLimit.parse(%{"limit" => "50"}, 100, 1_000) == {:ok, 50}
    assert ListLimit.parse(%{"limit" => 50}, 100, 1_000) == {:ok, 50}
    assert ListLimit.parse(%{"limit" => "999999"}, 100, 1_000) == {:ok, 1_000}
    assert ListLimit.parse(%{"limit" => "0"}, 100, 1_000) == {:error, :limit}
    assert ListLimit.parse(%{"limit" => "-5"}, 100, 1_000) == {:error, :limit}
    assert ListLimit.parse(%{"limit" => "abc"}, 100, 1_000) == {:error, :limit}
    assert ListLimit.parse(%{"limit" => [1]}, 100, 1_000) == {:error, :limit}
  end

  test "the four list reads refuse a malformed limit", %{conn: conn} do
    security = create_security!(name: "Limit Co", ticker: "LIM")

    for path <- [
          "/api/v1/transactions?limit=abc",
          "/api/v1/securities?limit=0",
          "/api/v1/exchange_rates?limit=-1",
          "/api/v1/securities/#{security.id}/quotes?limit=x"
        ] do
      response = conn |> get(path) |> json_response(422)
      assert %{"errors" => %{"limit" => [_ | _]}} = response, path
    end
  end

  test "a quote limit keeps the newest rows of the window, ascending", %{conn: conn} do
    security = create_security!(name: "Newest Co", ticker: "NEW")

    rows =
      for day <- 1..5,
          do: %{date: Date.new!(2026, 1, day), close: Decimal.new("1#{day}"), source: "manual"}

    assert {:ok, 5} = Quotes.upsert_many(security.id, rows)

    %{"data" => data} =
      conn |> get("/api/v1/securities/#{security.id}/quotes?limit=2") |> json_response(200)

    assert Enum.map(data, & &1["date"]) == ["2026-01-04", "2026-01-05"]
  end

  test "the four list reads accept a limit and answer as before", %{conn: conn} do
    security = create_security!(name: "Limit Co", ticker: "LIM")

    for path <- [
          "/api/v1/transactions?limit=10",
          "/api/v1/securities?limit=10",
          "/api/v1/exchange_rates?limit=10",
          "/api/v1/securities/#{security.id}/quotes?limit=10"
        ] do
      assert %{"data" => data} = conn |> get(path) |> json_response(200), path
      assert is_list(data)
    end
  end

  # User story:
  # As the operator,
  # I want a quote upsert refused past a row cap,
  # so that one request cannot carry an unbounded number of rows.
  #
  # Acceptance criteria:
  # - More rows than the cap answer 422 naming the cap; nothing is written.
  test "the quote upsert refuses more rows than the cap", %{conn: conn} do
    security = create_security!(name: "Cap Co", ticker: "CAP")
    cap = ListLimit.quote_upsert_max_rows()

    rows =
      for i <- 1..(cap + 1) do
        %{"date" => Date.to_iso8601(Date.add(~D[2000-01-01], i)), "close" => "1.00"}
      end

    response =
      conn
      |> put("/api/v1/securities/#{security.id}/quotes", %{"quotes" => rows})
      |> json_response(422)

    assert %{"errors" => %{"quotes" => [message]}} = response
    assert message =~ Integer.to_string(cap)
    assert Quotes.range(security.id, ~D[1990-01-01], ~D[2100-01-01]) == []
  end

  # User story (#776 — Sprint 11 Lane W, the surface check's first catch):
  # As the operator whose agent reads the research log, the snapshot list and
  # the three cash-flow roll-ups over the API,
  # I want every collection read of that family to take a bounded limit, spelled
  # the same way as the four #771 reads, or to record why its period is the bound,
  # so that an agent reading a collection has a way to ask for less, and the
  # family is not half-done a third time.
  #
  # Acceptance criteria:
  # - The four research-log reads, the snapshot list and the three roll-ups
  #   accept limit and answer as before without it; a malformed limit is 422.
  # - A limit keeps the most relevant rows of each read's own order: the newest
  #   entries of a security's log and of the uncorroborated read, the most
  #   overdue positions of the unreviewed read, the soonest-expiring entries of
  #   the expiring read, the newest snapshots, and the newest years of a
  #   roll-up's annual matrix — the matrix rows a year keeps are unchanged.
  # - The trades read keeps from/to as its bound: the FIFO matcher needs the
  #   whole history, and each leg is filtered by its own date.
  test "the eight further collection reads refuse a malformed limit", %{conn: conn} do
    security = create_security!(name: "Limit Co", ticker: "LIM")

    for path <- [
          "/api/v1/securities/#{security.id}/notes?limit=abc",
          "/api/v1/notes/unreviewed?limit=0",
          "/api/v1/notes/uncorroborated?limit=-1",
          "/api/v1/notes/expiring?limit=x",
          "/api/v1/snapshots?limit=0",
          "/api/v1/realized_gains?limit=abc",
          "/api/v1/external_flows?limit=0",
          "/api/v1/costs?limit=-2"
        ] do
      response = conn |> get(path) |> json_response(422)
      assert %{"errors" => %{"limit" => [_ | _]}} = response, path
    end
  end

  test "the eight further collection reads accept a limit and answer as before", %{conn: conn} do
    security = create_security!(name: "Limit Co", ticker: "LIM")

    for path <- [
          "/api/v1/securities/#{security.id}/notes?limit=10",
          "/api/v1/notes/unreviewed?limit=10",
          "/api/v1/notes/uncorroborated?limit=10",
          "/api/v1/notes/expiring?limit=10",
          "/api/v1/snapshots?limit=10",
          "/api/v1/realized_gains?limit=10",
          "/api/v1/external_flows?limit=10",
          "/api/v1/costs?limit=10"
        ] do
      assert %{"data" => data} = conn |> get(path) |> json_response(200), path
      assert is_map(data), path
    end
  end

  test "a note limit keeps the newest entries and the thesis state still reads the whole log",
       %{conn: conn} do
    security = create_security!(name: "Noted Co", ticker: "NOT")

    for {day, kind} <- [{1, "evidence"}, {2, "evidence"}, {3, "decision"}] do
      {:ok, _} =
        Knowledge.append_note(Actor.owner_ui(), %{
          security_id: security.id,
          author: "agent",
          kind: kind,
          body: "entry #{day}",
          source_quality: "primary",
          as_of: Date.new!(2026, 3, day)
        })
    end

    %{"data" => data} =
      conn |> get("/api/v1/securities/#{security.id}/notes?limit=2") |> json_response(200)

    assert Enum.map(data["entries"], & &1["as_of"]) == ["2026-03-03", "2026-03-02"]
    assert data["limit"] == 2
    assert data["thesis_state"] == unlimited_thesis_state(conn, security)
  end

  defp unlimited_thesis_state(conn, security) do
    %{"data" => data} =
      conn |> get("/api/v1/securities/#{security.id}/notes") |> json_response(200)

    data["thesis_state"]
  end

  test "an expiring limit keeps the soonest entries, a snapshot limit the newest",
       %{conn: conn} do
    security = create_security!(name: "Expiring Co", ticker: "EXP")
    today = Portfolixir.Clock.today()

    for days <- [20, 5, 12] do
      {:ok, _} =
        Knowledge.append_note(Actor.owner_ui(), %{
          security_id: security.id,
          author: "agent",
          kind: "decision",
          body: "block for #{days} days",
          source_quality: "primary",
          as_of: today,
          valid_until: Date.add(today, days)
        })
    end

    %{"data" => expiring} = conn |> get("/api/v1/notes/expiring?limit=2") |> json_response(200)
    assert Enum.map(expiring["entries"], & &1["days_until_expiry"]) == [5, 12]
    assert expiring["limit"] == 2

    for {name, date} <- [
          {"older", ~D[2026-01-05]},
          {"newest", ~D[2026-03-01]},
          {"middle", ~D[2026-02-01]}
        ] do
      {:ok, _} =
        Snapshots.create_snapshot(Actor.owner_ui(), %{name: name, as_of: date, view_id: nil})
    end

    %{"data" => snapshots} = conn |> get("/api/v1/snapshots?limit=2") |> json_response(200)
    assert Enum.map(snapshots["snapshots"], & &1["name"]) == ["newest", "middle"]
    assert snapshots["limit"] == 2
  end

  test "a roll-up limit keeps the newest years and says so in its basis", %{conn: conn} do
    world = base_world()
    security = create_security!(name: "Charged ETF", ticker: "CHG")

    for year <- [2024, 2025, 2026] do
      buy!(world, security,
        quantity: "1",
        price: "100",
        fees: "1.50",
        taxes: "0.50",
        date: Date.new!(year, 3, 1)
      )
    end

    %{"data" => costs} = conn |> get("/api/v1/costs?limit=2") |> json_response(200)
    assert Enum.map(costs["annual"], & &1["year"]) == [2026, 2025]
    assert costs["limit"] == 2
    assert costs["computation_basis"]["window"] =~ "newest 2 years"

    %{"data" => unlimited} = conn |> get("/api/v1/costs") |> json_response(200)
    assert Enum.map(unlimited["annual"], & &1["year"]) == [2026, 2025, 2024]

    assert unlimited["computation_basis"]["window"] ==
             "full ledger history, grouped by booking date"

    assert is_nil(unlimited["limit"]) or unlimited["limit"] == 100
  end

  # The two other roll-ups name the cut the same way (#776): a shorter answer
  # never reads as a shorter history.
  test "the realized-gains and external-flows roll-ups name the cut in their basis",
       %{conn: conn} do
    world = base_world()
    security = create_security!(name: "Cut Co", ticker: "CUT")

    for year <- [2025, 2026] do
      deposit!(world, "100", Date.new!(year, 1, 10))
      buy!(world, security, quantity: "1", price: "100", date: Date.new!(year, 2, 1))
      sell!(world, security, quantity: "1", price: "110", date: Date.new!(year, 3, 1))
    end

    for {path, grouping} <- [
          {"/api/v1/realized_gains", "grouped by each trade's close date"},
          {"/api/v1/external_flows", "grouped by booking date"}
        ] do
      %{"data" => cut} = conn |> get(path <> "?limit=1") |> json_response(200)
      assert Enum.map(cut["annual"], & &1["year"]) == [2026], path
      assert cut["limit"] == 1, path

      assert cut["computation_basis"]["window"] ==
               "the newest 1 years of the full ledger history, " <> grouping,
             path

      %{"data" => whole} = conn |> get(path) |> json_response(200)
      assert Enum.map(whole["annual"], & &1["year"]) == [2026, 2025], path
      assert whole["computation_basis"]["window"] == "full ledger history, " <> grouping, path
    end
  end

  test "the trades read keeps from and to as its bound and takes no limit", %{conn: conn} do
    security = create_security!(name: "Traded Co", ticker: "TRD")

    %{"data" => data} =
      conn |> get("/api/v1/securities/#{security.id}/trades?limit=1") |> json_response(200)

    assert Map.has_key?(data, "open_lots")
    assert data["basis"]["bound"] =~ "from/to"
  end
end
