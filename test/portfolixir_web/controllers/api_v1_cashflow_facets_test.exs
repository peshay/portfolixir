defmodule PortfolixirWeb.ApiV1CashflowFacetsTest do
  # The Cash-flow facets' API coverage (two-way rule): #724 realized gains.
  # Financial values serialize as Decimal strings; every metric payload
  # carries its computation basis (AGENTS.md metric rule).
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Fx
  alias Portfolixir.WorldFixtures

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp get_json(conn, path) do
    conn |> api_conn() |> get(path) |> json_response(200)
  end

  # User story (issue #724):
  # As the operating LLM agent,
  # I want the realized-gains roll-up over the API,
  # so that the figure the operator reads on /cashflow?tab=realized is the
  # same figure I can reason over — basis included.
  #
  # Acceptance criteria:
  # - GET /api/v1/realized_gains serves the annual matrix with Decimal
  #   strings, the excluded block, and the computation basis (series,
  #   window, reference, gaps).
  test "GET /api/v1/realized_gains serves the converted roll-up with its basis", %{conn: conn} do
    world = WorldFixtures.base_world()
    eur = WorldFixtures.create_security!(name: "Euro Equity", ticker: "EEQ", currency: "EUR")
    WorldFixtures.buy!(world, eur, quantity: "10", price: "100", date: ~D[2026-01-05])

    WorldFixtures.sell!(world, eur,
      quantity: "10",
      price: "120",
      fees: "9.90",
      date: ~D[2026-03-10]
    )

    gbp = WorldFixtures.create_security!(name: "Pound Equity", ticker: "PEQ", currency: "GBP")

    gbp_world =
      Map.merge(
        world,
        WorldFixtures.add_depot(world.portfolio,
          currency: "GBP",
          cash_name: "GBP Cash",
          depot_name: "GBP Depot"
        )
      )

    WorldFixtures.buy!(gbp_world, gbp,
      quantity: "2",
      price: "10",
      date: ~D[2026-01-09],
      currency: "GBP"
    )

    WorldFixtures.sell!(gbp_world, gbp,
      quantity: "2",
      price: "30",
      date: ~D[2026-02-20],
      currency: "GBP"
    )

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "GBP",
          date: ~D[2026-03-01],
          rate: "0.85",
          source: "manual"
        }
      ])

    response = get_json(conn, "/api/v1/realized_gains")

    assert %{"data" => data} = response
    assert data["base_currency"] == "EUR"
    assert [%{"year" => 2026, "months" => months, "total" => "190.1"}] = data["annual"]
    assert months["3"] == "190.1"
    assert data["excluded"] == %{"count" => 1, "securities" => ["Pound Equity"]}
    assert data["conversion_note"] =~ "EUR hub"

    basis = data["computation_basis"]
    assert basis["series"] =~ "FIFO"
    assert basis["window"] =~ "close date"
    assert basis["reference"] =~ "EUR hub"
    assert basis["gaps"] =~ "excluded"
  end
end
