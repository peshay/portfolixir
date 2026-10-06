defmodule PortfolixirWeb.ApiV1ContributionTest do
  # FR-41, ADR-0051 §6 and §11: the contribution reads over the API.
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Clock
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  defp get_json(conn, path, status \\ 200) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(status)
  end

  defp book!(attrs) do
    {:ok, tx} = Ledger.create_transaction(Actor.owner_ui(), attrs)
    tx
  end

  defp cash!(world, type, amount, date, security \\ nil) do
    book!(%{
      portfolio_id: world.portfolio.id,
      cash_account_id: world.cash.id,
      security_id: security && security.id,
      type: type,
      date: date,
      gross_amount: amount,
      currency_code: "EUR"
    })
  end

  # Invented figures only, all in EUR, so every figure is computable by hand.
  # The year before this one (`year`):
  #
  #   01-02  deposit 10000; buy Alpha Fund 10 @ 100, fees 2 (closes 100,
  #          then 130 on 12-31)
  #   03-02  buy Beta Share 5 @ 40, fees 1; 03-20 sell it 5 @ 50, fees 1
  #          (never quoted: priced by its own trades)
  #   04-01  inbound delivery Gamma Fund 3, no price, never quoted
  #   05-04  dividend Alpha Fund 20; 06-01 interest 12; 07-01 fee 7
  #
  # Over that year: Alpha 1300 − 0 − 1000 + 20 − 2 = 318; Beta 0 − 0 −
  # (200 − 250) − 2 = 48; Gamma 0, valued on no day. Remainder: interest 12,
  # standalone fees and taxes −7, currency 0. The money result is the end
  # value 1300 + 9071 cash, less the 10000 deposited: 371 = 366 + 5.
  defp world do
    year = Clock.today().year - 1
    on = fn month, day -> Date.new!(year, month, day) end

    world = base_world(name: "Contribution", cash_name: "Cash", depot_name: "Depot")
    alpha = create_security!(name: "Alpha Fund", ticker: "ALF", isin: "DE000APICON4")
    beta = create_security!(name: "Beta Share", ticker: "BTS")
    gamma = create_security!(name: "Gamma Fund", ticker: "GMF")

    deposit!(world, "10000", on.(1, 2))
    buy!(world, alpha, quantity: "10", price: "100", fees: "2", date: on.(1, 2))
    put_quotes!(alpha, [{on.(1, 2), "100"}, {on.(12, 31), "130"}])
    buy!(world, beta, quantity: "5", price: "40", fees: "1", date: on.(3, 2))
    sell!(world, beta, quantity: "5", price: "50", fees: "1", date: on.(3, 20))

    book!(%{
      portfolio_id: world.portfolio.id,
      securities_account_id: world.depot.id,
      security_id: gamma.id,
      type: "inbound_delivery",
      date: on.(4, 1),
      quantity: "3",
      currency_code: "EUR"
    })

    cash!(world, "dividend", "20", on.(5, 4), alpha)
    cash!(world, "interest", "12", on.(6, 1))
    cash!(world, "fee", "7", on.(7, 1))

    Map.merge(world, %{year: year, alpha: alpha, beta: beta, gamma: gamma})
  end

  # A view whose one bucket tags the world's depot and cash account.
  defp view!(world, name) do
    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "#{name} bucket"})
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), world.depot, [bucket.id])
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), world.cash, [bucket.id])
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: name, include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])
    view
  end

  defp decimal_sum(values),
    do: Enum.reduce(values, Decimal.new("0"), &Decimal.add(Decimal.new(&1), &2))

  # User story (FR-41, ADR-0051 §6 and §11):
  # As the operator's agent asking which position made how much of a
  # period's result,
  # I want one read per scope that answers each position's money
  # contribution with the remainder lines and the totals,
  # so that the table sums to the "+x EUR in the period" figure beside the
  # TTWROR and every term can be checked by hand.
  #
  # Acceptance criteria:
  # - GET /api/v1/portfolios/:portfolio_id/performance/contribution answers
  #   portfolio_id, view_id (null unscoped), period, base_currency,
  #   start_date, end_date, positions, remainder, totals, as_of, stale and
  #   computation_basis; year=, period= and from=/to= are the performance
  #   read's.
  # - Each position carries security_id, name, isin, start_value,
  #   end_value, net_flows, income, costs, contribution, held_at_start,
  #   held_at_end, unvalued_days and unvalued_reason ("no_price", "no_rate"
  #   or null); financial decimals are strings, dates ISO.
  # - Positions are sorted by contribution, largest first, with no rank or
  #   label key; a position bought and sold inside the window is listed.
  # - The positions plus the remainder lines sum to totals.result, the
  #   performance read's end_value − start_value − net_external_flows (I1).
  test "answers each position's contribution, the remainder and the totals", %{conn: conn} do
    world = world()

    data =
      get_json(
        conn,
        "/api/v1/portfolios/#{world.portfolio.id}/performance/contribution?year=#{world.year}"
      )["data"]

    assert data["portfolio_id"] == world.portfolio.id
    assert data["view_id"] == nil
    refute Map.has_key?(data, "view")
    assert data["period"] == Integer.to_string(world.year)
    assert data["base_currency"] == "EUR"
    assert data["start_date"] == "#{world.year}-01-02"
    assert data["end_date"] == "#{world.year}-12-31"
    assert data["stale"] == false
    assert {:ok, %DateTime{}, _offset} = DateTime.from_iso8601(data["as_of"])

    assert [alpha, beta, gamma] = data["positions"]

    assert alpha == %{
             "security_id" => world.alpha.id,
             "name" => "Alpha Fund",
             "isin" => "DE000APICON4",
             "start_value" => "0",
             "end_value" => "1300",
             "net_flows" => "1000",
             "income" => "20",
             "costs" => "2",
             "contribution" => "318",
             "held_at_start" => false,
             "held_at_end" => true,
             "unvalued_days" => 0,
             "unvalued_reason" => nil
           }

    # I3 over the API: bought and sold inside the window, held at neither
    # end, and still in the table.
    assert beta["security_id"] == world.beta.id
    assert beta["contribution"] == "48"
    assert beta["net_flows"] == "-50"
    assert beta["costs"] == "2"
    assert {beta["held_at_start"], beta["held_at_end"]} == {false, false}

    # §10: counted zero on every day it was held, kept in the sum, named.
    assert gamma["security_id"] == world.gamma.id
    assert gamma["contribution"] == "0"
    assert gamma["unvalued_reason"] == "no_price"

    assert gamma["unvalued_days"] ==
             Date.diff(Date.new!(world.year, 12, 31), Date.new!(world.year, 4, 1)) + 1

    assert data["remainder"] == %{
             "interest" => "12",
             "standalone_fees_and_taxes" => "-7",
             "cash_currency_effect" => "0"
           }

    assert data["totals"] == %{"result" => "371", "positions" => "366", "remainder" => "5"}

    # #1055: every balance is in EUR and valued, so no cash account is named.
    assert data["unvalued_cash_accounts"] == []

    # I1: the positions and the lines sum exactly to the result, and the
    # result is the performance read's money figure over the same window.
    assert Decimal.equal?(
             decimal_sum(Enum.map(data["positions"], & &1["contribution"])),
             data["totals"]["positions"]
           )

    assert Decimal.equal?(decimal_sum(Map.values(data["remainder"])), data["totals"]["remainder"])

    assert Decimal.equal?(
             decimal_sum([data["totals"]["positions"], data["totals"]["remainder"]]),
             data["totals"]["result"]
           )

    performance =
      get_json(conn, "/api/v1/portfolios/#{world.portfolio.id}/performance?year=#{world.year}")[
        "data"
      ]

    money_result =
      performance["end_value"]
      |> Decimal.new()
      |> Decimal.sub(Decimal.new(performance["start_value"]))
      |> Decimal.sub(Decimal.new(performance["net_external_flows"]))

    assert Decimal.equal?(money_result, data["totals"]["result"])

    # §11: no rank or label key on a row.
    for position <- data["positions"],
        key <- ~w(rank label top best worst detractor share) do
      refute Map.has_key?(position, key)
    end

    # The other period spellings are the performance read's.
    assert get_json(
             conn,
             "/api/v1/portfolios/#{world.portfolio.id}/performance/contribution?period=max"
           )["data"]["period"] == "max"

    ranged =
      get_json(
        conn,
        "/api/v1/portfolios/#{world.portfolio.id}/performance/contribution" <>
          "?from=#{world.year}-03-01&to=#{world.year}-03-31"
      )["data"]

    assert ranged["period"] == "#{world.year}-03-01..#{world.year}-03-31"
    assert ranged["start_date"] == "#{world.year}-03-01"

    assert Enum.find(ranged["positions"], &(&1["security_id"] == world.beta.id))["contribution"] ==
             "48"
  end

  # User story (FR-41, ADR-0051 §11; AGENTS.md metric rule):
  # As the operator's agent reading a contribution,
  # I want the payload to state how it was computed,
  # so that I do not mistake it for a share of the result, a return or a
  # figure that balances itself.
  #
  # Acceptance criteria:
  # - computation_basis carries input_series, window (start_date, end_date),
  #   reference null, gaps and assumptions.
  # - gaps says a day without a price or a rate path counts zero and that the
  #   affected positions are listed with their days, and names
  #   unvalued_cash_accounts, where a foreign-currency balance that counted
  #   zero is listed (#1055).
  # - assumptions states the §1 definition, the §3 identity, "base
  #   currency, currency move included", the 34-digit precision of a
  #   non-terminating conversion, and that the currency line holds a trade's
  #   settlement difference.
  # - assumptions says a trade's costs are read in its cash account's
  #   currency, the currency a cross-currency trade records them in (#1051).
  test "states its computation basis in the payload", %{conn: conn} do
    world = world()

    basis =
      get_json(
        conn,
        "/api/v1/portfolios/#{world.portfolio.id}/performance/contribution?year=#{world.year}"
      )["data"]["computation_basis"]

    assert %{
             "input_series" => input_series,
             "window" => %{"start_date" => start_date, "end_date" => end_date},
             "reference" => nil,
             "gaps" => gaps,
             "assumptions" => assumptions
           } = basis

    assert {start_date, end_date} == {"#{world.year}-01-02", "#{world.year}-12-31"}
    assert input_series =~ "ADR-0010"
    assert input_series =~ "per position"
    assert gaps =~ "counts zero"
    assert gaps =~ "the affected positions are listed with their days"
    assert gaps =~ "unvalued_cash_accounts"
    refute gaps =~ "no account is named"
    assert assumptions =~ "end_value − start_value − net_flows + income − costs"
    assert assumptions =~ "end value − start value − net external flows"
    assert assumptions =~ "never a plug"
    assert assumptions =~ "base currency, currency move included"
    assert assumptions =~ "34 significant digits"
    assert assumptions =~ "settlement difference"
    assert assumptions =~ "read in the currency of the trade's cash account (#708, #1051)"
  end

  # User story (FR-41, ADR-0051 §4):
  # As the operator's agent asking for a window that holds no walked day,
  # I want the read's honest emptiness,
  # so that a future year or a range before the history never reads as a
  # table of zeros.
  #
  # Acceptance criteria:
  # - A future year, a range before the history and a portfolio with nothing
  #   booked answer start_date null, no positions, and "0" lines and totals,
  #   as the performance read answers its empty window, with the basis's
  #   window.start_date null.
  test "an empty window is the performance read's emptiness", %{conn: conn} do
    world = world()
    empty = base_world(name: "Nothing Booked", cash_name: "Idle Cash", depot_name: "Idle Depot")

    for path <- [
          "/api/v1/portfolios/#{world.portfolio.id}/performance/contribution?year=#{world.year + 2}",
          "/api/v1/portfolios/#{world.portfolio.id}/performance/contribution" <>
            "?from=2001-01-01&to=2001-12-31",
          "/api/v1/portfolios/#{empty.portfolio.id}/performance/contribution"
        ] do
      data = get_json(conn, path)["data"]

      assert data["start_date"] == nil, path
      assert data["positions"] == [], path

      assert data["remainder"] == %{
               "interest" => "0",
               "standalone_fees_and_taxes" => "0",
               "cash_currency_effect" => "0"
             },
             path

      assert data["totals"] == %{"result" => "0", "positions" => "0", "remainder" => "0"}, path
      assert data["computation_basis"]["window"]["start_date"] == nil, path
      assert is_binary(data["end_date"]), path
      assert data["stale"] == false, path
    end
  end

  # User story (FR-41, ADR-0051 §6):
  # As the operator's agent asking about a view,
  # I want the contribution in the performance family's two forms,
  # so that a portfolio narrowed with view= and a view across every
  # portfolio answer like the performance and benchmark reads do.
  #
  # Acceptance criteria:
  # - The portfolio read with view= echoes view_id and the active view.
  # - GET /api/v1/views/:view_id/performance/contribution answers the view
  #   across every portfolio in EUR, portfolio_id null, view_id and the view
  #   echoed, with the period parameters of the portfolio read.
  test "takes a view in the performance family's two forms", %{conn: conn} do
    world = world()
    view = view!(world, "Contribution View")

    narrowed =
      get_json(
        conn,
        "/api/v1/portfolios/#{world.portfolio.id}/performance/contribution" <>
          "?view=#{view.id}&year=#{world.year}"
      )["data"]

    assert narrowed["portfolio_id"] == world.portfolio.id
    assert narrowed["view_id"] == view.id
    assert narrowed["view"] == %{"id" => view.id, "name" => "Contribution View"}
    assert narrowed["totals"] == %{"result" => "371", "positions" => "366", "remainder" => "5"}

    across =
      get_json(conn, "/api/v1/views/#{view.id}/performance/contribution?year=#{world.year}")[
        "data"
      ]

    assert across["portfolio_id"] == nil
    assert across["view_id"] == view.id
    assert across["view"] == %{"id" => view.id, "name" => "Contribution View"}
    assert across["base_currency"] == "EUR"
    assert across["period"] == Integer.to_string(world.year)
    assert across["totals"] == %{"result" => "371", "positions" => "366", "remainder" => "5"}

    assert Enum.map(across["positions"], & &1["contribution"]) == ["318", "48", "0"]
    assert across["computation_basis"]["assumptions"] =~ "base currency, currency move included"

    ranged =
      get_json(
        conn,
        "/api/v1/views/#{view.id}/performance/contribution" <>
          "?from=#{world.year}-03-01&to=#{world.year}-03-31"
      )["data"]

    assert ranged["period"] == "#{world.year}-03-01..#{world.year}-03-31"
  end

  # A EUR portfolio whose "Tagesgeld CHF" received 2000 CHF on 07-14 of the
  # year before this one, while CHF's first stored rate (EUR/CHF 0.8) is
  # from 08-01: the walk counts the balance zero for 18 days, then at 2500.
  defp franc_world do
    year = Clock.today().year - 1
    on = fn month, day -> Date.new!(year, month, day) end

    world = base_world(name: "Franc", cash_name: "Giro", depot_name: "Depot")

    {:ok, franc} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "Tagesgeld CHF",
        currency_code: "CHF"
      })

    deposit!(world, "1000", on.(7, 1))

    book!(%{
      portfolio_id: world.portfolio.id,
      cash_account_id: franc.id,
      type: "deposit",
      date: on.(7, 14),
      gross_amount: "2000",
      currency_code: "CHF"
    })

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "CHF",
          date: on.(8, 1),
          rate: "0.8",
          source: "manual"
        }
      ])

    Map.merge(world, %{year: year, franc: franc})
  end

  # User story (#1055, ADR-0051 §10; board J2 A):
  # As the operator's agent reading a period that holds a CHF deposit made
  # before the instance had any CHF rate,
  # I want the performance and the contribution reads to name the account,
  # in both forms, with its balance in CHF, its days and its first rate's
  # date,
  # so that I do not report the jump in cash_currency_effect as a currency
  # gain.
  #
  # Acceptance criteria:
  # - The performance and the contribution read, of the portfolio and of a
  #   view holding the account, carry unvalued_cash_accounts: cash_account_id,
  #   name, currency_code, balance (a Decimal string in CHF), unvalued_days
  #   18, unvalued_reason "no_rate", unvalued_through_end false and
  #   first_rate_date, the ISO date of the first rate inside the window.
  # - A window that ends before the first rate answers first_rate_date null
  #   and unvalued_through_end true.
  # - Every figure is unchanged: the result is 2500, all of it in
  #   cash_currency_effect.
  test "names a cash account held before its first rate, on both reads and in both forms",
       %{conn: conn} do
    world = franc_world()
    year = world.year
    view = view!(world, "Franc View")
    # The view's one bucket tags the CHF account too.
    buckets = Buckets.cash_account_bucket_ids(world.cash.id)
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), world.franc, buckets)

    expected = %{
      "cash_account_id" => world.franc.id,
      "name" => "Tagesgeld CHF",
      "currency_code" => "CHF",
      "balance" => "2000",
      "unvalued_days" => 18,
      "unvalued_reason" => "no_rate",
      "unvalued_through_end" => false,
      "first_rate_date" => "#{year}-08-01"
    }

    paths = [
      "/api/v1/portfolios/#{world.portfolio.id}/performance",
      "/api/v1/portfolios/#{world.portfolio.id}/performance/contribution",
      "/api/v1/portfolios/#{world.portfolio.id}/performance?view=#{view.id}",
      "/api/v1/portfolios/#{world.portfolio.id}/performance/contribution?view=#{view.id}",
      "/api/v1/views/#{view.id}/performance",
      "/api/v1/views/#{view.id}/performance/contribution"
    ]

    for path <- paths do
      separator = if path =~ "?", do: "&", else: "?"
      data = get_json(conn, path <> separator <> "year=#{year}")["data"]
      assert data["unvalued_cash_accounts"] == [expected], path

      early =
        get_json(conn, path <> separator <> "from=#{year}-07-01&to=#{year}-07-31")["data"]

      assert early["unvalued_cash_accounts"] == [
               %{expected | "unvalued_through_end" => true, "first_rate_date" => nil}
             ],
             path
    end

    contribution =
      get_json(
        conn,
        "/api/v1/portfolios/#{world.portfolio.id}/performance/contribution?year=#{year}"
      )["data"]

    assert contribution["remainder"]["cash_currency_effect"] == "2500"
    assert contribution["totals"]["result"] == "2500"
    assert contribution["positions"] == []
  end

  # User story (FR-41, ADR-0051 §6):
  # As the operator's agent sending a wrong id or period,
  # I want the performance read's answers,
  # so that one error contract covers the whole family.
  #
  # Acceptance criteria:
  # - An unknown or malformed portfolio, and an unknown view= on it, are 404;
  #   a malformed view= is 422 on view.
  # - An unknown or malformed view id on the view form is 404.
  # - An unknown period, a malformed year, a half-given or backwards range
  #   are 422 on period, on both forms.
  test "answers the performance read's errors", %{conn: conn} do
    world = world()
    view = view!(world, "Error View")
    portfolio = "/api/v1/portfolios/#{world.portfolio.id}/performance/contribution"
    across = "/api/v1/views/#{view.id}/performance/contribution"

    assert get_json(conn, "/api/v1/portfolios/999999/performance/contribution", 404) ==
             %{"errors" => %{"detail" => "not found"}}

    assert get_json(conn, "/api/v1/portfolios/abc/performance/contribution", 404)
    assert get_json(conn, "#{portfolio}?view=999999", 404)

    assert get_json(conn, "#{portfolio}?view=abc", 422) ==
             %{"errors" => %{"view" => ["is invalid"]}}

    assert get_json(conn, "/api/v1/views/999999/performance/contribution", 404)
    assert get_json(conn, "/api/v1/views/abc/performance/contribution", 404)

    for base <- [portfolio, across],
        query <- [
          "?period=2w",
          "?year=abc",
          "?from=2025-01-01",
          "?from=2025-05-01&to=2025-01-01",
          "?from=2025-13-01&to=2025-12-31"
        ] do
      assert get_json(conn, base <> query, 422) == %{"errors" => %{"period" => ["is invalid"]}},
             base <> query
    end
  end

  # A concurrent delete that commits after the controller looked the view up
  # and before the contribution read loads it: the hook deletes the view
  # right after the request's first read of the views table, in the request's
  # own process.
  defp with_view_deleted_after_lookup(view, fun) do
    test_pid = self()
    handler = "contribution-view-race-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:portfolixir, :repo, :query],
        fn _event, _measurements, %{query: query}, _config ->
          if self() == test_pid and query =~ ~s(FROM "views") and
               Process.get(handler) == nil do
            Process.put(handler, :deleted)
            {:ok, _} = Buckets.delete_view(Actor.owner_ui(), view)
          end
        end,
        nil
      )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end
  end

  # User story (FR-41, ADR-0051 §6):
  # As the operator's agent reading a view's contribution while the
  # operator deletes that view,
  # I want the read to answer not found,
  # so that the race costs me one round trip and never a server error.
  #
  # Acceptance criteria:
  # - A view deleted after the portfolio read resolved view= and before the
  #   contribution loads it answers 404, never a 500.
  # - The same holds for the view read across every portfolio.
  test "a view deleted during the read is a 404 in both forms", %{conn: conn} do
    world = world()

    narrowed = view!(world, "Vanishing View")
    path = "/api/v1/portfolios/#{world.portfolio.id}/performance/contribution?view=#{narrowed.id}"

    assert with_view_deleted_after_lookup(narrowed, fn -> get_json(conn, path, 404) end) ==
             %{"errors" => %{"detail" => "not found"}}

    assert Buckets.get_view(narrowed.id) == nil

    across = view!(world, "Vanishing Across")

    assert with_view_deleted_after_lookup(across, fn ->
             get_json(conn, "/api/v1/views/#{across.id}/performance/contribution", 404)
           end) == %{"errors" => %{"detail" => "not found"}}

    assert Buckets.get_view(across.id) == nil
  end
end
