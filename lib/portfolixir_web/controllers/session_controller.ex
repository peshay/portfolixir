defmodule PortfolixirWeb.SessionController do
  @moduledoc """
  The login and logout of the optional UI password (ADR-0045 §1, #764).

  `new` renders the one-field form (or, with no password configured, the
  sentence saying the UI is open); `create` checks the source's throttle, then
  the password in constant time, and stores the flag in a renewed session;
  `delete` drops the session. The password is never logged.
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
      error: nil
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
          error: gettext("Too many attempts. Wait %{seconds} seconds.", seconds: seconds)
        )

      :ok ->
        attempt(conn, get_in(params, ["session", "password"]), source, return_to)
    end
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: "/login")
  end

  defp attempt(conn, password, source, return_to) do
    if UiAuth.enabled?() and UiAuth.valid_password?(password) do
      Throttle.success(:ui, source)

      conn
      |> configure_session(renew: true)
      |> put_session(UiAuth.session_key(), true)
      |> redirect(to: return_to)
    else
      Throttle.failure(:ui, source)

      conn
      |> put_status(:unauthorized)
      |> render(:new,
        enabled: UiAuth.enabled?(),
        return_to: return_to,
        error: gettext("Wrong password.")
      )
    end
  end
end
