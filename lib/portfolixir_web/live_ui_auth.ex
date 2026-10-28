defmodule PortfolixirWeb.LiveUiAuth do
  @moduledoc """
  The LiveView half of the optional UI login (ADR-0045 §1, #764): the socket
  refuses to mount for a session without the authenticated flag, so the
  transport cannot be used to bypass `PortfolixirWeb.RequireUiAuth`.

  A page already mounted is held to the same lifetime (security review
  2026-10-12, H19): the session it mounted with is checked again before every
  event the page receives, and once more when its stamp runs out, so an open
  page is sent to the login at its session's expiry rather than staying
  usable for as long as its socket stays connected. The stamp is renewed only
  by a request through the browser pipeline (`PortfolixirWeb.UiAuth.refresh/1`),
  never over the socket.
  """

  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, redirect: 2]

  alias PortfolixirWeb.UiAuth

  @expired {__MODULE__, :check_expiry}
  # Erlang's timers take at most about 49 days; a longer lifetime is checked
  # once a day until it runs out.
  @max_timer_ms 24 * 60 * 60 * 1000

  def on_mount(:default, _params, session, socket) do
    if UiAuth.allowed?(session) do
      {:cont, hold_to_lifetime(socket, session)}
    else
      {:halt, redirect(socket, to: "/login")}
    end
  end

  # Only a page behind a password with a lifetime has an expiry to keep.
  defp hold_to_lifetime(socket, session) do
    with true <- UiAuth.enabled?(),
         true <- connected?(socket),
         max_age when is_integer(max_age) <- UiAuth.session_max_age() do
      schedule_check(session, max_age)

      socket
      |> attach_hook(:ui_session_event, :handle_event, fn _event, _params, socket ->
        recheck(socket, session)
      end)
      |> attach_hook(:ui_session_expiry, :handle_info, fn
        @expired, socket ->
          with {:cont, socket} <- recheck(socket, session) do
            schedule_check(session, UiAuth.session_max_age())
            {:halt, socket}
          end

        _message, socket ->
          {:cont, socket}
      end)
    else
      _no_expiry -> socket
    end
  end

  defp recheck(socket, session) do
    if UiAuth.allowed?(session),
      do: {:cont, socket},
      else: {:halt, redirect(socket, to: "/login")}
  end

  # The first second past the stamp's lifetime, when `UiAuth` no longer
  # counts the session fresh.
  defp schedule_check(%{} = session, max_age) when is_integer(max_age) do
    stamp = Map.get(session, UiAuth.stamp_key(), 0)
    remaining_ms = (stamp + max_age + 1 - System.os_time(:second)) * 1000
    Process.send_after(self(), @expired, remaining_ms |> max(0) |> min(@max_timer_ms))
  end

  defp schedule_check(_session, _no_lifetime), do: :ok
end
