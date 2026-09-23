defmodule PortfolixirWeb.ApiV1IdRangeTest do
  @moduledoc """
  The `/api/v1` error contract for ids (#840): an id a PostgreSQL `bigint`
  cannot hold is answered like any other malformed id — never a 500.

  The route tables are read from the router rather than written out, so a
  route added later is swept by the same assertions without anyone having to
  remember to list it.
  """
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias PortfolixirWeb.Api.V1.IdParam

  # The largest bigint, one past it, and the value the edge-case hunter used.
  @max_int8 "9223372036854775807"
  @past_int8 "9223372036854775808"
  @far "99999999999999999999"
  @far_number 99_999_999_999_999_999_999

  # Every key through which an id reaches a controller today.
  @id_keys ~w(id security_id portfolio_id securities_account_id cash_account_id
    counter_cash_account_id counter_securities_account_id classification_id
    category_id parent_id supersedes_id view_id view bucket_id plan_id
    running_balance_for security_ids bucket_ids)

  # The body wrappers a write endpoint reads its attributes from.
  @wrappers ~w(transaction cash_account securities_account category classification
    bucket view note event portfolio security isin_change statement_snapshot
    profile allowance_order parameters)

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  defp api_routes do
    PortfolixirWeb.Router
    |> Phoenix.Router.routes()
    |> Enum.filter(&String.starts_with?(&1.path, "/api/v1/"))
  end

  defp has_path_param?(route), do: String.contains?(route.path, "/:")

  # Dispatches and reports a raise as a result of its own, so one failing
  # route does not hide the rest of the table.
  defp request(conn, verb, path, body) do
    conn
    |> dispatch(@endpoint, verb, path, encode(body))
    |> then(&{&1.status, Jason.decode!(&1.resp_body)})
  rescue
    exception -> {:raised, exception.__struct__}
  end

  defp encode(body) when is_binary(body), do: body
  defp encode(body), do: Jason.encode!(body)

  describe "IdParam.parse/1" do
    test "accepts a positive id a bigint column can hold, as a string or an integer" do
      assert IdParam.parse("1") == {:ok, 1}
      assert IdParam.parse(42) == {:ok, 42}
      assert IdParam.parse(@max_int8) == {:ok, 9_223_372_036_854_775_807}
    end

    test "refuses what no id column can hold" do
      for raw <- [@past_int8, @far, @far_number, "0", "-1", 0, -1, "-#{@far}"] do
        assert IdParam.parse(raw) == :error, "expected #{inspect(raw)} to be refused"
      end
    end

    test "refuses a malformed value" do
      for raw <- ["", "abc", "1.5", "1abc", nil, 1.0, %{}, ["1"]] do
        assert IdParam.parse(raw) == :error, "expected #{inspect(raw)} to be refused"
      end
    end

    test "a list parses whole or not at all" do
      assert IdParam.parse_list(["1", 2]) == {:ok, [1, 2]}
      assert IdParam.parse_list([]) == {:ok, []}
      assert IdParam.parse_list(["1", @far]) == :error
      assert IdParam.parse_list("1") == :error
    end
  end

  # User story (#840):
  # As the operator's agent,
  # I want an id no record can have answered like any unknown id,
  # so that a typo or a corrupted id never looks like a server fault.
  #
  # Acceptance criteria:
  # - Every /api/v1 route with a path id answers 404 with the JSON error
  #   envelope for an id past the bigint range, as it does for a malformed id.
  # - The largest bigint is still an ordinary id: it reaches the route, which
  #   answers it as it answers any unknown id (404, the 422 an empty body
  #   earns, or an idempotent delete's 200), never a 500.
  test "every path id past the bigint range answers 404, never 500", %{conn: conn} do
    routes = Enum.filter(api_routes(), &has_path_param?/1)
    swept = Enum.map(routes, & &1.path)

    # The families the issue named are in the sweep, so the sweep is at
    # least as wide as the report it answers.
    for named <- [
          "/api/v1/securities/:id",
          "/api/v1/securities/:security_id/quotes",
          "/api/v1/securities/:security_id/trades",
          "/api/v1/securities/:security_id/notes"
        ] do
      assert named in swept
    end

    failures =
      for route <- routes,
          id <- [@past_int8, @far, "-#{@far}", "abc"],
          path = Regex.replace(~r/:[a-z_]+/, route.path, id),
          result = request(conn, route.verb, path, "{}"),
          not match?({404, %{"errors" => _}}, result) do
        {route.verb, route.path, id, result}
      end

    assert failures == []
  end

  test "the largest bigint is an ordinary unknown id on every path", %{conn: conn} do
    failures =
      for route <- api_routes(),
          has_path_param?(route),
          path = Regex.replace(~r/:[a-z_]+/, route.path, @max_int8),
          result = request(conn, route.verb, path, "{}"),
          not match?({status, _body} when status < 500, result) do
        {route.verb, route.path, result}
      end

    assert failures == []
  end

  # User story (#840):
  # As the operator's agent,
  # I want an out-of-range id in a query string or a request body refused as
  # a field error,
  # so that the filter or the reference I sent is named instead of the
  # server failing.
  #
  # Acceptance criteria:
  # - No /api/v1 route answers 5xx or raises for an id key past the bigint
  #   range in its query string, its body, or its body's attribute wrapper,
  #   as a string or as a number.
  # - The sites that raised before answer 422 naming the field.
  test "no route fails for an id past the bigint range in its query or body", %{conn: conn} do
    world = sweep_world()

    failures =
      for route <- api_routes(),
          route.verb != :delete,
          key <- @id_keys,
          form <- [:query, :body],
          {path, body} = sweep_request(route, world, key, form),
          result = request(conn, route.verb, path, body),
          not match?({status, _body} when status < 500, result) do
        {route.verb, route.path, key, form, result}
      end

    assert failures == []
  end

  @query_sites [
    {"/api/v1/transactions", "security_id"},
    {"/api/v1/transactions", "portfolio_id"},
    {"/api/v1/transactions", "securities_account_id"},
    {"/api/v1/transactions", "running_balance_for"},
    {"/api/v1/notes/uncorroborated", "security_id"},
    {"/api/v1/notes/expiring", "security_id"},
    {"/api/v1/events/unconfirmed", "security_id"},
    {"/api/v1/events/stale", "security_id"}
  ]

  test "an out-of-range id filter answers 422 naming the filter", %{conn: conn} do
    for {path, key} <- @query_sites, id <- [@past_int8, @far] do
      assert {422, %{"errors" => %{^key => _}}} =
               request(conn, :get, "#{path}?#{key}=#{id}", ""),
             "#{path}?#{key}=#{id}"
    end
  end

  test "an out-of-range id in a write body answers 422 naming the field", %{conn: conn} do
    world = base_world()
    security = create_security!()
    tx = buy!(world, security)
    {:ok, classification} = Classifications.create_classification(Actor.owner_ui(), %{name: "C"})

    buy = %{
      "portfolio_id" => world.portfolio.id,
      "securities_account_id" => world.depot.id,
      "security_id" => security.id,
      "type" => "buy",
      "date" => "2026-05-15",
      "quantity" => "3",
      "price" => "101",
      "currency_code" => "EUR"
    }

    retraction = %{
      "kind" => "retraction",
      "body" => "withdrawn",
      "source_quality" => "primary",
      "as_of" => "2026-08-01",
      "author" => "operator"
    }

    sites = [
      {:post, "/api/v1/transactions", "security_id",
       &%{"transaction" => Map.put(buy, "security_id", &1)}},
      {:post, "/api/v1/transactions", "securities_account_id",
       &%{"transaction" => Map.put(buy, "securities_account_id", &1)}},
      {:patch, "/api/v1/transactions/#{tx.id}", "portfolio_id",
       &%{"transaction" => %{"portfolio_id" => &1}}},
      {:post, "/api/v1/cash_accounts", "portfolio_id",
       &%{"cash_account" => %{"portfolio_id" => &1, "name" => "C", "currency_code" => "EUR"}}},
      {:post, "/api/v1/securities_accounts", "cash_account_id",
       &%{
         "securities_account" => %{
           "portfolio_id" => world.portfolio.id,
           "cash_account_id" => &1,
           "name" => "D"
         }
       }},
      {:patch, "/api/v1/securities_accounts/#{world.depot.id}", "cash_account_id",
       &%{"securities_account" => %{"cash_account_id" => &1}}},
      {:post, "/api/v1/securities/#{security.id}/notes", "supersedes_id",
       &%{"note" => Map.put(retraction, "supersedes_id", &1)}},
      {:post, "/api/v1/snapshots", "view_id",
       &%{"name" => "S", "as_of" => "2026-02-15", "view_id" => &1}},
      {:post, "/api/v1/classifications/#{classification.id}/categories", "parent_id",
       &%{"category" => %{"name" => "Core", "parent_id" => &1}}},
      {:put, "/api/v1/classifications/#{classification.id}/assignments", "category_id",
       &%{"security_id" => security.id, "category_id" => &1}},
      {:put, "/api/v1/portfolios/#{world.portfolio.id}/targets", "classification_id",
       &%{"targets" => [], "classification_id" => &1}},
      {:put, "/api/v1/securities_accounts/#{world.depot.id}/buckets", "bucket_ids",
       &%{"bucket_ids" => [&1]}},
      {:post, "/api/v1/splits/preview", "security_id",
       &%{"security_id" => &1, "date" => "2026-01-02"}},
      {:put, "/api/v1/settings/default_view", "view_id", &%{"view_id" => &1}}
    ]

    for {verb, path, field, body} <- sites, value <- [@far_number, @far] do
      assert {422, %{"errors" => %{^field => _}}} = request(conn, verb, path, body.(value)),
             "#{verb} #{path} #{field}=#{inspect(value)}"
    end
  end

  test "a free-form attribute that merely looks like an id is left alone", %{conn: conn} do
    security = create_security!()

    body = %{"security" => %{"attributes" => %{"provider_id" => @far}}}

    assert {200, %{"data" => %{"attributes" => %{"provider_id" => @far}}}} =
             request(conn, :patch, "/api/v1/securities/#{security.id}", body)
  end

  # A small world so path ids resolve and a request gets as far as reading
  # its query and body.
  defp sweep_world do
    world = base_world()
    security = create_security!()
    tx = buy!(world, security)
    {:ok, classification} = Classifications.create_classification(Actor.owner_ui(), %{name: "C"})

    {:ok, category} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "B"})
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "V", include_all: true})

    %{
      "portfolio_id" => world.portfolio.id,
      "security_id" => security.id,
      "classification_id" => classification.id,
      "category_id" => category.id,
      "view_id" => view.id,
      "securities" => security.id,
      "cash_accounts" => world.cash.id,
      "securities_accounts" => world.depot.id,
      "transactions" => tx.id,
      "classifications" => classification.id,
      "categories" => category.id,
      "buckets" => bucket.id,
      "views" => view.id
    }
  end

  defp sweep_request(route, world, key, form) do
    path =
      Regex.replace(~r/([a-z_]+)\/:([a-z_]+)/, route.path, fn _whole, segment, param ->
        value =
          if param == "id",
            do: Map.get(world, segment, 1),
            else: Map.get(world, param, 1)

        "#{segment}/#{value}"
      end)

    {number, string} =
      if String.ends_with?(key, "_ids"),
        do: {[@far_number], [@far]},
        else: {@far_number, @far}

    case form do
      :query ->
        {path <> "?" <> URI.encode_query(%{key => @far}), "{}"}

      # The key at the top level as a JSON number, and inside every attribute
      # wrapper as a string.
      :body ->
        {path, Map.new(@wrappers, &{&1, %{key => string}}) |> Map.put(key, number)}
    end
  end
end
