defmodule Portfolixir.Portfolios.Performance.MoversAttackTest do
  # Sprint 30 plan D-5 item 5: the attack lens on T1 (FR-59, ADR-0061)
  # before integration, written by a session that did not build the read.
  # Risk tier (money math): every expected figure below was recomputed
  # independently in Python's `decimal` at 34 significant digits, half-up
  # (Decimal's default context), from the closes, rates and split ratios the
  # test stores; none is copied from the read's output.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [
      add_depot: 2,
      base_world: 1,
      buy!: 3,
      deliver_untraded!: 4,
      deposit!: 3,
      put_quotes!: 2,
      sell!: 3
    ]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Fx
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Lifecycle
  alias Portfolixir.Portfolios.Performance.Contribution
  alias Portfolixir.Portfolios.Performance.Movers
  alias Portfolixir.Portfolios.Performance.WindowReturn
  alias Portfolixir.Repo

  # metrics_carry_no_verdict_test.exs's words, matched as substrings of a key.
  @forbidden ~w(signal recommend rating score action alert verdict advice)

  defp d(value), do: Decimal.new(value)

  defp assert_decimal(actual, expected) do
    assert %Decimal{} = actual
    assert Decimal.equal?(actual, d(expected)), "expected #{expected}, got #{inspect(actual)}"
  end

  defp assert_exact(actual, expected) do
    assert %Decimal{} = actual
    assert Decimal.to_string(actual) == expected
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

  defp split!(security, date, numerator, denominator) do
    {:ok, _splits} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: date,
        ratio_numerator: numerator,
        ratio_denominator: denominator
      })
  end

  # A close a release before the plausibility bounds could store: written
  # past the changeset, as such a legacy row sits in the table.
  defp legacy_quote!(security, date, close) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    {1, _rows} =
      Repo.insert_all(SecurityQuote, [
        %{
          security_id: security.id,
          date: date,
          close: d(close),
          source: "manual",
          inserted_at: now,
          updated_at: now
        }
      ])
  end

  defp view!(depots, cash_accounts) do
    {:ok, bucket} =
      Buckets.create_bucket(Actor.owner_ui(), %{name: "Atk #{System.unique_integer([:positive])}"})

    for depot <- depots,
        do: :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [bucket.id])

    for cash <- cash_accounts,
        do: :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), cash, [bucket.id])

    {:ok, view} =
      Buckets.create_view(Actor.owner_ui(), %{
        name: "Atk #{System.unique_integer([:positive])}",
        include_all: false
      })

    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])
    view
  end

  defp world!(name) do
    world = base_world(name: name, cash_name: "#{name} Cash", depot_name: "#{name} Depot")
    {world, view!([world.depot], [world.cash])}
  end

  defp read!(view_id, window, opts) do
    assert {:ok, read} = Movers.read(view_id, window, opts)
    read
  end

  defp names(entries), do: Enum.map(entries, & &1.security.name)
  defp ids(entries), do: Enum.map(entries, & &1.security.id)
  defp all_entries(ranking), do: ranking.highest ++ ranking.lowest
  defp entry(entries, security), do: Enum.find(entries, &(&1.security.id == security.id))

  defp wealth_row!(view_id, from, to, today, security) do
    {:ok, wealth} =
      Contribution.for_view(view_id,
        period: {:range, from, to},
        base_currency: "EUR",
        today: today
      )

    Enum.find(wealth.positions, &(&1.security_id == security.id))
  end

  defp assert_disjoint(ranking) do
    highest = MapSet.new(ids(ranking.highest))
    lowest = MapSet.new(ids(ranking.lowest))
    assert MapSet.disjoint?(highest, lowest)
  end

  # -- splits: forward, reverse, on the start day -----------------------------------

  # Attack: a split, a reverse split and a split effective on the window's
  # start day S must read in one display basis on both ends, so none reads as
  # a crash or a jump, on the price side and on the money side.
  test "a 3:1 split, a 1:5 reverse split and a 2:1 split effective on S" do
    {world, view} = world!("Split")
    alpha = security!(%{name: "Alpha Three", asset_class: "equity"})
    bravo = security!(%{name: "Bravo Reverse", asset_class: "equity"})
    charlie = security!(%{name: "Charlie Sunday", asset_class: "equity"})

    deposit!(world, "5000", ~D[2026-11-01])
    buy!(world, alpha, quantity: "6", price: "200", date: ~D[2026-11-02])
    buy!(world, bravo, quantity: "100", price: "2", date: ~D[2026-11-02])
    buy!(world, charlie, quantity: "4", price: "100", date: ~D[2026-11-02])

    put_quotes!(alpha, [{~D[2026-11-06], "200"}, {~D[2026-11-12], "67"}])
    put_quotes!(bravo, [{~D[2026-11-06], "2"}, {~D[2026-11-12], "9.5"}])
    put_quotes!(charlie, [{~D[2026-11-06], "100"}, {~D[2026-11-12], "50.5"}])

    split!(alpha, ~D[2026-11-10], 3, 1)
    split!(bravo, ~D[2026-11-10], 1, 5)
    # Effective on the week's start day S, a Sunday: the close standing for S
    # is Friday's, from before the split.
    split!(charlie, ~D[2026-11-08], 2, 1)

    today = ~D[2026-11-12]
    read = read!(view.id, "week", today: today)
    assert read.start_on == ~D[2026-11-08]

    # Alpha: 67 x 3 / 200 - 1 = 0.005 (the display start 66.66... never
    # rounded). Bravo: 9.5 / (2 x 5) - 1 = -0.05. Charlie: 50.5 x 2 / 100 - 1
    # = 0.01.
    price = read.price_return
    assert names(price.highest) == ["Charlie Sunday", "Alpha Three"]
    assert names(price.lowest) == ["Bravo Reverse"]
    assert_exact(entry(price.highest, alpha).return, "0.005")
    assert_decimal(entry(price.highest, charlie).return, "0.01")
    assert_decimal(entry(price.lowest, bravo).return, "-0.05")
    assert_decimal(entry(price.lowest, bravo).start.close, "10")

    # Money over 9 to 12 November: Alpha 18 x 67 - 6 x 200 = 6; Bravo
    # 20 x 9.5 - 100 x 2 = -10; Charlie 8 x 50.5 - 4 x 100 = 4.
    money = read.contribution
    assert names(money.highest) == ["Alpha Three", "Charlie Sunday"]
    assert names(money.lowest) == ["Bravo Reverse"]
    assert_decimal(entry(money.highest, alpha).contribution, "6")
    assert_decimal(entry(money.highest, charlie).contribution, "4")
    assert_decimal(entry(money.lowest, bravo).contribution, "-10")
  end

  # Attack: a split effective on S where S has its own close (the post-split
  # close), and "day" across the split: P before the split, E on it.
  test "a split effective on a start day with a close, and day across it" do
    {world, view} = world!("Delta")
    delta = security!(%{name: "Delta Monday", asset_class: "equity"})
    deposit!(world, "1000", ~D[2025-06-01])
    buy!(world, delta, quantity: "4", price: "90", date: ~D[2025-06-02])
    put_quotes!(delta, [{~D[2025-06-27], "90"}, {~D[2025-06-30], "46"}, {~D[2025-07-10], "48.3"}])
    split!(delta, ~D[2025-06-30], 2, 1)

    # Month on 10 July 2025: S = Monday 30 June, its own post-split close 46.
    # 48.3 / 46 - 1 = 0.05; money 8 x (48.3 - 46) = 18.4.
    month = read!(view.id, "month", today: ~D[2025-07-10])
    assert month.start_on == ~D[2025-06-30]
    [row] = month.price_return.highest
    assert row.start.date == ~D[2025-06-30]
    assert_decimal(row.return, "0.05")
    assert_decimal(hd(month.contribution.highest).contribution, "18.4")

    # Day on 30 June: E = 46, P = Friday 27 June's 90 / 2 = 45.
    # 46 x 2 / 90 - 1 = 1/45 at 34 digits; money [30, 30]: 8 x 46 - 4 x 90 = 8.
    day = read!(view.id, "day", today: ~D[2025-06-30])
    [day_row] = day.price_return.highest
    assert {day_row.start.date, day_row.end.date} == {~D[2025-06-27], ~D[2025-06-30]}
    assert_exact(day_row.return, "0.022222222222222222222222222222222")
    assert {day.contribution.from, day.contribution.to} == {~D[2025-06-30], ~D[2025-06-30]}
    assert_decimal(hd(day.contribution.highest).contribution, "8")
  end

  # -- 29 February ---------------------------------------------------------------------

  # Attack: 29 February as the window's start day S, and the year back from
  # the days around it.
  test "29 February as a start day, and the year from 28 February and 1 March" do
    {world, view} = world!("Leap")
    leap = security!(%{name: "Leap Two"})
    deposit!(world, "500", ~D[2023-01-10])
    buy!(world, leap, quantity: "2", price: "75", date: ~D[2023-01-10])

    put_quotes!(leap, [
      {~D[2024-02-28], "80"},
      {~D[2024-02-29], "81"},
      {~D[2024-03-01], "82"},
      {~D[2024-03-15], "84.24"},
      {~D[2024-03-29], "85"},
      {~D[2024-05-15], "90"},
      {~D[2025-02-28], "100"}
    ])

    # Month on 15 March 2024: S = 29 February. 84.24 / 81 - 1 = 0.04;
    # 2 x 3.24 = 6.48.
    month = read!(view.id, "month", today: ~D[2024-03-15])
    assert month.start_on == ~D[2024-02-29]
    assert hd(month.price_return.highest).start.date == ~D[2024-02-29]
    assert_decimal(hd(month.price_return.highest).return, "0.04")
    assert {month.contribution.from, month.contribution.to} == {~D[2024-03-01], ~D[2024-03-15]}
    assert_decimal(hd(month.contribution.highest).contribution, "6.48")

    # 1y on 28 February 2025: S = 28 February 2024; the leap day is inside.
    # 100 / 80 - 1 = 0.25; 2 x 20 = 40.
    year = read!(view.id, "1y", today: ~D[2025-02-28])
    assert year.start_on == ~D[2024-02-28]
    assert_decimal(hd(year.price_return.highest).return, "0.25")
    assert {year.contribution.from, year.contribution.to} == {~D[2024-02-29], ~D[2025-02-28]}
    assert_decimal(hd(year.contribution.highest).contribution, "40")

    # 1y on Saturday 1 March 2025: S = 1 March 2024 (82); E stands on Friday.
    # 100 / 82 - 1 at 34 digits; 2 x 18 = 36.
    later = read!(view.id, "1y", today: ~D[2025-03-01])
    assert later.start_on == ~D[2024-03-01]
    assert_exact(hd(later.price_return.highest).return, "0.219512195121951219512195121951220")
    assert hd(later.price_return.highest).end.date == ~D[2025-02-28]
    assert_decimal(hd(later.contribution.highest).contribution, "36")

    # Day on 1 March 2024: P is the leap day. 82 / 81 - 1 at 34 digits;
    # money [1 March, 1 March]: 2 x 1 = 2.
    day = read!(view.id, "day", today: ~D[2024-03-01])
    assert hd(day.price_return.highest).start.date == ~D[2024-02-29]
    assert_exact(hd(day.price_return.highest).return, "0.012345679012345679012345679012346")
    assert_decimal(hd(day.contribution.highest).contribution, "2")

    # Quarter on 15 May 2024: S = Sunday 31 March, Friday 29 March's close.
    # 90 / 85 - 1 at 34 digits; 2 x 5 = 10.
    quarter = read!(view.id, "quarter", today: ~D[2024-05-15])
    assert quarter.start_on == ~D[2024-03-31]
    assert hd(quarter.price_return.highest).start.date == ~D[2024-03-29]
    assert_exact(hd(quarter.price_return.highest).return, "0.058823529411764705882352941176471")
    assert_decimal(hd(quarter.contribution.highest).contribution, "10")
  end

  # -- trades inside the window ----------------------------------------------------------

  # Attack: sold and bought back inside the window. One row on each side, the
  # price return the security's whole window, the money ADR-0051's.
  test "sold and bought back inside the window is one row on each side" do
    {world, view} = world!("Echo")
    echo = security!(%{name: "Echo Return", asset_class: "equity"})
    deposit!(world, "1000", ~D[2026-11-01])
    buy!(world, echo, quantity: "5", price: "40", date: ~D[2026-11-02])

    put_quotes!(echo, [
      {~D[2026-11-06], "40"},
      {~D[2026-11-09], "41"},
      {~D[2026-11-10], "42"},
      {~D[2026-11-11], "43"},
      {~D[2026-11-12], "44"}
    ])

    sell!(world, echo, quantity: "5", price: "41", date: ~D[2026-11-09])
    buy!(world, echo, quantity: "5", price: "43", date: ~D[2026-11-11])

    today = ~D[2026-11-12]
    read = read!(view.id, "week", today: today)

    # 44 / 40 - 1 = 0.1.
    assert [row] = read.price_return.highest
    assert_decimal(row.return, "0.1")

    # 5 x 44 - 5 x 40 - (5 x 43 - 5 x 41) = 10.
    assert [money] = read.contribution.highest
    assert read.contribution.lowest == []
    assert_decimal(money.contribution, "10")
    assert {money.held_at_start, money.held_at_end} == {true, true}
  end

  # Attack: a security the view's depot sold out of but another depot (outside
  # the view) still holds is not in the view's price universe, and is in its
  # money ranking as sold; everything ranks it by price.
  test "sold out in the view, held outside it" do
    {world, view} = world!("Fox")
    outside = add_depot(world.portfolio, cash_name: "Fox Out Cash", depot_name: "Fox Out Depot")
    outside_world = %{portfolio: world.portfolio, depot: outside.depot, cash: outside.cash}
    fox = security!(%{name: "Fox Split Holder", asset_class: "equity"})
    deposit!(world, "1000", ~D[2026-11-01])
    deposit!(outside_world, "1000", ~D[2026-11-01])
    buy!(world, fox, quantity: "2", price: "30", date: ~D[2026-11-02])
    buy!(outside_world, fox, quantity: "3", price: "30", date: ~D[2026-11-02])
    put_quotes!(fox, [{~D[2026-11-06], "30"}, {~D[2026-11-12], "33"}])
    sell!(world, fox, quantity: "2", price: "31", date: ~D[2026-11-10])

    today = ~D[2026-11-12]
    read = read!(view.id, "week", today: today)
    assert read.price_return.answered == 0
    assert [sold] = read.contribution.highest
    assert sold.held_at_end == false
    # 0 - 2 x 30 - (0 - 62) = 2.
    assert_decimal(sold.contribution, "2")

    everything = read!(nil, "week", today: today)
    assert [held] = everything.price_return.highest
    assert_decimal(held.return, "0.1")
    # 3 x 33 - 5 x 30 - (-62) = 11.
    assert_decimal(hd(everything.contribution.highest).contribution, "11")
  end

  # -- ties ----------------------------------------------------------------------

  # Attack: equal figures of different Decimal representations (0.1 from
  # 110/100 and from 55/50), a non-ASCII name in two cases, and the ISIN after
  # the case-folded name.
  test "ties across representations and a non-ASCII case fold" do
    {world, view} = world!("Tie")

    specs = [
      {"yew", %{name: "Yew Fund"}, "50", "55"},
      {"ash", %{name: "Ash Fund"}, "100", "110"},
      {"upper", %{name: "ÄPFEL FONDS", isin: "XS0000000025"}, "20", "22"},
      {"lower", %{name: "äpfel fonds", isin: "XS0000000017"}, "10", "11"}
    ]

    by_key =
      Map.new(specs, fn {key, attrs, start, finish} ->
        security = security!(attrs)
        deliver_untraded!(world, security, "1", date: ~D[2026-11-02])
        put_quotes!(security, [{~D[2026-11-06], start}, {~D[2026-11-12], finish}])
        {key, security.id}
      end)

    read = read!(view.id, "week", today: ~D[2026-11-12])
    price = read.price_return
    for row <- all_entries(price), do: assert_decimal(row.return, "0.1")

    # Case-folded: "ash fund" < "yew fund" < "äpfel fonds" by code point, and
    # the two äpfel by ISIN.
    expected = Enum.map(~w(ash yew lower upper), &Map.fetch!(by_key, &1))
    assert ids(price.highest) == Enum.take(expected, 2)
    assert ids(price.lowest) == Enum.drop(expected, 2)
  end

  # Attack: two securities equal on every key and figure. They are told apart
  # only by creation time; with n = 2 one stands in each half. Each moves 10
  # -> 11, so the money side ranks them too (a contribution of exactly 0
  # would stand in neither half, board 04 ②).
  test "twins equal on every key: creation order, one per half" do
    {world, view} = world!("Twin")

    [first, second] =
      for _index <- 1..2 do
        security = security!(%{name: "Twin Fund"})
        deliver_untraded!(world, security, "1", date: ~D[2026-11-02])
        put_quotes!(security, [{~D[2026-11-06], "10"}, {~D[2026-11-12], "11"}])
        security
      end

    for _round <- 1..3 do
      read = read!(view.id, "week", today: ~D[2026-11-12])
      assert ids(read.price_return.highest) == [first.id]
      assert ids(read.price_return.lowest) == [second.id]
      assert ids(read.contribution.highest) == [first.id]
      assert ids(read.contribution.lowest) == [second.id]
    end
  end

  # -- the halves -------------------------------------------------------------------

  defp halves_view(moves) do
    {world, view} = world!("Halves #{length(moves)}")

    for {move, index} <- Enum.with_index(moves) do
      fund = security!(%{name: "H#{String.pad_leading(Integer.to_string(index), 2, "0")}"})
      deliver_untraded!(world, fund, "1", date: ~D[2026-11-02])

      put_quotes!(fund, [{~D[2026-11-06], "100"}, {~D[2026-11-12], Integer.to_string(100 + move)}])
    end

    view
  end

  # Attack: n = 10 and limits 5, 3 and 1; n = 2 and 3. The halves never share a
  # security and take min(k, ceil(n/2)) and min(k, floor(n/2)). H08 ends
  # where it started: its price return of 0 is ranked, its contribution of 0
  # is counted (board 04 ②), so the money side's n is 9.
  test "the halves for n = 10, 3 and 2 under limits 5, 3 and 1" do
    today = ~D[2026-11-12]
    ten = halves_view([4, -4, 3, -3, 2, -2, 1, -1, 0, 5])

    for {limit, high, low, money_low} <- [{5, 5, 5, 4}, {3, 3, 3, 3}, {1, 1, 1, 1}, {50, 5, 5, 4}] do
      read = read!(ten.id, "week", today: today, limit: limit)
      assert {length(read.price_return.highest), length(read.price_return.lowest)} == {high, low}

      assert {length(read.contribution.highest), length(read.contribution.lowest)} ==
               {high, money_low}

      assert read.contribution.unanswered.zero_contribution == 1
      for ranking <- [read.price_return, read.contribution], do: assert_disjoint(ranking)
    end

    k3 = read!(ten.id, "week", today: today, limit: 3)
    assert names(k3.price_return.highest) == ["H09", "H00", "H02"]
    assert names(k3.price_return.lowest) == ["H01", "H03", "H05"]

    three = halves_view([1, 0, -1])
    read = read!(three.id, "week", today: today, limit: 1)
    assert names(read.price_return.highest) == ["H00"]
    assert names(read.price_return.lowest) == ["H02"]

    two = halves_view([0, 0])
    read = read!(two.id, "week", today: today)
    assert names(read.price_return.highest) == ["H00"]
    assert names(read.price_return.lowest) == ["H01"]
  end

  # -- zero ------------------------------------------------------------------------

  # Attack: an exactly-zero return is a figure and ranked, never a negative
  # zero. A contribution of exactly 0 stands in neither half and is counted
  # zero_contribution, whatever its scale or sign ("0.00", "-0"): board 04
  # ② keeps unpriced funds out of the lowest half (ADR-0061's amendment of
  # 2026-11-19, third precision; Sprint 30 closing act, design critic,
  # finding 4).
  test "an exact zero return is ranked, a zero contribution counted" do
    {world, view} = world!("Zero")
    flat = security!(%{name: "Flat Fund"})
    trip = security!(%{name: "Trip Fund"})
    deposit!(world, "1000", ~D[2026-11-01])
    buy!(world, flat, quantity: "3", price: "10", date: ~D[2026-11-02])
    put_quotes!(flat, [{~D[2026-11-06], "10.00"}, {~D[2026-11-12], "10"}])
    put_quotes!(trip, [{~D[2026-11-06], "7"}, {~D[2026-11-12], "7"}])
    # Bought and sold at one price inside the window: a money result of 0.
    buy!(world, trip, quantity: "2", price: "7", date: ~D[2026-11-09])
    sell!(world, trip, quantity: "2", price: "7", date: ~D[2026-11-10])

    read = read!(view.id, "week", today: ~D[2026-11-12], include_unanswered: true)
    [row] = read.price_return.highest
    assert_decimal(row.return, "0")
    refute String.starts_with?(Decimal.to_string(row.return), "-")

    # Flat 30 -> 30 and Trip 14 - 14 = 0: both counted, neither ranked.
    money = read.contribution
    assert money.answered == 0
    assert {money.highest, money.lowest} == {[], []}
    assert money.unanswered == %{no_valuation: 0, zero_contribution: 2}

    assert Enum.map(money.unanswered_entries, &{&1.security.name, &1.reason}) == [
             {"Flat Fund", "zero_contribution"},
             {"Trip Fund", "zero_contribution"}
           ]
  end

  # -- FX -------------------------------------------------------------------------

  # Attack: a GBP security whose first stored rate is after the week's start
  # close: no_fx_rate on the week, a figure on day (both closes after the
  # first rate), each at its own date's rate.
  test "a missing rate on the start end: no_fx_rate on the week, a figure on day" do
    {world, view} = world!("Gilt")
    gilt = security!(%{name: "Gilt Fund", currency_code: "GBP"})
    deliver_untraded!(world, gilt, "1", date: ~D[2026-11-02])
    put_quotes!(gilt, [{~D[2026-11-06], "50"}, {~D[2026-11-10], "52"}, {~D[2026-11-12], "53"}])
    rate!("GBP", ~D[2026-11-09], "0.85")
    rate!("GBP", ~D[2026-11-11], "0.86")

    today = ~D[2026-11-12]
    week = read!(view.id, "week", today: today, include_unanswered: true)
    assert week.price_return.answered == 0
    assert week.price_return.unanswered.no_fx_rate == 1
    assert [%{reason: "no_fx_rate"}] = week.price_return.unanswered_entries

    # (53 x 0.85) / (52 x 0.86) - 1 at 34 digits.
    day = read!(view.id, "day", today: today)
    [row] = day.price_return.highest
    assert {row.start.date, row.end.date} == {~D[2026-11-10], ~D[2026-11-12]}
    assert_exact(row.return, "0.007379248658318425760286225402504")

    # The money side keeps ADR-0051's figure for the same window: the row
    # and Wealth's table agree term for term.
    [money] = all_entries(week.contribution)
    table = wealth_row!(view.id, ~D[2026-11-09], today, today, gilt)
    assert Decimal.equal?(money.contribution, table.contribution)
    assert money.unvalued_days == table.unvalued_days
  end

  # -- the benchmark flag ------------------------------------------------------------

  # Attack: a flagged benchmark the scope holds is ranked like any position
  # (ADR-0061 §2), on both sides.
  test "a held benchmark is ranked on both sides" do
    {world, view} = world!("Bench")

    {:ok, index} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Index Tracker",
        currency_code: "EUR",
        asset_class: "fund"
      })

    {:ok, index} = Catalog.update_security(Actor.owner_ui(), index, %{is_benchmark: true})
    assert index.is_benchmark
    deposit!(world, "1000", ~D[2026-11-01])
    buy!(world, index, quantity: "2", price: "100", date: ~D[2026-11-02])
    put_quotes!(index, [{~D[2026-11-06], "100"}, {~D[2026-11-12], "103"}])

    read = read!(view.id, "week", today: ~D[2026-11-12])
    assert [row] = read.price_return.highest
    assert row.security.id == index.id
    assert_decimal(row.return, "0.03")
    assert [money] = read.contribution.highest
    assert_decimal(money.contribution, "6")
  end

  # -- all unanswered -----------------------------------------------------------------

  # Attack: a view whose holdings are all without a figure: empty halves on
  # both sides, every one counted, on every window.
  test "a view whose holdings are all unanswered" do
    {world, view} = world!("Dark")
    a = security!(%{name: "Dark A"})
    b = security!(%{name: "Dark B"})
    for s <- [a, b], do: deliver_untraded!(world, s, "1", date: ~D[2026-11-02])

    for window <- Movers.windows() do
      read = read!(view.id, window, today: ~D[2026-11-12], include_unanswered: true)

      for ranking <- [read.price_return, read.contribution] do
        assert {ranking.highest, ranking.lowest, ranking.answered} == {[], [], 0}, window
      end

      assert read.price_return.unanswered |> Map.values() |> Enum.sum() == 2
      assert length(read.price_return.unanswered_entries) == 2

      if window == "day" do
        assert {read.contribution.from, read.contribution.to} == {nil, nil}
        assert read.price_return.unanswered.no_close_at_end == 2
        assert read.contribution.computation_basis.gaps =~ "no day D"
      else
        assert read.contribution.unanswered == %{no_valuation: 2, zero_contribution: 0}
        assert names(read.contribution.unanswered_entries) == ["Dark A", "Dark B"]
      end
    end
  end

  # -- the as-of day on a weekend and on 1 January -------------------------------------

  # Attack: T a Saturday, a Sunday and 1 January (a holiday without closes):
  # the start days, the money windows, and the year to date on its first day.
  test "a Saturday, a Sunday and 1 January as the as-of day" do
    {world, view} = world!("Kilo")
    kilo = security!(%{name: "Kilo Share", asset_class: "equity"})
    deposit!(world, "1000", ~D[2025-11-01])
    buy!(world, kilo, quantity: "1", price: "95", date: ~D[2025-11-03])

    put_quotes!(kilo, [
      {~D[2026-11-06], "96"},
      {~D[2026-11-13], "98"},
      {~D[2025-12-24], "100"},
      {~D[2025-12-30], "104"},
      {~D[2025-12-31], "105"}
    ])

    for saturday_or_sunday <- [~D[2026-11-14], ~D[2026-11-15]] do
      week = read!(view.id, "week", today: saturday_or_sunday)
      assert week.start_on == ~D[2026-11-08]

      assert {week.contribution.from, week.contribution.to} ==
               {~D[2026-11-09], saturday_or_sunday}

      [row] = week.price_return.highest
      assert {row.start.date, row.end.date} == {~D[2026-11-06], ~D[2026-11-13]}
      # 98 / 96 - 1 = 1/48 at 34 digits; money 98 - 96 = 2.
      assert_exact(row.return, "0.020833333333333333333333333333333")
      assert_decimal(hd(week.contribution.highest).contribution, "2")
    end

    new_year = ~D[2026-01-01]

    # ytd, month and quarter on 1 January: S = 31 December, one day; the
    # holiday has no close, so the end close is 31 December's too: a price
    # return of 0, ranked; a contribution of 0, counted (board 04 ②).
    for window <- ~w(ytd month quarter) do
      read = read!(view.id, window, today: new_year)
      assert read.start_on == ~D[2025-12-31]
      assert {read.contribution.from, read.contribution.to} == {new_year, new_year}
      [row] = read.price_return.highest
      assert {row.start.date, row.end.date} == {~D[2025-12-31], ~D[2025-12-31]}
      assert_decimal(row.return, "0")
      assert read.contribution.answered == 0
      assert read.contribution.unanswered == %{no_valuation: 0, zero_contribution: 1}
    end

    # The week of Thursday 1 January 2026 starts on Sunday 28 December: 105 /
    # 100 - 1 = 0.05, money 5.
    week = read!(view.id, "week", today: new_year)
    assert week.start_on == ~D[2025-12-28]
    assert_decimal(hd(week.price_return.highest).return, "0.05")
    assert_decimal(hd(week.contribution.highest).contribution, "5")

    # Day: 31 December against 30 December, 105 / 104 - 1 at 34 digits; D is
    # 31 December, money 1.
    day = read!(view.id, "day", today: new_year)
    [row] = day.price_return.highest
    assert {row.start.date, row.end.date} == {~D[2025-12-30], ~D[2025-12-31]}
    assert_exact(row.return, "0.009615384615384615384615384615385")
    assert {day.contribution.from, day.contribution.to} == {~D[2025-12-31], ~D[2025-12-31]}
    assert_decimal(hd(day.contribution.highest).contribution, "1")
  end

  # -- day's closes ---------------------------------------------------------------------

  # Attack: day when the last two closes are eight days apart (P has no age
  # limit), day when E itself is eight days old (no close stands for T), and
  # a legacy zero close on either end (never a price).
  test "day: closes a week apart, a stale E, and a legacy zero close" do
    {world, view} = world!("Lima")
    lima = security!(%{name: "Lima Gap"})
    mike = security!(%{name: "Mike Stale"})
    nova = security!(%{name: "Nova Zero Between"})
    oscar = security!(%{name: "Oscar Zero Last"})
    for s <- [lima, mike, nova, oscar], do: deliver_untraded!(world, s, "1", date: ~D[2026-10-20])

    put_quotes!(lima, [{~D[2026-11-01], "40"}, {~D[2026-11-09], "42"}])
    put_quotes!(mike, [{~D[2026-11-01], "10"}, {~D[2026-11-04], "11"}])
    put_quotes!(nova, [{~D[2026-11-10], "10"}, {~D[2026-11-12], "11"}])
    legacy_quote!(nova, ~D[2026-11-11], "0")
    put_quotes!(oscar, [{~D[2026-11-06], "8"}, {~D[2026-11-10], "10"}, {~D[2026-11-11], "12"}])
    legacy_quote!(oscar, ~D[2026-11-12], "0")

    today = ~D[2026-11-12]
    day = read!(view.id, "day", today: today, include_unanswered: true)
    price = day.price_return

    # Oscar 12 / 10 - 1 = 0.2 (E skips the zero on the 12th); Nova 11 / 10 - 1
    # = 0.1 (P skips the zero on the 11th); Lima 42 / 40 - 1 = 0.05 with P
    # eight days before E.
    assert names(price.highest) == ["Oscar Zero Last", "Nova Zero Between"]
    assert names(price.lowest) == ["Lima Gap"]
    assert_decimal(entry(price.highest, oscar).return, "0.2")
    assert entry(price.highest, oscar).end.date == ~D[2026-11-11]
    assert_decimal(entry(price.highest, nova).return, "0.1")
    assert entry(price.highest, nova).start.date == ~D[2026-11-10]
    lima_row = entry(price.lowest, lima)
    assert_decimal(lima_row.return, "0.05")
    assert {lima_row.start.date, lima_row.end.date} == {~D[2026-11-01], ~D[2026-11-09]}
    assert price.unanswered.no_close_at_end == 1
    assert [%{reason: "no_close_at_end"}] = price.unanswered_entries

    # Money: D is the 12th (Nova's positive close), never a zero-close day of
    # its own.
    assert {day.contribution.from, day.contribution.to} == {today, today}

    # Oscar alone: its zero on the 12th is no close, so D is the 11th.
    {oscar_world, oscar_view} = world!("Oscar")
    deliver_untraded!(oscar_world, oscar, "1", date: ~D[2026-10-20])
    alone = read!(oscar_view.id, "day", today: today)
    assert {alone.contribution.from, alone.contribution.to} == {~D[2026-11-11], ~D[2026-11-11]}

    # Week: Oscar's end close stands on the 11th, 12 / 8 - 1 = 0.5.
    week = read!(oscar_view.id, "week", today: today)
    assert_decimal(hd(week.price_return.highest).return, "0.5")
  end

  # Attack (S3, beside #1472): the money side's D had no age bound, so with
  # only a three-month-old close stored the price side said no_close_at_end
  # while the money side showed that old day's move. ADR-0061's amendment of
  # 2026-11-19 bounds D by E's 7 days.
  #
  # Independent figures: the edge's E and P are 12 and 10, 12 / 10 - 1 =
  # 0.2; its money on D = 5 November is 2 x (12 - 10) = 4 (Python decimal,
  # 34 digits).
  test "day: D is no older than the 7 days E may be" do
    today = ~D[2026-11-12]

    {old_world, old_view} = world!("Old")
    old = security!(%{name: "Old Close"})
    deliver_untraded!(old_world, old, "2", date: ~D[2026-07-01])
    put_quotes!(old, [{~D[2026-08-10], "10"}, {~D[2026-08-12], "12"}])

    stale = read!(old_view.id, "day", today: today)
    assert stale.price_return.unanswered.no_close_at_end == 1
    money = stale.contribution
    assert {money.from, money.to} == {nil, nil}
    assert {money.highest, money.lowest, money.answered} == {[], [], 0}
    assert money.computation_basis.window.day_on == nil
    assert money.computation_basis.gaps =~ "within 7 calendar days"

    # The edge: a close exactly 7 days before T is D, as it is E.
    {edge_world, edge_view} = world!("Edge")
    edge = security!(%{name: "Edge Close"})
    deliver_untraded!(edge_world, edge, "2", date: ~D[2026-10-01])
    put_quotes!(edge, [{~D[2026-11-04], "10"}, {~D[2026-11-05], "12"}])

    at_edge = read!(edge_view.id, "day", today: today)
    assert_decimal(hd(at_edge.price_return.highest).return, "0.2")

    assert {at_edge.contribution.from, at_edge.contribution.to} ==
             {~D[2026-11-05], ~D[2026-11-05]}

    assert_decimal(hd(at_edge.contribution.highest).contribution, "4")

    # One day further, the same closes stand for nothing on either side.
    past_edge = read!(edge_view.id, "day", today: Date.add(today, 1))
    assert past_edge.price_return.unanswered.no_close_at_end == 1
    assert {past_edge.contribution.from, past_edge.contribution.to} == {nil, nil}
  end

  # -- an unvalued baseline day (#1472) -------------------------------------------------

  # Attack (#1472): a position held over the whole window whose first close,
  # or first rate, arrives on the window's first day S + 1. The baseline day
  # S counts zero for missing data (ADR-0051 §10), so the position's whole
  # value reads as its contribution; while §10 counted window days only,
  # `unvalued_days` stayed 0 and the phantom gain stood unmarked at the top
  # of the money ranking, where ADR-0061 §4 ranks it only marked. ADR-0051's
  # amendment of 2026-11-19 counts the baseline day: the row is marked, and
  # the figure stays in the sum.
  #
  # Independent figures (Python decimal, 34 digits): First Monday's real
  # move is 3 x (21 - 20) = 3; the read reports 3 x 21 - 0 = 63. Gilt (GBP,
  # first rate on 9 November) reads 53 / 0.86 =
  # 61.62790697674418604651162790697674 by one division; the walk multiplies
  # by the rate's reciprocal, 53 x (1 / 0.86) =
  # 61.62790697674418604651162790697672. On day, 9 November, First Monday's
  # first-ever close reads 3 x 20 = 60, and Gilt 50 x (1 / 0.86) =
  # 58.13953488372093023255813953488370.
  test "a position unvalued only on the baseline day is ranked marked, its figure kept" do
    {world, view} = world!("Baseline")

    first = security!(%{name: "First Monday"})
    deliver_untraded!(world, first, "3", date: ~D[2026-11-02])
    put_quotes!(first, [{~D[2026-11-09], "20"}, {~D[2026-11-12], "21"}])

    gilt = security!(%{name: "Gilt Fund", currency_code: "GBP"})
    deliver_untraded!(world, gilt, "1", date: ~D[2026-11-02])
    put_quotes!(gilt, [{~D[2026-11-06], "50"}, {~D[2026-11-12], "53"}])
    rate!("GBP", ~D[2026-11-09], "0.86")

    today = ~D[2026-11-12]
    money = read!(view.id, "week", today: today).contribution
    assert {money.from, money.to} == {~D[2026-11-09], today}
    assert money.answered == 2 and money.unanswered == %{no_valuation: 0, zero_contribution: 0}

    assert [%{security: %{id: first_id}} = first_row] = money.highest
    assert first_id == first.id
    assert_decimal(first_row.contribution, "63")
    assert_decimal(first_row.start_value, "0")
    assert_decimal(first_row.end_value, "63")
    assert first_row.held_at_start and first_row.held_at_end

    assert {first_row.unvalued_days, first_row.unvalued_reason, first_row.valued_days} ==
             {1, :no_price, 4}

    assert [%{security: %{id: gilt_id}} = gilt_row] = money.lowest
    assert gilt_id == gilt.id
    assert_exact(gilt_row.contribution, "61.62790697674418604651162790697672")
    assert_decimal(gilt_row.start_value, "0")

    assert {gilt_row.unvalued_days, gilt_row.unvalued_reason, gilt_row.valued_days} ==
             {1, :no_rate, 4}

    # Wealth's table for the same window reads the same rows.
    for {security, row} <- [{first, first_row}, {gilt, gilt_row}] do
      wealth = wealth_row!(view.id, ~D[2026-11-09], today, today, security)
      assert Decimal.equal?(wealth.contribution, row.contribution)
      assert {wealth.unvalued_days, wealth.unvalued_reason} == {1, row.unvalued_reason}
    end

    # Day, 9 November: D is First Monday's first-ever close day; its
    # baseline, the 8th, had no close (First Monday) and no rate (Gilt).
    day = read!(view.id, "day", today: ~D[2026-11-09]).contribution
    assert {day.from, day.to} == {~D[2026-11-09], ~D[2026-11-09]}
    assert [%{security: %{id: ^first_id}} = first_day] = day.highest
    assert [%{security: %{id: ^gilt_id}} = gilt_day] = day.lowest
    assert_decimal(first_day.contribution, "60")
    assert_exact(gilt_day.contribution, "58.13953488372093023255813953488370")

    assert {first_day.unvalued_days, first_day.unvalued_reason, first_day.valued_days} ==
             {1, :no_price, 1}

    assert {gilt_day.unvalued_days, gilt_day.unvalued_reason, gilt_day.valued_days} ==
             {1, :no_rate, 1}
  end

  # -- a merged-away security ---------------------------------------------------------

  # Attack: a security merged into another is ranked under the survivor only,
  # once, with the merged quantity.
  test "a merged-away security is ranked only as its survivor" do
    {world, view} = world!("Merge")
    source = security!(%{name: "Merge Source", isin: "XS0000000033"})
    target = security!(%{name: "Merge Target"})
    deposit!(world, "1000", ~D[2026-10-01])
    buy!(world, source, quantity: "3", price: "25", date: ~D[2026-10-02])
    buy!(world, target, quantity: "2", price: "25", date: ~D[2026-10-02])
    put_quotes!(target, [{~D[2026-11-06], "25"}, {~D[2026-11-12], "26"}])

    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    {:ok, _record, :applied} =
      Lifecycle.merge_security(Actor.owner_ui(), source.id, target.id, %{
        plan_digest: preview.plan_digest,
        identity_choice: "adopt_source_isin"
      })

    read = read!(view.id, "week", today: ~D[2026-11-12], include_unanswered: true)
    # 26 / 25 - 1 = 0.04; 5 x 1 = 5.
    assert ids(all_entries(read.price_return)) == [target.id]
    assert_decimal(hd(read.price_return.highest).return, "0.04")
    assert ids(all_entries(read.contribution)) == [target.id]
    assert_decimal(hd(read.contribution.highest).contribution, "5")
    refute source.id in ids(read.price_return.unanswered_entries)
    refute source.id in ids(read.contribution.unanswered_entries)
  end

  # -- the basis and no verdict ------------------------------------------------------------

  defp keys(map) when is_map(map) and not is_struct(map),
    do: Enum.flat_map(map, fn {key, value} -> [key | keys(value)] end)

  defp keys(list) when is_list(list), do: Enum.flat_map(list, &keys/1)
  defp keys(_value), do: []

  # Attack: the basis states each window's actual dates and rule, and the
  # payload, its unanswered entries and its embedded table basis included,
  # carries no forbidden word in any key, on every window, view and
  # everything.
  test "the basis states the dates the rows stand on, and no key rates" do
    {world, view} = world!("Basis")
    fund = security!(%{name: "Basis Fund"})
    dark = security!(%{name: "Basis Dark"})
    deposit!(world, "500", ~D[2026-11-01])
    buy!(world, fund, quantity: "1", price: "100", date: ~D[2026-11-02])
    deliver_untraded!(world, dark, "1", date: ~D[2026-11-02])
    put_quotes!(fund, [{~D[2026-09-30], "90"}, {~D[2026-11-06], "100"}, {~D[2026-11-12], "101"}])
    today = ~D[2026-11-12]

    for scope <- [view.id, nil], window <- Movers.windows() do
      read = read!(scope, window, today: today, include_unanswered: true)
      price_basis = read.price_return.computation_basis
      money_basis = read.contribution.computation_basis

      assert price_basis.window.start_on == read.start_on
      assert money_basis.window.from == read.contribution.from
      assert money_basis.window.to == read.contribution.to
      assert price_basis.scope.view_id == scope
      assert money_basis.scope.view_id == scope
      assert price_basis.gaps =~ "no_fx_rate"
      assert money_basis.gaps =~ "no_valuation"
      assert price_basis.halves =~ "min(5, ceil(n / 2))"

      if window == "day" do
        assert price_basis.gaps =~ "one_close_only"
        assert money_basis.window.day_on == read.contribution.from
      else
        refute price_basis.gaps =~ "one_close_only"
        assert Date.add(read.start_on, 1) == read.contribution.from
      end

      offenders =
        read
        |> keys()
        |> Enum.filter(fn key ->
          downcased = String.downcase(to_string(key))
          Enum.any?(@forbidden, &String.contains?(downcased, &1))
        end)

      assert offenders == [], "#{window}: #{inspect(offenders)}"
    end
  end

  # -- the price side is WindowReturn's on every window ---------------------------------

  # Attack: for every window but day, each row equals WindowReturn over
  # (start_on, end_on) to the last digit, so the read cannot drift from sale
  # hindsight and the crash rankings.
  test "every window's price row is WindowReturn's over (S, T)" do
    {world, view} = world!("Agree")
    rate!("USD", ~D[2025-01-01], "1.05")
    rate!("USD", ~D[2026-06-30], "1.13")
    rate!("USD", ~D[2026-11-09], "1.1587")
    usd = security!(%{name: "Agree Dollar", currency_code: "USD"})
    eur = security!(%{name: "Agree Euro"})
    for s <- [usd, eur], do: deliver_untraded!(world, s, "1", date: ~D[2025-06-01])

    points = [
      {~D[2025-11-19], "70"},
      {~D[2025-12-31], "71.5"},
      {~D[2026-09-30], "80.25"},
      {~D[2026-10-30], "81"},
      {~D[2026-11-13], "83.3"},
      {~D[2026-11-18], "84.7"},
      {~D[2026-11-19], "85.1"}
    ]

    put_quotes!(usd, points)
    put_quotes!(eur, Enum.map(points, fn {date, close} -> {date, Decimal.mult(d(close), 2)} end))
    today = ~D[2026-11-19]

    for window <- ~w(week month quarter ytd 1y) do
      read = read!(view.id, window, today: today)

      for security <- [usd, eur] do
        row = entry(all_entries(read.price_return), security)
        {:ok, direct} = WindowReturn.price_return(security, read.start_on, today)
        assert row.return == direct.return, "#{window} #{security.name}"
      end
    end
  end

  # -- performance --------------------------------------------------------------------

  # Attack: a view of 50 securities with a year of weekday closes each; every
  # window read is timed. Reported, with a generous bound so a pathological
  # read (a query per day per security) fails.
  @tag timeout: 600_000
  test "fifty securities and a year of closes: each window reads in bounded time" do
    {world, view} = world!("Fifty")
    deposit!(world, "100000", ~D[2025-10-01])
    first = ~D[2025-11-03]

    days =
      for offset <- 0..381, date = Date.add(first, offset), Date.day_of_week(date) <= 5, do: date

    for index <- 1..50 do
      security =
        security!(%{name: "Perf #{String.pad_leading(Integer.to_string(index), 2, "0")}"})

      buy!(world, security, quantity: "10", price: "100", date: ~D[2025-10-02])

      rows =
        days
        |> Enum.with_index()
        |> Enum.map(fn {date, n} ->
          %{date: date, close: d(100 + rem(n * index, 37)), source: "manual"}
        end)

      {:ok, _quotes} = Catalog.Quotes.upsert_many(security.id, rows)
    end

    today = ~D[2026-11-19]

    timings =
      for window <- Movers.windows() do
        {micros, {:ok, read}} = :timer.tc(fn -> Movers.read(view.id, window, today: today) end)
        assert read.price_return.answered == 50
        {window, div(micros, 1000)}
      end

    for {window, ms} <- timings, do: assert(ms < 30_000, "#{window}: #{ms} ms")
  end
end
