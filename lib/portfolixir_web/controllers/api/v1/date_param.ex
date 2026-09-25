defmodule PortfolixirWeb.Api.V1.DateParam do
  @moduledoc """
  The one parser of a date a read takes as a filter (E25 S4, F70; the S3/S4
  review round): `from`, `to`, `as_of`.

  It is `Portfolixir.Input.BoundedDate.parse/1`, the rule every writer
  meets, so a read accepts exactly the dates a writer can store: an ISO 8601
  calendar date `YYYY-MM-DD` from `BoundedDate.earliest/0` to
  `BoundedDate.latest/0`. Anything else is a **422 naming the parameter**
  instead of a date the database cannot hold reaching a query, which failed
  there with a 500.
  """

  alias Portfolixir.Input.BoundedDate

  @doc """
  `{:ok, nil}` when `key` is absent or blank, `{:ok, date}` for a bounded
  date, `:error` for anything else.
  """
  @spec parse(map(), String.t()) :: {:ok, Date.t() | nil} | :error
  def parse(params, key) when is_map(params) and is_binary(key) do
    case Map.get(params, key) do
      value when value in [nil, ""] ->
        {:ok, nil}

      value ->
        case BoundedDate.parse(value) do
          {:ok, date} -> {:ok, date}
          {:error, _reason} -> :error
        end
    end
  end
end
