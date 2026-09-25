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
  #                    writes `former_names` alone, for the remembered remap
  #                    and the removal.
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
     "SecuritiesAccount.former_names_changeset"} => :former_names_only
  }

  @changeset_writes ~w(put_change force_change change)a
  @bulk_writes ~w(insert_all update_all)a

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
    end
    """

    assert [{"sample.ex", :a, "Security.changeset"}] =
             builder_calls_in_source("sample.ex", sample)

    assert [_change, _update_all, _raw_sql, _upsert] = side_writes_in_source("sample.ex", sample)
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
  # anywhere (the struct it changes cannot be told from the source); an
  # update_all or insert_all naming one (an upsert's on_conflict replace
  # included) in a function that names one of the three schemas; or a raw
  # SQL UPDATE of one of the three tables.
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

        {{:., _, [_mod, fun]}, meta, args} = node, acc when fun in @bulk_writes ->
          {node, maybe_offender(acc, names_a_schema? and mentions_frozen?(args), path, meta, fun)}

        {fun, meta, args} = node, acc when fun in @bulk_writes and is_list(args) ->
          {node, maybe_offender(acc, names_a_schema? and mentions_frozen?(args), path, meta, fun)}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(offenders)
  end

  defp maybe_offender(acc, false, _path, _meta, _what), do: acc

  defp maybe_offender(acc, true, path, meta, what),
    do: ["#{path}:#{Keyword.get(meta, :line, "?")} #{what}" | acc]

  defp names_a_schema?(body) do
    found?(body, fn
      {:__aliases__, _, segments} -> List.last(segments) in @schemas
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
