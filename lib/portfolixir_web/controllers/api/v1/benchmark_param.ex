defmodule PortfolixirWeb.Api.V1.BenchmarkParam do
  @moduledoc """
  Shared parsing for the `benchmark=` query parameter of the benchmark
  comparison reads (ADR-0046 §4): `rate:<decimal>` for a fixed effective
  annual rate (a decimal fraction — `rate:0.02` is 2 % p.a.) or
  `security:<id>` for any catalog security with at least one stored quote,
  flagged `is_benchmark` or not (ADR-0046's amendment of 2026-11-07, #1416;
  the rule is `Portfolixir.Catalog.BenchmarkSecurity.resolve/1`).

  Returns `{:ok, {:rate, Decimal.t()} | {:security, Security.t()}}` or
  `{:error, {:benchmark, errors}}` with the `errors` object the 422 carries:
  the parameter is required, a rate must be a finite decimal inside the
  engine's bound (`Portfolixir.Portfolios.Performance.Benchmark.valid_rate?/1`:
  -99.9999 % to 1000 % p.a.), and a security must exist and have a stored
  quote (`has no stored quote` otherwise) — no security is silently compared
  against an empty series.

  A security a merge took away is refused as `is not a benchmark security`,
  and when the survivor at the live end of its merge chain is a security the
  rule accepts the refusal names it as `merged_into {kind, id}`, as the
  merged-away reads do (#959; ADR-0050 §12, `Portfolixir.Lifecycle.merged_into/2`):
  a retry with that id compares. A survivor without a stored quote, a chain
  that ends at a row deleted since, and an id no merge names are refused
  without it.
  """

  alias Portfolixir.Catalog.BenchmarkSecurity
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Input.BoundedDecimal
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
    with {:ok, id} <- IdParam.parse(raw),
         {:ok, security} <- BenchmarkSecurity.resolve(id) do
      {:ok, {:security, security}}
    else
      :error ->
        invalid()

      {:error, :no_quote} ->
        refused(%{benchmark: ["has no stored quote"]})

      {:error, {:merged_into, survivor}} ->
        not_a_benchmark(%{merged_into: %{kind: "security", id: survivor}})

      {:error, :not_found} ->
        not_a_benchmark(%{})
    end
  end

  defp not_a_benchmark(extra),
    do: refused(Map.put(extra, :benchmark, ["is not a benchmark security"]))

  defp refused(errors), do: {:error, {:benchmark, errors}}

  defp blank, do: {:error, {:benchmark, %{benchmark: ["can't be blank"]}}}
  defp invalid, do: {:error, {:benchmark, %{benchmark: ["is invalid"]}}}
end
