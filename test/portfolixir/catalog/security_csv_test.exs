defmodule Portfolixir.Catalog.SecurityCsvTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.SecurityCsv

  setup do
    Catalog.ensure_mvp_currencies!()
    :ok
  end

  test "render_csv includes required header and rows", %{} do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Apple",
        symbol: "AAPL",
        currency_code: "USD",
        active: true
      })

    csv = SecurityCsv.render_csv([security])
    [header, row] = String.split(csv, "\n", trim: true)

    assert header ==
             "name,symbol,currency_code,active,isin,wkn,provider_symbol,exchange_code,notes"

    assert row == "Apple,AAPL,USD,true,,,,,"
  end

  test "render_csv escapes commas and quotes", %{} do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Comma, \"Inc.\"",
        symbol: "COM,1",
        currency_code: "USD",
        notes: "Contains,quote\"and\nnewline"
      })

    csv = SecurityCsv.render_csv([security])

    assert String.ends_with?(
             csv,
             "\"Comma, \"\"Inc.\"\"\",\"COM,1\",USD,true,,,,,\"Contains,quote\"\"and\nnewline\""
           )

    assert String.starts_with?(
             csv,
             "name,symbol,currency_code,active,isin,wkn,provider_symbol,exchange_code,notes\n"
           )
  end

  test "render_csv exports empty optional fields as empty cells", %{} do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Simple",
        symbol: "SIMP",
        currency_code: "USD",
        active: false
      })

    csv = SecurityCsv.render_csv([security])
    [_, row] = String.split(csv, "\n", trim: true)

    assert row == "Simple,SIMP,USD,false,,,,,"
  end

  test "preview_csv_rows parses an exported-style header row and validates rows", %{} do
    assert {:ok, %{rows: [row]}} =
             SecurityCsv.preview_csv_rows(
               """
               name,symbol,currency_code,active,isin,wkn,provider_symbol,exchange_code,notes
               Apple,AAPL,USD,true,US123,987,APPL,NAS,Tech stock
               """,
               valid_currency_codes: ["USD"]
             )

    assert row.row_number == 1
    assert row.status == :valid
    assert row.name == "Apple"
    assert row.symbol == "AAPL"
    assert row.currency_code == "USD"
    assert row.active == true
    assert row.notes == "Tech stock"
  end

  test "preview_csv_rows parses quoted values with commas, quotes, and newlines", %{} do
    assert {:ok, %{rows: [row]}} =
             SecurityCsv.preview_csv_rows(
               """
               name,symbol,currency_code,active,isin,wkn,provider_symbol,exchange_code,notes
               "Comma, \"\"Inc.\"\"","COM,1",USD,true,"IS,IN","W,KN","P,ROV","EX,1","Note with comma, quote ""and"" newline
               line"
               """,
               valid_currency_codes: ["USD"]
             )

    assert row.name == "Comma, \"Inc.\""
    assert row.symbol == "COM,1"
    assert row.isin == "IS,IN"
    assert row.wkn == "W,KN"
    assert row.provider_symbol == "P,ROV"
    assert row.exchange_code == "EX,1"
    assert row.notes == "Note with comma, quote \"and\" newline\nline"
  end

  test "preview_csv_rows defaults empty active to true", %{} do
    assert {:ok, %{rows: [row]}} =
             SecurityCsv.preview_csv_rows(
               """
               name,symbol,currency_code,active,isin,wkn,provider_symbol,exchange_code,notes
               Active Default,AD,USD,,,,
               """,
               valid_currency_codes: ["USD"]
             )

    assert row.status == :valid
    assert row.active == true
  end

  test "preview_csv_rows rejects invalid active values", %{} do
    assert {:ok, %{rows: [row]}} =
             SecurityCsv.preview_csv_rows(
               """
               name,symbol,currency_code,active,isin,wkn,provider_symbol,exchange_code,notes
               Bad Active,BAD,USD,not_true,,,,
               """,
               valid_currency_codes: ["USD"]
             )

    assert row.status == :invalid
    assert "active must be true or false" in row.errors
  end

  test "preview_csv_rows reports missing required values", %{} do
    assert {:ok, %{rows: [row]}} =
             SecurityCsv.preview_csv_rows(
               """
               name,symbol,currency_code,active,isin,wkn,provider_symbol,exchange_code,notes
               ,,USD,true,,,
               """,
               valid_currency_codes: ["USD"]
             )

    assert row.status == :invalid
    assert "name is required" in row.errors
    assert "symbol is required" in row.errors
  end

  test "preview_csv_rows ignores unknown header columns and does not fail", %{} do
    assert {:ok, %{rows: [row]}} =
             SecurityCsv.preview_csv_rows(
               """
               name,symbol,currency_code,extra_column,active
               Apple,AAPL,USD,ignored,true
               """,
               valid_currency_codes: ["USD"]
             )

    assert row.status == :valid
    assert row.name == "Apple"
    assert row.symbol == "AAPL"
    assert row.currency_code == "USD"
    assert row.active == true
  end

  test "preview_csv_rows returns an error when required headers are missing", %{} do
    assert {:error, message} =
             SecurityCsv.preview_csv_rows(
               """
               name,symbol
               Apple,AAPL
               """,
               valid_currency_codes: ["USD"]
             )

    assert message == "Missing required headers: currency_code"
  end

  test "preview_csv_rows returns an error for unknown currency code when catalog currencies are supplied",
       %{} do
    assert {:ok, %{rows: [row]}} =
             SecurityCsv.preview_csv_rows(
               """
               name,symbol,currency_code,active,isin,wkn,provider_symbol,exchange_code,notes
               Apple,AAPL,XXX,true,,,
               """,
               valid_currency_codes: ["USD"]
             )

    assert row.status == :invalid
    assert "currency_code is unknown" in row.errors
  end

  test "preview_csv_rows returns an error for empty input", %{} do
    assert {:error, "CSV input is empty."} =
             SecurityCsv.preview_csv_rows("", valid_currency_codes: [])
  end
end
