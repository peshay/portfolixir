defmodule PortfolixirWeb.Api.V1.DeleteParamsGuard do
  @moduledoc """
  A `DELETE` takes only the parameters its route declares (N-07; Sprint 25
  retrospective, carry-forward 2): a query or body key the route does not
  declare is answered 422 naming it, before the action runs. A parameter of
  a delete is honoured or refused, never dropped, so `dry_run` asked of a
  delete that offers no dry run is a refusal and not the delete.

  A route declares what its action reads in the router, on the route:

      delete("/views/:id", ViewController, :delete, metadata: %{delete_takes: ~w(dry_run)})

  A route without the declaration takes none. The route's path parameters
  are its own and are not looked at; how a declared parameter is read, and
  what a value of it means, stays the action's
  (`PortfolixirWeb.Api.V1.DryRunParam`). The refusals are the ones the
  actions that already checked for themselves answer
  (`PortfolixirWeb.Api.V1.ClosedBody`, `DryRunParam`).
  `test/portfolixir_web/controllers/api_v1_delete_params_test.exs` walks the
  router's DELETE routes, so a new one cannot arrive without the refusal.
  """

  @behaviour Plug

  import Plug.Conn, only: [halt: 1, put_status: 2]
  import Phoenix.Controller, only: [json: 2]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: "DELETE"} = conn, _opts) do
    takes = takes(conn)

    case unknown_keys(conn, takes) do
      [] ->
        conn

      keys ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: Map.new(keys, &{&1, [refusal(takes)]})})
        |> halt()
    end
  end

  def call(conn, _opts), do: conn

  @doc "The parameters the DELETE route that matched `conn` declares."
  @spec takes(Plug.Conn.t()) :: [String.t()]
  def takes(%Plug.Conn{private: %{phoenix_router: router}} = conn) do
    case Phoenix.Router.route_info(router, "DELETE", conn.path_info, conn.host) do
      %{delete_takes: takes} when is_list(takes) -> takes
      _undeclared -> []
    end
  end

  defp unknown_keys(conn, takes) do
    [conn.query_params, conn.body_params]
    |> Enum.flat_map(fn
      %{} = params when not is_struct(params) -> Map.keys(params)
      _unfetched -> []
    end)
    |> Enum.reject(&(&1 in takes))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp refusal([]), do: "is unknown: this request takes no parameters"
  defp refusal(takes), do: "is unknown: this delete takes only " <> Enum.join(takes, ", ")
end
