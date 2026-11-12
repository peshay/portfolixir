defmodule Portfolixir.Crashes do
  @moduledoc """
  Crash windows (FR-54, idea I24; ADR-0058): declines of 10 % or more in
  the stored closes of one benchmark security the operator chooses, the
  **crash benchmark** (`Portfolixir.Settings.crash_benchmark_security_id/0`,
  §1). The rule fixes a window's dates and is derived at read, never stored
  (§2), so every agent and the screen read the same windows.

  Unset, the rule detects nothing, and the read says why:
  `detected: []` with `reason: "no_crash_benchmark"` (§1).
  """

  alias Portfolixir.Catalog.BenchmarkSecurity
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Settings

  @typedoc "The detected windows over the crash benchmark, or why there are none."
  @type detection :: %{
          benchmark: Security.t() | nil,
          detected: [map()],
          reason: String.t() | nil
        }

  @doc """
  The windows the rule detects over the crash benchmark's closes (ADR-0058
  §1, §2). With no crash benchmark chosen: `detected: []`, `reason:
  "no_crash_benchmark"`, `benchmark: nil`.
  """
  @spec detected() :: detection()
  def detected do
    case Settings.crash_benchmark_security_id() do
      nil -> none("no_crash_benchmark")
      id -> detected_for(id)
    end
  end

  # The rule over the benchmark's closes is ADR-0058 §2 (Sprint 29 C2).
  defp detected_for(id) do
    case BenchmarkSecurity.resolve(id) do
      {:ok, security} -> %{benchmark: security, detected: [], reason: nil}
      {:error, _refusal} -> none("crash_benchmark_unavailable")
    end
  end

  defp none(reason), do: %{benchmark: nil, detected: [], reason: reason}
end
