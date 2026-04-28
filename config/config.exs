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

import_config "#{Mix.env()}.exs"
