defmodule Portfolixir.Portfolios.SnapshotComparison do
  @moduledoc """
  The ADR-0027 counterfactual: values a depot snapshot's frozen holdings
  **buy-and-hold** over the real stored quote history and compares that
  against the scope's real TTWROR since the as-of date — answering "would I
  have done better if I had changed nothing?".

  The snapshot side is derived, never stored (ADR-0004): the position set is
  the ledger projected up to the snapshot's as-of date, filtered to the
  snapshot's view scope. Each day from as-of to today it is valued with the
  last quote close on or before that day, converted to the portfolio's base
  currency through the EUR hub at that day's stored rate (ADR-0007) — exactly
  the pricing semantics of the daily performance walk. No trades and no flows
  enter this side.

  The real side reuses `Portfolixir.Portfolios.Performance`'s daily walk and
  chains its per-day returns from the as-of date on:
  `(1 + cum_today) / (1 + cum_as_of) − 1`.

  The v1 comparison is **gross and price-return only** (ADR-0027):
  distributions the frozen positions would have paid are a documented
  follow-up. Securities without a usable close on or before the as-of date
  (or with no FX path into the base currency there) are **excluded and
  surfaced as gaps** (AR-4) — they never leak a silent zero into the totals.

  Data loading happens up front; the daily walk itself issues no queries
  (AR-2: the shell loads, the core computes).
  """

  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Snapshots

  @zero Decimal.new(0)
  @one Decimal.new(1)
  @hub "EUR"
  @gbx_per_gbp Decimal.new(100)

  @doc """
  Computes the comparison for one snapshot within `portfolio_id`'s scope pair
  (the page's portfolio, the snapshot's view — the same pairing the Wealth
  page's performance walk uses).

  Options:
    * `:today` — end date override (for tests); defaults to `Date.utc_today()`.

  Returns `{:ok, comparison}`, `{:error, :not_found}` (unknown snapshot), or
  `{:error, :view_not_found}` (the snapshot's view vanished).
  """
  def for_snapshot(snapshot_or_id, portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    today = Keyword.get(opts, :today, Date.utc_today())

    with {:ok, snapshot} <- Snapshots.fetch_snapshot(snapshot_or_id),
         scope when not is_tuple(scope) <- Buckets.load_scope(portfolio_id, snapshot.view_id) do
      base = base_currency(portfolio_id)
      as_of = snapshot.as_of

      candidates = frozen_quantities(portfolio_id, as_of, scope)
      fx = init_fx(candidates, base, as_of, today)
      {included, gaps} = split_by_valuability(candidates, as_of, base, fx)
      pricing = init_pricing(included, as_of, today)

      snapshot_series = walk(included, pricing, fx, base, as_of, today)
      real = real_side(portfolio_id, snapshot.view_id, as_of, today)

      {:ok, build_result(snapshot, base, snapshot_series, real, gaps, today)}
    end
  end

  # -- loading (shell) ---------------------------------------------------------

  defp base_currency(portfolio_id) do
    case Portfolios.get_portfolio(portfolio_id) do
      %{base_currency_code: ccy} when is_binary(ccy) -> ccy
      _ -> @hub
    end
  end

  # The frozen position set: ledger projected up to as-of, scope-filtered,
  # aggregated per security and enriched with the security's currency and name.
  defp frozen_quantities(portfolio_id, as_of, scope) do
    portfolio_id
    |> Ledger.positions_for_portfolio(as_of: as_of)
    |> Enum.filter(fn {{account_id, security_id}, _qty} ->
      Buckets.position_in_scope?(scope, account_id, security_id)
    end)
    |> Enum.reduce(%{}, fn {{_account_id, security_id}, qty}, acc ->
      Map.update(acc, security_id, qty, &Decimal.add(&1, qty))
    end)
    |> Enum.reject(fn {_security_id, qty} -> Decimal.equal?(qty, 0) end)
    |> Enum.map(fn {security_id, qty} ->
      security = Catalog.get_security!(security_id)

      %{
        security_id: security_id,
        security_name: security.name,
        currency: security.currency_code,
        quantity: qty
      }
    end)
  end

  # A position is valuable when it has a close on-or-before the as-of date AND
  # the walk's own converter can reach the base currency with the FX rates
  # seeded at the as-of date. The gate deliberately uses the SAME conversion
  # path as the daily walk (review finding: an `Fx.rate/3`-based gate admitted
  # same-currency positions the walk then zeroed out) — gate and walk cannot
  # disagree by construction. Anything else is a gap (AR-4).
  defp split_by_valuability(positions, as_of, base, fx_at_as_of) do
    {included, excluded} =
      Enum.split_with(positions, fn position ->
        has_seed_quote?(position, as_of) and
          convertible?(position.currency, base, fx_at_as_of)
      end)

    gaps =
      Enum.map(excluded, fn position ->
        %{
          security_id: position.security_id,
          security_name: position.security_name,
          reason: if(has_seed_quote?(position, as_of), do: :no_fx_rate, else: :no_quote_at_as_of)
        }
      end)

    {included, gaps}
  end

  defp has_seed_quote?(%{security_id: security_id}, as_of) do
    match?(%{close: %Decimal{}}, Quotes.at_or_before(security_id, as_of))
  end

  defp convertible?(currency, base, fx) do
    not is_nil(to_base_or_nil(@one, currency, base, fx))
  end

  defp fx_currency("GBX"), do: "GBP"
  defp fx_currency(ccy), do: ccy

  # Per-security price pointers: the seed is the last close on-or-before the
  # as-of date, upcoming points advance the walk (mirrors Performance).
  defp init_pricing(positions, as_of, today) do
    Map.new(positions, fn %{security_id: security_id} ->
      carried =
        case Quotes.at_or_before(security_id, as_of) do
          %{close: %Decimal{} = close} -> close
          _ -> nil
        end

      points =
        security_id
        |> Quotes.range(Date.add(as_of, 1), today)
        |> Enum.map(&%{date: &1.date, close: &1.close})

      {security_id, %{price: carried, upcoming: points}}
    end)
  end

  # EUR-hub rate pointers per non-hub currency (GBX prices through GBP × 100).
  defp init_fx(positions, base, as_of, today) do
    positions
    |> Enum.map(& &1.currency)
    |> Enum.concat([base])
    |> Enum.map(&fx_currency/1)
    |> Enum.uniq()
    |> Enum.reject(&(&1 in [nil, @hub]))
    |> Map.new(fn ccy ->
      carried =
        case Fx.hub_rate_before(ccy, as_of) do
          %{rate: %Decimal{} = rate} -> rate
          _ -> nil
        end

      points =
        ccy
        |> Fx.series(Date.add(as_of, 1))
        |> Enum.filter(&(Date.compare(&1.date, today) != :gt))
        |> Enum.map(&%{date: &1.date, rate: &1.rate})

      {ccy, %{rate: carried, upcoming: points}}
    end)
  end

  # -- the pure daily walk -----------------------------------------------------

  defp walk([], _pricing, _fx, _base, _as_of, _today), do: []

  defp walk(positions, pricing, fx, base, as_of, today) do
    as_of
    |> Date.range(today)
    |> Enum.reduce({[], pricing, fx}, fn day, {acc, pricing, fx} ->
      pricing = advance_map(pricing, day, &advance_price/2)
      fx = advance_map(fx, day, &advance_rate/2)
      value = day_value(positions, pricing, fx, base)
      {[%{date: day, value: value} | acc], pricing, fx}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp day_value(positions, pricing, fx, base) do
    Enum.reduce(positions, @zero, fn position, acc ->
      case Map.get(pricing, position.security_id) do
        %{price: %Decimal{} = close} ->
          native = Decimal.mult(position.quantity, close)
          Decimal.add(acc, to_base(native, position.currency, base, fx))

        _ ->
          acc
      end
    end)
  end

  defp advance_map(map, day, advance_fun) do
    Enum.reduce(map, map, fn {key, entry}, acc ->
      case advance_fun.(entry, day) do
        ^entry -> acc
        advanced -> Map.put(acc, key, advanced)
      end
    end)
  end

  defp advance_price(%{upcoming: [%{date: date, close: close} | rest]} = entry, day) do
    if Date.compare(date, day) in [:lt, :eq] do
      advance_price(%{entry | price: close, upcoming: rest}, day)
    else
      entry
    end
  end

  defp advance_price(entry, _day), do: entry

  defp advance_rate(%{upcoming: [%{date: date, rate: rate} | rest]} = entry, day) do
    if Date.compare(date, day) in [:lt, :eq] do
      advance_rate(%{entry | rate: rate, upcoming: rest}, day)
    else
      entry
    end
  end

  defp advance_rate(entry, _day), do: entry

  # ECB semantics: a stored rate is "quote currency per 1 EUR" (ADR-0007), so
  # from → base is amount × (base_rate / from_rate), each leg via the hub.
  # Excluded up front by split_by_valuability (which gates through the same
  # to_base_or_nil path); a mid-series rate can only carry forward, so the
  # zero fallback is unreachable for included positions.
  defp to_base(amount, currency, base, fx) do
    to_base_or_nil(amount, currency, base, fx) || @zero
  end

  # Same-currency needs no stored rate — mirrors Fx.rate/3's from == to
  # short-circuit, so e.g. a USD position in a USD-base portfolio values
  # correctly even when no EUR hub rate was ever synced (review finding).
  defp to_base_or_nil(amount, currency, base, _fx) when currency == base, do: amount

  defp to_base_or_nil(amount, currency, base, fx) do
    with {:ok, from_rate} <- eur_rate(currency, fx),
         {:ok, to_rate} <- eur_rate(base, fx) do
      Decimal.mult(amount, Decimal.div(to_rate, from_rate))
    else
      _ -> nil
    end
  end

  defp eur_rate(@hub, _fx), do: {:ok, @one}

  defp eur_rate("GBX", fx) do
    with {:ok, gbp} <- eur_rate("GBP", fx) do
      {:ok, Decimal.mult(gbp, @gbx_per_gbp)}
    end
  end

  defp eur_rate(ccy, fx) when is_binary(ccy) do
    case fx do
      %{^ccy => %{rate: %Decimal{} = rate}} -> {:ok, rate}
      _ -> {:error, :no_rate}
    end
  end

  defp eur_rate(_ccy, _fx), do: {:error, :no_rate}

  # -- the real side -----------------------------------------------------------

  # The scope's TTWROR chained since the as-of date, from the shared daily
  # walk. The baseline is the value on the as-of day; each later day chains
  # r_d = V_d / (V_{d−1} + F_d) − 1 — exactly `Performance.summarise/2`'s
  # period chaining with the as-of date as the period start. Returns a map of
  # date → growth factor since as-of (1 on the as-of day) plus the overall
  # since-as-of TTWROR.
  defp real_side(portfolio_id, view_id, as_of, today) do
    case Performance.analysis(portfolio_id, view: view_id, today: today) do
      %{daily: [_ | _] = daily} ->
        {up_to_as_of, since} = Enum.split_with(daily, &(Date.compare(&1.date, as_of) != :gt))

        case List.last(up_to_as_of) do
          # The walk starts after the as-of date: no baseline, no real side.
          nil ->
            %{factors: %{}, ttwror: nil}

          %{value: baseline} ->
            {factors, _prev, growth} =
              Enum.reduce(since, {%{as_of => @one}, baseline, @one}, fn point,
                                                                        {factors, prev, growth} ->
                growth = Decimal.mult(growth, day_factor(point, prev))
                {Map.put(factors, point.date, growth), point.value, growth}
              end)

            %{factors: factors, ttwror: Decimal.sub(growth, @one)}
        end

      _ ->
        %{factors: %{}, ttwror: nil}
    end
  end

  # r_d = V_d / (V_{d−1} + F_d) − 1, flows at the start of the day; a zero or
  # negative base contributes no return (mirrors Performance).
  defp day_factor(point, prev) do
    denominator = Decimal.add(prev, point.flow)

    if Decimal.compare(denominator, @zero) == :gt do
      Decimal.div(point.value, denominator)
    else
      @one
    end
  end

  # -- assembling the result ---------------------------------------------------

  defp build_result(snapshot, base, snapshot_series, real, gaps, today) do
    as_of_value = value_at(snapshot_series, 0)
    current_value = value_at(snapshot_series, -1)

    series =
      Enum.map(snapshot_series, fn point ->
        %{
          date: point.date,
          snapshot_value: point.value,
          snapshot_indexed: indexed(point.value, as_of_value),
          real_indexed: Map.get(real.factors, point.date)
        }
      end)

    %{
      snapshot: %{
        id: snapshot.id,
        name: snapshot.name,
        as_of: snapshot.as_of,
        view_id: snapshot.view_id
      },
      base_currency: base,
      as_of: snapshot.as_of,
      today: today,
      as_of_value: as_of_value || @zero,
      current_value: current_value || @zero,
      snapshot_return: snapshot_return(as_of_value, current_value),
      real_ttwror: real.ttwror,
      series: series,
      gaps: %{unvalued_securities: gaps},
      basis: %{
        method: "buy_and_hold_vs_ttwror",
        gross: true,
        price_return_only: true
      }
    }
  end

  defp value_at([], _index), do: nil
  defp value_at(series, 0), do: List.first(series).value
  defp value_at(series, -1), do: List.last(series).value

  defp indexed(_value, nil), do: nil

  defp indexed(value, as_of_value) do
    if Decimal.equal?(as_of_value, 0), do: nil, else: Decimal.div(value, as_of_value)
  end

  defp snapshot_return(nil, _current), do: nil
  defp snapshot_return(_as_of, nil), do: nil

  defp snapshot_return(as_of_value, current_value) do
    case indexed(current_value, as_of_value) do
      nil -> nil
      factor -> Decimal.sub(factor, @one)
    end
  end
end
