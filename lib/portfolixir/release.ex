defmodule Portfolixir.Release do
  @moduledoc "Release tasks for explicit deployment operations."

  @app :portfolixir

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _migrated, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
