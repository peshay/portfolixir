defmodule PortfolixirWeb.Api.V1.BenchmarkParam do
  @moduledoc """
  Shared parsing for the `benchmark=` query parameter of the benchmark
  comparison reads (ADR-0046 §4): `rate:<decimal>` for a fixed effective
  annual rate (a decimal fraction — `rate:0.02` is 2 % p.a.) or
  `security:<id>` for a catalog security flagged `is_benchmark`.

  Returns `{:ok, {:rate, Decimal.t()} | {:security, Security.t()}}` or
  `{:error, {:benchmark, errors}}` with the `errors` object the 422 carries:
  the parameter is required, a rate must be a finite decimal inside the
  engine's bound (`Portfolixir.Portfolios.Performance.Benchmark.valid_rate?/1`:
  -99.9999 % to 1000 % p.a.), and a security must exist and be flagged — any
  other security is refused rather than silently compared against.

  A security a merge took away is refused the same way, and when the
  survivor at the live end of its merge chain is a flagged benchmark
  security the refusal names it as `merged_into {kind, id}`, as the
  merged-away reads do (#959; ADR-0050 §12, `Portfolixir.Lifecycle.merged_into/2`):
  a retry with that id compares. A survivor that is not flagged, a chain that
  ends at a row deleted since, and an id no merge names are refused without
  it.
  """

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Input.BoundedDecimal
  alias Portfolixir.Lifecycle
  alias Portfolixir.Portfolios.Performance.Benchmark
  alias PortfolixirWeb.Api.V1.IdParam

  @typedoc "The `errors` object of a 422 on `benchmark=`."
  @type errors :: %{
          required(:benchmark) => [String.t()],
          optional(:merged_into) => %{kind: String.t(), id: integer()}
        }

  @spec resolve(map()) ::
          {:ok, {:rate, Decimal.t()} | {:security, Security.t()}}
          | {:error, {:benchmark, errors()}}
  def resolve(params) do
    case Map.get(params, "benchmark") do
      nil -> blank()
      "" -> blank()
      "rate:" <> rate -> rate(rate)
      "security:" <> id -> security(id)
      _other -> invalid()
    end
  end

  defp rate(raw) when is_binary(raw) do
    # The shared finite-decimal parser (E25 S4, G15).
    case BoundedDecimal.parse(raw) do
      {:ok, rate} ->
        # One bound, the engine's (the IRR solver's domain, -99.9999 % to
        # 1000 % p.a.): a rate outside it crashed the arithmetic before the
        # comparison could refuse it (closing-act finding).
        if Benchmark.valid_rate?(rate), do: {:ok, {:rate, rate}}, else: invalid()

      :error ->
        invalid()
    end
  end

  defp security(raw) when is_binary(raw) do
    # IdParam refuses an id past the int8 range, so it never reaches the
    # database encoder.
    case IdParam.parse(raw) do
      {:ok, id} -> flagged(id, Catalog.get_security(id))
      :error -> invalid()
    end
  end

  defp flagged(_id, %Security{is_benchmark: true} = security), do: {:ok, {:security, security}}
  defp flagged(_id, %Security{}), do: not_a_benchmark(%{})

  # #959: no such row. When a merge took it away and the live end of its
  # chain is a benchmark security, the refusal names that row, the one a
  # retry can compare against; otherwise it is today's refusal.
  defp flagged(id, nil) do
    with survivor when is_integer(survivor) <- Lifecycle.merged_into(:security, id),
         %Security{is_benchmark: true} <- Catalog.get_security(survivor) do
      not_a_benchmark(%{merged_into: %{kind: "security", id: survivor}})
    else
      _no_benchmark_survivor -> not_a_benchmark(%{})
    end
  end

  defp not_a_benchmark(extra),
    do: {:error, {:benchmark, Map.put(extra, :benchmark, ["is not a benchmark security"])}}

  defp blank, do: {:error, {:benchmark, %{benchmark: ["can't be blank"]}}}
  defp invalid, do: {:error, {:benchmark, %{benchmark: ["is invalid"]}}}
end
