defmodule Portfolixir.Repo.Migrations.CreateDashboards do
  @moduledoc """
  ADR-0062 §2 (Sprint 31, D1): `dashboards`, a stored arrangement of
  widgets — its `name`, its `position` in the menu, its `layout` (a JSON
  array of items) and the `lock_version` a replace carries. A dashboard
  holds no figure: no foreign key, no money, nothing the ledger reads.

  **Bounds:** the name 1 to 60 characters (trimmed, one line, in the
  context, `Portfolixir.Dashboards.Dashboard`); the position and the
  lock_version 1 or more; the layout a JSON array of at most 40 items.
  What an item may hold is the context's to check
  (`Portfolixir.Dashboards.Layout`), since it reads the widget registry
  and the views; the table bounds its size. At most 50 dashboards is the
  context's too, under a lock, since no row constraint can count rows.

  **The journal:** every write is journaled under its actor, and the table
  is armed with the journal-actor guard at creation.
  """
  use Ecto.Migration

  def up do
    create table(:dashboards) do
      add(:name, :string, size: 60, null: false)
      add(:position, :integer, null: false)
      add(:layout, :jsonb, null: false, default: fragment("'[]'::jsonb"))
      add(:lock_version, :integer, null: false, default: 1)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:dashboards, [:position, :id]))

    check(:name, "char_length(name) BETWEEN 1 AND 60")
    check(:position, "position >= 1")
    check(:lock_version, "lock_version >= 1")

    check(
      :layout,
      "jsonb_typeof(layout) = 'array' AND jsonb_array_length(layout) <= 40"
    )

    execute("""
    CREATE TRIGGER dashboards_require_journal_actor
      BEFORE INSERT OR UPDATE OR DELETE ON dashboards
      FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS dashboards_require_journal_actor ON dashboards")
    drop(table(:dashboards))
  end

  defp check(name, expression) do
    create(constraint(:dashboards, :"dashboards_#{name}_check", check: expression))
  end
end
