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
  """
  @spec rebuild_derived() :: {:ok, map()}
  def rebuild_derived do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    Portfolixir.Derived.rebuild(&Portfolixir.Portfolios.Performance.Warmup.warm/0)
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app, do: Application.ensure_loaded(@app)
end
