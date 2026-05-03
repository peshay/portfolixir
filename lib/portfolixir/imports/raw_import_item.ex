defmodule Portfolixir.Imports.RawImportItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Imports.{ImportConflict, ImportRun, ImportSource}

  schema "raw_import_items" do
    field(:external_id, :string)
    field(:content_hash, :string)
    field(:content_type, :string)
    field(:original_filename, :string)
    field(:payload, :map, default: %{})
    field(:status, :string, default: "new")

    belongs_to(:import_source, ImportSource)
    belongs_to(:import_run, ImportRun)
    has_many(:import_conflicts, ImportConflict)

    timestamps()
  end

  @doc false
  def changeset(raw_import_item, attrs) do
    raw_import_item
    |> cast(
      attrs,
      [
        :import_source_id,
        :import_run_id,
        :external_id,
        :content_hash,
        :content_type,
        :original_filename,
        :payload,
        :status
      ]
    )
    |> validate_required([:import_source_id])
    |> assoc_constraint(:import_source)
    |> foreign_key_constraint(:import_run_id)
    |> unique_constraint(:external_id,
      name: :raw_import_items_source_id_external_id_uq
    )
    |> unique_constraint(:content_hash,
      name: :raw_import_items_source_id_content_hash_uq
    )
  end
end
