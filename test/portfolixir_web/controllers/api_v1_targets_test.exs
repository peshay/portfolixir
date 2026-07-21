defmodule PortfolixirWeb.ApiV1TargetsTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, create_security!: 1, buy!: 3, put_quote!: 3, deposit!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.Targets

  @auth {"authorization", "Bearer test-api-token"}

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
  end

  defp get_json(conn, path), do: conn |> api_conn() |> get(path)
  defp put_json(conn, path, body), do: conn |> api_conn() |> put(path, Jason.encode!(body))
  defp patch_json(conn, path, body), do: conn |> api_conn() |> patch(path, Jason.encode!(body))
  defp delete_json(conn, path), do: conn |> api_conn() |> delete(path)

  defp setup_world do
    world = base_world()

    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    security = create_security!(name: "Core Equity", ticker: "CORE", asset_class: "equity")

    {:ok, _} =
      Classifications.assign_security(
        Portfolixir.Actor.owner_ui(),
        security.id,
        classification.id,
        core.id
      )

    # Fund the cash account so the buy leaves it at zero: counting cash is 0, so
    # the allocation basis here is securities only (issue #335).
    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, security, quantity: "10", price: "100")
    put_quote!(security, ~D[2026-06-01], "120")

    Map.merge(world, %{classification: classification, core: core, security: security})
  end

  # User story:
  # As an API client (and the LLM I connect over MCP),
  # I want to store target weights and read a SOLL/IST allocation breakdown,
  # so that my weekly drift check runs entirely against the Portfolixir API.
  #
  # Acceptance criteria:
  # - PUT targets stores weights and GET targets returns them.
  # - GET allocation reports market value, actual/target weight and drift per
  #   category, against the stored quote-based valuation.
  # - GET allocation without classification_id returns 422.
  # - An out-of-range weight returns 422; DELETE removes a target.
  test "stores targets and reports allocation drift through the API", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    assert get_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets")
           |> json_response(200) == %{"data" => %{"targets" => []}}

    set =
      put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
        "classification_id" => classification.id,
        "targets" => [%{"category_id" => core.id, "target_weight" => "0.8"}]
      })

    assert %{"data" => %{"targets" => [target]}} = json_response(set, 200)
    assert target["category_id"] == core.id
    assert target["target_weight"] == "0.8"

    allocation =
      get_json(
        conn,
        "/api/v1/portfolios/#{portfolio.id}/allocation?classification_id=#{classification.id}"
      )

    assert %{"data" => data} = json_response(allocation, 200)
    assert data["total_value"] == "1200"

    assert [category] = data["categories"]
    assert category["category_id"] == core.id
    assert category["market_value"] == "1200"
    assert category["actual_weight"] == "1"
    assert category["target_weight"] == "0.8"
    # actual - target (positive = overweight, ADR-0023): 1 - 0.8 = 0.2.
    assert category["drift_weight"] == "0.2"
    assert category["drift_value"] == "240"

    # Drill-down with display-only rebalancing hints (ADR-0023): the position
    # carries its quantity, its share of the category drift and the indicative
    # quantity to sell at the implied unit price (240 / 120 = 2). Positive =
    # sell; nothing is persisted or transmitted as an order.
    assert [position] = category["positions"]
    assert position["security_name"] == "Core Equity"
    assert position["quantity"] == "10"
    assert position["drift_value"] == "240"
    assert position["rebalance_quantity"] == "2"

    # The allocation carries a cash row (here cash is 0) and the Σ top level.
    assert data["cash"]["market_value"] == "0"
    assert data["cash"]["actual_weight"] == "0"
    assert data["cash"]["target_weight"] == "0"
    assert data["top_level_target_sum"] == "0.8"

    # Core has no children carrying a target, so its advisory child_target_sum is
    # null (issue #378): the consumer can tell "no comparison offered" apart from
    # "the children sum to zero".
    assert category["child_target_sum"] == nil
  end

  # User story:
  # As an API client (and the LLM I connect over MCP),
  # I want each allocation row to carry the advisory sum of its direct children's
  # targets (child_target_sum) as a Decimal string,
  # so that I can flag target-tree inconsistency without recomputing it.
  #
  # Acceptance criteria:
  # - A parent row whose direct children carry targets exposes child_target_sum
  #   as a Decimal string (the sum of those children's targets).
  # - A row without child targets exposes child_target_sum as null.
  test "exposes the advisory child_target_sum per allocation row", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    {:ok, tech} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Tech",
        parent_id: core.id
      })

    {:ok, emerging} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Emerging",
        parent_id: core.id
      })

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.6"},
        %{"category_id" => tech.id, "target_weight" => "0.3"},
        %{"category_id" => emerging.id, "target_weight" => "0.2"}
      ])

    data =
      get_json(
        conn,
        "/api/v1/portfolios/#{portfolio.id}/allocation?classification_id=#{classification.id}"
      )
      |> json_response(200)
      |> Map.fetch!("data")

    rows = Map.new(data["categories"], &{&1["category_id"], &1})

    # Core's direct children (Tech 0.3 + Emerging 0.2) sum to 0.5, rendered as a
    # Decimal string.
    core_row = rows[core.id]
    assert core_row["child_target_sum"] == "0.5"
    assert is_binary(core_row["child_target_sum"])

    # The leaf children have no targeted children of their own, so null.
    assert rows[tech.id]["child_target_sum"] == nil
    assert rows[emerging.id]["child_target_sum"] == nil
  end

  # User story:
  # As an API client (and the LLM I connect over MCP) steering a cash quote,
  # I want to set the portfolio's cash target and read the allocation cash row,
  # so that cash is part of the same SOLL/IST basis as the categories.
  #
  # Acceptance criteria:
  # - PATCH /portfolios/:id sets cash_target_weight; it is returned and feeds the
  #   allocation cash row and the Σ top level.
  # - The 100% basis is securities + counting cash, so a category percentage
  #   shrinks once cash is present.
  test "sets the cash target and reports it in the allocation cash row", %{conn: conn} do
    world = setup_world()
    %{portfolio: portfolio, classification: classification} = world

    # Add 120 EUR of counting cash on top of the (funded) 1200 EUR of securities:
    # basis becomes 1320; the core category is 1200/1320 and cash is 120/1320.
    deposit!(world, "120", ~D[2026-06-02])

    patched =
      patch_json(conn, "/api/v1/portfolios/#{portfolio.id}", %{
        "portfolio" => %{"cash_target_weight" => "0.05"}
      })

    assert %{"data" => updated} = json_response(patched, 200)
    assert updated["cash_target_weight"] == "0.05"

    data =
      get_json(
        conn,
        "/api/v1/portfolios/#{portfolio.id}/allocation?classification_id=#{classification.id}"
      )
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["total_value"] == "1320"
    assert data["cash"]["market_value"] == "120"
    assert data["cash"]["target_weight"] == "0.05"
    assert data["top_level_target_sum"] == "0.05"

    [category] = data["categories"]
    # Shrunk from 1 (securities-only) to 1200/1320 once cash joins the basis.
    refute category["actual_weight"] == "1"
  end

  test "requires classification_id for the allocation endpoint", %{conn: conn} do
    %{portfolio: portfolio} = setup_world()

    response =
      get_json(conn, "/api/v1/portfolios/#{portfolio.id}/allocation") |> json_response(422)

    assert response == %{"errors" => %{"classification_id" => ["is required"]}}
  end

  test "rejects an out-of-range target weight and deletes targets", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    rejected =
      put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
        "classification_id" => classification.id,
        "targets" => [%{"category_id" => core.id, "target_weight" => "1.5"}]
      })

    assert %{"errors" => %{"target_weight" => [_ | _]}} = json_response(rejected, 422)

    stored =
      put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
        "classification_id" => classification.id,
        "targets" => [%{"category_id" => core.id, "target_weight" => "0.5"}]
      })

    assert %{"data" => %{"targets" => [_]}} = json_response(stored, 200)

    deleted =
      delete_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets/#{core.id}")
      |> json_response(200)

    assert deleted == %{"data" => %{"deleted" => 1}}
  end

  test "rejects a malformed targets list with 422 instead of crashing", %{conn: conn} do
    %{portfolio: portfolio, classification: classification} = setup_world()

    response =
      put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
        "classification_id" => classification.id,
        "targets" => [1]
      })

    assert %{"errors" => %{"targets" => [_ | _]}} = json_response(response, 422)
  end

  # User story:
  # As an API client (and the LLM I connect over MCP),
  # I want clear 404/422 errors for unknown portfolios, missing fields and
  # cross-tree categories,
  # so that a bad targets request fails loudly instead of mis-filing a weight.
  #
  # Acceptance criteria:
  # - An unknown or non-numeric portfolio id returns 404 on index/set/delete.
  # - A set request without classification_id returns 422; without a targets
  #   list returns 422 ("must be a list").
  # - Setting a target against an unknown classification returns 404.
  # - A category from another classification returns 422 (category mismatch).
  # - GET targets scoped by classification_id returns only that tree's targets.
  test "returns 404 for an unknown or non-numeric portfolio", %{conn: conn} do
    assert get_json(conn, "/api/v1/portfolios/999999/targets") |> json_response(404) ==
             %{"errors" => %{"detail" => "not found"}}

    assert put_json(conn, "/api/v1/portfolios/not-a-number/targets", %{
             "classification_id" => 1,
             "targets" => []
           })
           |> json_response(404) == %{"errors" => %{"detail" => "not found"}}

    assert delete_json(conn, "/api/v1/portfolios/999999/targets/1")
           |> json_response(404) == %{"errors" => %{"detail" => "not found"}}
  end

  test "returns 404 deleting a target with a non-numeric category id", %{conn: conn} do
    %{portfolio: portfolio} = setup_world()

    assert delete_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets/not-a-number")
           |> json_response(404) == %{"errors" => %{"detail" => "not found"}}
  end

  test "requires classification_id and a targets list on set", %{conn: conn} do
    %{portfolio: portfolio, core: core} = setup_world()

    missing_classification =
      put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
        "targets" => [%{"category_id" => core.id, "target_weight" => "0.5"}]
      })

    assert json_response(missing_classification, 422) ==
             %{"errors" => %{"classification_id" => ["is required"]}}

    %{classification: classification} = setup_world()

    not_a_list =
      put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
        "classification_id" => classification.id,
        "targets" => "nope"
      })

    assert json_response(not_a_list, 422) == %{"errors" => %{"targets" => ["must be a list"]}}
  end

  test "returns 404 setting targets against an unknown classification", %{conn: conn} do
    %{portfolio: portfolio, core: core} = setup_world()

    response =
      put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
        "classification_id" => 999_999,
        "targets" => [%{"category_id" => core.id, "target_weight" => "0.5"}]
      })

    assert json_response(response, 404) == %{"errors" => %{"detail" => "not found"}}
  end

  test "returns 422 for a category from another classification", %{conn: conn} do
    %{portfolio: portfolio, classification: classification} = setup_world()

    {:ok, other} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Regions"})

    {:ok, foreign} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: other.id,
        name: "Europe"
      })

    response =
      put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
        "classification_id" => classification.id,
        "targets" => [%{"category_id" => foreign.id, "target_weight" => "0.5"}]
      })

    assert %{"errors" => %{"detail" => detail}} = json_response(response, 422)
    assert detail =~ "category does not belong"
  end

  test "scopes the targets index to one classification", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.7"}
      ])

    scoped =
      get_json(
        conn,
        "/api/v1/portfolios/#{portfolio.id}/targets?classification_id=#{classification.id}"
      )
      |> json_response(200)

    assert %{"data" => %{"targets" => [target]}} = scoped
    assert target["category_id"] == core.id

    # A different classification id scopes to an empty list.
    empty =
      get_json(
        conn,
        "/api/v1/portfolios/#{portfolio.id}/targets?classification_id=#{classification.id + 999}"
      )
      |> json_response(200)

    assert empty == %{"data" => %{"targets" => []}}
  end

  # User story:
  # As an API client (and the LLM I connect over MCP) steering several coherent
  # plans,
  # I want the target read/write endpoints to accept a `view` parameter (ADR-0020),
  # so that I can store and read a separate SOLL plan per view without the plans
  # bleeding into each other.
  #
  # Acceptance criteria:
  # - PUT/GET targets with `view=<id>` write/read only that view's plan; the
  #   Gesamt plan (view omitted) stays untouched and independent.
  # - DELETE targets with `view=<id>` removes only that view's target.
  # - The plans are independent: a weight set under a view is invisible to Gesamt
  #   and vice versa.
  test "stores and reads a view-scoped target plan independently of Gesamt", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Stocks", include_all: true})

    # Gesamt plan: 0.4
    put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
      "classification_id" => classification.id,
      "targets" => [%{"category_id" => core.id, "target_weight" => "0.4"}]
    })

    # View plan: 0.9, scoped by the `view` param.
    set =
      put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
        "classification_id" => classification.id,
        "view" => view.id,
        "targets" => [%{"category_id" => core.id, "target_weight" => "0.9"}]
      })

    assert %{"data" => %{"targets" => [target]}} = json_response(set, 200)
    assert target["target_weight"] == "0.9"
    assert is_binary(target["target_weight"])

    # Reading the view's plan returns only its 0.9.
    view_read =
      get_json(
        conn,
        "/api/v1/portfolios/#{portfolio.id}/targets?classification_id=#{classification.id}&view=#{view.id}"
      )
      |> json_response(200)

    assert %{"data" => %{"targets" => [%{"target_weight" => "0.9"}]}} = view_read

    # Reading Gesamt (view omitted) still returns 0.4 — the plans are independent.
    gesamt_read =
      get_json(
        conn,
        "/api/v1/portfolios/#{portfolio.id}/targets?classification_id=#{classification.id}"
      )
      |> json_response(200)

    assert %{"data" => %{"targets" => [%{"target_weight" => "0.4"}]}} = gesamt_read

    # Deleting the view's target leaves Gesamt's untouched.
    assert delete_json(
             conn,
             "/api/v1/portfolios/#{portfolio.id}/targets/#{core.id}?view=#{view.id}"
           )
           |> json_response(200) == %{"data" => %{"deleted" => 1}}

    assert get_json(
             conn,
             "/api/v1/portfolios/#{portfolio.id}/targets?classification_id=#{classification.id}&view=#{view.id}"
           )
           |> json_response(200) == %{"data" => %{"targets" => []}}

    gesamt_after =
      get_json(
        conn,
        "/api/v1/portfolios/#{portfolio.id}/targets?classification_id=#{classification.id}"
      )
      |> json_response(200)

    assert %{"data" => %{"targets" => [%{"target_weight" => "0.4"}]}} = gesamt_after
  end

  # User story:
  # As an API client reading the allocation under a view,
  # I want the SOLL side of the allocation to reflect that view's plan (ADR-0020),
  # so that the drift table steers against the view's coherent 100% plan, not the
  # Gesamt one.
  #
  # Acceptance criteria:
  # - GET allocation?view=<id> echoes the active view (#445) AND reports the
  #   view's plan target/drift, not the Gesamt plan's.
  test "allocation under a view reflects that view's SOLL plan", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Stocks", include_all: true})

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.4"}
      ])

    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio.id,
        classification.id,
        [%{"category_id" => core.id, "target_weight" => "0.9"}],
        view: view.id
      )

    data =
      get_json(
        conn,
        "/api/v1/portfolios/#{portfolio.id}/allocation?classification_id=#{classification.id}&view=#{view.id}"
      )
      |> json_response(200)
      |> Map.fetch!("data")

    # #445: the active view is echoed.
    assert data["view"] == %{"id" => view.id, "name" => "Stocks"}

    # SOLL side reflects the view's plan (0.9), not Gesamt's (0.4).
    [category] = data["categories"]
    assert category["target_weight"] == "0.9"
    assert category["actual_weight"] == "1"
    # actual - target (ADR-0023): 1 - 0.9 = 0.1 overweight.
    assert category["drift_weight"] == "0.1"
    assert data["top_level_target_sum"] == "0.9"
  end

  # User story:
  # As an API client (and the LLM I connect over MCP) steering a cash quote per
  # view,
  # I want to read and write the per-plan cash target over the API (ADR-0020 — it
  # moved out of the portfolio object),
  # so that each view's plan owns its own cash steering and the legacy portfolio
  # cash target keeps working as the Gesamt cash target.
  #
  # Acceptance criteria:
  # - PUT /portfolios/:id/cash_target sets the cash target; GET returns it; both
  #   accept `view` (omitted = Gesamt) and serialize the decimal as a string.
  # - A view's cash target is independent of the Gesamt cash target.
  # - The legacy portfolio PATCH `cash_target_weight` still works and reads back
  #   as the Gesamt cash target (back-compat).
  test "reads and writes the per-plan cash target with a view scope", %{conn: conn} do
    %{portfolio: portfolio} = setup_world()
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Stocks", include_all: true})

    # No cash target yet on either plan.
    assert get_json(conn, "/api/v1/portfolios/#{portfolio.id}/cash_target")
           |> json_response(200) == %{"data" => %{"cash_target_weight" => nil}}

    # Set the Gesamt cash target.
    gesamt =
      put_json(conn, "/api/v1/portfolios/#{portfolio.id}/cash_target", %{
        "cash_target_weight" => "0.05"
      })

    assert %{"data" => %{"cash_target_weight" => "0.05"}} = json_response(gesamt, 200)

    # Set a different cash target on the view's plan.
    scoped =
      put_json(conn, "/api/v1/portfolios/#{portfolio.id}/cash_target", %{
        "view" => view.id,
        "cash_target_weight" => "0.2"
      })

    assert %{"data" => %{"cash_target_weight" => weight}} = json_response(scoped, 200)
    assert weight == "0.2"
    assert is_binary(weight)

    # The two plans are independent.
    assert get_json(conn, "/api/v1/portfolios/#{portfolio.id}/cash_target?view=#{view.id}")
           |> json_response(200) == %{"data" => %{"cash_target_weight" => "0.2"}}

    assert get_json(conn, "/api/v1/portfolios/#{portfolio.id}/cash_target")
           |> json_response(200) == %{"data" => %{"cash_target_weight" => "0.05"}}

    # Back-compat: the legacy portfolio PATCH reads/writes the Gesamt cash target.
    patched =
      patch_json(conn, "/api/v1/portfolios/#{portfolio.id}", %{
        "portfolio" => %{"cash_target_weight" => "0.07"}
      })

    assert %{"data" => %{"cash_target_weight" => "0.07"}} = json_response(patched, 200)

    # The PATCH wrote the Gesamt cash target — the view's plan is untouched.
    assert get_json(conn, "/api/v1/portfolios/#{portfolio.id}/cash_target")
           |> json_response(200) == %{"data" => %{"cash_target_weight" => "0.07"}}

    assert get_json(conn, "/api/v1/portfolios/#{portfolio.id}/cash_target?view=#{view.id}")
           |> json_response(200) == %{"data" => %{"cash_target_weight" => "0.2"}}

    # Clearing with null is accepted.
    cleared =
      put_json(conn, "/api/v1/portfolios/#{portfolio.id}/cash_target", %{
        "view" => view.id,
        "cash_target_weight" => nil
      })

    assert %{"data" => %{"cash_target_weight" => nil}} = json_response(cleared, 200)
  end

  # User story:
  # As an API client (and the LLM I connect over MCP) steering per position (#481),
  # I want to set SOLL targets on individual positions and read the category
  # roll-up over the API (ADR-0030),
  # so that the position-first SOLL model is machine-usable before the editor UI
  # ships.
  #
  # Acceptance criteria (ADR-0030, #481 slice 1):
  # - PUT /targets accepts a security_id in an entry and stores a position target
  #   (financials as strings); category-only writes are unchanged.
  # - GET /position_targets returns the position rows AND the per-category
  #   effective roll-up, surfacing an explicit/position conflict.
  # - DELETE /position_targets/:category_id/:security_id removes one position row.
  # - A position target for a security not under the category returns 422.
  test "stores, reads and deletes per-position targets through the API", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, core: core, security: security} =
      setup_world()

    # A category target coexists with the position targets under it.
    put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
      "classification_id" => classification.id,
      "targets" => [%{"category_id" => core.id, "target_weight" => "0.6"}]
    })

    set =
      put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
        "classification_id" => classification.id,
        "targets" => [
          %{"category_id" => core.id, "security_id" => security.id, "target_weight" => "0.5"}
        ]
      })

    assert %{"data" => %{"targets" => [target]}} = json_response(set, 200)
    assert target["security_id"] == security.id
    assert target["target_weight"] == "0.5"

    # The category list endpoint stays category-only (back-compat).
    category_read =
      get_json(
        conn,
        "/api/v1/portfolios/#{portfolio.id}/targets?classification_id=#{classification.id}"
      )
      |> json_response(200)

    assert %{"data" => %{"targets" => [category_row]}} = category_read
    assert category_row["category_id"] == core.id
    assert category_row["security_id"] == nil
    assert category_row["target_weight"] == "0.6"

    # The position endpoint returns the position rows plus the effective roll-up.
    data =
      get_json(
        conn,
        "/api/v1/portfolios/#{portfolio.id}/position_targets?classification_id=#{classification.id}"
      )
      |> json_response(200)
      |> Map.fetch!("data")

    # The row is self-sufficient (UAT polish round): it names its security so a
    # client does not need a second call to render "Core Equity 0.5".
    assert [%{"security_id" => psid, "security_name" => "Core Equity", "target_weight" => "0.5"}] =
             data["position_targets"]

    assert psid == security.id

    assert [effective] = data["effective_targets"]
    assert effective["category_id"] == core.id
    assert effective["explicit"] == "0.6"
    assert effective["position_sum"] == "0.5"
    assert effective["effective"] == "0.5"
    assert effective["conflict"] == true

    # Delete the single position row; the category row is untouched.
    deleted =
      delete_json(
        conn,
        "/api/v1/portfolios/#{portfolio.id}/position_targets/#{core.id}/#{security.id}"
      )
      |> json_response(200)

    assert deleted == %{"data" => %{"deleted" => 1}}

    assert get_json(conn, "/api/v1/portfolios/#{portfolio.id}/position_targets")
           |> json_response(200) ==
             %{"data" => %{"position_targets" => [], "effective_targets" => []}}

    assert %{"data" => %{"targets" => [_]}} =
             get_json(
               conn,
               "/api/v1/portfolios/#{portfolio.id}/targets?classification_id=#{classification.id}"
             )
             |> json_response(200)
  end

  # User story (#481 slice 2a, ADR-0030 — the owner's own words):
  # As an API client (and the LLM I connect over MCP),
  # I want the allocation to report position SOLL — including positions I do
  # not own yet, visible with IST 0 — and the category's EFFECTIVE target,
  # so that the machine-readable plan view matches what the owner steers.
  #
  # Acceptance criteria:
  # - Each allocation category carries `conflict` and `has_stale`; its
  #   `target_weight` is the effective target (position sum wins).
  # - Each position row carries `target_weight`, `drift_weight` (strings) and
  #   `held`; a SOLL-only row reports IST 0 and the indicative quantity at the
  #   latest quote (or null without a price). All decimals are strings.
  test "reports position SOLL and effective targets in the allocation", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, core: core, security: security} =
      setup_world()

    next_buy = create_security!(name: "Next Buy", ticker: "NEXT", asset_class: "equity")
    put_quote!(next_buy, ~D[2026-06-01], "60")

    {:ok, _} =
      Classifications.assign_security(
        Portfolixir.Actor.owner_ui(),
        next_buy.id,
        classification.id,
        core.id
      )

    # Explicit category weight 0.6 plus position rows summing to 0.75: the
    # position sum steers and the conflict is surfaced (ADR-0030).
    put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
      "classification_id" => classification.id,
      "targets" => [%{"category_id" => core.id, "target_weight" => "0.6"}]
    })

    put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
      "classification_id" => classification.id,
      "targets" => [
        %{"category_id" => core.id, "security_id" => security.id, "target_weight" => "0.5"},
        %{"category_id" => core.id, "security_id" => next_buy.id, "target_weight" => "0.25"}
      ]
    })

    data =
      get_json(
        conn,
        "/api/v1/portfolios/#{portfolio.id}/allocation?classification_id=#{classification.id}"
      )
      |> json_response(200)
      |> Map.fetch!("data")

    assert [category] = data["categories"]
    # The effective target (0.5 + 0.25), not the explicit 0.6; the mismatch is
    # flagged, and the Σ consumes the same effective value.
    assert category["target_weight"] == "0.75"
    assert category["conflict"] == true
    assert category["has_stale"] == false
    assert data["top_level_target_sum"] == "0.75"

    positions = Map.new(category["positions"], &{&1["security_name"], &1})

    # The held position with its own SOLL drift: actual 1 - 0.5 = 0.5 →
    # +600 EUR, sell 600 × 10 / 1200 = 5 units.
    held = positions["Core Equity"]
    assert held["held"] == true
    assert held["target_weight"] == "0.5"
    assert held["drift_weight"] == "0.5"
    assert held["drift_value"] == "600"
    assert held["rebalance_quantity"] == "5"
    assert is_binary(held["target_weight"]) and is_binary(held["drift_weight"])

    # The not-yet-held position: IST 0, full underweight drift (-0.25 →
    # -300 EUR), indicative buy of 300 / 60 = 5 units at the latest quote.
    wanted = positions["Next Buy"]
    assert wanted["held"] == false
    assert wanted["quantity"] == "0"
    assert wanted["market_value"] == "0"
    assert wanted["weight"] == "0"
    assert wanted["target_weight"] == "0.25"
    assert wanted["drift_weight"] == "-0.25"
    assert wanted["drift_value"] == "-300"
    assert wanted["rebalance_quantity"] == "-5"
  end

  test "rejects a position target for a security not under the category with 422", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    # A security that is not assigned under Core.
    other = create_security!(name: "Unrelated", ticker: "UNRL", asset_class: "equity")

    response =
      put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
        "classification_id" => classification.id,
        "targets" => [
          %{"category_id" => core.id, "security_id" => other.id, "target_weight" => "0.5"}
        ]
      })

    assert %{"errors" => %{"detail" => detail}} = json_response(response, 422)
    # UAT polish round: the 422 names BOTH ids so the operator can act on it
    # without re-deriving which entry was rejected.
    assert detail =~ "security #{other.id} is not under category #{core.id}"
    assert detail =~ "assign it there (or a descendant) first"
  end

  # User story:
  # As an API client (#481 fix round),
  # I want a present-but-garbage security_id to fail loudly with 422,
  # so that a malformed position write can never be silently coerced into a
  # category write that overwrites my stored category target.
  #
  # Acceptance criteria:
  # - A non-numeric string security_id returns 422.
  # - A float security_id (a JSON number like 12.5) returns 422.
  # - The stored category row is untouched and no position row appears.
  test "rejects a present-but-invalid security_id with 422 and leaves the category row untouched",
       %{conn: conn} do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
      "classification_id" => classification.id,
      "targets" => [%{"category_id" => core.id, "target_weight" => "0.6"}]
    })

    for bad <- ["abc", 12.5] do
      response =
        put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
          "classification_id" => classification.id,
          "targets" => [
            %{"category_id" => core.id, "security_id" => bad, "target_weight" => "0.9"}
          ]
        })

      assert %{"errors" => %{"targets" => [message]}} = json_response(response, 422)
      assert message =~ "security_id"
    end

    # The category row still carries its original weight; no position row exists.
    assert %{"data" => %{"targets" => [%{"target_weight" => "0.6"}]}} =
             get_json(
               conn,
               "/api/v1/portfolios/#{portfolio.id}/targets?classification_id=#{classification.id}"
             )
             |> json_response(200)

    assert %{"data" => %{"position_targets" => []}} =
             get_json(conn, "/api/v1/portfolios/#{portfolio.id}/position_targets")
             |> json_response(200)
  end

  # User story:
  # As an API client (#481 fix round),
  # I want duplicate position rows for one security rejected with a helpful 422,
  # so that a plan never carries the same security steering two categories.
  test "rejects duplicate position entries for one security with 422", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, core: core, security: security} =
      setup_world()

    response =
      put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
        "classification_id" => classification.id,
        "targets" => [
          %{"category_id" => core.id, "security_id" => security.id, "target_weight" => "0.3"},
          %{"category_id" => core.id, "security_id" => security.id, "target_weight" => "0.4"}
        ]
      })

    assert %{"errors" => %{"detail" => detail}} = json_response(response, 422)
    assert detail =~ "one position row per security"

    assert %{"data" => %{"position_targets" => []}} =
             get_json(conn, "/api/v1/portfolios/#{portfolio.id}/position_targets")
             |> json_response(200)
  end

  # User story:
  # As an API client (#481 fix round),
  # I want stale position rows surfaced in the position-targets read,
  # so that a reclassified security's row is visibly steering its old category
  # instead of being silently miscounted or dropped.
  #
  # Acceptance criteria:
  # - Each position_targets row carries stale (false while the security sits
  #   under the stored category, true after it is reassigned elsewhere).
  # - Each effective_targets entry carries has_stale.
  test "surfaces stale position rows through the position-targets endpoint", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, core: core, security: security} =
      setup_world()

    put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
      "classification_id" => classification.id,
      "targets" => [
        %{"category_id" => core.id, "security_id" => security.id, "target_weight" => "0.5"}
      ]
    })

    data =
      get_json(conn, "/api/v1/portfolios/#{portfolio.id}/position_targets")
      |> json_response(200)
      |> Map.fetch!("data")

    assert [%{"stale" => false}] = data["position_targets"]
    assert [%{"has_stale" => false}] = data["effective_targets"]

    # Reassign the security to another category: the stored row goes stale.
    {:ok, edge} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Edge"
      })

    {:ok, _} =
      Classifications.assign_security(Actor.owner_ui(), security.id, classification.id, edge.id)

    data =
      get_json(conn, "/api/v1/portfolios/#{portfolio.id}/position_targets")
      |> json_response(200)
      |> Map.fetch!("data")

    assert [%{"stale" => true}] = data["position_targets"]
    assert [%{"has_stale" => true}] = data["effective_targets"]
  end

  test "rejects an out-of-range cash target with 422", %{conn: conn} do
    %{portfolio: portfolio} = setup_world()

    response =
      put_json(conn, "/api/v1/portfolios/#{portfolio.id}/cash_target", %{
        "cash_target_weight" => "1.5"
      })

    assert %{"errors" => %{"cash_target_weight" => [_ | _]}} = json_response(response, 422)
  end

  test "returns 404 reading the cash target of an unknown portfolio", %{conn: conn} do
    assert get_json(conn, "/api/v1/portfolios/999999/cash_target")
           |> json_response(404) == %{"errors" => %{"detail" => "not found"}}
  end

  # User story:
  # As an API client,
  # I want a bad `view` parameter to fail with the existing structured error
  # contract on every target endpoint (ADR-0020, reusing #445's view_param),
  # so that a malformed or unknown view never crashes the request or silently
  # falls back to Gesamt.
  #
  # Acceptance criteria:
  # - A non-integer `view` returns 422 {view: ["is invalid"]}.
  # - An unknown `view` id returns 404.
  # - This holds across GET/PUT/DELETE targets and the cash-target endpoints.
  test "validates the view parameter on the target endpoints", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    bad = %{"errors" => %{"view" => ["is invalid"]}}
    missing = %{"errors" => %{"detail" => "not found"}}

    # GET targets
    assert get_json(
             conn,
             "/api/v1/portfolios/#{portfolio.id}/targets?classification_id=#{classification.id}&view=nope"
           )
           |> json_response(422) == bad

    assert get_json(
             conn,
             "/api/v1/portfolios/#{portfolio.id}/targets?classification_id=#{classification.id}&view=999999"
           )
           |> json_response(404) == missing

    # PUT targets
    assert put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
             "classification_id" => classification.id,
             "view" => "nope",
             "targets" => [%{"category_id" => core.id, "target_weight" => "0.5"}]
           })
           |> json_response(422) == bad

    assert put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
             "classification_id" => classification.id,
             "view" => 999_999,
             "targets" => [%{"category_id" => core.id, "target_weight" => "0.5"}]
           })
           |> json_response(404) == missing

    # DELETE targets
    assert delete_json(
             conn,
             "/api/v1/portfolios/#{portfolio.id}/targets/#{core.id}?view=nope"
           )
           |> json_response(422) == bad

    assert delete_json(
             conn,
             "/api/v1/portfolios/#{portfolio.id}/targets/#{core.id}?view=999999"
           )
           |> json_response(404) == missing

    # GET/PUT cash_target
    assert get_json(conn, "/api/v1/portfolios/#{portfolio.id}/cash_target?view=nope")
           |> json_response(422) == bad

    assert put_json(conn, "/api/v1/portfolios/#{portfolio.id}/cash_target", %{
             "view" => 999_999,
             "cash_target_weight" => "0.1"
           })
           |> json_response(404) == missing
  end
end
