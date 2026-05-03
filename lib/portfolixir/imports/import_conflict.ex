defmodule Portfolixir.Imports.ImportConflict do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Imports.{ImportRun, ImportSource, RawImportItem}

  @statuses ["open", "resolved"]

  schema "import_conflicts" do
    field(:conflict_type, :string)
    field(:status, :string, default: "open")
    field(:summary, :string)
    field(:details, :map, default: %{})

    belongs_to(:import_source, ImportSource)
    belongs_to(:import_run, ImportRun)
    belongs_to(:raw_import_item, RawImportItem)

    timestamps()
  end

  @doc false
  def changeset(import_conflict, attrs) do
    import_conflict
    |> cast(attrs, [
      :import_source_id,
      :import_run_id,
      :raw_import_item_id,
      :conflict_type,
      :status,
      :summary,
      :details
    ])
    |> validate_required([:import_source_id, :import_run_id, :conflict_type, :summary])
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:import_source)
    |> assoc_constraint(:import_run)
    |> foreign_key_constraint(:raw_import_item_id)
  end

  @doc false
  def resolve_changeset(import_conflict, attrs) do
    import_conflict
    |> cast(attrs, [:status, :details])
    |> validate_inclusion(:status, @statuses)
  end
end
