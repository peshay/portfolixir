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
    * In a release, the log filter that keeps a crashing live page's form
      values and session out of the log (security review 2026-10-12, H71);
      config-gated, see `PortfolixirWeb.SocketCrashReport.install_on_boot/0`.
    * A stored exchange rate that is not positive, named in one warning
      (`Portfolixir.Fx.report_non_positive_rates_on_boot/0`, K06); no read
      uses it. Config-gated (off in tests).
  """
  @spec after_start() :: :ok
  def after_start do
    PortfolixirWeb.SocketCrashReport.install_on_boot()
    Portfolixir.Classifications.seed_builtins_on_boot()
    Portfolixir.Catalog.reconcile_logos_on_boot()
    warn_if_exposed()
    Portfolixir.Fx.report_non_positive_rates_on_boot()
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
      # The capped workers `Portfolixir.HeapCap.run/1` starts: a page's load,
      # and each performance warm-up and refresher walk (#1204, K08).
      {Task.Supervisor, name: Portfolixir.CappedTasks},
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
  `PORTFOLIXIR_TRUSTED_PROXIES` that did not parse, and (H04) those too wide
  to name a proxy; (H20) an API token with few distinct characters; (H19) a
  `PORTFOLIXIR_SESSION_DAYS` that is not a whole number of days; and (H06) a
  protective switch whose value is not a switch value. The decisions are pure
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
    overbroad = Portfolixir.RuntimeConfig.overbroad_trusted_proxies()
    principals = Application.get_env(:portfolixir, :api_tokens)

    session_days =
      Application.get_env(:portfolixir, :session_days) ||
        System.get_env("PORTFOLIXIR_SESSION_DAYS")

    for {:warn, message} <- [
          Portfolixir.RuntimeConfig.exposure_warning(ip, password),
          Portfolixir.RuntimeConfig.password_warning(ip, password),
          Portfolixir.RuntimeConfig.trusted_proxies_warning(force_ssl, ip, proxies),
          Portfolixir.RuntimeConfig.unreadable_proxies_warning(unreadable),
          Portfolixir.RuntimeConfig.overbroad_proxies_warning(overbroad),
          Portfolixir.RuntimeConfig.weak_tokens_warning(principals),
          Portfolixir.RuntimeConfig.session_days_warning(session_days)
          | Portfolixir.RuntimeConfig.protective_switch_warnings()
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
