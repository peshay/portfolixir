defmodule Portfolixir.Invariants.CascadeRemovalsTest do
  # E25 S6 (#891), F43 (risk-tier: audit, ADR-0036). A database cascade
  # removes rows the journal never sees: the entry records the parent only.
  # This test reads the real foreign keys from pg_constraint, so a cascading
  # key added later cannot slip past `Portfolixir.Journal.Cascades` — it
  # fails the build until someone names the journaled delete that removes its
  # rows per row first.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Journal.Cascades

  # User story:
  # As the maintainer of the audit journal,
  # I want every foreign key that deletes or rewrites rows of a journal-armed
  # table on its own to be listed with the context delete that removes those
  # rows per row, journaled, before the parent goes,
  # so that no delete path records only the parent while the database removes
  # the children silently.
  #
  # Acceptance criteria:
  # - The cascading foreign keys (ON DELETE CASCADE, SET NULL or SET
  #   DEFAULT) are enumerated from pg_constraint, never from a hand-kept list.
  # - Each one into an armed table is listed exactly once in
  #   Portfolixir.Journal.Cascades; a missing one fails, naming it.
  test "every cascading foreign key into an armed table is listed as removed per-row by its context" do
    armed = armed_tables()

    missing =
      for {name, %{table: table}} <- cascading_foreign_keys(),
          MapSet.member?(armed, table),
          name not in declared_names(),
          do: name

    assert Enum.sort(missing) == [],
           "cascading foreign keys into journal-armed tables without a per-row journaled " <>
             "removal in Portfolixir.Journal.Cascades (E25 S6, F43):\n" <>
             Enum.join(Enum.sort(missing), "\n")
  end

  # The scope tables (ADR-0018 §5) are unarmed, but their writers journal:
  # a cascade into them is held to the same list.
  test "every other cascading foreign key is listed too, and nothing is listed twice or stale" do
    database = cascading_foreign_keys()
    names = declared_names()

    missing = database |> Map.keys() |> Enum.reject(&(&1 in names)) |> Enum.sort()
    assert missing == [], "cascading foreign keys not listed:\n" <> Enum.join(missing, "\n")

    twice = for {name, count} <- Enum.frequencies(names), count > 1, do: name
    assert twice == [], "listed more than once:\n" <> Enum.join(twice, "\n")

    stale = names |> Enum.reject(&Map.has_key?(database, &1)) |> Enum.sort()

    assert stale == [],
           "listed cascading foreign keys the database no longer has (or that no longer " <>
             "cascade):\n" <> Enum.join(stale, "\n")

    reshaped =
      for entry <- Cascades.cascades(),
          %{} = actual <- [Map.get(database, entry.constraint)],
          {entry.table, entry.columns, entry.references} !=
            {actual.table, actual.columns, actual.references},
          do: entry.constraint

    assert reshaped == [], "listed with another shape:\n" <> Enum.join(reshaped, "\n")
  end

  test "every listed removal names a delete that exists, or a parent no path deletes" do
    offenders =
      for %{removed_by: removed_by, constraint: name, basis: basis} <- Cascades.cascades(),
          not valid_removal?(removed_by) or not (is_binary(basis) and basis != ""),
          do: "#{name}: #{inspect(removed_by)}"

    assert offenders == [], "invalid removals:\n" <> Enum.join(offenders, "\n")

    # The one parent listed as never deleted must stay so: a delete path for
    # it would have to remove its children per row first, and be listed.
    for %{removed_by: :no_delete_path, references: "portfolios"} <- Cascades.cascades() do
      Code.ensure_loaded!(Portfolixir.Portfolios)

      for arity <- 0..4,
          do: refute(function_exported?(Portfolixir.Portfolios, :delete_portfolio, arity))

      refute Enum.any?(Path.wildcard("lib/**/*.ex"), &(File.read!(&1) =~ "delete_portfolio")),
             "a portfolio delete path exists — list what it removes per row first"
    end
  end

  # The enumeration must not pass vacuously.
  test "the pg_constraint enumeration sees cascading and set-null keys" do
    database = cascading_foreign_keys()

    assert %{on_delete: "c", table: "portfolio_targets"} =
             Map.fetch!(database, "portfolio_targets_plan_id_fkey")

    assert %{on_delete: "n"} = Map.fetch!(database, "buckets_source_portfolio_id_fkey")
    refute Map.has_key?(database, "transactions_security_id_fkey")
  end

  defp valid_removal?(:no_delete_path), do: true

  defp valid_removal?({module, function, arity}) do
    Code.ensure_loaded?(module) and function_exported?(module, function, arity)
  end

  defp valid_removal?(_other), do: false

  defp declared_names, do: Enum.map(Cascades.cascades(), & &1.constraint)

  # 'c' CASCADE, 'n' SET NULL, 'd' SET DEFAULT: the actions that change or
  # remove a referencing row on their own.
  defp cascading_foreign_keys do
    %{rows: rows} =
      Repo.query!("""
      SELECT c.conname,
             cl.relname,
             ref.relname,
             ARRAY(
               SELECT a.attname::text
               FROM unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
               JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
               ORDER BY k.ord
             ),
             c.confdeltype::text
      FROM pg_constraint c
      JOIN pg_class cl ON cl.oid = c.conrelid
      JOIN pg_class ref ON ref.oid = c.confrelid
      JOIN pg_namespace n ON n.oid = cl.relnamespace
      WHERE c.contype = 'f'
        AND n.nspname = 'public'
        AND c.confdeltype IN ('c', 'n', 'd')
      """)

    Map.new(rows, fn [name, table, references, columns, on_delete] ->
      {name, %{table: table, references: references, columns: columns, on_delete: on_delete}}
    end)
  end

  defp armed_tables do
    %{rows: rows} =
      Repo.query!("""
      SELECT c.relname
      FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_proc p ON p.oid = t.tgfoid
      WHERE p.proname = 'portfolixir_require_journal_actor'
        AND NOT t.tgisinternal
      """)

    MapSet.new(rows, fn [name] -> name end)
  end
end
