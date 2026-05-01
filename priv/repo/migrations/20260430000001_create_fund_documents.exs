defmodule Portfolixir.Repo.Migrations.CreateFundDocuments do
  use Ecto.Migration

  def change do
    create table(:fund_documents) do
      add(:security_id, references(:securities, on_delete: :restrict), null: false)
      add(:raw_import_item_id, references(:raw_import_items, on_delete: :restrict), null: false)
      add(:document_type, :string, null: false, default: "factsheet")
      add(:source, :string, null: false, default: "upload")
      add(:original_filename, :string, null: false)
      add(:content_type, :string, null: false)
      add(:content_hash, :string, null: false)
      add(:extracted_text, :text)
      add(:extraction_status, :string, null: false, default: "unsupported")
      add(:extraction_error, :text)
      add(:metadata, :map, null: false, default: "{}")

      timestamps()
    end

    create(index(:fund_documents, [:security_id]))
    create(index(:fund_documents, [:raw_import_item_id]))

    create(
      unique_index(
        :fund_documents,
        [:security_id, :content_hash],
        name: :fund_documents_security_id_content_hash_uq
      )
    )
  end
end
