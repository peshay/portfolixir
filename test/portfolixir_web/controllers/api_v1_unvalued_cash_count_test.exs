defmodule PortfolixirWeb.ApiV1UnvaluedCashCountTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1, buy!: 3, deposit!: 4, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @auth {"authorization", "Bearer test-api-token"}

  defp get_json(conn, path) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
    |> get(path)
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp usd_account!(world, name, balance) do
    {:ok, account} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: name,
        currency_code: "USD"
      })

    if balance do
      {:ok, _} =
        Ledger.set_cash_balance(Actor.owner_ui(), account, %{
          date: ~D[2026-01-05],
          amount: balance
        })
    end

    account
  end

  # Board 01's accounts (#1081): an EUR world valued in full, two USD
  # accounts holding money with no EUR rate stored, and an empty USD account,
  # which leaves nothing out of the total.
  defp seed do
    world = base_world(name: "Alpha", cash_name: "Girokonto", depot_name: "Depot")
    security = create_security!(name: "World Co.", ticker: "WRLD", asset_class: "equity")
    put_quote!(security, ~D[2026-06-01], "10")
    deposit!(world, "300", ~D[2026-01-01], [])
    buy!(world, security, quantity: "10", price: "10")

    settlement = usd_account!(world, "USD Settlement", "1850")
    broker = usd_account!(world, "US Broker", "60")
    empty = usd_account!(world, "Leer USD", nil)

    Map.merge(world, %{settlement: settlement, broker: broker, empty: empty})
  end

  defp assert_counts_unvalued_cash(data, path) do
    # Cash 300 − 100 in EUR; the USD balances are not in it.
    assert data["unvalued_cash_count"] == 2, path
    assert data["total_cash"] == "200", path
    assert data["total_with_cash"] == "300", path

    note = data["valuation_note"]
    assert note =~ "left out of total_cash and total_with_cash", path
    assert note =~ "unvalued_cash_count counts", path
    assert note =~ "non-zero balance", path
    assert note =~ "valued: false", path

    unvalued =
      data["cash_balances"]
      |> Enum.reject(& &1["valued"])
      |> Enum.map(&{&1["name"], &1["balance"]})
      |> Enum.sort()

    assert unvalued == [{"Leer USD", "0"}, {"US Broker", "60"}, {"USD Settlement", "1850"}],
           path
  end

  # User story (#1081, D-3 — the agent's half):
  # As the agent reading the routine total with include_positions=false,
  # I want the valuation to say that unvalued cash is not in total_cash, and
  # how many accounts hold it,
  # so that the roll-up read does not hide the gap the Overview now names.
  #
  # Acceptance criteria:
  # - Every valuation form — the portfolio valuation, the view valuation and
  #   the view-less valuation — carries unvalued_cash_count: the cash
  #   accounts in scope with valued: false and a non-zero balance, with and
  #   without include_positions.
  # - An empty account with no rate is listed with valued: false and not
  #   counted.
  # - total_cash and total_with_cash are unchanged; decimals stay strings.
  # - Each form's valuation_note states the rule.
  test "every valuation form counts the unvalued cash and says it is not in total_cash",
       %{conn: conn} do
    world = seed()

    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "all"})
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), world.depot, [bucket.id])

    for account <- [world.cash, world.settlement, world.broker, world.empty] do
      :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), account, [bucket.id])
    end

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "All", include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])

    for base <- [
          "/api/v1/valuation",
          "/api/v1/portfolios/#{world.portfolio.id}/valuation",
          "/api/v1/views/#{view.id}/valuation"
        ],
        query <- ["?include_positions=false", ""] do
      path = base <> query
      data = get_json(conn, path)

      assert data["positions_included"] == (query == ""), path
      assert_counts_unvalued_cash(data, path)
    end
  end

  # Acceptance criteria:
  # - The count follows the scope: a view whose buckets hold none of the USD
  #   accounts counts 0, and its note still states the rule.
  test "the count follows the view's scope", %{conn: conn} do
    world = seed()

    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "euro"})
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), world.depot, [bucket.id])
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), world.cash, [bucket.id])

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Euro", include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])

    data = get_json(conn, "/api/v1/views/#{view.id}/valuation?include_positions=false")

    assert data["unvalued_cash_count"] == 0
    assert Enum.all?(data["cash_balances"], & &1["valued"])
    assert data["valuation_note"] =~ "unvalued_cash_count counts"
  end
end
