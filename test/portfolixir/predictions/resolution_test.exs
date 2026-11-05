defmodule Portfolixir.Predictions.ResolutionTest do
  # ADR-0055 §3 (Sprint 25 plan, Lane F, F2; risk tier: money math). A
  # prediction is resolved at read, from stored closes in EUR, through S1's
  # window return (`Portfolixir.Portfolios.Performance.WindowReturn`), so
  # the resolution and the sale hindsight read cannot drift. Nothing is
  # stored. Every figure below is an exact Decimal derived by hand in the
  # comments, at Decimal's default context (34 significant digits, half-up),
  # and a USD security is resolved at a moving rate (the plan's D-8.3).
  #
  # The fixture's calendar: every call is made on Wednesday 2026-03-04 at
  # 15:00 UTC (the test clock seam of `create_prediction/3`), so its start
  # closes stand for 2026-03-04, the day made (ADR-0055, amendment of
  # 2026-11-05: the last close on or before the day made), and it resolves
  # on Monday 2026-06-01. The reads pass `today: 2026-11-05`, long past the
  # 7 days a resolution may wait for its end close.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [create_security!: 1, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Clock
  alias Portfolixir.Fx
  alias Portfolixir.Predictions
  alias Portfolixir.Predictions.Resolution

  @made_at ~U[2026-03-04 15:00:00.000000Z]
  @start_on ~D[2026-03-04]
  @resolves_on ~D[2026-06-01]
  @today ~D[2026-11-05]

  defp d(value), do: Decimal.new(value)

  defp assert_decimal(actual, expected) do
    assert %Decimal{} = actual
    assert Decimal.equal?(actual, d(expected)), "expected #{expected}, got #{inspect(actual)}"
  end

  defp security!(name, currency \\ "EUR"),
    do: create_security!(name: name, ticker: nil, currency: currency, asset_class: "equity")

  defp benchmark!(name, currency \\ "EUR") do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        currency_code: currency,
        asset_class: "etf",
        is_benchmark: true
      })

    security
  end

  defp rate!(date, rate) do
    {:ok, 1} =
      Fx.upsert_many([
        %{base_currency: "EUR", quote_currency: "USD", date: date, rate: rate, source: "manual"}
      ])
  end

  defp predict!(security, direction, benchmark, extra \\ %{}, made_at \\ @made_at) do
    attrs =
      Map.merge(
        %{
          "security_id" => security.id,
          "direction" => direction,
          "probability" => "0.70",
          "benchmark" => benchmark,
          "resolves_on" => Date.to_iso8601(@resolves_on),
          "model" => "example-model-1"
        },
        extra
      )

    {:ok, prediction} =
      Predictions.create_prediction(Actor.api_token_rw("research-agent"), attrs, now: made_at)

    prediction
  end

  defp resolve(prediction, today \\ @today), do: Predictions.resolve(prediction, today: today)

  # User story (F2, ADR-0055 §3 "Start" and "Outcome", as amended on
  # 2026-11-05):
  # As the operator's agent coming back to an absolute call,
  # I want it resolved from the last close on or before the day I made it
  # to the last close on or before its date,
  # so that no call scores a move it had already seen.
  #
  # Acceptance criteria:
  # - The start close is the made day's own close when one is stored; a
  #   close dated the day BEFORE the made day exists and is not used.
  # - `rate:0` is the absolute call: the benchmark return is exactly 0 and
  #   the excess is the security's return.
  # - The resolution names both closes, their dates, the dates they stand
  #   for, both returns and the excess.
  test "an absolute outperform call hits, measured from the made day's close" do
    security = security!("Rising Co.")

    # 03-04 is the made day and the start; the day before's 200 must not be
    # used (from it the return would be 110 / 200 - 1 = -0.45, a miss).
    put_quotes!(security, [
      {~D[2026-03-03], "200"},
      {~D[2026-03-04], "100"},
      {~D[2026-06-01], "110"}
    ])

    prediction = predict!(security, "outperform", "rate:0")

    assert %Resolution{} = resolution = resolve(prediction)
    assert resolution.status == :resolved
    assert resolution.outcome == :hit
    assert resolution.reason == nil
    assert resolution.start_on == @start_on
    assert resolution.end_on == @resolves_on

    # 110 / 100 - 1 = 0.1; rate:0 returns exactly 0; excess 0.1 - 0 = 0.1.
    assert resolution.security.start.stands_for == @start_on
    assert resolution.security.start.date == ~D[2026-03-04]
    assert_decimal(resolution.security.start.close, "100")
    assert_decimal(resolution.security.start.eur_value, "100")
    assert resolution.security.end.stands_for == @resolves_on
    assert resolution.security.end.date == ~D[2026-06-01]
    assert_decimal(resolution.security.end.close, "110")
    assert_decimal(resolution.security.return, "0.1")

    # 2026-03-04 -> 2026-06-01: 27 + 30 + 31 + 1 = 89 days.
    assert resolution.benchmark.kind == :rate
    assert_decimal(resolution.benchmark.rate, "0")
    assert resolution.benchmark.from == @start_on
    assert resolution.benchmark.to == @resolves_on
    assert resolution.benchmark.days == 89
    assert_decimal(resolution.benchmark.return, "0")

    assert_decimal(resolution.excess, "0.1")
  end

  # User story (the Sprint 25 closing act's money lens, reproduced; ADR-0055
  # amendment of 2026-11-05, §1):
  # As the operator scoring an agent that writes after the evening sync,
  # I want a call made after the day's close measured from that close,
  # so that the jump it saw before writing is not scored as its foresight.
  #
  # Acceptance criteria:
  # - Closes Monday 100 and Tuesday 110, a call made Tuesday 22:00 UTC,
  #   outperform rate:0, the end close 110: measured from Tuesday's 110 the
  #   return is exactly 0, a miss (from Monday's 100 it was +0.1, a hit).
  test "a call made after the day's close starts from that close" do
    security = security!("Evening Co.")

    put_quotes!(security, [
      {~D[2026-03-02], "100"},
      {~D[2026-03-03], "110"},
      {~D[2026-06-01], "110"}
    ])

    resolution =
      resolve(predict!(security, "outperform", "rate:0", %{}, ~U[2026-03-03 22:00:00.000000Z]))

    # 110 / 110 - 1 = 0; excess 0 - 0 = 0: a miss.
    assert resolution.start_on == ~D[2026-03-03]
    assert resolution.security.start.date == ~D[2026-03-03]
    assert_decimal(resolution.security.start.close, "110")
    assert_decimal(resolution.security.return, "0")
    assert_decimal(resolution.excess, "0")
    assert {resolution.status, resolution.outcome} == {:resolved, :miss}
  end

  # User story (F2, ADR-0055 §3 "Start" and "Staleness", as amended): a
  # call made on a day without a close (a Saturday) starts from the last
  # close before it within 7 days, never from a close after it; with none
  # in those 7 days it is unresolved.
  #
  # Acceptance criteria:
  # - Made Saturday 2026-03-07: Friday 03-06's close is the start, Monday
  #   03-09's is never used.
  # - With only a close dated 02-27 (eight days before 03-07) before the
  #   made day, the call is no_start_close, even with a close after it.
  test "a made day without a close starts from the last close before it, within 7 days" do
    saturday = ~U[2026-03-07 12:00:00.000000Z]
    security = security!("Weekend Co.")

    # From Monday's 300 the return would be 110 / 300 - 1, a miss.
    put_quotes!(security, [
      {~D[2026-03-06], "100"},
      {~D[2026-03-09], "300"},
      {~D[2026-06-01], "110"}
    ])

    resolution = resolve(predict!(security, "outperform", "rate:0", %{}, saturday))

    # 110 / 100 - 1 = 0.1: a hit.
    assert resolution.start_on == ~D[2026-03-07]
    assert resolution.security.start.stands_for == ~D[2026-03-07]
    assert resolution.security.start.date == ~D[2026-03-06]
    assert_decimal(resolution.security.return, "0.1")
    assert {resolution.status, resolution.outcome} == {:resolved, :hit}

    stale = security!("Fresh Listing Co.")

    # 02-27 + 8 = 03-07 (February 2026 has 28 days): stale. 03-09 is after
    # the made day. Nothing stands for 03-07.
    put_quotes!(stale, [
      {~D[2026-02-27], "100"},
      {~D[2026-03-09], "100"},
      {~D[2026-06-01], "110"}
    ])

    resolution = resolve(predict!(stale, "outperform", "rate:0", %{}, saturday))

    assert resolution.status == :unresolved
    assert resolution.reason == :no_start_close
    assert resolution.outcome == nil
    assert resolution.excess == nil
    assert resolution.security == nil
    assert resolution.benchmark == nil
  end

  # User story (F2, ADR-0055 §3 "Outcome"):
  # As the agent scored on its calls,
  # I want a hit and a miss read the same way in both directions,
  # so that the score counts what the prices did, not how a call was worded.
  #
  # Acceptance criteria:
  # - outperform hits iff excess > 0, underperform iff excess < 0.
  test "hit and miss in both directions" do
    up = security!("Up Co.")
    down = security!("Down Co.")

    # Up: 100 -> 110 = +0.1. Down: 100 -> 90 = 90 / 100 - 1 = -0.1.
    put_quotes!(up, [{~D[2026-03-03], "100"}, {~D[2026-06-01], "110"}])
    put_quotes!(down, [{~D[2026-03-03], "100"}, {~D[2026-06-01], "90"}])

    for {security, direction, outcome, excess} <- [
          {up, "outperform", :hit, "0.1"},
          {up, "underperform", :miss, "0.1"},
          {down, "outperform", :miss, "-0.1"},
          {down, "underperform", :hit, "-0.1"}
        ] do
      resolution = resolve(predict!(security, direction, "rate:0"))

      assert {resolution.status, resolution.outcome} == {:resolved, outcome},
             "#{security.name} #{direction}"

      assert_decimal(resolution.excess, excess)
    end
  end

  # User story (F2, ADR-0055 §3 "Outcome"): an excess of exactly 0 is a
  # miss for both directions, against a flat absolute call and against a
  # security benchmark that moved exactly as much.
  test "an excess of exactly 0 is a miss both ways" do
    flat = security!("Flat Co.")
    put_quotes!(flat, [{~D[2026-03-03], "100"}, {~D[2026-06-01], "100"}])

    # 100 / 100 - 1 = 0; rate:0 is 0; excess 0.
    for direction <- ["outperform", "underperform"] do
      resolution = resolve(predict!(flat, direction, "rate:0"))
      assert {resolution.status, resolution.outcome} == {:resolved, :miss}
      assert_decimal(resolution.excess, "0")
    end

    security = security!("Tracker Co.")
    index = benchmark!("Tracked Index")
    put_quotes!(security, [{~D[2026-03-03], "100"}, {~D[2026-06-01], "110"}])
    put_quotes!(index, [{~D[2026-03-03], "50"}, {~D[2026-06-01], "55"}])

    # 110 / 100 - 1 = 0.1 and 55 / 50 - 1 = 0.1; excess 0.1 - 0.1 = 0.
    for direction <- ["outperform", "underperform"] do
      resolution = resolve(predict!(security, direction, "security:#{index.id}"))
      assert {resolution.status, resolution.outcome} == {:resolved, :miss}
      assert_decimal(resolution.security.return, "0.1")
      assert_decimal(resolution.benchmark.return, "0.1")
      assert_decimal(resolution.excess, "0")
    end
  end

  # User story (F2, ADR-0055 §3 "Benchmark return"):
  # As the agent whose call is scored against the money's alternative,
  # I want a fixed rate compounded by Benchmark.daily_rate_factor/1 over
  # the calendar days between the two dates the security's closes stand
  # for,
  # so that `rate:0.05` reads as it does on the benchmark comparison.
  #
  # Acceptance criteria:
  # - The days run from start.stands_for (2026-03-04) to end.stands_for
  #   (2026-06-01): 89 days, not counted from the close dates.
  test "a nonzero rate benchmark compounds the daily factor over the stand-for days" do
    security = security!("Slow Co.")

    # The end close is dated Friday 05-29 and stands for Monday 06-01: the
    # rate still runs to 06-01.
    put_quotes!(security, [{~D[2026-03-03], "100"}, {~D[2026-05-29], "101"}])

    resolution = resolve(predict!(security, "outperform", "rate:0.05"))

    # 2026-03-04 -> 2026-06-01: 27 days to 03-31, 30 in April, 31 in May
    # and 1 in June = 89 days. Benchmark.daily_rate_factor(0.05) is
    # 1.0001336806171135 (S1's test pins it); multiplied into 1 eighty-nine
    # times, each product rounded to 34 significant digits half-up (Python
    # decimal, prec 34, ROUND_HALF_UP), it is
    # 1.011967827909202849631225425164531, so the rate's return is
    # 0.011967827909202849631225425164531.
    # Security: 101 / 100 - 1 = 0.01 (the 03-03 close stands for 03-04).
    # Excess: 0.01 - 0.011967827909202849631225425164531
    #       = -0.001967827909202849631225425164531 < 0: outperform misses.
    assert resolution.security.end.date == ~D[2026-05-29]
    assert resolution.security.end.stands_for == @resolves_on
    assert resolution.benchmark.kind == :rate
    assert resolution.benchmark.days == 89
    assert Decimal.to_string(resolution.benchmark.return) == "0.011967827909202849631225425164531"
    assert_decimal(resolution.security.return, "0.01")
    assert Decimal.to_string(resolution.excess) == "-0.001967827909202849631225425164531"
    assert {resolution.status, resolution.outcome} == {:resolved, :miss}

    underperform = resolve(predict!(security, "underperform", "rate:0.05"))
    assert {underperform.status, underperform.outcome} == {:resolved, :hit}
  end

  # User story (F2, ADR-0055 §3 "Benchmark return", a security benchmark):
  # As the agent calling a stock against an index,
  # I want the index measured by the same rule and the same dates,
  # so that both sides of the excess are like for like.
  test "a security benchmark by the same rule and the same dates" do
    security = security!("Growth Co.")
    index = benchmark!("Broad Index")

    put_quotes!(security, [{~D[2026-03-03], "100"}, {~D[2026-06-01], "120"}])
    # The index's start close (Friday 02-27, five days before) stands for
    # the made day 03-04 too; its close of 03-09, after the made day, is
    # never the start.
    put_quotes!(index, [
      {~D[2026-02-27], "200"},
      {~D[2026-03-09], "400"},
      {~D[2026-06-01], "230"}
    ])

    resolution = resolve(predict!(security, "outperform", "security:#{index.id}"))

    # Security: 120 / 100 - 1 = 0.2. Index: 230 / 200 - 1 = 0.15.
    # Excess: 0.2 - 0.15 = 0.05 > 0: hit.
    assert resolution.benchmark.kind == :security
    assert resolution.benchmark.security_id == index.id
    assert resolution.benchmark.currency_code == "EUR"
    assert resolution.benchmark.start.stands_for == @start_on
    assert resolution.benchmark.start.date == ~D[2026-02-27]
    assert_decimal(resolution.benchmark.start.close, "200")
    assert resolution.benchmark.end.date == ~D[2026-06-01]
    assert_decimal(resolution.benchmark.end.close, "230")
    assert_decimal(resolution.benchmark.return, "0.15")
    assert_decimal(resolution.security.return, "0.2")
    assert_decimal(resolution.excess, "0.05")
    assert {resolution.status, resolution.outcome} == {:resolved, :hit}
  end

  # User story (F2, ADR-0055 §3 "Currency"; the plan's D-8.3):
  # As the operator who holds a USD security in EUR,
  # I want its call resolved in EUR at each close's own date's rate,
  # so that a rising euro shows as the loss it is to me.
  #
  # Acceptance criteria:
  # - A +20 % USD move while EUR/USD rises from 1.25 to 1.60 reads -6.25 %
  #   in EUR, so an absolute outperform call misses; one rate for both
  #   ends would have read +20 % and a hit.
  test "a USD security at a moving rate is resolved in EUR" do
    security = security!("US Growth Co.", "USD")
    put_quotes!(security, [{~D[2026-03-03], "100"}, {~D[2026-06-01], "120"}])
    rate!(~D[2026-03-03], "1.25")
    rate!(~D[2026-06-01], "1.60")

    resolution = resolve(predict!(security, "outperform", "rate:0"))

    # Start: 100 USD x (1 / 1.25 = 0.8) = 80 EUR.
    # End: 120 USD x (1 / 1.60 = 0.625) = 75 EUR.
    # Return: 75 / 80 - 1 = -0.0625; excess -0.0625 < 0: outperform misses.
    assert resolution.security.currency_code == "USD"
    assert_decimal(resolution.security.start.fx_rate, "0.8")
    assert_decimal(resolution.security.start.eur_value, "80")
    assert_decimal(resolution.security.end.fx_rate, "0.625")
    assert_decimal(resolution.security.end.eur_value, "75")
    assert_decimal(resolution.security.return, "-0.0625")
    assert_decimal(resolution.excess, "-0.0625")
    assert {resolution.status, resolution.outcome} == {:resolved, :miss}
  end

  # User story (the Sprint 25 closing act's money lens, reproduced):
  # As the agent calling a USD stock against a USD index,
  # I want a call whose two sides moved exactly alike to read excess 0,
  # so that it is the miss ADR-0055 §3 says it is, not a 1E-33 hit.
  test "identical moves in one non-EUR currency: excess exactly 0, a miss" do
    stock = security!("US Stock Co.", "USD")
    index = benchmark!("US Broad Index", "USD")
    put_quotes!(stock, [{~D[2026-03-04], "123"}, {~D[2026-06-01], "135.3"}])
    put_quotes!(index, [{~D[2026-03-04], "17"}, {~D[2026-06-01], "18.7"}])
    rate!(~D[2026-03-04], "1.07")
    rate!(~D[2026-06-01], "1.13")

    # Both returns: (end x 1.07) / (start x 1.13) - 1, one division of
    # exact products = 0.041592920353982300884955752212389 (window return
    # test); excess 0.
    resolution = resolve(predict!(stock, "outperform", "security:#{index.id}"))
    assert Decimal.to_string(resolution.security.return) == "0.041592920353982300884955752212389"
    assert Decimal.to_string(resolution.benchmark.return) == "0.041592920353982300884955752212389"
    assert_decimal(resolution.excess, "0")
    assert {resolution.status, resolution.outcome} == {:resolved, :miss}
  end

  # User story (F2, ADR-0055 §3 "Staleness"; D-10 condition 4):
  # As the agent reading its score,
  # I want a call without a usable close or rate named unresolved with its
  # reason,
  # so that nothing is ever estimated into my score.
  #
  # Acceptance criteria:
  # - no_end_close: the last close is more than 7 days before resolves_on.
  # - no_benchmark_close: the benchmark security has no close standing for
  #   the start or for the end; the security's side is still named.
  # - no_fx_rate: the security or the benchmark has no stored rate path to
  #   EUR.
  describe "unresolved, with its reason" do
    test "no_end_close" do
      security = security!("Halted Co.")
      # 05-24 is eight days before 06-01: stale.
      put_quotes!(security, [{~D[2026-03-03], "100"}, {~D[2026-05-24], "110"}])

      resolution = resolve(predict!(security, "outperform", "rate:0"))
      assert {resolution.status, resolution.reason} == {:unresolved, :no_end_close}
      assert resolution.outcome == nil
      assert resolution.excess == nil
    end

    test "no_benchmark_close, at the start and at the end" do
      security = security!("Priced Co.")
      put_quotes!(security, [{~D[2026-03-03], "100"}, {~D[2026-06-01], "110"}])

      no_start = benchmark!("Late Index")
      # Its only close before the made day is nine days before 03-04.
      put_quotes!(no_start, [{~D[2026-02-23], "50"}, {~D[2026-06-01], "55"}])

      no_end = benchmark!("Closed Index")
      put_quotes!(no_end, [{~D[2026-03-03], "50"}, {~D[2026-05-24], "55"}])

      for index <- [no_start, no_end] do
        resolution = resolve(predict!(security, "outperform", "security:#{index.id}"))
        assert {resolution.status, resolution.reason} == {:unresolved, :no_benchmark_close}
        assert resolution.outcome == nil
        assert resolution.excess == nil
        assert resolution.benchmark == nil
        # The security's side resolved and is named.
        assert_decimal(resolution.security.return, "0.1")
      end
    end

    test "no_fx_rate, on the security's side and on the benchmark's" do
      # No EUR/USD rate is stored at all.
      us_security = security!("Unpriced US Co.", "USD")
      put_quotes!(us_security, [{~D[2026-03-03], "100"}, {~D[2026-06-01], "110"}])

      resolution = resolve(predict!(us_security, "outperform", "rate:0"))
      assert {resolution.status, resolution.reason} == {:unresolved, :no_fx_rate}
      assert resolution.security == nil

      security = security!("Euro Co.")
      us_index = benchmark!("US Index", "USD")
      put_quotes!(security, [{~D[2026-03-03], "100"}, {~D[2026-06-01], "110"}])
      put_quotes!(us_index, [{~D[2026-03-03], "100"}, {~D[2026-06-01], "110"}])

      resolution = resolve(predict!(security, "outperform", "security:#{us_index.id}"))
      assert {resolution.status, resolution.reason} == {:unresolved, :no_fx_rate}
      assert_decimal(resolution.security.return, "0.1")
      assert resolution.benchmark == nil
    end

    # The security's own reasons come first, in S1's order (start close, end
    # close, rate), then the benchmark's.
    test "the security's reason comes before the benchmark's" do
      security = security!("Silent Co.")
      index = benchmark!("Silent Index")

      resolution = resolve(predict!(security, "outperform", "security:#{index.id}"))
      assert {resolution.status, resolution.reason} == {:unresolved, :no_start_close}
    end
  end

  # User story (F2, ADR-0055 §3 "open until resolves_on has passed"):
  # As the agent asking about a call whose date has not passed,
  # I want it read `open`, with nothing computed,
  # so that a call is never scored on the day it resolves, before that
  # day's close can be stored.
  #
  # Acceptance criteria:
  # - open while today is on or before resolves_on; resolved from the day
  #   after once the close of resolves_on is stored (finality, below).
  # - The default today is the instance's calendar day,
  #   Portfolixir.Clock.today/0 (E25 S6, G08: one "today" for every check).
  test "open until resolves_on has passed" do
    security = security!("Waiting Co.")
    put_quotes!(security, [{~D[2026-03-03], "100"}, {~D[2026-06-01], "110"}])
    prediction = predict!(security, "outperform", "rate:0")

    for today <- [~D[2026-03-04], ~D[2026-05-31], @resolves_on] do
      resolution = resolve(prediction, today)

      assert %Resolution{
               status: :open,
               outcome: nil,
               reason: nil,
               security: nil,
               benchmark: nil,
               excess: nil
             } = resolution

      assert resolution.start_on == @start_on
      assert resolution.end_on == @resolves_on
    end

    assert resolve(prediction, ~D[2026-06-02]).status == :resolved

    # Without today:, the instance's calendar day decides: a call due today
    # is open, one due yesterday waits for its end close (open), one due
    # eight days ago has passed the wait (and, with no close, is
    # unresolved).
    today = Clock.today()
    made_at = DateTime.new!(Date.add(today, -30), ~T[12:00:00.000000], "Etc/UTC")

    due = fn resolves_on ->
      {:ok, prediction} =
        Predictions.create_prediction(
          Actor.owner_ui(),
          %{
            "security_id" => security!("Clocked Co.").id,
            "direction" => "outperform",
            "probability" => "0.60",
            "benchmark" => "rate:0",
            "resolves_on" => Date.to_iso8601(resolves_on)
          },
          now: made_at
        )

      prediction
    end

    assert Predictions.resolve(due.(today)).status == :open
    assert Predictions.resolve(due.(Date.add(today, -1))).status == :open
    assert Predictions.resolve(due.(Date.add(today, -8))).status == :unresolved
  end

  # User story (the Sprint 25 closing act's UAT persona, reproduced;
  # ADR-0055 amendment of 2026-11-05, §2, finality):
  # As the operator quoting an agent's score,
  # I want a call to stay open after its date until its end close is in,
  # so that a resolved call never flips when a late close arrives.
  #
  # Acceptance criteria:
  # - resolves_on has passed and only an older close is stored: open (it
  #   read "resolved hit" from Friday's close before the amendment).
  # - Once a close dated resolves_on is stored: resolved, from that close.
  # - A Saturday resolves_on with Friday's and Monday's closes stored:
  #   resolved from Friday's; Monday's is the evidence only.
  # - A security benchmark waits for its own close on or after resolves_on.
  # - 7 days after resolves_on the wait ends: from resolves_on + 8 a call
  #   resolves with what is stored, or reads unresolved with its reason.
  describe "finality: a resolution waits for its end close" do
    test "open until a close dated resolves_on is stored, then resolved from it" do
      security = security!("Late Close Co.")

      # Friday 05-29's 110 stands for Monday 06-01 (three days before).
      put_quotes!(security, [{~D[2026-03-04], "100"}, {~D[2026-05-29], "110"}])
      prediction = predict!(security, "outperform", "rate:0")

      for today <- [~D[2026-06-02], ~D[2026-06-05]] do
        assert %Resolution{status: :open, outcome: nil, security: nil, excess: nil} =
                 resolve(prediction, today)
      end

      put_quotes!(security, [{~D[2026-06-01], "99"}])

      # 99 / 100 - 1 = -0.01 < 0: the outperform call misses (from Friday's
      # 110 it would have read +0.1, a hit, and flipped).
      resolution = resolve(prediction, ~D[2026-06-02])
      assert {resolution.status, resolution.outcome} == {:resolved, :miss}
      assert resolution.security.end.date == ~D[2026-06-01]
      assert_decimal(resolution.security.return, "-0.01")
    end

    test "a Saturday resolves_on resolves from Friday's close, Monday's is evidence only" do
      security = security!("Saturday Co.")

      put_quotes!(security, [
        {~D[2026-03-04], "100"},
        {~D[2026-05-29], "110"},
        {~D[2026-06-01], "50"}
      ])

      prediction = predict!(security, "outperform", "rate:0", %{"resolves_on" => "2026-05-30"})

      # Read on Tuesday 06-02: Monday's close is stored, a close dated on or
      # after 05-30, the evidence that the data of 05-30 is in.
      resolution = resolve(prediction, ~D[2026-06-02])

      # From Friday's 110: 110 / 100 - 1 = 0.1, a hit; Monday's 50 is not
      # the end close (it is dated after 05-30).
      assert {resolution.status, resolution.outcome} == {:resolved, :hit}
      assert resolution.security.end.stands_for == ~D[2026-05-30]
      assert resolution.security.end.date == ~D[2026-05-29]
      assert_decimal(resolution.security.return, "0.1")

      without_monday = security!("Saturday Waiting Co.")
      put_quotes!(without_monday, [{~D[2026-03-04], "100"}, {~D[2026-05-29], "110"}])

      waiting =
        predict!(without_monday, "outperform", "rate:0", %{"resolves_on" => "2026-05-30"})

      assert resolve(waiting, ~D[2026-06-02]).status == :open
    end

    test "a security benchmark waits for its own close on or after resolves_on" do
      security = security!("Prompt Co.")
      index = benchmark!("Slow Index")
      put_quotes!(security, [{~D[2026-03-04], "100"}, {~D[2026-06-01], "120"}])
      put_quotes!(index, [{~D[2026-03-04], "200"}, {~D[2026-05-29], "230"}])

      prediction = predict!(security, "outperform", "security:#{index.id}")
      assert resolve(prediction, ~D[2026-06-02]).status == :open

      put_quotes!(index, [{~D[2026-06-01], "250"}])

      # Security 120 / 100 - 1 = 0.2; index 250 / 200 - 1 = 0.25; excess
      # 0.2 - 0.25 = -0.05 < 0: a miss.
      resolution = resolve(prediction, ~D[2026-06-02])
      assert {resolution.status, resolution.outcome} == {:resolved, :miss}
      assert_decimal(resolution.benchmark.return, "0.25")
      assert_decimal(resolution.excess, "-0.05")
    end

    test "seven days after resolves_on the wait ends" do
      older = security!("Stopped Co.")
      put_quotes!(older, [{~D[2026-03-04], "100"}, {~D[2026-05-29], "110"}])
      with_older = predict!(older, "outperform", "rate:0")

      silent = security!("Silent After Co.")
      put_quotes!(silent, [{~D[2026-03-04], "100"}])
      without_end = predict!(silent, "outperform", "rate:0")

      # 06-08 is resolves_on + 7: still waiting.
      assert resolve(with_older, ~D[2026-06-08]).status == :open
      assert resolve(without_end, ~D[2026-06-08]).status == :open

      # 06-09 is resolves_on + 8: resolved from Friday's close (110 / 100 -
      # 1 = 0.1, a hit), or unresolved with its reason.
      resolution = resolve(with_older, ~D[2026-06-09])
      assert {resolution.status, resolution.outcome} == {:resolved, :hit}
      assert resolution.security.end.date == ~D[2026-05-29]

      unresolved = resolve(without_end, ~D[2026-06-09])
      assert {unresolved.status, unresolved.reason} == {:unresolved, :no_end_close}
    end
  end

  # User story (F2, ADR-0055 §5 "filtered by ... status ... and due_before"):
  # As the agent coming back to its calls,
  # I want to list them by their derived status and to ask which open calls
  # come due by a date,
  # so that I find the calls to look at without resolving each myself.
  #
  # Acceptance criteria:
  # - list_with_resolution/2 answers each prediction with its resolution,
  #   newest first, under the storage filters of list_predictions/2.
  # - `status` filters by the derived status; an unknown status matches
  #   nothing and mints no atom; `limit` counts what the status kept.
  # - `due_before` is the due query: OPEN predictions whose resolves_on is
  #   on or before the date, so a call already resolved is not due, and a
  #   call past its date that still waits for its end close (ADR-0055
  #   amendment of 2026-11-05, §2) is.
  # - `resolves_from` and `resolves_to` bound resolves_on, both inclusive.
  describe "the status filter and the due query" do
    setup do
      priced = security!("Priced Co.")
      put_quotes!(priced, [{~D[2026-03-03], "100"}, {~D[2026-06-01], "110"}])
      unpriced = security!("Unpriced Co.")

      resolved = predict!(priced, "outperform", "rate:0")
      unresolved = predict!(unpriced, "outperform", "rate:0")
      # Today (2026-11-05) is its date: still open.
      due_today = predict!(priced, "outperform", "rate:0", %{"resolves_on" => "2026-11-05"})
      due_soon = predict!(priced, "underperform", "rate:0", %{"resolves_on" => "2026-12-01"})
      later = predict!(priced, "outperform", "rate:0", %{"resolves_on" => "2027-03-01"})
      # Past its date four days ago, no close since 06-01: waiting, open.
      awaiting = predict!(priced, "outperform", "rate:0", %{"resolves_on" => "2026-11-01"})

      %{
        awaiting: awaiting,
        resolved: resolved,
        unresolved: unresolved,
        due_today: due_today,
        due_soon: due_soon,
        later: later
      }
    end

    test "by status, newest first, each with its resolution", ctx do
      list = fn filters -> Predictions.list_with_resolution(filters, today: @today) end
      ids = fn filters -> filters |> list.() |> Enum.map(& &1.prediction.id) end

      assert [%{prediction: %{}, resolution: %Resolution{}} | _] = list.([])

      assert ids.([]) == [
               ctx.awaiting.id,
               ctx.later.id,
               ctx.due_soon.id,
               ctx.due_today.id,
               ctx.unresolved.id,
               ctx.resolved.id
             ]

      assert ids.(status: :open) == [
               ctx.awaiting.id,
               ctx.later.id,
               ctx.due_soon.id,
               ctx.due_today.id
             ]

      assert ids.(status: "resolved") == [ctx.resolved.id]
      assert ids.(status: :unresolved) == [ctx.unresolved.id]
      assert ids.(status: "nobody_status_zz") == []
      assert_raise ArgumentError, fn -> String.to_existing_atom("nobody_status_zz") end

      # The limit counts after the status: the one resolved call is found
      # behind four newer open ones.
      assert ids.(status: :resolved, limit: 1) == [ctx.resolved.id]
      assert ids.(status: :open, limit: 2) == [ctx.awaiting.id, ctx.later.id]

      assert [%{resolution: %Resolution{status: :resolved, outcome: :hit}}] =
               list.(status: :resolved)

      assert [%{resolution: %Resolution{status: :unresolved, reason: :no_start_close}}] =
               list.(status: :unresolved)
    end

    test "due_before is the open calls due on or before the date", ctx do
      ids = fn filters ->
        filters |> Predictions.list_predictions(today: @today) |> Enum.map(& &1.id)
      end

      # The resolved and the unresolved call resolve on 2026-06-01, before
      # the date, and are past it and its wait: not due. The call of
      # 2026-11-01 waits for its end close: due.
      assert ids.(due_before: ~D[2026-12-01]) ==
               [ctx.awaiting.id, ctx.due_soon.id, ctx.due_today.id]

      assert ids.(due_before: ~D[2026-11-05]) == [ctx.awaiting.id, ctx.due_today.id]
      assert ids.(due_before: ~D[2026-11-04]) == [ctx.awaiting.id]
      assert ids.(due_before: ~D[2026-10-31]) == []

      # The same through list_with_resolution/2, with the status beside it;
      # a status other than open beside due_before matches nothing.
      assert [_, _, _] =
               entries =
               Predictions.list_with_resolution([due_before: ~D[2026-12-01]], today: @today)

      assert Enum.all?(entries, &(&1.resolution.status == :open))

      assert Predictions.list_with_resolution([due_before: ~D[2026-12-01], status: :resolved],
               today: @today
             ) == []

      # Eight days after 11-05 both waits have ended (no close since 06-01:
      # unresolved); only the call due 12-01 is still due.
      assert Predictions.list_predictions([due_before: ~D[2026-12-01]], today: ~D[2026-11-13])
             |> Enum.map(& &1.id) == [ctx.due_soon.id]
    end

    test "resolves_from and resolves_to bound resolves_on, inclusive", ctx do
      ids = fn filters -> filters |> Predictions.list_predictions() |> Enum.map(& &1.id) end

      assert ids.(resolves_from: ~D[2026-11-05], resolves_to: ~D[2026-12-01]) ==
               [ctx.due_soon.id, ctx.due_today.id]

      assert ids.(resolves_to: ~D[2026-06-01]) == [ctx.unresolved.id, ctx.resolved.id]
      assert ids.(resolves_from: ~D[2027-03-01]) == [ctx.later.id]
      assert ids.(resolves_from: ~D[2027-03-02]) == []
    end
  end
end
