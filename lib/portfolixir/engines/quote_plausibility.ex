defmodule Portfolixir.Engines.QuotePlausibility do
  @moduledoc """
  The `implausible_quote` guard (#1101, Sprint 20 plan D-7), pure: whether a
  security's stored quotes contradict its own bookings.

  For each booking — a buy, a sell or a priced inbound delivery — the stored
  quote on the booking's date, or the latest within `window_days/0` days
  before it, is compared with the booking's price per unit in the security's
  currency. A booking is **outside** when that quote is below 1/`threshold/0`
  or above `threshold/0` times its price; the band includes its ends.

  **Why the same date** (D-7): a share that rose twentyfold cannot trip it,
  because its quote on each booking's date matched the price paid then. A
  ticker mapped wrong from day one does trip it, and so does a pence/pound
  slip.

  **One price basis** (board 02, found while drawing 1; ADR-0028 §2): a
  booked price is as traded on its date, while a provider's stored close is
  back-adjusted for later splits. The quote is therefore read on the
  booking's own basis — as traded on its date (`QuoteAdjustment.raw_close/4`)
  and moved into the booking's split era (`QuoteAdjustment.rebase_close/4`)
  — so a recorded split is not named. An unrecorded split is: its remedy is
  to record the split.

  **What is skipped** (found while drawing 2): a booking with no price, or a
  price of 0 — a bonus share, a delivery at no cost — has no ratio; and a
  booking with no quote in its window is not compared.

  The shell that loads the bookings and quotes is
  `Portfolixir.Portfolios.QuotePlausibility`. Nothing is stored and nothing
  is converted: the guard names.
  """

  alias Portfolixir.Catalog.QuoteAdjustment

  @threshold 2
  @window_days 7

  @typedoc """
  One booking: its kind, date and price per unit in the security's currency
  (`nil` when it has none), and the latest stored quote within its window,
  with the quote's storage basis (`QuoteAdjustment.basis/2`).
  """
  @type booking :: %{
          kind: String.t(),
          date: Date.t(),
          price: Decimal.t() | nil,
          quote: %{date: Date.t(), close: Decimal.t(), basis: QuoteAdjustment.basis()} | nil
        }

  @doc "The factor a quote may differ from a booked price by, either way, unnamed: 2."
  @spec threshold() :: pos_integer()
  def threshold, do: @threshold

  @doc "How many days before a booking a quote may be dated and still stand for its day: 7."
  @spec window_days() :: pos_integer()
  def window_days, do: @window_days

  @doc """
  The finding over one security's bookings, or `nil` when none is outside
  the band: the latest booking outside it (`kind`, `date`, `price`), the
  quote it was compared with (`quote_date`, and `close` on the booking's
  basis), `ratio` (close ÷ price, at full precision) and
  `bookings_outside`, how many bookings are outside.
  """
  @spec finding([booking()], [QuoteAdjustment.split_event()]) :: map() | nil
  def finding(bookings, split_events) when is_list(bookings) and is_list(split_events) do
    outside =
      for booking <- bookings,
          compared = compare(booking, split_events),
          compared != nil,
          outside?(compared),
          do: compared

    case outside do
      [] ->
        nil

      outside ->
        outside
        |> Enum.max_by(& &1.date, Date)
        |> Map.put(:bookings_outside, length(outside))
    end
  end

  defp compare(%{price: %Decimal{} = price, quote: %{} = quote} = booking, events) do
    if Decimal.compare(price, 0) == :gt and in_window?(quote.date, booking.date) do
      close =
        quote.close
        |> QuoteAdjustment.raw_close(quote.date, quote.basis, events)
        |> QuoteAdjustment.rebase_close(quote.date, booking.date, events)

      %{
        kind: booking.kind,
        date: booking.date,
        price: price,
        quote_date: quote.date,
        close: close,
        ratio: Decimal.div(close, price)
      }
    end
  end

  defp compare(_booking, _events), do: nil

  defp in_window?(quote_date, booking_date),
    do: Date.diff(booking_date, quote_date) in 0..@window_days

  # Outside [1/k, k], both ends included: close > k × price or k × close <
  # price, without a rounded division at either end.
  defp outside?(%{close: close, price: price}) do
    Decimal.compare(close, Decimal.mult(price, @threshold)) == :gt or
      Decimal.compare(Decimal.mult(close, @threshold), price) == :lt
  end
end
