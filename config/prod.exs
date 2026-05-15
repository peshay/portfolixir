import Config

# Credentials and connection URL are intentionally loaded in runtime.exs from DATABASE_URL.
config :portfolixir, Portfolixir.Repo,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

# Keep static asset manifest config near endpoint and document follow-up for release-time asset wiring when needed.
config :portfolixir, PortfolixirWeb.Endpoint,
  url: [host: "127.0.0.1", port: 4000],
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true

# Background quote-history sync is opt-in. Enable it in prod so charts
# stay current; tests/dev keep it off to avoid surprise HTTP traffic.
config :portfolixir, Portfolixir.Catalog.QuoteSync, enabled?: true

# Try to fetch a logo for new securities (CoinGecko for crypto, Wikipedia
# for equities/ETFs/funds). Disabled in tests to keep them hermetic.
config :portfolixir, :enable_logo_discovery, true
