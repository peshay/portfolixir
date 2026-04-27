import Config

config :portfolixir, Portfolixir.Repo,
  database: "portfolixir_dev",
  username: "postgres",
  password: "postgres",
  hostname: "127.0.0.1",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  stacktrace: true

config :portfolixir, PortfolixirWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_which_should_be_changed_in_production",
  watchers: []
