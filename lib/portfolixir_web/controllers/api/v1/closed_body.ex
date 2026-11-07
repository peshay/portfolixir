defmodule PortfolixirWeb.Api.V1.ClosedBody do
  @moduledoc """
  The closed schema of a write (ADR-0056 §7 and §9; Sprint 27, N8): a key the
  write does not take is refused with 422 naming it, never dropped in
  silence, so a misspelt field (`intervall_minutes`) or a field the system
  states (`last_ok_at`, `set_by`) cannot pass for an accepted write.

  `check/3` reads the request's query and body parameters (never the route's
  path parameters): beside the one wrapper key, nothing; inside the wrapper,
  only the fields the write takes. A wrapper that is not an object is
  `PortfolixirWeb.Api.V1.BodyObject`'s to answer, so it is not looked into.
  """

  import Plug.Conn, only: [put_status: 2]
  import Phoenix.Controller, only: [json: 2]

  @doc """
  `:ok`, or `{:error, errors}` with one entry per unknown key: `wrapper` is
  the one key the request may carry beside the route (`nil` for none), and
  `fields` the keys the wrapper's object may carry.
  """
  @spec check(Plug.Conn.t(), String.t() | nil, [String.t()]) :: :ok | {:error, map()}
  def check(%Plug.Conn{} = conn, wrapper, fields) when is_list(fields) do
    outside =
      conn
      |> request_keys()
      |> Enum.reject(&(&1 == wrapper))
      |> Map.new(&{&1, [outside_message(wrapper)]})

    inside =
      case wrapper && body(conn)[wrapper] do
        %{} = object when not is_struct(object) ->
          object
          |> Map.keys()
          |> Enum.reject(&(&1 in fields))
          |> Map.new(&{&1, [inside_message(wrapper, fields)]})

        _not_an_object ->
          %{}
      end

    case Map.merge(inside, outside) do
      empty when empty == %{} -> :ok
      errors -> {:error, errors}
    end
  end

  @doc "The 422 of `check/3`'s errors."
  @spec refuse(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def refuse(conn, errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end

  @doc """
  The keys of `object` that are not among `fields`, each with the refusal
  that names the fields an object of `kind` takes: for a nested object a
  write checks itself (a security's `news_identity`).
  """
  @spec unknown(map(), [String.t()], String.t()) :: map()
  def unknown(object, fields, kind) when is_map(object) do
    object
    |> Map.keys()
    |> Enum.reject(&(&1 in fields))
    |> Map.new(&{&1, [inside_message(kind, fields)]})
  end

  defp request_keys(conn) do
    [conn.query_params, body(conn)]
    |> Enum.flat_map(&Map.keys/1)
    |> Enum.uniq()
  end

  defp body(%Plug.Conn{body_params: %{} = body}) when not is_struct(body), do: body
  defp body(_conn), do: %{}

  defp outside_message(nil), do: "is unknown: this request takes no parameters"
  defp outside_message(wrapper), do: "is unknown: this write takes its fields under #{wrapper}"

  defp inside_message(kind, fields),
    do: "is unknown: #{kind} takes only #{Enum.join(fields, ", ")}"
end
