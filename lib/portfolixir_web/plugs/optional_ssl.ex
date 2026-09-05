defmodule PortfolixirWeb.OptionalSsl do
  @moduledoc """
  `Plug.SSL`, switched on at runtime instead of compile time (#759, ADR-0045 §2).

  Phoenix's `:force_ssl` endpoint option is read with `compile_env`, so an
  operator could not opt in with an environment variable. This plug reads
  `config :portfolixir, :force_ssl` (set from `PHX_FORCE_SSL` in
  `config/runtime.exs`) on each request and delegates to `Plug.SSL` when it is
  a keyword list; `false`/`nil` is a no-op, which keeps a plain-HTTP loopback
  instance working.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case Application.get_env(:portfolixir, :force_ssl) do
      opts when is_list(opts) and opts != [] -> Plug.SSL.call(conn, Plug.SSL.init(opts))
      _off -> conn
    end
  end
end
