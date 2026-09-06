defmodule PortfolixirWeb.SessionLifetime do
  @moduledoc """
  `Plug.Session` with the lifetime the operator configured (#777, ADR-0045 §1).

  `Plug.Session` bakes its cookie options — `max_age` among them — into what
  `init/1` returns, and an endpoint's `plug/2` runs `init/1` at compile time. A
  release image reads `PORTFOLIXIR_SESSION_DAYS` at boot, so the options are
  built per request here instead: the same compile-time/runtime tension
  `PortfolixirWeb.OptionalSsl` solves for `force_ssl`. Building them is a few
  keyword operations and one HMAC for the derived salt, next to the cookie's own
  signature verification and the request's database work.

  What this sets is browser hygiene, not the boundary. `Plug.Session` keeps
  `:max_age` among the cookie options and hands the store none, so a signed
  cookie verifies for as long as `SECRET_KEY_BASE` is unchanged whatever the
  browser was told. The lifetime that decides is the timestamp
  `PortfolixirWeb.UiAuth` checks on the server.
  """

  @behaviour Plug

  alias PortfolixirWeb.UiAuth

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts), do: Plug.Session.call(conn, Plug.Session.init(options()))

  @doc "The endpoint's session options with the configured lifetime applied."
  @spec options() :: keyword()
  def options do
    base = PortfolixirWeb.Endpoint.session_options()

    case UiAuth.session_max_age() do
      nil -> base
      seconds -> Keyword.put(base, :max_age, seconds)
    end
  end
end
