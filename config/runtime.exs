import Config

if config_env() == :prod do
  config :portfolixir, PortfolixirWeb.Endpoint,
    server: true,
    url: [host: System.fetch_env!("PHX_HOST")],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    check_origin: [System.fetch_env!("PHX_HOST")],
    http: [
      port: String.to_integer(System.get_env("PORT") || "4000"),
      # Loopback unless PHX_BIND_ALL says otherwise (ADR-0045 §2, #758): an
      # instance is reachable only from its own machine until the operator
      # opens it deliberately — the same default config/dev.exs has.
      ip: Portfolixir.RuntimeConfig.bind_ip()
    ],
    cache_static_manifest: "/opt/app/priv/static/cache_manifest.json"

  # The Host allow-list behind PortfolixirWeb.HostGuard: PHX_HOST, the loopback
  # names, and PORTFOLIXIR_ALLOWED_HOSTS (comma-separated) for a reverse-proxy
  # name or a LAN address.
  config :portfolixir, PortfolixirWeb.HostGuard, hosts: Portfolixir.RuntimeConfig.allowed_hosts()

  config :portfolixir, Portfolixir.Repo,
    url: System.fetch_env!("DATABASE_URL"),
    ssl: Portfolixir.RuntimeConfig.database_ssl?(),
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
end
