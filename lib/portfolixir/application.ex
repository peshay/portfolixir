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
      Portfolixir.Portfolios.Performance.Cache,
      {Portfolixir.Portfolios.Performance.Warmup,
       Application.get_env(:portfolixir, Portfolixir.Portfolios.Performance.Warmup, [])},
      PortfolixirWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Portfolixir.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      # Built-in classification trees (asset-class, currency) are bootstrap data:
      # seeded once at startup, after the Repo is up, rather than lazily on every
      # read path (#529). Idempotent + config-gated (off in tests); see
      # Classifications.seed_builtins_on_boot/0.
      Portfolixir.Classifications.seed_builtins_on_boot()
      {:ok, pid}
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    PortfolixirWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
