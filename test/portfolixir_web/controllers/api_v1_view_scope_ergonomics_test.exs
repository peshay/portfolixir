defmodule PortfolixirWeb.ApiV1ViewScopeErgonomicsTest do
  # Issue #740: FR-37's read-ergonomics parameters reached the portfolio scope
  # but skipped two reads the agent actually makes — the view-scoped valuation
  # (`include_positions`) and the position-target listing (`min_drift`). Both
  # halves land here with the spelling the shipped endpoints use.
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1, buy!: 3, deposit!: 4, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.Targets

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp get_json(conn, path, status \\ 200) do
    conn |> api_conn() |> get(path) |> json_response(status)
  end

  # User story (issue #740, FR-37 on the view axis):
  # As the operating agent reading a bucket view's total wealth,
  # I want include_positions=false on the view valuation,
  # so that a cross-portfolio roll-up costs the three figures I read, not
  # every position row — the same parameter the portfolio valuation has.
  #
  # Acceptance criteria:
  # - include_positions=false omits the position rows and states
  #   positions_included: false; totals and cash balances survive.
  # - The default shape is unchanged; an invalid value is a 422.
  test "the view valuation takes include_positions", %{conn: conn} do
    world = base_world(name: "View Ergo", cash_name: "Ergo Cash", depot_name: "Ergo Depot")
    security = create_security!(name: "World Co.", ticker: "WRLD", asset_class: "equity")
    put_quote!(security, ~D[2026-06-01], "10")
    deposit!(world, "300", ~D[2026-01-01], [])
    buy!(world, security, quantity: "10", price: "10")

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "All", include_all: true})
    base = "/api/v1/views/#{view.id}/valuation"

    full = get_json(conn, base)["data"]
    assert full["positions_included"] == true
    assert [_position] = full["positions"]

    slim = get_json(conn, base <> "?include_positions=false")["data"]
    assert slim["positions_included"] == false
    refute Map.has_key?(slim, "positions")
    assert slim["total_with_cash"] == full["total_with_cash"]
    assert slim["total_value"] == "100"
    assert length(slim["cash_balances"]) == 1
    assert slim["view"] == %{"id" => view.id, "name" => "All"}

    assert %{"errors" => %{"include_positions" => ["is invalid"]}} =
             get_json(conn, base <> "?include_positions=maybe", 422)
  end

  # User story (issue #740, FR-37 on the position level):
  # As the operating agent asking which position targets drifted,
  # I want min_drift on the position-target listing,
  # so that the rows that deviate come back — spelled and measured exactly
  # as the allocation read's min_drift one level up.
  #
  # Acceptance criteria:
  # - min_drift keeps only position rows whose |drift_weight| meets the
  #   threshold; kept rows carry drift_weight (actual − position SOLL, as the
  #   allocation computes it).
  # - The response states min_drift, position_targets_total (pre-filter) and
  #   a drift basis; without min_drift the shape is unchanged.
  # - An invalid threshold is a 422.
  test "the position-target listing takes min_drift", %{conn: conn} do
    world = base_world(name: "Drift Ergo", cash_name: "Drift Cash", depot_name: "Drift Depot")
    owner = Actor.owner_ui()

    {:ok, classification} = Classifications.create_classification(owner, %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(owner, %{classification_id: classification.id, name: "Core"})

    on_target = create_security!(name: "On Target Co.", ticker: "ONTG", asset_class: "equity")
    off_target = create_security!(name: "Off Target Co.", ticker: "OFTG", asset_class: "equity")
    filler = create_security!(name: "Filler Co.", ticker: "FILL", asset_class: "equity")

    for security <- [on_target, off_target, filler] do
      {:ok, _} = Classifications.assign_security(owner, security.id, classification.id, core.id)
    end

    # Cash funds the buys exactly, so the steering basis is securities only:
    # on_target 50 %, off_target 30 %, filler 20 % of the basis. The plan sums
    # to 100 % (0.5 + 0.2 + 0.3), so drift is the plain actual − target.
    deposit!(world, "100", ~D[2026-01-01], [])
    buy!(world, on_target, quantity: "5", price: "10")
    buy!(world, off_target, quantity: "3", price: "10")
    buy!(world, filler, quantity: "2", price: "10")

    for security <- [on_target, off_target, filler] do
      put_quote!(security, ~D[2026-06-01], "10")
    end

    {:ok, _} =
      Targets.set_targets(owner, world.portfolio.id, classification.id, [
        %{"category_id" => core.id, "security_id" => on_target.id, "target_weight" => "0.5"},
        %{"category_id" => core.id, "security_id" => off_target.id, "target_weight" => "0.2"},
        %{"category_id" => core.id, "security_id" => filler.id, "target_weight" => "0.3"}
      ])

    base = "/api/v1/portfolios/#{world.portfolio.id}/position_targets"

    plain = get_json(conn, base)["data"]
    assert length(plain["position_targets"]) == 3
    assert plain["position_targets_total"] == 3
    assert plain["min_drift"] == nil
    assert plain["drift_basis"] == nil
    refute Enum.any?(plain["position_targets"], &Map.has_key?(&1, "drift_weight"))

    # on_target drifts 0; off_target +0.1 (30 % actual vs 20 % SOLL); filler
    # −0.1 (20 % vs 30 %). The comparison is on |drift_weight|, inclusive.
    filtered = get_json(conn, base <> "?min_drift=0.05")["data"]

    assert Enum.map(filtered["position_targets"], &{&1["security_id"], &1["drift_weight"]}) ==
             [{off_target.id, "0.1"}, {filler.id, "-0.1"}]

    assert filtered["min_drift"] == "0.05"
    assert filtered["position_targets_total"] == 3
    assert filtered["drift_basis"] =~ "allocation"
    # The roll-up is untouched by the row filter.
    assert [%{"category_id" => core_id}] = filtered["effective_targets"]
    assert core_id == core.id

    assert get_json(conn, base <> "?min_drift=0.15")["data"]["position_targets"] == []

    everything = get_json(conn, base <> "?min_drift=0")["data"]
    assert length(everything["position_targets"]) == 3
    assert Enum.all?(everything["position_targets"], &is_binary(&1["drift_weight"]))

    assert %{"errors" => %{"min_drift" => ["is invalid"]}} =
             get_json(conn, base <> "?min_drift=lots", 422)

    assert %{"errors" => %{"min_drift" => ["is invalid"]}} =
             get_json(conn, base <> "?min_drift=-0.1", 422)
  end
end
