defmodule Portfolixir.Catalog.SecurityMetrics do
  @moduledoc """
  The per-security derived metrics read (FR-39, [ADR-0047](../../docs/decisions/0047-derived-metrics-per-security-and-per-view.md)).

  The **shell** half of the engine/shell split (AR-2): it loads the security's
  split-adjusted close series (ADR-0028 §2) and hands it to
  `Portfolixir.Engines.PriceMetrics`, then wraps the answer in the computation
  basis the `AGENTS.md` metric rule requires **in the payload** — input series,
  reference, the treatment of gaps, and the assumptions the figures rest on.

  ## The series, and why it is not converted

  One input series: the security's own stored closes, in the **security's own
  currency** (ADR-0047 §1, identity I7). Converting to the base currency would
  fold the FX path into a figure that claims to be the instrument's own
  volatility, so nothing here reads an exchange rate. The portfolio-scope
  figures of FR-40 read a different series entirely — the daily valuation walk
  — and the two are never mixed.

  The whole stored history up to `as_of` is read rather than a fixed lookback:
  an SMA-200 needs 200 *closes*, which is roughly ten months of a daily series
  and a decade of a monthly one, so a calendar bound would silently refuse the
  sparse case.

  ## Lifetime `:none`, and the seam that is missing

  `security_metrics` registers with ADR-0039 §2 at lifetime **`:none`**, and
  the reason is the point (ADR-0047 §8): `Invalidation.after_quote_write/1`
  resolves through `BlastRadius.for_quote/1`, which answers *the portfolios
  that have ever transacted the security*. For a security **no portfolio has
  ever held** — a benchmark, a watch-only candidate, exactly the security whose
  research metrics are most wanted — that list is empty, so a quote write bumps
  **nothing** and any memo would be stale with no counter able to say so.
  Moving this analytic to `:request` or `:durable` needs the per-security basis
  key filed as its own issue by the batch, and not before.
  """

  import Ecto.Query

  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Clock
  alias Portfolixir.Derived
  alias Portfolixir.Engines.PriceMetrics
  alias Portfolixir.Repo

  # Older than any stored quote: the read takes the whole history up to as_of.
  @series_floor ~D[1900-01-01]

  @doc """
  `{:ok, payload}` for one security, or `{:error, :not_found}`.

  Options:

    * `:as_of` — the day the metrics are computed as of; closes dated after it
      are not read. Defaults to `Portfolixir.Clock.today/0`, because "how has
      this priced lately" is a local calendar question (#609).
  """
  @spec for_security(integer() | String.t(), keyword()) ::
          {:ok, map()} | {:error, :not_found}
  def for_security(security_id, opts \\ [])

  def for_security(security_id, opts) when is_binary(security_id) do
    case Integer.parse(security_id) do
      {id, ""} -> for_security(id, opts)
      _ -> {:error, :not_found}
    end
  end

  def for_security(security_id, opts) when is_integer(security_id) do
    case Repo.one(from(s in Security, where: s.id == ^security_id)) do
      nil -> {:error, :not_found}
      %Security{} = security -> {:ok, compute(security, Keyword.get(opts, :as_of, Clock.today()))}
    end
  end

  defp compute(%Security{} = security, %Date{} = as_of) do
    # Served through the derived-value axis (ADR-0039) as the
    # `:security_metrics` analytic. At the registry's `:none` lifetime this is
    # a plain call and the numbers are identical; the basis is the global one
    # because no per-security basis exists yet (ADR-0047 §8) — which is
    # exactly why the lifetime is `:none` and the key is never used.
    {:fresh, metrics} =
      Derived.fetch(
        :security_metrics,
        Derived.global_basis(),
        "#{security.id}:#{Date.to_iso8601(as_of)}",
        fn -> PriceMetrics.compute(series(security, as_of), as_of) end
      )

    %{
      security_id: security.id,
      security_name: security.name,
      currency_code: security.currency_code,
      as_of: as_of,
      latest_close: metrics.latest,
      computation_basis: computation_basis(security),
      metrics: Map.delete(metrics, :latest)
    }
  end

  defp series(%Security{} = security, %Date{} = as_of) do
    security.id
    |> Quotes.adjusted_range(@series_floor, as_of)
    |> Enum.map(&%{date: &1.date, close: &1.close})
  end

  # ADR-0039 C4 / AGENTS.md metric rule / ADR-0047 §6: the SHARED parts of the
  # basis sit once on the payload; the part that varies — the window — sits on
  # each metric beside its observation count, and the `window` line here says
  # so rather than naming a span no single metric was measured over.
  defp computation_basis(%Security{} = security) do
    %{
      input_series:
        "the security's own stored closes in the ADR-0028 §2 display basis " <>
          "(split-adjusted at read time; the stored rows are never mutated), in the " <>
          "security's own currency #{security.currency_code} — deliberately NOT converted " <>
          "to the base currency, because a price metric is a statement about the " <>
          "instrument and a conversion would fold the FX path into it (ADR-0047 §1)",
      window:
        "per metric: every metric carries the span it was measured over, or the span it " <>
          "was asked for when it refused, together with its observation count (ADR-0047 §6)",
      reference: nil,
      gaps:
        "a day with no stored close produces no return observation: returns are taken " <>
          "between consecutive stored closes and nothing is carried forward, because " <>
          "carrying a price forward and then differencing manufactures a calm 0 % day " <>
          "(ADR-0047 §5). A stored close of zero or below is not a price and is dropped " <>
          "before any metric reads the series, so the observation counts are prices " <>
          "actually read. Below its stated minimum a metric is null " <>
          "with insufficient_data and its observation count, never a number: " <>
          "#{PriceMetrics.min_return_observations()} return observations for volatility, " <>
          "n closes for an n-day moving average, 2 closes for the drawdown, and a close " <>
          "on or before the window's start for the momentum and the 52-week extremes. " <>
          "Momentum also refuses when the series does not reach FORWARD into the period " <>
          "— a history that stopped before the period began would otherwise report 0 % " <>
          "over a zero-day window",
      assumptions:
        "volatility is the POPULATION standard deviation of the window's simple daily " <>
          "returns (divided by the observation count, not by one less), annualized by " <>
          "√#{PriceMetrics.trading_days_per_year()} — the observations per year of a " <>
          "stored-close series (ADR-0047 §4). Distances, momentum and volatility are " <>
          "ratios, not percentages (0.05 is +5 %). The 52-week window is " <>
          "#{PriceMetrics.extremes_window_days()} days. Every figure is rounded at " <>
          "scale 6 on the way out; the square root is the one float operation of AR-3's " <>
          "island and nothing float is persisted"
    }
  end
end
