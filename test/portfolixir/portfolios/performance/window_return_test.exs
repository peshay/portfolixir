defmodule Portfolixir.Portfolios.Performance.WindowReturnTest do
  # Sprint 25 Lane S, S1 (ADR-0055 §3, the plan's D-3): one function for a
  # window's price return in EUR, from stored closes and stored EUR-hub
  # rates. S2 (what a sale missed) and F2 (prediction resolution) both call
  # it, so the two cannot drift. Risk tier (ADR-0036): every figure below is
  # an exact Decimal derived by hand in the comments, at Decimal's default
  # context (34 significant digits, half-up: IEEE 754 decimal128), and the
  # window is checked at a moving rate (the plan's D-8.3).
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Fx
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Portfolios.Performance.Benchmark
  alias Portfolixir.Portfolios.Performance.WindowReturn

  defp d(value), do: Decimal.new(value)

  defp assert_decimal(actual, expected) do
    assert %Decimal{} = actual
    assert Decimal.equal?(actual, d(expected)), "expected #{expected}, got #{inspect(actual)}"
  end

  defp rate!(date, rate, quote_currency \\ "USD") do
    {:ok, 1} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: quote_currency,
          date: date,
          rate: rate,
          source: "manual"
        }
      ])
  end

  # User story (S1, ADR-0055 §3):
  # As the agent reading what a call or a sale was measured against,
  # I want a EUR security's window return from its stored closes,
  # so that the figure is the close-to-close move and names the closes used.
  #
  # Acceptance criteria:
  # - The start is the last close on or before the start date, the end the
  #   last close on or before the end date; each names the date it stands
  #   for and the date of the close itself.
  # - A EUR close converts at exactly 1; the return is end / start - 1.
  test "a EUR security: the close-to-close return at a rate of exactly 1" do
    security = create_security!(name: "Euro Fund", ticker: "EUF", currency: "EUR")

    # The start date (a Saturday) has no close of its own: Friday's stands
    # for it. 100 -> 125 is 125 / 100 - 1 = 0.25.
    put_quotes!(security, [
      {~D[2026-03-06], "100"},
      {~D[2026-06-01], "125"}
    ])

    assert {:ok, result} = WindowReturn.price_return(security, ~D[2026-03-07], ~D[2026-06-01])

    assert result.security_id == security.id
    assert result.currency_code == "EUR"

    assert result.start.stands_for == ~D[2026-03-07]
    assert result.start.date == ~D[2026-03-06]
    assert_decimal(result.start.close, "100")
    assert_decimal(result.start.stored_close, "100")
    assert_decimal(result.start.fx_rate, "1")
    assert_decimal(result.start.eur_value, "100")

    assert result.end.stands_for == ~D[2026-06-01]
    assert result.end.date == ~D[2026-06-01]
    assert_decimal(result.end.close, "125")
    assert_decimal(result.end.eur_value, "125")

    assert_decimal(result.return, "0.25")
  end

  # User story (S1, ADR-0055 §3 "Currency"):
  # As the operator whose holdings are valued in EUR,
  # I want a USD security's return measured in EUR at each close's own
  # date's stored rate,
  # so that the figure compares what I hold, not what the ticker shows.
  #
  # Acceptance criteria:
  # - fx_rate is EUR per one unit of the close's currency, 1 / the stored
  #   EUR-hub rate, at Decimal's default 34 significant digits.
  test "a USD security at an unchanged rate converts both closes at it" do
    security = create_security!(name: "US Fund", ticker: "USF", currency: "USD")
    put_quotes!(security, [{~D[2026-03-02], "110"}, {~D[2026-06-01], "121"}])
    rate!(~D[2026-03-02], "1.1")
    rate!(~D[2026-06-01], "1.1")

    assert {:ok, result} = WindowReturn.price_return(security, ~D[2026-03-02], ~D[2026-06-01])

    # 1 / 1.1 at 34 significant digits = 0.9090909090909090909090909090909091;
    # 110 x that = 100.0000000000000000000000000000000010, rounded to 34
    # digits = 100.0000000000000000000000000000000; 121 x it = 110.00...0 the
    # same way; 110 / 100 - 1 = 0.1, the USD move, as an unchanged rate must
    # give.
    assert Decimal.to_string(result.start.fx_rate) == "0.9090909090909090909090909090909091"
    assert Decimal.to_string(result.end.fx_rate) == "0.9090909090909090909090909090909091"
    assert_decimal(result.start.eur_value, "100")
    assert_decimal(result.end.eur_value, "110")
    assert_decimal(result.return, "0.1")
  end

  # User story (S1, the plan's D-8.3: every money identity at a moving rate):
  # As the agent scoring a call on a USD security,
  # I want the start close converted at the start's rate and the end close
  # at the end's,
  # so that a rising euro shows as the loss in EUR it is.
  #
  # Acceptance criteria:
  # - A USD move of +20 % while EUR/USD rises from 1.25 to 1.60 reads
  #   -6.25 % in EUR; one rate for both ends would read +20 %.
  # - A rate whose inverse does not terminate is carried at 34 significant
  #   digits, with no other rounding on the way.
  test "a moving EUR/USD rate: each close at its own date's rate" do
    security = create_security!(name: "US Growth", ticker: "USG", currency: "USD")
    put_quotes!(security, [{~D[2026-03-02], "100"}, {~D[2026-06-01], "120"}])
    rate!(~D[2026-03-02], "1.25")
    rate!(~D[2026-06-01], "1.60")

    assert {:ok, result} = WindowReturn.price_return(security, ~D[2026-03-02], ~D[2026-06-01])

    # Start: 100 USD x (1 / 1.25 = 0.8) = 80 EUR.
    # End: 120 USD x (1 / 1.60 = 0.625) = 75 EUR.
    # Return: 75 / 80 - 1 = 0.9375 - 1 = -0.0625.
    assert_decimal(result.start.fx_rate, "0.8")
    assert_decimal(result.start.eur_value, "80")
    assert_decimal(result.end.fx_rate, "0.625")
    assert_decimal(result.end.eur_value, "75")
    assert_decimal(result.return, "-0.0625")

    other = create_security!(name: "US Value", ticker: "USV", currency: "USD")
    put_quotes!(other, [{~D[2026-03-03], "100"}, {~D[2026-06-02], "130"}])
    rate!(~D[2026-03-03], "1.1")
    rate!(~D[2026-06-02], "1.2")

    assert {:ok, moved} = WindowReturn.price_return(other, ~D[2026-03-03], ~D[2026-06-02])

    # Start: 100 x (1 / 1.1 = 0.9090909090909090909090909090909091)
    #   = 90.90909090909090909090909090909091.
    # End: 130 x (1 / 1.2 = 0.8333333333333333333333333333333333)
    #   = 108.3333333333333333333333333333333 (rounded to 34 digits).
    # 108.3333333333333333333333333333333 / 90.90909090909090909090909090909091
    #   = 1.191666666666666666666666666666666 at 34 digits (the exact
    #   quotient 130 x 1.1 / (100 x 1.2) = 1.191666...), minus 1.
    assert Decimal.to_string(moved.start.eur_value) == "90.90909090909090909090909090909091"
    assert Decimal.to_string(moved.end.eur_value) == "108.3333333333333333333333333333333"
    assert Decimal.to_string(moved.return) == "0.191666666666666666666666666666666"
  end

  # User story (S1, ADR-0055 §3 "Currency", "as valuation does"):
  # As the operator reading a weekend or holiday close,
  # I want the conversion to use the most recent stored rate on or before
  # the close's date, as the daily valuation walk does,
  # so that a day without an ECB fixing converts as my holdings do.
  #
  # Acceptance criteria:
  # - A close on a day without a rate converts at the last rate before it.
  # - A rate stored only after the close's date is no rate: :no_fx_rate.
  test "the rate is the most recent stored on or before the close's date, never a later one" do
    security = create_security!(name: "US Carry", ticker: "USC", currency: "USD")
    put_quotes!(security, [{~D[2026-03-02], "100"}, {~D[2026-06-01], "100"}])
    # The start close's day has no rate; the Friday before it has 1.25.
    rate!(~D[2026-02-27], "1.25")
    rate!(~D[2026-06-01], "1.25")

    assert {:ok, result} = WindowReturn.price_return(security, ~D[2026-03-02], ~D[2026-06-01])
    assert_decimal(result.start.fx_rate, "0.8")
    assert_decimal(result.return, "0")

    later_only = create_security!(name: "US Later", ticker: "USL", currency: "USD")
    put_quotes!(later_only, [{~D[2026-01-05], "100"}, {~D[2026-06-01], "100"}])

    # The first stored USD rate is 2026-02-27, after the start close.
    assert {:error, :no_fx_rate} =
             WindowReturn.price_return(later_only, ~D[2026-01-05], ~D[2026-06-01])
  end

  # User story (S1, ADR-0055 §3 "unresolved ... no_fx_rate"):
  # As the agent reading an unresolved call,
  # I want a close with no stored rate path to EUR named as :no_fx_rate,
  # so that the call is never measured at a guessed rate.
  test "a currency with no stored rate at all is :no_fx_rate" do
    security = create_security!(name: "Swiss Fund", ticker: "CHF1", currency: "CHF")
    put_quotes!(security, [{~D[2026-03-02], "100"}, {~D[2026-06-01], "110"}])

    assert {:error, :no_fx_rate} =
             WindowReturn.price_return(security, ~D[2026-03-02], ~D[2026-06-01])

    # Once a rate is stored on the start close's day, the end close (no rate
    # of its own) converts at the same rate, carried forward.
    rate!(~D[2026-03-02], "0.95", "CHF")

    assert {:ok, result} = WindowReturn.price_return(security, ~D[2026-03-02], ~D[2026-06-01])
    # Both closes at 1 / 0.95: the rate cancels, 110 / 100 - 1 = 0.1 (the
    # quotient of the two 34-digit EUR values rounds back to 1.1).
    assert_decimal(result.return, "0.1")
  end

  # User story (S1, ADR-0055 §3 "Staleness"):
  # As the agent reading a call on a security whose quotes stopped,
  # I want a close more than 7 calendar days before the date it stands for
  # treated as no close,
  # so that a stale price never resolves a call.
  #
  # Acceptance criteria:
  # - A close 7 days before the date is accepted; 8 days before is refused.
  # - The start side reads :no_start_close, the end side :no_end_close.
  test "staleness: a close 7 days old stands, 8 days old is no close, on either end" do
    security = create_security!(name: "Stale Fund", ticker: "STL", currency: "EUR")
    put_quotes!(security, [{~D[2026-03-02], "100"}, {~D[2026-06-01], "110"}])

    # Start: 2026-03-09 - 7 days = 2026-03-02, the close's own date.
    assert {:ok, seven} = WindowReturn.price_return(security, ~D[2026-03-09], ~D[2026-06-01])
    assert seven.start.date == ~D[2026-03-02]
    assert seven.start.stands_for == ~D[2026-03-09]

    # Start: 2026-03-10 - 8 days = 2026-03-02: one day too old.
    assert {:error, :no_start_close} =
             WindowReturn.price_return(security, ~D[2026-03-10], ~D[2026-06-01])

    # End: 2026-06-08 - 7 = 2026-06-01 stands; 2026-06-09 - 8 does not.
    assert {:ok, end_seven} = WindowReturn.price_return(security, ~D[2026-03-02], ~D[2026-06-08])
    assert end_seven.end.date == ~D[2026-06-01]

    assert {:error, :no_end_close} =
             WindowReturn.price_return(security, ~D[2026-03-02], ~D[2026-06-09])

    # The close lookup on its own, by the same rule.
    assert {:ok, close} = WindowReturn.close_on_or_before(security, ~D[2026-03-09])
    assert close.date == ~D[2026-03-02]
    assert_decimal(close.close, "100")
    assert {:error, :no_close} = WindowReturn.close_on_or_before(security, ~D[2026-03-10])
  end

  # User story (S1, ADR-0055 §3 "no_start_close", "no_end_close"):
  # As the agent reading a call on a security without quotes,
  # I want a missing close named on the side it is missing from,
  # so that the reason says what to fetch.
  #
  # Acceptance criteria:
  # - No close at all: :no_start_close (the start is checked first).
  # - A start close but none near the end: :no_end_close.
  # - A close dated after the date asked for never stands for it.
  test "a missing close is named on its side, and a later close never stands for an earlier date" do
    empty = create_security!(name: "No Quotes", ticker: "NOQ", currency: "EUR")

    assert {:error, :no_start_close} =
             WindowReturn.price_return(empty, ~D[2026-03-02], ~D[2026-06-01])

    security = create_security!(name: "Gap Fund", ticker: "GAP", currency: "EUR")
    put_quotes!(security, [{~D[2026-03-02], "100"}, {~D[2026-06-02], "110"}])

    # The only close near the end is the day after it.
    assert {:error, :no_end_close} =
             WindowReturn.price_return(security, ~D[2026-03-02], ~D[2026-06-01])

    # And the only close near the start is after it too.
    assert {:error, :no_start_close} =
             WindowReturn.price_return(security, ~D[2026-03-01], ~D[2026-06-02])
  end

  # User story (S1, the benchmark comparison's price rule, ADR-0046):
  # As the agent reading a return across a stored close of 0,
  # I want a close that is not positive treated as no close,
  # so that a legacy zero row never divides or reads as a 100 % loss.
  test "a stored close that is not positive is no close" do
    security = create_security!(name: "Zero Row", ticker: "ZRO", currency: "EUR")
    put_quotes!(security, [{~D[2026-03-02], "100"}, {~D[2026-06-01], "120"}])

    # A release before the plausibility bounds could store a 0; insert one
    # past the changeset, the way such a row exists.
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.insert_all(SecurityQuote, [
      %{
        security_id: security.id,
        date: ~D[2026-03-03],
        close: d("0"),
        source: "manual",
        inserted_at: now,
        updated_at: now
      }
    ])

    # The zero on 03-03 is skipped: 03-02's 100 stands for 03-04.
    assert {:ok, result} = WindowReturn.price_return(security, ~D[2026-03-04], ~D[2026-06-01])
    assert result.start.date == ~D[2026-03-02]
    assert_decimal(result.return, "0.2")
  end

  # User story (S1, ADR-0028 §2, the current display basis):
  # As the operator of a security that split inside the window,
  # I want both closes read in the current display basis,
  # so that a 2:1 split is not a 50 % loss.
  #
  # Acceptance criteria:
  # - A manual (raw) close before the split is divided by its ratio; the
  #   stored value stays named beside it.
  test "a split inside the window: both closes in the current display basis" do
    world = base_world(name: "S1 World", cash_name: "S1 Cash", depot_name: "S1 Depot")
    security = create_security!(name: "Split Co", ticker: "SPL", currency: "EUR")
    deposit!(world, "1000", ~D[2026-03-02])
    buy!(world, security, quantity: "5", price: "200", date: ~D[2026-03-02])
    put_quotes!(security, [{~D[2026-03-02], "200"}, {~D[2026-06-01], "110"}])

    {:ok, _txs} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: ~D[2026-04-01],
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    assert {:ok, result} = WindowReturn.price_return(security, ~D[2026-03-02], ~D[2026-06-01])

    # 200 stored before a 2:1 split reads 200 / 2 = 100; 110 / 100 - 1 = 0.1.
    assert_decimal(result.start.stored_close, "200")
    assert_decimal(result.start.close, "100")
    assert_decimal(result.start.eur_value, "100")
    assert_decimal(result.return, "0.1")
  end

  # User story (S1): an end before the start is no window.
  test "an end date before the start date is refused" do
    security = create_security!(name: "Order Fund", ticker: "ORD", currency: "EUR")
    put_quotes!(security, [{~D[2026-03-02], "100"}])

    assert {:error, :invalid_window} =
             WindowReturn.price_return(security, ~D[2026-03-02], ~D[2026-03-01])
  end

  # User story (S1 for F2, ADR-0055 §3 "Benchmark return"):
  # As the agent whose call is measured against a fixed rate,
  # I want the rate's return over the window's calendar days compounded by
  # Benchmark.daily_rate_factor/1, as the benchmark comparison does,
  # so that `rate:0.05` reads the same here as on the comparison.
  #
  # Acceptance criteria:
  # - rate 0 gives exactly 0 over any span; a span of 0 days gives 0.
  # - One day gives the daily factor minus 1.
  # - 365 days compound the factor 365 times, one multiplication a day.
  test "the fixed-rate return compounds Benchmark.daily_rate_factor/1 per calendar day" do
    assert_decimal(WindowReturn.fixed_rate_return(d("0"), ~D[2025-01-01], ~D[2030-01-01]), "0")
    assert_decimal(WindowReturn.fixed_rate_return(d("0.05"), ~D[2026-03-02], ~D[2026-03-02]), "0")

    # The daily factor is (1 + 0.05)^(1/365) taken once as a float,
    # 1.0001336806171135 (the float's shortest decimal), so one day reads
    # 0.0001336806171135.
    assert Decimal.equal?(Benchmark.daily_rate_factor(d("0.05")), d("1.0001336806171135"))

    assert_decimal(
      WindowReturn.fixed_rate_return(d("0.05"), ~D[2026-03-02], ~D[2026-03-03]),
      "0.0001336806171135"
    )

    # 2025-01-01 to 2026-01-01 is 365 days: 1.0001336806171135 multiplied
    # into 1 365 times, each product rounded to 34 significant digits
    # (half-up), is 1.050000000000022857612005448692235, so the return is
    # 0.050000000000022857612005448692235: the annual 5 % up to the float
    # factor's own error, which the benchmark comparison carries the same
    # way.
    assert Decimal.to_string(
             WindowReturn.fixed_rate_return(d("0.05"), ~D[2025-01-01], ~D[2026-01-01])
           ) == "0.050000000000022857612005448692235"
  end

  # User story (S1): the fixed-rate span is a window, never a negative one.
  test "the fixed-rate return refuses an end before its start" do
    assert_raise FunctionClauseError, fn ->
      WindowReturn.fixed_rate_return(d("0.05"), ~D[2026-03-02], ~D[2026-03-01])
    end
  end
end
