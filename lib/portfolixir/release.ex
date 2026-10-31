defmodule Portfolixir.Release do
  @moduledoc """
  Release-time tasks for the production image (ADR-0045 §2, #760).

  A release carries no Mix, so the migrations the development entrypoint runs
  with `mix ecto.migrate` run here through `Ecto.Migrator`:

      bin/portfolixir eval "Portfolixir.Release.migrate()"

  The release entrypoint (`docker/release-entrypoint.sh`) calls it before
  starting the application. Nothing else lives here: there is no seed data
  (`priv/repo/seeds.exs` is empty by design) and no rollback command, because
  migrations are additive and a rollback across a release restores the
  database backup taken before the upgrade (`docs/home-deployment.md`).
  """

  alias Portfolixir.Derived
  alias Portfolixir.Portfolios.Performance.Warmup

  @app :portfolixir

  @doc "Runs every pending migration of every configured repo."
  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _fun_return, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc """
  Drops and rebuilds the durable derived values (ADR-0039), the release-side
  twin of `mix portfolixir.derived.rebuild`. Returns the task's own report.

  It runs in a VM of its own, usually beside the running instance
  (`docker compose exec app bin/portfolixir eval ...`), so it starts the
  application without the web listener, which could not bind the port the
  instance holds, and without the schedulers' boot work and the boot steps,
  which the instance does already (security review 2026-10-12, K05).
  """
  @spec rebuild_derived() :: {:ok, map()}
  def rebuild_derived do
    load_app()
    standalone_config()
    {:ok, _} = Application.ensure_all_started(@app)

    Derived.rebuild(&Warmup.warm/0)
  end

  # The processes that do work of their own at boot. The derived refresher
  # is not among them: it acts only on a write's notice, and the rebuild
  # writes nothing it would be told about.
  @schedulers [
    Portfolixir.Catalog.QuoteSync,
    Portfolixir.Fx.RateSync,
    Portfolixir.Portfolios.Performance.Warmup
  ]

  @boot_switches [:enable_logo_discovery, :seed_builtins_on_boot, :reconcile_logos_on_boot]

  defp standalone_config do
    merge_env(PortfolixirWeb.Endpoint, server: false)
    Enum.each(@schedulers, &merge_env(&1, enabled?: false))
    Enum.each(@boot_switches, &Application.put_env(@app, &1, false))
  end

  defp merge_env(key, opts),
    do: Application.put_env(@app, key, Keyword.merge(Application.get_env(@app, key, []), opts))

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app, do: Application.ensure_loaded(@app)
end
