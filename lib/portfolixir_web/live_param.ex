defmodule PortfolixirWeb.LiveParam do
  @moduledoc """
  The one reader of what a page is handed (E25 S4, F16, F17, #868): its URL
  parameters and its event payloads.

  Both arrive from the client, so both can carry anything JSON or a query
  string can express — a string where an id was expected, a number past what
  any column holds, a list, a map, nothing at all. A page that parses such a
  value itself either crashes its process on the unexpected shape or hands an
  out-of-range integer to a query, which the driver refuses to encode. Every
  LiveView reads an id, a year, a bounded integer or a nested form map through
  this module instead, and a value it cannot read comes back as `nil` (or an
  empty map), which the page treats as "nothing asked": the URL falls back to
  its default and the event changes nothing.

  Ids go through `PortfolixirWeb.Api.V1.IdParam`, the JSON API's own id
  parser, so a page and the API accept exactly the same ids.
  """

  alias PortfolixirWeb.Api.V1.IdParam

  # A year a calendar names and the `int4` year columns hold — the bound the
  # tax API applies to its own `year` (#856).
  @years 1..9999

  @doc """
  An id — a positive integer within the `bigint` range, given as an integer
  or a string of digits — or `nil`.
  """
  @spec id(term()) :: pos_integer() | nil
  def id(value) do
    case IdParam.parse(value) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  @doc "`id/1` in the `{:ok, id}` / `:error` shape, for a `with` chain."
  @spec fetch_id(term()) :: {:ok, pos_integer()} | :error
  def fetch_id(value), do: IdParam.parse(value)

  @doc """
  A list of ids, from a list or a comma-separated string; an entry that is
  not an id is dropped, and anything that is neither shape reads as `[]`.
  """
  @spec ids(term()) :: [pos_integer()]
  def ids(values) when is_list(values), do: values |> Enum.map(&id/1) |> Enum.reject(&is_nil/1)

  def ids(value) when is_binary(value),
    do: value |> String.split(",", trim: true) |> Enum.map(&String.trim/1) |> ids()

  def ids(_value), do: []

  @doc "A calendar year in `1..9999`, or `nil`."
  @spec year(term()) :: pos_integer() | nil
  def year(value), do: integer(value, @years)

  @doc "An integer inside `range`, given as an integer or a string of digits, or `nil`."
  @spec integer(term(), Range.t()) :: integer() | nil
  def integer(value, %Range{} = range) when is_integer(value) do
    if value in range, do: value
  end

  def integer(value, range) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> integer(int, range)
      _malformed -> nil
    end
  end

  def integer(_value, _range), do: nil

  @doc "A string, or `nil` for any other shape."
  @spec string(term()) :: String.t() | nil
  def string(value) when is_binary(value), do: value
  def string(_value), do: nil

  @doc """
  A nested form payload (`%{"transaction" => %{…}}`): the map itself, or an
  empty map for any other shape, so a form handler reads fields that are
  simply absent rather than crashing on a string or a list.
  """
  @spec map(term()) :: map()
  def map(value) when is_map(value) and not is_struct(value), do: value
  def map(_value), do: %{}

  @doc """
  A flat form payload: `map/1` keeping only the fields a form's inputs send,
  a string under a string key. A field that arrived as a list, a map or a
  number is dropped, as if the input had not been there.
  """
  @spec form(term()) :: %{optional(String.t()) => String.t()}
  def form(value) do
    for {key, field} <- map(value),
        is_binary(key) and is_binary(field),
        into: %{},
        do: {key, field}
  end
end
