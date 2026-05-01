defmodule Portfolixir.Catalog.FactsheetDocuments do
  @moduledoc "Factsheet upload intake and text extraction workflow."

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.FundDocument
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Imports.DocumentInbox

  @default_extractor_module Portfolixir.Catalog.DefaultFactsheetDocumentTextExtractor
  @document_type "factsheet"
  @document_source "upload"

  def register_factsheet(security_id, filename, content_type, binary_content, opts \\ [])

  def register_factsheet(security_id, filename, content_type, binary_content, opts)
      when is_integer(security_id) and is_binary(filename) and is_binary(content_type) and
             is_binary(binary_content) do
    with {:ok, _security} <- ensure_security_exists(security_id),
         extractor <- Keyword.get(opts, :extractor_module, @default_extractor_module),
         {:ok, _doc_status, raw_item} <-
           DocumentInbox.register_document(filename, content_type, binary_content),
         {:ok, extraction_status, extracted_text, extraction_error} <-
           extract_text(extractor, binary_content),
         {:ok, fund_doc_status, fund_document} <-
           upsert_fund_document(
             security_id,
             raw_item,
             extraction_status,
             extracted_text,
             extraction_error
           ) do
      {:ok, fund_doc_status, fund_document}
    end
  end

  def register_factsheet(_, _, _, _, _), do: {:error, :invalid_arguments}

  defp ensure_security_exists(security_id) do
    case Catalog.get_security(security_id) do
      %Security{} = security -> {:ok, security}
      _ -> {:error, :security_not_found}
    end
  end

  defp extract_text(extractor_module, binary_content) do
    case extractor_module.extract_text(binary_content) do
      {:ok, extracted_text} ->
        {:ok, "extracted", extracted_text, nil}

      {:error, :empty} ->
        {:ok, "empty", nil, nil}

      {:error, :unsupported} ->
        {:ok, "unsupported", nil, nil}

      {:error, reason} ->
        {:ok, "failed", nil, inspect(reason)}

      _ ->
        {:ok, "failed", nil, "unexpected extractor response"}
    end
  end

  defp upsert_fund_document(
         security_id,
         raw_item,
         extraction_status,
         extracted_text,
         extraction_error
       ) do
    content_hash = raw_item.content_hash

    case Catalog.get_fund_document_for_security_and_hash(security_id, content_hash) do
      %FundDocument{} = existing_document ->
        {:ok, :already_exists, existing_document}

      nil ->
        create_attrs = %{
          security_id: security_id,
          raw_import_item_id: raw_item.id,
          document_type: @document_type,
          source: @document_source,
          original_filename: raw_item.original_filename,
          content_type: raw_item.content_type,
          content_hash: content_hash,
          extracted_text: extracted_text,
          extraction_status: extraction_status,
          extraction_error: extraction_error,
          metadata: %{}
        }

        case Catalog.create_fund_document(create_attrs) do
          {:ok, fund_document} ->
            {:ok, :created, fund_document}

          {:error, changeset} ->
            case Catalog.get_fund_document_for_security_and_hash(security_id, content_hash) do
              %FundDocument{} = existing_document ->
                {:ok, :already_exists, existing_document}

              nil ->
                {:error, changeset}
            end
        end
    end
  end
end
