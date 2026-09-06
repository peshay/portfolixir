defmodule PortfolixirWeb.UiAuth do
  @moduledoc """
  Optional single-password authentication for the web UI (ADR-0045 §1, #764).

  One operator, one instance: the password comes from `PORTFOLIXIR_UI_PASSWORD`
  (or `config :portfolixir, :ui_password`). **Unset means the UI stays open**,
  so no existing instance changes on upgrade. Set, a plug on the browser
  pipeline and an `on_mount` on the LiveView session both require the flag
  this module stores in the signed session cookie.

  The password is compared in constant time and never logged. Failed attempts
  are throttled per source by `Portfolixir.Auth.Throttle` under the `:ui`
  scope. The `/api/v1` routes are untouched: the bearer token stays the
  agent's credential, and the UI password is never accepted there.
  """

  alias Portfolixir.RuntimeConfig

  @session_key "ui_authenticated"
  @stamp_key "ui_authenticated_at"
  @max_refresh_interval 86_400

  @doc "The session key the plug and the `on_mount` read."
  @spec session_key() :: String.t()
  def session_key, do: @session_key

  @doc "The session key carrying when the login happened (#777)."
  @spec stamp_key() :: String.t()
  def stamp_key, do: @stamp_key

  @doc """
  How long a login stays valid, in seconds, or `nil` for "until the browser
  closes" (`PORTFOLIXIR_SESSION_DAYS=0`).
  """
  @spec session_max_age() :: pos_integer() | nil
  def session_max_age do
    RuntimeConfig.session_max_age(
      case Application.get_env(:portfolixir, :session_days) do
        nil -> System.get_env("PORTFOLIXIR_SESSION_DAYS")
        configured -> configured
      end
    )
  end

  @doc "Whether a UI password is configured (non-empty)."
  @spec enabled?() :: boolean()
  def enabled? do
    case configured_password() do
      password when is_binary(password) and password != "" -> true
      _ -> false
    end
  end

  @doc """
  Whether the (plain or LiveView) session carries the authenticated flag AND is
  still inside its lifetime.

  The freshness check is the boundary, not the cookie's `max_age`: `Plug.Session`
  hands the cookie store no expiry, so a signed cookie verifies for as long as
  `SECRET_KEY_BASE` is unchanged. A session with no timestamp — one issued before
  #777 — is past its lifetime by definition.
  """
  @spec authenticated?(map()) :: boolean()
  def authenticated?(session) when is_map(session) do
    Map.get(session, @session_key) == true and fresh?(Map.get(session, @stamp_key))
  end

  def authenticated?(_session), do: false

  @doc "Marks the session authenticated, now."
  @spec put_authenticated(Plug.Conn.t()) :: Plug.Conn.t()
  def put_authenticated(%Plug.Conn{} = conn) do
    conn
    |> Plug.Conn.put_session(@session_key, true)
    |> Plug.Conn.put_session(@stamp_key, now())
  end

  @doc """
  Slides the window: re-stamps a session whose stamp has aged past the refresh
  interval, so continued use never expires. Recent sessions are left alone, so
  the ordinary request writes no cookie.
  """
  @spec refresh(Plug.Conn.t()) :: Plug.Conn.t()
  def refresh(%Plug.Conn{} = conn) do
    with max_age when is_integer(max_age) <- session_max_age(),
         stamp when is_integer(stamp) <- Plug.Conn.get_session(conn, @stamp_key),
         true <- now() - stamp >= refresh_interval(max_age) do
      Plug.Conn.put_session(conn, @stamp_key, now())
    else
      _ -> conn
    end
  end

  # Half the lifetime, and at most a day: a short lifetime still gets renewed
  # well before it lapses, a long one writes a cookie at most once a day.
  defp refresh_interval(max_age), do: min(div(max_age, 2), @max_refresh_interval)

  defp fresh?(stamp) do
    case session_max_age() do
      nil -> true
      max_age -> is_integer(stamp) and now() - stamp <= max_age
    end
  end

  defp now, do: System.os_time(:second)

  @doc "Whether the browser may proceed: no password configured, or the session is authenticated."
  @spec allowed?(map()) :: boolean()
  def allowed?(session), do: not enabled?() or authenticated?(session)

  @doc "Constant-time comparison of a submitted password against the configured one."
  @spec valid_password?(term()) :: boolean()
  def valid_password?(candidate) when is_binary(candidate) do
    case configured_password() do
      password when is_binary(password) and password != "" ->
        byte_size(candidate) == byte_size(password) and
          Plug.Crypto.secure_compare(candidate, password)

      _ ->
        false
    end
  end

  def valid_password?(_candidate), do: false

  @doc """
  The path to return to after login: a relative path on this instance, never
  a protocol-relative or absolute URL. Anything else becomes `/`.
  """
  @spec safe_return_path(term()) :: String.t()
  def safe_return_path(path) when is_binary(path) do
    cond do
      not String.starts_with?(path, "/") -> "/"
      String.starts_with?(path, "//") -> "/"
      String.contains?(path, ["://", "\\", "%09", "%0a", "%0d", "%0A", "%0D"]) -> "/"
      # Whitespace and control characters: what Phoenix's redirect refuses,
      # returned as "/" here rather than raised after a correct password.
      Regex.match?(~r/[\x00-\x20\x7f]/, path) -> "/"
      true -> path
    end
  end

  def safe_return_path(_path), do: "/"

  defp configured_password do
    Application.get_env(:portfolixir, :ui_password) || System.get_env("PORTFOLIXIR_UI_PASSWORD")
  end
end
