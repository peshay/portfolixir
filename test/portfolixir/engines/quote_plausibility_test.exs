defmodule Portfolixir.Engines.QuotePlausibilityTest do
  # #1101 (Sprint 20 β B4, plan D-7; board ux-design-2026-10-07/02-money-findings,
  # pick L2 A): a quote series that contradicts the holding's own trades is
  # named. The engine half, pure: for each buy, sell or priced inbound
  # delivery, the stored quote on the booking's date, or the latest within 7
  # days before it, is compared with the booking's price per unit; a booking
  # whose quote is below half or above twice its price is outside. Every
  # figure is an exact Decimal.
  #
  # The data is invented: "Arbolia Inc." and "Wrenfield Gardens AG" are the
  # board's, every other name and figure is synthetic.
  use ExUnit.Case, async: true

  alias Portfolixir.Engines.QuotePlausibility

  defp d(value), do: Decimal.new(value)

  defp booking(kind, date, price, quote \\ nil) do
    %{kind: kind, date: date, price: price && d(price), quote: quote}
  end

  defp quote_point(date, close, basis \\ :raw), do: %{date: date, close: d(close), basis: basis}

  # User story (#1101, D-7 "Why the same date"):
  # As the operator whose holding rose twentyfold since I bought it,
  # I want the guard to compare each booking with the quote of its own day,
  # so that a real rise is never named, while a quote series from another
  # listing is.
  #
  # Acceptance criteria:
  # - Bought at 10.00 (quote that day 10.20) and sold at 200.00 (quote that
  #   day 198.00): nothing is named, though the last quote is twenty times
  #   the buy.
  # - A mis-mapped ticker, quotes about ten times every booking: named, with
  #   the latest booking outside the band — the sell of 2026-04-03 at 61.40,
  #   compared with the quote of 2026-04-02 (none stored that day), 618.90,
  #   ratio 618.90 / 61.40 — and bookings_outside 2.
  test "a twentyfold riser is not named, a mis-mapped ticker is" do
    riser = [
      booking("buy", ~D[2024-01-10], "10.00", quote_point(~D[2024-01-10], "10.20")),
      booking("sell", ~D[2026-03-02], "200.00", quote_point(~D[2026-03-02], "198.00"))
    ]

    assert QuotePlausibility.finding(riser, []) == nil

    arbolia = [
      booking("buy", ~D[2026-01-14], "58.20", quote_point(~D[2026-01-14], "589.10")),
      booking("sell", ~D[2026-04-03], "61.40", quote_point(~D[2026-04-02], "618.90"))
    ]

    finding = QuotePlausibility.finding(arbolia, [])

    assert finding.kind == "sell"
    assert finding.date == ~D[2026-04-03]
    assert Decimal.equal?(finding.price, d("61.40"))
    assert finding.quote_date == ~D[2026-04-02]
    assert Decimal.equal?(finding.close, d("618.90"))
    assert Decimal.equal?(finding.ratio, Decimal.div(d("618.90"), d("61.40")))
    assert finding.bookings_outside == 2
  end

  # User story (#1101): the pence/pound slip, D-7's other named case.
  #
  # Acceptance criteria:
  # - A booking at 12.40 beside a quote of 1240 that day (pence stored as
  #   pounds) is named, ratio 100; a booking at 1240 beside a quote of 12.40
  #   is named, ratio 0.01.
  test "a pence/pound slip is named in either direction" do
    pence =
      QuotePlausibility.finding(
        [booking("buy", ~D[2026-02-11], "12.40", quote_point(~D[2026-02-11], "1240"))],
        []
      )

    assert Decimal.equal?(pence.ratio, d("100"))

    pounds =
      QuotePlausibility.finding(
        [booking("buy", ~D[2026-02-11], "1240", quote_point(~D[2026-02-11], "12.40"))],
        []
      )

    assert Decimal.equal?(pounds.ratio, d("0.01"))
  end

  # User story (#1101, D-7 threshold 2):
  # As the operator,
  # I want the band [1/2, 2] to include its ends,
  # so that only a quote strictly below half or strictly above twice the
  # booked price is named.
  #
  # Acceptance criteria:
  # - Ratio exactly 2 and exactly 1/2: nothing named.
  # - 20.02 beside 10.00 and 4.99 beside 10.00: named.
  test "the band includes its ends" do
    on = ~D[2026-05-12]

    assert QuotePlausibility.finding([booking("buy", on, "10.00", quote_point(on, "20.00"))], []) ==
             nil

    assert QuotePlausibility.finding([booking("buy", on, "10.00", quote_point(on, "5.00"))], []) ==
             nil

    assert %{ratio: high} =
             QuotePlausibility.finding(
               [booking("buy", on, "10.00", quote_point(on, "20.02"))],
               []
             )

    assert Decimal.equal?(high, d("2.002"))

    assert %{ratio: low} =
             QuotePlausibility.finding([booking("buy", on, "10.00", quote_point(on, "4.99"))], [])

    assert Decimal.equal?(low, d("0.499"))
    assert QuotePlausibility.threshold() == 2
  end

  # User story (#1101, D-7 window and gaps):
  # As the operator,
  # I want a booking compared only with a quote from its own week,
  # so that a quote from long before, or after, the booking never stands in
  # for its day.
  #
  # Acceptance criteria:
  # - A quote 7 days before the booking is used; one 8 days before, or one
  #   dated after the booking, is not, and the booking is not compared.
  # - A booking with no quote is not compared.
  test "a booking is compared with a quote from the 7 days before it, or not at all" do
    on = ~D[2026-05-12]

    assert %{quote_date: ~D[2026-05-05]} =
             QuotePlausibility.finding(
               [booking("buy", on, "48.20", quote_point(~D[2026-05-05], "4.87"))],
               []
             )

    assert QuotePlausibility.finding(
             [booking("buy", on, "48.20", quote_point(~D[2026-05-04], "4.87"))],
             []
           ) == nil

    assert QuotePlausibility.finding(
             [booking("buy", on, "48.20", quote_point(~D[2026-05-13], "4.87"))],
             []
           ) == nil

    assert QuotePlausibility.finding([booking("buy", on, "48.20")], []) == nil
    assert QuotePlausibility.window_days() == 7
  end

  # User story (board 02, found while drawing 2):
  # As the operator holding bonus shares booked at 0.00,
  # I want such a booking skipped,
  # so that a free share, which has no ratio, never names its security.
  #
  # Acceptance criteria:
  # - A buy at 0.00 beside a quote of 41.25 that day: nothing named.
  # - A delivery with no price: nothing named.
  test "a booking at a price of 0, or with none, has no ratio and is skipped" do
    on = ~D[2025-03-03]

    assert QuotePlausibility.finding([booking("buy", on, "0", quote_point(on, "41.25"))], []) ==
             nil

    assert QuotePlausibility.finding(
             [booking("inbound_delivery", on, nil, quote_point(on, "41.25"))],
             []
           ) == nil
  end

  # User story (board 02, found while drawing 1; ADR-0028 §2):
  # As the operator whose security split,
  # I want the booked price and the quote compared on one price basis,
  # so that a recorded split is not named, while an unrecorded one is, its
  # remedy being to record the split.
  #
  # Acceptance criteria (a 10:1 split effective 2026-02-01; bought 10 at
  # 100.00 on 2026-01-05):
  # - A provider's back-adjusted quote of 10.05 that day: nothing named with
  #   the split recorded; without it, named at ratio 0.1005.
  # - A manual (as-traded) quote of 101.00 that day: nothing named, with or
  #   without the split.
  # - A booking on 2026-02-02 at 10.10, after the split, beside the manual
  #   quote of 2026-01-30, 100.00, before it: nothing named, since the quote
  #   is read on the booking's basis (10.00); at 3.00 it is named, its close
  #   shown on that basis, 10, ratio 10 / 3.
  test "a quote and a booked price are compared on one split basis" do
    split = [%{date: ~D[2026-02-01], ratio: {10, 1}}]
    on = ~D[2026-01-05]
    mirrored = [booking("buy", on, "100.00", quote_point(on, "10.05", :provider_mirror))]

    assert QuotePlausibility.finding(mirrored, split) == nil
    assert %{ratio: unrecorded} = QuotePlausibility.finding(mirrored, [])
    assert Decimal.equal?(unrecorded, d("0.1005"))

    manual = [booking("buy", on, "100.00", quote_point(on, "101.00"))]
    assert QuotePlausibility.finding(manual, split) == nil
    assert QuotePlausibility.finding(manual, []) == nil

    across = quote_point(~D[2026-01-30], "100.00")

    assert QuotePlausibility.finding([booking("buy", ~D[2026-02-02], "10.10", across)], split) ==
             nil

    finding = QuotePlausibility.finding([booking("buy", ~D[2026-02-02], "3.00", across)], split)
    assert Decimal.equal?(finding.close, d("10"))
    assert Decimal.equal?(finding.ratio, Decimal.div(d("10"), d("3.00")))
  end
end
