defmodule Portfolixir.Catalog.FundDocument do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Imports.RawImportItem

  schema "fund_documents" do
    field(:document_type, :string, default: "factsheet")
    field(:source, :string, default: "upload")
    field(:original_filename, :string)
    field(:content_type, :string)
    field(:content_hash, :string)
    field(:extracted_text, :string)
    field(:extraction_status, :string)
    field(:extraction_error, :string)
    field(:metadata, :map, default: %{})

    belongs_to(:security, Security)
    belongs_to(:raw_import_item, RawImportItem)

    timestamps()
  end

  @doc false
  def changeset(fund_document, attrs) do
    fund_document
    |> cast(attrs, [
      :security_id,
      :raw_import_item_id,
      :document_type,
      :source,
      :original_filename,
      :content_type,
      :content_hash,
      :extracted_text,
      :extraction_status,
      :extraction_error,
      :metadata
    ])
    |> validate_required([
      :security_id,
      :raw_import_item_id,
      :document_type,
      :source,
      :original_filename,
      :content_type,
      :content_hash,
      :extraction_status
    ])
    |> validate_inclusion(:document_type, ["factsheet"])
    |> validate_inclusion(:source, ["upload"])
    |> validate_inclusion(:extraction_status, ["extracted", "empty", "failed", "unsupported"])
    |> validate_metadata_map()
    |> assoc_constraint(:security)
    |> assoc_constraint(:raw_import_item)
    |> unique_constraint(:content_hash,
      name: :fund_documents_security_id_content_hash_uq
    )
  end

  defp validate_metadata_map(changeset) do
    validate_change(changeset, :metadata, fn :metadata, metadata ->
      case metadata do
        %{} = _map -> []
        _ -> [metadata: "is invalid"]
      end
    end)
  end
end
