import Config

if config_env() == :prod do
  config :portfolixir, PortfolixirWeb.Endpoint,
    server: true,
    url: [host: System.fetch_env!("PHX_HOST")],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    check_origin: [System.fetch_env!("PHX_HOST")],
    http: [
      port: String.to_integer(System.get_env("PORT") || "4000"),
      ip: {0, 0, 0, 0}
    ],
    cache_static_manifest: "/opt/app/priv/static/cache_manifest.json"

  config :portfolixir, Portfolixir.Repo,
    url: System.fetch_env!("DATABASE_URL"),
    ssl: Portfolixir.RuntimeConfig.database_ssl?(),
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
end
