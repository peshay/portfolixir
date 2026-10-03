defmodule PortfolixirWeb.ApiV1ReadParamBoundsTest do
  # E25 S4, F70 and G24 (#889), from the S3/S4 review round: the writers got
  # one bounded date and one text rule, but the reads' date and text filters
  # still reached the database unbounded. A date the database cannot hold, or
  # a filter carrying a character it refuses, failed in the query with a 500.
  # Every read now parses a date filter through the bounded date
  # (PortfolixirWeb.Api.V1.DateParam) and a text filter through the text rule
  # (PortfolixirWeb.Api.V1.TextParam).
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1, buy!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Clock

  @outside ["-5000-01-01", "1899-12-31", "3000-01-01", "20260102", "2026-1-2"]
  @nul "a\u0000b"

  # Every GET route under /api/v1, read from the router when this file
  # compiles, so the walk below is one test per route: each has its own
  # timeout, and a slow or failing route names itself. A path routed twice
  # answers from its first route, so it is walked once.
  @api_reads PortfolixirWeb.Router
             |> Phoenix.Router.routes()
             |> Enum.filter(&(&1.verb == :get and String.starts_with?(&1.path, "/api/v1")))
             |> Enum.map(& &1.path)
             |> Enum.uniq()

  @text_keys ~w(query holder institution resource_type resource_id name type kind status
                jurisdiction direction scope series projection period fields view)

  @date_keys ~w(from to as_of since date)

  @malformed_filters Enum.map(@text_keys, &{&1, @nul}) ++
                       for(
                         key <- @date_keys,
                         value <- ["-5000-01-01", "5874898-01-01"],
                         do: {key, value}
                       )

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    world = base_world(name: "Read filters")
    security = create_security!(name: "Sable Ridge Minerals", ticker: "SRM")
    # Dated a week before today rather than on a fixed day: the reads that
    # walk the ledger day by day walk from the first booking to today, so a
    # fixed date made the route walk below slower every day it aged.
    booked_on = Date.add(Clock.today(), -7)
    buy!(world, security, date: booked_on)
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Core"})

    %{conn: conn, world: world, security: security, view: view, booked_on: booked_on}
  end

  defp status_and_errors(conn, path) do
    conn = get(conn, path)
    errors = if conn.status == 422, do: Jason.decode!(conn.resp_body)["errors"], else: nil
    {conn.status, errors}
  end

  # User story:
  # As the operator's agent reading a dated history,
  # I want a date filter outside the ledger's range, or not written YYYY-MM-DD,
  # refused with a 422 naming the parameter,
  # so that a malformed filter costs me one round trip and never a server
  # error.
  #
  # Acceptance criteria:
  # - The transactions and quotes reads' from and to, and the metrics and
  #   policy-rule reads' as_of, answer a date outside 1900-01-01 to
  #   2999-12-31, or in another form, with 422 naming the parameter.
  # - A date inside the range still filters.
  test "a dated read refuses a date outside the bounded range",
       %{conn: conn, world: world, security: security, booked_on: booked_on} do
    reads = [
      {"/api/v1/transactions", "from"},
      {"/api/v1/transactions", "to"},
      {"/api/v1/securities/#{security.id}/quotes", "from"},
      {"/api/v1/securities/#{security.id}/quotes", "to"},
      {"/api/v1/securities/#{security.id}/metrics", "as_of"},
      {"/api/v1/portfolios/#{world.portfolio.id}/policy_rules", "as_of"},
      {"/api/v1/securities/#{security.id}/trades", "from"}
    ]

    for {path, key} <- reads, value <- @outside do
      assert {422, errors} =
               status_and_errors(conn, path <> "?" <> URI.encode_query(%{key => value})),
             "#{path}?#{key}=#{value}"

      assert Map.has_key?(errors, key), "#{path}?#{key}=#{value}: #{inspect(errors)}"
    end

    before_the_buy = Date.add(booked_on, -4)
    after_the_buy = Date.add(booked_on, 1)

    assert %{"data" => [_booked]} =
             conn |> get("/api/v1/transactions?from=#{before_the_buy}") |> json_response(200)

    assert %{"data" => []} =
             conn |> get("/api/v1/transactions?from=#{after_the_buy}") |> json_response(200)
  end

  # User story:
  # As the operator's agent filtering a read by text,
  # I want a filter carrying a character the database refuses, longer than a
  # name can be, or not a string, refused with a 422 naming the parameter,
  # so that a garbled filter never answers a server error.
  #
  # Acceptance criteria:
  # - The securities query, the journal's resource_type and resource_id, and
  #   the tax reads' holder, institution and jurisdiction answer such a
  #   filter with 422 naming it.
  # - A plain filter still applies.
  test "a text-filtered read refuses text the database cannot compare", %{conn: conn} do
    reads = [
      {"/api/v1/securities", "query", ""},
      {"/api/v1/journal", "resource_type", ""},
      {"/api/v1/journal", "resource_id", ""},
      {"/api/v1/tax/parameters", "jurisdiction", ""},
      {"/api/v1/tax/profiles", "holder", ""},
      {"/api/v1/tax/allowance_orders", "holder", ""},
      {"/api/v1/tax/allowance_orders", "institution", ""},
      {"/api/v1/tax/statement_snapshots", "holder", ""},
      {"/api/v1/tax/statement_snapshots", "institution", ""},
      {"/api/v1/tax/trim_budget", "holder", "&tax_year=2025"}
    ]

    for {path, key, rest} <- reads,
        query <- [
          URI.encode_query(%{key => @nul}),
          URI.encode_query(%{key => String.duplicate("a", 256)}),
          "#{key}[]=a"
        ] do
      assert {422, errors} = status_and_errors(conn, path <> "?" <> query <> rest),
             "#{path}?#{query}"

      assert Map.has_key?(errors, key), "#{path}?#{query}: #{inspect(errors)}"
    end

    assert %{"data" => [%{"name" => "Sable Ridge Minerals"}]} =
             conn |> get("/api/v1/securities?query=Sable") |> json_response(200)
  end

  # Acceptance criteria:
  # - Across every API read, a malformed date or text value in any of the
  #   filter names the reads take answers something other than a 500.
  # - The walk covers every GET route under /api/v1, more than 50 of them,
  #   one test per route.
  test "the route walk covers every API read" do
    assert length(@api_reads) > 50
  end

  for route_path <- @api_reads do
    test "GET #{route_path} answers a malformed date or text filter without a server error",
         %{conn: conn, world: world, security: security, view: view} do
      route_path = unquote(route_path)

      path =
        route_path
        |> String.replace(":portfolio_id", "#{world.portfolio.id}")
        |> String.replace(":security_id", "#{security.id}")
        |> String.replace(":view_id", "#{view.id}")
        |> String.replace(":id", "#{security.id}")
        |> String.replace(":file", "missing.png")

      for {key, value} <- @malformed_filters do
        query = URI.encode_query(%{key => value, "tax_year" => "2025"})
        conn = get(conn, path <> "?" <> query)
        assert conn.status != 500, "#{route_path}?#{key}: #{conn.status}"
      end
    end
  end
end
