import Config

config :portfolixir,
  ecto_repos: [Portfolixir.Repo]

# The reconcile endpoint's external position list must never be logged
# (ADR-0029 §6 boundary / NFR-4): filter the `rows` request parameter from
# Phoenix parameter logging alongside the default password filter.
config :phoenix, :filter_parameters, ["password", "rows"]

config :portfolixir, PortfolixirWeb.Endpoint,
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
# measurement.
config :portfolixir, Portfolixir.Derived,
  lifetimes: [performance_analysis: :durable, performance_view_analysis: :durable]

# Derived-value refresh (ADR-0039 amendment §2): a write bumps the data version
# and the refresher re-materializes the affected bases in the background. The
# quiet period is what collapses a Portfolio Performance import's per-row bumps
# into one refresh per basis; the maximum delay is what keeps a write stream
# that never pauses from starving the drain.
config :portfolixir, Portfolixir.Derived.Refresher, quiet_ms: 500, max_delay_ms: 10_000

import_config "#{Mix.env()}.exs"
