defmodule PortfolixirWeb.RequireUiAuth do
  @moduledoc """
  The browser-pipeline half of the optional UI login (ADR-0045 §1, #764):
  with a password configured, an unauthenticated request is redirected to the
  login page with the path to return to. Without one, a no-op.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  alias PortfolixirWeb.UiAuth

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if UiAuth.allowed?(get_session(conn)) do
      conn
    else
      conn
      |> redirect(to: "/login?" <> URI.encode_query(%{"to" => return_path(conn)}))
      |> halt()
    end
  end

  defp return_path(%Plug.Conn{request_path: path, query_string: ""}), do: path
  defp return_path(%Plug.Conn{request_path: path, query_string: query}), do: path <> "?" <> query
end
