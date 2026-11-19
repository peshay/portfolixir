defmodule Portfolixir.Portfolios.Performance.MoversTest do
  # Sprint 30 Lane T, T1 (FR-59, idea I32, ADR-0061 §2 to §6): the tops
  # and flops per calendar window, two rankings over one window, derived at
  # every read. Risk tier (money math): every figure below is an exact
  # Decimal derived by hand in the comments, at Decimal's default context
  # (34 significant digits, half-up), and was recomputed independently in
  # Python's `decimal` at the same precision. The price side must agree with
  # `WindowReturn` (sale hindsight's function) and the money side with
  # ADR-0051's contribution read (Wealth's table) to the last digit.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [
      add_depot: 2,
      base_world: 1,
      buy!: 3,
      deliver_untraded!: 4,
      deposit!: 3,
      deposit!: 4,
      put_quotes!: 2,
      sell!: 3
    ]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Fx
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Portfolios.Performance.Contribution
  alias Portfolixir.Portfolios.Performance.Movers
  alias Portfolixir.Portfolios.Performance.SaleHindsight
  alias Portfolixir.Portfolios.Performance.WindowReturn

  # The keys metrics_carry_no_verdict_test.exs refuses anywhere in a metric
  # payload; T2 walks the API's answer with it, this file the read's.
  @forbidden ~w(signal recommend rating score action alert verdict advice)

  defp d(value), do: Decimal.new(value)

  defp assert_decimal(actual, expected) do
    assert %Decimal{} = actual
    assert Decimal.equal?(actual, d(expected)), "expected #{expected}, got #{inspect(actual)}"
  end

  defp security!(attrs) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(%{currency_code: "EUR", asset_class: "fund"}, attrs)
      )

    security
  end

  defp rate!(currency, date, rate) do
    {:ok, 1} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: currency,
          date: date,
          rate: rate,
          source: "manual"
        }
      ])
  end

  defp view!(depots, cash_accounts) do
    {:ok, bucket} =
      Buckets.create_bucket(Actor.owner_ui(), %{
        name: "Movers #{System.unique_integer([:positive])}"
      })

    for depot <- depots,
        do: :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [bucket.id])

    for cash <- cash_accounts,
        do: :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), cash, [bucket.id])

    {:ok, view} =
      Buckets.create_view(Actor.owner_ui(), %{
        name: "Movers #{System.unique_integer([:positive])}",
        include_all: false
      })

    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])
    view
  end

  defp names(entries), do: Enum.map(entries, & &1.security.name)

  defp read!(view_id, window, opts) do
    assert {:ok, read} = Movers.read(view_id, window, opts)
    read
  end

  defp entry(entries, security), do: Enum.find(entries, &(&1.security.id == security.id))

  defp all_entries(ranking), do: ranking.highest ++ ranking.lowest

  # -- §3: the windows and their start days -------------------------------------

  # User story (FR-59, ADR-0061 §3):
  # As the operator glancing at what moved this week, month, quarter or year,
  # I want each window to start from the close that stands for the day before
  # it,
  # so that "this week" means since last week's close, on every weekday.
  #
  # Acceptance criteria:
  # - week: the day before this ISO week's Monday, on a Monday and a Sunday
  #   too; month: the last day of the previous month; quarter: the last day
  #   of the previous calendar quarter; ytd: 31 December of the previous
  #   year; 1y: one year back, 29 February mapping to 28 February; day: no
  #   single start day.
  # - Every window ends on the as-of day; an unknown window is refused.
  test "each window's start day" do
    # A Monday's week starts from the Sunday before it, so from Friday's
    # close for a share; the Sunday of the same week starts from that Sunday.
    assert Movers.start_on("week", ~D[2026-11-16]) == ~D[2026-11-15]
    assert Movers.start_on("week", ~D[2026-11-18]) == ~D[2026-11-15]
    assert Movers.start_on("week", ~D[2026-11-22]) == ~D[2026-11-15]

    # A month's first day starts from the previous month's last, leap day
    # included.
    assert Movers.start_on("month", ~D[2026-11-01]) == ~D[2026-10-31]
    assert Movers.start_on("month", ~D[2026-03-01]) == ~D[2026-02-28]
    assert Movers.start_on("month", ~D[2024-03-01]) == ~D[2024-02-29]

    # A quarter's first day starts from the previous quarter's last.
    assert Movers.start_on("quarter", ~D[2026-04-01]) == ~D[2026-03-31]
    assert Movers.start_on("quarter", ~D[2026-11-19]) == ~D[2026-09-30]
    assert Movers.start_on("quarter", ~D[2026-01-01]) == ~D[2025-12-31]

    # 1 January: the year to date, the month and the quarter all start from
    # 31 December.
    assert Movers.start_on("ytd", ~D[2026-01-01]) == ~D[2025-12-31]
    assert Movers.start_on("ytd", ~D[2026-11-19]) == ~D[2025-12-31]
    assert Movers.start_on("month", ~D[2026-01-01]) == ~D[2025-12-31]

    # 29 February maps to 28 February a year back.
    assert Movers.start_on("1y", ~D[2028-02-29]) == ~D[2027-02-28]
    assert Movers.start_on("1y", ~D[2024-02-29]) == ~D[2023-02-28]
    assert Movers.start_on("1y", ~D[2026-11-19]) == ~D[2025-11-19]

    # "Tag" has no single start day: it is per security (price) and one day
    # D (money).
    assert Movers.start_on("day", ~D[2026-11-19]) == nil

    assert Movers.windows() == ~w(day week month quarter ytd 1y)
    assert {:error, :invalid_window} = Movers.read(nil, "2y", today: ~D[2026-11-19])
    assert {:error, :invalid_window} = Movers.read(nil, :week, today: ~D[2026-11-19])
  end

  # -- §3 and the Consequences: the price side is WindowReturn's ----------------

  # User story (FR-59, ADR-0061 §3, the plan's D-1 criterion 7):
  # As the agent comparing this week's move with what a sale missed,
  # I want a security's week here to be sale hindsight's window return over
  # the same dates,
  # so that two surfaces never show two figures for one move.
  #
  # Acceptance criteria:
  # - The week's price return is WindowReturn.price_return(security, S, T):
  #   the start close stands for the Sunday before the Monday (Friday's
  #   close), each close converts at its own date's EUR-hub rate, one
  #   division.
  # - Sale hindsight's span over the same two dates (a sale on S, its latest
  #   close on T) answers the same Decimal to the last digit.
  # - The row names both closes, their dates and their EUR values.
  test "a security's week equals sale hindsight's WindowReturn over the same dates" do
    world =
      base_world(
        name: "Harbor World",
        cash_currency: "USD",
        cash_name: "Harbor Cash",
        depot_name: "Harbor Depot"
      )

    harbor = security!(%{name: "Harbor Freight Inc", currency_code: "USD", ticker_symbol: "HBF"})
    rate!("USD", ~D[2026-10-01], "1.17")
    rate!("USD", ~D[2026-11-06], "1.1612")
    rate!("USD", ~D[2026-11-12], "1.1587")
    deposit!(world, "5000", ~D[2026-10-01], currency: "USD")
    buy!(world, harbor, quantity: "10", price: "110", date: ~D[2026-10-01], currency: "USD")
    put_quotes!(harbor, [{~D[2026-11-06], "120.40"}, {~D[2026-11-12], "126.10"}])
    # Two of ten sold on the week's start day; eight are held at T.
    sell!(world, harbor, quantity: "2", price: "121", date: ~D[2026-11-08], currency: "USD")

    today = ~D[2026-11-12]
    read = read!(nil, "week", today: today)

    assert read.start_on == ~D[2026-11-08]
    assert read.end_on == today
    assert [row] = read.price_return.highest
    assert read.price_return.lowest == []

    # (126.10 x 1.1612) / (120.40 x 1.1587) - 1, one division at 34 digits:
    # 146.42732 / 139.50748 - 1 = 0.049601928154676724144110408990256.
    assert Decimal.to_string(row.return) == "0.049601928154676724144110408990256"
    assert row.start.stands_for == ~D[2026-11-08]
    assert row.start.date == ~D[2026-11-06]
    assert_decimal(row.start.close, "120.40")
    assert row.end.date == ~D[2026-11-12]
    assert_decimal(row.end.close, "126.10")

    assert {:ok, direct} = WindowReturn.price_return(harbor, ~D[2026-11-08], today)
    assert Decimal.to_string(row.return) == Decimal.to_string(direct.return)
    assert row.start == direct.start and row.end == direct.end

    %{rows: [sale]} = SaleHindsight.report(today: today)
    latest = Enum.find(sale.spans, &(&1.span == "latest"))
    assert latest.end_on == today
    assert Decimal.to_string(latest.security.return) == Decimal.to_string(row.return)
  end

  # -- §3: "Tag" per security on the price side, one day D on the money side -----

  # User story (FR-59, ADR-0061 §3 and §6.3; board 04's weekend state):
  # As the operator looking on a Monday morning before the shares' closes
  # arrive,
  # I want each security's "Tag" to be its last close against the one before,
  # and the money side's day to be the last day any held security closed,
  # so that a share reads Friday against Thursday and a coin its Sunday, and
  # each row says so.
  #
  # Acceptance criteria:
  # - Price, day: per security, its latest close E (on or before T) against
  #   the close before it P, by WindowReturn.price_return(security, P, E);
  #   the row carries P and E.
  # - Money, day: the window [D, D], D the latest day on or before T on which
  #   a close of any security the scope holds is stored, named in the answer.
  # - A weekend's "Tag" reads the same: the share Friday against Thursday.
  # - On a Monday before the Monday closes, the week has moved nothing yet.
  test "day is per security on the price side and the last close day on the money side" do
    world = base_world(name: "Tag World", cash_name: "Tag Cash", depot_name: "Tag Depot")
    view = view!([world.depot], [world.cash])
    share = security!(%{name: "Linden Works AG", asset_class: "equity"})
    coin = security!(%{name: "Kestrel Coin", asset_class: "crypto"})

    deposit!(world, "1000", ~D[2026-11-01])
    buy!(world, share, quantity: "10", price: "48", date: ~D[2026-11-02])
    buy!(world, coin, quantity: "2", price: "190", date: ~D[2026-11-02])
    put_quotes!(share, [{~D[2026-11-12], "50"}, {~D[2026-11-13], "52"}])

    put_quotes!(coin, [
      {~D[2026-11-13], "200"},
      {~D[2026-11-14], "210"},
      {~D[2026-11-15], "205"}
    ])

    # Monday 16 November, no Monday close yet.
    monday = read!(view.id, "day", today: ~D[2026-11-16])
    assert monday.start_on == nil
    assert monday.end_on == ~D[2026-11-16]

    # Share: Friday 52 against Thursday 50: 52 / 50 - 1 = 0.04.
    # Coin: Sunday 205 against Saturday 210: 205 / 210 - 1 = -1/42.
    assert [%{} = top] = monday.price_return.highest
    assert [%{} = bottom] = monday.price_return.lowest
    assert top.security.id == share.id
    assert_decimal(top.return, "0.04")
    assert {top.start.date, top.end.date} == {~D[2026-11-12], ~D[2026-11-13]}
    assert bottom.security.id == coin.id
    assert Decimal.to_string(bottom.return) == "-0.0238095238095238095238095238095238"
    assert {bottom.start.date, bottom.end.date} == {~D[2026-11-14], ~D[2026-11-15]}

    {:ok, direct} = WindowReturn.price_return(coin, ~D[2026-11-14], ~D[2026-11-15])
    assert bottom.return == direct.return

    # Money: D is Sunday, the coin's last close; only the coin moved.
    # Share 10 x 52 -> 10 x 52 = 0, a contribution of exactly 0, so it stands
    # in neither half and is counted (board 04 ②); coin 2 x 210 -> 2 x 205 =
    # -10, the one answered entry, so the highest half.
    money = monday.contribution
    assert {money.from, money.to} == {~D[2026-11-15], ~D[2026-11-15]}
    assert [%{contribution: coin_day} = coin_row] = money.highest
    assert money.lowest == []
    assert money.unanswered == %{no_valuation: 0, zero_contribution: 1}
    assert coin_row.security.id == coin.id
    assert_decimal(coin_day, "-10")

    {:ok, wealth} =
      Contribution.for_view(view.id,
        period: {:range, ~D[2026-11-15], ~D[2026-11-15]},
        base_currency: "EUR",
        today: ~D[2026-11-16]
      )

    assert Enum.find(wealth.positions, &(&1.security_id == coin.id)).contribution == coin_day

    # The weekend's "Tag" is the same answer on the Sunday: Friday against
    # Thursday for the share, Sunday against Saturday for the coin.
    sunday = read!(view.id, "day", today: ~D[2026-11-15])
    assert names(sunday.price_return.highest) == ["Linden Works AG"]
    assert names(sunday.price_return.lowest) == ["Kestrel Coin"]
    assert {sunday.contribution.from, sunday.contribution.to} == {~D[2026-11-15], ~D[2026-11-15]}

    # On the Saturday the coin rose: 210 / 200 - 1 = 0.05 above the share's
    # 0.04; its day's money 2 x (210 - 200) = 20.
    saturday = read!(view.id, "day", today: ~D[2026-11-14])
    assert [coin_top] = saturday.price_return.highest
    assert coin_top.security.id == coin.id
    assert_decimal(coin_top.return, "0.05")

    assert {saturday.contribution.from, saturday.contribution.to} ==
             {~D[2026-11-14], ~D[2026-11-14]}

    assert_decimal(hd(saturday.contribution.highest).contribution, "20")

    # The Monday's week starts from Sunday: the share's start and end closes
    # are both Friday's, the coin's both Sunday's; neither moved. Equal
    # figures order by name: Kestrel before Linden.
    week = read!(view.id, "week", today: ~D[2026-11-16])
    assert week.start_on == ~D[2026-11-15]
    assert names(week.price_return.highest) == ["Kestrel Coin"]
    assert names(week.price_return.lowest) == ["Linden Works AG"]
    for row <- all_entries(week.price_return), do: assert_decimal(row.return, "0")
    linden = entry(all_entries(week.price_return), share)
    assert {linden.start.date, linden.end.date} == {~D[2026-11-13], ~D[2026-11-13]}
    assert {week.contribution.from, week.contribution.to} == {~D[2026-11-16], ~D[2026-11-16]}
  end

  # -- §2, §6.4, §6.6, §6.7: the universes, a split, a trade inside the window ---

  # User story (FR-59, ADR-0061 §2, §6.4, §6.6, §6.7):
  # As the operator reading this week's tops and flops,
  # I want the price ranking over what I hold today and the money ranking
  # over every position the week touched,
  # so that a split is not a crash, a position bought and sold inside the
  # week shows what it made, and both agree with Wealth's table.
  #
  # Acceptance criteria:
  # - A split inside the window reads in the current display basis: 200
  #   before a 2:1 split and 102 after is +2 %, not -49 %.
  # - A security bought and sold inside the window is not ranked by price; it
  #   is ranked by contribution, held_at_end false.
  # - A security bought inside the window and held at its end is ranked by
  #   its price return over the whole window; the purchase moves only its
  #   contribution.
  # - A position held over the whole window without flows reads the same
  #   sign in both rankings.
  # - Each contribution equals Wealth's table (ADR-0051's view read) for the
  #   custom window S + 1 to T, every term of the row.
  # - Nothing outside the view is ranked.
  test "a split, a round trip and the scope: both rankings, Wealth's figures" do
    world = base_world(name: "Week World", cash_name: "Week Cash", depot_name: "Week Depot")
    outside = add_depot(world.portfolio, cash_name: "Outside Cash", depot_name: "Outside Depot")
    view = view!([world.depot], [world.cash])

    alder = security!(%{name: "Alder Split SE", asset_class: "equity"})
    birch = security!(%{name: "Birch Trade NV", asset_class: "equity"})
    cedar = security!(%{name: "Cedar Hold PLC", asset_class: "equity"})
    dune = security!(%{name: "Dune Late AG", asset_class: "equity"})
    yonder = security!(%{name: "Yonder Fund"})

    deposit!(world, "2000", ~D[2026-11-01])
    buy!(world, alder, quantity: "5", price: "200", date: ~D[2026-11-02])
    buy!(world, cedar, quantity: "4", price: "25", date: ~D[2026-11-02])

    put_quotes!(alder, [{~D[2026-11-06], "200"}, {~D[2026-11-10], "101"}, {~D[2026-11-12], "102"}])

    put_quotes!(cedar, [{~D[2026-11-06], "25"}, {~D[2026-11-12], "24"}])
    put_quotes!(birch, [{~D[2026-11-06], "39"}, {~D[2026-11-10], "42"}, {~D[2026-11-12], "45"}])

    {:ok, _splits} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: alder.id,
        date: ~D[2026-11-10],
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    # Bought and sold inside the week: 3 at 40 with 1.50 fees, 3 at 44.
    buy!(world, birch, quantity: "3", price: "40", fees: "1.50", date: ~D[2026-11-09])
    sell!(world, birch, quantity: "3", price: "44", date: ~D[2026-11-11])

    # Bought inside the week and held: 2 at 52 on the Tuesday.
    put_quotes!(dune, [{~D[2026-11-06], "50"}, {~D[2026-11-12], "55"}])
    buy!(world, dune, quantity: "2", price: "52", date: ~D[2026-11-10])

    # Outside the view, held and moving: in neither ranking.
    outside_world = %{portfolio: world.portfolio, depot: outside.depot, cash: outside.cash}
    deposit!(outside_world, "500", ~D[2026-11-01])
    buy!(outside_world, yonder, quantity: "1", price: "100", date: ~D[2026-11-02])
    put_quotes!(yonder, [{~D[2026-11-06], "100"}, {~D[2026-11-12], "150"}])

    today = ~D[2026-11-12]
    read = read!(view.id, "week", today: today)
    assert read.view_id == view.id

    # Price: Dune 50 -> 55 is 0.1 over the whole week, bought on Tuesday or
    # not; Alder 200 / 2 = 100 -> 102 is 0.02; Cedar 25 -> 24 is -0.04.
    # Birch is not held at T; Yonder is outside the view.
    price = read.price_return
    assert names(price.highest) == ["Dune Late AG", "Alder Split SE"]
    assert names(price.lowest) == ["Cedar Hold PLC"]
    assert price.answered == 3
    assert_decimal(hd(price.highest).return, "0.1")
    alder_price = entry(price.highest, alder)
    assert_decimal(alder_price.return, "0.02")
    assert_decimal(alder_price.start.stored_close, "200")
    assert_decimal(alder_price.start.close, "100")
    assert_decimal(hd(price.lowest).return, "-0.04")

    # Money over 9 to 12 November: Alder 10 x 102 - 5 x 200 = 20; Birch
    # 0 - 0 - (120 - 132) - 1.50 = 10.50; Dune 2 x 55 - 0 - 104 = 6; Cedar
    # 4 x 24 - 4 x 25 = -4.
    money = read.contribution
    assert {money.from, money.to} == {~D[2026-11-09], today}
    assert names(money.highest) == ["Alder Split SE", "Birch Trade NV"]
    assert names(money.lowest) == ["Cedar Hold PLC", "Dune Late AG"]
    assert money.answered == 4
    assert_decimal(entry(money.lowest, dune).contribution, "6")
    assert_decimal(entry(money.lowest, dune).net_flows, "104")

    alder_money = entry(money.highest, alder)
    birch_money = entry(money.highest, birch)
    cedar_money = entry(money.lowest, cedar)
    assert_decimal(alder_money.contribution, "20")
    assert_decimal(birch_money.contribution, "10.50")
    assert_decimal(birch_money.costs, "1.50")
    assert birch_money.held_at_end == false
    assert alder_money.held_at_end == true
    assert_decimal(cedar_money.contribution, "-4")

    # §6.7: a position held over the whole window without flows reads one
    # sign in both rankings.
    for {security, money_row} <- [{alder, alder_money}, {cedar, cedar_money}] do
      price_row = entry(all_entries(price), security)
      assert Decimal.compare(price_row.return, 0) == Decimal.compare(money_row.contribution, 0)
    end

    # Wealth's table for the same custom window, the read Wealth's
    # Performance tab makes, term for term.
    {:ok, wealth} =
      Contribution.for_view(view.id,
        period: {:range, ~D[2026-11-09], today},
        base_currency: "EUR",
        today: today
      )

    for row <- all_entries(money) do
      table = Enum.find(wealth.positions, &(&1.security_id == row.security.id))

      for key <- [:contribution, :start_value, :end_value, :net_flows, :income, :costs] do
        assert Decimal.to_string(Map.fetch!(row, key)) ==
                 Decimal.to_string(Map.fetch!(table, key)),
               "#{row.security.name} #{key}"
      end

      assert {row.held_at_start, row.held_at_end, row.unvalued_days} ==
               {table.held_at_start, table.held_at_end, table.unvalued_days}
    end

    assert length(wealth.positions) == 4

    # Everything: Yonder joins both rankings, 100 -> 150 and 1 x 50.
    everything = read!(nil, "week", today: today)
    assert everything.view_id == nil
    assert names(everything.price_return.highest) == ["Yonder Fund", "Dune Late AG"]
    assert names(everything.price_return.lowest) == ["Cedar Hold PLC", "Alder Split SE"]

    assert names(everything.contribution.highest) ==
             ["Yonder Fund", "Alder Split SE", "Birch Trade NV"]

    assert names(everything.contribution.lowest) == ["Cedar Hold PLC", "Dune Late AG"]
  end

  # -- §4: the halves, never sharing a name ---------------------------------------

  # Eleven funds of one unit each, bought at 100 and closing 100 on the
  # Friday before the week; each closes at 100 + x on T, a price return of
  # x / 100 and a contribution of x.
  @moves [7, -3, 12, 0, -8, 5, 1, -1, 9, -12, 3]

  defp halves_world(moves) do
    world = base_world(name: "Halves World", cash_name: "Halves Cash", depot_name: "Halves Depot")
    view = view!([world.depot], [world.cash])
    deposit!(world, "5000", ~D[2026-11-01])

    for {move, index} <- Enum.with_index(moves) do
      fund = security!(%{name: "Fund #{<<?A + index>>}"})
      buy!(world, fund, quantity: "1", price: "100", date: ~D[2026-11-02])

      put_quotes!(fund, [{~D[2026-11-06], "100"}, {~D[2026-11-12], Integer.to_string(100 + move)}])
    end

    view
  end

  # Each figure normalized, so a money amount stored at 18 decimals reads as
  # the number it is; equality is checked digit for digit all the same.
  defp figures(entries, key),
    do: Enum.map(entries, &(&1 |> Map.fetch!(key) |> Decimal.normalize() |> Decimal.to_string()))

  # User story (FR-59, ADR-0061 §4 and §6.2; board 04's states):
  # As the operator reading the highest and the lowest of a window,
  # I want the two halves cut from one sorted list,
  # so that a name never stands in both, a short list reads as halves, and a
  # single holding reads as one highest and no lowest.
  #
  # Acceptance criteria:
  # - With n answered entries and a limit k, highest takes min(k, ceil(n/2))
  #   of the largest, descending, and lowest min(k, floor(n/2)) of the rest,
  #   ascending: n = 11 and k = 5 read 5 and 5; k = 50 reads 6 and 5; n = 6
  #   reads 3 and 3; n = 1 reads 1 and 0; n = 0 reads none.
  # - The money side's fund that ends where it started contributes exactly
  #   0 and is counted, not ranked (board 04 ②), so there n is 10 and 5,
  #   where the price side ranks its return of 0.
  # - The limit is 1 to 50, default 5.
  test "the halves never share a name: n = 11, 6, 1 and 0" do
    view = halves_world(@moves)
    today = ~D[2026-11-12]

    read = read!(view.id, "week", today: today)
    assert read.limit == 5
    price = read.price_return
    assert price.answered == 11
    assert figures(price.highest, :return) == ~w(0.12 0.09 0.07 0.05 0.03)
    assert figures(price.lowest, :return) == ~w(-0.12 -0.08 -0.03 -0.01 0)
    money = read.contribution
    assert money.answered == 10
    assert money.unanswered == %{no_valuation: 0, zero_contribution: 1}
    assert figures(money.highest, :contribution) == ~w(12 9 7 5 3)
    assert figures(money.lowest, :contribution) == ~w(-12 -8 -3 -1 1)

    wide = read!(view.id, "week", today: today, limit: 50)
    assert figures(wide.price_return.highest, :return) == ~w(0.12 0.09 0.07 0.05 0.03 0.01)
    assert figures(wide.price_return.lowest, :return) == ~w(-0.12 -0.08 -0.03 -0.01 0)
    assert figures(wide.contribution.highest, :contribution) == ~w(12 9 7 5 3)
    assert figures(wide.contribution.lowest, :contribution) == ~w(-12 -8 -3 -1 1)

    for {ranking, n} <- [{wide.price_return, 11}, {wide.contribution, 10}] do
      ids = Enum.map(all_entries(ranking), & &1.security.id)
      assert length(ids) == n and length(Enum.uniq(ids)) == n
    end

    # An empty view: n = 0 on both sides, never a list of zeros.
    empty = read!(view!([], []).id, "week", today: today)
    assert empty.price_return.answered == 0
    assert {empty.price_return.highest, empty.price_return.lowest} == {[], []}
    assert {empty.contribution.highest, empty.contribution.lowest} == {[], []}
    assert empty.contribution.answered == 0

    assert {:error, :invalid_limit} = Movers.read(view.id, "week", today: today, limit: 0)
    assert {:error, :invalid_limit} = Movers.read(view.id, "week", today: today, limit: 51)
    assert {:error, :invalid_limit} = Movers.read(view.id, "week", today: today, limit: "5")
    assert {:error, :view_not_found} = Movers.read(9_999_999, "week", today: today)
  end

  test "six held read three and three" do
    today = ~D[2026-11-12]
    six = halves_world(Enum.take(@moves, 6))
    read = read!(six.id, "week", today: today)
    assert figures(read.price_return.highest, :return) == ~w(0.12 0.07 0.05)
    assert figures(read.price_return.lowest, :return) == ~w(-0.08 -0.03 0)
    # The fund at 0 is counted on the money side (board 04 ②): five
    # answered, three over two.
    assert figures(read.contribution.highest, :contribution) == ~w(12 7 5)
    assert figures(read.contribution.lowest, :contribution) == ~w(-8 -3)
    assert read.contribution.unanswered.zero_contribution == 1
  end

  test "one held security reads one highest and no lowest" do
    today = ~D[2026-11-12]
    one = halves_world([7])
    read = read!(one.id, "week", today: today)
    assert figures(read.price_return.highest, :return) == ~w(0.07)
    assert read.price_return.lowest == []
    assert figures(read.contribution.highest, :contribution) == ~w(7)
    assert read.contribution.lowest == []
  end

  # -- §4: ties by ADR-0058 G1's full order ------------------------------------------

  # User story (FR-59, ADR-0061 §4 and §6.1):
  # As the agent reading the same ranking twice,
  # I want equal figures ordered by the name case-folded, the ISIN, the
  # ticker, the WKN and the currency, never by an id or the order rows were
  # stored in,
  # so that a rank never depends on how the database answered.
  #
  # Acceptance criteria:
  # - Every key of ADR-0058 G1 decides a tie where the keys before it are
  #   equal; a missing value sorts after a present one.
  # - The highest half takes the first of that order, the lowest half the
  #   rest in the same order, on both rankings.
  #
  # Every fund closes 100 then 101: a return of 0.01 and a contribution of
  # 1 each, equal and not 0, since a contribution of exactly 0 is in neither
  # half (board 04 ②). The dollar's hub rate is 1, so its 1 dollar is 1 EUR
  # too.
  test "ties follow the full order on every key" do
    world = base_world(name: "Tie World", cash_name: "Tie Cash", depot_name: "Tie Depot")
    view = view!([world.depot], [world.cash])
    rate!("USD", ~D[2026-11-01], "1")

    # Created out of order, so neither creation nor id order is the answer.
    specs = [
      {"usd", %{name: "Same Fund", currency_code: "USD"}},
      {"wkn", %{name: "Same Fund", wkn: "A0SAM1"}},
      {"ticker-b-wkn2", %{name: "Same Fund", ticker_symbol: "BBB", wkn: "A0SAM2"}},
      {"isin2", %{name: "same fund", isin: "XS0000000025"}},
      {"ticker-a", %{name: "SAME FUND", ticker_symbol: "AAA"}},
      {"ticker-b-nowkn", %{name: "Same Fund", ticker_symbol: "BBB"}},
      {"eur", %{name: "Same Fund"}},
      {"ash", %{name: "Ash Fund"}},
      {"isin1", %{name: "Same Fund", isin: "XS0000000017"}},
      {"ticker-b-wkn1", %{name: "Same Fund", ticker_symbol: "BBB", wkn: "A0SAM0"}},
      # Equal on every key: the one created first stands first.
      {"twin-first", %{name: "Zeta Twin"}},
      {"twin-second", %{name: "Zeta Twin"}}
    ]

    securities =
      Map.new(specs, fn {key, attrs} ->
        security = security!(attrs)
        deliver_untraded!(world, security, "1", date: ~D[2026-11-02])
        put_quotes!(security, [{~D[2026-11-06], "100"}, {~D[2026-11-12], "101"}])
        {key, security.id}
      end)

    expected =
      Enum.map(
        ~w(ash isin1 isin2 ticker-a ticker-b-wkn1 ticker-b-wkn2 ticker-b-nowkn wkn eur usd) ++
          ~w(twin-first twin-second),
        &Map.fetch!(securities, &1)
      )

    read = read!(view.id, "week", today: ~D[2026-11-12], limit: 50)

    for ranking <- [read.price_return, read.contribution] do
      assert ranking.answered == 12
      assert Enum.map(ranking.highest, & &1.security.id) == Enum.take(expected, 6)
      assert Enum.map(ranking.lowest, & &1.security.id) == Enum.drop(expected, 6)
    end

    for row <- all_entries(read.price_return), do: assert_decimal(row.return, "0.01")
    for row <- all_entries(read.contribution), do: assert_decimal(row.contribution, "1")
  end

  # -- §4: no answer, never a zero -----------------------------------------------------

  # User story (FR-59, ADR-0061 §4; board 04: unpriced funds):
  # As the operator whose view holds a fund nobody quotes,
  # I want a security without a figure counted under its reason, and a
  # position valued on no day or contributing exactly zero counted apart,
  # so that neither fills the lowest half with a zero it never earned.
  #
  # Acceptance criteria:
  # - Price: no_close_at_start, no_close_at_end and no_fx_rate are counted,
  #   and for day also one_close_only; include_unanswered lists them in the
  #   tie order with the reason.
  # - Money: a position valued on no day of the window is counted
  #   no_valuation, not ranked; one with some unvalued days stays ranked with
  #   its unvalued_days in its row.
  # - Money: a position whose contribution is exactly 0 stands in neither
  #   half and is counted zero_contribution (board 04 ②; ADR-0061's
  #   amendment of 2026-11-19, third precision; Sprint 30 closing act,
  #   design critic, finding 4).
  test "the unanswered are counted by reason, never ranked as a zero" do
    world = base_world(name: "Gap World", cash_name: "Gap Cash", depot_name: "Gap Depot")
    view = view!([world.depot], [world.cash])

    steady = security!(%{name: "Steady Fund"})
    fresh = security!(%{name: "Fresh Listing"})
    single = security!(%{name: "Single Print"})
    stale = security!(%{name: "Stale Quote"})
    franc = security!(%{name: "Franc Fund", currency_code: "CHF"})
    unquoted = security!(%{name: "Unquoted Trust"})

    for security <- [steady, fresh, single, stale, franc, unquoted],
        do: deliver_untraded!(world, security, "1", date: ~D[2026-11-02])

    put_quotes!(steady, [{~D[2026-11-06], "10"}, {~D[2026-11-12], "11"}])
    put_quotes!(fresh, [{~D[2026-11-10], "20"}, {~D[2026-11-12], "21"}])
    put_quotes!(single, [{~D[2026-11-12], "5"}])
    put_quotes!(stale, [{~D[2026-11-03], "8"}])
    put_quotes!(franc, [{~D[2026-11-06], "30"}, {~D[2026-11-12], "33"}])

    today = ~D[2026-11-12]
    week = read!(view.id, "week", today: today, include_unanswered: true)

    # Only Steady has both closes in EUR: 11 / 10 - 1 = 0.1.
    price = week.price_return
    assert price.answered == 1
    assert names(price.highest) == ["Steady Fund"]
    assert_decimal(hd(price.highest).return, "0.1")

    assert price.unanswered == %{no_close_at_start: 3, no_close_at_end: 1, no_fx_rate: 1}

    assert Enum.map(price.unanswered_entries, &{&1.security.name, &1.reason}) == [
             {"Franc Fund", "no_fx_rate"},
             {"Fresh Listing", "no_close_at_start"},
             {"Single Print", "no_close_at_start"},
             {"Stale Quote", "no_close_at_end"},
             {"Unquoted Trust", "no_close_at_start"}
           ]

    # Money over 9 to 12 November: Fresh 0 -> 21 (unvalued on the 8th, the
    # baseline, and the 9th), Single 0 -> 5 (unvalued 8th to 11th), Steady
    # 10 -> 11, Stale 8 -> 8. Franc has no rate path and Unquoted no price on
    # any day: no_valuation. The baseline counts since ADR-0051's amendment
    # of 2026-11-19 (#1472). Stale's 0 is a figure no half shows (board 04
    # ②): counted zero_contribution, so three answered split two over one.
    money = week.contribution
    assert money.answered == 3
    assert names(money.highest) == ["Fresh Listing", "Single Print"]
    assert figures(money.highest, :contribution) == ~w(21 5)
    assert names(money.lowest) == ["Steady Fund"]
    assert figures(money.lowest, :contribution) == ~w(1)

    assert {entry(money.highest, fresh).unvalued_days, entry(money.highest, single).unvalued_days} ==
             {2, 4}

    assert entry(money.highest, fresh).unvalued_reason == :no_price
    assert entry(money.lowest, steady).unvalued_days == 0
    assert money.unanswered == %{no_valuation: 2, zero_contribution: 1}

    assert Enum.map(money.unanswered_entries, &{&1.security.name, &1.reason}) == [
             {"Franc Fund", "no_valuation"},
             {"Stale Quote", "zero_contribution"},
             {"Unquoted Trust", "no_valuation"}
           ]

    assert money.computation_basis.gaps =~ "zero_contribution"
    assert money.computation_basis.halves =~ "exactly 0"

    # Day: Steady 11 against 10 (P on the 6th, the close before E), Fresh 21
    # against 20 = 0.05; Stale's last close is older than 7 days, Unquoted has
    # none, Single only one.
    day = read!(view.id, "day", today: today)
    assert day.price_return.answered == 2
    assert names(day.price_return.highest) == ["Steady Fund"]
    assert names(day.price_return.lowest) == ["Fresh Listing"]
    assert hd(day.price_return.highest).start.date == ~D[2026-11-06]
    assert_decimal(hd(day.price_return.lowest).return, "0.05")
    refute Map.has_key?(day.price_return, :unanswered_entries)

    assert day.price_return.unanswered == %{
             no_close_at_start: 0,
             no_close_at_end: 2,
             no_fx_rate: 1,
             one_close_only: 1
           }
  end

  # -- 29 February, the year and the month ---------------------------------------------

  # User story (FR-59, ADR-0061 §3):
  # As the operator on a leap day,
  # I want the year to start from 28 February a year back and the year to
  # date and the month from their last days,
  # so that no window starts on a day that does not exist.
  #
  # Acceptance criteria:
  # - On 29 February 2024: 1y from 28 February 2023, ytd and quarter from 31
  #   December 2023 (Friday's close standing for the Sunday), month from 31
  #   January 2024; each price return and contribution exact.
  test "29 February: the year, the year to date, the quarter and the month" do
    world = base_world(name: "Leap World", cash_name: "Leap Cash", depot_name: "Leap Depot")
    view = view!([world.depot], [world.cash])
    leap = security!(%{name: "Leap Fund"})
    deposit!(world, "500", ~D[2023-01-10])
    buy!(world, leap, quantity: "2", price: "75", date: ~D[2023-01-10])

    put_quotes!(leap, [
      {~D[2023-02-28], "80"},
      {~D[2023-12-29], "88"},
      {~D[2024-01-31], "90"},
      {~D[2024-02-29], "92"}
    ])

    today = ~D[2024-02-29]

    # 92 / 80 - 1 = 0.15; 2 x (92 - 80) = 24.
    year = read!(view.id, "1y", today: today)
    assert year.start_on == ~D[2023-02-28]
    assert_decimal(hd(year.price_return.highest).return, "0.15")
    assert {year.contribution.from, year.contribution.to} == {~D[2023-03-01], today}
    assert_decimal(hd(year.contribution.highest).contribution, "24")

    # 92 / 88 - 1 = 1/22 at 34 digits; 2 x (92 - 88) = 8.
    for window <- ["ytd", "quarter"] do
      read = read!(view.id, window, today: today)
      assert read.start_on == ~D[2023-12-31]
      [row] = read.price_return.highest
      assert row.start.date == ~D[2023-12-29]
      assert Decimal.to_string(row.return) == "0.045454545454545454545454545454545"
      assert {read.contribution.from, read.contribution.to} == {~D[2024-01-01], today}
      assert_decimal(hd(read.contribution.highest).contribution, "8")
    end

    # 92 / 90 - 1 = 1/45 at 34 digits; 2 x (92 - 90) = 4.
    month = read!(view.id, "month", today: today)
    assert month.start_on == ~D[2024-01-31]

    assert Decimal.to_string(hd(month.price_return.highest).return) ==
             "0.022222222222222222222222222222222"

    assert_decimal(hd(month.contribution.highest).contribution, "4")
  end

  # -- §5 and §7: the basis in every payload, no verdict -------------------------------

  defp keys(map) when is_map(map) and not is_struct(map),
    do: Enum.flat_map(map, fn {key, value} -> [key | keys(value)] end)

  defp keys(list) when is_list(list), do: Enum.flat_map(list, &keys/1)
  defp keys(_value), do: []

  # User story (FR-59, ADR-0061 §5 and §7; AGENTS.md's metric rule):
  # As the agent checking a ranking by hand,
  # I want each ranking to state its input series, window, scope, universe,
  # close lookup, currency, tie order, split rule and gaps, with no
  # reference, and no key that reads as a verdict,
  # so that I can reproduce it and nothing in it tells me what to do.
  #
  # Acceptance criteria:
  # - Both rankings carry computation_basis with input_series, window,
  #   scope, universe, currency, ties, halves and gaps, and reference null.
  # - The window names its key and its dates; day names its per-row rule
  #   and D.
  # - No key of the payload contains a word the no-verdict invariant
  #   forbids.
  test "each ranking states its basis and carries no verdict key" do
    world = base_world(name: "Basis World", cash_name: "Basis Cash", depot_name: "Basis Depot")
    view = view!([world.depot], [world.cash])
    fund = security!(%{name: "Basis Fund"})
    unquoted = security!(%{name: "Basis Unquoted"})
    deposit!(world, "500", ~D[2026-11-01])
    buy!(world, fund, quantity: "1", price: "100", date: ~D[2026-11-02])
    deliver_untraded!(world, unquoted, "1", date: ~D[2026-11-02])
    put_quotes!(fund, [{~D[2026-11-06], "100"}, {~D[2026-11-12], "101"}])

    for window <- Movers.windows() do
      read = read!(view.id, window, today: ~D[2026-11-12], include_unanswered: true)

      for ranking <- [read.price_return, read.contribution] do
        basis = ranking.computation_basis

        for key <- [:input_series, :window, :scope, :universe, :currency, :ties, :halves, :gaps],
            do: assert(Map.has_key?(basis, key), "#{window}: #{key}")

        assert basis.reference == nil
        assert basis.currency == "EUR"
        assert basis.window.key == window
        assert basis.window.end_on == ~D[2026-11-12]
      end

      assert read.price_return.computation_basis.staleness_days == 7

      offenders =
        read
        |> keys()
        |> Enum.filter(fn key ->
          downcased = String.downcase(to_string(key))
          Enum.any?(@forbidden, &String.contains?(downcased, &1))
        end)

      assert offenders == [], "#{window}: #{inspect(offenders)}"
    end

    day = read!(view.id, "day", today: ~D[2026-11-12])
    assert day.price_return.computation_basis.window.start_on == nil
    assert day.contribution.computation_basis.window.day_on == ~D[2026-11-12]
  end
end
