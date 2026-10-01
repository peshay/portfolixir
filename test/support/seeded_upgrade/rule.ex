defmodule Portfolixir.SeededUpgrade.Rule do
  @moduledoc """
  The rule the seeded-upgrade harness exists for (Sprint 17, Lane G-1,
  #995): every migration newer than `since/0` that adds a CHECK, a NOT NULL
  or a backfill has a seeded case -- a test tagged
  `@tag seeded_upgrade: <its version>` that seeds the rows an older instance
  holds and migrates over them with `Portfolixir.SeededUpgrade`.

  Such a migration is exactly what a database migrated from empty cannot
  test: it holds no legacy row for the constraint to refuse or the backfill
  to trip on, and the release migrates at boot. Migrations up to `since/0`
  are not listed anywhere; they are simply older than the rule.

  ## The heuristic

  Read from the migration's parsed source, so comments, `@moduledoc` and
  `@doc` text never count, and deliberately wide: a false positive costs one
  seeded case, a miss costs a release that does not boot.

    * **CHECK** -- `constraint(table, name, check: ...)` on a table the
      migration does not create itself, or SQL text with `CHECK (` or
      `VALIDATE CONSTRAINT` (which makes a constraint added `NOT VALID`
      bind the rows already stored).
    * **NOT NULL** -- `add`, `modify` or `add_if_not_exists` with
      `null: false`, or `timestamps` without `null: true` (Ecto makes both
      columns NOT NULL by default), inside `alter table(...)` of a table the
      migration does not create; or SQL text with `SET NOT NULL` or
      `ADD COLUMN ... NOT NULL`.
    * **backfill** -- SQL text with `UPDATE <table> SET` or
      `INSERT INTO ... SELECT`; a write through a repo (`repo()`, a `repo`
      variable or `Repo`: `update_all`, `insert_all`, `update`, `insert` and
      their bang forms); or any call into application code (a `Portfolixir`
      module other than the repo), which is how the policy-rule author
      backfill ran.

  SQL is matched in upper case, the way every migration here writes it, so
  prose such as a log message's "kind check (" is not read as SQL. A string
  built by interpolation (`"UPDATE \#{table} SET ..."`, the house style for
  a table named in a module attribute) or by `<>` is matched as one text,
  each interpolated or concatenated expression standing in as an
  identifier: matched piece by piece, `UPDATE \#{table} SET` would read as
  two strings and no backfill.
  """

  alias Portfolixir.ScratchDatabase

  # The latest migration on the branch the rule landed on. A migration after
  # it falls under the rule; nothing up to it is listed.
  @since 20_260_926_121_500

  @repo_writes [
    :update_all,
    :insert_all,
    :update,
    :update!,
    :insert,
    :insert!,
    :insert_or_update,
    :insert_or_update!
  ]

  @sql [
    check: ~r/\bCHECK\s*\(/,
    check: ~r/\bVALIDATE\s+CONSTRAINT\b/,
    not_null: ~r/\bSET\s+NOT\s+NULL\b/,
    not_null: ~r/\bADD\s+COLUMN\b[^,;]*\bNOT\s+NULL\b/,
    backfill: ~r/\bUPDATE\s+(?:ONLY\s+)?[\w."]+\s+(?:AS\s+)?(?:\w+\s+)?SET\b/,
    backfill: ~r/\bINSERT\s+INTO\b[^;]*\bSELECT\b/
  ]

  # What an interpolated or concatenated expression reads as in SQL text.
  @placeholder "interpolated"

  @type change :: :check | :not_null | :backfill

  @doc "The last migration older than the rule."
  @spec since() :: pos_integer()
  def since, do: @since

  @doc """
  The migrations newer than `since/0` that add a CHECK, a NOT NULL or a
  backfill and that no seeded case names, as `{version, file, changes}`.
  Options, for the rule's own tests: `:migrations` (the directory, by default
  `priv/repo/migrations`), `:since` (the cutoff, by default `since/0`) and
  `:tests` (the test files read for tags, by default `test/**/*_test.exs`).
  """
  @spec uncovered(keyword()) :: [{pos_integer(), String.t(), [change()]}]
  def uncovered(opts \\ []) do
    dir = Keyword.get_lazy(opts, :migrations, &ScratchDatabase.migrations_dir/0)
    since = Keyword.get(opts, :since, @since)
    covered = opts |> Keyword.get(:tests, "test/**/*_test.exs") |> covered_versions()

    for {version, file} <- ScratchDatabase.migration_files(dir),
        version > since,
        version not in covered,
        changes <- [file |> File.read!() |> changes()],
        changes != [] do
      {version, Path.basename(file), changes}
    end
  end

  @doc """
  The versions the seeded cases cover: every `seeded_upgrade: <version>` (or
  a list of versions) tag in the test files `glob` matches.
  """
  @spec covered_versions(String.t()) :: MapSet.t(pos_integer())
  def covered_versions(glob \\ "test/**/*_test.exs") do
    for file <- Path.wildcard(glob),
        [_tag, value] <-
          Regex.scan(~r/seeded_upgrade:\s*(\[[^\]]*\]|\d[\d_]*)/, File.read!(file)),
        [digits] <- Regex.scan(~r/\d[\d_]*/, value),
        into: MapSet.new() do
      digits |> String.replace("_", "") |> String.to_integer()
    end
  end

  @doc "What a migration's source adds that legacy rows can break, by the heuristic above."
  @spec changes(String.t()) :: [change()]
  def changes(source) do
    ast = source |> Code.string_to_quoted!() |> drop_docs()
    created = created_tables(ast)
    app_aliases = app_aliases(ast)

    {_ast, found} =
      Macro.prewalk(ast, MapSet.new(), fn node, found ->
        {node, MapSet.union(found, detect(node, created, app_aliases))}
      end)

    Enum.filter([:check, :not_null, :backfill], &(&1 in found))
  end

  @doc """
  The failure message for `uncovered/1`'s list, over the migrations in `dir`
  (by default `priv/repo/migrations`).
  """
  @spec explain([{pos_integer(), String.t(), [change()]}], String.t()) :: String.t()
  def explain(uncovered, dir \\ ScratchDatabase.migrations_dir()) do
    versions = dir |> ScratchDatabase.migration_files() |> Enum.map(&elem(&1, 0))
    shown = if dir == ScratchDatabase.migrations_dir(), do: "priv/repo/migrations", else: dir

    entries =
      Enum.map_join(uncovered, "\n", fn {version, file, changes} ->
        "  #{shown}/#{file} -- adds #{Enum.map_join(changes, " and ", &describe/1)}; " <>
          seed_at(versions, version)
      end)

    """
    These migrations are newer than the seeded-upgrade rule (#{@since}) and add a
    CHECK, a NOT NULL or a backfill, but no seeded-upgrade case covers them:

    #{entries}

    A migration like that runs over every row an upgrading instance holds, and a
    database migrated from empty holds none -- the release can stop at boot on a
    row no other test has. For each one, add a case that seeds such rows with
    plain SQL and migrates over them, in a module with
    `@moduletag :seeded_upgrade`:

        @tag seeded_upgrade: <the migration's version>
        test "<the migration> does not stop the upgrade over <the legacy rows>" do
          upgrade = Portfolixir.SeededUpgrade.upgrade!(from: <the version before it>, seed: &seed/1)
          # assert the migrated shape with Portfolixir.SeededUpgrade.query!/3
        end

    test/portfolixir/seeded_upgrade/sprint16_test.exs has two, and
    docs/development/guide.md ("Upgrade migrations over legacy rows") says when
    a case is required and how to write one.
    """
  end

  # -- the source walk ----------------------------------------------------------

  defp drop_docs(ast) do
    Macro.prewalk(ast, fn
      {:@, _meta, [{doc, _doc_meta, _text}]} when doc in [:moduledoc, :doc, :typedoc] -> nil
      node -> node
    end)
  end

  defp created_tables(ast) do
    {_ast, created} =
      Macro.prewalk(ast, MapSet.new(), fn
        {create, _meta, [{:table, _table_meta, [name | _opts]} | _block]} = node, acc
        when create in [:create, :create_if_not_exists] ->
          {node, MapSet.put(acc, table_name(name))}

        node, acc ->
          {node, acc}
      end)

    created
  end

  # The short names under which the migration reaches a `Portfolixir` module
  # through `alias` (the repo excepted).
  defp app_aliases(ast) do
    {_ast, aliases} = Macro.prewalk(ast, MapSet.new(), &{&1, collect_alias(&1, &2)})
    aliases
  end

  # `alias Portfolixir.A.B` and `alias Portfolixir.A.B, as: C`.
  defp collect_alias(
         {:alias, _meta, [{:__aliases__, _, [:Portfolixir | _] = parts} | opts]},
         acc
       ),
       do: put_alias(acc, parts, as(opts))

  # `alias Portfolixir.A.{B, C}`.
  defp collect_alias({:alias, _meta, [{{:., _, [base_alias, :{}]}, _, children}]}, acc) do
    case base_alias do
      {:__aliases__, _, [:Portfolixir | _] = base} ->
        for {:__aliases__, _meta, parts} <- children, reduce: acc do
          acc -> put_alias(acc, base ++ parts, nil)
        end

      _other ->
        acc
    end
  end

  defp collect_alias(_node, acc), do: acc

  defp put_alias(acc, [:Portfolixir, :Repo | _parts], _as), do: acc
  defp put_alias(acc, parts, nil), do: MapSet.put(acc, List.last(parts))
  defp put_alias(acc, _parts, {:__aliases__, _meta, [short]}), do: MapSet.put(acc, short)

  defp as([opts]) when is_list(opts), do: Keyword.get(opts, :as)
  defp as(_opts), do: nil

  defp detect({:constraint, _meta, [table, _name, opts]}, created, _app_aliases)
       when is_list(opts) do
    if Keyword.has_key?(opts, :check) and table_name(table) not in created,
      do: MapSet.new([:check]),
      else: MapSet.new()
  end

  defp detect({:alter, _meta, [{:table, _table_meta, [table | _opts]}, [do: block]]}, created, _) do
    if table_name(table) not in created and not_null_column?(block),
      do: MapSet.new([:not_null]),
      else: MapSet.new()
  end

  defp detect(text, _created, _app_aliases) when is_binary(text), do: sql_changes(text)

  defp detect({op, _meta, parts} = built, _created, _app_aliases)
       when op in [:<<>>, :<>] and is_list(parts),
       do: built |> sql_text() |> sql_changes()

  defp detect({{:., _meta, [receiver, fun]}, _call_meta, _args}, _created, app_aliases)
       when is_atom(fun) do
    if (repo?(receiver) and fun in @repo_writes) or app_module?(receiver, app_aliases),
      do: MapSet.new([:backfill]),
      else: MapSet.new()
  end

  defp detect(_node, _created, _app_aliases), do: MapSet.new()

  defp sql_changes(text) do
    for {change, pattern} <- @sql, Regex.match?(pattern, text), into: MapSet.new(), do: change
  end

  # A string as the SQL it builds: the literal pieces of an interpolation or
  # a `<>` chain joined, each expression standing in as one identifier.
  defp sql_text(text) when is_binary(text), do: text
  defp sql_text({:<<>>, _meta, parts}), do: Enum.map_join(parts, &sql_text/1)
  defp sql_text({:<>, _meta, [left, right]}), do: sql_text(left) <> sql_text(right)
  defp sql_text(_expression), do: @placeholder

  defp not_null_column?(block) do
    {_ast, found?} =
      Macro.prewalk(block, false, fn
        {column, _meta, args} = node, found?
        when column in [:add, :modify, :add_if_not_exists] and is_list(args) ->
          {node, found? or null_false?(args)}

        {:timestamps, _meta, args} = node, found? when is_list(args) ->
          {node, found? or not null_true?(args)}

        node, found? ->
          {node, found?}
      end)

    found?
  end

  defp null_false?(args) do
    case List.last(args) do
      opts when is_list(opts) -> Keyword.keyword?(opts) and Keyword.get(opts, :null) == false
      _other -> false
    end
  end

  # `timestamps(null: true)` is the one form that adds nullable columns.
  defp null_true?([opts]) when is_list(opts), do: Keyword.get(opts, :null) == true
  defp null_true?(_args), do: false

  defp repo?({:repo, _meta, context}) when is_atom(context) or context == [], do: true
  defp repo?({:__aliases__, _meta, [:Repo]}), do: true
  defp repo?({:__aliases__, _meta, [:Portfolixir, :Repo]}), do: true
  defp repo?(_receiver), do: false

  defp app_module?({:__aliases__, _meta, [:Portfolixir, :Repo | _parts]}, _app_aliases), do: false
  defp app_module?({:__aliases__, _meta, [:Portfolixir | _parts]}, _app_aliases), do: true
  defp app_module?({:__aliases__, _meta, [short | _parts]}, app_aliases), do: short in app_aliases
  defp app_module?(_receiver, _app_aliases), do: false

  defp table_name(name) when is_atom(name), do: Atom.to_string(name)
  defp table_name(name) when is_binary(name), do: name
  defp table_name(other), do: Macro.to_string(other)

  defp describe(:check), do: "a CHECK"
  defp describe(:not_null), do: "a NOT NULL"
  defp describe(:backfill), do: "a backfill"

  defp seed_at(versions, version) do
    case versions |> Enum.filter(&(&1 < version)) |> List.last() do
      nil -> "seed an empty database, as it is the first migration"
      before -> "seed at #{before}, the migration before it"
    end
  end
end
