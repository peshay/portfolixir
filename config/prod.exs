import Config

# Credentials and connection URL are intentionally loaded in runtime.exs from DATABASE_URL.
config :portfolixir, Portfolixir.Repo,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

# Info, not Logger's debug default (E25 S2, F66): at debug the release wrote
# query parameters, request and page-event parameters and session contents to
# the container log. Info keeps the request line, warnings and errors.
config :logger, level: :info

# Keep static asset manifest config near endpoint and document follow-up for release-time asset wiring when needed.
config :portfolixir, PortfolixirWeb.Endpoint,
  url: [host: "127.0.0.1", port: 4000],
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true

# Background quote-history sync is opt-in. Enable it in prod so charts
# stay current; tests/dev keep it off to avoid surprise HTTP traffic.
config :portfolixir, Portfolixir.Catalog.QuoteSync, enabled?: true
config :portfolixir, Portfolixir.Fx.RateSync, enabled?: true

# Try to fetch a logo for new securities (CoinGecko for crypto, Wikipedia
# for equities/ETFs/funds). Disabled in tests to keep them hermetic.
config :portfolixir, :enable_logo_discovery, true

# The HTTPS posture (D-2 of the Sprint 11 plan, #382): TLS is terminated by
# the operator's reverse proxy (ADR-0045 §2), which forwards
# X-Forwarded-Proto; the in-app redirect and HSTS are the runtime opt-in
# PHX_FORCE_SSL (config/runtime.exs, PortfolixirWeb.OptionalSsl), off here
# by default because a loopback instance without TLS is the safe baseline.
# Stated in prod.exs so the posture is visible where Sobelow's Config.HTTPS
# check reads it: configured, not forced.
config :portfolixir, force_ssl: false
