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
  each upgrade gets its own database, named after the test database with an
  `_upgrade_` suffix, and nothing here touches the sandboxed one.

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
  import ExUnit.Callbacks, only: [on_exit: 1, start_supervised!: 1]

  alias Ecto.Adapters.Postgres
  alias Ecto.Migrator
  alias Portfolixir.Repo

  # Two connections: the migrator's lock and the migration it runs.
  @pool_size 2

  # What this VM has learned about a database's schema, cached VM-wide once
  # seen: whether the data-version log and its pending mark exist yet
  # (`Portfolixir.Derived.DataVersion`). A release migrates in a VM of its
  # own, which starts without them; this VM has seen the test database and
  # earlier scratch databases at other versions, and a migration that writes
  # through the journal would trust their answer. Every migrator run here
  # starts from a fresh VM's state, and the test leaves none behind.
  @schema_caches [
    {Portfolixir.Derived.DataVersion, :schema_ready},
    {Portfolixir.Derived.DataVersion, :pending_column}
  ]

  # The actor a seed writes under. Journal-armed tables refuse a write without
  # one, and every write the seeded release made carried one.
  @seed_actor "system_job:seeded_upgrade"

  @enforce_keys [:database, :repo]
  defstruct [:database, :repo, :from, :seeded, migrated: [], log: ""]

  @type t :: %__MODULE__{
          database: String.t(),
          repo: pid(),
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
      journal actor set; what it returns lands in `:seeded`.

  Answers the database after the upgrade: `:seeded`, `:migrated` (the
  versions the upgrade ran, ascending) and `:log` (what it logged). Fails
  the test, naming the migration, when the upgrade stops. Call it from a
  test: the database is dropped by the test's `on_exit`.
  """
  @spec upgrade!(keyword()) :: t()
  def upgrade!(opts) do
    from = Keyword.fetch!(opts, :from)
    seed = Keyword.fetch!(opts, :seed)
    db = %{scratch_database!() | from: from}

    known_version!(from)
    migrate!(db, to: from)
    seeded = in_seed_transaction(db, fn -> seed.(db) end)

    {result, log} = ExUnit.CaptureLog.with_log(fn -> migrate_to_head(db) end)

    case result do
      {:ok, migrated} ->
        %{db | seeded: seeded, migrated: migrated, log: log}

      {:error, kind, reason, stacktrace} ->
        flunk("""
        the upgrade from #{from} to head stopped at #{stopped_at(db)}:

        #{Exception.format(kind, reason, stacktrace)}
        log:
        #{log}
        """)
    end
  end

  @doc "Runs `sql` with `params` on the scratch database."
  @spec query!(t(), String.t(), list()) :: Postgrex.Result.t()
  def query!(%__MODULE__{} = db, sql, params \\ []) do
    on_database(db, fn -> Repo.query!(sql, params) end)
  end

  @doc """
  Runs `fun` in one transaction on the scratch database with a journal actor
  set, as a seed runs: for a test that writes after the upgrade, such as one
  asserting that a new row is refused. Raises what `fun` raises.
  """
  @spec journaled!(t(), (-> result)) :: result when result: term()
  def journaled!(%__MODULE__{} = db, fun), do: in_seed_transaction(db, fun)

  @doc "The head of `priv/repo/migrations`: the last version an upgrade runs."
  @spec head() :: pos_integer()
  def head, do: migrations() |> List.last() |> elem(0)

  @doc """
  Every migration under `priv/repo/migrations` as `{version, module}`,
  ascending -- the source `Ecto.Migrator` runs. Each file is compiled once per
  VM: a module already loaded (by an earlier case, or a test that requires
  the file itself) is reused, as a second compile would redefine it.
  """
  @spec migrations() :: [{pos_integer(), module()}]
  def migrations do
    Repo
    |> Migrator.migrations_path()
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(&load_migration/1)
  end

  @doc "The file name of the migration `version`, for messages."
  @spec file_of(pos_integer()) :: String.t()
  def file_of(version) do
    Repo
    |> Migrator.migrations_path()
    |> Path.join("#{version}_*.exs")
    |> Path.wildcard()
    |> case do
      [file] -> Path.basename(file)
      _none -> "#{version} (no such migration)"
    end
  end

  # -- the scratch database --------------------------------------------------

  defp scratch_database! do
    base = Keyword.fetch!(Repo.config(), :database)
    database = "#{base}_upgrade_#{System.pid()}_#{System.unique_integer([:positive])}"

    config =
      Keyword.merge(Repo.config(),
        database: database,
        pool: DBConnection.ConnectionPool,
        pool_size: @pool_size,
        log: false
      )

    :ok = Postgres.storage_up(config)

    # Registered before the repo starts, so a failed start still drops the
    # database. The test supervisor stops the repo before on_exit runs; FORCE
    # also ends any connection a crashed migration left behind.
    on_exit(fn ->
      forget_schema_caches()
      :ok = Postgres.storage_down(Keyword.put(config, :force_drop, true))
    end)

    repo = start_supervised!({Repo, Keyword.put(config, :name, nil)})
    %__MODULE__{database: database, repo: repo}
  end

  defp on_database(%__MODULE__{repo: repo}, fun) do
    previous = Repo.put_dynamic_repo(repo)

    try do
      fun.()
    after
      Repo.put_dynamic_repo(previous)
    end
  end

  defp in_seed_transaction(db, fun) do
    on_database(db, fn ->
      {:ok, result} =
        Repo.transaction(fn ->
          Repo.query!("SELECT set_config('portfolixir.journal_actor', $1, true)", [@seed_actor])
          fun.()
        end)

      result
    end)
  end

  # -- migrating ---------------------------------------------------------------

  defp migrate!(%__MODULE__{repo: repo}, to: version) do
    forget_schema_caches()
    Migrator.run(Repo, migrations(), :up, to: version, dynamic_repo: repo, log: false)
  end

  defp migrate_to_head(%__MODULE__{repo: repo}) do
    forget_schema_caches()
    {:ok, Migrator.run(Repo, migrations(), :up, all: true, dynamic_repo: repo, log: false)}
  catch
    kind, reason -> {:error, kind, reason, __STACKTRACE__}
  end

  defp forget_schema_caches, do: Enum.each(@schema_caches, &:persistent_term.erase/1)

  # The first migration the scratch database has not recorded: the one the
  # upgrade stopped at, as its transaction rolled back.
  defp stopped_at(db) do
    %{rows: rows} = query!(db, "SELECT version FROM schema_migrations")
    applied = MapSet.new(rows, fn [version] -> version end)

    case Enum.find(migrations(), fn {version, _module} -> version not in applied end) do
      {version, _module} -> file_of(version)
      nil -> "no pending migration"
    end
  end

  defp known_version!(version) do
    unless List.keymember?(migrations(), version, 0) do
      flunk("#{version} is not a migration under priv/repo/migrations")
    end
  end

  defp load_migration(file) do
    {version, "_" <> _name} = file |> Path.basename() |> Integer.parse()
    module = module_of(file)

    unless Code.ensure_loaded?(module), do: Code.require_file(file)

    {version, module}
  end

  # The module a migration file defines, read from its source rather than by
  # compiling it.
  defp module_of(file) do
    {:defmodule, _meta, [{:__aliases__, _alias_meta, parts} | _body]} =
      file |> File.read!() |> Code.string_to_quoted!()

    Module.concat(parts)
  end
end
