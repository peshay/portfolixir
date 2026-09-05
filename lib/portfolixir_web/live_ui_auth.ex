defmodule PortfolixirWeb.LiveUiAuth do
  @moduledoc """
  The LiveView half of the optional UI login (ADR-0045 §1, #764): the socket
  refuses to mount for a session without the authenticated flag, so the
  transport cannot be used to bypass `PortfolixirWeb.RequireUiAuth`.
  """

  import Phoenix.LiveView, only: [redirect: 2]

  alias PortfolixirWeb.UiAuth

  def on_mount(:default, _params, session, socket) do
    if UiAuth.allowed?(session) do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/login")}
    end
  end
end
