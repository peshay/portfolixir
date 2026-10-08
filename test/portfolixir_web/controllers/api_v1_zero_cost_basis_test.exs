defmodule PortfolixirWeb.ApiV1ZeroCostBasisTest do
  # #1142 (Sprint 20 β B3, plan D-6; board ux-design-2026-10-07/02-money-findings,
  # found while drawing 10, the payload half): a closed trade or a held
  # position whose cost basis is zero has no percentage return. The reads
  # that serve the percentage answer null, not "0", and the payload's
  # computation basis states why, as it states annualized_return's reasons
  # (the AGENTS.md metric rule). The MCP tools portfolixir.trades.list,
  # portfolixir.cashflow.realized_gains and portfolixir.holdings.list pass
  # these bodies through.
  #
  # The data is invented, the board's: "Larkspur Rail AG", 12 bonus shares
  # booked as a buy at 0.00, 8 sold at 41.25 (+330.00), latest close 41.80;
  # "Fennwick Labs AG", 15 shares delivered in at no price, latest close
  # 22.40 (336.00).
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger

  defp get_json(conn, path) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(200)
  end

  defp seed! do
    world = base_world(name: "Bonus World", cash_name: "Girokonto", depot_name: "Depot 1")
    deposit!(world, "5000", ~D[2025-01-02])
    larkspur = create_security!(name: "Larkspur Rail AG", ticker: "LKR")
    buy!(world, larkspur, quantity: "12", price: "0", date: ~D[2025-03-03])
    sell!(world, larkspur, quantity: "8", price: "41.25", date: ~D[2026-08-13])
    put_quote!(larkspur, ~D[2026-10-06], "41.80")

    fennwick = create_security!(name: "Fennwick Labs AG", ticker: "FWL")

    {:ok, _delivery} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: fennwick.id,
        type: "inbound_delivery",
        date: ~D[2026-02-02],
        quantity: "15",
        currency_code: "EUR"
      })

    put_quote!(fennwick, ~D[2026-10-06], "22.40")

    %{world: world, larkspur: larkspur, fennwick: fennwick}
  end

  # User story (#1142, the payload half):
  # As the operating LLM agent reading a security's closed trades and open
  # lots,
  # I want a return on no cost served as null with its reason in the basis,
  # so that I never quote a bonus share's +330.00 as a flat 0 %.
  #
  # Acceptance criteria:
  # - GET /api/v1/securities/:id/trades: the closed trade reads basis "0",
  #   realized_pnl_abs "330", realized_pnl_pct null (before: "0"),
  #   annualized_return null with annualized_return_reason "no_cost_basis"
  #   (before: "no_sign_change"); the open lot of the 4 remaining shares
  #   reads unrealized_pnl_abs "167.2" and unrealized_pnl_pct null (before:
  #   "0").
  # - computation_basis.realized_pnl_pct and .unrealized_pnl_pct, new, state
  #   the rule; computation_basis.annualized_return names no_cost_basis.
  test "the trades read serves a return on no cost as null, with the rule", %{conn: conn} do
    %{larkspur: larkspur} = seed!()

    %{"data" => data} = get_json(conn, "/api/v1/securities/#{larkspur.id}/trades")

    assert [closed] = data["closed_trades"]

    assert Map.take(closed, [
             "basis",
             "proceeds",
             "realized_pnl_abs",
             "realized_pnl_pct",
             "annualized_return",
             "annualized_return_reason"
           ]) == %{
             "basis" => "0",
             "proceeds" => "330",
             "realized_pnl_abs" => "330",
             "realized_pnl_pct" => nil,
             "annualized_return" => nil,
             "annualized_return_reason" => "no_cost_basis"
           }

    assert [lot] = data["open_lots"]

    assert Map.take(lot, [
             "quantity",
             "buy_price_native",
             "unrealized_pnl_abs",
             "unrealized_pnl_pct"
           ]) ==
             %{
               "quantity" => "4",
               "buy_price_native" => "0",
               "unrealized_pnl_abs" => "167.2",
               "unrealized_pnl_pct" => nil
             }

    basis = data["computation_basis"]
    assert basis["realized_pnl_pct"] =~ "null, never 0, where basis is 0"
    assert basis["realized_pnl_pct"] =~ "no_cost_basis"
    assert basis["unrealized_pnl_pct"] =~ "null, never 0, where that cost is 0"
    assert basis["annualized_return"] =~ "no_cost_basis"
  end

  # User story (#1142, the payload half):
  # As the operating LLM agent reading the realized-gains roll-up,
  # I want the trade's missing percentage served as null with its reason,
  # so that the roll-up and the security's own read say the same.
  #
  # Acceptance criteria:
  # - GET /api/v1/realized_gains: the trade reads realized_base "330",
  #   realized_pnl_pct null (before: "0"), annualized_return_reason
  #   "no_cost_basis"; computation_basis.realized_pnl_pct states the rule.
  test "the realized-gains read serves a return on no cost as null, with the rule", %{
    conn: conn
  } do
    seed!()

    %{"data" => data} = get_json(conn, "/api/v1/realized_gains")

    assert [trade] = data["trades"]
    assert trade["realized_base"] == "330"
    assert trade["realized_pnl_pct"] == nil
    assert trade["annualized_return"] == nil
    assert trade["annualized_return_reason"] == "no_cost_basis"
    assert data["computation_basis"]["realized_pnl_pct"] =~ "null, never 0, where basis is 0"
  end

  # User story (#1142, the unrealized side, the issue's own example):
  # As the operating LLM agent reading a portfolio's holdings,
  # I want a position delivered in at no cost to carry no percentage return,
  # so that I read its 336.00 as a gain on nothing, not as flat.
  #
  # Acceptance criteria:
  # - GET /api/v1/portfolios/:id/holdings: Fennwick's row reads cost_basis
  #   "0", market_value "336", unrealized_pnl_abs "336" and
  #   unrealized_pnl_pct null (before: "0"); the same under
  #   ?security_id= (one position) and under fields=.
  # - The envelope's computation_basis.unrealized_pnl_pct, new, states the
  #   rule.
  test "the holdings read serves a position on no cost as null, with the rule", %{conn: conn} do
    %{world: world, fennwick: fennwick} = seed!()
    path = "/api/v1/portfolios/#{world.portfolio.id}/holdings"

    response = get_json(conn, path)
    row = Enum.find(response["data"], &(&1["security_id"] == fennwick.id))

    assert Map.take(row, [
             "cost_basis",
             "market_value",
             "unrealized_pnl_abs",
             "unrealized_pnl_pct"
           ]) ==
             %{
               "cost_basis" => "0",
               "market_value" => "336",
               "unrealized_pnl_abs" => "336",
               "unrealized_pnl_pct" => nil
             }

    assert response["computation_basis"]["unrealized_pnl_pct"] =~
             "null, never 0, where that cost is 0"

    assert %{"data" => [position]} = get_json(conn, "#{path}?security_id=#{fennwick.id}")
    assert position["unrealized_pnl_pct"] == nil

    assert %{"data" => [selected]} =
             get_json(
               conn,
               "#{path}?security_id=#{fennwick.id}&fields=security_id,unrealized_pnl_pct"
             )

    assert selected == %{"security_id" => fennwick.id, "unrealized_pnl_pct" => nil}
  end
end
