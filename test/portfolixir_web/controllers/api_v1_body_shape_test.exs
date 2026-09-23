defmodule PortfolixirWeb.ApiV1BodyShapeTest do
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Tax

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  # User story (#853, the error contract of docs/integration/api-and-mcp.md):
  # As the operator's agent sending a malformed write,
  # I want a 422 naming the field,
  # so that I can tell a bad request from a broken server — a 500 tells me
  # neither.
  #
  # Acceptance criteria:
  # - PUT /tax/parameters with an empty body answers 422 naming the missing
  #   fields, never an ArgumentError.
  # - Every write whose body carries its attributes under one wrapper key
  #   answers 422 naming that key when the wrapper is not an object (a string,
  #   a number, a list), never a FunctionClauseError.
  test "a body whose wrapper is not an object is a 422 naming it, on every wrapped write",
       %{conn: conn} do
    world = base_world(name: "Shapes")
    security = create_security!(name: "Shape Co", ticker: "SHP")
    tx = buy!(world, security, quantity: "1", price: "10")
    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Shape bucket"})
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Shape view"})
    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Shape tree"})

    {:ok, profile} =
      Tax.create_profile(Actor.owner_ui(), %{holder: "Shape", valid_from: ~D[2025-01-01]})

    {:ok, rule} =
      PolicyRules.create_rule(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "Shape rule",
        version: %{
          subject_type: "cash",
          measure: "weight",
          kind: "floor",
          threshold: "1",
          severity: "warn"
        }
      })

    routes = [
      {:post, "/api/v1/views", "view"},
      {:patch, "/api/v1/views/#{view.id}", "view"},
      {:post, "/api/v1/securities/#{security.id}/isin-change", "isin_change"},
      {:put, "/api/v1/tax/parameters", "parameters"},
      {:post, "/api/v1/tax/profiles", "profile"},
      {:patch, "/api/v1/tax/profiles/#{profile.id}", "profile"},
      {:put, "/api/v1/tax/allowance_orders", "allowance_order"},
      {:post, "/api/v1/transactions", "transaction"},
      {:patch, "/api/v1/transactions/#{tx.id}", "transaction"},
      {:post, "/api/v1/classifications", "classification"},
      {:patch, "/api/v1/classifications/#{tree.id}", "classification"},
      {:post, "/api/v1/classifications/#{tree.id}/categories", "category"},
      {:post, "/api/v1/buckets", "bucket"},
      {:patch, "/api/v1/buckets/#{bucket.id}", "bucket"},
      {:post, "/api/v1/tax/statement_snapshots", "statement_snapshot"},
      {:post, "/api/v1/portfolios", "portfolio"},
      {:patch, "/api/v1/portfolios/#{world.portfolio.id}", "portfolio"},
      {:post, "/api/v1/securities/#{security.id}/events", "event"},
      {:post, "/api/v1/securities", "security"},
      {:patch, "/api/v1/securities/#{security.id}", "security"},
      {:post, "/api/v1/portfolios/#{world.portfolio.id}/policy_rules", "rule"},
      {:post, "/api/v1/policy_rules/#{rule.id}/versions", "version"}
    ]

    for {method, path, key} <- routes, bad <- ["x", 42, ["x"]] do
      conn = dispatch(conn, @endpoint, method, path, %{key => bad})

      assert conn.status == 422,
             "#{method} #{path} with #{key}: #{inspect(bad)} answered #{conn.status}, expected 422"

      assert %{"errors" => errors} = Jason.decode!(conn.resp_body)

      # Two routes answered this before #853 and keep their own contract: the
      # events treat a non-object as an empty one (422 naming the missing
      # fields), the ISIN change names its wrapper "is invalid".
      unless key == "event" do
        assert Map.has_key?(errors, key),
               "#{method} #{path}: 422 does not name #{key}: #{inspect(errors)}"
      end
    end

    %{"errors" => errors} = conn |> put("/api/v1/tax/parameters", %{}) |> json_response(422)
    assert Map.has_key?(errors, "tax_year")

    # The rule's nested version is a wrapper too (closing act, edge-case
    # hunter): a string there is not four missing fields.
    for bad <- ["cap", 42, ["x"]] do
      %{"errors" => errors} =
        conn
        |> post("/api/v1/portfolios/#{world.portfolio.id}/policy_rules", %{
          "rule" => %{"name" => "Nested", "version" => bad}
        })
        |> json_response(422)

      assert errors == %{"version" => ["must be an object"]}
    end
  end
end
