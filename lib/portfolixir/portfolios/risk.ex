defmodule Portfolixir.Portfolios.Risk do
  @moduledoc """
  Read-time risk/concentration lens for one portfolio (FR8–FR10).

  Pure derivation from the live `Portfolixir.Portfolios.Valuation` and the
  securities' asset classification — nothing is stored, so the lens is
  deterministic on read (ADR-0004, ADR-0012). All figures cross the API/MCP
  boundary as full-precision Decimal strings (ADR-0016): no rounding happens
  here.

  Everything is computed over the **steerable basis**: the valued positions'
  market value (scoped by the active view, ADR-0018), the same basis the
  allocation drift uses. To keep a holding out of this basis while it still
  counts toward total wealth, tag it with a bucket and exclude that bucket from
  the active view; the position then falls outside the scoped valuation and does
  not dilute the concentration view either. A security held in several depots is
  merged into one single-name exposure first; weights are the merged value as a
  share of the steerable basis.

  Weights, caps and HHI all live on a **percentage scale (0–100)** so the three
  read consistently in one response:

    * **Single-name Top-N** (`top_holdings`) — the largest single-name exposures,
      default `N = 10` (override with `:top_n`), each with its percentage weight
      and a `severity` (`ok`/`warn`/`hard`) from the instrument-type-aware
      thresholds below (FR8/FR10).
    * **HHI** (`hhi`) — the Herfindahl-Hirschman Index of the single-name
      percentage weights (`Σ weight²`), on the 0–10000 scale, with a `band`:
      `low` (`< 1500`), `moderate` (`[1500, 2500]`), `concentrated` (`> 2500`).
      Bands are overridable with `:hhi_bands` (FR8).
    * **Asset-class cap violations** (`asset_class_violations`) — opt-in caps per
      asset class (`:asset_class_caps`, no shipped defaults). Only classes whose
      current percentage weight exceeds the configured cap come back, each with
      the asset class, current weight, cap and overage in percentage points
      (FR9).

  ## Instrument-type-aware single-name thresholds (FR10)

  The Top-N severity uses shipped defaults, overridable per call:

    * a single **stock** (any non-ETF instrument) — `warn` above `7`, `hard`
      above `10`;
    * an **ETF** (the `etf` asset class, reusing the existing classification
      signal — issue #325) — `warn` above `25`, no `hard`.

  Override with `:stock_thresholds` (`%{warn: Decimal, hard: Decimal}`) and
  `:etf_thresholds` (`%{warn: Decimal}`). A breach is a real threshold crossing,
  never noise (counter-metric CM3): `severity` is `ok` until the weight is
  strictly above the relevant `warn`.
  """

  alias Portfolixir.Portfolios.Valuation

  @zero Decimal.new("0")
  @hundred Decimal.new("100")
  @default_top_n 10

  # Default HHI bands on the 0–10000 scale (FR8).
  @default_low Decimal.new("1500")
  @default_high Decimal.new("2500")

  # Default instrument-type-aware single-name thresholds, percentage scale (FR10).
  @default_stock_warn Decimal.new("7")
  @default_stock_hard Decimal.new("10")
  @default_etf_warn Decimal.new("25")

  @etf_asset_class "etf"

  @doc """
  Builds the risk/concentration lens for `portfolio_id`.

  Options:

    * `:top_n` – number of single-name entries to return (default `10`).
    * `:hhi_bands` – `%{low: Decimal, high: Decimal}` HHI band cutoffs.
    * `:asset_class_caps` – `%{asset_class => Decimal}` percentage caps (opt-in).
    * `:stock_thresholds` – `%{warn: Decimal, hard: Decimal}` stock cutoffs.
    * `:etf_thresholds` – `%{warn: Decimal}` ETF cutoff.
    * forwarded to `Valuation.for_portfolio/2` for tests: `:prices`,
      `:base_currency`.

  Returns the lens map. The portfolio is assumed to exist; the controller checks
  existence and forwards a `404` otherwise.
  """
  def for_portfolio(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    # `:view` scopes risk by flowing through to the valuation it is computed over
    # (#444); no view -> unscoped -> identical to today.
    {valuation_opts, risk_opts} =
      Keyword.split(opts, [:prices, :base_currency, :view])

    valuation = Valuation.for_portfolio(portfolio_id, valuation_opts)

    exposures =
      valuation
      |> steerable_positions()
      |> merge_by_security()

    basis = sum_values(exposures)
    weighted = Enum.map(exposures, &put_weight(&1, basis))

    %{
      portfolio_id: valuation.portfolio_id,
      base_currency: valuation.base_currency,
      steerable_basis: basis,
      top_holdings: top_holdings(weighted, risk_opts),
      hhi: hhi(weighted, risk_opts),
      asset_class_violations: asset_class_violations(weighted, basis, risk_opts)
    }
  end

  # The steerable basis: the valued positions (scoped by the active view,
  # ADR-0018). Unvalued positions carry no market value and are dropped,
  # mirroring the allocation breakdown.
  defp steerable_positions(valuation) do
    Enum.filter(valuation.positions, & &1.valued)
  end

  # One single-name exposure per security: a security held across several depots
  # is summed into one line (concentration is per security, not per depot).
  defp merge_by_security(positions) do
    positions
    |> Enum.group_by(& &1.security_id)
    |> Enum.map(fn {security_id, grouped} ->
      first = hd(grouped)

      %{
        security_id: security_id,
        security_name: first.security_name,
        asset_class: first.asset_class,
        market_value: sum_values(grouped)
      }
    end)
  end

  defp put_weight(exposure, basis) do
    Map.put(exposure, :weight, percentage(exposure.market_value, basis))
  end

  # The largest single-name exposures first, capped at N (default 10), each
  # tagged with its instrument-type-aware severity (FR8/FR10). Ties on weight
  # break by security_id so the order is deterministic.
  defp top_holdings(weighted, opts) do
    top_n = Keyword.get(opts, :top_n, @default_top_n)
    {stock, etf} = thresholds(opts)

    weighted
    |> Enum.sort(&order_desc/2)
    |> Enum.take(top_n)
    |> Enum.map(fn exposure ->
      %{
        security_id: exposure.security_id,
        security_name: exposure.security_name,
        asset_class: exposure.asset_class,
        market_value: exposure.market_value,
        weight: exposure.weight,
        severity: severity(exposure, stock, etf)
      }
    end)
  end

  # Largest weight first; equal weights break by ascending security_id so the
  # Top-N order is deterministic regardless of the valuation's input order.
  defp order_desc(a, b) do
    case Decimal.compare(a.weight, b.weight) do
      :gt -> true
      :lt -> false
      :eq -> a.security_id <= b.security_id
    end
  end

  # ETF severity reuses the asset-class signal (issue #325): an ETF only ever
  # warns (no hard cap), every other instrument follows the stock thresholds.
  defp severity(%{asset_class: @etf_asset_class} = exposure, _stock, etf) do
    if above?(exposure.weight, etf.warn), do: "warn", else: "ok"
  end

  defp severity(exposure, stock, _etf) do
    cond do
      above?(exposure.weight, stock.hard) -> "hard"
      above?(exposure.weight, stock.warn) -> "warn"
      true -> "ok"
    end
  end

  # HHI over the single-name percentage weights: Σ weight², on the 0–10000 scale,
  # with a band from the (overridable) cutoffs (FR8).
  defp hhi(weighted, opts) do
    %{low: low, high: high} = bands(opts)

    value =
      Enum.reduce(weighted, @zero, fn exposure, acc ->
        Decimal.add(acc, Decimal.mult(exposure.weight, exposure.weight))
      end)

    %{value: value, band: band(value, low, high)}
  end

  defp band(value, low, high) do
    cond do
      Decimal.compare(value, low) == :lt -> "low"
      Decimal.compare(value, high) == :gt -> "concentrated"
      true -> "moderate"
    end
  end

  # Opt-in asset-class caps (FR9): group the steerable value by asset class, and
  # return only the classes whose current percentage weight exceeds the cap, with
  # the overage in percentage points. No caps configured ⇒ no violations.
  defp asset_class_violations(weighted, basis, opts) do
    caps = Keyword.get(opts, :asset_class_caps, %{})

    weight_by_class =
      weighted
      |> Enum.group_by(& &1.asset_class)
      |> Map.new(fn {asset_class, exposures} ->
        {asset_class, percentage(sum_values(exposures), basis)}
      end)

    caps
    |> Enum.flat_map(fn {asset_class, cap} ->
      current = Map.get(weight_by_class, asset_class, @zero)

      if above?(current, cap) do
        [
          %{
            asset_class: asset_class,
            current_weight: current,
            cap: cap,
            overage: Decimal.sub(current, cap)
          }
        ]
      else
        []
      end
    end)
    |> Enum.sort_by(& &1.asset_class)
  end

  defp thresholds(opts) do
    stock = Keyword.get(opts, :stock_thresholds, %{})
    etf = Keyword.get(opts, :etf_thresholds, %{})

    {
      %{
        warn: Map.get(stock, :warn, @default_stock_warn),
        hard: Map.get(stock, :hard, @default_stock_hard)
      },
      %{warn: Map.get(etf, :warn, @default_etf_warn)}
    }
  end

  defp bands(opts) do
    bands = Keyword.get(opts, :hhi_bands, %{})
    %{low: Map.get(bands, :low, @default_low), high: Map.get(bands, :high, @default_high)}
  end

  defp sum_values(exposures) do
    Enum.reduce(exposures, @zero, &Decimal.add(&2, &1.market_value))
  end

  # A market value as a percentage (0–100 scale) of the basis; `0` when the basis
  # is empty so an empty portfolio never divides by zero.
  defp percentage(value, basis) do
    if Decimal.equal?(basis, @zero) do
      @zero
    else
      value |> Decimal.div(basis) |> Decimal.mult(@hundred)
    end
  end

  defp above?(value, threshold), do: Decimal.compare(value, threshold) == :gt
end
