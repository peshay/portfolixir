defmodule Portfolixir.WriteActorTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Journal.Allowlist

  # User story:
  # As a maintainer rolling out the audit journal leaf-first,
  # I want a mechanical gate that fails when a public context write function
  # gains/keeps a Repo write without taking an `Actor` first argument, unless it
  # is explicitly grandfathered (a list that only shrinks),
  # so that no write path can bypass attribution as the refactor proceeds
  # (P2, ADR-0017, architecture amendment 1).
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
    Portfolixir.Imports => "lib/portfolixir/imports.ex",
    Portfolixir.Buckets => "lib/portfolixir/buckets.ex",
    Portfolixir.Tax => "lib/portfolixir/tax.ex",
    Portfolixir.Knowledge => "lib/portfolixir/knowledge.ex",
    Portfolixir.Lifecycle => "lib/portfolixir/lifecycle.ex"
  }

  # Contexts whose actor-first refactor + table arming has landed (leaf-first:
  # Catalog/Fx first). When a context is converted it carries NO grandfathered
  # writers and its journaled tables are armed (amendment 1 coupling).
  @converted_contexts [
    Portfolixir.Catalog,
    Portfolixir.Fx,
    Portfolixir.Portfolios,
    Portfolixir.Ledger,
    Portfolixir.Classifications,
    Portfolixir.Tax,
    Portfolixir.Knowledge,
    # ADR-0050: born actor-first, its two tables armed at creation.
    Portfolixir.Lifecycle
  ]

  # Migration-only data backfills: arity locked by immutable migrations (which run
  # before the table is armed), so they cannot take an actor. Excluded by class,
  # not grandfathered.
  @migration_helpers MapSet.new([{Portfolixir.Catalog, :backfill_inferred_asset_classes, 0}])

  # Writers of allowlisted market-data tables (never journaled, ADR-0017).
  @allowlisted_writers MapSet.new([{Portfolixir.Fx, :upsert_many, 1}])

  # System-job writers (#1269): writes no person or token asks for — the boot
  # seed of the built-in trees and the two background logo jobs. Each journals
  # under a fixed `Actor.system_job/1` inside its own body, because a job has
  # no requester whose actor it could take. Excluded by class, not
  # grandfathered, and held to that class below: no web-layer module (the
  # pages, the JSON API the MCP companion calls) may call one, or a request
  # would write under the job's identity instead of its own, and each entry
  # must still reach an `Actor.system_job/1` call and still be a writer.
  @system_job_writers %{
    {Portfolixir.Catalog, :put_logo_attributes, 2} =>
      "the background logo discovery's write, journaled as system_job logo",
    {Portfolixir.Catalog, :put_logo_file_mark, 3} =>
      "the logo reconciliation's compare-and-set, journaled as system_job logo_reconcile",
    {Portfolixir.Classifications, :ensure_builtins, 0} =>
      "the idempotent seed of the built-in trees, journaled as system_job builtin_seed",
    {Portfolixir.Classifications, :seed_builtins_on_boot, 0} =>
      "the application start's config-gated call of ensure_builtins/0"
  }

  # The classifier must not pass vacuously (#1269): it once kept only the
  # last call it visited in a body and so read 7 writers instead of 62. A
  # count below this floor means it stopped seeing writers; raise the floor
  # when writers are added, never lower it to make a red run pass.
  @writer_floor 62

  # Pre-existing public context writers not yet actor-first (later leaf-first
  # slices: Portfolios/Classifications → Ledger → Imports). SHRINK-ONLY: a stale
  # entry (no longer a non-actor-first writer) fails this test, forcing removal as
  # each context is converted.
  # The leaf-first ADR-0017 rollout is COMPLETE: every context that writes
  # financial data (Catalog/Fx, Portfolios, Ledger, Classifications) is converted
  # — its public writers are actor-first (or, for built-in tree seeding, journal
  # internally under a fixed `system_job` actor) and its tables are guard-armed.
  # So the grandfather list of "not-yet-actor-first writers" is now empty; a new
  # write path that forgets the actor is rejected by the per-table guard trigger
  # at runtime and, where AST-detectable, by this gate. The list stays here
  # (empty) so a future context's transitional writers can be parked deliberately.
  @grandfathered MapSet.new([])

  # Journaled tables currently guard-armed. Grows as contexts convert. `buckets`
  # is the root tag table of the born-actor-first Buckets context (ADR-0018). Its
  # assignment join tables stay un-armed as ADR-0018 §5 scope tables
  # (`Portfolixir.Journal.Allowlist.unarmed_scope_tables/0`): their writers journal
  # one aggregate entry per account or position. Since ADR-0050 §11 their foreign
  # keys onto accounts, depots and securities RESTRICT instead of cascading, so
  # the database refuses to delete a row that still carries a membership — but
  # with no guard trigger, that a membership removal is journaled rests on the
  # Buckets context writers (ADR-0050 §13), not on the database.
  @armed_tables MapSet.new([
                  "securities",
                  "security_identifier_aliases",
                  "buckets",
                  "portfolios",
                  "cash_accounts",
                  "securities_accounts",
                  "transactions",
                  "classifications",
                  "classification_categories",
                  "security_category_assignments",
                  "portfolio_target_plans",
                  "portfolio_targets",
                  "tax_parameters",
                  "tax_profiles",
                  "allowance_orders",
                  "tax_statement_snapshots",
                  # ADR-0044 §5: the research log is armed in the migration
                  # that creates it (a signed clause), so the agent's write
                  # path adds nothing to the rollout debt.
                  "security_notes",
                  # ADR-0048 §4: security events, armed in their first
                  # migration for the same reason — an agent writes these
                  # rows. Unlike the research log this table is MUTABLE, so
                  # the guard covers UPDATE and DELETE in earnest rather than
                  # as a precaution: the journal IS the change history.
                  "security_events",
                  # ADR-0049 §4: policy rules and their versions, armed in
                  # their first migration — an agent writes these rows, and
                  # the journal records WHO changed a standard while the
                  # versions record WHAT it was.
                  "policy_rules",
                  "policy_rule_versions",
                  # ADR-0050 §3, §12: the merge records and the retired import
                  # hashes, append-only and armed in the migrations that create
                  # them — the journal records who merged and who retired.
                  "merge_records",
                  "retired_import_hashes"
                ])

  # Derived-value tables (ADR-0039): materializations of ledger-derived reads,
  # rebuildable at any time. A derived-value write is NOT a financial write and
  # is deliberately neither journaled nor guard-armed — this list makes that
  # table class EXPLICIT, because implicit non-coverage is how the journal gate
  # would be bypassed rather than weakened (ADR-0039 §5, sign-off condition).
  @derived_tables MapSet.new(["derived_values", "derived_data_version_events"])

  # The two tables outside every class: Ecto's migration ledger and the
  # journal itself, which the guard exists to feed.
  @bookkeeping_tables MapSet.new(["schema_migrations", "audit_journal"])

  # `Repo.transaction` is deliberately NOT a write marker: a read-only
  # transaction is not a write. Writing transactions are detected through the
  # `Multi.*` / `Repo.*` write calls they contain.
  @repo_writes ~w(insert insert! update update! delete delete! insert_all update_all
                  delete_all insert_or_update insert_or_update!)a
  @multi_writes ~w(insert update delete insert_all update_all delete_all insert_or_update)a

  # Writers named one by one, because the classifier below follows only
  # same-file calls and does not see a write made through another module (a
  # store, a sibling context). Each was found writing under a fixed actor
  # (security review 2026-10-12, decision T-16): every clause takes the
  # actor first.
  @pinned_actor_first %{
    {Portfolixir.Catalog, :set_logo_override} => "lib/portfolixir/catalog.ex",
    {Portfolixir.Catalog, :remove_logo} => "lib/portfolixir/catalog.ex",
    {Portfolixir.Catalog, :rediscover_logo} => "lib/portfolixir/catalog.ex",
    {Portfolixir.Classifications, :reclassify_securities} => "lib/portfolixir/classifications.ex",
    {Portfolixir.Classifications, :reset_asset_class} => "lib/portfolixir/classifications.ex",
    {Portfolixir.Settings, :set_default_view} => "lib/portfolixir/settings.ex",
    {Portfolixir.Catalog.LogoStore, :store_manual_bytes} =>
      "lib/portfolixir/catalog/logo_store.ex"
  }

  test "every pinned writer takes an Actor first in every clause" do
    violations =
      for {{module, name}, file} <- @pinned_actor_first,
          clauses = file |> File.read!() |> Code.string_to_quoted!() |> collect_defs(),
          named = Enum.filter(clauses, &(&1.kind == :def and &1.name == name)),
          named == [] or not Enum.all?(named, &actor_first?(&1.args)) do
        {module, name, Enum.map(named, & &1.arity)}
      end

    assert violations == [],
           "pinned writers missing (or not taking) an Actor first argument:\n" <>
             Enum.map_join(violations, "\n", &inspect/1)
  end

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

  test "the classifier reads at least the known number of public writers" do
    count = @context_files |> Map.keys() |> Enum.flat_map(&writers/1) |> length()

    assert count >= @writer_floor,
           "the classifier found #{count} public context writers, fewer than the " <>
             "#{@writer_floor} known — it stopped seeing writers (#1269)"
  end

  test "every system-job writer is still a writer that journals under a system job" do
    bad =
      for {{module, name, arity} = entry, _reason} <- @system_job_writers,
          not Enum.any?(writers(module), &match?({^name, ^arity, false}, &1)) or
            not reaches_system_job?(module, name),
          do: entry

    assert bad == [],
           "system-job entries that no longer write without an actor, or no longer " <>
             "reach Actor.system_job/1 — remove or fix them:\n" <>
             Enum.map_join(bad, "\n", &inspect/1)
  end

  test "no web-layer module calls a system-job writer" do
    names =
      MapSet.new(@system_job_writers, fn {{module, name, _}, _} -> {short(module), name} end)

    callers =
      for file <- Path.wildcard("lib/portfolixir_web/**/*.ex"),
          call <- remote_calls(file |> File.read!() |> Code.string_to_quoted!()),
          MapSet.member?(names, call),
          do: {file, call}

    assert callers == [],
           "a web-layer module calls a system-job writer, so a request would write " <>
             "under the job's identity — give the write path an actor:\n" <>
             Enum.map_join(callers, "\n", &inspect/1)
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

  test "derived-value tables exist and stay deliberately un-journaled (ADR-0039)" do
    existing = tables_in_db()

    for table <- @derived_tables do
      assert MapSet.member?(existing, table),
             "expected derived table #{table} to exist — did the ADR-0039 migration change?"
    end

    assert MapSet.disjoint?(@derived_tables, @armed_tables)

    assert MapSet.disjoint?(@derived_tables, armed_tables_in_db()),
           "a derived-value table gained a journal guard trigger — a materialization " <>
             "write is not a financial write (ADR-0039); arming it would make every " <>
             "read-path store fail for want of an actor"
  end

  # User story (E25 S6, F52):
  # As the maintainer of the audit journal,
  # I want every table in the database to sit in exactly one classification —
  # armed, unarmed scope, non-journaled market data or derived,
  # so that a table added without a decision on its journaling fails the
  # build by name instead of passing every guard-coverage test unnoticed.
  #
  # Acceptance criteria:
  # - The database's tables, minus the migration ledger and the journal, are
  #   the disjoint union of the four classification sets.
  # - A table in none of them is named; a table in two of them is named.
  test "every database table is classified exactly once" do
    gaps = classification_gaps(tables_in_db())

    assert gaps.unclassified == [],
           "tables in no journal classification (armed, unarmed scope, non-journaled " <>
             "or derived) — decide and list each one:\n" <> Enum.join(gaps.unclassified, "\n")

    assert gaps.overlapping == [],
           "tables in more than one journal classification:\n" <>
             Enum.join(gaps.overlapping, "\n")
  end

  # The classification must not pass vacuously: a table nobody listed is
  # named, and so is one listed twice.
  test "a table missing from every classification list is named" do
    gaps = classification_gaps(MapSet.put(tables_in_db(), "an_unclassified_table"))
    assert gaps.unclassified == ["an_unclassified_table"]

    assert classification_gaps(tables_in_db(), [MapSet.new(["securities"])]).overlapping ==
             ["securities"]
  end

  # User story (#1269):
  # As the maintainer of the audit journal,
  # I want the classifier to call a function a writer when ANY node of its
  # body is a Repo/Multi write, not only when the last node it visits is,
  # so that the gate checks every public writer instead of the few whose
  # final call happens to write.
  #
  # Acceptance criteria:
  # - A write followed by a non-write call (a return value, a broadcast) is
  #   still classified as a write, directly and through a local helper.
  # - A function with no write anywhere is not a writer.
  test "the classifier sees a write that is not the last call of a body" do
    source = """
    defmodule Synthetic do
      def write_then_ok(attrs) do
        Repo.insert!(attrs)
        :ok
      end

      def write_then_call(attrs) do
        {:ok, row} = Repo.update(attrs)
        Phoenix.PubSub.broadcast(:pubsub, "topic", row)
      end

      def multi_then_commit(attrs) do
        Multi.new() |> Multi.insert(:row, attrs) |> Repo.transaction()
      end

      def via_helper(attrs), do: helper(attrs) |> Enum.count()

      def reader(id), do: Repo.get(Thing, id)

      defp helper(attrs) do
        Repo.delete_all(attrs)
        Logger.info("deleted")
      end
    end
    """

    names = source |> writers_in() |> Enum.map(fn {name, _arity, _actor?} -> name end)

    assert Enum.sort(names) == [:multi_then_commit, :via_helper, :write_then_call, :write_then_ok]
  end

  defp classification_gaps(tables, extra_sets \\ []) do
    sets =
      [
        @armed_tables,
        MapSet.new(Allowlist.unarmed_scope_tables()),
        MapSet.new(Allowlist.non_journaled_tables()),
        @derived_tables
      ] ++ extra_sets

    counts = sets |> Enum.flat_map(&MapSet.to_list/1) |> Enum.frequencies()
    classified = MapSet.new(Map.keys(counts))

    %{
      unclassified:
        tables
        |> MapSet.difference(@bookkeeping_tables)
        |> MapSet.difference(classified)
        |> Enum.sort(),
      overlapping: for({table, count} <- counts, count > 1, do: table) |> Enum.sort()
    }
  end

  # -- AST classifier --------------------------------------------------------

  defp excluded?(module, name, arity) do
    key = {module, name, arity}

    MapSet.member?(@migration_helpers, key) or MapSet.member?(@allowlisted_writers, key) or
      Map.has_key?(@system_job_writers, key)
  end

  defp short(module), do: module |> Module.split() |> List.last() |> String.to_existing_atom()

  # {last alias segment, function} of every remote call in `ast`.
  defp remote_calls(ast) do
    {_, calls} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, segs}, fun]}, _, _args} = node, acc when is_atom(fun) ->
          {node, [{List.last(segs), fun} | acc]}

        node, acc ->
          {node, acc}
      end)

    calls
  end

  # Whether `name` in `module`'s file reaches an `Actor.system_job/1` call,
  # in its own body or through same-file helpers.
  defp reaches_system_job?(module, name) do
    clauses =
      @context_files
      |> Map.fetch!(module)
      |> File.read!()
      |> Code.string_to_quoted!()
      |> collect_defs()

    defined = clauses |> Enum.map(& &1.name) |> MapSet.new()
    by_name = Enum.group_by(clauses, & &1.name)
    reachable = reach(MapSet.new([name]), [name], by_name, defined)

    Enum.any?(clauses, fn clause ->
      MapSet.member?(reachable, clause.name) and
        {:Actor, :system_job} in remote_calls(clause.body)
    end)
  end

  defp reach(seen, [], _by_name, _defined), do: seen

  defp reach(seen, [name | rest], by_name, defined) do
    new =
      by_name
      |> Map.get(name, [])
      |> Enum.flat_map(&collect_local_calls(&1.body, defined))
      |> Enum.reject(&MapSet.member?(seen, &1))
      |> Enum.uniq()

    reach(Enum.into(new, seen), new ++ rest, by_name, defined)
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
  defp writers(module), do: @context_files |> Map.fetch!(module) |> File.read!() |> writers_in()

  defp writers_in(source) do
    clauses = source |> Code.string_to_quoted!() |> collect_defs()
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
        {{:., _, [{:__aliases__, _, segs}, fun]}, _, _args} = node, acc when is_atom(fun) ->
          {node, acc or write_call?(List.last(segs), fun)}

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

  defp tables_in_db do
    %{rows: rows} =
      Repo.query!("SELECT tablename FROM pg_tables WHERE schemaname = 'public'")

    rows |> Enum.map(fn [name] -> name end) |> MapSet.new()
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
