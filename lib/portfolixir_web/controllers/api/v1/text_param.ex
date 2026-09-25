defmodule PortfolixirWeb.Api.V1.TextParam do
  @moduledoc """
  The one parser of a text a read takes as a filter (E25 S4, G24; the S3/S4
  review round): a search `query`, a `holder`, an `institution`, a
  `resource_type`.

  It is `Portfolixir.Input.Text.check/2`, the rule every writer meets, as
  one-line text of at most 255 code points: a filter carrying a NUL or
  another control character, longer than a stored name can be, or not a
  string at all (`key[]=…`) is a **422 naming the parameter** instead of a
  value the database refuses to compare, which failed in the query with a
  500.
  """

  alias Portfolixir.Input.Text

  @max 255

  @doc "The longest text filter a read accepts, in code points."
  @spec max() :: pos_integer()
  def max, do: @max

  @doc """
  `{:ok, nil}` when `key` is absent or blank, `{:ok, text}` for one-line
  text within the bound, `:error` for anything else.
  """
  @spec parse(map(), String.t()) :: {:ok, String.t() | nil} | :error
  def parse(params, key) when is_map(params) and is_binary(key) do
    case Map.get(params, key) do
      value when value in [nil, ""] ->
        {:ok, nil}

      value when is_binary(value) ->
        if Text.check(value, max: @max) == :ok, do: {:ok, value}, else: :error

      _not_text ->
        :error
    end
  end

  @doc """
  Parses each of `keys`: `{:ok, %{key => text | nil}}`, or `{:error, key}`
  for the first one that is not a text filter.
  """
  @spec parse_all(map(), [String.t()]) ::
          {:ok, %{optional(String.t()) => String.t() | nil}} | {:error, String.t()}
  def parse_all(params, keys) when is_map(params) and is_list(keys) do
    Enum.reduce_while(keys, {:ok, %{}}, fn key, {:ok, parsed} ->
      case parse(params, key) do
        {:ok, text} -> {:cont, {:ok, Map.put(parsed, key, text)}}
        :error -> {:halt, {:error, key}}
      end
    end)
  end
end
