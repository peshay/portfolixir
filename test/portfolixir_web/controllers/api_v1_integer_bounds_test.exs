defmodule PortfolixirWeb.ApiV1IntegerBoundsTest do
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1]

  alias PortfolixirWeb.Api.V1.IntegerParam

  @huge "99999999999999999999"

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  # User story (#856, the error contract of docs/integration/api-and-mcp.md):
  # As the operator's agent passing a count or a horizon,
  # I want a value past the stated bound refused as a 422 naming the
  # parameter,
  # so that a typo costs me one round trip — not a 500, and not a request
  # that never answers.
  #
  # Acceptance criteria:
  # - `offset` on the securities list and `days` on the research log's
  #   horizon reads answer 422 above their stated bounds.
  # - Every other integer query parameter of /api/v1 — `year`, `tax_year`,
  #   `top_n`, `limit`, the events' `days` — answers a 2xx or a 4xx for a
  #   20-digit value, within the test's timeout: never a 500, never a hang.
  test "an integer query parameter past its bound is never a 500 or a hang", %{conn: conn} do
    world = base_world(name: "Bounds")
    pid = world.portfolio.id

    refused = [
      {"/api/v1/securities?offset=#{@huge}", "offset"},
      {"/api/v1/securities?offset=#{IntegerParam.max_offset() + 1}", "offset"},
      {"/api/v1/notes/unreviewed?days=#{@huge}", "days"},
      {"/api/v1/notes/expiring?days=#{IntegerParam.max_days() + 1}", "days"}
    ]

    for {path, field} <- refused do
      %{"errors" => errors} = conn |> get(path) |> json_response(422)
      assert Map.has_key?(errors, field), "#{path} does not name #{field}: #{inspect(errors)}"
    end

    swept = [
      "/api/v1/securities?limit=#{@huge}",
      "/api/v1/portfolios/#{pid}/performance?year=#{@huge}",
      "/api/v1/portfolios/#{pid}/performance?year=-#{@huge}",
      "/api/v1/portfolios/#{pid}/income?year=#{@huge}",
      "/api/v1/portfolios/#{pid}/risk?top_n=#{@huge}",
      "/api/v1/events/upcoming?days=#{@huge}",
      "/api/v1/events/stale?days=#{@huge}",
      "/api/v1/tax/allowance_orders?holder=A&tax_year=#{@huge}",
      "/api/v1/tax/statement_snapshots?tax_year=#{@huge}",
      "/api/v1/tax/trim_budget?holder=A&tax_year=#{@huge}",
      "/api/v1/journal?limit=#{@huge}",
      "/api/v1/realized_gains?limit=#{@huge}"
    ]

    for path <- swept do
      status = conn |> get(path) |> Map.fetch!(:status)
      assert status < 500, "#{path} answered #{status}"
    end
  end
end
