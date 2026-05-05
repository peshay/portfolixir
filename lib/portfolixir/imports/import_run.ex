defmodule Portfolixir.Imports.ImportRun do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Imports.{ImportConflict, ImportSource, RawImportItem}

  schema "import_runs" do
    field(:status, :string, default: "pending")
    field(:started_at, :utc_datetime_usec)
    field(:finished_at, :utc_datetime_usec)
    field(:summary, :map, default: %{})

    belongs_to(:import_source, ImportSource)
    has_many(:raw_import_items, RawImportItem)
    has_many(:import_conflicts, ImportConflict)

    timestamps()
  end

  @doc false
  def changeset(import_run, attrs) do
    import_run
    |> cast(attrs, [:import_source_id, :status, :started_at, :finished_at, :summary])
    |> validate_required([:import_source_id])
    |> assoc_constraint(:import_source)
  end
end
