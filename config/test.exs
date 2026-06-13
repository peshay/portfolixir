bind_all_http = String.downcase(System.get_env("PHX_BIND_ALL", "false"))
server_enabled = String.downcase(System.get_env("PHX_SERVER", "false")) in ["1", "true", "yes"]

import Config

config :portfolixir, Portfolixir.Repo,
  database: System.get_env("DATABASE_NAME", "portfolixir_test"),
  username: System.get_env("DATABASE_USER", "postgres"),
  password: System.get_env("DATABASE_PASSWORD", "postgres"),
  hostname: System.get_env("DATABASE_HOST", "127.0.0.1"),
  port: String.to_integer(System.get_env("DATABASE_PORT", "5432")),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :portfolixir, PortfolixirWeb.Endpoint,
  url: [host: System.get_env("PHX_HOST", "localhost"), port: 4002],
  http: [
    ip: if(bind_all_http in ["1", "true", "yes"], do: {0, 0, 0, 0}, else: {127, 0, 0, 1}),
    port: 4002
  ],
  secret_key_base:
    "test_secret_key_base_which_should_be_changed_in_production_and_is_long_enough_for_sessions",
  server: server_enabled

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :portfolixir, :api_token, "test-api-token"

config :portfolixir, Portfolixir.Catalog.SecuritySearch,
  providers: [Portfolixir.Catalog.SecuritySearch.Fake],
  timeout_ms: 1000

config :portfolixir, Portfolixir.Catalog.QuoteSync,
  enabled?: false,
  interval_ms: 60_000,
  adapter_for: %{}

config :portfolixir, Portfolixir.Fx.RateSync,
  enabled?: false,
  interval_ms: 60_000,
  provider: Portfolixir.Fx.RateSync.Fake

# Logo discovery is gated off in tests so create_security/1 doesn't make
# outbound HTTP calls. Tests that need it call LogoLookup.run/2 directly
# with a Req plug stub.
config :portfolixir, :enable_logo_discovery, false
# Drain immediately and never auto-rescan in tests, so the discovery suite is
# fast and deterministic (the queue is driven explicitly).
config :portfolixir, :logo_discovery_drain_ms, 0
config :portfolixir, :logo_discovery_refresh_ms, 0
