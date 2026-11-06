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
  alias Portfolixir.Ledger
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

  # User story (closing act A1, ADR-0057 §1.2: a candidate pays money):
  # As the agent reading a sale whose only later buy cost nothing,
  # I want that buy not counted as a candidate,
  # so that the sale reads no_buy_within_30_days and never claims an earlier
  # sale took money that no buy asked for.
  #
  # Acceptance criteria:
  # - A buy with no positive cash debit (a zero-price buy, which the ledger
  #   accepts) is no candidate: the sale reads no_match,
  #   no_buy_within_30_days.
  test "a buy with no positive debit is no candidate" do
    world = base_world(name: "Switch Free Buy")
    sale = sell!(world, security!("SFB"), quantity: "10", price: "100", date: ~D[2025-01-15])
    buy!(world, security!("BFB"), quantity: "5", price: "0", date: ~D[2025-01-16])

    assert %{status: :no_match, reason: :no_buy_within_30_days, buys: []} = block(sale)
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

    # Same-day ties are split pro rata, never by id (ADR-0057 as amended on
    # 2026-11-06): proceeds 300 + 300 = 600 on 2025-01-15, debits
    # 400 + 400 = 800 on 2025-01-16, t = min(600, 800) = 600; each sale
    # gives each buy 600 x (300 / 600) x (400 / 800) = 150.
    for sale <- [one, two] do
      assert [%{amount_taken: first_buy}, %{amount_taken: second_buy}] =
               Map.fetch!(first, sale.id).buys

      assert_decimal(first_buy, "150")
      assert_decimal(second_buy, "150")
    end
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

  # User story (closing act M3, ADR-0057 §2: each side one division):
  # As the operator whose switch inside a USD account came out even,
  # I want the difference to read exactly 0,
  # so that an even switch never reads as a tiny loss or gain.
  #
  # Acceptance criteria:
  # - At a EUR-hub rate whose inverse does not terminate (1.3), kept and
  #   switched are equal to the last digit and the difference is exactly 0.
  test "an even switch at a hub rate of 1.3 reads a difference of exactly 0" do
    world = base_world(name: "Sides Even", cash_currency: "USD")
    sold = security!("SEV", "USD")
    bought = security!("BEV", "USD")
    rate!(~D[2025-01-02], "1.3")

    put_quotes!(sold, [{~D[2025-01-15], "100"}, {~D[2025-02-14], "110"}])
    put_quotes!(bought, [{~D[2025-02-14], "275"}])

    # Proceeds 10 x 100 = 1000 USD; the buy's debit 4 x 250 = 1000 USD: a = 1.
    sale =
      sell!(world, sold, quantity: "10", price: "100", date: ~D[2025-01-15], currency: "USD")

    buy!(world, bought, quantity: "4", price: "250", date: ~D[2025-01-20], currency: "USD")

    # 1m: kept = 1000 x 10 x 110 / (1000 x 1.3) = 1100 / 1.3; switched =
    # 1000 x 4 x 275 / (1000 x 1.3) = 1100 / 1.3: the same quotient, one
    # division each, so 846.1538461538461538461538461538462 both, and the
    # difference exactly 0. (Through 110 x (1 / 1.3) and 275 x (1 / 1.3),
    # each inverse rounded at 34 digits, the two sides differed by 1E-31.)
    one = Enum.find(block(sale).spans, &(&1.span == "1m"))
    assert Decimal.equal?(one.difference, Decimal.new(0)), inspect(one.difference)
    assert one.switched == one.kept
    assert_decimal(one.kept, "846.1538461538461538461538461538462")
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

  # User story (R1, ADR-0057 §3: fees inside, taxes apart):
  # As the operator who paid to switch,
  # I want the fees inside the difference and named as one line, and the
  # sale's taxes named apart and added back to the switched side,
  # so that the switch is compared before tax, as the kept position would be.
  #
  # Acceptance criteria:
  # - fees_inside = a x the sale's fees + each buy's share x its fees, for
  #   the buys dated on or before the span's end, in EUR.
  # - taxes_apart = a x the sale's taxes, in EUR; difference = switched +
  #   taxes_apart - kept.
  # - A buy dated after the end adds no fee yet: its money is still cash.
  test "the fees inside the difference and the sale's taxes apart" do
    world = base_world(name: "Costs")
    sold = security!("SCO")
    bought = security!("BCO")
    put_quotes!(sold, [{~D[2025-01-15], "100"}, {~D[2025-02-14], "110"}])
    put_quotes!(bought, [{~D[2025-02-14], "200"}])

    # Proceeds 10 x 100 - fees 10 - taxes 40 = 950; the buy's debit
    # 4 x 180 + fees 40 = 760, all of it taken: a = 760 / 950 = 0.8.
    sale =
      sell!(world, sold,
        quantity: "10",
        price: "100",
        fees: "10",
        taxes: "40",
        date: ~D[2025-01-15]
      )

    buy!(world, bought, quantity: "4", price: "180", fees: "40", date: ~D[2025-01-20])

    block = block(sale)
    assert_decimal(block.proceeds, "950")
    assert_decimal(block.share_of_proceeds_matched, "0.8")
    assert_decimal(block.unallocated, "190")

    # 1m, in EUR at 1:
    #   kept         = 760 x 10 x 110 / 950          = 880   (0.8 x 10 x 110)
    #   switched     = 760 x 4 x 200 / 760           = 800
    #   taxes_apart  = 760 x 40 / 950                = 32    (0.8 x 40)
    #   fees_inside  = 760 x 10 / 950 + 760 x 40 / 760 = 8 + 40 = 48
    #   difference   = 800 + 32 - 880                = -48
    one = Enum.find(block.spans, &(&1.span == "1m"))
    assert_decimal(one.kept, "880")
    assert_decimal(one.switched, "800")
    assert_decimal(one.taxes_apart, "32")
    assert_decimal(one.fees_inside, "48")
    assert_decimal(one.difference, "-48")
    assert_decimal(one.income_apart, "0")

    # A sale on Friday 2025-01-31 (1m ends 2025-02-28) at flat prices, with
    # a buy on day 3 and one on day 30, after the 1m end. Proceeds 1000;
    # debits 4 x 100 + 4 = 404 and 5 x 100 + 6 = 506: a = 910 / 1000 = 0.91.
    flat = base_world(name: "Costs Flat")
    flat_sold = security!("SCF")
    early = security!("BCE")
    late = security!("BCL")

    put_quotes!(flat_sold, [
      {~D[2025-01-31], "100"},
      {~D[2025-02-28], "100"},
      {~D[2025-04-30], "100"}
    ])

    put_quotes!(early, [{~D[2025-02-28], "100"}, {~D[2025-04-30], "100"}])
    put_quotes!(late, [{~D[2025-04-30], "100"}])

    flat_sale = sell!(flat, flat_sold, quantity: "10", price: "100", date: ~D[2025-01-31])
    buy!(flat, early, quantity: "4", price: "100", fees: "4", date: ~D[2025-02-03])
    buy!(flat, late, quantity: "5", price: "100", fees: "6", date: ~D[2025-03-02])

    spans = Map.new(block(flat_sale).spans, &{&1.span, &1})

    #   1m (2025-02-28): kept = 910 x 10 x 100 / 1000 = 910;
    #     switched = 404 x 4 x 100 / 404 = 400, + 506 as cash = 906;
    #     fees_inside = 0 + 404 x 4 / 404 = 4 (the later buy's fee is not
    #     paid yet); difference = 906 - 910 = -4
    #   3m (2025-04-30): switched = 400 + 506 x 5 x 100 / 506 = 900;
    #     fees_inside = 4 + 6 = 10; difference = 900 - 910 = -10
    assert_decimal(spans["1m"].kept, "910")
    assert_decimal(spans["1m"].switched, "906")
    assert_decimal(spans["1m"].fees_inside, "4")
    assert_decimal(spans["1m"].difference, "-4")
    assert_decimal(spans["3m"].switched, "900")
    assert_decimal(spans["3m"].fees_inside, "10")
    assert_decimal(spans["3m"].difference, "-10")
  end

  # User story (R1, ADR-0057 §3: the sale's taxes apart, signed):
  # As the operator whose sale brought a tax refund,
  # I want the refund named as a negative taxes_apart and its cash among the
  # proceeds,
  # so that a refund flatters the switch no more than a tax burdens it.
  #
  # Acceptance criteria:
  # - A tax_refund of the sold security on the sale's date and cash account
  #   (the shape the import gives a refund split off a sale) joins the
  #   proceeds and is a negative tax of the sale.
  test "a tax refund on the sale is a negative taxes_apart" do
    world = base_world(name: "Costs Refund")
    sold = security!("SRF")
    bought = security!("BRF")
    put_quotes!(sold, [{~D[2025-01-15], "100"}, {~D[2025-02-14], "110"}])
    put_quotes!(bought, [{~D[2025-02-14], "220"}])

    sale = sell!(world, sold, quantity: "10", price: "100", date: ~D[2025-01-15])

    {:ok, _refund} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        security_id: sold.id,
        type: "tax_refund",
        date: ~D[2025-01-15],
        gross_amount: "25",
        currency_code: "EUR"
      })

    # Proceeds 1000 + the refund 25 = 1025; the buy's debit 5 x 205 = 1025.
    buy!(world, bought, quantity: "5", price: "205", date: ~D[2025-01-20])

    block = block(sale)
    assert_decimal(block.proceeds, "1025")
    assert_decimal(block.share_of_proceeds_matched, "1")

    # 1m: kept = 1025 x 10 x 110 / 1025 = 1100; switched = 1025 x 5 x 220 /
    # 1025 = 1100; taxes_apart = 1025 x (0 - 25) / 1025 = -25;
    # difference = 1100 + (-25) - 1100 = -25.
    one = Enum.find(block.spans, &(&1.span == "1m"))
    assert_decimal(one.kept, "1100")
    assert_decimal(one.switched, "1100")
    assert_decimal(one.taxes_apart, "-25")
    assert_decimal(one.difference, "-25")
  end

  # User story (R1, ADR-0057 §3: income is price only on both sides):
  # As the operator whose new position paid a dividend,
  # I want the bought positions' booked distributions within the span named
  # apart and never added,
  # so that I see them without the comparison counting what the kept side
  # cannot.
  #
  # Acceptance criteria:
  # - income_apart is each bought position's part of the distributions
  #   booked on its security after the buy and up to the span's end, before
  #   withholding tax (net plus tax): the share of the buy this sale paid for
  #   x the buy's quantity over the quantity held the day before.
  # - The difference does not include it.
  test "the bought positions' distributions are named apart, never added" do
    world = base_world(name: "Costs Income")
    sold = security!("SIN")
    bought = security!("BIN")
    put_quotes!(sold, [{~D[2025-01-15], "100"}, {~D[2025-02-14], "100"}, {~D[2025-04-15], "100"}])
    put_quotes!(bought, [{~D[2025-02-14], "100"}, {~D[2025-04-15], "100"}])

    # 10 shares held before the sale: the dividends are paid on 20.
    buy!(world, bought, quantity: "10", price: "90", date: ~D[2024-12-02])
    sale = sell!(world, sold, quantity: "10", price: "100", date: ~D[2025-01-15])
    buy!(world, bought, quantity: "10", price: "100", date: ~D[2025-01-20])

    for {date, net, tax} <- [{~D[2025-02-10], "18", "2"}, {~D[2025-03-10], "30", "0"}] do
      {:ok, _dividend} =
        Ledger.create_transaction(Actor.owner_ui(), %{
          portfolio_id: world.portfolio.id,
          cash_account_id: world.cash.id,
          security_id: bought.id,
          type: "dividend",
          date: date,
          gross_amount: net,
          taxes: tax,
          currency_code: "EUR"
        })
    end

    spans = Map.new(block(sale).spans, &{&1.span, &1})

    #   1m (2025-02-15): 1000 x 10 x (18 + 2) / (1000 x 20) = 10
    #   3m (2025-04-15): 10 + 1000 x 10 x 30 / (1000 x 20)  = 10 + 15 = 25
    # kept = switched = 1000 at flat prices: the difference stays 0.
    assert_decimal(spans["1m"].income_apart, "10")
    assert_decimal(spans["1m"].difference, "0")
    assert_decimal(spans["3m"].income_apart, "25")
    assert_decimal(spans["3m"].difference, "0")
  end

  # --- Sprint 26 closing act, M1 (ADR-0057 as amended on 2026-11-06) ---

  # Deletes a booking through the Ledger and books it again unchanged: a
  # true, journaled correction that gives the booking a new, higher id.
  defp rebook!(world, %Transaction{} = row, security) do
    {:ok, _deleted} = Ledger.delete_transaction(Actor.owner_ui(), row)

    book = if row.type == "buy", do: &buy!/3, else: &sell!/3

    book.(world, security,
      quantity: Decimal.to_string(row.quantity),
      price: Decimal.to_string(row.price),
      fees: Decimal.to_string(row.fees),
      taxes: Decimal.to_string(row.taxes),
      date: row.date
    )
  end

  # The span figures of a block, by span label, with the booking ids left
  # out: what must not move when a booking is deleted and booked again.
  defp figures(block) do
    %{
      status: block.status,
      reason: block.reason,
      proceeds: block.proceeds,
      a: block.share_of_proceeds_matched,
      unallocated: block.unallocated,
      buys:
        block.buys
        |> Enum.map(&{&1.security.id, &1.date, &1.amount_taken, &1.share_of_buy})
        |> Enum.sort(),
      spans: Enum.map(block.spans, &Map.take(&1, [:span, :kept, :switched, :difference]))
    }
  end

  # User story (closing act M1, ADR-0057 §1.3 as amended: same-day buys
  # without ids):
  # As the operator who bought two securities on one day with a sale's money,
  # I want the proceeds split over both buys in proportion to their debits,
  # so that which buy was booked first, or rebooked later, cannot decide
  # what the switch cost.
  #
  # Acceptance criteria:
  # - Two same-day buys of 1000 each share one sale's 1000 pro rata: each
  #   takes 500, share_of_buy 0.5.
  # - Deleting the first buy and booking it again unchanged (a higher id)
  #   leaves every figure as it was.
  test "two same-day buys share the proceeds pro rata, whatever their ids" do
    world = base_world(name: "Tie Buys")
    sold = security!("TB0")
    x = security!("TBX")
    y = security!("TBY")

    put_quotes!(sold, [{~D[2025-01-15], "100"}, {~D[2025-02-14], "100"}])
    put_quotes!(x, [{~D[2025-02-14], "50"}])
    put_quotes!(y, [{~D[2025-02-14], "150"}])

    # Proceeds 10 x 100 = 1000; debits 10 x 100 = 1000 each, both on
    # 2025-01-20: t = min(1000, 2000) = 1000, each buy takes
    # 1000 x 1000 / 2000 = 500, share 500 / 1000 = 0.5.
    sale = sell!(world, sold, quantity: "10", price: "100", date: ~D[2025-01-15])
    buy_x = buy!(world, x, quantity: "10", price: "100", date: ~D[2025-01-20])
    buy!(world, y, quantity: "10", price: "100", date: ~D[2025-01-20])

    before = block(sale)

    assert [%{amount_taken: taken_x, share_of_buy: share_x}, %{amount_taken: taken_y}] =
             Enum.sort_by(before.buys, &(&1.security.id == y.id))

    assert_decimal(taken_x, "500")
    assert_decimal(share_x, "0.5")
    assert_decimal(taken_y, "500")
    assert_decimal(before.share_of_proceeds_matched, "1")

    # 1m (2025-02-15): kept = 1 x 10 x 100 = 1000; switched = 0.5 x 10 x 50
    # + 0.5 x 10 x 150 = 250 + 750 = 1000; difference = 0. (By id, X alone
    # took the money: 500 - 1000 = -500; after rebooking X, Y: +500.)
    one = Enum.find(before.spans, &(&1.span == "1m"))
    assert_decimal(one.kept, "1000")
    assert_decimal(one.switched, "1000")
    assert_decimal(one.difference, "0")

    rebook!(world, buy_x, x)
    assert figures(block(sale)) == figures(before)
  end

  # User story (closing act M1, ADR-0057 §1.3 as amended: same-day sales
  # without ids):
  # As the operator who sold two positions on one day and bought one,
  # I want the buy funded by both sales in proportion to their proceeds,
  # so that rebooking one sale cannot make a losing switch vanish.
  #
  # Acceptance criteria:
  # - Two same-day sales of 1000 each fund one buy of 1000 with 500 each,
  #   a = 0.5 for both.
  # - Deleting one sale and booking it again unchanged leaves both blocks'
  #   figures as they were.
  test "two same-day sales fund one buy pro rata, whatever their ids" do
    world = base_world(name: "Tie Sales")
    rises = security!("TSA")
    falls = security!("TSB")
    bought = security!("TSZ")

    put_quotes!(rises, [{~D[2025-01-15], "100"}, {~D[2025-02-14], "150"}])
    put_quotes!(falls, [{~D[2025-01-15], "100"}, {~D[2025-02-14], "50"}])
    put_quotes!(bought, [{~D[2025-02-14], "100"}])

    # Proceeds 1000 each on 2025-01-15; the buy's debit 10 x 100 = 1000:
    # t = min(2000, 1000) = 1000, each sale gives 1000 x 1000 / 2000 = 500,
    # a = 500 / 1000 = 0.5, unallocated 500, share_of_buy 500 / 1000 = 0.5.
    sale_a = sell!(world, rises, quantity: "10", price: "100", date: ~D[2025-01-15])
    sale_b = sell!(world, falls, quantity: "10", price: "100", date: ~D[2025-01-15])
    buy!(world, bought, quantity: "10", price: "100", date: ~D[2025-01-16])

    blocks = SaleReinvestment.blocks([sale_a, sale_b], @today)
    a = Map.fetch!(blocks, sale_a.id)
    b = Map.fetch!(blocks, sale_b.id)

    for block <- [a, b] do
      assert block.status == :matched
      assert [%{amount_taken: taken, share_of_buy: share}] = block.buys
      assert_decimal(taken, "500")
      assert_decimal(share, "0.5")
      assert_decimal(block.share_of_proceeds_matched, "0.5")
      assert_decimal(block.unallocated, "500")
    end

    # 1m: A kept = 0.5 x 10 x 150 = 750, switched = 0.5 x 10 x 100 = 500,
    # difference -250; B kept = 0.5 x 10 x 50 = 250, switched 500, +250.
    # (By id, A alone: 1000 - 1500 = -500 and B no_match; after rebooking
    # A, B alone: +500 and the losing switch gone.)
    one_a = Enum.find(a.spans, &(&1.span == "1m"))
    assert_decimal(one_a.kept, "750")
    assert_decimal(one_a.switched, "500")
    assert_decimal(one_a.difference, "-250")
    one_b = Enum.find(b.spans, &(&1.span == "1m"))
    assert_decimal(one_b.kept, "250")
    assert_decimal(one_b.difference, "250")

    rebooked = rebook!(world, sale_a, rises)
    after_rebook = SaleReinvestment.blocks([rebooked, sale_b], @today)
    assert figures(Map.fetch!(after_rebook, rebooked.id)) == figures(a)
    assert figures(Map.fetch!(after_rebook, sale_b.id)) == figures(b)
  end

  # User story (closing act M1, ADR-0057 §1.1 as amended: a refund without
  # ids):
  # As the operator whose sale brought a tax refund booked beside it,
  # I want the refund attached to its sale whatever the order the two were
  # booked in, and split pro rata over two same-day sales of the security,
  # so that rebooking either booking cannot move the proceeds.
  #
  # Acceptance criteria:
  # - A tax_refund booked before its sale (a lower id) still joins the sale's
  #   proceeds and is a negative tax of it.
  # - Two same-day sales of the security on the account share one refund in
  #   proportion to their proceeds.
  # - Deleting a sale and booking it again unchanged moves nothing.
  test "a tax refund attaches to its sale whatever the ids, pro rata over a day's sales" do
    world = base_world(name: "Tie Refund")
    sold = security!("TRX")
    bought = security!("TRZ")
    put_quotes!(sold, [{~D[2025-01-15], "100"}, {~D[2025-02-14], "100"}])
    put_quotes!(bought, [{~D[2025-02-14], "1010"}])

    # The refund is booked first, so its id is below both sales'.
    {:ok, refund} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        security_id: sold.id,
        type: "tax_refund",
        date: ~D[2025-01-15],
        gross_amount: "40",
        currency_code: "EUR"
      })

    small = sell!(world, sold, quantity: "10", price: "100", date: ~D[2025-01-15])
    large = sell!(world, sold, quantity: "30", price: "100", date: ~D[2025-01-15])
    assert refund.id < small.id
    buy!(world, bought, quantity: "4", price: "1010", date: ~D[2025-01-20])

    # The refund 40 splits by the sales' cash amounts 1000 and 3000:
    #   small: 40 x 1000 / 4000 = 10, proceeds 1010, taxes 0 - 10 = -10
    #   large: 40 x 3000 / 4000 = 30, proceeds 3030, taxes -30
    # The buy's debit 4 x 1010 = 4040 = 1010 + 3030: t = 4040, each sale
    # gives all of its proceeds, a = 1; share_of_buy 1010 / 4040 = 0.25 and
    # 3030 / 4040 = 0.75.
    blocks = SaleReinvestment.blocks([small, large], @today)
    first = Map.fetch!(blocks, small.id)
    second = Map.fetch!(blocks, large.id)
    assert_decimal(first.proceeds, "1010")
    assert_decimal(second.proceeds, "3030")
    assert_decimal(first.share_of_proceeds_matched, "1")
    assert [%{share_of_buy: quarter}] = first.buys
    assert_decimal(quarter, "0.25")

    # 1m: small kept = 1 x 10 x 100 = 1000, switched = 0.25 x 4 x 1010 =
    # 1010, taxes_apart = -10, difference = 1010 - 10 - 1000 = 0; large kept
    # = 3000, switched = 0.75 x 4 x 1010 = 3030, taxes_apart = -30,
    # difference 0.
    one = Enum.find(first.spans, &(&1.span == "1m"))
    assert_decimal(one.switched, "1010")
    assert_decimal(one.taxes_apart, "-10")
    assert_decimal(one.difference, "0")
    two = Enum.find(second.spans, &(&1.span == "1m"))
    assert_decimal(two.switched, "3030")
    assert_decimal(two.taxes_apart, "-30")
    assert_decimal(two.difference, "0")

    # The small sale deleted and booked again: now its id is above the
    # refund's and the large sale's; nothing moves.
    rebooked = rebook!(world, small, sold)
    again = SaleReinvestment.blocks([rebooked, large], @today)
    assert figures(Map.fetch!(again, rebooked.id)) == figures(first)
    assert figures(Map.fetch!(again, large.id)) == figures(second)
  end

  # User story (closing act M1, ADR-0057 §1.3 as amended: a buy of a
  # security sold in the same group):
  # As the operator who sold X and Y on one day and then bought X back and
  # Z,
  # I want the pro rata split to keep X's money out of the X buy and still
  # end, by rule,
  # so that the exclusion of the sold security holds without any id.
  #
  # Acceptance criteria:
  # - The pairing runs in rounds: each buy takes f x its need, split over
  #   the sales it may take from by their remaining proceeds, f the largest
  #   factor up to 1 that no sale overdraws; the rounds repeat until no
  #   allowed pair has money on both sides.
  test "a buy of a security sold the same day takes only from the other sales" do
    world = base_world(name: "Tie Exclusion")
    x = security!("TEX")
    y = security!("TEY")
    z = security!("TEZ")

    sale_x = sell!(world, x, quantity: "1", price: "100", date: ~D[2025-01-15])
    sale_y = sell!(world, y, quantity: "1", price: "100", date: ~D[2025-01-15])
    buy_x = buy!(world, x, quantity: "1", price: "100", date: ~D[2025-01-16])
    buy_z = buy!(world, z, quantity: "1", price: "100", date: ~D[2025-01-16])

    # Proceeds X 100, Y 100; needs: buy X 100 (may take from Y only), buy Z
    # 100 (from X and Y).
    # Round 1: E(buy X) = 100, E(buy Z) = 200; loads: sale X 100/200 = 1/2,
    #   sale Y 100/100 + 100/200 = 3/2; f = min(1, 2, 2/3) = 2/3.
    #   Y -> buy X = 2/3 x 100 x 100/100 = 200/3; X -> Z = Y -> Z =
    #   2/3 x 100 x 100/200 = 100/3. Sale Y is used up; X has 200/3 left;
    #   each buy needs 100/3 more.
    # Round 2: buy X has no sale left to take from; E(buy Z) = 200/3, load of
    #   X = (100/3)/(200/3) = 1/2, f = 1: X -> Z += 100/3. Buy Z is paid.
    # Sale X: Z took 200/3, a = (200/3)/100 = 2/3, unallocated 100/3.
    # Sale Y: buy X 200/3 and Z 100/3, a = 1, unallocated 0.
    blocks = SaleReinvestment.blocks([sale_x, sale_y], @today)

    from_x = Map.fetch!(blocks, sale_x.id)
    assert [%{buy_id: z_id, amount_taken: x_to_z}] = from_x.buys
    assert z_id == buy_z.id
    assert_decimal(x_to_z, "66.66666666666666666666666666666667")
    assert_decimal(from_x.share_of_proceeds_matched, "0.6666666666666666666666666666666667")
    assert_decimal(from_x.unallocated, "33.33333333333333333333333333333333")

    from_y = Map.fetch!(blocks, sale_y.id)

    assert [%{buy_id: ^z_id, amount_taken: y_to_z}, %{amount_taken: y_to_x} = to_x] =
             Enum.sort_by(from_y.buys, &(&1.buy_id == buy_x.id))

    assert to_x.buy_id == buy_x.id
    assert_decimal(y_to_x, "66.66666666666666666666666666666667")
    assert_decimal(y_to_z, "33.33333333333333333333333333333333")
    assert_decimal(from_y.share_of_proceeds_matched, "1")
    assert_decimal(from_y.unallocated, "0")
  end

  # User story (closing act A5, AGENTS.md: every metric states its basis):
  # As the agent reading days_to_first_buy,
  # I want the payload's basis to define it,
  # so that I know what the number counts without reading the code.
  #
  # Acceptance criteria:
  # - computation_basis has days_to_first_buy: calendar days from the sale
  #   date to the first matched buy's date, 0 on the sale day, null without
  #   a match.
  test "the basis defines days_to_first_buy" do
    basis = SaleReinvestment.computation_basis()

    assert basis.days_to_first_buy =~
             "calendar days from the sale's date to the date of the " <>
               "first matched buy"

    assert basis.days_to_first_buy =~ "0 when it is on the sale's own date"
  end
end
