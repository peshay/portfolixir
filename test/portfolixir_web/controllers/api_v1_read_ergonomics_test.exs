defmodule PortfolixirWeb.ApiV1ReadErgonomicsTest do
  # FR-37 / issue #665: sparse fieldsets, roll-up-only aggregates and
  # server-side threshold filters on the four heaviest reads — holdings,
  # transactions, valuation and allocation. The acceptance measure (−70 %
  # response volume with nothing load-bearing cut) is asserted here as a
  # permanent test, on synthetic fixtures.
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets
  alias PortfolixirWeb.Api.V1.JSON

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp owner, do: Portfolixir.Actor.owner_ui()

  # A synthetic world big enough that per-position payload dominates the
  # envelope: one portfolio, one depot, 10 securities with buys and quotes,
  # a classification with per-category targets.
  defp seed_world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(owner(), %{name: "Ergo", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(owner(), %{
        portfolio_id: portfolio.id,
        name: "Ergo Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(owner(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Ergo Depot"
      })

    {:ok, classification} = Classifications.create_classification(owner(), %{name: "Strategy"})

    {:ok, cat_a} =
      Classifications.create_category(owner(), %{
        classification_id: classification.id,
        name: "Growth"
      })

    {:ok, cat_b} =
      Classifications.create_category(owner(), %{
        classification_id: classification.id,
        name: "Value"
      })

    securities =
      for i <- 1..10 do
        {:ok, security} =
          Catalog.create_security(owner(), %{
            name: "Synthetic Equity #{i}",
            ticker_symbol: "SYN#{i}",
            currency_code: "EUR",
            asset_class: "equity"
          })

        {:ok, _} =
          Ledger.create_transaction(owner(), %{
            portfolio_id: portfolio.id,
            securities_account_id: depot.id,
            cash_account_id: cash.id,
            security_id: security.id,
            type: "buy",
            date: ~D[2026-01-02],
            quantity: "10",
            price: "#{50 + i}",
            fees: "1.50",
            taxes: "0",
            currency_code: "EUR"
          })

        {:ok, _} =
          Quotes.upsert_many(security.id, [
            %{date: ~D[2026-06-01], close: "#{60 + i * 5}", source: "manual"}
          ])

        category = if rem(i, 2) == 0, do: cat_a, else: cat_b

        {:ok, _} =
          Classifications.assign_security(owner(), security.id, classification.id, category.id)

        security
      end

    {:ok, _} =
      Targets.set_targets(owner(), portfolio.id, classification.id, [
        %{"category_id" => cat_a.id, "target_weight" => "0.10"},
        %{"category_id" => cat_b.id, "target_weight" => "0.90"}
      ])

    %{
      portfolio: portfolio,
      cash: cash,
      depot: depot,
      classification: classification,
      cat_a: cat_a,
      cat_b: cat_b,
      securities: securities
    }
  end

  defp get_json(conn, path) do
    conn |> api_conn() |> get(path) |> json_response(200)
  end

  defp volume(payload), do: byte_size(Jason.encode!(payload))

  # User story (FR-37, issue #665):
  # As the operating LLM agent listing holdings or transactions,
  # I want to select only the fields my current task needs via a validated
  # `fields` parameter,
  # so that a routine read does not spend my context window on two dozen
  # fields per row I am not going to use.
  #
  # Acceptance criteria:
  # - `fields=` is a per-endpoint whitelist: an unknown name is a 422 naming
  #   the parameter, never a silent fallback and never an atom created from
  #   input.
  # - Each returned row carries exactly the requested fields.
  # - The self-describing envelope (currency basis, as_of) stays.
  test "holdings fields= returns exactly the requested row fields", %{conn: conn} do
    world = seed_world()

    response =
      get_json(
        conn,
        "/api/v1/portfolios/#{world.portfolio.id}/holdings?fields=security_id,quantity,market_value"
      )

    assert response["currency_basis"] == "security_currency"
    assert [row | _] = response["data"]
    assert Map.keys(row) |> Enum.sort() == ["market_value", "quantity", "security_id"]
  end

  test "holdings fields= rejects an unknown field with a 422", %{conn: conn} do
    world = seed_world()

    response =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/holdings?fields=security_id,drop%20table")
      |> json_response(422)

    assert %{"errors" => %{"fields" => ["is invalid"]}} = response
  end

  test "transactions fields= returns exactly the requested row fields", %{conn: conn} do
    _world = seed_world()

    response = get_json(conn, "/api/v1/transactions?fields=id,type,date,gross_amount")

    assert [row | _] = response["data"]
    assert Map.keys(row) |> Enum.sort() == ["date", "gross_amount", "id", "type"]
  end

  test "transactions fields= rejects an unknown field with a 422", %{conn: conn} do
    response =
      conn
      |> api_conn()
      |> get("/api/v1/transactions?fields=nope")
      |> json_response(422)

    assert %{"errors" => %{"fields" => ["is invalid"]}} = response
  end

  # User story (FR-37, issue #665):
  # As the operating LLM agent asking for portfolio totals,
  # I want `include_positions=false` on valuation and allocation,
  # so that I can take the roll-up (totals, cash, category rows) without the
  # position rows that dominate the payload.
  #
  # Acceptance criteria:
  # - `include_positions=false` omits position rows; the response says so
  #   via `positions_included: false`.
  # - The default is unchanged (positions included).
  # - An invalid value is a 422.
  test "valuation include_positions=false omits position rows", %{conn: conn} do
    world = seed_world()
    base = "/api/v1/portfolios/#{world.portfolio.id}/valuation"

    full = get_json(conn, base)
    assert full["data"]["positions_included"] == true
    assert length(full["data"]["positions"]) == 10

    slim = get_json(conn, base <> "?include_positions=false")
    assert slim["data"]["positions_included"] == false
    refute Map.has_key?(slim["data"], "positions")
    # The roll-up survives: totals and cash balances.
    assert slim["data"]["total_with_cash"] == full["data"]["total_with_cash"]
    assert length(slim["data"]["cash_balances"]) == 1

    assert conn
           |> api_conn()
           |> get(base <> "?include_positions=maybe")
           |> json_response(422)
  end

  test "allocation include_positions=false omits position rows from categories and unassigned",
       %{conn: conn} do
    world = seed_world()

    base =
      "/api/v1/portfolios/#{world.portfolio.id}/allocation?classification_id=#{world.classification.id}"

    full = get_json(conn, base)
    assert full["data"]["positions_included"] == true
    assert Enum.any?(full["data"]["categories"], &(&1["positions"] != []))

    slim = get_json(conn, base <> "&include_positions=false")
    assert slim["data"]["positions_included"] == false
    refute Enum.any?(slim["data"]["categories"], &Map.has_key?(&1, "positions"))
    # The category roll-up itself is intact.
    assert length(slim["data"]["categories"]) == length(full["data"]["categories"])
    assert slim["data"]["total_value"] == full["data"]["total_value"]
  end

  # User story (FR-37, issue #665):
  # As the operating LLM agent looking for what drifted,
  # I want a server-side threshold filter on the allocation read,
  # so that the five or six deviating rows come back instead of the whole
  # category tree.
  #
  # Acceptance criteria:
  # - `min_drift=` (absolute drift weight, Decimal string) returns only
  #   categories whose |drift_weight| meets the threshold; targetless
  #   (drift-less) categories are filtered out.
  # - The response states the applied filter (`min_drift`) and how many
  #   category rows existed before filtering (`categories_total`), so a
  #   filtered read is self-describing about its own computation basis.
  # - An invalid threshold is a 422.
  test "allocation min_drift returns only the deviating category rows", %{conn: conn} do
    world = seed_world()

    base =
      "/api/v1/portfolios/#{world.portfolio.id}/allocation?classification_id=#{world.classification.id}"

    full = get_json(conn, base)
    assert full["data"]["min_drift"] == nil
    total = length(full["data"]["categories"])

    # cat_a target 10% vs. actual ~50% => |drift| ~0.40; cat_b target 90%
    # vs. actual ~50% => |drift| ~0.40. A 0.99 threshold filters both; a
    # 0.05 threshold keeps both.
    filtered = get_json(conn, base <> "&min_drift=0.99")
    assert filtered["data"]["categories"] == []
    assert filtered["data"]["min_drift"] == "0.99"
    assert filtered["data"]["categories_total"] == total

    kept = get_json(conn, base <> "&min_drift=0.05")
    assert length(kept["data"]["categories"]) == 2

    assert conn
           |> api_conn()
           |> get(base <> "&min_drift=lots")
           |> json_response(422)
  end

  # User story (FR-37, issue #665 — the acceptance measure):
  # As the sprint's reviewer,
  # I want the −70 % response-volume claim asserted as a test on the four
  # heaviest reads,
  # so that the measure is reproducible instead of a number in a PR body.
  #
  # Acceptance criteria:
  # - On the seeded synthetic world, the slim variant of each of the four
  #   heaviest reads (holdings, transactions, valuation, allocation) is at
  #   least 70 % smaller than the full read.
  test "the slim variants cut at least 70% of response volume on the four heaviest reads",
       %{conn: conn} do
    world = seed_world()
    p = world.portfolio.id

    pairs = [
      {"/api/v1/portfolios/#{p}/holdings",
       "/api/v1/portfolios/#{p}/holdings?fields=security_id,quantity,market_value"},
      {"/api/v1/transactions", "/api/v1/transactions?fields=id,type,date,gross_amount"},
      {"/api/v1/portfolios/#{p}/valuation",
       "/api/v1/portfolios/#{p}/valuation?include_positions=false"},
      {"/api/v1/portfolios/#{p}/allocation?classification_id=#{world.classification.id}",
       "/api/v1/portfolios/#{p}/allocation?classification_id=#{world.classification.id}" <>
         "&include_positions=false&min_drift=0.05"}
    ]

    for {full_path, slim_path} <- pairs do
      full = volume(get_json(conn, full_path))
      slim = volume(get_json(conn, slim_path))

      assert slim <= full * 0.30,
             "#{slim_path} is #{slim} bytes, more than 30% of the full #{full} bytes"
    end
  end

  # The field inventory (issue #665 acceptance): the whitelists offer every
  # field the full serializers emit, so nothing load-bearing was cut from
  # what a caller can select — the slim read is a subset by choice, never by
  # omission.
  test "the fields whitelists cover the full serializer output exactly" do
    holding_sample =
      Map.new(JSON.holding_fields(), fn field -> {field, nil} end)

    assert JSON.holding(holding_sample, 1) |> Map.keys() |> Enum.sort() ==
             Enum.sort(JSON.holding_fields())

    transaction_sample = %Portfolixir.Ledger.Transaction{}

    assert JSON.transaction(transaction_sample) |> Map.keys() |> Enum.sort() ==
             Enum.sort(JSON.transaction_fields())
  end
end
