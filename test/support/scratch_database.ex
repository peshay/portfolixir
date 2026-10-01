defmodule Portfolixir.ScratchDatabase do
  @moduledoc """
  A database of a test's own, outside the SQL sandbox, for the two harnesses
  that cannot run inside it: the seeded-upgrade harness
  (`Portfolixir.SeededUpgrade`), which runs the migrator, and the lock-order
  harness (`Portfolixir.LockRace`), which needs two real connections. The
  sandbox the rest of the suite uses is never touched.

  `start!/1`, called from a test or a `setup_all`, creates an empty database
  named after the test database with a suffix, and reaches it through a
  second, unsandboxed instance of `Portfolixir.Repo` started as a dynamic repo
  and supervised by the test. It is not a repo module of its own because
  application code reaches the database through `Portfolixir.Repo` by name: a
  migration's backfill, or a context function a lock-order case runs. In a
  process that has called `Portfolixir.Repo.put_dynamic_repo/1` with it (see
  `run/2`), and in every process `Ecto.Migrator` runs a migration in, those
  calls land on the scratch database. The database is force-dropped by the
  test's `on_exit`, whatever the outcome.
  """

  import ExUnit.Callbacks, only: [on_exit: 1, start_supervised!: 1]

  alias Ecto.Adapters.Postgres
  alias Ecto.Migrator
  alias Portfolixir.Repo

  # What this VM has learned about a database's schema, cached VM-wide once
  # seen: whether the data-version log and its pending mark exist yet
  # (`Portfolixir.Derived.DataVersion`). A release migrates in a VM of its
  # own, which starts without them; this VM has seen the test database and
  # other scratch databases at other versions, and a migration that writes
  # through the journal would trust their answer. Every migrator run here
  # starts from a fresh VM's state, and a test leaves none behind.
  @schema_caches [
    {Portfolixir.Derived.DataVersion, :schema_ready},
    {Portfolixir.Derived.DataVersion, :pending_column}
  ]

  @enforce_keys [:database, :repo]
  defstruct [:database, :repo]

  @type t :: %__MODULE__{database: String.t(), repo: pid()}

  @doc """
  Creates an empty scratch database and starts a repo on it. Options:
  `:suffix` (the name's suffix, default `"scratch"`) and `:pool_size` (the
  connections the test needs at once, default 2: the migrator's lock and the
  migration it runs).
  """
  @spec start!(keyword()) :: t()
  def start!(opts \\ []) do
    base = Keyword.fetch!(Repo.config(), :database)
    suffix = Keyword.get(opts, :suffix, "scratch")
    database = "#{base}_#{suffix}_#{System.pid()}_#{System.unique_integer([:positive])}"

    config =
      Keyword.merge(Repo.config(),
        database: database,
        pool: DBConnection.ConnectionPool,
        pool_size: Keyword.get(opts, :pool_size, 2),
        log: false
      )

    :ok = Postgres.storage_up(config)

    # Registered before the repo starts, so a failed start still drops the
    # database. The test supervisor stops the repo before on_exit runs; FORCE
    # also ends any connection a crashed writer or migration left behind.
    on_exit(fn ->
      forget_schema_caches()
      :ok = Postgres.storage_down(Keyword.put(config, :force_drop, true))
    end)

    repo = start_supervised!({Repo, Keyword.put(config, :name, nil)})
    %__MODULE__{database: database, repo: repo}
  end

  @doc """
  Migrates the database up to `version` (inclusive), or to head with
  `:head`, from a fresh VM's schema caches. Answers the versions it ran;
  raises what a migration raises.
  """
  @spec migrate!(%{repo: pid()}, pos_integer() | :head) :: [pos_integer()]
  def migrate!(%{repo: repo}, version) do
    forget_schema_caches()
    to = if version == :head, do: [all: true], else: [to: version]
    Migrator.run(Repo, migrations(), :up, to ++ [dynamic_repo: repo, log: false])
  end

  @doc "Runs `fun` in this process with `Portfolixir.Repo` on the scratch database."
  @spec run(%{repo: pid()}, (-> result)) :: result when result: term()
  def run(%{repo: repo}, fun) do
    previous = Repo.put_dynamic_repo(repo)

    try do
      fun.()
    after
      Repo.put_dynamic_repo(previous)
    end
  end

  @doc "Runs `sql` with `params` on the scratch database."
  @spec query!(%{repo: pid()}, String.t(), list()) :: Postgrex.Result.t()
  def query!(db, sql, params \\ []), do: run(db, fn -> Repo.query!(sql, params) end)

  @doc """
  Every migration under `priv/repo/migrations` as `{version, module}`,
  ascending -- the source `Ecto.Migrator` runs. Each file is compiled once per
  VM: a module already loaded (by an earlier run, or a test that requires the
  file itself) is reused, as a second compile would redefine it.
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

  defp forget_schema_caches, do: Enum.each(@schema_caches, &:persistent_term.erase/1)

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
