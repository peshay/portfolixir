defmodule Portfolixir.ScratchDatabaseSweepTest do
  # #1022: a scratch database outlived a test VM killed before its on_exit
  # ran, and nothing removed it. async: false -- it creates and drops
  # databases beside the suite's own.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.Postgres
  alias Portfolixir.Repo
  alias Portfolixir.ScratchDatabase

  @moduletag :seeded_upgrade

  # User story:
  # As the maintainer whose test run was killed mid-way,
  # I want the next run to drop the scratch databases the killed one left,
  # and never one a run still going (here or in another checkout) is using,
  # so that the database server does not fill up with orphans.
  #
  # Acceptance criteria:
  # - A database named as a scratch database of this test database whose VM
  #   no longer runs, and to which nothing is connected, is dropped.
  # - One whose VM still runs is kept, and so is a database merely named
  #   alike with another base.
  test "the sweep drops the scratch databases of a VM that is gone, and only those" do
    base = Keyword.fetch!(Repo.config(), :database)
    dead_pid = dead_os_pid()

    orphan = "#{base}_upgrade_#{dead_pid}_1"
    live = "#{base}_upgrade_#{System.pid()}_#{System.unique_integer([:positive])}"
    stranger = "#{base}x_upgrade_#{dead_pid}_2"

    for name <- [orphan, live, stranger], do: :ok = create!(name)

    on_exit(fn -> for name <- [orphan, live, stranger], do: drop!(name) end)

    dropped = ScratchDatabase.sweep!()

    assert orphan in dropped
    refute live in dropped
    refute stranger in dropped
    refute exists?(orphan)
    assert exists?(live)
    assert exists?(stranger)
  end

  # The pid of a shell that printed it and has exited by the time
  # System.cmd/2 returns.
  defp dead_os_pid do
    {pid, 0} = System.cmd("sh", ["-c", "echo $$"])
    String.trim(pid)
  end

  defp config(name), do: Keyword.put(Repo.config(), :database, name)
  defp create!(name), do: Postgres.storage_up(config(name))

  defp drop!(name) do
    case Postgres.storage_down(Keyword.put(config(name), :force_drop, true)) do
      :ok -> :ok
      {:error, :already_down} -> :ok
    end
  end

  defp exists?(name) do
    {:ok, conn} =
      Postgrex.start_link(
        Keyword.merge(config("postgres"), pool: DBConnection.ConnectionPool, pool_size: 1)
      )

    try do
      %{rows: [[found]]} =
        Postgrex.query!(conn, "SELECT count(*) FROM pg_database WHERE datname = $1", [name])

      found == 1
    after
      GenServer.stop(conn)
    end
  end
end
