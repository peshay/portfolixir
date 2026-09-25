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
      # One run per key for a security's sync and the FX backfill (E25, G04).
      Portfolixir.SingleFlight,
      Portfolixir.Auth.Throttle,
      {Portfolixir.Catalog.LogoDiscovery, []},
      # The one serial queue for new securities' quote backfill (E25, G04).
      {Portfolixir.Catalog.QuoteEnrichment, []},
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

  # ADR-0045 §2 (#758): bound beyond loopback with no UI password, or (T-2,
  # E25 S1 F67) with a short one, is named in the log at startup. The decisions
  # are pure functions so they are unit-tested; this is only the wiring.
  defp warn_if_exposed do
    ip = listen_ip()

    password =
      Application.get_env(:portfolixir, :ui_password) || System.get_env("PORTFOLIXIR_UI_PASSWORD")

    for {:warn, message} <- [
          Portfolixir.RuntimeConfig.exposure_warning(ip, password),
          Portfolixir.RuntimeConfig.password_warning(ip, password)
        ] do
      Logger.warning(message)
    end

    :ok
  end

  defp listen_ip do
    case get_in(Application.get_env(:portfolixir, PortfolixirWeb.Endpoint, []), [:http, :ip]) do
      nil -> {127, 0, 0, 1}
      ip -> ip
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    PortfolixirWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
