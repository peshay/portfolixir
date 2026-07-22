defmodule PortfolixirWeb.ApiV1SplitsTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits

  @auth {"authorization", "Bearer test-api-token"}

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
  end

  defp split_world do
    world_a = base_world(name: "Api Split A", cash_name: "ASA Cash", depot_name: "ASA Depot")
    world_b = base_world(name: "Api Split B", cash_name: "ASB Cash", depot_name: "ASB Depot")
    security = create_security!(name: "Api Fanout Co", ticker: "AFN")
    buy!(world_a, security, quantity: "10", price: "100", date: ~D[2026-01-02])
    buy!(world_b, security, quantity: "4", price: "100", date: ~D[2026-01-02])
    %{a: world_a, b: world_b, security: security}
  end

  defp split_body(security, extra \\ %{}) do
    Map.merge(
      %{
        "security_id" => security.id,
        "date" => "2026-02-02",
        "ratio_numerator" => 10,
        "ratio_denominator" => 5
      },
      extra
    )
  end

  # User story (ADR-0028 §1/§5, issue #589):
  # As an agent operating Portfolixir over the JSON API,
  # I want a dedicated preview endpoint for the split booking flow,
  # so that I can inspect the per-portfolio fan-out (quantities before and
  # after, current position, warnings) before writing anything.
  #
  # Acceptance criteria:
  # - POST /api/v1/splits/preview returns the normalized ratio, warnings and
  #   one row per positioned portfolio with all quantities as Decimal strings.
  # - The preview writes nothing.
  test "POST /api/v1/splits/preview previews the fan-out with Decimal strings", %{conn: conn} do
    %{a: world_a, b: world_b, security: security} = split_world()

    response =
      conn
      |> api_conn()
      |> post("/api/v1/splits/preview", Jason.encode!(split_body(security)))
      |> json_response(200)

    data = response["data"]
    assert data["security_id"] == security.id
    assert data["date"] == "2026-02-02"
    assert data["ratio_numerator"] == 2
    assert data["ratio_denominator"] == 1
    assert data["warnings"] == []

    rows = Enum.sort_by(data["portfolios"], & &1["portfolio_id"])
    assert [row_a, row_b] = rows
    assert row_a["portfolio_id"] == world_a.portfolio.id
    assert row_a["portfolio_name"] == "Api Split A"
    assert row_a["quantity_before"] == "10"
    assert row_a["quantity_after"] == "20"
    assert row_a["current_position"] == "20"
    assert row_b["portfolio_id"] == world_b.portfolio.id
    assert row_b["quantity_before"] == "4"
    assert row_b["quantity_after"] == "8"
    assert row_b["current_position"] == "8"

    # Read-only: nothing was booked.
    assert [] ==
             Ledger.list_transactions(security_id: security.id)
             |> Enum.filter(&(&1.type == "split"))
  end

  # User story (ADR-0028 §1/§5, issue #589):
  # As an agent operating Portfolixir over the JSON API,
  # I want one booking call to fan the split out across all positioned
  # portfolios,
  # so that the split books identically through API and UI-less MCP flows.
  #
  # Acceptance criteria:
  # - POST /api/v1/splits returns 201 with the created transactions in the
  #   existing transaction JSON shape (ratio parts as integers).
  test "POST /api/v1/splits books one row per positioned portfolio", %{conn: conn} do
    %{a: world_a, b: world_b, security: security} = split_world()

    response =
      conn
      |> api_conn()
      |> post("/api/v1/splits", Jason.encode!(split_body(security)))
      |> json_response(201)

    transactions = response["data"]["transactions"]
    assert length(transactions) == 2

    for tx <- transactions do
      assert tx["type"] == "split"
      assert tx["security_id"] == security.id
      assert tx["date"] == "2026-02-02"
      assert tx["split_ratio_numerator"] == 2
      assert tx["split_ratio_denominator"] == 1
      assert tx["quantity"] == nil
      assert tx["price"] == nil
    end

    booked = transactions |> Enum.map(& &1["portfolio_id"]) |> Enum.sort()
    assert booked == Enum.sort([world_a.portfolio.id, world_b.portfolio.id])
  end

  # User story (issue #589, API contract):
  # As the operator of a locally exposed API,
  # I want the split endpoints to require the bearer token,
  # so that the write path stays behind the same auth wall as every other
  # /api/v1 route.
  #
  # Acceptance criteria:
  # - Both endpoints return 401 JSON without credentials.
  test "split endpoints require the bearer token", %{conn: conn} do
    for path <- ["/api/v1/splits/preview", "/api/v1/splits"] do
      response =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> post(path, Jason.encode!(%{}))
        |> json_response(401)

      assert response == %{"errors" => %{"detail" => "unauthorized"}}
    end
  end

  # User story (ADR-0028 §1, issue #589):
  # As an API consumer sending an invalid split request,
  # I want 422 errors in the API's field-keyed shape and 404 for an unknown
  # security,
  # so that failures are machine-readable like every other endpoint's.
  #
  # Acceptance criteria:
  # - Identity ratio, future date and no-position requests return 422 with
  #   %{errors: %{field => [message]}}.
  # - A second same-day split returns 422 naming the existing event.
  # - An unknown security returns 404.
  test "split endpoints translate context errors into API error shapes", %{conn: conn} do
    %{security: security} = split_world()

    identity =
      conn
      |> api_conn()
      |> post(
        "/api/v1/splits/preview",
        Jason.encode!(split_body(security, %{"ratio_numerator" => 5, "ratio_denominator" => 5}))
      )
      |> json_response(422)

    assert [message] = identity["errors"]["ratio"]
    assert message =~ "share count"

    invalid_ratio =
      conn
      |> api_conn()
      |> post(
        "/api/v1/splits",
        Jason.encode!(split_body(security, %{"ratio_numerator" => 0}))
      )
      |> json_response(422)

    assert [message] = invalid_ratio["errors"]["ratio"]
    assert message =~ "positive integers"

    future =
      conn
      |> api_conn()
      |> post(
        "/api/v1/splits",
        Jason.encode!(
          split_body(security, %{"date" => Date.to_iso8601(Date.add(Date.utc_today(), 3))})
        )
      )
      |> json_response(422)

    assert [message] = future["errors"]["date"]
    assert message =~ "future"

    unheld = create_security!(name: "Api Unheld Co", ticker: "AUN")

    no_position =
      conn
      |> api_conn()
      |> post("/api/v1/splits", Jason.encode!(split_body(unheld)))
      |> json_response(422)

    assert [message] = no_position["errors"]["security_id"]
    assert message =~ "position"

    not_found =
      conn
      |> api_conn()
      |> post(
        "/api/v1/splits/preview",
        Jason.encode!(split_body(security, %{"security_id" => security.id + 1000}))
      )
      |> json_response(404)

    assert not_found["errors"]["detail"] == "not found"

    # Book once, then retry: the conflict names the existing event.
    assert {:ok, [existing | _]} =
             Splits.book_split(Actor.api_token_rw(), %{
               security_id: security.id,
               date: ~D[2026-02-02],
               ratio_numerator: 2,
               ratio_denominator: 1
             })

    conflict =
      conn
      |> api_conn()
      |> post("/api/v1/splits", Jason.encode!(split_body(security)))
      |> json_response(422)

    assert [message] = conflict["errors"]["date"]
    assert message =~ "already booked"
    assert message =~ "##{existing.id}"
    assert message =~ "2:1"
    assert message =~ "2026-02-02"
  end
end
