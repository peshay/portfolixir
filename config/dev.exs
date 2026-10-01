bind_all_http = String.downcase(System.get_env("PHX_BIND_ALL", "false"))

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

config :portfolixir, PortfolixirWeb.Endpoint,
  url: [host: System.get_env("PHX_HOST", "localhost"), port: dev_http_port],
  http: [
    ip: if(bind_all_http in ["1", "true", "yes"], do: {0, 0, 0, 0}, else: {127, 0, 0, 1}),
    port: dev_http_port
  ],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base:
    "dev_secret_key_base_which_should_be_changed_in_production_and_is_long_enough_for_sessions",
  watchers: []

# The Host allow-list (ADR-0045 §2, #758): PHX_HOST, the loopback names, and
# PORTFOLIXIR_ALLOWED_HOSTS for a LAN address or a proxy name.
# Inlined rather than delegated to Portfolixir.RuntimeConfig because this file
# is evaluated before the application is compiled; runtime.exs uses the helper.
dev_extra_hosts =
  "PORTFOLIXIR_ALLOWED_HOSTS"
  |> System.get_env("")
  |> String.split(",")

config :portfolixir, PortfolixirWeb.HostGuard,
  hosts:
    ([System.get_env("PHX_HOST", "localhost"), "localhost", "127.0.0.1"] ++ dev_extra_hosts)
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()

# Logo discovery and the quote and FX sync fetch from public hosts by
# themselves, at boot and after every new security.
# PORTFOLIXIR_BACKGROUND_FETCH=off leaves all three off from boot, for a run
# that must send nothing out: every documented demo seed command sets it, so
# a seeded review database does not vary with provider availability and no
# demo name leaves the machine (#963). Unset, dev keeps the full live
# experience.
background_fetch_switch = String.downcase(System.get_env("PORTFOLIXIR_BACKGROUND_FETCH", "on"))
background_fetch? = background_fetch_switch not in ~w(0 false no off)

# Try to fetch a logo for new securities locally as well so the dev
# experience matches prod.
config :portfolixir, :enable_logo_discovery, background_fetch?

# Run the quote-sync GenServer in dev so freshly imported securities
# get prices on the next tick. Disabled by default in `config/config.exs`
# (because tests must not make real HTTP calls and prod is opt-in via
# runtime.exs). For dev we want the full live experience.
config :portfolixir, Portfolixir.Catalog.QuoteSync, enabled?: background_fetch?
config :portfolixir, Portfolixir.Fx.RateSync, enabled?: background_fetch?
