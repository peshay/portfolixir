defmodule Portfolixir.Invariants.IdentityFreezeWritersTest do
  # ADR-0050 §11 first bullet and §16 invariant 15 (risk-tier: money and
  # identity, ADR-0036). The identity-field freezes — a cash account's
  # currency and portfolio binding, a depot's portfolio binding, a security's
  # currency — live in the three schemas' `changeset/2`, "so every writer is
  # covered". That holds only while every writer of the three tables builds
  # its write there. The Sprint 15 lesson: an invariant is swept over every
  # writer of the table, not shown on one path. This test is the sweep's
  # static half — it enumerates the writers from the source, so a new one
  # fails here until it is classified; the dynamic half shows each update
  # writer refused (test/portfolixir/lifecycle/freeze_test.exs, the API and
  # LiveView freeze tests).
  #
  # The same sweep holds ADR-0050 §4's name guard: with no unique index, the
  # guard in the account schemas' `changeset/2` is the single enforcement
  # point of account-name uniqueness, "every writer passes through it". So
  # every schema function that can write `name` runs it, every writer of
  # `former_names` is known and classified, and no code writes either around
  # them.
  use ExUnit.Case, async: true

  @lib_sources Path.wildcard("lib/**/*.ex")

  @schema_sources %{
    "lib/portfolixir/portfolios/cash_account.ex" => ~w(currency_code portfolio_id),
    "lib/portfolixir/portfolios/securities_account.ex" => ~w(portfolio_id),
    "lib/portfolixir/catalog/security.ex" => ~w(currency_code)
  }

  @schemas ~w(CashAccount SecuritiesAccount Security)a
  @tables ~w(cash_accounts securities_accounts securities)
  @frozen ~w(currency_code portfolio_id)a

  # Every function outside the schemas that builds a changeset of one of the
  # three, and why the freeze holds on it:
  #   :insert        — a new row, which nothing can reference yet;
  #   :update        — an update through `changeset/2`, which carries the
  #                    freeze (shown refused in the dynamic half);
  #   :isin_only     — `changeset/2` with an ISIN alone (ADR-0029 §3), so it
  #                    carries the freeze and changes no frozen field;
  #   :logo_only     — `logo_changeset/2`, which writes `attributes` alone;
  #   :former_names_only — `former_names_changeset/2` (ADR-0050 §4), which
  #                    writes `former_names` alone, for the remembered remap,
  #                    the removal and a merge's append of the source's names;
  #   :cash_link_only  — `SecuritiesAccount.reassign_changeset/2` (ADR-0050 §7
  #                    step 5), which writes a depot's `cash_account_id` alone,
  #                    for a cash-account merge re-pointing the source's
  #                    linked depots; no frozen field and no name is cast.
  @expected_writers %{
    {"lib/portfolixir/portfolios.ex", :create_cash_account, "CashAccount.changeset"} => :insert,
    {"lib/portfolixir/portfolios.ex", :update_cash_account, "CashAccount.changeset"} => :update,
    {"lib/portfolixir/portfolios.ex", :create_securities_account, "SecuritiesAccount.changeset"} =>
      :insert,
    {"lib/portfolixir/portfolios.ex", :update_securities_account, "SecuritiesAccount.changeset"} =>
      :update,
    {"lib/portfolixir/catalog.ex", :create_security, "Security.changeset"} => :insert,
    {"lib/portfolixir/catalog.ex", :update_security, "Security.changeset"} => :update,
    {"lib/portfolixir/catalog.ex", :put_logo_attributes, "Security.logo_changeset"} => :logo_only,
    {"lib/portfolixir/catalog/identifier_aliases.ex", :write_new_isin, "Security.changeset"} =>
      :isin_only,
    {"lib/portfolixir/lifecycle/account_names.ex", :former_names_changeset,
     "CashAccount.former_names_changeset"} => :former_names_only,
    {"lib/portfolixir/lifecycle/account_names.ex", :former_names_changeset,
     "SecuritiesAccount.former_names_changeset"} => :former_names_only,
    {"lib/portfolixir/lifecycle/merge_writer.ex", :append_former_names,
     "CashAccount.former_names_changeset"} => :former_names_only,
    {"lib/portfolixir/lifecycle/merge_writer.ex", :append_former_names,
     "SecuritiesAccount.former_names_changeset"} => :former_names_only,
    {"lib/portfolixir/lifecycle/merge_writer.ex", :reassign_depot,
     "SecuritiesAccount.reassign_changeset"} => :cash_link_only
  }

  @changeset_writes ~w(put_change force_change change)a
  @bulk_writes ~w(insert_all update_all)a
  @upserts ~w(insert insert! insert_all insert_or_update insert_or_update!)a
  @field_writes ~w(cast put_change force_change change insert_all update_all)a

  @account_schema_sources ~w(
    lib/portfolixir/portfolios/cash_account.ex
    lib/portfolixir/portfolios/securities_account.ex
  )
  @account_schemas ~w(CashAccount SecuritiesAccount)a
  @account_tables ~w(cash_accounts securities_accounts)

  # Every function that can write `former_names` (ADR-0050 §4), and why the
  # name guard holds on it:
  #   :schema_builder — the schemas' `former_names_changeset/2`, called only
  #                     by the writers below;
  #   :rename_rule    — `changeset/2`'s guard forces the list on a rename,
  #                     under the account-identity lock;
  #   :remember_or_removal — the remembered remap and the removal, which hold
  #                     the lock and decide the outcome first;
  #   :backfill       — the one-time migration from the journal, held against
  #                     the guard before it writes (it runs alone, at upgrade);
  #   :merge          — a merge's append of the source's names to the target
  #                     (ADR-0050 §7 step 7, L3): the merge holds the
  #                     account-identity lock it took first, and appends only
  #                     what `AccountNames.merge_names/2` answered after the
  #                     source was deleted — the guard's check, with the
  #                     target's live name, its own former names and every
  #                     name another account carries left out.
  @former_name_writers %{
    {"lib/portfolixir/portfolios/cash_account.ex", :former_names_changeset} => :schema_builder,
    {"lib/portfolixir/portfolios/securities_account.ex", :former_names_changeset} =>
      :schema_builder,
    {"lib/portfolixir/lifecycle/account_names.ex", :guard_rename} => :rename_rule,
    {"lib/portfolixir/lifecycle/account_names.ex", :former_names_changeset} =>
      :remember_or_removal,
    {"lib/portfolixir/lifecycle/former_names_backfill.ex", :write_row} => :backfill,
    {"lib/portfolixir/lifecycle/merge_writer.ex", :append_former_names} => :merge
  }

  # User story:
  # As the maintainer of the identity-field freezes,
  # I want every code path that builds a write of a cash account, a depot or
  # a security to be known by name, with the reason the freeze holds on it,
  # so that a new writer cannot appear around the freeze unswept.
  #
  # Acceptance criteria:
  # - The functions outside the three schemas that call one of their
  #   changeset builders are exactly the expected set.
  # - Every update among them goes through `changeset/2`, which carries the
  #   freeze; the only other builder is the logo changeset.
  test "the writers of the three tables are exactly the known, classified set" do
    found =
      @lib_sources
      |> Enum.reject(&Map.has_key?(@schema_sources, &1))
      |> Enum.flat_map(&builder_calls_in/1)
      |> MapSet.new()

    expected = @expected_writers |> Map.keys() |> MapSet.new()
    unexpected = found |> MapSet.difference(expected) |> Enum.sort()
    gone = expected |> MapSet.difference(found) |> Enum.sort()

    assert unexpected == [],
           "new writers of cash_accounts, securities_accounts or securities — classify each " <>
             "in @expected_writers and, if it updates a stored row, show the freeze refusing it " <>
             "(ADR-0050 §11):\n" <> Enum.map_join(unexpected, "\n", &inspect/1)

    assert gone == [],
           "expected writers no longer found — did they move?\n" <>
             Enum.map_join(gone, "\n", &inspect/1)

    for {{_path, _fun, builder}, :update} <- @expected_writers do
      assert builder =~ ~r/\.changeset$/, "#{builder} is an update without the freeze"
    end
  end

  # User story:
  # As the maintainer of the identity-field freezes,
  # I want every function in the three schemas that can put a frozen field on
  # a row to run the freeze,
  # so that a second changeset added beside `changeset/2` cannot bypass it.
  #
  # Acceptance criteria:
  # - In each schema, the functions that cast or change a frozen field are
  #   exactly `changeset/2`, and each pipes into `Freeze.validate/1`.
  test "each schema function that can write a frozen field runs the freeze" do
    for {path, fields} <- @schema_sources do
      source = File.read!(path)
      ast = Code.string_to_quoted!(source)
      attributes = module_attributes(ast)

      writers =
        for {name, body} <- defs(ast),
            writes_frozen?(body, fields, attributes),
            uniq: true,
            do: {name, runs_freeze?(body)}

      assert writers == [{:changeset, true}],
             "#{path}: the functions that can write #{Enum.join(fields, ", ")} must be " <>
               "exactly changeset/2, piped into Freeze.validate/1; found #{inspect(writers)}"
    end
  end

  test "no code writes a frozen field around the changeset" do
    offenders = Enum.flat_map(@lib_sources -- Map.keys(@schema_sources), &side_writes_in/1)

    assert offenders == [],
           "a frozen identity field written outside the schemas' changeset/2 " <>
             "(ADR-0050 §11):\n" <> Enum.join(offenders, "\n")
  end

  # The sweep must not pass vacuously: it finds a writer and each kind of
  # side write in a sample.
  test "the source sweep finds a writer and the side writes in a sample" do
    sample = """
    defmodule Sample do
      def a(s), do: Security.changeset(s, %{})
      def b(s), do: s |> Ecto.Changeset.change(currency_code: "USD") |> Repo.update()
      def c(id), do: from(a in CashAccount, where: a.id == ^id) |> Repo.update_all(set: [portfolio_id: 2])
      def d, do: Repo.query!("UPDATE securities SET currency_code = 'USD'")
      def e(rows), do: Repo.insert_all(Security, rows, on_conflict: {:replace, [:currency_code]})
      def f(params), do: %CashAccount{} |> Ecto.Changeset.cast(params, [:currency_code]) |> Repo.insert()
      def g(id), do: from(a in "cash_accounts", where: a.id == ^id) |> Repo.update_all(set: [currency_code: "USD"])
      def h(rows), do: Repo.insert_all(Security, rows, on_conflict: :replace_all)
      def i(cs), do: Repo.insert(cs, on_conflict: {:replace_all_except, [:id]}, conflict_target: :id, into: SecuritiesAccount)
    end
    """

    assert [{"sample.ex", :a, "Security.changeset"}] =
             builder_calls_in_source("sample.ex", sample)

    offenders = side_writes_in_source("sample.ex", sample)

    # b's change, c's update_all, d's raw SQL, e's upsert; f's cast outside
    # the schemas, g's schemaless update_all, h's and i's replace-all upserts.
    assert length(offenders) == 8, Enum.join(offenders, "\n")
    assert Enum.any?(offenders, &(&1 =~ "cast"))
    assert Enum.count(offenders, &(&1 =~ "replace_all")) == 2
  end

  # User story:
  # As the maintainer of the name guard (ADR-0050 §4),
  # I want every code path that can write an account's name or its former
  # names to be known, and each schema function that writes a name to run
  # the guard,
  # so that a new writer cannot give two accounts one name, or one former
  # name to two accounts, where no unique index would stop it.
  #
  # Acceptance criteria:
  # - In each account schema, the functions that cast or change `name` are
  #   exactly `changeset/2`, and it pipes into `AccountNames.validate/1`.
  # - The functions that write `former_names` are exactly the classified set.
  # - No code writes `name` or `former_names` of an account around them: no
  #   change, cast, bulk write or raw SQL naming them outside the schemas and
  #   the classified writers.
  test "each account schema function that can write a name runs the name guard" do
    for path <- @account_schema_sources do
      ast = path |> File.read!() |> Code.string_to_quoted!()
      attributes = module_attributes(ast)

      writers =
        for {name, body} <- defs(ast),
            writes_frozen?(body, ["name"], attributes),
            uniq: true,
            do: {name, runs_name_guard?(body)}

      assert writers == [{:changeset, true}],
             "#{path}: the functions that can write name must be exactly changeset/2, " <>
               "piped into AccountNames.validate/1; found #{inspect(writers)}"
    end
  end

  test "the writers of former_names are exactly the known, classified set" do
    found = @lib_sources |> Enum.flat_map(&former_name_writers_in/1) |> MapSet.new()
    expected = @former_name_writers |> Map.keys() |> MapSet.new()

    assert MapSet.difference(found, expected) |> Enum.sort() == [],
           "new writers of former_names — classify each in @former_name_writers with the " <>
             "reason the name guard holds on it (ADR-0050 §4)"

    assert MapSet.difference(expected, found) |> Enum.sort() == [],
           "expected writers of former_names no longer found — did they move?"
  end

  test "no code writes an account's name around the changeset" do
    offenders =
      @lib_sources
      |> Kernel.--(@account_schema_sources)
      |> Enum.flat_map(&name_side_writes_in/1)

    assert offenders == [],
           "an account's name written outside its changeset/2 (ADR-0050 §4):\n" <>
             Enum.join(offenders, "\n")
  end

  test "the name sweeps find their writers in a sample" do
    sample = """
    defmodule Sample do
      def a(acc, names), do: Ecto.Changeset.change(acc, former_names: names)
      def b(cs, names), do: Changeset.force_change(cs, :former_names, names)
      def c(acc, names), do: CashAccount.former_names_changeset(acc, names)
      def d(id), do: from(a in "securities_accounts", where: a.id == ^id) |> Repo.update_all(set: [former_names: []])
      def e(%CashAccount{} = acc), do: acc |> Ecto.Changeset.change(name: "Other") |> Repo.update()
      def f(id), do: from(a in CashAccount, where: a.id == ^id) |> Repo.update_all(set: [name: "X"])
      def g, do: Repo.query!("UPDATE securities_accounts SET name = 'X'")
      def h(category), do: category |> Ecto.Changeset.change(name: "Core") |> Repo.update()
      def i(%CashAccount{} = acc, name), do: Changeset.force_change(acc, :notes, name)
    end
    """

    assert "sample.ex"
           |> former_name_writers_in_source(sample)
           |> Enum.map(&elem(&1, 1))
           |> Enum.sort() ==
             [:a, :b, :c, :d]

    offenders = name_side_writes_in_source("sample.ex", sample)

    # a to d write former_names; e to g write an account's name; h renames
    # something that is not an account, and i only passes a variable called
    # name.
    assert length(offenders) == 7, Enum.join(offenders, "\n")
    refute Enum.any?(offenders, &(&1 =~ ~r/sample\.ex:(9|10) /))
  end

  # --- the sweep ---------------------------------------------------------------

  defp builder_calls_in(path), do: builder_calls_in_source(path, File.read!(path))

  defp builder_calls_in_source(path, source) do
    source
    |> Code.string_to_quoted!()
    |> defs()
    |> Enum.flat_map(fn {name, body} ->
      for builder <- builders_called(body), do: {path, name, builder}
    end)
    |> Enum.uniq()
  end

  defp builders_called(body) do
    {_ast, builders} =
      Macro.prewalk(body, [], fn
        {{:., _, [{:__aliases__, _, segments}, fun]}, _, _args} = node, acc
        when is_atom(fun) ->
          schema = List.last(segments)

          if schema in @schemas and String.ends_with?(Atom.to_string(fun), "changeset"),
            do: {node, ["#{schema}.#{fun}" | acc]},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(builders)
  end

  defp side_writes_in(path), do: side_writes_in_source(path, File.read!(path))

  # A side write is a frozen field written without `changeset/2`: a
  # put_change/force_change/change naming `currency_code` or `portfolio_id`
  # anywhere (the struct it changes cannot be told from the source); a cast,
  # an update_all or an insert_all naming one (an upsert's on_conflict replace
  # included) in a function that names one of the three schemas or tables; an
  # insert or insert_all there that replaces every column on conflict
  # (`:replace_all`, `{:replace_all_except, _}`), which names no field; or a
  # raw SQL UPDATE of one of the three tables.
  defp side_writes_in_source(path, source) do
    ast = Code.string_to_quoted!(source)

    in_defs =
      for {_name, body} <- defs(ast),
          offender <- frozen_writes(body, path, names_a_schema?(body)),
          do: offender

    raw_sql =
      ast
      |> strings()
      |> Enum.filter(&raw_sql_write?/1)
      |> Enum.map(fn _sql -> "#{path} raw_sql" end)

    in_defs ++ raw_sql
  end

  defp frozen_writes(body, path, names_a_schema?) do
    {_ast, offenders} =
      Macro.prewalk(body, [], fn
        {fun, meta, args} = node, acc when fun in @changeset_writes and is_list(args) ->
          {node, maybe_offender(acc, mentions_frozen?(args), path, meta, fun)}

        {{:., _, [_mod, fun]}, meta, args} = node, acc when fun in @changeset_writes ->
          {node, maybe_offender(acc, mentions_frozen?(args), path, meta, fun)}

        {:cast, meta, args} = node, acc when is_list(args) ->
          {node,
           maybe_offender(acc, names_a_schema? and mentions_frozen?(args), path, meta, :cast)}

        {{:., _, [_mod, :cast]}, meta, args} = node, acc ->
          {node,
           maybe_offender(acc, names_a_schema? and mentions_frozen?(args), path, meta, :cast)}

        {{:., _, [_mod, fun]}, meta, args} = node, acc when fun in @upserts ->
          {node, upsert_offender(acc, names_a_schema?, args, path, meta, fun)}

        {fun, meta, args} = node, acc when fun in @bulk_writes and is_list(args) ->
          {node, upsert_offender(acc, names_a_schema?, args, path, meta, fun)}

        {{:., _, [_mod, fun]}, meta, args} = node, acc when fun in @bulk_writes ->
          {node, upsert_offender(acc, names_a_schema?, args, path, meta, fun)}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(offenders)
  end

  defp upsert_offender(acc, names_a_schema?, args, path, meta, fun) do
    cond do
      not names_a_schema? -> acc
      replaces_all?(args) -> maybe_offender(acc, true, path, meta, "#{fun} replace_all")
      fun in @bulk_writes -> maybe_offender(acc, mentions_frozen?(args), path, meta, fun)
      true -> acc
    end
  end

  defp replaces_all?(args) do
    found?(args, fn
      {:on_conflict, :replace_all} -> true
      {:on_conflict, {:replace_all_except, _columns}} -> true
      _other -> false
    end)
  end

  defp maybe_offender(acc, false, _path, _meta, _what), do: acc

  defp maybe_offender(acc, true, path, meta, what),
    do: ["#{path}:#{Keyword.get(meta, :line, "?")} #{what}" | acc]

  # An alias of one of the three schemas, or one of their table names (a
  # schemaless query writes the table as well).
  defp names_a_schema?(body) do
    found?(body, fn
      {:__aliases__, _, segments} -> List.last(segments) in @schemas
      table when is_binary(table) -> table in @tables
      _other -> false
    end)
  end

  defp mentions_frozen?(ast), do: found?(ast, &(&1 in @frozen))

  # SQL syntax, not prose.
  defp raw_sql_write?(string) do
    string =~
      ~r/\bUPDATE\s+(#{Enum.join(@tables, "|")})\s+SET\b[^;]*\b(currency_code|portfolio_id)\b/i
  end

  defp strings(ast) do
    {_ast, strings} =
      Macro.prewalk(ast, [], fn
        binary, acc when is_binary(binary) -> {binary, [binary | acc]}
        node, acc -> {node, acc}
      end)

    strings
  end

  # --- the schema side ---------------------------------------------------------

  defp writes_frozen?(body, fields, attributes) do
    found?(body, fn
      {:cast, _, [_data, _params, cast_fields | _]} ->
        names_field?(cast_fields, fields, attributes)

      {:cast, _, [_params, cast_fields | _]} ->
        names_field?(cast_fields, fields, attributes)

      {fun, _, args} when fun in @changeset_writes and is_list(args) ->
        names_field?(args, fields, attributes)

      _other ->
        false
    end)
  end

  defp runs_name_guard?(body) do
    found?(body, fn
      {{:., _, [{:__aliases__, _, [:AccountNames]}, :validate]}, _, _args} -> true
      _other -> false
    end)
  end

  # --- the name guard's writers (ADR-0050 §4) --------------------------------------

  defp former_name_writers_in(path), do: former_name_writers_in_source(path, File.read!(path))

  defp former_name_writers_in_source(path, source) do
    for {name, _head, body} <- source |> Code.string_to_quoted!() |> defs_with_heads(),
        writes_former_names?(body),
        uniq: true,
        do: {path, name}
  end

  defp writes_former_names?(body) do
    found?(body, fn
      {fun, _, args} when fun in @field_writes and is_list(args) ->
        mentions?(args, :former_names)

      {{:., _, [_mod, fun]}, _, args} when fun in @field_writes ->
        mentions?(args, :former_names)

      {{:., _, [{:__aliases__, _, segments}, :former_names_changeset]}, _, _args} ->
        List.last(segments) in @account_schemas

      _other ->
        false
    end)
  end

  defp name_side_writes_in(path), do: name_side_writes_in_source(path, File.read!(path))

  # A former-names write by a function not classified in @former_name_writers;
  # a change, cast or bulk write naming `name` in a function that names an
  # account schema or table (anywhere else `name` is some other record's); or
  # a raw SQL UPDATE of an account table setting either.
  defp name_side_writes_in_source(path, source) do
    ast = Code.string_to_quoted!(source)

    in_defs =
      Enum.flat_map(defs_with_heads(ast), fn {name, head, body} ->
        former =
          if writes_former_names?(body) and
               not Map.has_key?(@former_name_writers, {path, name}),
             do: ["#{path}:#{line_of(head)} former_names"],
             else: []

        names =
          if names_an_account?({head, body}),
            do: name_writes(body, path),
            else: []

        former ++ names
      end)

    raw_sql =
      for string <- strings(ast),
          string =~
            ~r/\bUPDATE\s+(#{Enum.join(@account_tables, "|")})\s+SET\b[^;]*\b(name|former_names)\b/i,
          do: "#{path}:? raw_sql"

    in_defs ++ raw_sql
  end

  defp name_writes(body, path) do
    {_ast, offenders} =
      Macro.prewalk(body, [], fn
        {fun, meta, args} = node, acc
        when fun in @field_writes and is_list(args) ->
          {node, maybe_offender(acc, mentions?(args, :name), path, meta, "#{fun} name")}

        {{:., _, [_mod, fun]}, meta, args} = node, acc
        when fun in @field_writes ->
          {node, maybe_offender(acc, mentions?(args, :name), path, meta, "#{fun} name")}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(offenders)
  end

  defp names_an_account?(ast) do
    found?(ast, fn
      {:__aliases__, _, segments} -> List.last(segments) in @account_schemas
      table when is_binary(table) -> table in @account_tables
      _other -> false
    end)
  end

  # The field as an atom in the call — a keyword key or a field list — never
  # a variable that happens to share its name (`name` in AccountNames).
  defp mentions?(ast, field) do
    ast
    |> Macro.prewalk(fn
      {var, _meta, context} when is_atom(var) and is_atom(context) -> nil
      node -> node
    end)
    |> found?(&(&1 == field))
  end

  defp line_of({:when, meta, _args}), do: Keyword.get(meta, :line, "?")
  defp line_of({_name, meta, _args}), do: Keyword.get(meta, :line, "?")

  defp runs_freeze?(body) do
    found?(body, fn
      {{:., _, [{:__aliases__, _, [:Freeze]}, :validate]}, _, _args} -> true
      _other -> false
    end)
  end

  defp names_field?(ast, fields, attributes) do
    found?(ast, fn
      atom when is_atom(atom) ->
        Atom.to_string(atom) in fields

      {:sigil_w, _, [{:<<>>, _, [words]}, _modifiers]} ->
        Enum.any?(String.split(words), &(&1 in fields))

      {:@, _, [{name, _, context}]} when is_atom(context) ->
        attribute_names?(attributes, name, fields)

      _other ->
        false
    end)
  end

  defp attribute_names?(attributes, name, fields) do
    case Map.fetch(attributes, name) do
      {:ok, value} -> names_field?(value, fields, %{})
      :error -> false
    end
  end

  # --- AST helpers ---------------------------------------------------------------

  defp module_attributes(ast) do
    {_ast, attributes} =
      Macro.prewalk(ast, %{}, fn
        {:@, _, [{name, _, [value]}]} = node, acc when is_atom(name) ->
          {node, Map.put(acc, name, value)}

        node, acc ->
          {node, acc}
      end)

    attributes
  end

  defp defs(ast) do
    {_ast, defs} =
      Macro.prewalk(ast, [], fn
        {kind, _meta, [head, body]} = node, acc when kind in [:def, :defp] ->
          {node, [{def_name(head), body} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(defs)
  end

  defp defs_with_heads(ast) do
    {_ast, defs} =
      Macro.prewalk(ast, [], fn
        {kind, _meta, [head, body]} = node, acc when kind in [:def, :defp] ->
          {node, [{def_name(head), head, body} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(defs)
  end

  defp def_name({:when, _meta, [head | _guards]}), do: def_name(head)
  defp def_name({name, _meta, _args}) when is_atom(name), do: name

  defp found?(ast, predicate) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        node, true -> {node, true}
        node, false -> {node, predicate.(node)}
      end)

    found
  end
end
