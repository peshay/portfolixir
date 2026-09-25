defmodule PortfolixirWeb.Api.V1.IdRangeGuard do
  @moduledoc """
  Refuses an id no `bigint` column can hold before any controller sees it
  (#840).

  Runs in the `/api/v1` pipeline after authentication. It reads every
  id-shaped param — a path param, and a query or JSON body key named `id`,
  `*_id`, `*_ids`, `view` or `running_balance_for`, at any depth of the body
  — and answers:

    * a path id past the range: `404`, the answer every malformed or unknown
      path id already gets;
    * a query or body id past the range: `422` naming the key, the shape of
      the field error a malformed id already gets.

  Only the out-of-range class is decided here; a malformed or unknown id
  still reaches its controller and keeps the answer it had. Because the
  guard sits in the pipeline rather than in each controller, a route added
  later is covered without anyone remembering to call it.

  Two things are deliberately not read: a security's free-form `attributes`
  map (operator-defined keys whose values are text, not references) and the
  keys that are text columns despite the `_id` suffix (`online_id`, a quote
  provider's identifier; `resource_id`, the journal filter).
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias PortfolixirWeb.Api.V1.IdParam

  @scalar_keys ~w(view running_balance_for)
  @text_keys ~w(online_id resource_id)
  @opaque_subtrees ~w(attributes)

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      Enum.any?(conn.path_params, fn {_key, value} -> not IdParam.int8?(value) end) ->
        conn |> put_status(:not_found) |> json(%{errors: %{detail: "not found"}}) |> halt()

      key = out_of_range_key(conn.query_params) || out_of_range_key(conn.body_params) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{key => ["is invalid"]}})
        |> halt()

      true ->
        conn
    end
  end

  @doc """
  The first key (depth first) of a params map that carries an id past the
  `bigint` range, or nil. The pages' event guard
  (`PortfolixirWeb.LiveEventGuard`) reads an event payload with the same
  rule, so a page and the API refuse the same ids.
  """
  @spec out_of_range_key(term()) :: String.t() | nil
  def out_of_range_key(%{} = params) when not is_struct(params) do
    Enum.find_value(params, fn {key, value} -> check(to_string(key), value) end)
  end

  def out_of_range_key(_params), do: nil

  defp check(key, _value) when key in @opaque_subtrees or key in @text_keys, do: nil

  defp check(key, value) when is_list(value) do
    if id_key?(key) and not Enum.all?(value, &IdParam.int8?/1),
      do: key,
      else: Enum.find_value(value, &out_of_range_key/1)
  end

  defp check(_key, %{} = value) when not is_struct(value), do: out_of_range_key(value)

  defp check(key, value) do
    if id_key?(key) and not IdParam.int8?(value), do: key
  end

  defp id_key?(key) do
    key == "id" or key in @scalar_keys or String.ends_with?(key, "_id") or
      String.ends_with?(key, "_ids")
  end
end
