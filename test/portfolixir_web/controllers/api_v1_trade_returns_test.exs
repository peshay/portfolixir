defmodule PortfolixirWeb.ApiV1TradeReturnsTest do
  # #984 rescoped (Sprint 17 T1): the annualized return per closed
  # round-trip on both reads that serve closed trades, with its reason and
  # its rule in the payload (AGENTS.md metric rule). Risk-tier: the pins
  # below hold every field the two reads served before, value for value.
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [add_depot: 2, base_world: 1, buy!: 3, create_security!: 1, sell!: 3]

  alias Portfolixir.Fx

  defp get_json(conn, path) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(200)
  end

  # 10 bought at 100 with 5 in fees, sold 545 days later at 150 with 5 in
  # fees: basis 1005, proceeds 1495, (1495 / 1005)^(365 / 545) - 1 =
  # 0.30470061616... -> 0.304701. A second security closes after 30 days.
  defp seed! do
    world = base_world(name: "Returns World", cash_name: "RW Cash", depot_name: "RW Depot")
    long = create_security!(name: "Longhold Industries", ticker: "LHI")
    short = create_security!(name: "Quickturn Retail", ticker: "QTR")

    buy!(world, long, quantity: "10", price: "100", fees: "5", date: ~D[2024-01-02])
    sell!(world, long, quantity: "10", price: "150", fees: "5", date: ~D[2025-06-30])

    buy!(world, short, quantity: "4", price: "50", date: ~D[2025-03-01])
    sell!(world, short, quantity: "4", price: "45", date: ~D[2025-03-31])

    %{long: long, short: short}
  end

  # realized_pnl_pct as the wire writes a Decimal: realized / basis, normalized.
  defp pct(realized, basis) do
    realized
    |> Decimal.new()
    |> Decimal.div(Decimal.new(basis))
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  @new_keys ["annualized_return", "annualized_return_reason"]

  # User story (#984 rescoped, Sprint 17 T1):
  # As the operating LLM agent,
  # I want the annualized return of every closed trade on the realized-gains
  # read, with its reason when it is absent and its rule in the payload,
  # so that I answer "was the trade worth it" with the operator's figure and
  # can say why a short trade has none.
  #
  # Acceptance criteria:
  # - Every trade row carries annualized_return (a decimal string, or null)
  #   and annualized_return_reason (null when the figure is present).
  # - A trade held under 365 days has null with holding_period_under_365_days.
  # - computation_basis.annualized_return states the rule.
  # - Every field a row served before is unchanged, value for value.
  test "GET /api/v1/realized_gains carries the annualized return per trade", %{conn: conn} do
    %{long: long, short: short} = seed!()

    %{"data" => data} = get_json(conn, "/api/v1/realized_gains")

    assert [newest, oldest] = data["trades"]

    # The rows as they were served before #984, field for field.
    assert Map.drop(newest, @new_keys) == %{
             "security_id" => long.id,
             "security_name" => "Longhold Industries",
             "open_date" => "2024-01-02",
             "close_date" => "2025-06-30",
             "quantity" => "10",
             "basis" => "1005",
             "proceeds" => "1495",
             "holding_period_days" => 545,
             "currency_code" => "EUR",
             "realized_pnl_abs" => "490",
             "realized_pnl_pct" => pct("490", "1005"),
             "realized_base" => "490"
           }

    assert Map.drop(oldest, @new_keys) == %{
             "security_id" => short.id,
             "security_name" => "Quickturn Retail",
             "open_date" => "2025-03-01",
             "close_date" => "2025-03-31",
             "quantity" => "4",
             "basis" => "200",
             "proceeds" => "180",
             "holding_period_days" => 30,
             "currency_code" => "EUR",
             "realized_pnl_abs" => "-20",
             "realized_pnl_pct" => "-0.1",
             "realized_base" => "-20"
           }

    assert newest["annualized_return"] == "0.304701"
    assert newest["annualized_return_reason"] == nil

    assert oldest["annualized_return"] == nil
    assert oldest["annualized_return_reason"] == "holding_period_under_365_days"

    basis = data["computation_basis"]
    assert basis["annualized_return"] =~ "XIRR"
    assert basis["annualized_return"] =~ "holding_period_under_365_days"
    assert basis["annualized_return"] =~ "own currency"

    # The figures and the basis keys the read carried before are unchanged.
    assert data["summary"] == %{
             "realized_total" => "470",
             "hit_rate" => "0.5",
             "average_holding_period_days" => 288,
             "trade_count" => 2
           }

    assert Map.take(basis, ~w(series window reference gaps)) == %{
             "series" =>
               "realized_pnl_abs per FIFO-matched closed trade (proceeds net of sell fees and taxes, minus consumed basis)",
             "window" => "full ledger history, grouped by each trade's close date",
             "reference" => "EUR hub rates at or before each close date (D-1, issue #724)",
             "gaps" =>
               "a sale with no stored close-date rate is excluded from the converted totals and named in excluded"
           }
  end

  # User story (#984 rescoped, Sprint 17 T1):
  # As the operating LLM agent,
  # I want the same figure on a security's trades read,
  # so that the per-security answer and the roll-up never disagree.
  #
  # Acceptance criteria:
  # - Every closed trade carries annualized_return and its reason, the same
  #   values the realized-gains read serves for the same round-trip.
  # - The payload carries computation_basis.annualized_return.
  # - Every field a closed trade served before is unchanged.
  test "GET /api/v1/securities/:id/trades carries the annualized return per closed trade",
       %{conn: conn} do
    %{long: long, short: short} = seed!()

    %{"data" => data} = get_json(conn, "/api/v1/securities/#{long.id}/trades")

    assert [closed] = data["closed_trades"]

    assert Map.drop(closed, @new_keys) == %{
             "open_date" => "2024-01-02",
             "close_date" => "2025-06-30",
             "quantity" => "10",
             "avg_buy_price" => "100",
             "avg_sell_price" => "150",
             "buy_fees" => "5",
             "buy_taxes" => "0",
             "sell_fees" => "5",
             "sell_taxes" => "0",
             "basis" => "1005",
             "proceeds" => "1495",
             "realized_pnl_abs" => "490",
             "realized_pnl_pct" => pct("490", "1005"),
             "holding_period_days" => 545,
             "currency_code" => "EUR"
           }

    assert closed["annualized_return"] == "0.304701"
    assert closed["annualized_return_reason"] == nil
    assert data["computation_basis"]["annualized_return"] =~ "XIRR"

    # The keys the read carried before are all still there, unchanged in kind.
    assert data["method"] == "fifo"
    assert data["open_lots"] == []
    assert data["orphan_sells"] == []
    assert data["basis"]["method"] == "fifo"

    %{"data" => short_data} = get_json(conn, "/api/v1/securities/#{short.id}/trades")
    assert [short_closed] = short_data["closed_trades"]
    assert short_closed["annualized_return"] == nil
    assert short_closed["annualized_return_reason"] == "holding_period_under_365_days"
  end

  # Acceptance criteria (closing act γ, money lens M2):
  # - The figure is solved over the trade's own currency on both reads: a
  #   USD trade in an EUR portfolio reads the same rate on the realized-gains
  #   read, whose rows also carry the EUR result, as on the trades read —
  #   never a rate over the converted amounts.
  test "both reads annualize a foreign-currency trade in its own currency", %{conn: conn} do
    world = base_world(name: "Dollar World", cash_name: "DW Cash", depot_name: "DW Depot")

    usd =
      add_depot(world.portfolio, cash_currency: "USD", cash_name: "DW USD", depot_name: "DW US")
      |> Map.put(:portfolio, world.portfolio)

    security = create_security!(name: "Synthetic Harbor Corp", ticker: "SHC", currency: "USD")

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2023-05-02],
          rate: "1.1",
          source: "manual"
        }
      ])

    # -251 USD on 2021-01-04, +399 USD on 2023-05-02 (848 days): the exact
    # XIRR is 0.22079882358261..., where the converted flows would read
    # 0.202907.
    trade = [currency: "USD"]
    buy!(usd, security, [quantity: "5", price: "50", fees: "1", date: ~D[2021-01-04]] ++ trade)
    sell!(usd, security, [quantity: "5", price: "80", fees: "1", date: ~D[2023-05-02]] ++ trade)

    %{"data" => realized} = get_json(conn, "/api/v1/realized_gains")
    assert [row] = realized["trades"]
    assert row["currency_code"] == "USD"
    assert row["annualized_return"] == "0.220799"

    %{"data" => trades} = get_json(conn, "/api/v1/securities/#{security.id}/trades")
    assert [closed] = trades["closed_trades"]
    assert closed["annualized_return"] == "0.220799"
  end
end
