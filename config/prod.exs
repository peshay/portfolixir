import Config

config :portfolixir, Portfolixir.Repo,
  database: "portfolixir_prod",
  username: "postgres",
  password: "postgres",
  hostname: "127.0.0.1",
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

config :portfolixir, PortfolixirWeb.Endpoint,
  url: [host: "127.0.0.1", port: 4000],
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true
