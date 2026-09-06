import Config

if config_env() == :prod do
  secret_key_base = System.fetch_env!("SECRET_KEY_BASE")

  config :portfolixir, PortfolixirWeb.Endpoint,
    server: true,
    url: [host: System.fetch_env!("PHX_HOST")],
    secret_key_base: secret_key_base,
    # Derived per installation rather than the literal in config.exs (#759).
    live_view: [
      signing_salt: Portfolixir.RuntimeConfig.derived_salt(secret_key_base, "live_view")
    ],
    # The socket handshake accepts the same names the Host guard does (#758).
    check_origin: Enum.map(Portfolixir.RuntimeConfig.allowed_hosts(), &("//" <> &1)),
    http: [
      port: String.to_integer(System.get_env("PORT") || "4000"),
      # Loopback unless PHX_BIND_ALL says otherwise (ADR-0045 §2, #758): an
      # instance is reachable only from its own machine until the operator
      # opens it deliberately — the same default config/dev.exs has.
      ip: Portfolixir.RuntimeConfig.bind_ip()
    ],
    # Relative: Phoenix resolves it inside the release's own priv directory.
    cache_static_manifest: "priv/static/cache_manifest.json"

  # The Host allow-list behind PortfolixirWeb.HostGuard: PHX_HOST, the loopback
  # names, and PORTFOLIXIR_ALLOWED_HOSTS (comma-separated) for a reverse-proxy
  # name or a LAN address.
  config :portfolixir, PortfolixirWeb.HostGuard, hosts: Portfolixir.RuntimeConfig.allowed_hosts()

  # PHX_FORCE_SSL=true redirects plain HTTP and sets HSTS, reading the scheme
  # from the proxy's x-forwarded-proto (#759). Off by default so a loopback
  # instance without TLS keeps working.
  config :portfolixir, :force_ssl, Portfolixir.RuntimeConfig.force_ssl_opts()

  # The proxies whose x-forwarded-for names the throttle's source (#771).
  config :portfolixir, :trusted_proxies, Portfolixir.RuntimeConfig.trusted_proxies()

  # The agent's credential is checked at boot (#761): length and no
  # placeholder, with the variable named in the failure.
  config :portfolixir,
         :api_token,
         Portfolixir.RuntimeConfig.validate_api_token!(System.get_env("PORTFOLIXIR_API_TOKEN"))

  config :portfolixir, Portfolixir.Repo,
    url: System.fetch_env!("DATABASE_URL"),
    ssl: Portfolixir.RuntimeConfig.database_ssl?(),
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
end
