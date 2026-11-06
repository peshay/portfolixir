defmodule Portfolixir.Portfolios.Performance.SaleReinvestmentTest do
  # Sprint 26 Lane R, R1 (ADR-0057 §§1-3; I18 mode 3): what a switch cost.
  # A sale's proceeds go into the buys booked from the same cash account
  # within 30 days, by a fixed rule; per span the kept side stands beside
  # the switched side. Risk tier (ADR-0036; the plan's D-8.1): every figure
  # below is an exact Decimal derived by hand in the comments, at Decimal's
  # default context (34 significant digits, half-up), and the rates are
  # chosen so that each EUR conversion (1 / the stored hub rate) is exact.
  # Every name and figure here is synthetic.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [
      add_depot: 2,
      base_world: 1,
      buy!: 3,
      create_security!: 1,
      put_quotes!: 2,
      sell!: 3
    ]

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.Performance.SaleReinvestment

  @today ~D[2026-03-10]

  defp d(value), do: Decimal.new(value)

  defp assert_decimal(actual, expected) do
    assert %Decimal{} = actual
    assert Decimal.equal?(actual, d(expected)), "expected #{expected}, got #{inspect(actual)}"
  end

  defp block(sale, today \\ @today),
    do: Map.fetch!(SaleReinvestment.blocks([sale], today), sale.id)

  # A EUR-hub rate: `rate` units of USD per 1 EUR from `date` on.
  defp rate!(date, rate) do
    {:ok, 1} =
      Fx.upsert_many([
        %{base_currency: "EUR", quote_currency: "USD", date: date, rate: rate, source: "manual"}
      ])
  end

  defp security!(ticker, currency \\ "EUR"),
    do: create_security!(name: "Synthetic #{ticker}", ticker: ticker, currency: currency)

  # User story (R1, ADR-0057 §1: the purchases are found by rule):
  # As the operator asking whether a switch was worth it,
  # I want the buys a sale's money went into found by a fixed rule,
  # so that nobody chooses the flattering buy after seeing the outcome.
  #
  # Acceptance criteria:
  # - The proceeds are the sale's booked cash amount on its cash account.
  # - A buy from the same cash account within 30 days takes from them, at
  #   most its own cash debit; the block names the buy, its date, its
  #   security, the amount taken and the share of the buy.
  # - share_of_proceeds_matched (the ADR's `a`) is the sum taken over the
  #   proceeds; unallocated is the rest; days_to_first_buy counts calendar
  #   days from the sale to its first matched buy.
  test "one sale and one buy: the buy takes the proceeds" do
    world = base_world(name: "Switch One")
    sold = security!("SW1")
    bought = security!("BY1")

    # Proceeds: 10 x 100 = 1000 EUR. The buy's debit: 5 x 200 = 1000 EUR.
    sale = sell!(world, sold, quantity: "10", price: "100", date: ~D[2025-01-15])
    buy = buy!(world, bought, quantity: "5", price: "200", date: ~D[2025-01-20])

    block = block(sale)

    assert block.status == :matched
    assert block.reason == nil
    assert block.currency_code == "EUR"
    assert_decimal(block.proceeds, "1000")

    assert [taken] = block.buys
    assert taken.buy_id == buy.id
    assert taken.date == ~D[2025-01-20]
    assert taken.security.id == bought.id
    assert_decimal(taken.amount_taken, "1000")
    assert_decimal(taken.cash_debit, "1000")
    # 1000 / 1000 = 1
    assert_decimal(taken.share_of_buy, "1")

    # a = 1000 / 1000 = 1, nothing left over, 2025-01-15 -> 2025-01-20.
    assert_decimal(block.share_of_proceeds_matched, "1")
    assert_decimal(block.unallocated, "0")
    assert block.days_to_first_buy == 5
  end

  # User story (R1, ADR-0057 §1.3: a buy takes at most its own debit):
  # As the operator who topped a purchase up with other money,
  # I want a buy larger than the proceeds funded by them only in part,
  # so that only the part the sale paid for is compared.
  #
  # Acceptance criteria:
  # - The buy takes the whole proceeds; its share is the proceeds over its
  #   debit.
  test "a buy larger than the proceeds is funded in part" do
    world = base_world(name: "Switch Part")
    sold = security!("SWP")
    bought = security!("BYP")

    # Proceeds 10 x 100 = 1000; debit 8 x 200 = 1600.
    sale = sell!(world, sold, quantity: "10", price: "100", date: ~D[2025-01-15])
    buy!(world, bought, quantity: "8", price: "200", date: ~D[2025-01-20])

    block = block(sale)

    assert [taken] = block.buys
    assert_decimal(taken.amount_taken, "1000")
    assert_decimal(taken.cash_debit, "1600")
    # 1000 / 1600 = 0.625
    assert_decimal(taken.share_of_buy, "0.625")
    assert_decimal(block.share_of_proceeds_matched, "1")
    assert_decimal(block.unallocated, "0")
  end

  # User story (R1, ADR-0057 §1.3: the order):
  # As the operator who sold twice before one purchase,
  # I want the oldest proceeds spent first, by sale date then booking id,
  # so that two sales never both claim the same money.
  #
  # Acceptance criteria:
  # - The earlier sale's proceeds are taken first, even when that sale was
  #   booked later (a higher id).
  # - A sale whose candidate buys were all funded by earlier proceeds reads
  #   no_match with proceeds_taken_by_earlier_sale.
  test "two sales compete for one buy: the oldest proceeds go first" do
    world = base_world(name: "Switch Queue")
    bought = security!("BYQ")

    # Booked in this order so that the later sale has the lower id.
    later = sell!(world, security!("SQ2"), quantity: "4", price: "100", date: ~D[2025-01-12])
    earlier = sell!(world, security!("SQ1"), quantity: "6", price: "100", date: ~D[2025-01-10])
    last = sell!(world, security!("SQ3"), quantity: "5", price: "100", date: ~D[2025-01-14])
    buy = buy!(world, bought, quantity: "10", price: "100", date: ~D[2025-01-15])
    assert later.id < earlier.id

    blocks = SaleReinvestment.blocks([later, earlier, last], @today)

    # The buy's debit is 10 x 100 = 1000: 600 from the sale of 2025-01-10,
    # then 400 from the sale of 2025-01-12, nothing left for 2025-01-14.
    first = Map.fetch!(blocks, earlier.id)
    assert [%{buy_id: buy_id} = taken] = first.buys
    assert buy_id == buy.id
    assert_decimal(taken.amount_taken, "600")
    # 600 / 1000 = 0.6
    assert_decimal(taken.share_of_buy, "0.6")
    assert_decimal(first.share_of_proceeds_matched, "1")

    second = Map.fetch!(blocks, later.id)
    assert [taken] = second.buys
    assert_decimal(taken.amount_taken, "400")
    assert_decimal(taken.share_of_buy, "0.4")
    # 400 / 400 = 1
    assert_decimal(second.share_of_proceeds_matched, "1")

    third = Map.fetch!(blocks, last.id)
    assert third.status == :no_match
    assert third.reason == :proceeds_taken_by_earlier_sale
    assert third.buys == []
    assert_decimal(third.proceeds, "500")
    assert_decimal(third.unallocated, "500")
  end

  # User story (R1, ADR-0057 §1.2: 30 calendar days, dates without times):
  # As the operator whose money waited before it was spent,
  # I want a buy counted up to day 30 after the sale and from the sale's own
  # day, and not on day 31,
  # so that money that waited is not money that switched.
  #
  # Acceptance criteria:
  # - A buy 30 days after the sale counts; one 31 days after does not, and
  #   the sale reads no_match with no_buy_within_30_days.
  # - A buy on the sale's own date counts, even one booked before the sale.
  test "the 30 days: day 30 and the sale's own date count, day 31 does not" do
    sale_on = ~D[2025-01-15]

    day_31 = base_world(name: "Switch Day 31")
    sale_31 = sell!(day_31, security!("S31"), quantity: "1", price: "100", date: sale_on)
    buy!(day_31, security!("B31"), quantity: "1", price: "100", date: ~D[2025-02-15])

    day_30 = base_world(name: "Switch Day 30")
    sale_30 = sell!(day_30, security!("S30"), quantity: "1", price: "100", date: sale_on)
    buy!(day_30, security!("B30"), quantity: "1", price: "100", date: ~D[2025-02-14])

    same_day = base_world(name: "Switch Day 0")
    early = buy!(same_day, security!("B00"), quantity: "1", price: "100", date: sale_on)
    sale_0 = sell!(same_day, security!("S00"), quantity: "1", price: "100", date: sale_on)
    assert early.id < sale_0.id

    blocks = SaleReinvestment.blocks([sale_31, sale_30, sale_0], @today)

    # 2025-01-15 + 31 = 2025-02-15.
    assert %{status: :no_match, reason: :no_buy_within_30_days, buys: []} =
             Map.fetch!(blocks, sale_31.id)

    # 2025-01-15 + 30 = 2025-02-14.
    assert %{status: :matched, days_to_first_buy: 30} = Map.fetch!(blocks, sale_30.id)

    assert %{status: :matched, days_to_first_buy: 0, buys: [%{buy_id: buy_id}]} =
             Map.fetch!(blocks, sale_0.id)

    assert buy_id == early.id
  end

  # User story (R1, ADR-0057 §1.2: the same cash account):
  # As the operator who pays from more than one account,
  # I want only the buys debiting the sale's own cash account matched,
  # so that the rule follows the money it can see and no other.
  #
  # Acceptance criteria:
  # - A buy from another cash account of the same portfolio is no
  #   candidate: the sale reads no_match, no_buy_within_30_days.
  test "a buy from another cash account is not matched" do
    world = base_world(name: "Switch Accounts")

    %{cash: other_cash, depot: other_depot} =
      add_depot(world.portfolio, cash_name: "Other Cash", depot_name: "Other Depot")

    other = %{world | cash: other_cash, depot: other_depot}

    sale = sell!(world, security!("SAC"), quantity: "1", price: "100", date: ~D[2025-01-15])
    buy!(other, security!("BAC"), quantity: "1", price: "100", date: ~D[2025-01-16])

    assert %{status: :no_match, reason: :no_buy_within_30_days} = block(sale)
  end

  # User story (R1, ADR-0057 §1.2: of any security other than the one sold):
  # As the operator who sold and bought back the same security,
  # I want that buy not counted as a switch,
  # so that a round trip is not read as a decision to switch.
  #
  # Acceptance criteria:
  # - A buy of the sold security is no candidate for that sale.
  test "a buy of the security that was sold is not a candidate" do
    world = base_world(name: "Switch Same")
    sold = security!("SSM")

    sale = sell!(world, sold, quantity: "1", price: "100", date: ~D[2025-01-15])
    buy!(world, sold, quantity: "1", price: "95", date: ~D[2025-01-16])

    assert %{status: :no_match, reason: :no_buy_within_30_days} = block(sale)
  end

  # User story (R1, ADR-0057 §4: an orphan sell with no settlement):
  # As the agent reading a sale that settled no cash,
  # I want it named no_match with no_cash_account,
  # so that a sale without proceeds is never compared.
  #
  # Acceptance criteria:
  # - A sale with no cash account reads no_match, no_cash_account, and no
  #   proceeds.
  # - A sale whose booked cash amount on its account is not positive (a
  #   write-off at price 0) reads the same.
  test "a sale without a settlement reads no_cash_account" do
    world = base_world(name: "Switch Orphan")
    write_off = sell!(world, security!("SWO"), quantity: "5", price: "0", date: ~D[2025-01-15])
    buy!(world, security!("BWO"), quantity: "1", price: "100", date: ~D[2025-01-16])

    # The ledger requires a cash account on a sell; a row read without one
    # (no settlement at all) is the same answer.
    orphan = %Transaction{
      id: -1,
      type: "sell",
      date: ~D[2025-01-15],
      quantity: d("1"),
      price: d("100"),
      fees: d("0"),
      taxes: d("0"),
      currency_code: "EUR",
      security_id: write_off.security_id,
      cash_account_id: nil
    }

    blocks = SaleReinvestment.blocks([write_off, orphan], @today)

    for id <- [write_off.id, orphan.id] do
      assert %{status: :no_match, reason: :no_cash_account, buys: [], proceeds: nil} =
               Map.fetch!(blocks, id)
    end
  end

  # User story (R1, ADR-0057 §1.4: what is left over):
  # As the operator who spent part of the money and kept the rest,
  # I want the part no buy took within 30 days named unallocated and kept out
  # of the comparison,
  # so that money that waited does not count as switched.
  #
  # Acceptance criteria:
  # - Two buys within 30 days take their debits; a third on day 36 takes
  #   nothing; unallocated is the rest, a the share taken, and
  #   days_to_first_buy the first matched buy's distance.
  test "unallocated after 30 days, the share a and the days to the first buy" do
    world = base_world(name: "Switch Rest")

    sale = sell!(world, security!("SRS"), quantity: "10", price: "100", date: ~D[2025-01-15])
    # Debits 3 x 100 = 300 (day 5) and 2 x 100 = 200 (day 17); the buy of
    # 2025-02-20 (day 36) is outside the window.
    buy!(world, security!("BR1"), quantity: "3", price: "100", date: ~D[2025-01-20])
    buy!(world, security!("BR2"), quantity: "2", price: "100", date: ~D[2025-02-01])
    buy!(world, security!("BR3"), quantity: "4", price: "100", date: ~D[2025-02-20])

    block = block(sale)

    assert Enum.map(block.buys, & &1.date) == [~D[2025-01-20], ~D[2025-02-01]]
    # a = (300 + 200) / 1000 = 0.5; unallocated = 1000 - 500 = 500.
    assert_decimal(block.share_of_proceeds_matched, "0.5")
    assert_decimal(block.unallocated, "500")
    assert block.days_to_first_buy == 5
  end

  # User story (R1, ADR-0057 §1: the same ledger gives the same matches):
  # As the maintainer holding the rule,
  # I want two reads of one ledger to answer the same blocks,
  # so that the matches are a reading of the ledger and nothing else.
  #
  # Acceptance criteria:
  # - Two calls in a row return equal blocks.
  test "the same ledger gives the same matches twice in a row" do
    world = base_world(name: "Switch Twice")
    one = sell!(world, security!("ST1"), quantity: "3", price: "100", date: ~D[2025-01-15])
    two = sell!(world, security!("ST2"), quantity: "3", price: "100", date: ~D[2025-01-15])
    buy!(world, security!("BT1"), quantity: "4", price: "100", date: ~D[2025-01-16])
    buy!(world, security!("BT2"), quantity: "4", price: "100", date: ~D[2025-01-16])

    first = SaleReinvestment.blocks([one, two], @today)
    assert first == SaleReinvestment.blocks([one, two], @today)

    # one (the lower id) is spent first: 300 into the first buy; two gives
    # 100 to the first buy and 200 to the second.
    assert [%{amount_taken: taken}] = Map.fetch!(first, one.id).buys
    assert_decimal(taken, "300")

    assert [%{amount_taken: hundred}, %{amount_taken: two_hundred}] =
             Map.fetch!(first, two.id).buys

    assert_decimal(hundred, "100")
    assert_decimal(two_hundred, "200")
  end

  # User story (R1, ADR-0057 §2: the two sides, per span):
  # As the operator asking whether a switch was worth it,
  # I want, per FR-50 span, what the sold part would be worth had I kept it
  # beside what the bought positions are worth, and the difference,
  # so that I read what the money did where it went.
  #
  # Acceptance criteria:
  # - The spans are FR-50's: 1m, 3m, 12m and latest, with the same end
  #   dates as the sale's own row.
  # - kept = a x the sold quantity x the sold security's close at the end,
  #   in EUR; switched = the share of each buy this sale paid for x the
  #   buy's quantity x the bought security's close at the end, in EUR;
  #   difference = switched + taxes_apart - kept, before tax.
  # - A buy funded in part counts with its share only.
  test "one sale and one buy: kept, switched and the difference per span" do
    world = base_world(name: "Sides One")
    sold = security!("SD1")
    bought = security!("BD1")
    part = security!("BD2")

    put_quotes!(sold, [
      {~D[2025-01-15], "100"},
      {~D[2025-02-14], "110"},
      {~D[2025-04-15], "90"},
      {~D[2026-01-15], "130"},
      {~D[2026-03-02], "150"}
    ])

    put_quotes!(bought, [
      {~D[2025-02-14], "210"},
      {~D[2025-04-15], "240"},
      {~D[2026-01-15], "180"},
      {~D[2026-03-02], "260"}
    ])

    # Proceeds 10 x 100 = 1000; the buy's debit 5 x 200 = 1000: a = 1.
    sale = sell!(world, sold, quantity: "10", price: "100", date: ~D[2025-01-15])
    buy!(world, bought, quantity: "5", price: "200", date: ~D[2025-01-20])

    block = block(sale)
    assert Enum.map(block.spans, & &1.span) == ["1m", "3m", "12m", "latest"]

    # kept = 1 x 10 x the sold close; switched = (1000 / 1000) x 5 x the
    # bought close; difference = switched + 0 - kept:
    #   1m (2025-02-15, Friday's closes): 10 x 110 = 1100, 5 x 210 = 1050, -50
    #   3m (2025-04-15):                  10 x  90 =  900, 5 x 240 = 1200, 300
    #   12m (2026-01-15):                 10 x 130 = 1300, 5 x 180 =  900, -400
    #   latest (2026-03-02):              10 x 150 = 1500, 5 x 260 = 1300, -200
    expected = [
      {"1m", ~D[2025-02-15], "1100", "1050", "-50"},
      {"3m", ~D[2025-04-15], "900", "1200", "300"},
      {"12m", ~D[2026-01-15], "1300", "900", "-400"},
      {"latest", ~D[2026-03-02], "1500", "1300", "-200"}
    ]

    for {label, end_on, kept, switched, difference} <- expected do
      span = Enum.find(block.spans, &(&1.span == label))
      assert span.status == :complete, label
      assert span.end_on == end_on, label
      assert_decimal(span.kept, kept)
      assert_decimal(span.switched, switched)
      assert_decimal(span.difference, difference)
    end

    # The same sale funding part of a larger buy: proceeds 1000 of a debit
    # 8 x 200 = 1600, share 0.625, so 0.625 x 8 = 5 shares count:
    #   1m switched = 1000 x 8 x 210 / 1600 = 1050, as above.
    other = base_world(name: "Sides Part")
    put_quotes!(part, [{~D[2025-02-14], "210"}])
    part_sale = sell!(other, sold, quantity: "10", price: "100", date: ~D[2025-01-15])
    buy!(other, part, quantity: "8", price: "200", date: ~D[2025-01-20])

    one = Enum.find(block(part_sale).spans, &(&1.span == "1m"))
    assert_decimal(one.kept, "1100")
    assert_decimal(one.switched, "1050")
    assert_decimal(one.difference, "-50")
  end

  # User story (R1, ADR-0057 §2: before a buy the money waits as cash; D-8.3
  # every money identity at a moving rate):
  # As the operator holding in EUR who switched within a USD account,
  # I want both sides in EUR at the end's rates, and the money a later buy
  # took counted as cash in its account's currency until that buy,
  # so that a moving euro and the waiting both show.
  #
  # Acceptance criteria:
  # - The proceeds and the queue run in the cash account's currency (USD).
  # - Each close converts at its own date's stored rate; the cash of a buy
  #   dated after the span's end converts at the end's rate.
  test "a USD account at a moving rate, and a buy after a span's end held as cash" do
    world = base_world(name: "Sides Dollar", cash_currency: "USD")
    sold = security!("SDU", "USD")
    early = security!("BDU", "USD")
    late = security!("BLU", "USD")

    # EUR-hub rates: 1.25 USD per EUR on the sale day (1 USD = 0.8 EUR),
    # 1.6 on 2025-02-28 (1 USD = 0.625 EUR).
    rate!(~D[2025-01-31], "1.25")
    rate!(~D[2025-02-28], "1.6")

    put_quotes!(sold, [{~D[2025-01-31], "100"}, {~D[2025-02-28], "110"}])
    put_quotes!(early, [{~D[2025-02-28], "260"}])

    # The sale on Friday 2025-01-31: its 1m span ends on 2025-02-28 (28
    # days), so a buy on day 30 (2025-03-02) is after that span's end.
    # Proceeds 10 x 100 = 1000 USD; debits 2 x 200 = 400 USD (day 3) and
    # 3 x 200 = 600 USD (day 30): a = 1000 / 1000 = 1.
    sale =
      sell!(world, sold, quantity: "10", price: "100", date: ~D[2025-01-31], currency: "USD")

    buy!(world, early, quantity: "2", price: "200", date: ~D[2025-02-03], currency: "USD")
    buy!(world, late, quantity: "3", price: "200", date: ~D[2025-03-02], currency: "USD")

    block = block(sale)
    assert block.currency_code == "USD"
    assert_decimal(block.proceeds, "1000")
    assert block.days_to_first_buy == 3

    # 1m, at 0.625 EUR per USD (the rate of 2025-02-28, not the sale day's
    # 0.8):
    #   kept     = 1 x 10 x 110 x 0.625                    = 687.5
    #   switched = (400 / 400) x 2 x 260 x 0.625            = 325
    #            + 600 USD as cash x 0.625                  = 375
    #                                                       = 700
    #   difference = 700 - 687.5                            = 12.5
    one = Enum.find(block.spans, &(&1.span == "1m"))
    assert one.status == :complete
    assert one.end_on == ~D[2025-02-28]
    assert_decimal(one.kept, "687.5")
    assert_decimal(one.switched, "700")
    assert_decimal(one.difference, "12.5")
  end

  # User story (R1, ADR-0057 §2: pending and incomplete, as in FR-50):
  # As the agent reading a recent or a sparsely priced switch,
  # I want a span not yet reached named pending, and one that cannot be
  # measured named incomplete with the side and the reason,
  # so that no figure is estimated.
  #
  # Acceptance criteria:
  # - A span whose end is after today is pending, with no figure.
  # - Without a close of the sold security at the end: incomplete, side
  #   kept, no_end_close; without one of a bought security: side switched.
  test "a pending span, and incomplete spans with their side and reason" do
    world = base_world(name: "Sides Gaps")
    sold = security!("SDG")
    bought = security!("BDG")

    put_quotes!(sold, [{~D[2025-01-15], "100"}, {~D[2025-02-14], "110"}, {~D[2025-04-15], "90"}])
    put_quotes!(bought, [{~D[2025-02-14], "210"}])

    sale = sell!(world, sold, quantity: "10", price: "100", date: ~D[2025-01-15])
    buy!(world, bought, quantity: "5", price: "200", date: ~D[2025-01-20])

    # Today 2025-06-01: 1m and 3m have ended, 12m (2026-01-15) has not.
    spans = Map.new(block(sale, ~D[2025-06-01]).spans, &{&1.span, &1})

    assert %{status: :complete} = spans["1m"]

    # 3m: the sold security has a close (90), the bought one has none from
    # 2025-04-08 to 2025-04-15.
    assert %{status: :incomplete, side: :switched, reason: :no_end_close, kept: nil} =
             spans["3m"]

    assert %{status: :pending, reason: nil, kept: nil, switched: nil, difference: nil} =
             spans["12m"]

    # latest: the sold security's latest close, 2025-04-15, as the row's.
    assert spans["latest"].end_on == ~D[2025-04-15]
    assert spans["latest"].status == :incomplete

    # A sale whose sold security has no close at a span's end: side kept.
    gap = base_world(name: "Sides Kept Gap")
    unpriced = security!("SDN")
    put_quotes!(unpriced, [{~D[2025-01-15], "100"}])
    gap_sale = sell!(gap, unpriced, quantity: "1", price: "100", date: ~D[2025-01-15])
    buy!(gap, bought, quantity: "1", price: "100", date: ~D[2025-01-16])

    gap_spans = Map.new(block(gap_sale, ~D[2025-06-01]).spans, &{&1.span, &1})
    assert %{status: :incomplete, side: :kept, reason: :no_end_close} = gap_spans["1m"]
    # No close after the sale: the latest span has no end, as in FR-50.
    assert %{status: :incomplete, side: :kept, reason: :no_end_close, end_on: nil} =
             gap_spans["latest"]
  end

  # User story (R1, ADR-0057 §2: split-adjusted closes, ADR-0028):
  # As the operator whose sold or bought security split after the switch,
  # I want each quantity read in the closes' basis,
  # so that a split is not a move on either side.
  #
  # Acceptance criteria:
  # - A 2:1 split after the sale doubles the sold quantity the kept side
  #   prices; one after the buy doubles the bought quantity.
  test "a split after the sale or the buy is not a move" do
    world = base_world(name: "Sides Split")
    sold = security!("SDS")
    bought = security!("BDS")

    put_quotes!(sold, [{~D[2025-01-15], "100"}, {~D[2025-02-14], "55"}])
    put_quotes!(bought, [{~D[2025-02-14], "105"}])

    # A position of the sold security is left, so its split books.
    buy!(world, sold, quantity: "20", price: "90", date: ~D[2024-06-03])
    sale = sell!(world, sold, quantity: "10", price: "100", date: ~D[2025-01-15])
    buy!(world, bought, quantity: "5", price: "200", date: ~D[2025-01-20])

    for security <- [sold, bought] do
      {:ok, _rows} =
        Splits.book_split(Actor.owner_ui(), %{
          security_id: security.id,
          date: ~D[2025-02-01],
          ratio_numerator: 2,
          ratio_denominator: 1
        })
    end

    # 1m, closes of 2025-02-14 after the split, quantities x 2:
    #   kept     = 1 x 10 x 2 x 55            = 1100
    #   switched = (1000 / 1000) x 5 x 2 x 105 = 1050
    one = Enum.find(block(sale).spans, &(&1.span == "1m"))
    assert_decimal(one.kept, "1100")
    assert_decimal(one.switched, "1050")
    assert_decimal(one.difference, "-50")
  end
end
