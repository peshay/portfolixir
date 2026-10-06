defmodule Portfolixir.SeededUpgrade do
  @moduledoc """
  The seeded-upgrade harness (Sprint 17, Lane G-1, #995): an upgrade replayed
  over the rows an earlier release left behind.

  `upgrade!/1` creates a scratch database, migrates it to a named earlier
  version, runs a seed function that inserts synthetic legacy rows with plain
  SQL, migrates to head through `Ecto.Migrator` -- the call
  `Portfolixir.Release.migrate/0` makes when a release boots -- and hands the
  test the result: what the seed returned, the versions the upgrade ran and
  the log it wrote. The test then reads the migrated rows with `query!/3`.
  The scratch database is dropped when the test exits, whatever its outcome.

  A migration that stops on a legacy row fails the test with the migration's
  file and the database's error, which is what the release would have
  printed at boot.

  ## A scratch database, reached through `Portfolixir.Repo` itself

  The migrator cannot run under the SQL sandbox the rest of the suite uses:
  it holds its own lock and runs each migration in a process of its own, and
  a migration's DDL would change the schema every concurrent test reads. So
  each upgrade gets its own database (`Portfolixir.ScratchDatabase`, named
  after the test database with an `_upgrade_` suffix), and nothing here
  touches the sandboxed one.

  The scratch database is reached through a second, unsandboxed instance of
  `Portfolixir.Repo`, started as a dynamic repo, not through a repo module of
  its own: a migration may call application code that writes through
  `Portfolixir.Repo` by name (the policy-rule author backfill does), and
  `Ecto.Migrator` carries the dynamic repo into the process it runs each
  migration in. Such a call therefore lands on the scratch database, inside
  the migration's transaction, exactly as it does on a release.

  ## Where the cases run

  A module of seeded cases carries `@moduletag :seeded_upgrade`, and each
  case names the migration it covers with `@tag seeded_upgrade: <version>`;
  `Portfolixir.SeededUpgrade.Rule` reads that tag to require a case for every
  new migration that adds a CHECK, a NOT NULL or a backfill.

  The cases are part of the default `mix test` run, and the
  `migration-roundtrip` CI job runs them again on their own
  (`mix test --only seeded_upgrade`). They stay in the default run because a
  gate that only one CI job runs is one a contributor cannot reproduce before
  pushing, and they can: they share nothing with the sandbox, wait on no
  timer, and cost a migration run from an empty database each (a few seconds).
  They are `async: false` only to keep those runs off the cores the async
  suite is using.
  """

  import ExUnit.Assertions, only: [flunk: 1]

  alias Portfolixir.Repo
  alias Portfolixir.ScratchDatabase

  # The actor a seed writes under. Journal-armed tables refuse a write without
  # one, and every write the seeded release made carried one.
  @seed_actor "system_job:seeded_upgrade"

  @enforce_keys [:database, :repo]
  defstruct [:database, :repo, :migrations, :from, :seeded, migrated: [], log: ""]

  @type t :: %__MODULE__{
          database: String.t(),
          repo: pid(),
          migrations: String.t() | nil,
          from: pos_integer() | nil,
          seeded: term(),
          migrated: [pos_integer()],
          log: String.t()
        }

  @doc """
  Replays an upgrade over seeded legacy rows. Options:

    * `:from` (required) -- the version the scratch database is migrated to
      before the seed, inclusive: the last migration of the release whose
      rows are seeded;
    * `:seed` (required) -- a function of the database (`t()`) that inserts
      the legacy rows with `query!/3`. It runs in one transaction with a
      journal actor set; what it returns lands in `:seeded`;
    * `:to` -- the version the upgrade stops at, inclusive, by default
      `:head`: for a case that reads a migration's result before a later one
      changes it, or one that runs a migration's `down` with `down!/2`;
    * `:migrations` -- the directory of migrations to replay, by default the
      application's (`priv/repo/migrations`); the harness's own tests point
      it at a directory of synthetic ones.

  Answers the database after the upgrade: `:seeded`, `:migrated` (the
  versions the upgrade ran, ascending) and `:log` (what it logged). Fails
  the test, naming the migration, when the upgrade stops. Call it from a
  test: the database is dropped by the test's `on_exit`.
  """
  @spec upgrade!(keyword()) :: t()
  def upgrade!(opts) do
    from = Keyword.fetch!(opts, :from)
    seed = Keyword.fetch!(opts, :seed)
    to = Keyword.get(opts, :to, :head)
    migrations = Keyword.get_lazy(opts, :migrations, &ScratchDatabase.migrations_dir/0)

    known_version!(from, migrations)
    if to != :head, do: known_version!(to, migrations)

    %ScratchDatabase{database: database, repo: repo} = ScratchDatabase.start!(suffix: "upgrade")
    db = %__MODULE__{database: database, repo: repo, migrations: migrations, from: from}

    ScratchDatabase.migrate!(db, from, migrations)
    seeded = journaled!(db, fn -> seed.(db) end)

    {result, log} = ExUnit.CaptureLog.with_log(fn -> migrate_to(db, to) end)

    case result do
      {:ok, migrated} ->
        %{db | seeded: seeded, migrated: migrated, log: log}

      {:error, kind, reason, stacktrace} ->
        flunk("""
        the upgrade from #{from} to #{to} stopped at #{stopped_at(db)}:

        #{Exception.format(kind, reason, stacktrace)}
        log:
        #{log}
        """)
    end
  end

  @doc "Runs `sql` with `params` on the scratch database."
  @spec query!(t(), String.t(), list()) :: Postgrex.Result.t()
  def query!(%__MODULE__{} = db, sql, params \\ []), do: ScratchDatabase.query!(db, sql, params)

  @doc """
  Runs `fun` in one transaction on the scratch database with a journal actor
  set, as a seed runs: for a test that writes after the upgrade, such as one
  asserting that a new row is refused. Raises what `fun` raises.
  """
  @spec journaled!(t(), (-> result)) :: result when result: term()
  def journaled!(%__MODULE__{} = db, fun) do
    ScratchDatabase.run(db, fn ->
      {:ok, result} =
        Repo.transaction(fn ->
          Repo.query!("SELECT set_config('portfolixir.journal_actor', $1, true)", [@seed_actor])
          fun.()
        end)

      result
    end)
  end

  @doc """
  Runs the `down` of the last `steps` migrations the database has applied,
  newest first, as `mix ecto.rollback --step` does. Answers the versions it
  reverted; raises what a migration raises.
  """
  @spec down!(t(), pos_integer()) :: [pos_integer()]
  def down!(%__MODULE__{} = db, steps), do: ScratchDatabase.rollback!(db, steps, db.migrations)

  @doc "The head of `priv/repo/migrations`: the last version an upgrade runs."
  @spec head() :: pos_integer()
  def head, do: ScratchDatabase.migrations() |> List.last() |> elem(0)

  defp migrate_to(db, to) do
    {:ok, ScratchDatabase.migrate!(db, to, db.migrations)}
  catch
    kind, reason -> {:error, kind, reason, __STACKTRACE__}
  end

  # The first migration the scratch database has not recorded: the one the
  # upgrade stopped at, as its transaction rolled back.
  defp stopped_at(db) do
    %{rows: rows} = query!(db, "SELECT version FROM schema_migrations")
    applied = MapSet.new(rows, fn [version] -> version end)

    db.migrations
    |> ScratchDatabase.migration_files()
    |> Enum.find_value("no pending migration", fn {version, file} ->
      if version not in applied, do: Path.basename(file)
    end)
  end

  defp known_version!(version, dir) do
    unless List.keymember?(ScratchDatabase.migration_files(dir), version, 0) do
      flunk("#{version} is not a migration in #{Path.relative_to_cwd(dir)}")
    end
  end
end
