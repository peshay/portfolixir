defmodule PortfolixirWeb.SessionController do
  @moduledoc """
  The login and logout of the optional UI password (ADR-0045 §1, #764).

  `new` renders the one-field form (or, with no password configured, the
  sentence saying the UI is open); `create` checks the source's throttle, then
  the password in constant time, and stores the flag in a renewed session;
  `delete` drops the session and disconnects the LiveView sockets it opened.
  The password is never logged.
  """
  use Phoenix.Controller, formats: [:html]
  use Gettext, backend: PortfolixirWeb.Gettext

  import Plug.Conn

  alias Portfolixir.Auth.Throttle
  alias PortfolixirWeb.UiAuth

  def new(conn, params) do
    render(conn, :new,
      enabled: UiAuth.enabled?(),
      return_to: UiAuth.safe_return_path(params["to"]),
      error: nil,
      lockout: nil
    )
  end

  def create(conn, params) do
    source = Throttle.source_key(conn.remote_ip)
    return_to = UiAuth.safe_return_path(params["to"])

    case Throttle.check(:ui, source) do
      {:locked, seconds} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(seconds))
        |> put_status(:too_many_requests)
        |> render(:new,
          enabled: UiAuth.enabled?(),
          return_to: return_to,
          error: nil,
          lockout:
            ngettext(
              "Too many attempts. Wait one second.",
              "Too many attempts. Wait %{count} seconds.",
              seconds
            )
        )

      :ok ->
        attempt(conn, submitted_password(params), source, return_to)
    end
  end

  # A GET never changes state: the logout link opens this one-button page,
  # and the button posts (with its CSRF token) to `delete/2`.
  def confirm_logout(conn, _params), do: render(conn, :confirm_logout)

  def delete(conn, _params) do
    # An open LiveView keeps its socket after the cookie is gone; the
    # session's socket id lets the logout close it (#764).
    case get_session(conn, "live_socket_id") do
      nil -> :ok
      live_socket_id -> PortfolixirWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> configure_session(drop: true)
    |> redirect(to: "/login")
  end

  # Only the shape the form sends; anything else is a wrong password.
  defp submitted_password(%{"session" => %{"password" => password}}) when is_binary(password),
    do: password

  defp submitted_password(_params), do: nil

  defp attempt(conn, password, source, return_to) do
    if UiAuth.enabled?() and UiAuth.valid_password?(password) do
      Throttle.success(:ui, source)

      conn
      |> configure_session(renew: true)
      |> put_session(UiAuth.session_key(), true)
      |> put_session(
        "live_socket_id",
        "ui_sessions:" <> Base.url_encode64(:crypto.strong_rand_bytes(16))
      )
      |> redirect(to: return_to)
    else
      Throttle.failure(:ui, source)

      conn
      |> put_status(:unauthorized)
      |> render(:new,
        enabled: UiAuth.enabled?(),
        return_to: return_to,
        error: gettext("Wrong password."),
        lockout: nil
      )
    end
  end
end
