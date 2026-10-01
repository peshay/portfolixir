defmodule PortfolixirWeb.ImportsConverterExampleTest do
  # Sprint 17 A4 (#983): the MCP companion's `import_converter` prompt states
  # the Portfolio Performance CSV v1 format a user's agent writes a converter
  # for, and shows one synthetic example of it (and one of the JSON v1
  # variant). The examples live once, in the prompt module, between markers;
  # this test reads them from there and takes them through the real Imports
  # page, so the format the prompt teaches is the format the preview accepts,
  # and the cash effects it describes are the ones the ledger books.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @prompts "mcp-server/src/prompts.ts"

  defp example!(marker) do
    source = File.read!(@prompts)

    case Regex.run(~r/\/\/ BEGIN #{marker}\n[^`]*`(.*?)`;\n\/\/ END #{marker}/s, source) do
      [_, body] -> body
      nil -> flunk("#{@prompts} carries no #{marker} block")
    end
  end

  defp drop(view, name, content, type) do
    view
    |> file_input("#pp-import-form", :pp_file, [
      %{name: name, content: content, type: type, last_modified: 1_700_000_000_000}
    ])
    |> render_upload(name)

    render_async(view)
  end

  defp apply_import(conn, name, content, type) do
    {:ok, view, _html} = live(conn, "/imports")
    drop(view, name, content, type)

    refute has_element?(view, "#parser-warnings-box")
    refute has_element?(view, "#pp-import-confirm[disabled]")

    view |> element("form#pp-import-apply") |> render_submit()
    render_async(view, 2_000)
  end

  defp balance(name) do
    account = Enum.find(Portfolios.list_cash_accounts(), &(&1.name == name))
    assert account, "no cash account #{name}"
    Ledger.cash_balances() |> Map.fetch!(account.id)
  end

  defp quantity(depot_name, security_name) do
    depot = Enum.find(Portfolios.list_securities_accounts(), &(&1.name == depot_name))
    security = Enum.find(Portfolixir.Catalog.list_securities(), &(&1.name == security_name))
    Ledger.positions_for_portfolio(depot.portfolio_id) |> Map.get({depot.id, security.id})
  end

  # User story (A4, #983):
  # As the operator whose agent wrote a converter from my bank's export,
  # I want the CSV the import_converter prompt teaches to preview without an
  # error on the Imports page and to book the cash the prompt says it books,
  # so that the file I drop is the file I meant, and dropping it twice books
  # nothing twice.
  #
  # Acceptance criteria:
  # - The prompt's CSV example parses with no row error, every warning being
  #   the CSV's documented missing ISIN, into the kinds it names.
  # - Betrag is each row's cash effect: a buy's includes its fees and taxes, a
  #   sell's is net of them, a dividend's is net of the withheld tax; the
  #   example keeps quantity × price consistent with it to the cent.
  # - Dropped on a fresh instance's Imports page, it applies with every
  #   prefilled choice, and the cash balances and positions are exact.
  # - Dropping it again books nothing.
  test "the import_converter CSV example previews cleanly and books exactly", %{conn: conn} do
    csv = example!("PP CSV V1 EXAMPLE")

    assert {:ok, preview} = PortfolioPerformance.parse(csv, filename: "converted.csv")
    assert preview.format == :csv
    assert preview.errors == []
    assert Enum.all?(preview.entries, &(&1.warnings in [[], ["csv-without-isin"]]))

    assert Enum.map(preview.entries, & &1.kind) ==
             ~w(deposit buy buy dividend sell interest fee cash_transfer)

    for entry <- preview.entries, entry.kind in ["buy", "sell"] do
      trade = Decimal.mult(entry.quantity, entry.price)
      costs = Decimal.add(entry.fees, entry.taxes)

      expected =
        if entry.kind == "buy", do: Decimal.add(trade, costs), else: Decimal.sub(trade, costs)

      assert Decimal.equal?(entry.gross_amount, expected), "row #{entry.source_row}"
    end

    dividend = Enum.find(preview.entries, &(&1.kind == "dividend"))
    assert Decimal.equal?(dividend.gross_amount, Decimal.new("7.36"))
    assert Decimal.equal?(dividend.taxes, Decimal.new("2.64"))

    done = apply_import(conn, "converted.csv", csv, "text/csv")
    assert done =~ "Created transactions: 8"

    # 10,000.00 − 3,221.00 − 501.50 + 7.36 + 612.50 + 3.10 − 4.90 − 1,000.00
    assert Decimal.equal?(balance("Example Bank Cash"), Decimal.new("5895.56"))
    assert Decimal.equal?(balance("Example Savings"), Decimal.new("1000.00"))

    assert Decimal.equal?(
             quantity("Example Broker Depot", "Example World Equity Fund"),
             Decimal.new("40")
           )

    assert Decimal.equal?(
             quantity("Example Broker Depot", "Sample Industrial Corp") || Decimal.new(0),
             Decimal.new(0)
           )

    apply_import(conn, "converted.csv", csv, "text/csv")
    assert length(Ledger.list_transactions()) == 8
    assert Decimal.equal?(balance("Example Bank Cash"), Decimal.new("5895.56"))
  end

  # User story (A4, #983):
  # As the operator whose export carries another currency or ISINs,
  # I want the JSON v1 variant the prompt describes to import as well,
  # so that a foreign-currency account and its securities keep what the CSV
  # cannot carry.
  #
  # Acceptance criteria:
  # - The prompt's JSON example parses with no row error, keeping its
  #   currency and its ISIN.
  # - Applied, the cash account is created in that currency and books the
  #   amount as its cash effect.
  test "the import_converter JSON example keeps its currency and ISIN", %{conn: conn} do
    json = example!("PP JSON V1 EXAMPLE")

    assert {:ok, preview} = PortfolioPerformance.parse(json, filename: "converted.json")
    assert preview.format == :json
    assert preview.errors == []
    assert Enum.all?(preview.entries, &(&1.currency_code == "USD"))

    buy = Enum.find(preview.entries, &(&1.kind == "buy"))
    assert buy.security.isin == "XXEXAMPLE019"
    assert Decimal.equal?(buy.price, Decimal.new("60"))

    done = apply_import(conn, "converted.json", json, "application/json")
    assert done =~ "Created transactions: 2"

    account = Enum.find(Portfolios.list_cash_accounts(), &(&1.name == "Example USD Cash"))
    assert account.currency_code == "USD"
    assert Decimal.equal?(balance("Example USD Cash"), Decimal.new("797.00"))
  end
end
