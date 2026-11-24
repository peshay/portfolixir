# The release's switch vocabulary (Portfolixir.RuntimeConfig.switch/2, H06),
# written out here because configuration is read before the application is
# compiled: 1/true/yes/on are on, 0/false/no/off are off, trimmed, any case.
switch_word = fn value, default ->
  case (value || "") |> String.trim() |> String.downcase() do
    word when word in ~w(1 true yes on) -> true
    word when word in ~w(0 false no off) -> false
    _unset_or_unread -> default
  end
end

bind_all_http? = switch_word.(System.get_env("PHX_BIND_ALL"), false)

import Config

config :portfolixir, Portfolixir.Repo,
  database: System.get_env("DATABASE_NAME", "portfolixir_dev"),
  username: "postgres",
  password: "postgres",
  hostname: System.get_env("DATABASE_HOST", "127.0.0.1"),
  # As config/test.exs reads it: a walkthrough against another PostgreSQL
  # (the PostgreSQL 18 that CI and Compose run) names its port once.
  port: String.to_integer(System.get_env("DATABASE_PORT", "5432")),
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  stacktrace: true

dev_http_port = String.to_integer(System.get_env("PORT", "4000"))

# The Host allow-list (ADR-0045 §2, #758): PHX_HOST, the loopback names, and
# PORTFOLIXIR_ALLOWED_HOSTS for a LAN address or a proxy name.
# Inlined rather than delegated to Portfolixir.RuntimeConfig because this file
# is evaluated before the application is compiled; runtime.exs uses the helper.
dev_extra_hosts =
  "PORTFOLIXIR_ALLOWED_HOSTS"
  |> System.get_env("")
  |> String.split(",")

dev_hosts =
  ([System.get_env("PHX_HOST", "localhost"), "localhost", "127.0.0.1"] ++ dev_extra_hosts)
  |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
  |> Enum.reject(&(&1 == ""))
  |> Enum.uniq()

# Debug pages are a developer's tool, off unless asked for (N-01): Phoenix
# compiles its debugger into the endpoint only when this is true, and a
# server run from source (README, "Run from source") is an instance, not a
# debugging session. The switch is read when the endpoint is compiled: a
# server started with another value than it was compiled with refuses to
# boot and says so, until `mix compile --force` has run with the new value.
dev_debug_errors? = switch_word.(System.get_env("PORTFOLIXIR_DEV_DEBUG_ERRORS"), false)

config :portfolixir, PortfolixirWeb.Endpoint,
  url: [host: System.get_env("PHX_HOST", "localhost"), port: dev_http_port],
  http: [
    ip: if(bind_all_http?, do: {0, 0, 0, 0}, else: {127, 0, 0, 1}),
    port: dev_http_port
  ],
  # The socket handshake accepts the names the Host guard accepts, as a
  # release's does (K18): the socket is dispatched ahead of the guard.
  check_origin: Enum.map(dev_hosts, &("//" <> &1)),
  # No signing key and no LiveView salt here: no configuration file holds
  # the key (N-01). config/runtime.exs sets both under :dev, the key from
  # SECRET_KEY_BASE or generated per checkout, the salt derived from it.
  code_reloader: true,
  debug_errors: dev_debug_errors?,
  watchers: []

config :portfolixir, PortfolixirWeb.HostGuard, hosts: dev_hosts

# Logo discovery, the quote and FX sync, and the news feeds' fetch and the
# chain reader (both run where the quote sync runs) fetch from public hosts
# by themselves, at boot, on their schedules and after every new security.
# PORTFOLIXIR_BACKGROUND_FETCH=off leaves all of them off from boot, for a run
# that must send nothing out: every documented demo seed command sets it, so
# a seeded review database does not vary with provider availability and no
# demo name leaves the machine (#963). Unset, dev keeps the full live
# experience.
background_fetch? = switch_word.(System.get_env("PORTFOLIXIR_BACKGROUND_FETCH"), true)

# Try to fetch a logo for new securities locally as well so the dev
# experience matches prod.
config :portfolixir, :enable_logo_discovery, background_fetch?

# Run the quote-sync GenServer in dev so freshly imported securities
# get prices on the next tick. Disabled by default in `config/config.exs`
# (because tests must not make real HTTP calls and prod is opt-in via
# runtime.exs). For dev we want the full live experience.
config :portfolixir, Portfolixir.Catalog.QuoteSync, enabled?: background_fetch?
config :portfolixir, Portfolixir.Fx.RateSync, enabled?: background_fetch?
