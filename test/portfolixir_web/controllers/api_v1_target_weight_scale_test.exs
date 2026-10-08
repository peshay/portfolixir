defmodule PortfolixirWeb.ApiV1TargetWeightScaleTest do
  # E25 S4, G14 (#889): target weights accepted arbitrarily fine precision,
  # which the allocation's renormalisation carried into its drift figures; and
  # a position valued at 0 received a category-share drift of a signed zero.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.Target
  alias Portfolixir.Repo

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    world = base_world(name: "Weight scale")

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, growth} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Growth"
      })

    {:ok, value} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Value"
      })

    %{conn: conn, world: world, classification: classification, growth: growth, value: value}
  end

  defp assign!(security, classification, category) do
    {:ok, _} =
      Classifications.assign_security(
        Actor.owner_ui(),
        security.id,
        classification.id,
        category.id
      )
  end

  # Every string in the payload that is a non-finite decimal's spelling.
  defp non_finite(payload) when is_map(payload),
    do: payload |> Map.values() |> Enum.flat_map(&non_finite/1)

  defp non_finite(payload) when is_list(payload), do: Enum.flat_map(payload, &non_finite/1)

  defp non_finite(value) when is_binary(value) do
    if value =~ ~r/\A-?(NaN|Inf|Infinity)\z/i, do: [value], else: []
  end

  defp non_finite(_value), do: []

  # User story:
  # As the operator's agent writing a plan,
  # I want a weight finer than the plan keeps refused,
  # so that a weight is never carried into the drift figures at a precision
  # the allocation cannot hold.
  #
  # Acceptance criteria:
  # - A category or position target weight, a cash target and a portfolio's
  #   cash target with more than 6 decimal places answer 422 naming the
  #   field and store nothing; 6 decimal places are accepted.
  # - An allocation whose top-level target sum is the smallest weight a plan
  #   can hold emits no non-finite field.
  test "an over-precise weight answers 422, and a tiny top-level sum stays finite",
       %{conn: conn, world: world, classification: classification, growth: growth} do
    pid = world.portfolio.id

    body =
      conn
      |> put("/api/v1/portfolios/#{pid}/targets", %{
        "classification_id" => classification.id,
        "targets" => [%{"category_id" => growth.id, "target_weight" => "0.1234567"}]
      })
      |> json_response(422)

    assert Map.has_key?(body["errors"], "target_weight")
    assert Repo.aggregate(Target, :count) == 0

    body =
      conn
      |> put("/api/v1/portfolios/#{pid}/cash_target", %{"cash_target_weight" => "0.0500001"})
      |> json_response(422)

    assert Map.has_key?(body["errors"], "cash_target_weight")

    body =
      conn
      |> post("/api/v1/portfolios", %{
        "portfolio" => %{
          "name" => "Scaled",
          "base_currency_code" => "EUR",
          "cash_target_weight" => "0.0500001"
        }
      })
      |> json_response(422)

    assert Map.has_key?(body["errors"], "cash_target_weight")

    security = create_security!(name: "Meridian Global Equity ETF", ticker: "MGE")
    assign!(security, classification, growth)
    buy!(world, security, quantity: "10", price: "10")

    assert conn
           |> put("/api/v1/portfolios/#{pid}/targets", %{
             "classification_id" => classification.id,
             "targets" => [%{"category_id" => growth.id, "target_weight" => "0.000001"}]
           })
           |> json_response(200)

    %{"data" => allocation} =
      conn
      |> get("/api/v1/portfolios/#{pid}/allocation?classification_id=#{classification.id}")
      |> json_response(200)

    assert allocation["top_level_target_sum"] == "0.000001"
    assert non_finite(allocation) == []
  end

  # User story (#1143, #945's API half):
  # As the operator's agent writing a batch of targets,
  # I want a refused weight to name its row beside the field error, as the
  # plan editor puts the refused row first,
  # so that I can tell which row of the batch to correct.
  #
  # Acceptance criteria:
  # - A position row refused for its precision answers errors.row
  #   {category_id, security_id} beside errors.target_weight.
  # - A category row refused for its range answers errors.row with
  #   security_id null.
  # - A cash target refused for its range or precision answers errors.row
  #   "cash" beside errors.cash_target_weight.
  # - Nothing is written, and a refusal that is not a weight's carries no
  #   row.
  test "a refused target or cash-target weight names its row",
       %{conn: conn, world: world, classification: classification, growth: growth, value: value} do
    pid = world.portfolio.id
    security = create_security!(name: "Meridian Global Equity ETF", ticker: "MGE")
    assign!(security, classification, growth)

    put_targets = fn rows ->
      conn
      |> put("/api/v1/portfolios/#{pid}/targets", %{
        "classification_id" => classification.id,
        "targets" => rows
      })
      |> json_response(422)
      |> Map.fetch!("errors")
    end

    errors =
      put_targets.([
        %{"category_id" => value.id, "target_weight" => "0.4"},
        %{
          "category_id" => growth.id,
          "security_id" => security.id,
          "target_weight" => "0.1234567"
        },
        %{"category_id" => growth.id, "target_weight" => "0.6"}
      ])

    assert errors["row"] == %{"category_id" => growth.id, "security_id" => security.id}
    assert Map.has_key?(errors, "target_weight")

    errors =
      put_targets.([
        %{"category_id" => growth.id, "target_weight" => "0.5"},
        %{"category_id" => value.id, "target_weight" => "1.5"}
      ])

    assert errors["row"] == %{"category_id" => value.id, "security_id" => nil}
    assert Map.has_key?(errors, "target_weight")
    assert Repo.aggregate(Target, :count) == 0

    for weight <- ["1.2", "0.0500001"] do
      errors =
        conn
        |> put("/api/v1/portfolios/#{pid}/cash_target", %{"cash_target_weight" => weight})
        |> json_response(422)
        |> Map.fetch!("errors")

      assert errors["row"] == "cash", weight
      assert Map.has_key?(errors, "cash_target_weight"), weight
    end

    # A refusal of the batch's shape names no row.
    errors =
      put_targets.([
        %{"category_id" => growth.id, "target_weight" => "0.5"},
        %{"category_id" => growth.id, "target_weight" => "0.5"}
      ])

    refute Map.has_key?(errors, "row")
  end

  # User story (board 12, "zero-value drift", before/after):
  # As the operator reading which positions to act on,
  # I want a position valued at 0 to carry no share of its category's drift,
  # so that it neither shows a signed "-0.00" nor sorts among the positions I
  # can trade.
  #
  # Acceptance criteria:
  # - A SOLL-less position with market value 0 answers drift_value and
  #   rebalance_quantity null, as an unassigned position does.
  # - The payload's computation_basis names the case as a gap.
  test "a zero-value position carries no drift share, and the basis names the gap",
       %{conn: conn, world: world, classification: classification, growth: growth, value: value} do
    held = create_security!(name: "Helios Solar Systems SE", ticker: "HSS")
    worthless = create_security!(name: "Larkspur Minerals SE", ticker: "LMS")
    other = create_security!(name: "Harbor Light Utilities SE", ticker: "HLU")
    assign!(held, classification, growth)
    assign!(worthless, classification, growth)
    assign!(other, classification, value)
    buy!(world, held, quantity: "10", price: "10")
    # A free allotment booked at price 0 and never quoted: valued at 0.
    buy!(world, worthless, quantity: "10", price: "0")
    buy!(world, other, quantity: "10", price: "30")

    assert conn
           |> put("/api/v1/portfolios/#{world.portfolio.id}/targets", %{
             "classification_id" => classification.id,
             "targets" => [
               %{"category_id" => growth.id, "target_weight" => "0.5"},
               %{"category_id" => value.id, "target_weight" => "0.5"}
             ]
           })
           |> json_response(200)

    %{"data" => allocation} =
      conn
      |> get(
        "/api/v1/portfolios/#{world.portfolio.id}/allocation?classification_id=#{classification.id}"
      )
      |> json_response(200)

    growth_row = Enum.find(allocation["categories"], &(&1["name"] == "Growth"))
    zero = Enum.find(growth_row["positions"], &(&1["security_name"] == "Larkspur Minerals SE"))

    traded =
      Enum.find(growth_row["positions"], &(&1["security_name"] == "Helios Solar Systems SE"))

    assert zero["market_value"] == "0"
    assert zero["drift_value"] == nil
    assert zero["rebalance_quantity"] == nil
    assert traded["drift_value"] == "-100"

    assert allocation["computation_basis"]["drift_value"] =~ "market value"
    assert Enum.any?(allocation["computation_basis"]["gaps"], &(&1 =~ "valued at 0"))
  end
end
