defmodule PortfolixirWeb.LogoFileController do
  @moduledoc """
  Serves a stored security logo from the logo directory (#764).

  The files used to be static assets ahead of the router; named by security
  id, they told anyone who could reach the port which companies the operator
  holds. Now they sit in the browser pipeline, behind the optional UI login,
  with the same nosniff header the static plug set.
  """
  use Phoenix.Controller, formats: [:html]

  import Plug.Conn

  alias Portfolixir.Catalog.LogoStore

  # The name is a security id plus an extension the store writes, checked by
  # LogoStore.served_file/2 — the one shape check, shared with the logo
  # reconciliation (#933) — before it is joined onto the configured
  # directory; nothing else from the request reaches the file system.
  # sobelow_skip ["Traversal.SendFile"]
  def show(conn, %{"file" => file}) do
    with {:ok, path, ext} <- LogoStore.served_file(file),
         true <- File.regular?(path) do
      conn
      |> put_image_type(ext)
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("cache-control", "private, max-age=86400")
      |> send_file(200, path)
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  # One literal per extension the pattern admits: the type never comes from
  # the request.
  defp put_image_type(conn, "png"), do: put_resp_content_type(conn, "image/png")
  defp put_image_type(conn, "jpg"), do: put_resp_content_type(conn, "image/jpeg")
  defp put_image_type(conn, "webp"), do: put_resp_content_type(conn, "image/webp")
end
