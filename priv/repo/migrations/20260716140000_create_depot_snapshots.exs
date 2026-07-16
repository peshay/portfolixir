defmodule Portfolixir.Repo.Migrations.CreateDepotSnapshots do
  @moduledoc """
  Depot snapshots (ADR-0027): a snapshot is a pure ledger **marker** — a name,
  a view scope (`view_id` NULL = the "everything" scope) and an as-of date.

  Deliberately NO financial data is stored: the holdings and cost basis a
  snapshot represents are derived on demand by projecting the transaction
  ledger up to the as-of date (ADR-0004), so a snapshot can never drift from
  the ledger. Deleting a view removes its snapshots (the marker's scope is
  gone); "everything" snapshots are untouched.
  """
  use Ecto.Migration

  def change do
    create table(:depot_snapshots) do
      add(:name, :string, null: false)
      add(:as_of, :date, null: false)
      add(:view_id, references(:views, on_delete: :delete_all))

      timestamps()
    end

    execute(
      """
      CREATE UNIQUE INDEX depot_snapshots_name_per_scope_index
        ON depot_snapshots (view_id, name)
        NULLS NOT DISTINCT;
      """,
      "DROP INDEX depot_snapshots_name_per_scope_index;"
    )

    create(index(:depot_snapshots, [:view_id]))
  end
end
