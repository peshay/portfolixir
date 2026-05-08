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

    assert has_element?(
             view,
             "#document-upload-form[aria-describedby=\"document-upload-form-intro\"]"
           )

    assert has_element?(view, "#document-upload-file-hint")
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
      file_input(
        view,
        "#document-upload-form",
        :factsheet_file,
        [
          %{
            name: "factsheet.pdf",
            content: pdf_content,
            type: "application/pdf",
            size: byte_size(pdf_content)
          }
        ]
      )

    assert render_upload(upload, "factsheet.pdf") =~ "100%"

    _html =
      view
      |> form("#document-upload-form", %{"security_id" => "#{security.id}"})
      |> render_submit()

    assert has_element?(view, "#factsheet-review-link")

    assert has_element?(
             view,
             "#document-upload-form[aria-describedby=\"document-upload-form-intro document-upload-success\"]"
           )

    assert Repo.aggregate(
             from(fd in FundDocument, where: fd.security_id == ^security.id),
             :count,
             :id
           ) ==
             before_security_doc_count + 1

    assert Repo.aggregate(Transaction, :count, :id) == before_transaction_count
    assert Repo.aggregate(FundAllocationItem, :count, :id) == before_allocation_count
  end

  test "successful upload includes a link to allocation review", %{conn: conn} do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Target Security",
        symbol: "TGT#{System.unique_integer([:positive])}",
        currency_code: "USD"
      })

    pdf_content = "PDF-LIKE\nFACTSHEET_TEXT:#{security.id}:Synthetic extraction placeholder"

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
      |> form("#document-upload-form", %{"security_id" => "#{security.id}"})
      |> render_submit()

    fund_document =
      Repo.get_by!(FundDocument, security_id: security.id, original_filename: "factsheet.pdf")

    expected_path = "/fund-documents/#{fund_document.id}/allocations/review"

    assert html =~ "Factsheet registered."
    assert has_element?(view, "#factsheet-review-link")
    assert has_element?(view, "#factsheet-review-link[href=\"#{expected_path}\"]")

    rendered = render(view)
    assert rendered =~ expected_path
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
      render_submit(
        view,
        "register_factsheet",
        %{"security_id" => "#{security.id}", "factsheet_file" => upload}
      )

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

    second_html =
      second_view
      |> form("#document-upload-form", %{"security_id" => "#{security.id}"})
      |> render_submit()

    assert has_element?(second_view, "#document-upload-success")
    assert second_html =~ "This factsheet has already been uploaded for the selected security."

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

    assert has_element?(
             view,
             "#document-upload-upload-error-1[role=\"alert\"]",
             "Unsupported file type."
           )

    assert has_element?(
             view,
             "#document-upload-form[aria-describedby=\"document-upload-form-intro document-upload-upload-error-1\"]"
           )

    assert Repo.aggregate(FundDocument, :count, :id) == 0
  end

  test "invalid security id shows a validation error", %{conn: conn} do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Target Security",
        symbol: "TGT#{System.unique_integer([:positive])}",
        currency_code: "USD"
      })

    {:ok, view, _html} = live(conn, "/documents/new")

    upload =
      file_input(view, "#document-upload-form", :factsheet_file, [
        %{
          name: "factsheet.pdf",
          content: @pdf_with_text,
          type: "application/pdf",
          size: byte_size(@pdf_with_text)
        }
      ])

    assert render_upload(upload, "factsheet.pdf") =~ "100%"

    html =
      render_submit(view, "register_factsheet", %{
        "security_id" => "not-a-number",
        "factsheet_file" => upload
      })

    assert html =~ "Please select a valid security."
    assert has_element?(view, "#document-upload-error", "Please select a valid security.")

    assert has_element?(
             view,
             "#document-upload-form[aria-describedby=\"document-upload-form-intro document-upload-error\"]"
           )

    assert Repo.aggregate(
             from(fd in FundDocument, where: fd.security_id == ^security.id),
             :count,
             :id
           ) == 0
  end

  test "submitting without a file shows a deterministic error", %{conn: conn} do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Target Security",
        symbol: "TGT#{System.unique_integer([:positive])}",
        currency_code: "USD"
      })

    {:ok, view, _html} = live(conn, "/documents/new")

    html =
      view
      |> form("#document-upload-form", %{"security_id" => "#{security.id}"})
      |> render_submit()

    assert html =~ "Please choose a PDF file before submitting."

    assert has_element?(
             view,
             "#document-upload-error",
             "Please choose a PDF file before submitting."
           )
  end

  test "non-existent security shows no-longer-available error", %{conn: conn} do
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
          name: "factsheet.pdf",
          content: @pdf_with_text,
          type: "application/pdf",
          size: byte_size(@pdf_with_text)
        }
      ])

    assert render_upload(upload, "factsheet.pdf") =~ "100%"

    html =
      render_submit(view, "register_factsheet", %{
        "security_id" => "999999",
        "factsheet_file" => upload
      })

    assert html =~ "Selected security is no longer available."

    assert has_element?(
             view,
             "#document-upload-error",
             "Selected security is no longer available."
           )
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

  test "no-securities state exposes deterministic accessible title and description", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/documents/new")

    assert has_element?(
             view,
             "#document-upload-empty-state[aria-labelledby=\"document-upload-empty-state-title\"][aria-describedby=\"document-upload-empty-state-description\"]"
           )

    assert has_element?(view, "#document-upload-empty-state-title", "No securities yet")

    assert has_element?(
             view,
             "#document-upload-empty-state-description",
             "Create a security first to attach factsheets."
           )
  end

  test "no-securities state instructs to create a security first", %{conn: conn} do
    {:ok, view, html} = live(conn, "/documents/new")

    assert has_element?(
             view,
             "#document-upload-empty-state[role=\"status\"][aria-live=\"polite\"]"
           )

    assert has_element?(view, "#document-upload-empty-state a[href=\"/securities\"]")
    refute has_element?(view, "#document-upload-form")
    assert html =~ "Create a security first to attach factsheets."
  end
end
