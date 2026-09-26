defmodule PortfolixirWeb.Api.V1.IdParam do
  @moduledoc """
  The one id parser of the JSON API (#840).

  Every table's primary key is a PostgreSQL `bigint` (`bigserial`), so an id
  is a positive integer no larger than `9_223_372_036_854_775_807`. Anything
  else — a value past that bound included — cannot name a record, and the
  controllers answer it exactly as they answer a malformed id. Before this
  module each controller carried its own `Integer.parse/1` copy with no upper
  bound, so an id like `99999999999999999999` reached the driver and raised
  `DBConnection.EncodeError`: a 500 where the contract promises a 404 or 422.

  `PortfolixirWeb.Api.V1.IdRangeGuard` applies `int8?/1` to every id-shaped
  param before a controller runs, so a route added later cannot forget it;
  the controllers use `parse/1` for their own well-formedness checks. The
  pages read every id they are handed through it too, by way of
  `PortfolixirWeb.LiveParam` (E25 S4), so a page and the API accept exactly
  the same ids.
  """

  @max_int8 9_223_372_036_854_775_807
  @min_int8 -9_223_372_036_854_775_808

  @doc """
  Parses an id from a path, query or JSON body value.

  Returns `{:ok, id}` for a positive integer within the `bigint` range, given
  as an integer or as a string of digits; `:error` for anything else.
  """
  @spec parse(term()) :: {:ok, pos_integer()} | :error
  def parse(value) when is_integer(value) and value > 0 and value <= @max_int8,
    do: {:ok, value}

  def parse(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> parse(id)
      _malformed -> :error
    end
  end

  def parse(_value), do: :error

  @doc "Parses a list of ids whole: `{:ok, ids}` or `:error` if any one fails."
  @spec parse_list(term()) :: {:ok, [pos_integer()]} | :error
  def parse_list(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case parse(value) do
        {:ok, id} -> {:cont, {:ok, [id | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      :error -> :error
    end
  end

  def parse_list(_values), do: :error

  @doc """
  Whether an integer-shaped value fits a `bigint` column.

  `false` only for an integer (or a string of digits) outside the `bigint`
  range — the one value class the driver refuses to encode. Anything that is
  not integer-shaped is `true`: it is not this check's business, and the
  controllers already answer it as malformed.
  """
  @spec int8?(term()) :: boolean()
  def int8?(value) when is_integer(value), do: value >= @min_int8 and value <= @max_int8

  def int8?(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int8?(int)
      _not_integer_shaped -> true
    end
  end

  def int8?(_value), do: true
end
