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

  @session_key "ui_authenticated"

  @doc "The session key the plug and the `on_mount` read."
  @spec session_key() :: String.t()
  def session_key, do: @session_key

  @doc "Whether a UI password is configured (non-empty)."
  @spec enabled?() :: boolean()
  def enabled? do
    case configured_password() do
      password when is_binary(password) and password != "" -> true
      _ -> false
    end
  end

  @doc "Whether the (plain or LiveView) session carries the authenticated flag."
  @spec authenticated?(map()) :: boolean()
  def authenticated?(session) when is_map(session), do: Map.get(session, @session_key) == true
  def authenticated?(_session), do: false

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
      String.starts_with?(path, "//") -> "/"
      String.starts_with?(path, "/") and not String.contains?(path, "://") -> path
      true -> "/"
    end
  end

  def safe_return_path(_path), do: "/"

  defp configured_password do
    Application.get_env(:portfolixir, :ui_password) || System.get_env("PORTFOLIXIR_UI_PASSWORD")
  end
end
