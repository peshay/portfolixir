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

config :portfolixir, Portfolixir.Fx.RateSync,
  enabled?: false,
  interval_ms: 12 * 60 * 60 * 1000,
  provider: Portfolixir.Fx.RateSync.Ecb

import_config "#{Mix.env()}.exs"
