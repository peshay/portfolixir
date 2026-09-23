defmodule PortfolixirWeb.Api.V1.IntegerParam do
  @moduledoc """
  The bounded non-negative integer parameter (#856): an `offset` or a horizon
  in `days` that a 20-digit value can reach the database with, or walk
  `Date.add/2` for minutes with.

  A value above the stated bound is a **422 naming the parameter**, the error
  contract of `docs/integration/api-and-mcp.md`, rather than an
  `DBConnection.EncodeError` (a 500) or a request that never answers. The
  bounds are generous — nobody pages ten million rows in or asks about a
  horizon of more than ten years — and stated here so the documentation and
  the tests read one number.

  `limit` has its own family contract (capped and echoed, #771/#811) and the
  security events' `days` keeps the capped-and-echoed contract it shipped
  with (Sprint 13); both were already bounded.
  """

  @max_offset 1_000_000
  @max_days 3650

  @doc "The largest `offset` the list reads accept."
  @spec max_offset() :: pos_integer()
  def max_offset, do: @max_offset

  @doc "The widest horizon, in days, the research log's reads accept (ten years)."
  @spec max_days() :: pos_integer()
  def max_days, do: @max_days

  @doc """
  `{:ok, value}` — `default` when the parameter is absent or blank — or
  `{:error, key}` for anything that is not an integer in `0..max`.
  """
  @spec parse(map(), String.t(), non_neg_integer() | nil, pos_integer()) ::
          {:ok, non_neg_integer() | nil} | {:error, String.t()}
  def parse(params, key, default, max) when is_map(params) and is_binary(key) do
    case Map.get(params, key) do
      value when value in [nil, ""] -> {:ok, default}
      value when is_integer(value) -> in_range(value, key, max)
      value when is_binary(value) -> parse_binary(value, key, max)
      _other -> {:error, key}
    end
  end

  defp parse_binary(value, key, max) do
    case Integer.parse(value) do
      {int, ""} -> in_range(int, key, max)
      _malformed -> {:error, key}
    end
  end

  defp in_range(int, _key, max) when int >= 0 and int <= max, do: {:ok, int}
  defp in_range(_int, key, _max), do: {:error, key}
end
