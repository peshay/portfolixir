defmodule Portfolixir.Application do
  @moduledoc false
  use Application

  require Logger

  alias Portfolixir.Portfolios.Performance.Warmup

  @impl true
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: Portfolixir.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children(), opts) do
      # Built-in classification trees (asset-class, currency) are bootstrap data:
      # seeded once at startup, after the Repo is up, rather than lazily on every
      # read path (#529). Idempotent + config-gated (off in tests); see
      # Classifications.seed_builtins_on_boot/0.
      Portfolixir.Classifications.seed_builtins_on_boot()
      warn_if_exposed()
      {:ok, pid}
    end
  end

  @doc """
  The supervised children, in start order. Public so the wiring itself is
  testable — a child handed the wrong collaborator would otherwise be a silent
  production-only no-op with a green suite.
  """
  @spec children() :: [Supervisor.child_spec() | {module(), term()} | module()]
  def children do
    [
      Portfolixir.Repo,
      {Phoenix.PubSub, name: Portfolixir.PubSub},
      {Task.Supervisor, name: Portfolixir.LogoSupervisor},
      {Portfolixir.Catalog.LogoDiscovery, []},
      {Portfolixir.Catalog.QuoteSync,
       Application.get_env(:portfolixir, Portfolixir.Catalog.QuoteSync, [])},
      {Portfolixir.Fx.RateSync, Application.get_env(:portfolixir, Portfolixir.Fx.RateSync, [])},
      Portfolixir.Imports.PreviewStore,
      Portfolixir.Derived.Memo,
      {Warmup, Application.get_env(:portfolixir, Warmup, [])},
      # The refresher schedules; `Warmup` owns which scopes are operative. Wired
      # here rather than defaulted inside the derived layer so the layer keeps
      # no dependency on the performance context — the same shape as
      # `Derived.rebuild(&Warmup.warm/0)` (ADR-0039 amendment §1).
      {Portfolixir.Derived.Refresher,
       :portfolixir
       |> Application.get_env(Portfolixir.Derived.Refresher, [])
       |> Keyword.put_new(:refresh, &Warmup.warm_basis/1)},
      PortfolixirWeb.Endpoint
    ]
  end

  # ADR-0045 §2 (#758): bound beyond loopback with no UI password is named in
  # the log at startup. The decision is a pure function so it is unit-tested;
  # this is only the wiring.
  defp warn_if_exposed do
    ip =
      :portfolixir
      |> Application.get_env(PortfolixirWeb.Endpoint, [])
      |> get_in([:http, :ip])

    password =
      Application.get_env(:portfolixir, :ui_password) || System.get_env("PORTFOLIXIR_UI_PASSWORD")

    case Portfolixir.RuntimeConfig.exposure_warning(ip || {127, 0, 0, 1}, password) do
      :ok -> :ok
      {:warn, message} -> Logger.warning(message)
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    PortfolixirWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
