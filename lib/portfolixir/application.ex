defmodule Portfolixir.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Portfolixir.Repo,
      {Phoenix.PubSub, name: Portfolixir.PubSub},
      {Task.Supervisor, name: Portfolixir.LogoSupervisor},
      {Portfolixir.Catalog.LogoDiscovery, []},
      {Portfolixir.Catalog.QuoteSync,
       Application.get_env(:portfolixir, Portfolixir.Catalog.QuoteSync, [])},
      {Portfolixir.Fx.RateSync, Application.get_env(:portfolixir, Portfolixir.Fx.RateSync, [])},
      Portfolixir.Imports.PreviewStore,
      PortfolixirWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Portfolixir.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    PortfolixirWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
