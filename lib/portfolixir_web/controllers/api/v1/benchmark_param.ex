defmodule PortfolixirWeb.Api.V1.BenchmarkParam do
  @moduledoc """
  Shared parsing for the `benchmark=` query parameter of the benchmark
  comparison reads (ADR-0046 §4): `rate:<decimal>` for a fixed effective
  annual rate (a decimal fraction — `rate:0.02` is 2 % p.a.) or
  `security:<id>` for a catalog security flagged `is_benchmark`.

  Returns `{:ok, {:rate, Decimal.t()} | {:security, Security.t()}}` or
  `{:error, {:benchmark, message}}` with the message the 422 carries: the
  parameter is required, a rate must be a finite decimal above -1, and a
  security must exist and be flagged — any other security is refused rather
  than silently compared against.
  """

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security

  @minus_one Decimal.new("-1")

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
    case Decimal.parse(raw) do
      {%Decimal{} = rate, ""} ->
        if Decimal.nan?(rate) or Decimal.inf?(rate) or Decimal.compare(rate, @minus_one) != :gt,
          do: invalid(),
          else: {:ok, {:rate, rate}}

      _malformed ->
        invalid()
    end
  end

  defp security(raw) when is_binary(raw) do
    with {id, ""} <- Integer.parse(raw),
         %Security{is_benchmark: true} = security <- Catalog.get_security(id) do
      {:ok, {:security, security}}
    else
      :error -> invalid()
      {_id, _rest} -> invalid()
      _unflagged_or_missing -> {:error, {:benchmark, "is not a benchmark security"}}
    end
  end

  defp blank, do: {:error, {:benchmark, "can't be blank"}}
  defp invalid, do: {:error, {:benchmark, "is invalid"}}
end
