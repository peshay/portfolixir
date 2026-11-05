defmodule Portfolixir.Portfolios.Performance.SaleHindsightTest do
  # Sprint 25 Lane S, S2 (I18 modes 1 and 2, the plan's D-3): what a sale
  # missed. One row per sale booking, four spans after the sale, each
  # measured by S1's WindowReturn.price_return/3 and never by a second
  # computation. Risk tier (ADR-0036): every figure below is an exact
  # Decimal derived by hand in the comments, at Decimal's default context
  # (34 significant digits, half-up), for no benchmark, a rate benchmark and
  # a security benchmark (the plan's D-1.2), and a USD security is measured
  # at a moving rate (D-8.3).
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [
      base_world: 1,
      buy!: 3,
      create_security!: 1,
      cross_trade!: 3,
      put_quotes!: 2,
      sell!: 3
    ]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Fx
  alias Portfolixir.Portfolios.Performance.SaleHindsight

  # The clock of every test below: the spans of a sale on 2025-01-15 all end
  # on or before it, the latest close (2026-03-02) included.
  @today ~D[2026-03-10]

  defp d(value), do: Decimal.new(value)

  defp assert_decimal(actual, expected) do
    assert %Decimal{} = actual
    assert Decimal.equal?(actual, d(expected)), "expected #{expected}, got #{inspect(actual)}"
  end

  defp benchmark!(name, ticker) do
    security = create_security!(name: name, ticker: ticker, currency: "EUR")
    {:ok, flagged} = Catalog.update_security(Actor.owner_ui(), security, %{is_benchmark: true})
    flagged
  end

  defp rate!(date, rate) do
    {:ok, 1} =
      Fx.upsert_many([
        %{base_currency: "EUR", quote_currency: "USD", date: date, rate: rate, source: "manual"}
      ])
  end

  defp span(row, label), do: Enum.find(row.spans, &(&1.span == label))

  # The sold security of the shape tests: sold on Wednesday 2025-01-15 at a
  # booked 101 (the close that day is 100, so the two are told apart). The
  # four span ends are 2025-02-15 (a Saturday: Friday's close stands for it),
  # 2025-04-15, 2026-01-15 and the latest close, 2026-03-02.
  defp sold_world do
    world = base_world(name: "Hindsight")
    security = create_security!(name: "Sold Fund", ticker: "SLD", currency: "EUR")

    put_quotes!(security, [
      {~D[2025-01-15], "100"},
      {~D[2025-02-14], "110"},
      {~D[2025-04-15], "90"},
      {~D[2026-01-15], "130"},
      {~D[2026-03-02], "150"}
    ])

    buy!(world, security, quantity: "10", price: "80", date: ~D[2024-06-03])
    sale = sell!(world, security, quantity: "10", price: "101", date: ~D[2025-01-15])

    %{world: world, security: security, sale: sale}
  end

  # User story (S2, I18 mode 1 without a comparison; D-3):
  # As the operator looking back at a sale,
  # I want the sold security's move after the sale over 1, 3 and 12 months
  # and to the latest close, measured from its close on the sale day,
  # so that I see what the position did after I let it go.
  #
  # Acceptance criteria:
  # - One row per sale booking, naming the transaction, the date, the
  #   security, the quantity and the booked price and currency.
  # - The start is the close standing for the sale day, in EUR; the booked
  #   price is beside it, not used.
  # - Four spans, 1m, 3m, 12m (Date.shift/2 by calendar months) and latest
  #   (the security's latest close), each with its end date, the closes used
  #   and the security's return; without a benchmark the benchmark side and
  #   the difference are nil.
  test "without a benchmark each span answers the security's own return" do
    %{security: security, sale: sale} = sold_world()

    assert %{rows: [row], truncated: false} = SaleHindsight.report(today: @today)

    assert row.sale_id == sale.id
    assert row.date == ~D[2025-01-15]
    assert row.security.id == security.id
    assert_decimal(row.quantity, "10")
    assert_decimal(row.price, "101")
    assert row.currency_code == "EUR"

    assert row.start.date == ~D[2025-01-15]
    assert_decimal(row.start.close, "100")
    assert_decimal(row.start.eur_value, "100")
    assert row.start_reason == nil

    assert Enum.map(row.spans, & &1.span) == ["1m", "3m", "12m", "latest"]

    # 1m: 110 / 100 - 1 = 0.1, Friday 2025-02-14's close standing for
    # Saturday 2025-02-15.
    one = span(row, "1m")
    assert one.status == :complete
    assert one.end_on == ~D[2025-02-15]
    assert one.days == 31
    assert one.security.end.date == ~D[2025-02-14]
    assert_decimal(one.security.return, "0.1")
    assert one.benchmark == nil
    assert one.difference == nil

    # 3m: 90 / 100 - 1 = -0.1; 12m: 130 / 100 - 1 = 0.3; latest (the
    # close of 2026-03-02): 150 / 100 - 1 = 0.5.
    assert span(row, "3m").end_on == ~D[2025-04-15]
    assert_decimal(span(row, "3m").security.return, "-0.1")
    assert span(row, "12m").end_on == ~D[2026-01-15]
    assert_decimal(span(row, "12m").security.return, "0.3")
    assert span(row, "latest").end_on == ~D[2026-03-02]
    assert span(row, "latest").days == 411
    assert_decimal(span(row, "latest").security.return, "0.5")
  end

  # User story (S2, I18 mode 1: a fixed percentage; ADR-0046's rate:):
  # As the operator who would have parked the proceeds at a fixed rate,
  # I want each span's rate return beside the security's and the difference,
  # so that I see what the sale missed against that rate.
  #
  # Acceptance criteria:
  # - The rate compounds daily over the span's calendar days, from the sale
  #   day to the date the end close stands for (WindowReturn's
  #   fixed_rate_return/3).
  # - difference = security return - benchmark return, unrounded.
  test "a rate benchmark: each span's three figures equal the hand computation" do
    sold_world()

    %{rows: [row]} = SaleHindsight.report(today: @today, benchmark: {:rate, d("0.05")})

    # The daily factor of 5 % p.a. is 1.0001336806171135 (S1's test), and
    # the rate return over n days is that factor multiplied into 1 n times,
    # each product at 34 significant digits half-up, minus 1:
    #   1m, 31 days:      0.004152419664798823558111758969043
    #     difference 0.1 - that  =  0.095847580335201176441888241030957
    #   3m, 90 days:      0.012103108392936760036609980125266
    #     difference -0.1 - that = -0.112103108392936760036609980125266
    #   12m, 365 days:    0.050000000000022857612005448692235
    #     difference 0.3 - that  =  0.249999999999977142387994551307765
    #   latest, 411 days: 0.056476232712616220647913357381662
    #     difference 0.5 - that  =  0.443523767287383779352086642618338
    expected = [
      {"1m", "0.1", "0.004152419664798823558111758969043", "0.095847580335201176441888241030957"},
      {"3m", "-0.1", "0.012103108392936760036609980125266",
       "-0.112103108392936760036609980125266"},
      {"12m", "0.3", "0.050000000000022857612005448692235",
       "0.249999999999977142387994551307765"},
      {"latest", "0.5", "0.056476232712616220647913357381662",
       "0.443523767287383779352086642618338"}
    ]

    for {label, own, rate, difference} <- expected do
      span = span(row, label)
      assert span.status == :complete, label
      assert_decimal(span.security.return, own)
      assert Decimal.to_string(span.benchmark.return) == rate, label
      assert Decimal.to_string(span.difference) == difference, label
      assert span.benchmark.start == nil
      assert span.benchmark.end == nil
    end
  end

  # User story (S2, I18 mode 2: another security, price only; D-3):
  # As the operator comparing a sale with an index I could have held,
  # I want the benchmark security measured from its own close standing for
  # the sale day to its close standing for each span's end,
  # so that both are measured alike and the difference is fair.
  #
  # Acceptance criteria:
  # - The benchmark's closes are found by the same rule (the last close on or
  #   before the date, within 7 days) and named with their dates.
  test "a security benchmark: each span's three figures equal the hand computation" do
    sold_world()
    bench = benchmark!("Bench Index", "BIX")

    # The sale day has no benchmark close: Tuesday 2025-01-14's 200 stands
    # for it.
    put_quotes!(bench, [
      {~D[2025-01-14], "200"},
      {~D[2025-02-14], "210"},
      {~D[2025-04-15], "220"},
      {~D[2026-01-15], "180"},
      {~D[2026-03-02], "250"}
    ])

    %{rows: [row]} = SaleHindsight.report(today: @today, benchmark: {:security, bench})

    # 1m: 210 / 200 - 1 = 0.05, difference 0.1 - 0.05 = 0.05;
    # 3m: 220 / 200 - 1 = 0.1, difference -0.1 - 0.1 = -0.2;
    # 12m: 180 / 200 - 1 = -0.1, difference 0.3 - (-0.1) = 0.4;
    # latest: 250 / 200 - 1 = 0.25, difference 0.5 - 0.25 = 0.25.
    expected = [
      {"1m", "0.1", "0.05", "0.05"},
      {"3m", "-0.1", "0.1", "-0.2"},
      {"12m", "0.3", "-0.1", "0.4"},
      {"latest", "0.5", "0.25", "0.25"}
    ]

    for {label, own, benchmark, difference} <- expected do
      span = span(row, label)
      assert span.status == :complete, label
      assert_decimal(span.security.return, own)
      assert_decimal(span.benchmark.return, benchmark)
      assert_decimal(span.difference, difference)
      assert span.benchmark.start.date == ~D[2025-01-14]
      assert span.benchmark.start.stands_for == ~D[2025-01-15]
    end

    assert span(row, "1m").benchmark.end.date == ~D[2025-02-14]
  end

  # User story (S2, D-3: a span whose end is after today is pending):
  # As the agent reading a recent sale,
  # I want a span not yet reached named pending, with its end date,
  # so that I never read a figure for a month that has not happened.
  #
  # Acceptance criteria:
  # - A span whose end date is after today is pending, with no figure.
  # - latest ends on the security's latest close and is answered.
  test "a span whose end is after today reads pending" do
    world = base_world(name: "Recent")
    security = create_security!(name: "Recent Fund", ticker: "RCF", currency: "EUR")
    put_quotes!(security, [{~D[2026-02-20], "50"}, {~D[2026-03-09], "55"}])
    sell!(world, security, quantity: "1", price: "50", date: ~D[2026-02-20])

    %{rows: [row]} = SaleHindsight.report(today: @today)

    for label <- ["1m", "3m", "12m"] do
      span = span(row, label)
      assert span.status == :pending, label
      assert span.reason == nil
      assert span.security == nil
      assert span.difference == nil
    end

    assert span(row, "1m").end_on == ~D[2026-03-20]

    # latest: 55 / 50 - 1 = 0.1, to the close of 2026-03-09.
    assert span(row, "latest").status == :complete
    assert span(row, "latest").end_on == ~D[2026-03-09]
    assert_decimal(span(row, "latest").security.return, "0.1")
  end

  # User story (S2, D-3: a span without closes is named, never estimated):
  # As the agent reading what a sale missed,
  # I want a span without a close at its end, or a sale without a close on
  # its day, named incomplete with S1's reason,
  # so that a gap in the quotes is never read as a figure.
  #
  # Acceptance criteria:
  # - No close within 7 days before a span's end: incomplete, no_end_close.
  # - No close within 7 days before the sale day: every reached span is
  #   incomplete, no_start_close, and the row's start is nil with the reason.
  # - A benchmark security without a close for the span: incomplete,
  #   no_benchmark_close, the security's own figure kept.
  # - Orphan sells count: a sale with no buy before it is a row.
  test "a missing close reads incomplete with its reason" do
    world = base_world(name: "Gaps")
    gappy = create_security!(name: "Gappy Fund", ticker: "GAP", currency: "EUR")
    unquoted = create_security!(name: "Unquoted Fund", ticker: "UNQ", currency: "EUR")
    bench = benchmark!("Short Index", "SIX")

    # Closes at the sale and at 1m only; the 3m end (2025-04-15) has none in
    # the 7 days before it. The benchmark has none at 1m.
    put_quotes!(gappy, [
      {~D[2025-01-15], "100"},
      {~D[2025-02-14], "120"},
      {~D[2026-01-15], "100"}
    ])

    put_quotes!(bench, [{~D[2025-01-15], "10"}, {~D[2025-04-15], "11"}, {~D[2026-01-15], "12"}])
    put_quotes!(unquoted, [{~D[2024-12-01], "70"}, {~D[2025-06-02], "75"}])

    sell!(world, gappy, quantity: "1", price: "100", date: ~D[2025-01-15])
    sell!(world, unquoted, quantity: "1", price: "70", date: ~D[2025-01-15])

    %{rows: rows} = SaleHindsight.report(today: @today, benchmark: {:security, bench})
    assert length(rows) == 2
    by_security = Map.new(rows, &{&1.security.id, &1})

    gap_row = Map.fetch!(by_security, gappy.id)

    # 1m: the security's 120 / 100 - 1 = 0.2 is kept; the benchmark has no
    # close from 2025-02-08 to 2025-02-15.
    one = span(gap_row, "1m")
    assert one.status == :incomplete
    assert one.reason == :no_benchmark_close
    assert_decimal(one.security.return, "0.2")
    assert one.benchmark == nil
    assert one.difference == nil

    three = span(gap_row, "3m")
    assert three.status == :incomplete
    assert three.reason == :no_end_close
    assert three.security == nil

    # 12m: 100 / 100 - 1 = 0 against 12 / 10 - 1 = 0.2, difference -0.2.
    twelve = span(gap_row, "12m")
    assert twelve.status == :complete
    assert_decimal(twelve.difference, "-0.2")

    # latest: the latest close is 2026-01-15's, the same as 12m's.
    assert span(gap_row, "latest").end_on == ~D[2026-01-15]

    # No close from 2025-01-08 to 2025-01-15: no start.
    unquoted_row = Map.fetch!(by_security, unquoted.id)
    assert unquoted_row.start == nil
    assert unquoted_row.start_reason == :no_start_close

    for label <- ["1m", "3m", "12m", "latest"] do
      span = span(unquoted_row, label)
      assert span.status == :incomplete, label
      assert span.reason == :no_start_close, label
    end
  end

  # User story (S2, D-8.3: every money identity at a moving rate):
  # As the operator who holds in EUR,
  # I want a USD security's span measured in EUR at each close's own rate,
  # so that a rising euro shows in what the sale missed.
  #
  # Acceptance criteria:
  # - The start close converts at the sale day's rate, the end close at its
  #   own date's rate (S1's rule); the booked USD price is shown as booked.
  test "a USD security is measured in EUR at a moving rate" do
    world = base_world(name: "Dollar")
    security = create_security!(name: "US Fund", ticker: "USF", currency: "USD")
    put_quotes!(security, [{~D[2025-01-15], "110"}, {~D[2025-02-14], "132"}])
    rate!(~D[2025-01-15], "1.1")
    rate!(~D[2025-02-14], "1.2")

    cross_trade!(world, security,
      type: "sell",
      quantity: "1",
      price: "111",
      settled: "100.9",
      gross: "100.9",
      date: ~D[2025-01-15]
    )

    %{rows: [row]} = SaleHindsight.report(today: @today)

    assert_decimal(row.price, "111")
    assert row.currency_code == "USD"

    # Start: 110 x (1 / 1.1) = 110 x 0.9090909090909090909090909090909091
    # = 100.0000000000000000000000000000000 at 34 digits; end: 132 x (1 / 1.2)
    # = 132 x 0.8333333333333333333333333333333333
    # = 110.0000000000000000000000000000000 at 34 digits; 110 / 100 - 1 =
    # 0.1 in EUR, where the USD closes moved 132 / 110 - 1 = 0.2.
    one = span(row, "1m")
    assert one.status == :complete
    assert Decimal.to_string(one.security.start.fx_rate) == "0.9090909090909090909090909090909091"
    assert Decimal.to_string(one.security.end.fx_rate) == "0.8333333333333333333333333333333333"
    assert_decimal(one.security.start.eur_value, "100")
    assert_decimal(one.security.end.eur_value, "110")
    assert_decimal(one.security.return, "0.1")
  end

  # User story (S2, D-3: one row per sale booking, filtered):
  # As the agent reading the sales of one portfolio, security or period,
  # I want the rows narrowed by portfolio, security and sale date, newest
  # first, and capped,
  # so that one call answers the question asked and never the whole ledger.
  #
  # Acceptance criteria:
  # - Two sales of one security are two rows; a buy is no row.
  # - portfolio_id, security_id, from and to (both inclusive) narrow the rows.
  # - limit caps the rows, newest first, and truncated says more matched.
  test "one row per sale booking, filtered and capped" do
    %{world: world, security: security, sale: first} = sold_world()
    other_world = base_world(name: "Other")
    other = create_security!(name: "Other Fund", ticker: "OTH", currency: "EUR")
    second = sell!(world, security, quantity: "2", price: "105", date: ~D[2025-03-03])
    third = sell!(other_world, other, quantity: "1", price: "10", date: ~D[2025-05-05])

    ids = fn opts ->
      Enum.map(SaleHindsight.report([today: @today] ++ opts).rows, & &1.sale_id)
    end

    assert ids.([]) == [third.id, second.id, first.id]
    assert ids.(portfolio_id: world.portfolio.id) == [second.id, first.id]
    assert ids.(security_id: other.id) == [third.id]
    assert ids.(from: ~D[2025-03-03], to: ~D[2025-05-04]) == [second.id]
    assert ids.(to: ~D[2025-01-15]) == [first.id]

    capped = SaleHindsight.report(today: @today, limit: 2)
    assert Enum.map(capped.rows, & &1.sale_id) == [third.id, second.id]
    assert capped.truncated == true
    assert capped.limit == 2
  end

  # User story (S2, AGENTS.md: every metric states its computation basis):
  # As the agent checking a figure,
  # I want the basis in the result: input series, window, reference, gaps,
  # and that distributions after a sale are not counted,
  # so that I read the figure for what it is.
  test "the computation basis names the series, the windows, the reference and the gaps" do
    bench = benchmark!("Basis Index", "BAS")

    for {benchmark, reference} <- [
          {nil, "none"},
          {{:rate, d("0.05")}, "0.05"},
          {{:security, bench}, "security #{bench.id} (EUR)"}
        ] do
      basis = SaleHindsight.report(today: @today, benchmark: benchmark).computation_basis

      for key <- [:input_series, :window, :reference, :gaps, :price_only, :sales, :booked_price] do
        assert is_binary(Map.fetch!(basis, key)), "#{key} missing"
      end

      assert basis.reference =~ reference
      assert basis.price_only =~ "understated"
      assert basis.window =~ "pending"
      assert basis.gaps =~ "7 calendar days"
    end
  end
end
