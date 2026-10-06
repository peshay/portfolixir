defmodule Portfolixir.Engines.BondMetrics do
  @moduledoc """
  The display-only bond metrics of
  [ADR-0052](../../docs/decisions/0052-bond-master-data-in-dedicated-columns.md)
  (#330, scope-ladder level (a)), and the two-scales guard.

  This is an **engine** (architecture D2/P3): pure functions over injected
  master data, a price, a quantity and a day — no `Repo`, no clock.
  `Portfolixir.Portfolios.Bonds` loads the inputs and wraps each figure in
  its computation basis.

  ## The convention every figure rests on

  A Portfolio Performance export books a percent-quoted bond's quantity as a
  **hundredth of its face amount** (the owner's answer of 2026-10-01, Sprint
  17 plan D-13): 100 units are a nominal of 10,000, and a quote of 97.25 is
  both 97.25 % of face and the price per unit. So the nominal held is
  quantity × 100, and coupon and price are both percent of face.

  ## The figures

    * `nominal_held/1` — quantity × 100, exact.
    * `remaining_term/2` — calendar days from the read day to the maturity,
      in years of #{365} days and in whole years and months. On or after the
      maturity the bond is `matured`.
    * current yield — coupon ÷ price, a ratio (0.025707 is 2.5707 %).
    * yield to maturity — the **linear** approximation
      (coupon + (100 − price) ÷ remaining years) ÷ price, a ratio, without
      compounding, accrued interest, fees or taxes. The remaining years are
      taken at full precision (`(100 − price) × 365 ÷ days`); only the
      answer is rounded.

  Ratios and years are rounded half up at scale #{6} on the way out, as the
  per-security metrics are (ADR-0047). A figure without its inputs is `nil`
  with `insufficient_data` and the inputs it lacks in `missing`; a matured
  bond has no yield (`matured`, not insufficient data).

  A yield over the last own **trade** price is refused when that price is at
  most #{5} (`price_on_unit_scale`): the two-scales band's mirror, 100 ÷ #{20}.
  Such a price per unit is what a booking of the nominal as the quantity
  looks like, and it is not percent of face, so coupon ÷ price is no yield
  (a 2.5 coupon over 0.984 read 254 %). The guard below cannot name that
  case: it needs a quote. A stored quote is a percent price at any level and
  is always used (closing act on U7, finding 3).

  ## The two-scales guard

  `two_scales/2` names a bond whose latest stored quote is between #{20} and
  #{500} times a booked price per unit (both ends included): quotes near
  100 beside bookings near 1, which is what an export that booked the
  nominal as the quantity looks like. A booking is a buy or a priced inbound
  delivery: since #779 a delivery's booked price opens its lot and drives
  its flow as a buy's does (closing act on U7, finding 4). Every money figure of such a bond is a
  hundred times too high, and the TTWROR does not show it (bond discovery,
  point 5). That is the **forward** direction.

  The **reverse** direction is the same band inverted (#1068, Sprint 19
  plan D-15): a latest quote between 1/#{500} and 1/#{20} of a booked price
  per unit, both ends included — quotes near 1 beside bookings near 100.
  The stored quotes are then not percent of face, and the bond counts a
  hundred times too low in every total. It is read as the booked price over
  the quote between #{20} and #{500}, the forward band's own figures, so
  both ends are exact. The quote itself must be on the unit scale, at most
  #{5} (`unit_scale_price_ceiling/0`): a percent quote of 98.5 beside a
  booking of 4,925 per piece is a denomination booked per piece, not quotes
  near 1, and the reverse note's remedy would point at the wrong figure.

  The finding says which direction it is. Where a bond's bookings fall in
  both bands, the forward finding is the one reported. The guard names; it
  converts nothing, in either direction (ADR-0052 §4).
  """

  @days_per_year 365
  @scale 6
  @hundred Decimal.new(100)
  @band_low Decimal.new(20)
  @band_high Decimal.new(500)
  @unit_scale_ceiling Decimal.div(@hundred, @band_low)

  @type price :: %{value: Decimal.t() | nil, date: Date.t() | nil, source: atom() | nil}

  @doc "The days a remaining term's year counts."
  @spec days_per_year() :: pos_integer()
  def days_per_year, do: @days_per_year

  @doc """
  The two-scales band: the ratios of quote to booked price per unit that are
  named in the forward direction. The reverse direction names the same
  ratios of booked price per unit to quote.
  """
  @spec two_scales_band() :: {Decimal.t(), Decimal.t()}
  def two_scales_band, do: {@band_low, @band_high}

  @doc """
  The highest own trade price a yield is refused over (`price_on_unit_scale`):
  par over the band's lower end, 100 ÷ 20 = 5.
  """
  @spec unit_scale_price_ceiling() :: Decimal.t()
  def unit_scale_price_ceiling, do: @unit_scale_ceiling

  @doc """
  Every metric of one bond: `terms` carries `:coupon_rate` and
  `:maturity_date` (either may be `nil`), `price` the price the valuation
  uses with its date and source, `quantity` the units held.
  """
  @spec compute(map(), price(), Decimal.t(), Date.t()) :: map()
  def compute(terms, price, %Decimal{} = quantity, %Date{} = as_of) do
    coupon_rate = Map.get(terms, :coupon_rate)
    term = remaining_term(Map.get(terms, :maturity_date), as_of)

    %{
      nominal_held: nominal_held(quantity),
      remaining_term: term,
      current_yield: current_yield(coupon_rate, price, term),
      yield_to_maturity: yield_to_maturity(coupon_rate, price, term)
    }
  end

  @doc "The face amount `quantity` units stand for: one unit is a hundredth of it."
  @spec nominal_held(Decimal.t()) :: Decimal.t()
  def nominal_held(%Decimal{} = quantity), do: Decimal.mult(quantity, @hundred)

  @doc """
  The time from `as_of` to `maturity_date`: `days`, `years` (days ÷ 365,
  scale 6), `whole_years` and `whole_months`; `matured` on and after the
  maturity date.
  """
  @spec remaining_term(Date.t() | nil, Date.t()) :: map()
  def remaining_term(nil, _as_of) do
    %{
      days: nil,
      years: nil,
      whole_years: nil,
      whole_months: nil,
      matured: false,
      insufficient_data: true,
      missing: ["maturity_date"]
    }
  end

  def remaining_term(%Date{} = maturity_date, %Date{} = as_of) do
    days = Date.diff(maturity_date, as_of)

    if days <= 0 do
      %{
        days: nil,
        years: nil,
        whole_years: nil,
        whole_months: nil,
        matured: true,
        insufficient_data: false,
        missing: []
      }
    else
      {whole_years, whole_months} = whole_years_and_months(as_of, maturity_date)

      %{
        days: days,
        years: days |> Decimal.new() |> Decimal.div(@days_per_year) |> round_out(),
        whole_years: whole_years,
        whole_months: whole_months,
        matured: false,
        insufficient_data: false,
        missing: []
      }
    end
  end

  # Whole calendar months from `from` to `to`, a month counting once its day
  # of the month is reached.
  defp whole_years_and_months(from, to) do
    months = (to.year - from.year) * 12 + (to.month - from.month)
    months = if to.day < from.day, do: months - 1, else: months
    {div(months, 12), rem(months, 12)}
  end

  defp current_yield(coupon_rate, price, term) do
    yield(price, missing_inputs(coupon_rate, price), term, fn ->
      Decimal.div(coupon_rate, price.value)
    end)
  end

  defp yield_to_maturity(coupon_rate, price, term) do
    missing = missing_inputs(coupon_rate, price) ++ term.missing

    yield(price, missing, term, fn ->
      pull_to_par =
        @hundred
        |> Decimal.sub(price.value)
        |> Decimal.mult(@days_per_year)
        |> Decimal.div(term.days)

      coupon_rate |> Decimal.add(pull_to_par) |> Decimal.div(price.value)
    end)
  end

  defp yield(price, missing, term, compute) do
    base = %{price: price, missing: missing, matured: term.matured, price_on_unit_scale: false}

    cond do
      term.matured ->
        Map.merge(base, %{value: nil, insufficient_data: false, missing: []})

      missing != [] ->
        Map.merge(base, %{value: nil, insufficient_data: true})

      unit_scale_trade_price?(price) ->
        Map.merge(base, %{value: nil, insufficient_data: false, price_on_unit_scale: true})

      true ->
        Map.merge(base, %{value: round_out(compute.()), insufficient_data: false})
    end
  end

  # The own trade price fallback on the unit scale; reached only with a
  # price above 0 (missing_inputs/2 names any other).
  defp unit_scale_trade_price?(%{source: :trade, value: %Decimal{} = value}),
    do: Decimal.compare(value, @unit_scale_ceiling) != :gt

  defp unit_scale_trade_price?(_price), do: false

  # A coupon of 0 is a zero-coupon bond, an input; a price of zero or below
  # is no price at all (as a close is not in ADR-0047's series).
  defp missing_inputs(coupon_rate, price) do
    coupon = if is_nil(coupon_rate), do: ["coupon_rate"], else: []
    priced? = match?(%Decimal{}, price.value) and Decimal.compare(price.value, 0) == :gt
    coupon ++ if(priced?, do: [], else: ["price"])
  end

  @doc """
  The two-scales finding for one bond, or `nil`: `latest_quote` is
  `%{close, date}` (or `nil` without a quote), `bookings` the booked prices
  per unit (buys and priced inbound deliveries) as `%{price, date}`.

  A finding carries its `direction` (`:forward`, quotes near 100 beside
  bookings near 1; `:reverse`, quotes near 1 beside bookings near 100), the
  quote, and the count and the last of the bookings in the band.
  """
  @spec two_scales(map() | nil, [map()]) :: map() | nil
  def two_scales(nil, _bookings), do: nil

  def two_scales(%{close: %Decimal{} = close} = latest_quote, bookings)
      when is_list(bookings) do
    forward = Enum.filter(bookings, &in_band?(close, &1, :forward))
    reverse = Enum.filter(bookings, &in_band?(close, &1, :reverse))

    case {forward, reverse} do
      {[], []} -> nil
      {[], in_band} -> finding(:reverse, latest_quote, in_band)
      {in_band, _reverse} -> finding(:forward, latest_quote, in_band)
    end
  end

  # The keys keep the forward case's names, which the API serves: in the
  # reverse direction they count the bookings near 100 the quote is a
  # hundredth of, and `direction` says which reading applies.
  defp finding(direction, latest_quote, in_band) do
    %{
      direction: direction,
      latest_quote: latest_quote,
      unit_scale_bookings: length(in_band),
      last_unit_scale_booking: Enum.max_by(in_band, & &1.date, Date)
    }
  end

  # Forward: quote ÷ price in the band. Reverse: price ÷ quote in the same
  # band, which is quote ÷ price from 1/500 to 1/20 without a rounded
  # division at either end, and only for a quote on the unit scale (at most
  # 100 ÷ 20).
  defp in_band?(close, %{price: %Decimal{} = price}, direction) do
    if Decimal.compare(price, 0) == :gt and Decimal.compare(close, 0) == :gt and
         (direction == :forward or Decimal.compare(close, @unit_scale_ceiling) != :gt) do
      ratio =
        case direction do
          :forward -> Decimal.div(close, price)
          :reverse -> Decimal.div(price, close)
        end

      Decimal.compare(ratio, @band_low) != :lt and Decimal.compare(ratio, @band_high) != :gt
    else
      false
    end
  end

  defp in_band?(_close, _booking, _direction), do: false

  defp round_out(%Decimal{} = value), do: Decimal.round(value, @scale, :half_up)
end
