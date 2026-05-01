defmodule Portfolixir.Catalog.FactsheetAllocationPreviewTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.FactsheetAllocationPreview
  alias Portfolixir.Catalog.FactsheetDocuments
  alias Portfolixir.Catalog.FundAllocation
  alias Portfolixir.Catalog.FundAllocationItem
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo
  alias Portfolixir.Taxonomies.Category

  setup do
    Catalog.ensure_mvp_currencies!()
    :ok
  end

  @fixture_text """
  Regions
  North America 62.5%
  Europe 18.3%
  Asia Pacific 12.2%

  Countries
  United States 58.1%
  Germany 5.2%

  Sectors
  Technology 24.1%
  Health Care 13.4%

  Asset Classes
  Equity 97.8%
  Cash 2.2%
  """

  @region_text """
  Regions
  North America 62.5%
  Europe 18.3%
  """

  @country_text """
  Countries
  United States 58.1%
  Germany 5.2%
  """

  @sector_text """
  Sectors
  Technology 24.1%
  Health Care 13.4%
  """

  @asset_class_text """
  Asset Classes
  Equity 97.8%
  Cash 2.2%
  """

  test "preview_text parses region allocations" do
    assert {:ok, preview} = FactsheetAllocationPreview.preview_text(@region_text)

    assert length(preview["allocations"]) == 1

    allocation = hd(preview["allocations"])
    assert allocation["allocation_type"] == "region"
    assert allocation["source"] == "factsheet_text"
    assert allocation["as_of_date"] == nil

    items = allocation["items"]
    assert length(items) == 2

    first = hd(items)
    assert first["label"] == "North America"
    assert Decimal.equal?(first["weight"], Decimal.new("62.5"))
    assert first["confidence"] == Decimal.new("1")
    assert first["raw_line"] == "North America 62.5%"
  end

  test "preview_text parses country allocations" do
    assert {:ok, preview} = FactsheetAllocationPreview.preview_text(@country_text)

    allocation = hd(preview["allocations"])
    assert allocation["allocation_type"] == "country"

    assert Enum.any?(allocation["items"], fn item ->
             item["label"] == "United States" &&
               Decimal.equal?(item["weight"], Decimal.new("58.1"))
           end)
  end

  test "preview_text parses sector allocations" do
    assert {:ok, preview} = FactsheetAllocationPreview.preview_text(@sector_text)

    allocation = hd(preview["allocations"])
    assert allocation["allocation_type"] == "sector"
    assert length(allocation["items"]) == 2
  end

  test "preview_text parses asset class allocations" do
    assert {:ok, preview} = FactsheetAllocationPreview.preview_text(@asset_class_text)

    allocation = hd(preview["allocations"])
    assert allocation["allocation_type"] == "asset_class"

    labels = Enum.map(allocation["items"], & &1["label"])
    assert "Cash" in labels
    assert "Equity" in labels
  end

  test "preview_text returns decimal weights" do
    assert {:ok, preview} = FactsheetAllocationPreview.preview_text(@fixture_text)

    assert Enum.all?(preview["allocations"], fn allocation ->
             Enum.all?(allocation["items"], fn item ->
               assert is_struct(item["weight"], Decimal)
               is_struct(item["confidence"], Decimal)
             end)
           end)
  end

  test "preview_text supports comma decimal separators" do
    text = """
    Countries
    United States 58,1 %
    Germany 5,2%
    """

    assert {:ok, preview} = FactsheetAllocationPreview.preview_text(text)

    first = hd(preview["allocations"]) |> then(fn allocation -> hd(allocation["items"]) end)
    second = hd(preview["allocations"]) |> then(fn allocation -> hd(tl(allocation["items"])) end)

    assert Decimal.equal?(first["weight"], Decimal.new("58.1"))
    assert Decimal.equal?(second["weight"], Decimal.new("5.2"))
  end

  test "ambiguous or unparseable lines produce warnings" do
    text = """
    Regions
    North America 62.5%
    Not sure this is an allocation row
    Europe 18.3%
    """

    assert {:ok, preview} = FactsheetAllocationPreview.preview_text(text)

    assert preview["counts"]["items"] == 2

    assert Enum.any?(
             preview["warnings"],
             &String.contains?(&1, "Could not parse allocation line")
           )
  end

  test "preview_text returns stable top-level keys" do
    assert {:ok, preview} = FactsheetAllocationPreview.preview_text(@fixture_text)

    assert Map.keys(preview) |> MapSet.new() ==
             MapSet.new([
               "fund_document_id",
               "security_id",
               "allocations",
               "warnings",
               "counts"
             ])
  end

  test "counts match parsed allocations and items" do
    assert {:ok, preview} = FactsheetAllocationPreview.preview_text(@fixture_text)

    allocation_count = length(preview["allocations"])

    item_count =
      Enum.reduce(preview["allocations"], 0, fn allocation, count ->
        count + length(allocation["items"])
      end)

    assert preview["counts"] == %{"allocations" => allocation_count, "items" => item_count}
    assert allocation_count == 4
    assert item_count == 9
  end

  test "preview_fund_document reads extracted text from persisted fund document" do
    security = create_security("FACTSHEET-PREVIEW")

    assert {:ok, :created, fund_document} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               "PDF-LIKE\nFACTSHEET_TEXT:#{@fixture_text}\nEOF"
             )

    assert {:ok, preview} = FactsheetAllocationPreview.preview_fund_document(fund_document.id)

    assert preview["fund_document_id"] == fund_document.id
    assert preview["security_id"] == security.id
    assert preview["counts"]["allocations"] == 4
  end

  test "fund_document without extracted_text returns deterministic warning" do
    security = create_security("FACTSHEET-NOTEXT")

    assert {:ok, :created, fund_document} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               "PDF-LIKE\nFACTSHEET_TEXT:\nEOF"
             )

    assert {:ok, preview} = FactsheetAllocationPreview.preview_fund_document(fund_document.id)

    assert preview["allocations"] == []
    assert preview["counts"] == %{"allocations" => 0, "items" => 0}
    assert "No extracted factsheet text is available." in preview["warnings"]
  end

  test "preview_fund_document does not persist allocations or ledger/ category records" do
    security = create_security("FACTSHEET-SIDEEFFECT")

    assert {:ok, :created, fund_document} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               "PDF-LIKE\nFACTSHEET_TEXT:#{@fixture_text}\nEOF"
             )

    before_allocations = Repo.aggregate(FundAllocation, :count, :id)
    before_items = Repo.aggregate(FundAllocationItem, :count, :id)
    before_transactions = Repo.aggregate(Transaction, :count, :id)
    before_categories = Repo.aggregate(Category, :count, :id)

    assert {:ok, _} = FactsheetAllocationPreview.preview_fund_document(fund_document.id)

    assert Repo.aggregate(FundAllocation, :count, :id) == before_allocations
    assert Repo.aggregate(FundAllocationItem, :count, :id) == before_items
    assert Repo.aggregate(Transaction, :count, :id) == before_transactions
    assert Repo.aggregate(Category, :count, :id) == before_categories
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
