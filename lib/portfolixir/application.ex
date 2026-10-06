defmodule Portfolixir.Application do
  @moduledoc false
  use Application

  require Logger

  alias Portfolixir.Portfolios.Performance.Warmup

  @impl true
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: Portfolixir.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children(), opts) do
      after_start()
      {:ok, pid}
    end
  end

  @doc """
  The steps `start/2` runs once the supervisor is up, in order. Public so the
  wiring is testable, as `children/0` is: a step removed or moved would
  otherwise be a silent production-only gap with a green suite.

    * Built-in classification trees (asset-class, currency) are bootstrap
      data: seeded once at startup, after the Repo is up, rather than lazily
      on every read path (#529). Idempotent and config-gated (off in tests);
      see `Classifications.seed_builtins_on_boot/0`.
    * The logo reconciliation (#933) starts as a supervised task, so it never
      holds up or stops the boot; config-gated (off in tests), see
      `Catalog.reconcile_logos_on_boot/1`.
    * The startup warnings, `warn_if_exposed/0`.
  """
  @spec after_start() :: :ok
  def after_start do
    Portfolixir.Classifications.seed_builtins_on_boot()
    Portfolixir.Catalog.reconcile_logos_on_boot()
    warn_if_exposed()
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
      # The post-commit bump (E25 S6, F47): settles the data-version events a
      # writer marked pending once its transaction has committed.
      {Portfolixir.Derived.PostCommit,
       Application.get_env(:portfolixir, Portfolixir.Derived.PostCommit, [])},
      PortfolixirWeb.Endpoint
    ]
  end

  @doc """
  Logs the startup warnings over the configuration the runtime config set.
  ADR-0045 §2 (#758): bound beyond loopback with no UI password, or (T-2, E25
  S1 F67) with a short one, is named in the log at startup; so is (#930)
  `PHX_FORCE_SSL` on beyond loopback with no trusted proxy beyond loopback,
  the redirect loop's cause; and, whatever the bind, the entries of
  `PORTFOLIXIR_TRUSTED_PROXIES` that did not parse. The decisions are pure
  functions in `Portfolixir.RuntimeConfig`, so they are unit-tested; this is
  only the wiring. Always `:ok`: a warning, never a refusal.
  """
  @spec warn_if_exposed() :: :ok
  def warn_if_exposed do
    ip = listen_ip()

    password =
      Application.get_env(:portfolixir, :ui_password) || System.get_env("PORTFOLIXIR_UI_PASSWORD")

    force_ssl = Application.get_env(:portfolixir, :force_ssl)
    proxies = Application.get_env(:portfolixir, :trusted_proxies)
    unreadable = Portfolixir.RuntimeConfig.unreadable_trusted_proxies()

    for {:warn, message} <- [
          Portfolixir.RuntimeConfig.exposure_warning(ip, password),
          Portfolixir.RuntimeConfig.password_warning(ip, password),
          Portfolixir.RuntimeConfig.trusted_proxies_warning(force_ssl, ip, proxies),
          Portfolixir.RuntimeConfig.unreadable_proxies_warning(unreadable)
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
