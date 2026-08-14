defmodule PortfolixirWeb.ApiV1TaxStalenessTest do
  # Issue #667 over the API: the activity-aware staleness assessment travels
  # with every recorded-statement payload and with the trim-budget roll-up,
  # and the trim budget is surfaced where the trim decision is made — as an
  # opt-in block on the allocation read.
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Tax

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp owner, do: Actor.owner_ui()

  defp record_snapshot!(as_of) do
    {:ok, snapshot} =
      Tax.create_snapshot(owner(), %{
        institution: "Synthetic Bank",
        holder: "Owner",
        tax_year: as_of.year,
        as_of: as_of,
        source: "manual",
        loss_pot_equities: "1000.00",
        loss_pot_other: "0",
        allowance_granted: "1000.00",
        allowance_used: "200.00"
      })

    snapshot
  end

  defp seed_booking_world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(owner(), %{name: "Tax API", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(owner(), %{
        portfolio_id: portfolio.id,
        name: "Tax API Cash",
        currency_code: "EUR"
      })

    %{portfolio: portfolio, cash: cash}
  end

  # User story (issue #667):
  # As the operating LLM agent reading recorded tax statements,
  # I want each snapshot payload to carry the activity-aware staleness
  # assessment with its computation basis,
  # so that I can tell a statement invalidated by activity from one that is
  # merely not from today.
  #
  # Acceptance criteria:
  # - GET /tax/statement_snapshots rows carry `staleness` with age fields,
  #   activity fields, the combined `warning` and a `basis` note.
  # - GET /tax/trim_budget carries the same assessment for its as_of.
  test "statement snapshots and the trim budget carry the staleness assessment", %{conn: conn} do
    world = seed_booking_world()
    today = Date.utc_today()
    snapshot = record_snapshot!(Date.add(today, -5))

    {:ok, _} =
      Ledger.create_transaction(owner(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        type: "tax_refund",
        date: Date.add(today, -2),
        gross_amount: "25.00",
        currency_code: "EUR"
      })

    response =
      conn
      |> api_conn()
      |> get("/api/v1/tax/statement_snapshots?holder=Owner&tax_year=#{snapshot.tax_year}")
      |> json_response(200)

    assert [row] = response["data"]
    staleness = row["staleness"]
    assert staleness["age_days"] == 5
    assert staleness["age_warning"] == false
    assert staleness["activity_since_count"] == 1
    assert staleness["activity_warning"] == true
    assert staleness["warning"] == true
    assert staleness["age_threshold_days"] == 90
    assert is_binary(staleness["basis"])
    assert "tax_refund" in staleness["activity_kinds"]

    budget =
      conn
      |> api_conn()
      |> get("/api/v1/tax/trim_budget?holder=Owner&tax_year=#{snapshot.tax_year}")
      |> json_response(200)

    assert budget["data"]["staleness"]["activity_warning"] == true
    assert budget["data"]["staleness"]["warning"] == true
  end

  # User story (issue #667, part 2):
  # As the operating LLM agent deciding a trim from the allocation drift,
  # I want the pot state and trim budget available on the allocation read,
  # so that the tax headroom is in front of me where the decision is made,
  # not only on the tax page.
  #
  # Acceptance criteria:
  # - `tax_context=true` on the allocation read attaches the current-year
  #   trim-budget roll-up per recorded holder, each with its staleness.
  # - The block states that it is holder-scoped, not portfolio-scoped.
  # - The default read is unchanged (no tax block); invalid values are 422.
  test "allocation ?tax_context=true attaches the trim-budget roll-up", %{conn: conn} do
    _world = seed_booking_world()
    today = Date.utc_today()
    _snapshot = record_snapshot!(Date.add(today, -5))

    {:ok, portfolio} =
      Portfolios.create_portfolio(owner(), %{name: "Alloc", base_currency_code: "EUR"})

    {:ok, classification} = Classifications.create_classification(owner(), %{name: "Strategy"})

    {:ok, _} =
      Catalog.create_security(owner(), %{name: "Any Equity", currency_code: "EUR"})

    base =
      "/api/v1/portfolios/#{portfolio.id}/allocation?classification_id=#{classification.id}"

    plain = conn |> api_conn() |> get(base) |> json_response(200)
    refute Map.has_key?(plain["data"], "tax_context")

    response = conn |> api_conn() |> get(base <> "&tax_context=true") |> json_response(200)
    tax_context = response["data"]["tax_context"]

    assert tax_context["tax_year"] == today.year
    assert tax_context["note"] =~ "holder"
    assert [budget] = tax_context["trim_budgets"]
    assert budget["holder"] == "Owner"
    assert budget["tax_free_trim_budget"] == "1800"
    assert budget["staleness"]["warning"] == false

    assert conn
           |> api_conn()
           |> get(base <> "&tax_context=perhaps")
           |> json_response(422)
  end
end
