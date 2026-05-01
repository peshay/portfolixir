defmodule Portfolixir.Catalog.FactsheetDocumentsTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.FactSheetTextExtractorFailure
  alias Portfolixir.Catalog.FactsheetDocuments
  alias Portfolixir.Catalog.FundAllocationItem
  alias Portfolixir.Imports.RawImportItem
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  setup do
    Catalog.ensure_mvp_currencies!()
    :ok
  end

  defmodule FactSheetTextExtractorFailure do
    @behaviour Portfolixir.Catalog.FactsheetDocumentTextExtractor

    @impl true
    def extract_text(_), do: {:error, :boom}
  end

  @pdf_with_text "PDF-LIKE\nFACTSHEET_TEXT:This is synthetic extracted allocation text\nEOF"
  @pdf_without_text "PDF-LIKE\nFACTSHEET_TEXT:\nEOF"

  test "registering a factsheet creates a raw import item through DocumentInbox" do
    security = create_security("FACTSHEET-RAW")

    assert {:ok, :created, fund_document} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               @pdf_with_text
             )

    raw_item = Repo.get!(RawImportItem, fund_document.raw_import_item_id)

    assert raw_item.original_filename == "factsheet.pdf"
    assert raw_item.content_type == "application/pdf"
    assert raw_item.payload["source"] == "local_document_inbox"
    assert raw_item.payload["original_filename"] == "factsheet.pdf"
  end

  test "registering a factsheet creates a fund document for the security" do
    security = create_security("FACTSHEET-CREATE")

    assert {:ok, :created, fund_document} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               @pdf_with_text
             )

    assert fund_document.security_id == security.id
    assert fund_document.document_type == "factsheet"
    assert fund_document.source == "upload"
    assert fund_document.original_filename == "factsheet.pdf"
    assert fund_document.content_type == "application/pdf"
    assert fund_document.extraction_status == "extracted"
    assert fund_document.extracted_text == "This is synthetic extracted allocation text"
  end

  test "duplicate upload for same security/content is idempotent and reused" do
    security = create_security("FACTSHEET-DUP")

    assert {:ok, :created, first} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               @pdf_with_text
             )

    assert {:ok, :already_exists, second} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               @pdf_with_text
             )

    assert second.id == first.id
    assert Repo.aggregate(Catalog.FundDocument, :count, :id) == 1
    assert Repo.aggregate(RawImportItem, :count, :id) == 1
  end

  test "same PDF content can be uploaded for different securities" do
    security_one = create_security("FACTSHEET-SHARED-ONE")
    security_two = create_security("FACTSHEET-SHARED-TWO")

    assert {:ok, :created, first_factsheet} =
             FactsheetDocuments.register_factsheet(
               security_one.id,
               "factsheet.pdf",
               "application/pdf",
               @pdf_with_text
             )

    assert {:ok, :created, second_factsheet} =
             FactsheetDocuments.register_factsheet(
               security_two.id,
               "factsheet.pdf",
               "application/pdf",
               @pdf_with_text
             )

    assert first_factsheet.id != second_factsheet.id
    assert first_factsheet.raw_import_item_id == second_factsheet.raw_import_item_id
    assert Repo.aggregate(Catalog.FundDocument, :count, :id) == 2
  end

  test "non-PDF content type is rejected" do
    security = create_security("FACTSHEET-TYPE")

    assert {:error, :unsupported_content_type} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.txt",
               "text/plain",
               @pdf_with_text
             )

    assert Repo.aggregate(Catalog.FundDocument, :count, :id) == 0
  end

  test "unknown security id is rejected" do
    assert {:error, :security_not_found} =
             FactsheetDocuments.register_factsheet(
               9_999_999,
               "factsheet.pdf",
               "application/pdf",
               @pdf_with_text
             )

    assert Repo.aggregate(Catalog.FundDocument, :count, :id) == 0
    assert Repo.aggregate(RawImportItem, :count, :id) == 0
  end

  test "raw PDF bytes are not stored in fund document metadata" do
    security = create_security("FACTSHEET-META")

    assert {:ok, :created, fund_document} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               @pdf_with_text
             )

    refute Map.has_key?(fund_document.metadata, "content")
    refute Map.has_key?(fund_document.metadata, "content_bytes")
    refute Map.has_key?(fund_document.metadata, "binary")
    refute Map.has_key?(fund_document.metadata, "pdf")
  end

  test "raw PDF bytes are not stored in raw import item payload" do
    security = create_security("FACTSHEET-PAYLOAD")

    assert {:ok, :created, fund_document} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               @pdf_with_text
             )

    payload = Repo.get!(RawImportItem, fund_document.raw_import_item_id).payload

    assert payload["source"] == "local_document_inbox"
    assert payload["original_filename"] == "factsheet.pdf"
    refute Map.has_key?(payload, "content")
    refute Map.has_key?(payload, "content_bytes")
    refute Map.has_key?(payload, "binary")
    refute Map.has_key?(payload, "pdf")
  end

  test "extracted text is stored when extractor succeeds" do
    security = create_security("FACTSHEET-EXTRACT")

    assert {:ok, :created, fund_document} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               @pdf_with_text
             )

    assert fund_document.extraction_status == "extracted"
    assert fund_document.extracted_text == "This is synthetic extracted allocation text"
  end

  test "empty text results in extraction status empty" do
    security = create_security("FACTSHEET-EMPTY")

    assert {:ok, :created, fund_document} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               @pdf_without_text
             )

    assert fund_document.extraction_status == "empty"
    assert fund_document.extracted_text == nil
    assert fund_document.extraction_error == nil
  end

  test "failed extraction stores failure status and message" do
    security = create_security("FACTSHEET-FAIL")

    assert {:ok, :created, fund_document} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               @pdf_with_text,
               extractor_module: FactSheetTextExtractorFailure
             )

    assert fund_document.extraction_status == "failed"
    assert fund_document.extracted_text == nil
    assert fund_document.extraction_error == ":boom"
  end

  test "no fund allocation items are created" do
    security = create_security("FACTSHEET-NOALLOC")
    before_count = Repo.aggregate(FundAllocationItem, :count, :id)

    assert {:ok, _status, _doc} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               @pdf_with_text
             )

    assert Repo.aggregate(FundAllocationItem, :count, :id) == before_count
  end

  test "no ledger transactions are created" do
    security = create_security("FACTSHEET-NOTXL")
    before_count = Repo.aggregate(Transaction, :count, :id)

    assert {:ok, _status, _doc} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               @pdf_with_text
             )

    assert Repo.aggregate(Transaction, :count, :id) == before_count
  end

  defp create_security(symbol) do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Factsheet #{symbol}",
        symbol: symbol,
        currency_code: "USD"
      })

    security
  end
end
