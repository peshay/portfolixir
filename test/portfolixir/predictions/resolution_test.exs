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
  # closes stand for Tuesday 2026-03-03, the day before the day made, and it
  # resolves on Monday 2026-06-01. The reads pass `today: 2026-11-05`.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [create_security!: 1, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Clock
  alias Portfolixir.Fx
  alias Portfolixir.Predictions
  alias Portfolixir.Predictions.Resolution

  @made_at ~U[2026-03-04 15:00:00.000000Z]
  @start_on ~D[2026-03-03]
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

  defp predict!(security, direction, benchmark, extra \\ %{}) do
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
      Predictions.create_prediction(Actor.api_token_rw("research-agent"), attrs, now: @made_at)

    prediction
  end

  defp resolve(prediction, today \\ @today), do: Predictions.resolve(prediction, today: today)

  # User story (F2, ADR-0055 §3 "Start" and "Outcome"):
  # As the operator's agent coming back to an absolute call,
  # I want it resolved from the last close strictly before the day I made
  # it to the last close on or before its date,
  # so that no call is measured from a close it could have seen coming.
  #
  # Acceptance criteria:
  # - The start close stands for the day before the UTC day of made_at; a
  #   close dated ON the made day exists and is not used.
  # - `rate:0` is the absolute call: the benchmark return is exactly 0 and
  #   the excess is the security's return.
  # - The resolution names both closes, their dates, the dates they stand
  #   for, both returns and the excess.
  test "an absolute outperform call hits, measured from the close before the day made" do
    security = security!("Rising Co.")

    # 03-03 is the start; the made day's 200 must not be used (from it the
    # return would be 110 / 200 - 1 = -0.45 and the call would miss).
    put_quotes!(security, [
      {~D[2026-03-03], "100"},
      {~D[2026-03-04], "200"},
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
    assert resolution.security.start.date == ~D[2026-03-03]
    assert_decimal(resolution.security.start.close, "100")
    assert_decimal(resolution.security.start.eur_value, "100")
    assert resolution.security.end.stands_for == @resolves_on
    assert resolution.security.end.date == ~D[2026-06-01]
    assert_decimal(resolution.security.end.close, "110")
    assert_decimal(resolution.security.return, "0.1")

    assert resolution.benchmark.kind == :rate
    assert_decimal(resolution.benchmark.rate, "0")
    assert resolution.benchmark.from == @start_on
    assert resolution.benchmark.to == @resolves_on
    assert resolution.benchmark.days == 90
    assert_decimal(resolution.benchmark.return, "0")

    assert_decimal(resolution.excess, "0.1")
  end

  # User story (F2, ADR-0055 §3 "Start"): the start close is strictly
  # before the day made, so a call whose only close in the window before
  # the day made is too old is unresolved, even with a close on the made
  # day itself.
  test "a close only on the made day is no start close" do
    security = security!("Fresh Listing Co.")

    # 02-23 is eight days before 03-03: stale. 03-04 is the made day: not
    # before it. Nothing stands for 03-03.
    put_quotes!(security, [
      {~D[2026-02-23], "100"},
      {~D[2026-03-04], "100"},
      {~D[2026-06-01], "110"}
    ])

    resolution = resolve(predict!(security, "outperform", "rate:0"))

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
  # - The days run from start.stands_for (2026-03-03) to end.stands_for
  #   (2026-06-01): 90 days, not counted from the close dates.
  test "a nonzero rate benchmark compounds the daily factor over the stand-for days" do
    security = security!("Slow Co.")

    # The end close is dated Friday 05-29 and stands for Monday 06-01: the
    # rate still runs to 06-01.
    put_quotes!(security, [{~D[2026-03-03], "100"}, {~D[2026-05-29], "101"}])

    resolution = resolve(predict!(security, "outperform", "rate:0.05"))

    # 2026-03-03 -> 2026-06-01: 28 days to 03-31, 30 in April, 31 in May
    # and 1 in June = 90 days. Benchmark.daily_rate_factor(0.05) is
    # 1.0001336806171135 (S1's test pins it); multiplied into 1 ninety
    # times, each product rounded to 34 significant digits half-up, it is
    # 1.012103108392936760036609980125266, so the rate's return is
    # 0.012103108392936760036609980125266.
    # Security: 101 / 100 - 1 = 0.01.
    # Excess: 0.01 - 0.012103108392936760036609980125266
    #       = -0.002103108392936760036609980125266 < 0: outperform misses.
    assert resolution.security.end.date == ~D[2026-05-29]
    assert resolution.security.end.stands_for == @resolves_on
    assert resolution.benchmark.kind == :rate
    assert resolution.benchmark.days == 90
    assert Decimal.to_string(resolution.benchmark.return) == "0.012103108392936760036609980125266"
    assert_decimal(resolution.security.return, "0.01")
    assert Decimal.to_string(resolution.excess) == "-0.002103108392936760036609980125266"
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
    # The index's start close (Friday 02-27) stands for 03-03 too; its made
    # day close (03-04) is not used either.
    put_quotes!(index, [
      {~D[2026-02-27], "200"},
      {~D[2026-03-04], "400"},
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
      # Its only close before the made day is eight days before 03-03.
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
  #   after.
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
    # is open, one due yesterday has passed (and, with no close, is
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
    assert Predictions.resolve(due.(Date.add(today, -1))).status == :unresolved
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
  #   on or before the date, so a call already past its date is not due.
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

      %{
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
               ctx.later.id,
               ctx.due_soon.id,
               ctx.due_today.id,
               ctx.unresolved.id,
               ctx.resolved.id
             ]

      assert ids.(status: :open) == [ctx.later.id, ctx.due_soon.id, ctx.due_today.id]
      assert ids.(status: "resolved") == [ctx.resolved.id]
      assert ids.(status: :unresolved) == [ctx.unresolved.id]
      assert ids.(status: "nobody_status_zz") == []
      assert_raise ArgumentError, fn -> String.to_existing_atom("nobody_status_zz") end

      # The limit counts after the status: the one resolved call is found
      # behind three newer open ones.
      assert ids.(status: :resolved, limit: 1) == [ctx.resolved.id]
      assert ids.(status: :open, limit: 2) == [ctx.later.id, ctx.due_soon.id]

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
      # the date, but are past it: not due.
      assert ids.(due_before: ~D[2026-12-01]) == [ctx.due_soon.id, ctx.due_today.id]
      assert ids.(due_before: ~D[2026-11-05]) == [ctx.due_today.id]
      assert ids.(due_before: ~D[2026-11-04]) == []

      # The same through list_with_resolution/2, with the status beside it.
      assert [%{resolution: %{status: :open}}, %{resolution: %{status: :open}}] =
               Predictions.list_with_resolution([due_before: ~D[2026-12-01]], today: @today)

      # A day later the call due today has passed.
      assert Predictions.list_predictions([due_before: ~D[2026-12-01]], today: ~D[2026-11-06])
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
