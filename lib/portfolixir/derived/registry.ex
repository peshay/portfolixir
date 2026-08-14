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
  @analytics %{
    performance_analysis: %{computation_version: 1, default_lifetime: :request},
    performance_view_analysis: %{computation_version: 1, default_lifetime: :request}
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
