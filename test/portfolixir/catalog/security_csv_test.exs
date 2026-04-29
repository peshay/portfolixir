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
end
