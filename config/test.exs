import Config

config :portfolixir, Portfolixir.Repo,
  database: "portfolixir_test",
  username: "postgres",
  password: "postgres",
  hostname: "127.0.0.1",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :portfolixir, PortfolixirWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_which_should_be_changed_in_production",
  server: false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime
