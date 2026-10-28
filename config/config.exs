import Config

config :portfolixir,
  ecto_repos: [Portfolixir.Repo]

# The reconcile endpoint's external position list must never be logged
# (ADR-0029 §6 boundary / NFR-4): filter the `rows` request parameter from
# Phoenix parameter logging alongside the default password filter. The CSRF
# token is bound to the session, and a live page's socket connect is logged
# with its parameters at info, the production level (E25 S2, F66).
config :phoenix, :filter_parameters, ["password", "rows", "_csrf_token"]

# The console handler writes every control character of a log entry as a
# visible escape (security review 2026-10-12, H69), in every environment;
# the remote group-leader filter is the one the handler carries by default.
config :logger, :default_handler,
  filters: [
    remote_gl: {&:logger_filters.remote_gl/2, :stop},
    escape_control: {&Portfolixir.LogEscape.filter/2, []}
  ]

config :portfolixir, PortfolixirWeb.Endpoint,
  # Bandit serves HTTP and the LiveView socket (#772); the http: options in
  # dev.exs, test.exs and runtime.exs (ip, port) merge into the ones below.
  adapter: Bandit.PhoenixAdapter,
  http: [
    # The listener's bounds (security review 2026-10-12, H09), sized for one
    # operator and the MCP companion: a browser holds a handful of
    # connections and one socket per open page, the companion a few, so
    # 10 acceptors of 50 connections each, 500 at once, leave room for a
    # reverse proxy's upstream pool. A connection whose client sends nothing
    # for 15 seconds is closed, whether it is idle between requests or stuck
    # in its request header; the socket's own timeout keeps an open page's
    # connection. The port is meant to sit behind a reverse proxy that times
    # the whole header (docs/home-deployment.md, "Reverse proxy").
    thousand_island_options: [num_acceptors: 10, num_connections: 50, read_timeout: 15_000],
    # No cleartext HTTP/2: no browser speaks it without TLS, the documented
    # proxies and the companion talk HTTP/1.1 to the application, and it
    # would carry many request processes on one connection.
    http_2_options: [enabled: false],
    # A message sent in fragments meets the LiveView socket's frame bound
    # too (security review 2026-10-12, H02; PortfolixirWeb.LiveSocket).
    websocket_options: [max_fragmented_message_size: 524_288]
  ],
  render_errors: [
    formats: [html: PortfolixirWeb.ErrorView, json: PortfolixirWeb.ErrorView],
    layout: false
  ],
  pubsub_server: Portfolixir.PubSub,
  live_view: [signing_salt: "portfolixir-salt"],
  json_library: Jason

config :portfolixir, Portfolixir.Catalog.SecuritySearch,
  providers: [
    Portfolixir.Catalog.SecuritySearch.PortfolioPerformance,
    Portfolixir.Catalog.SecuritySearch.CoinGecko
  ],
  timeout_ms: 4000

config :portfolixir, Portfolixir.Catalog.QuoteSync,
  enabled?: false,
  interval_ms: 6 * 60 * 60 * 1000,
  adapter_for: %{
    "coingecko" => Portfolixir.Catalog.QuoteSync.Yahoo,
    "portfolio_performance" => Portfolixir.Catalog.QuoteSync.Yahoo
  }

# Every server-side fetch of a caller- or provider-supplied URL passes
# Portfolixir.Net.UrlPolicy (#762): https only, public addresses only, and for
# the discovery sources the provider's own image hosts only. `.domain` entries
# match subdomains; `:any` skips the host check but never the address check.
config :portfolixir, Portfolixir.Catalog.LogoStore,
  allowed_hosts: %{
    coingecko: [".coingecko.com"],
    wikipedia: ["upload.wikimedia.org", "commons.wikimedia.org", ".wikipedia.org"],
    companieslogo: ["companieslogo.com", ".companieslogo.com"],
    manual: :any
  }

config :portfolixir, Portfolixir.Fx.RateSync,
  enabled?: false,
  interval_ms: 12 * 60 * 60 * 1000,
  provider: Portfolixir.Fx.RateSync.Ecb

# Derived-value lifetimes (ADR-0039 §2): every registered analytic is
# eligible; which ones run :durable is a configuration decision informed by
# measurement, never an architectural one. Both activations rest on the
# measurement recorded in ADR-0039 (`mix portfolixir.derived.measure`): the two
# daily walks cost seconds and their second call costs the same as the first,
# while every other figure a surface waits on lands in tens to a few hundred
# milliseconds. Further activations are one line each, added with their
# measurement. The in-memory tier keeps to a budget, `memo_max_entries` and
# `memo_max_bytes` (5000 entries and 128 MiB unless set here), and empties
# itself when a put would leave it over (E25 S4).
config :portfolixir, Portfolixir.Derived,
  lifetimes: [performance_analysis: :durable, performance_view_analysis: :durable]

# Derived-value refresh (ADR-0039 amendment §2): a write bumps the data version
# and the refresher re-materializes the affected bases in the background. The
# quiet period is what collapses a Portfolio Performance import's per-row bumps
# into one refresh per basis; the maximum delay is what keeps a write stream
# that never pauses from starving the drain.
config :portfolixir, Portfolixir.Derived.Refresher, quiet_ms: 500, max_delay_ms: 10_000

import_config "#{Mix.env()}.exs"
