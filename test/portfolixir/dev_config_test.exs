defmodule Portfolixir.DevConfigTest do
  # Closing-act finding UAT-15: config/test.exs read DATABASE_PORT, but
  # config/dev.exs set no Repo port, so the plan's walkthrough recipe
  # ("DATABASE_PORT=5433 … MIX_ENV=dev mix ecto.create/migrate/phx.server")
  # created its database on one server and migrated against whatever listened
  # on 5432 — a different PostgreSQL than the one the plan requires.
  #
  # async: false — the test sets DATABASE_PORT in the VM's environment.
  use ExUnit.Case, async: false

  # User story (closing-act finding UAT-15):
  # As a maintainer running a walkthrough instance against the PostgreSQL 18
  # server CI and Compose run,
  # I want the development configuration to honour DATABASE_PORT as the test
  # configuration does,
  # so that every mix task of the recipe talks to the server I named.
  #
  # Acceptance criteria:
  # - With DATABASE_PORT set, config/dev.exs gives the Repo that port.
  # - Unset, the Repo keeps PostgreSQL's default port 5432.
  test "the development Repo takes its port from DATABASE_PORT" do
    previous = System.get_env("DATABASE_PORT")

    try do
      System.put_env("DATABASE_PORT", "5433")
      assert repo_port() == 5433

      System.delete_env("DATABASE_PORT")
      assert repo_port() == 5432
    after
      if previous,
        do: System.put_env("DATABASE_PORT", previous),
        else: System.delete_env("DATABASE_PORT")
    end
  end

  defp repo_port do
    "config/dev.exs"
    |> Config.Reader.read!(env: :dev, target: :host)
    |> Keyword.fetch!(:portfolixir)
    |> Keyword.fetch!(Portfolixir.Repo)
    |> Keyword.fetch!(:port)
  end
end
