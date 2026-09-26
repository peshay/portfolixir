defmodule PortfolixirWeb.Api.V1.BenchmarkParam do
  @moduledoc """
  Shared parsing for the `benchmark=` query parameter of the benchmark
  comparison reads (ADR-0046 §4): `rate:<decimal>` for a fixed effective
  annual rate (a decimal fraction — `rate:0.02` is 2 % p.a.) or
  `security:<id>` for a catalog security flagged `is_benchmark`.

  Returns `{:ok, {:rate, Decimal.t()} | {:security, Security.t()}}` or
  `{:error, {:benchmark, message}}` with the message the 422 carries: the
  parameter is required, a rate must be a finite decimal inside the engine's
  bound (`Portfolixir.Portfolios.Performance.Benchmark.valid_rate?/1`:
  -99.9999 % to 1000 % p.a.), and a security must exist and be flagged — any
  other security is refused rather than silently compared against.
  """

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Input.BoundedDecimal
  alias Portfolixir.Portfolios.Performance.Benchmark
  alias PortfolixirWeb.Api.V1.IdParam

  @spec resolve(map()) ::
          {:ok, {:rate, Decimal.t()} | {:security, Security.t()}}
          | {:error, {:benchmark, String.t()}}
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
         %Security{is_benchmark: true} = security <- Catalog.get_security(id) do
      {:ok, {:security, security}}
    else
      :error -> invalid()
      _unflagged_or_missing -> {:error, {:benchmark, "is not a benchmark security"}}
    end
  end

  defp blank, do: {:error, {:benchmark, "can't be blank"}}
  defp invalid, do: {:error, {:benchmark, "is invalid"}}
end
