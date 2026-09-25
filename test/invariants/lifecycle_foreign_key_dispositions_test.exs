defmodule Portfolixir.Invariants.LifecycleForeignKeyDispositionsTest do
  # ADR-0050 §14 and §16 invariant 16 (risk-tier: audit, ADR-0036). The
  # lifecycle writers — the merges of ADR-0050 §7 and §9 and the hardened
  # deletes of §11 — act on every row that references a security, a cash
  # account or a depot. This test reads the real foreign keys from the
  # database, so a table added later cannot slip past the map: it would
  # otherwise break every merge (RESTRICT) or lose data silently (CASCADE).
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Lifecycle.ForeignKeys

  @lifecycle_tables ~w(securities cash_accounts securities_accounts)

  # User story:
  # As the maintainer of the lifecycle merges and deletes,
  # I want every foreign key that points at a security, a cash account or a
  # depot to carry a declared disposition for a merge and one for a delete,
  # so that no reference is ever handled by accident — a new one fails the
  # build until someone decides what a merge and a delete do with it.
  #
  # Acceptance criteria:
  # - The foreign keys are enumerated from pg_constraint, composite ones
  #   included, never from a hand-kept list.
  # - Each appears in the lifecycle module's disposition map exactly once,
  #   with one merge and one delete disposition from the closed vocabularies.
  # - A foreign key missing from the map, listed twice, declared but gone, or
  #   declared with another shape fails, and the failure names it.
  # - A delete disposition of `:restrict` sits on a foreign key the database
  #   itself refuses a delete through, so the 409 has a backstop.
  test "every foreign key onto the lifecycle tables has one merge and one delete disposition" do
    database = database_foreign_keys()
    declared = ForeignKeys.dispositions()
    declared_names = Enum.map(declared, & &1.constraint)

    missing = database |> Map.keys() |> Enum.reject(&(&1 in declared_names)) |> Enum.sort()

    assert missing == [],
           "foreign keys onto #{Enum.join(@lifecycle_tables, ", ")} without a declared " <>
             "merge and delete disposition in Portfolixir.Lifecycle.ForeignKeys " <>
             "(ADR-0050 §14):\n" <> Enum.join(missing, "\n")

    twice =
      declared_names
      |> Enum.frequencies()
      |> Enum.filter(fn {_name, count} -> count > 1 end)
      |> Enum.map(fn {name, _count} -> name end)
      |> Enum.sort()

    assert twice == [], "foreign keys listed more than once:\n" <> Enum.join(twice, "\n")

    stale = declared_names |> Enum.reject(&Map.has_key?(database, &1)) |> Enum.sort()

    assert stale == [],
           "declared foreign keys the database no longer has:\n" <> Enum.join(stale, "\n")

    reshaped =
      for entry <- declared,
          %{} = actual <- [Map.get(database, entry.constraint)],
          {entry.table, entry.columns, entry.references} !=
            {actual.table, actual.columns, actual.references} do
        "#{entry.constraint}: declared #{shape(entry)}, database has #{shape(actual)}"
      end

    assert reshaped == [],
           "declared foreign keys with another shape:\n" <> Enum.join(reshaped, "\n")
  end

  test "every disposition comes from the closed vocabularies" do
    offenders =
      for entry <- ForeignKeys.dispositions(),
          not (entry.merge in ForeignKeys.merge_dispositions() and
                 entry.delete in ForeignKeys.delete_dispositions() and
                 is_binary(entry.basis) and entry.basis != "") do
        "#{entry.constraint}: merge #{inspect(entry.merge)}, delete #{inspect(entry.delete)}, " <>
          "basis #{inspect(entry.basis)}"
      end

    assert offenders == [],
           "dispositions outside the closed vocabularies or without a basis:\n" <>
             Enum.join(offenders, "\n")
  end

  test "a :restrict delete disposition sits on a foreign key the database refuses through" do
    database = database_foreign_keys()

    # 'r' is RESTRICT, 'a' is NO ACTION: both refuse the delete of a still
    # referenced row. 'c' (CASCADE), 'n' (SET NULL) and 'd' (SET DEFAULT)
    # would let the database remove or rewrite the reference behind the
    # refusal the lifecycle code answers.
    offenders =
      for %{delete: :restrict} = entry <- ForeignKeys.dispositions(),
          %{on_delete: action} <- [Map.get(database, entry.constraint)],
          action not in ["r", "a"] do
        "#{entry.constraint}: ON DELETE action #{inspect(action)}"
      end

    assert offenders == [],
           "a :restrict delete disposition over a foreign key the database does not " <>
             "refuse through:\n" <> Enum.join(offenders, "\n")
  end

  # User story (ADR-0050 §11, §16 invariant 11):
  # As the maintainer of the audit trail,
  # I want no foreign key onto a security, a cash account or a depot to
  # remove or rewrite its referencing rows when that row is deleted,
  # so that no lifecycle path removes a row by cascade — a membership is
  # removed by its journaled writer first, or the database refuses the delete.
  #
  # Acceptance criteria:
  # - Every such foreign key, a :remove_journaled one included, is RESTRICT or
  #   NO ACTION; CASCADE, SET NULL and SET DEFAULT fail, naming the key.
  test "no foreign key onto the lifecycle tables removes a row by cascade" do
    offenders =
      for {name, %{on_delete: action}} <- database_foreign_keys(),
          action not in ["r", "a"] do
        "#{name}: ON DELETE action #{inspect(action)}"
      end
      |> Enum.sort()

    assert offenders == [],
           "foreign keys onto the lifecycle tables that act on their own when the row is " <>
             "deleted (ADR-0050 §11):\n" <> Enum.join(offenders, "\n")
  end

  # The enumeration must not pass vacuously: it sees single-column and
  # composite keys onto each of the three tables.
  test "the pg_constraint enumeration sees composite keys onto all three tables" do
    database = database_foreign_keys()

    for table <- @lifecycle_tables do
      assert Enum.any?(database, fn {_name, fk} -> fk.references == table end),
             "no foreign key onto #{table} found — is the enumeration broken?"
    end

    assert %{columns: ["cash_account_id", "portfolio_id"]} =
             Map.fetch!(database, "transactions_cash_account_portfolio_fkey")

    assert %{columns: ["securities_account_id", "portfolio_id"]} =
             Map.fetch!(database, "transactions_securities_account_portfolio_fkey")
  end

  defp database_foreign_keys do
    %{rows: rows} =
      Repo.query!(
        """
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
        JOIN pg_namespace n ON n.oid = ref.relnamespace
        WHERE c.contype = 'f'
          AND n.nspname = 'public'
          AND ref.relname = ANY($1)
        """,
        [@lifecycle_tables]
      )

    Map.new(rows, fn [name, table, references, columns, on_delete] ->
      {name, %{table: table, references: references, columns: columns, on_delete: on_delete}}
    end)
  end

  defp shape(fk), do: "#{fk.table}(#{Enum.join(fk.columns, ", ")}) -> #{fk.references}"
end
