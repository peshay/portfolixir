defmodule PortfolixirWeb.RequireUiAuth do
  @moduledoc """
  The browser-pipeline half of the optional UI login (ADR-0045 §1, #764):
  with a password configured, an unauthenticated request is redirected to the
  login page with the path to return to, cleaned by
  `PortfolixirWeb.UiAuth.safe_return_path/1` (no view, locale or benchmark
  choice rides through the login: E25 S7 review round, S7E-2). Without one, a
  no-op.
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
      # Continued use slides the window (#777); a recent session is untouched.
      UiAuth.refresh(conn)
    else
      conn
      |> redirect(
        to: "/login?" <> URI.encode_query(%{"to" => UiAuth.safe_return_path(return_path(conn))})
      )
      |> halt()
    end
  end

  defp return_path(%Plug.Conn{request_path: path, query_string: ""}), do: path
  defp return_path(%Plug.Conn{request_path: path, query_string: query}), do: path <> "?" <> query
end
