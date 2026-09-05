defmodule PortfolixirWeb.Api.V1.ListLimit do
  @moduledoc """
  The `limit` parameter of the list reads (#771): a generous default, a hard
  maximum, and one parser so every read spells it the same way.

  The defaults are sized so a realistic instance (hundreds of securities,
  tens of thousands of transactions, NFR-8) never sees them; they bound what
  one call can ask the instance to materialise, not what an operator can
  read. The quote upsert has a row cap for the same reason.
  """

  @quote_upsert_max_rows 10_000

  @doc "Rows one quote upsert may carry."
  @spec quote_upsert_max_rows() :: pos_integer()
  def quote_upsert_max_rows, do: @quote_upsert_max_rows

  @doc """
  `{:ok, limit}` — the default when absent or blank, else the value capped at
  `max` — or `{:error, :limit}` for zero, negative or non-numeric input.
  """
  @spec parse(map(), pos_integer(), pos_integer()) :: {:ok, pos_integer()} | {:error, :limit}
  def parse(params, default, max) when is_map(params) do
    case Map.get(params, "limit") do
      value when value in [nil, ""] -> {:ok, default}
      value when is_integer(value) and value > 0 -> {:ok, min(value, max)}
      value when is_binary(value) -> parse_binary(value, max)
      _ -> {:error, :limit}
    end
  end

  defp parse_binary(value, max) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> {:ok, min(int, max)}
      _ -> {:error, :limit}
    end
  end
end
