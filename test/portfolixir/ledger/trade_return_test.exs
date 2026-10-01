defmodule Portfolixir.Ledger.TradeReturnTest do
  # The annualized return per closed round-trip (#984 rescoped, Sprint 17 T1,
  # plan D-7): the money-weighted return of the trade's own flows, through the
  # existing XIRR solver (ADR-0034 §2), null under 365 days of holding.
  # Risk-tier money math: every expectation is an exact Decimal at the
  # solver's stated scale (6 places).
  use ExUnit.Case, async: true

  alias Portfolixir.Ledger.TradeMatcher
  alias Portfolixir.Ledger.TradeReturn

  defp buy(date, qty, price, opts \\ []) do
    %{
      type: "buy",
      date: date,
      quantity: Decimal.new(qty),
      price: Decimal.new(price),
      fees: Decimal.new(Keyword.get(opts, :fees, "0")),
      taxes: Decimal.new(Keyword.get(opts, :taxes, "0")),
      currency_code: "EUR"
    }
  end

  defp sell(date, qty, price, opts \\ []) do
    %{buy(date, qty, price, opts) | type: "sell"}
  end

  defp closed_trade(transactions) do
    %{closed_trades: [trade]} = TradeMatcher.match(transactions)
    trade
  end

  defp d(value), do: Decimal.new(value)

  @open ~D[2024-01-01]

  # User story (#984 rescoped, Sprint 17 T1):
  # As the operator asking whether a trade was worth it,
  # I want an annualized return beside each closed trade's percentage,
  # so that a two-week trade and a three-year trade with the same percentage
  # no longer read alike.
  #
  # Acceptance criteria (identity 1, plan Lane T):
  # - A single-lot trade held N >= 365 days returns
  #   (proceeds / basis)^(365 / N) - 1, at the solver's scale of 6 places.
  # - Fees and taxes are in the flows: the buy's cost includes them, the
  #   sell's proceeds are net of them.
  test "a single-lot trade held N >= 365 days annualizes as (proceeds / basis)^(365 / N) - 1" do
    # (1440 / 1000)^(365 / 730) - 1 = 1.2 - 1.
    two_years =
      closed_trade([buy(@open, "10", "100"), sell(Date.add(@open, 730), "10", "144")])

    assert TradeReturn.annualized(two_years) ==
             %{annualized_return: d("0.200000"), annualized_return_reason: nil}

    # (1500 / 1000)^(365 / 500) - 1 = 0.34445607884979... at scale 6.
    non_terminating =
      closed_trade([buy(@open, "10", "100"), sell(Date.add(@open, 500), "10", "150")])

    assert TradeReturn.annualized(non_terminating).annualized_return == d("0.344456")

    # Fees and taxes ride the flows: basis 10 x 100 + 5 = 1005, proceeds
    # 10 x 150 - 5 = 1495; (1495 / 1005)^(365 / 400) - 1 = 0.43675777816...
    with_costs =
      closed_trade([
        buy(@open, "10", "100", fees: "4", taxes: "1"),
        sell(Date.add(@open, 400), "10", "150", fees: "3", taxes: "2")
      ])

    assert Decimal.equal?(with_costs.basis, d("1005"))
    assert Decimal.equal?(with_costs.proceeds, d("1495"))
    assert TradeReturn.annualized(with_costs).annualized_return == d("0.436758")
  end

  # Acceptance criteria (identity 1, its boundary):
  # - At exactly 365 days the annualized return equals the period return
  #   the row already shows: (proceeds / basis)^1 - 1.
  test "at exactly 365 days of holding the annualized return is the period return" do
    one_year = closed_trade([buy(@open, "10", "100"), sell(Date.add(@open, 365), "10", "109")])

    assert one_year.holding_period_days == 365
    assert Decimal.equal?(one_year.realized_pnl_pct, d("0.09"))
    assert TradeReturn.annualized(one_year).annualized_return == d("0.090000")
  end

  # Acceptance criteria (identity 2, ADR-0034 §2's short-window rule):
  # - Under 365 days of holding the field is null, with its reason, because
  #   annualizing a short window explodes the figure: 5 % in 14 days would
  #   read as about 257 % a year.
  # - "Holding period" is the trade's own holding_period_days (the
  #   quantity-weighted days the row shows), never the span from the oldest
  #   lot: a sell that takes one old share and many new ones is a short trade.
  test "under 365 days of holding the annualized return is null with its reason" do
    short = closed_trade([buy(@open, "10", "100"), sell(Date.add(@open, 14), "10", "105")])

    assert short.holding_period_days == 14

    assert TradeReturn.annualized(short) ==
             %{annualized_return: nil, annualized_return_reason: :holding_period_under_365_days}

    just_short =
      closed_trade([buy(@open, "10", "100"), sell(Date.add(@open, 364), "10", "150")])

    assert TradeReturn.annualized(just_short).annualized_return_reason ==
             :holding_period_under_365_days

    # One share held 1000 days and 99 held 30: the oldest lot spans 1000
    # days, but the trade's holding period is 39.7 -> 40 days.
    mostly_new =
      closed_trade([
        buy(@open, "1", "100"),
        buy(Date.add(@open, 970), "99", "100"),
        sell(Date.add(@open, 1000), "100", "110")
      ])

    assert mostly_new.holding_period_days == 40

    assert TradeReturn.annualized(mostly_new) ==
             %{annualized_return: nil, annualized_return_reason: :holding_period_under_365_days}
  end

  # Acceptance criteria (identity 3):
  # - A loss stays above -100 %: compounding cannot go below it, where a
  #   linear annualization (the percent times 365 / N) would.
  # - A total loss has no rate (proceeds of zero leave no sign change) and is
  #   null with that reason, never -100 % invented.
  test "a loss stays above -100 % and a total loss is null with its reason" do
    halved = closed_trade([buy(@open, "10", "100"), sell(Date.add(@open, 730), "10", "64")])
    # (640 / 1000)^(365 / 730) - 1 = 0.8 - 1.
    assert TradeReturn.annualized(halved).annualized_return == d("-0.200000")

    # (10 / 1000)^(365 / 400) - 1 = -0.98503764343... at scale 6.
    wiped = closed_trade([buy(@open, "10", "100"), sell(Date.add(@open, 400), "10", "1")])
    assert %{annualized_return: rate} = TradeReturn.annualized(wiped)
    assert rate == d("-0.985038")
    assert Decimal.compare(rate, d("-1")) == :gt

    total = closed_trade([buy(@open, "10", "100"), sell(Date.add(@open, 400), "10", "0")])

    assert TradeReturn.annualized(total) ==
             %{annualized_return: nil, annualized_return_reason: :no_sign_change}
  end

  # Acceptance criteria (the money weighting, plan D-7):
  # - A multi-lot trade solves over each consumed lot's own buy at its own
  #   date and prorated cost, not over the summed basis at an averaged date.
  test "a multi-lot trade solves over each lot's own flow" do
    # -1000 at t0, -1000 at t0 + 365 days, +2640 at t0 + 730 days:
    # 1000 x 1.2^2 + 1000 x 1.2 = 2640, so the rate is exactly 0.2.
    trade =
      closed_trade([
        buy(@open, "10", "100"),
        buy(Date.add(@open, 365), "10", "100"),
        sell(Date.add(@open, 730), "20", "132")
      ])

    # 548 weighted days; the averaged-date shortcut would read
    # (2640 / 2000)^(365 / 548) - 1 = 0.2033..., not the money-weighted 0.2.
    assert trade.holding_period_days == 548
    assert TradeReturn.annualized(trade).annualized_return == d("0.200000")
  end

  # Acceptance criteria (closing act γ, money lens M1):
  # - Each lot's flow is its own cost — its price and its prorated fees —
  #   not the basis split by quantity: lots at different prices and fees
  #   give the exact XIRR of their own flows.
  test "a multi-lot trade weights each lot by its own cost, not by its quantity" do
    # -1003 at t0, -1303 at t0 + 900 days, +2793 at t0 + 1000 days; the
    # exact XIRR is 0.14164249121711..., where splitting the basis 2306 by
    # quantity would read 0.127414.
    trade =
      closed_trade([
        buy(@open, "10", "100", fees: "3"),
        buy(Date.add(@open, 900), "10", "130", fees: "3"),
        sell(Date.add(@open, 1000), "20", "140", fees: "5", taxes: "2")
      ])

    assert Enum.map(trade.lots, & &1.cost) == [d("1003"), d("1303")]
    assert TradeReturn.annualized(trade).annualized_return == d("0.141642")
  end

  # Acceptance criteria (closing act γ, money lens M3):
  # - A trade whose amounts run past what the solver's absolute tolerance
  #   (|NPV| < 1e-7) can meet in a float — a large position in a
  #   high-nominal currency — still solves: the rate is scale-free, so its
  #   flows are scaled to a cost of one million first.
  test "a trade too large for the solver's absolute tolerance still solves" do
    # -2,000,001,500 at t0, +2,740,000,000 at t0 + 500 days: the exact XIRR
    # is 0.25836252518138...; unscaled the solver answers no_root.
    trade =
      closed_trade([
        buy(@open, "1000000", "2000", fees: "1500"),
        sell(Date.add(@open, 500), "1000000", "2740")
      ])

    assert TradeReturn.annualized(trade) ==
             %{annualized_return: d("0.258363"), annualized_return_reason: nil}
  end

  # Acceptance criteria (ADR-0034 §2: no root is invented):
  # - When the solver does not converge inside its budget the field is null
  #   with the solver's own reason.
  test "a solver that does not converge leaves the field null with its reason" do
    trade = closed_trade([buy(@open, "10", "100"), sell(Date.add(@open, 730), "10", "144")])

    assert TradeReturn.annualized(trade, max_iterations: 0) ==
             %{annualized_return: nil, annualized_return_reason: :no_root}
  end

  # Acceptance criteria (the metric rule, AGENTS.md):
  # - The rule is stated once, as the sentence both reads carry in their
  #   computation_basis: the flows, the currency, the 365-day threshold and
  #   which holding period it reads, the scale, and every null reason.
  test "the stated basis names the flows, the threshold and every null reason" do
    basis = TradeReturn.basis()

    for phrase <- [
          "XIRR",
          "prorated cost",
          "proceeds",
          "own currency",
          "holding_period_days",
          "365",
          "6 decimal places",
          "holding_period_under_365_days",
          "no_sign_change",
          "no_root",
          "amount_out_of_range",
          "income received while the trade was open is not included"
        ] do
      assert basis =~ phrase, "the basis does not state #{inspect(phrase)}"
    end
  end
end
