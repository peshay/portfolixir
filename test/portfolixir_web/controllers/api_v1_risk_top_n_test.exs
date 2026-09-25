defmodule PortfolixirWeb.ApiV1RiskTopNTest do
  # E25 S4, F72 (#889): the risk read's Top-N had no upper bound, and its
  # correlation matrix grows with the square of the names it covers, so one
  # call could ask for work without end. top_n now follows the list reads'
  # capped-and-echoed contract, and the matrix covers a fixed number of the
  # leading names, stated in the payload's computation basis.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, create_security!: 1, buy!: 3, deposit!: 3]

  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Portfolios.Risk
  alias Portfolixir.Portfolios.RiskMetrics

  @names 23

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    world = base_world()
    deposit!(world, "100000", ~D[2026-01-01])

    for index <- 1..@names do
      security =
        create_security!(name: "Synthetic Name #{index}", ticker: "SN#{index}")

      buy!(world, security, quantity: "#{index}", price: "10")

      {:ok, _} =
        Quotes.upsert_many(security.id, [
          %{date: ~D[2026-01-03], close: "10", source: "manual"}
        ])
    end

    %{conn: conn, world: world}
  end

  defp risk(conn, world, query) do
    conn
    |> get("/api/v1/portfolios/#{world.portfolio.id}/risk#{query}")
    |> json_response(200)
    |> Map.fetch!("data")
  end

  # User story:
  # As the agent reading a portfolio's risk over the API,
  # I want an oversized top_n capped and the applied value echoed, and the
  # correlation matrix bounded to a stated number of leading names,
  # so that one read costs a bounded amount of work and tells me what it
  # covered.
  #
  # Acceptance criteria:
  # - top_n above the maximum answers 200 with top_n echoed at the maximum;
  #   the default and an in-range value are echoed as applied.
  # - The correlation matrix covers at most the fixed number of leading
  #   names, its pair count stays within that bound, and the payload names
  #   the number it covered in correlations and in computation_basis.
  test "an oversized top_n is echoed at the cap and the correlations stay bounded", ctx do
    %{conn: conn, world: world} = ctx
    max_top_n = Risk.max_top_n()
    names = RiskMetrics.max_correlated_names()

    assert names < @names

    default = risk(conn, world, "")
    assert default["top_n"] == 10
    assert length(default["top_holdings"]) == 10

    assert risk(conn, world, "?top_n=3")["top_n"] == 3

    data = risk(conn, world, "?top_n=#{max_top_n * 1000}")

    assert data["top_n"] == max_top_n
    assert length(data["top_holdings"]) == @names

    correlations = data["metrics"]["correlations"]

    assert correlations["leading_names"] == names
    assert length(correlations["security_ids"]) == names
    assert length(correlations["pairs"]) <= div(names * (names - 1), 2)

    assert correlations["security_ids"] ==
             data["top_holdings"] |> Enum.take(names) |> Enum.map(& &1["security_id"])

    assert data["metrics"]["computation_basis"]["input_series"] =~
             "at most the #{names} leading names"
  end
end
