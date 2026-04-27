bind_all_http = String.downcase(System.get_env("PHX_BIND_ALL", "false"))

import Config

config :portfolixir, Portfolixir.Repo,
  database: "portfolixir_test",
  username: "postgres",
  password: "postgres",
  hostname: System.get_env("DATABASE_HOST", "127.0.0.1"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :portfolixir, PortfolixirWeb.Endpoint,
  url: [host: System.get_env("PHX_HOST", "localhost"), port: 4002],
  http: [
    ip: if(bind_all_http in ["1", "true", "yes"], do: {0, 0, 0, 0}, else: {127, 0, 0, 1}),
    port: 4002
  ],
  secret_key_base: "test_secret_key_base_which_should_be_changed_in_production",
  server: false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime
