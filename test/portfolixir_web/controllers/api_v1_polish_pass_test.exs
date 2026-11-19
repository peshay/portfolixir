defmodule PortfolixirWeb.ApiV1PolishPassTest do
  # The API and MCP polish list (#1356), Sprint 30's planned pass, A3: one
  # functional test per line, each written first and seen failing for its
  # line's reason. Every name, figure and date is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quote
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  # Rewrites each security in turn, so PostgreSQL stores its new row version
  # after every other row: rewritten in descending id, the rows are stored
  # in descending id, a sort over tied keys meets them in that order, and
  # only an order that names the id puts them back.
  defp move_to_heap_end!(securities) do
    for security <- securities do
      {:ok, _updated} =
        Catalog.update_security(Actor.owner_ui(), security, %{note: "rewritten"})
    end
  end

  # User story (#1356, the unreviewed list's tie-break; #1294's rule):
  # As the agent reading the held positions nobody reviewed, with a limit,
  # I want positions that tie on their last entry and on their name to come
  # in id order,
  # so that a limit cut over the tie keeps the same rows on every read.
  #
  # Acceptance criteria:
  # - Held securities with no entry and one shared name read in ascending
  #   id, however PostgreSQL stores them.
  # - limit=n keeps the first n of that order.
  test "GET /api/v1/notes/unreviewed breaks a tie on last entry and name by id", %{conn: conn} do
    world = WorldFixtures.base_world()

    securities =
      for _n <- 1..12 do
        security = WorldFixtures.create_security!(name: "Tied Holding", ticker: nil)
        WorldFixtures.buy!(world, security, quantity: "1", price: "10", date: ~D[2026-01-05])
        security
      end

    move_to_heap_end!(securities |> Enum.take(11) |> Enum.reverse())
    ids = Enum.map(securities, & &1.id)

    read = fn query ->
      conn
      |> api_conn()
      |> get("/api/v1/notes/unreviewed", query)
      |> json_response(200)
      |> get_in(["data", "positions"])
      |> Enum.map(& &1["security_id"])
    end

    assert read.(%{}) == ids

    for n <- 1..12 do
      assert read.(%{"limit" => Integer.to_string(n)}) == Enum.take(ids, n), "limit #{n}"
    end
  end

  # User story (#1356, a security's quotes and the manual-quotes stretches):
  # As the agent reading a security's quotes or its manual stretches with a
  # limit,
  # I want each order to be one no two rows tie on,
  # so that a limit cut keeps the same rows on every read.
  #
  # Acceptance criteria:
  # - A security stores one quote per date whatever its source (the unique
  #   index on security and date): a second quote of another source on a
  #   stored date is refused, so the quotes read's date order has no tie.
  # - Two stretches never share their first date, so the stretches' order
  #   by first date has no tie either.
  test "a security's quotes and its manual stretches order by a key no two rows share",
       %{conn: conn} do
    security = WorldFixtures.create_security!(name: "Quoted Holding", ticker: nil)

    {:ok, _} =
      Quotes.upsert_many(security.id, [
        %{date: ~D[2026-03-02], close: "10", source: "manual"},
        %{date: ~D[2026-03-03], close: "11", source: "auto"},
        %{date: ~D[2026-03-04], close: "12", source: "manual"}
      ])

    assert_raise Ecto.ConstraintError, ~r/security_quotes_security_id_date_index/, fn ->
      Repo.insert!(%Quote{
        security_id: security.id,
        date: ~D[2026-03-02],
        close: Decimal.new("10"),
        source: "portfolio_performance"
      })
    end

    stretches =
      conn
      |> api_conn()
      |> get("/api/v1/securities/#{security.id}/quotes/manual")
      |> json_response(200)
      |> get_in(["data", "stretches"])

    froms = Enum.map(stretches, & &1["from"])
    assert froms == ["2026-03-02", "2026-03-04"]
    assert froms == Enum.uniq(froms)
  end

  # User story (#1356, the rate's exponent; Sprint 25's correctness lens):
  # As the agent comparing against a fixed rate,
  # I want a rate the engine cannot hold exactly refused when it is parsed,
  # as the Wealth page refuses it, and every rate echoed in one short
  # spelling,
  # so that neither read prints a rate of thousands of characters or a
  # rate other than the one it computed with.
  #
  # Acceptance criteria:
  # - rate:1E-6144 answers 422 on benchmark on the comparison and on sale
  #   hindsight, where one echoed "0" and the other about 6,000 characters.
  # - rate:0.05000000000000 is echoed "0.05" by both.
  test "benchmark=rate: is bounded at parse and echoed short on both reads", %{conn: conn} do
    world = WorldFixtures.base_world()
    comparison = "/api/v1/portfolios/#{world.portfolio.id}/performance/benchmark"

    for path <- [comparison, "/api/v1/sales/hindsight"] do
      assert %{"errors" => %{"benchmark" => ["is invalid"]}} =
               conn
               |> api_conn()
               |> get(path, %{"benchmark" => "rate:1E-6144"})
               |> json_response(422),
             path
    end

    long_zeros = "rate:0.05000000000000"

    assert %{"benchmark" => %{"kind" => "rate", "annual_rate" => "0.05"}} =
             conn
             |> api_conn()
             |> get(comparison, %{"benchmark" => long_zeros})
             |> json_response(200)
             |> Map.fetch!("data")

    assert %{"benchmark" => %{"kind" => "rate", "annual_rate" => "0.05"}} =
             conn
             |> api_conn()
             |> get("/api/v1/sales/hindsight", %{"benchmark" => long_zeros})
             |> json_response(200)
             |> Map.fetch!("data")
  end

  # User story (#1356, the operator's agent's report of 2026-11-07):
  # As the agent that sent the MCP companion's token to the API,
  # I want the 401 to say which token the API expects,
  # so that I fix the token instead of retrying into the lockout.
  #
  # Acceptance criteria:
  # - A wrong or missing token answers 401 naming PORTFOLIXIR_API_TOKEN and
  #   PORTFOLIXIR_API_TOKENS, and saying the companion's
  #   PORTFOLIXIR_MCP_TOKEN is not this route's.
  # - Nothing the request sent is echoed.
  test "the API's 401 names the token the route expects and echoes nothing sent", %{conn: conn} do
    sent = "companion-token-" <> String.duplicate("q", 40)

    for header <- [nil, "Bearer " <> sent] do
      request = put_req_header(conn, "accept", "application/json")
      request = if header, do: put_req_header(request, "authorization", header), else: request
      response = request |> get("/api/v1/securities") |> response(401)

      assert %{"errors" => %{"detail" => "unauthorized", "expected_token" => expected}} =
               Jason.decode!(response)

      assert expected =~ "PORTFOLIXIR_API_TOKEN"
      assert expected =~ "PORTFOLIXIR_API_TOKENS"
      assert expected =~ "PORTFOLIXIR_MCP_TOKEN"
      refute response =~ "qqqq"
      refute response =~ "companion-token"
    end
  end

  # User story (#1356, the UAT persona on #1436):
  # As the agent writing a security over raw HTTP,
  # I want a field sent beside the security wrapper refused with 422 naming
  # it, as the news writes refuse one,
  # so that I never believe a write landed that changed nothing.
  #
  # Acceptance criteria:
  # - PATCH /api/v1/securities/:id with {"feed": "MANUAL"} answers 422 on
  #   feed, saying the write takes its fields under security; nothing is
  #   stored.
  # - The same field beside a valid wrapper is refused too, and the wrapper's
  #   change is not stored either.
  # - A write with only the wrapper still answers 200.
  test "PATCH /api/v1/securities/:id refuses a field outside its wrapper", %{conn: conn} do
    security = WorldFixtures.create_security!(name: "Wrapped Holding", ticker: "WRH")

    patch_json = fn body ->
      conn |> api_conn() |> patch("/api/v1/securities/#{security.id}", Jason.encode!(body))
    end

    assert %{"errors" => %{"feed" => ["is unknown: this write takes its fields under security"]}} =
             patch_json.(%{"feed" => "MANUAL"}) |> json_response(422)

    assert %{"errors" => %{"feed" => [_refusal]}} =
             patch_json.(%{"security" => %{"name" => "Renamed Holding"}, "feed" => "MANUAL"})
             |> json_response(422)

    stored = Catalog.get_security(security.id)
    assert stored.name == "Wrapped Holding"
    assert stored.feed == security.feed

    assert %{"data" => %{"name" => "Renamed Holding"}} =
             patch_json.(%{"security" => %{"name" => "Renamed Holding"}}) |> json_response(200)
  end

  # User story (#1258, #1356):
  # As the agent reading the API reference before a reconcile,
  # I want the reference to state the reconcile's row cap, as its MCP schema
  # does and the endpoint enforces,
  # so that I split a long statement before the server refuses it.
  #
  # Acceptance criteria:
  # - The English and German references state the 10,000-row cap and the
  #   422 on rows past it, the number the controller enforces.
  test "the API reference states the holdings reconcile's row cap" do
    source = File.read!("lib/portfolixir_web/controllers/api/v1/holdings_reconcile_controller.ex")
    assert source =~ "@max_rows 10_000"

    for {path, fragment} <- [
          {"docs/integration/api-and-mcp.md",
           "At most 10000 rows per request; a longer `rows` list answers `422` on `rows`"},
          {"docs/de/integration/api-and-mcp.md",
           "Höchstens 10000 Zeilen je Anfrage; eine längere `rows`-Liste ergibt `422` auf `rows`"}
        ] do
      doc = path |> File.read!() |> String.replace(~r/\s+/, " ")
      assert doc =~ fragment, path
    end
  end
end
