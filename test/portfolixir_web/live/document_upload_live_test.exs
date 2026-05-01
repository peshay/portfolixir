defmodule PortfolixirWeb.DocumentUploadLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ecto.Query

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.FundAllocationItem
  alias Portfolixir.Catalog.FundDocument
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  @pdf_with_text "PDF-LIKE\nFACTSHEET_TEXT:Synthetic extraction placeholder\nEOF"

  setup do
    Catalog.ensure_mvp_currencies!()
    :ok
  end

  test "documents/new renders with a security picker and upload form", %{conn: conn} do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Target Security",
        symbol: "TGT",
        currency_code: "EUR"
      })

    {:ok, view, html} = live(conn, "/documents/new")

    assert has_element?(view, "#document-upload-form")
    assert has_element?(view, "h1", "Factsheet document")
    assert has_element?(view, "#document-security-id")
    assert has_element?(view, "option[value=\"#{security.id}\"]")
    assert has_element?(view, "#document-upload-submit", "Upload factsheet")
    assert html =~ "Attach PDF factsheet files directly to a security."
  end

  test "uploading a PDF factsheet registers a fund document", %{conn: conn} do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Target Security",
        symbol: "TGT#{System.unique_integer([:positive])}",
        currency_code: "USD"
      })

    pdf_content = "PDF-LIKE\nFACTSHEET_TEXT:#{security.id}:Synthetic extraction placeholder"

    before_transaction_count = Repo.aggregate(Transaction, :count, :id)
    before_allocation_count = Repo.aggregate(FundAllocationItem, :count, :id)

    before_security_doc_count =
      Repo.aggregate(from(fd in FundDocument, where: fd.security_id == ^security.id), :count, :id)

    {:ok, view, _html} = live(conn, "/documents/new")

    upload =
      file_input(view, "#document-upload-form", :factsheet_file, [
        %{
          name: "factsheet.pdf",
          content: pdf_content,
          type: "application/pdf",
          size: byte_size(pdf_content)
        }
      ])

    assert render_upload(upload, "factsheet.pdf") =~ "100%"

    html =
      view
      |> element("#document-upload-form")
      |> render_submit(%{"security_id" => "#{security.id}"})

    assert html =~ "app-shell-alert--success"

    assert Repo.aggregate(
             from(fd in FundDocument, where: fd.security_id == ^security.id),
             :count,
             :id
           ) ==
             before_security_doc_count + 1

    assert Repo.aggregate(Transaction, :count, :id) == before_transaction_count
    assert Repo.aggregate(FundAllocationItem, :count, :id) == before_allocation_count
  end

  test "uploading the same PDF twice for the same security is idempotent", %{conn: conn} do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Target Security",
        symbol: "TGT#{System.unique_integer([:positive])}",
        currency_code: "USD"
      })

    pdf_content = "PDF-LIKE\nFACTSHEET_TEXT:#{security.id}:Synthetic extraction placeholder"

    {:ok, view, _html} = live(conn, "/documents/new")

    before_security_doc_count =
      Repo.aggregate(from(fd in FundDocument, where: fd.security_id == ^security.id), :count, :id)

    upload =
      file_input(view, "#document-upload-form", :factsheet_file, [
        %{
          name: "factsheet.pdf",
          content: pdf_content,
          type: "application/pdf",
          size: byte_size(pdf_content)
        }
      ])

    assert render_upload(upload, "factsheet.pdf") =~ "100%"

    html =
      view
      |> element("#document-upload-form")
      |> render_submit(%{"security_id" => "#{security.id}"})

    assert html =~ "app-shell-alert--success"

    assert Repo.aggregate(
             from(fd in FundDocument, where: fd.security_id == ^security.id),
             :count,
             :id
           ) ==
             before_security_doc_count + 1

    first_upload_security_doc_count =
      Repo.aggregate(from(fd in FundDocument, where: fd.security_id == ^security.id), :count, :id)

    {:ok, second_view, _html} = live(conn, "/documents/new")

    upload =
      file_input(second_view, "#document-upload-form", :factsheet_file, [
        %{
          name: "factsheet.pdf",
          content: pdf_content,
          type: "application/pdf",
          size: byte_size(pdf_content)
        }
      ])

    assert render_upload(upload, "factsheet.pdf") =~ "100%"

    html =
      second_view
      |> element("#document-upload-form")
      |> render_submit(%{"security_id" => "#{security.id}"})

    assert html =~ "app-shell-alert--success"

    assert Repo.aggregate(
             from(fd in FundDocument, where: fd.security_id == ^security.id),
             :count,
             :id
           ) ==
             first_upload_security_doc_count
  end

  test "choosing a non-PDF is rejected", %{conn: conn} do
    {:ok, _security} =
      Catalog.create_security(%{
        name: "Target Security",
        symbol: "TGT#{System.unique_integer([:positive])}",
        currency_code: "USD"
      })

    {:ok, view, _html} = live(conn, "/documents/new")

    upload =
      file_input(view, "#document-upload-form", :factsheet_file, [
        %{
          name: "factsheet.txt",
          content: @pdf_with_text,
          type: "text/plain",
          size: byte_size(@pdf_with_text)
        }
      ])

    assert {:error, [[_entry_ref, :not_accepted]]} = render_upload(upload, "factsheet.txt")
    assert has_element?(view, "#document-upload-upload-error", "Unsupported file type.")
    assert Repo.aggregate(FundDocument, :count, :id) == 0
  end

  test "missing security selection shows a validation error", %{conn: conn} do
    {:ok, _security} =
      Catalog.create_security(%{
        name: "Target Security",
        symbol: "TGT#{System.unique_integer([:positive])}",
        currency_code: "USD"
      })

    pdf_content = "PDF-LIKE\nFACTSHEET_TEXT:missing-security"

    {:ok, view, _html} = live(conn, "/documents/new")

    upload =
      file_input(view, "#document-upload-form", :factsheet_file, [
        %{
          name: "factsheet.pdf",
          content: pdf_content,
          type: "application/pdf",
          size: byte_size(pdf_content)
        }
      ])

    assert render_upload(upload, "factsheet.pdf") =~ "100%"

    html = render_submit(view, "register_factsheet", %{"security_id" => ""})

    assert html =~ "Please select a security."
    assert has_element?(view, "#document-upload-error", "Please select a security.")
    assert Repo.aggregate(FundDocument, :count, :id) == 0
  end

  test "no-securities state instructs to create a security first", %{conn: conn} do
    {:ok, view, html} = live(conn, "/documents/new")

    assert has_element?(view, "#document-upload-empty-state")
    assert has_element?(view, "#document-upload-empty-state a[href=\"/securities\"]")
    assert html =~ "Create a security first to attach factsheets."
  end
end
