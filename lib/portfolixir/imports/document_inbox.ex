defmodule Portfolixir.Imports.DocumentInbox do
  @moduledoc "Register local PDF documents as raw import items."

  alias Portfolixir.Imports
  alias Portfolixir.Imports.{ImportSource, RawImportItem}
  alias Portfolixir.Repo

  @source_name "Local Document Inbox"
  @source_type "document_inbox"
  @source_status "active"
  @supported_content_type "application/pdf"
  @allowed_status "new"

  def register_document(filename, content_type, binary_content)
      when is_binary(filename) and is_binary(content_type) and is_binary(binary_content) do
    with :ok <- validate_content_type(content_type),
         {:ok, import_source} <- get_or_create_source(),
         content_hash <- content_hash(binary_content),
         {:ok, result, raw_item} <-
           upsert_raw_item(
             import_source,
             filename,
             content_type,
             content_hash,
             byte_size(binary_content)
           ) do
      {:ok, result, raw_item}
    end
  end

  def register_document(_, _, _),
    do: {:error, :invalid_arguments}

  defp get_or_create_source do
    case Repo.get_by(ImportSource, name: @source_name, type: @source_type, status: @source_status) do
      %ImportSource{} = source ->
        {:ok, source}

      nil ->
        create_source()
    end
  end

  defp create_source do
    Imports.create_import_source(%{
      name: @source_name,
      type: @source_type,
      status: @source_status
    })
  end

  defp validate_content_type(content_type) do
    if normalize_content_type(content_type) == @supported_content_type do
      :ok
    else
      {:error, :unsupported_content_type}
    end
  end

  defp normalize_content_type(content_type) do
    content_type |> String.trim() |> String.downcase()
  end

  defp upsert_raw_item(import_source, filename, content_type, content_hash, size_bytes) do
    case Repo.get_by(RawImportItem,
           import_source_id: import_source.id,
           content_hash: content_hash
         ) do
      %RawImportItem{} = existing ->
        {:ok, :already_exists, existing}

      nil ->
        payload = payload_for_metadata(filename, content_type, size_bytes)

        create_attrs = %{
          import_source_id: import_source.id,
          content_hash: content_hash,
          content_type: normalize_content_type(content_type),
          original_filename: filename,
          payload: payload,
          status: @allowed_status
        }

        case Imports.create_raw_import_item(create_attrs) do
          {:ok, item} ->
            {:ok, :created, item}

          {:error, _changeset} = error ->
            error
        end
    end
  end

  defp payload_for_metadata(filename, content_type, size_bytes) do
    %{
      "source" => "local_document_inbox",
      "original_filename" => filename,
      "content_type" => normalize_content_type(content_type),
      "byte_size" => size_bytes
    }
  end

  defp content_hash(binary_content) do
    :crypto.hash(:sha256, binary_content)
    |> Base.encode16(case: :lower)
    |> then(&"sha256:#{&1}")
  end
end
