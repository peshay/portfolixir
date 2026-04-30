defmodule Portfolixir.Imports.DocumentInboxTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Imports.DocumentInbox
  alias Portfolixir.Imports.{ImportSource, RawImportItem}
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  @pdf_a "PDF-BINARY-A"
  @pdf_b "PDF-BINARY-B"

  test "first PDF creates the local document inbox source" do
    assert {:ok, :created, item} =
             DocumentInbox.register_document("statement.pdf", "application/pdf", @pdf_a)

    assert item.content_type == "application/pdf"
    assert item.original_filename == "statement.pdf"

    source = Repo.get!(ImportSource, item.import_source_id)
    assert source.name == "Local Document Inbox"
    assert source.type == "document_inbox"
    assert source.status == "active"
  end

  test "first PDF creates one raw import item" do
    assert {:ok, :created, item} =
             DocumentInbox.register_document("statement.pdf", "application/pdf", @pdf_a)

    assert item.status == "new"
    assert Repo.aggregate(RawImportItem, :count, :id) == 1
  end

  test "same PDF content with same filename is deduplicated" do
    assert {:ok, :created, first} =
             DocumentInbox.register_document("statement.pdf", "application/pdf", @pdf_a)

    assert {:ok, :already_exists, second} =
             DocumentInbox.register_document("statement.pdf", "application/pdf", @pdf_a)

    assert second.id == first.id
    assert Repo.aggregate(RawImportItem, :count, :id) == 1
  end

  test "same PDF content with different filename is deduplicated" do
    assert {:ok, :created, first} =
             DocumentInbox.register_document("statement.pdf", "application/pdf", @pdf_a)

    assert {:ok, :already_exists, second} =
             DocumentInbox.register_document("statement_v2.pdf", "application/pdf", @pdf_a)

    assert second.id == first.id
    assert Repo.aggregate(RawImportItem, :count, :id) == 1
  end

  test "different PDF content creates a new raw import item" do
    assert {:ok, :created, first} =
             DocumentInbox.register_document("statement.pdf", "application/pdf", @pdf_a)

    assert {:ok, :created, second} =
             DocumentInbox.register_document("statement.pdf", "application/pdf", @pdf_b)

    assert second.id != first.id
    assert Repo.aggregate(RawImportItem, :count, :id) == 2
  end

  test "content hash is stable for the same binary" do
    assert {:ok, :created, first} =
             DocumentInbox.register_document("statement.pdf", "application/pdf", @pdf_a)

    assert {:ok, :already_exists, second} =
             DocumentInbox.register_document("statement_v2.pdf", "application/pdf", @pdf_a)

    assert first.content_hash == second.content_hash
  end

  test "payload contains safe metadata only" do
    assert {:ok, :created, item} =
             DocumentInbox.register_document("statement.pdf", "application/pdf", @pdf_a)

    expected_payload = %{
      "source" => "local_document_inbox",
      "original_filename" => "statement.pdf",
      "content_type" => "application/pdf",
      "byte_size" => byte_size(@pdf_a)
    }

    assert item.payload == expected_payload
  end

  test "payload does not contain raw document bytes" do
    assert {:ok, :created, item} =
             DocumentInbox.register_document("statement.pdf", "application/pdf", @pdf_a)

    assert not Map.has_key?(item.payload, "content")
    assert not Map.has_key?(item.payload, "content_bytes")
    assert not Map.has_key?(item.payload, "binary")
    assert not Map.has_key?(item.payload, "pdf")
  end

  test "non-PDF content type is rejected" do
    assert {:error, :unsupported_content_type} =
             DocumentInbox.register_document("statement.txt", "text/plain", @pdf_a)

    assert Repo.aggregate(RawImportItem, :count, :id) == 0
    assert Repo.aggregate(ImportSource, :count, :id) == 0
  end

  test "duplicate handling reuses existing source and does not create duplicate import sources" do
    assert {:ok, :created, _first} =
             DocumentInbox.register_document("statement.pdf", "application/pdf", @pdf_a)

    assert {:ok, :already_exists, _second} =
             DocumentInbox.register_document("statement_v2.pdf", "application/pdf", @pdf_a)

    assert Repo.aggregate(ImportSource, :count, :id) == 1
  end

  test "no ledger transactions are created" do
    existing_transactions = Repo.aggregate(Transaction, :count, :id)

    assert {:ok, :created, _item} =
             DocumentInbox.register_document("statement.pdf", "application/pdf", @pdf_a)

    assert Repo.aggregate(Transaction, :count, :id) == existing_transactions
  end
end
