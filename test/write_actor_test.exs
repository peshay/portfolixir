defmodule Portfolixir.WriteActorTest do
  use Portfolixir.DataCase, async: true

  # User story:
  # As a maintainer rolling out the audit journal leaf-first,
  # I want a mechanical gate that fails when a public context write function
  # gains/keeps a Repo write without taking an `Actor` first argument, unless it
  # is explicitly grandfathered (a list that only shrinks),
  # so that no write path can bypass attribution as the refactor proceeds
  # (P2, ADR-0015, architecture amendment 1).
  #
  # Scope: the classifier inspects each context's PUBLIC API module. Writers in
  # internal sub-modules reached through the context API are backstopped at
  # runtime by the per-table guard trigger (see append_only_test.exs).

  @context_files %{
    Portfolixir.Catalog => "lib/portfolixir/catalog.ex",
    Portfolixir.Fx => "lib/portfolixir/fx.ex",
    Portfolixir.Ledger => "lib/portfolixir/ledger.ex",
    Portfolixir.Portfolios => "lib/portfolixir/portfolios.ex",
    Portfolixir.Classifications => "lib/portfolixir/classifications.ex",
    Portfolixir.Imports => "lib/portfolixir/imports.ex"
  }

  # Contexts whose actor-first refactor + table arming has landed (leaf-first:
  # Catalog/Fx first). When a context is converted it carries NO grandfathered
  # writers and its journaled tables are armed (amendment 1 coupling).
  @converted_contexts [Portfolixir.Catalog, Portfolixir.Fx]

  # Migration-only data backfills: arity locked by immutable migrations (which run
  # before the table is armed), so they cannot take an actor. Excluded by class,
  # not grandfathered.
  @migration_helpers MapSet.new([{Portfolixir.Catalog, :backfill_inferred_asset_classes, 0}])

  # Writers of allowlisted market-data tables (never journaled, ADR-0015).
  @allowlisted_writers MapSet.new([{Portfolixir.Fx, :upsert_many, 1}])

  # Pre-existing public context writers not yet actor-first (later leaf-first
  # slices: Portfolios/Classifications → Ledger → Imports). SHRINK-ONLY: a stale
  # entry (no longer a non-actor-first writer) fails this test, forcing removal as
  # each context is converted.
  @grandfathered MapSet.new([
                   {Portfolixir.Portfolios, :create_portfolio, 1},
                   {Portfolixir.Portfolios, :update_portfolio, 2},
                   {Portfolixir.Portfolios, :set_cash_target, 2},
                   {Portfolixir.Portfolios, :create_cash_account, 1},
                   {Portfolixir.Portfolios, :update_cash_account, 2},
                   {Portfolixir.Portfolios, :delete_cash_account, 1},
                   {Portfolixir.Portfolios, :create_securities_account, 1},
                   {Portfolixir.Portfolios, :delete_securities_account, 1},
                   {Portfolixir.Ledger, :create_transaction, 1},
                   {Portfolixir.Ledger, :update_transaction, 2},
                   {Portfolixir.Ledger, :delete_transaction, 1},
                   {Portfolixir.Ledger, :set_cash_balance, 2},
                   {Portfolixir.Classifications, :create_classification, 1},
                   {Portfolixir.Classifications, :update_classification, 2},
                   {Portfolixir.Classifications, :delete_classification, 1},
                   {Portfolixir.Classifications, :create_category, 1},
                   {Portfolixir.Classifications, :update_category, 2},
                   {Portfolixir.Classifications, :delete_category, 1},
                   {Portfolixir.Classifications, :recolor_category, 2},
                   {Portfolixir.Classifications, :assign_security, 3},
                   {Portfolixir.Classifications, :assign_securities, 3},
                   {Portfolixir.Classifications, :unassign_security, 2},
                   {Portfolixir.Classifications, :unassign_securities, 2},
                   {Portfolixir.Classifications, :ensure_builtins, 0},
                   {Portfolixir.Classifications, :list_trees, 0},
                   {Portfolixir.Classifications, :security_category_map, 1}
                 ])

  # The only journaled tables currently guard-armed. Grows as contexts convert.
  @armed_tables MapSet.new(["securities"])

  # `Repo.transaction` is deliberately NOT a write marker: a read-only
  # transaction is not a write. Writing transactions are detected through the
  # `Multi.*` / `Repo.*` write calls they contain.
  @repo_writes ~w(insert insert! update update! delete delete! insert_all update_all
                  delete_all insert_or_update insert_or_update!)a
  @multi_writes ~w(insert update delete insert_all update_all delete_all insert_or_update)a

  test "every public context writer is actor-first, excluded, or grandfathered" do
    violations =
      for {module, _file} <- @context_files,
          {name, arity, actor_first?} <- writers(module),
          not actor_first?,
          not excluded?(module, name, arity),
          not MapSet.member?(@grandfathered, {module, name, arity}) do
        {module, name, arity}
      end

    assert violations == [],
           "public context writers missing an Actor first argument (P2/FR-28). " <>
             "Make them actor-first or grandfather them deliberately:\n" <>
             Enum.map_join(violations, "\n", &inspect/1)
  end

  test "no grandfather entry is stale (the list only shrinks)" do
    current = current_non_actor_writers()

    stale =
      for entry <- @grandfathered, not MapSet.member?(current, entry), do: entry

    assert stale == [],
           "grandfather entries no longer match a non-actor-first writer — remove them:\n" <>
             Enum.map_join(stale, "\n", &inspect/1)
  end

  test "converted contexts carry no grandfathered writers (armed ⟺ empty)" do
    leftover =
      for {module, _, _} = entry <- @grandfathered, module in @converted_contexts, do: entry

    assert leftover == [],
           "a converted context still has grandfathered writers:\n" <>
             Enum.map_join(leftover, "\n", &inspect/1)
  end

  test "only converted contexts' journaled tables are guard-armed" do
    assert armed_tables_in_db() == @armed_tables
  end

  # -- AST classifier --------------------------------------------------------

  defp excluded?(module, name, arity) do
    key = {module, name, arity}
    MapSet.member?(@migration_helpers, key) or MapSet.member?(@allowlisted_writers, key)
  end

  defp current_non_actor_writers do
    for {module, _file} <- @context_files,
        {name, arity, actor_first?} <- writers(module),
        not actor_first?,
        not excluded?(module, name, arity),
        into: MapSet.new() do
      {module, name, arity}
    end
  end

  # Returns [{name, arity, actor_first?}] for every public function of `module`
  # that transitively reaches a Repo/Multi write.
  defp writers(module) do
    file = Map.fetch!(@context_files, module)
    clauses = file |> File.read!() |> Code.string_to_quoted!() |> collect_defs()
    defined_names = clauses |> Enum.map(& &1.name) |> MapSet.new()

    direct =
      clauses
      |> Enum.group_by(& &1.name)
      |> Map.new(fn {name, cls} -> {name, Enum.any?(cls, &has_write_call?(&1.body))} end)

    local_calls =
      clauses
      |> Enum.group_by(& &1.name)
      |> Map.new(fn {name, cls} ->
        calls = cls |> Enum.flat_map(&collect_local_calls(&1.body, defined_names)) |> MapSet.new()
        {name, calls}
      end)

    writer_names = fixpoint(MapSet.new(), direct, local_calls)

    clauses
    |> Enum.filter(&(&1.kind == :def and MapSet.member?(writer_names, &1.name)))
    |> Enum.group_by(&{&1.name, &1.arity})
    |> Enum.map(fn {{name, arity}, cls} ->
      {name, arity, Enum.all?(cls, &actor_first?(&1.args))}
    end)
  end

  defp fixpoint(acc, direct, local_calls) do
    next =
      Enum.reduce(direct, acc, fn {name, writes?}, set ->
        if writes? or reaches_writer?(local_calls[name] || MapSet.new(), set) do
          MapSet.put(set, name)
        else
          set
        end
      end)

    if MapSet.equal?(next, acc), do: next, else: fixpoint(next, direct, local_calls)
  end

  defp reaches_writer?(calls, writers), do: Enum.any?(calls, &MapSet.member?(writers, &1))

  defp collect_defs(ast) do
    {_, defs} =
      Macro.prewalk(ast, [], fn
        {kind, _meta, [head | rest]} = node, acc when kind in [:def, :defp] ->
          {name, args} = head_name_args(head)
          body = rest |> List.first() |> body_of()
          {node, [%{kind: kind, name: name, arity: length(args), args: args, body: body} | acc]}

        node, acc ->
          {node, acc}
      end)

    defs
  end

  defp head_name_args({:when, _, [call, _guard]}), do: head_name_args(call)
  defp head_name_args({name, _, args}) when is_atom(name) and is_list(args), do: {name, args}
  defp head_name_args({name, _, nil}) when is_atom(name), do: {name, []}

  defp body_of(kw) when is_list(kw), do: Keyword.get(kw, :do)
  defp body_of(_), do: nil

  defp has_write_call?(nil), do: false

  defp has_write_call?(body) do
    {_, found} =
      Macro.prewalk(body, false, fn
        {{:., _, [{:__aliases__, _, segs}, fun]}, _, _args} = node, _acc when is_atom(fun) ->
          {node, write_call?(List.last(segs), fun)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp write_call?(:Repo, fun), do: fun in @repo_writes
  defp write_call?(:Multi, fun), do: fun in @multi_writes
  defp write_call?(_mod, _fun), do: false

  defp collect_local_calls(nil, _defined), do: []

  defp collect_local_calls(body, defined) do
    {_, calls} =
      Macro.prewalk(body, [], fn
        {name, _meta, args} = node, acc when is_atom(name) and is_list(args) ->
          if MapSet.member?(defined, name), do: {node, [name | acc]}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    calls
  end

  defp actor_first?([]), do: false

  defp actor_first?([first | _]) do
    str = Macro.to_string(first)
    String.contains?(str, "Actor") or str in ["actor", "_actor"]
  end

  defp armed_tables_in_db do
    %{rows: rows} =
      Repo.query!("""
      SELECT c.relname
      FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_proc p ON p.oid = t.tgfoid
      WHERE p.proname = 'portfolixir_require_journal_actor'
        AND NOT t.tgisinternal
      """)

    rows |> Enum.map(fn [name] -> name end) |> MapSet.new()
  end
end
