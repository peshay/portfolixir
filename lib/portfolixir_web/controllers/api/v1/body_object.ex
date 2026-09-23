defmodule PortfolixirWeb.Api.V1.BodyObject do
  @moduledoc """
  The input-shape check for the writes that carry their attributes under one
  wrapper key (`{"view": {...}}`, `{"transaction": {...}}`, ...) — #853.

  A wrapper that is present but not a JSON object (a string, a number, a
  list) is answered **422** naming the key, before the action runs. Without
  it the value reached a context function guarded by `is_map/1` and the
  request died as a `FunctionClauseError` — a 500, which tells an agent
  neither that its request was malformed nor which part. An absent wrapper is
  left to the action, which treats it as an empty object and answers its own
  field errors.

  Used as a module plug scoped to the actions that read the wrapper:

      plug PortfolixirWeb.Api.V1.BodyObject, "view" when action in [:create, :update]

  Only the request **body** is inspected: the same word can be a query
  parameter (`?view=` is a view id) or an integer in another route's body.
  """
  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @impl true
  def init(key) when is_binary(key), do: key

  @impl true
  def call(%Plug.Conn{body_params: %{} = body} = conn, key) do
    case Map.fetch(body, key) do
      {:ok, %{} = object} when not is_struct(object) ->
        conn

      {:ok, _not_an_object} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{key => ["must be an object"]}})
        |> halt()

      :error ->
        conn
    end
  end

  def call(conn, _key), do: conn
end
