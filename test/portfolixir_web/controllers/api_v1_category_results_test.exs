defmodule PortfolixirWeb.ApiV1CategoryResultsTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, create_security!: 1, buy!: 3, deposit!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications

  @auth {"authorization", "Bearer test-api-token"}

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
  end

  defp get_json(conn, path), do: conn |> api_conn() |> get(path)

  defp seed do
    world = base_world()

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    alpha = create_security!(name: "Alpha AG", ticker: "ALP")
    dark = create_security!(name: "Dark AG", ticker: "DRK")

    for security <- [alpha, dark] do
      {:ok, _} =
        Classifications.assign_security(
          Actor.owner_ui(),
          security.id,
          classification.id,
          core.id
        )
    end

    deposit!(world, "10000", ~D[2026-01-01])
    buy!(world, alpha, quantity: "10", price: "100")
    buy!(world, dark, quantity: "10", price: "50")

    # Alpha is priced at 150 (invested 1000, now 1500); Dark has no quote at
    # all, so its result is not derivable.
    Portfolixir.WorldFixtures.put_quote!(alpha, Date.utc_today(), "150")

    Map.merge(world, %{classification: classification, core: core, alpha: alpha, dark: dark})
  end

  # User story (#712, ADR-0041 §7):
  # As the LLM agent maintaining this portfolio,
  # I want each category's invested, current value and result in one call, with
  # the rows behind it and the rows it could not cover,
  # so that I can answer "how is Core doing?" without joining holdings to the
  # classification tree myself — and without mistaking a gap for a zero.
  #
  # Acceptance criteria:
  # - Financial values serialize as Decimal STRINGS (AR-11).
  # - The payload carries the one-line computation basis of ADR-0041 §1.
  # - It carries covered/total member counts and the excluded rows with their
  #   reasons, so an aggregate always has an address.
  # - The member positions ship with the aggregate (§3), never as a follow-up.
  test "reports the money-weighted category roll-up with its members and gaps", %{conn: conn} do
    world = seed()

    data =
      get_json(
        conn,
        "/api/v1/portfolios/#{world.portfolio.id}/category-results" <>
          "?classification_id=#{world.classification.id}"
      )
      |> json_response(200)
      |> Map.fetch!("data")

    # §1: the basis is one line, and it is stated rather than implied.
    assert data["basis"] == "current_composition"

    assert [core] = data["categories"]
    assert core["category_id"] == world.core.id
    assert core["name"] == "Core"

    # Decimal strings, not numbers (AR-11).
    assert core["invested"] == "1000"
    assert core["current_value"] == "1500"
    assert core["result_abs"] == "500"
    assert core["result_pct"] == "0.5"

    # §4: the unpriceable member is out of BOTH sides of the sum and named.
    assert core["covered_count"] == 1
    assert core["member_count"] == 2
    assert [excluded] = core["excluded"]
    assert excluded["security_name"] == "Dark AG"
    assert excluded["reason"] == "no_usable_price"

    # §3: the rows behind the aggregate ship with it.
    assert [position] = core["positions"]
    assert position["security_name"] == "Alpha AG"
    assert position["invested"] == "1000"
    assert position["result_abs"] == "500"
    assert position["result_pct"] == "0.5"
  end

  test "requires a classification and 404s an unknown portfolio", %{conn: conn} do
    world = seed()

    assert get_json(conn, "/api/v1/portfolios/#{world.portfolio.id}/category-results")
           |> json_response(422) == %{"errors" => %{"classification_id" => ["is required"]}}

    assert get_json(conn, "/api/v1/portfolios/9999999/category-results?classification_id=1")
           |> json_response(404)

    # A non-numeric id is a 404, not a 500.
    assert get_json(conn, "/api/v1/portfolios/not-an-id/category-results?classification_id=1")
           |> json_response(404)

    # ...and so is a classification that does not exist: the engine's
    # {:error, :not_found} must not surface as a crash.
    assert get_json(
             conn,
             "/api/v1/portfolios/#{world.portfolio.id}/category-results" <>
               "?classification_id=9999999"
           )
           |> json_response(404)
  end
end
