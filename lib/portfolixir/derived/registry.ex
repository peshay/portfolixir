defmodule Portfolixir.Derived.Registry do
  @moduledoc """
  The registry of derived analytics (ADR-0039 §2).

  Every analytic that registers here is **eligible for any lifetime** — a
  curated list of "cacheable values" is explicitly rejected by the ADR. Which
  analytics actually run `:durable` is a configuration decision informed by
  measurement (`config :portfolixir, Portfolixir.Derived, lifetimes: [...]`),
  never an architectural one.

  Each entry carries its **computation version**: the data-version counter
  covers data changes, not code changes, so a formula change must bump this
  number or the durable layer would silently keep serving the old formula's
  results (ADR-0039 §5, "computation version in the key").
  """

  @lifetimes [:none, :request, :durable]

  # analytic_id => %{computation_version, default_lifetime}
  #
  # `:request` as the default is ADR-0032's memo carried forward: everything
  # registered gets the volatile memo for free; `:durable` is opted into per
  # analytic via configuration (the C3 activation).
  # Computation versions. Bumped whenever the SHAPE or the arithmetic of a
  # stored payload changes, because the data-version counter covers data
  # changes and not code changes -- without the bump the durable tier keeps
  # serving rows computed by the old formula.
  #
  # v2 (2026-08-18, #708): every walk point gained `trade_costs`. A row stored
  # at v1 has points without it, and the snapshot comparison's pre-cost chain
  # would read those as a silent zero -- a cost figure of zero is exactly the
  # wrong answer, because it claims the changes were free.
  #
  # v3 (2026-09-15, #779 and #610, Sprint 11 Lane X): a delivery carrying a
  # booked price enters the day's flow and the lot queue at that price, and a
  # retired security's stale quote no longer counts as a measurement. Both
  # move `flow` and `basis` on stored points, so rows computed at v2 must not
  # be served.
  @analytics %{
    performance_analysis: %{computation_version: 3, default_lifetime: :request},
    performance_view_analysis: %{computation_version: 3, default_lifetime: :request},
    # The benchmark comparison (ADR-0046 §5, Sprint 11 Lane B): a read model
    # over a walk and a benchmark's price series, keyed under the global
    # basis because a benchmark the portfolio never held is outside the
    # portfolio's own blast radius.
    # v2 (E25 S4, G03): the stored value carries the walk it was built from
    # (`%{walk:, comparison:}`), checked on every hit instead of keyed.
    benchmark_comparison: %{computation_version: 2, default_lifetime: :request},
    # The per-security derived metrics (ADR-0047 §8, Sprint 13 Lane A1).
    # `:none` is the DEFAULT WITH A REASON, not a placeholder. The portfolio
    # radius of a quote write is empty for a security no portfolio has ever
    # held -- precisely the security whose research metrics are most wanted --
    # so the portfolio bases cannot invalidate this analytic. The seam that
    # can now exists (#825): `DataVersion.security_basis/1`, bumped by
    # `after_quote_write/1` and by the security's own writes and splits. The
    # ADR-0039 C3 measurement that would justify moving to `:request` or
    # `:durable` is therefore AVAILABLE, NOT TAKEN; `SecurityMetrics` already
    # keys under the security basis, so the move is that measurement.
    security_metrics: %{computation_version: 1, default_lifetime: :none},
    # The per-portfolio and per-view derived metrics (ADR-0047 §8, Sprint 14
    # Lane A1): the walk-derived figures and the Top-N correlation matrix on
    # the risk read. `:request` like its neighbours, keyed under the portfolio
    # basis exactly as `performance_analysis` is -- every write that moves the
    # walk, a held security's quote or an exchange rate bumps that basis.
    # v2 (E25 S4, F72): the correlation matrix covers a bounded number of
    # leading names and says how many (`leading_names`); a v1 payload lacks it.
    portfolio_metrics: %{computation_version: 2, default_lifetime: :request},
    # The policy findings (ADR-0049 §5, Sprint 15 Lane A2): the operator's
    # rules evaluated over the reads above. `:request`, keyed under the
    # portfolio basis AND the portfolio's rules counter (carried in the entry
    # key): a write that moves a measure bumps the first, a rule write the
    # second, and a finding that outlived an edited cap would be a stale
    # answer to the only question the read exists for.
    policy_findings: %{computation_version: 1, default_lifetime: :request}
  }

  @doc "All registered analytic ids."
  @spec analytics() :: [atom()]
  def analytics, do: Map.keys(@analytics)

  @doc "Whether `analytic_id` is registered."
  @spec registered?(atom()) :: boolean()
  def registered?(analytic_id), do: Map.has_key?(@analytics, analytic_id)

  @doc "The computation version of a registered analytic. Raises for unknown ids."
  @spec computation_version!(atom()) :: pos_integer()
  def computation_version!(analytic_id) do
    entry(analytic_id).computation_version
  end

  @doc """
  The configured lifetime of an analytic: the `:lifetimes` configuration entry
  where one is set, the registry default otherwise. With the derived layer
  disabled everything is `:none` — one "off" state, exactly like ADR-0032's
  cache switch. Raises for unknown ids and for invalid configured lifetimes.
  """
  @spec lifetime(atom()) :: :none | :request | :durable
  def lifetime(analytic_id) do
    default = entry(analytic_id).default_lifetime

    if Portfolixir.Derived.enabled?() do
      :portfolixir
      |> Application.get_env(Portfolixir.Derived, [])
      |> Keyword.get(:lifetimes, [])
      |> Keyword.get(analytic_id, default)
      |> validate_lifetime(analytic_id)
    else
      :none
    end
  end

  defp entry(analytic_id) do
    case Map.fetch(@analytics, analytic_id) do
      {:ok, entry} ->
        entry

      :error ->
        raise ArgumentError,
              "unregistered derived analytic #{inspect(analytic_id)} — register it in " <>
                "#{inspect(__MODULE__)} with a computation version (ADR-0039 §2)"
    end
  end

  defp validate_lifetime(lifetime, _analytic_id) when lifetime in @lifetimes, do: lifetime

  defp validate_lifetime(other, analytic_id) do
    raise ArgumentError,
          "invalid derived lifetime #{inspect(other)} configured for " <>
            "#{inspect(analytic_id)} — expected one of #{inspect(@lifetimes)}"
  end
end
