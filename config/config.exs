import Config

config :portfolixir,
  ecto_repos: [Portfolixir.Repo]

config :portfolixir, PortfolixirWeb.Endpoint,
  render_errors: [
    formats: [html: PortfolixirWeb.ErrorView, json: PortfolixirWeb.ErrorView],
    layout: false
  ],
  pubsub_server: Portfolixir.PubSub,
  live_view: [signing_salt: "portfolixir-salt"],
  json_library: Jason

config :portfolixir, PortfolixirWeb.Plugs.ReadApiKeyAuth,
  enabled: false,
  api_key: nil

config :portfolixir, PortfolixirWeb.Plugs.BrowserApiKeyAuth,
  enabled: false,
  api_key: nil

import_config "#{Mix.env()}.exs"
