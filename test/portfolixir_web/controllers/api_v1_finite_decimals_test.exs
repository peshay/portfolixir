defmodule PortfolixirWeb.ApiV1FiniteDecimalsTest do
  # E25 S4, G15 (#889): the drift-threshold parser compared a parsed
  # non-finite decimal without checking it, so the request answered 500
  # instead of 422. Every decimal query parser now shares one finite-decimal
  # helper (`Portfolixir.Input.BoundedDecimal.parse/1`).
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications

  @non_finite ["NaN", "nan", "Infinity", "-Infinity", "inf", "-inf"]

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    world = base_world(name: "Finite")

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    %{conn: conn, world: world, classification: classification}
  end

  # User story:
  # As the operator's agent asking for the rows that drift,
  # I want a threshold that is not a finite number refused as a field error,
  # so that a typo costs me one round trip and never a server error.
  #
  # Acceptance criteria:
  # - min_drift NaN, Infinity or -Infinity (any spelling the decimal parser
  #   reads) answers 422 naming min_drift on the allocation read and on the
  #   position-target listing.
  # - A finite threshold still answers 200.
  test "non-finite min_drift values answer 422 on both drift reads",
       %{conn: conn, world: world, classification: classification} do
    pid = world.portfolio.id
    cid = classification.id

    paths = [
      "/api/v1/portfolios/#{pid}/allocation?classification_id=#{cid}&min_drift=",
      "/api/v1/portfolios/#{pid}/position_targets?classification_id=#{cid}&min_drift="
    ]

    for path <- paths, value <- @non_finite do
      body = conn |> get(path <> URI.encode_www_form(value)) |> json_response(422)
      assert Map.has_key?(body["errors"], "min_drift"), "#{path}#{value}: #{inspect(body)}"
    end

    for path <- paths do
      assert conn |> get(path <> "0.05") |> json_response(200)
    end
  end

  # Acceptance criteria:
  # - The risk read's threshold objects and risk_free_rate refuse a
  #   non-finite value the same way.
  test "the risk read refuses a non-finite threshold or rate", %{conn: conn, world: world} do
    pid = world.portfolio.id

    for value <- @non_finite do
      encoded = URI.encode_www_form(value)

      assert conn
             |> get("/api/v1/portfolios/#{pid}/risk?risk_free_rate=#{encoded}")
             |> json_response(422)

      assert conn
             |> get("/api/v1/portfolios/#{pid}/risk?stock_thresholds[warn]=#{encoded}")
             |> json_response(422)
    end
  end
end
