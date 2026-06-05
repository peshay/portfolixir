bind_all_http = String.downcase(System.get_env("PHX_BIND_ALL", "false"))

import Config

config :portfolixir, Portfolixir.Repo,
  database: "portfolixir_dev",
  username: "postgres",
  password: "postgres",
  hostname: System.get_env("DATABASE_HOST", "127.0.0.1"),
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  stacktrace: true

config :portfolixir, PortfolixirWeb.Endpoint,
  url: [host: System.get_env("PHX_HOST", "localhost"), port: 4000],
  http: [
    ip: if(bind_all_http in ["1", "true", "yes"], do: {0, 0, 0, 0}, else: {127, 0, 0, 1}),
    port: 4000
  ],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base:
    "dev_secret_key_base_which_should_be_changed_in_production_and_is_long_enough_for_sessions",
  watchers: []

# Try to fetch a logo for new securities locally as well so the dev
# experience matches prod.
config :portfolixir, :enable_logo_discovery, true

# Run the quote-sync GenServer in dev so freshly imported securities
# get prices on the next tick. Disabled by default in `config/config.exs`
# (because tests must not make real HTTP calls and prod is opt-in via
# runtime.exs). For dev we want the full live experience.
config :portfolixir, Portfolixir.Catalog.QuoteSync, enabled?: true
config :portfolixir, Portfolixir.Fx.RateSync, enabled?: true
