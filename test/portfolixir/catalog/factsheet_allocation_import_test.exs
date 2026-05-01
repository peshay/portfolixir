defmodule Portfolixir.Catalog.FactsheetAllocationImportTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.FactsheetAllocationImport
  alias Portfolixir.Catalog.FactsheetAllocationPreview
  alias Portfolixir.Catalog.FactsheetDocuments
  alias Portfolixir.Catalog.{FundAllocation, FundAllocationItem, SecurityCategoryAssignment}
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

  @country_sector_asset_text """
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

  test "confirm_fund_document persists allocations from persisted fund document" do
    security = create_security("FACTSHEET-CONFIRM-DOC")

    assert {:ok, :created, fund_document} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               "PDF-LIKE\nFACTSHEET_TEXT:#{@fixture_text}\nEOF"
             )

    before_allocations = Repo.aggregate(FundAllocation, :count, :id)
    before_items = Repo.aggregate(FundAllocationItem, :count, :id)

    assert {:ok, summary} = FactsheetAllocationImport.confirm_fund_document(fund_document.id)

    assert summary["security_id"] == security.id
    assert summary["fund_document_id"] == fund_document.id
    assert summary["created"]["allocations"] == 4
    assert summary["created"]["fund_allocation_items"] == 9
    assert summary["skipped"]["allocations"] == 0
    assert summary["skipped"]["fund_allocation_items"] == 0

    assert Repo.aggregate(FundAllocation, :count, :id) == before_allocations + 4
    assert Repo.aggregate(FundAllocationItem, :count, :id) == before_items + 9

    allocations =
      Repo.all(
        from(a in FundAllocation,
          where: a.security_id == ^security.id,
          order_by: [asc: a.allocation_type]
        )
      )

    assert Enum.map(allocations, & &1.source) |> Enum.uniq() == ["factsheet"]

    assert Enum.map(allocations, & &1.allocation_type) == [
             "asset_class",
             "country",
             "region",
             "sector"
           ]
  end

  test "confirm_preview persists region allocation and items" do
    security = create_security("CONFIRM-REGION")

    assert {:ok, preview} =
             FactsheetAllocationPreview.preview_text(
               @region_text,
               %{"security_id" => security.id, "as_of_date" => "2026-03-02"}
             )

    assert {:ok, summary} = FactsheetAllocationImport.confirm_preview(preview)

    assert summary["created"]["allocations"] == 1
    assert summary["created"]["fund_allocation_items"] == 2

    allocation =
      Repo.get_by!(FundAllocation,
        security_id: security.id,
        source: "factsheet",
        allocation_type: "region"
      )

    assert allocation.as_of_date == ~D[2026-03-02]

    item_labels =
      Repo.all(
        from(i in FundAllocationItem,
          where: i.fund_allocation_id == ^allocation.id,
          order_by: [asc: i.label]
        )
        |> select([i], i.label)
      )

    assert item_labels == ["Europe", "North America"]
  end

  test "confirm_preview persists country, sector, and asset_class allocations" do
    security = create_security("CONFIRM-MULTI")

    assert {:ok, preview} =
             FactsheetAllocationPreview.preview_text(
               @country_sector_asset_text,
               %{"security_id" => security.id}
             )

    assert {:ok, summary} = FactsheetAllocationImport.confirm_preview(preview)

    assert summary["created"]["allocations"] == 3
    assert summary["created"]["fund_allocation_items"] == 6

    count =
      Repo.aggregate(
        from(a in FundAllocation, where: a.security_id == ^security.id),
        :count,
        :id
      )

    assert count == 3
  end

  test "confirmation summary has stable top-level keys" do
    security = create_security("CONFIRM-SUMMARY")

    assert {:ok, preview} =
             FactsheetAllocationPreview.preview_text(
               @region_text,
               %{"security_id" => security.id}
             )

    assert {:ok, summary} = FactsheetAllocationImport.confirm_preview(preview)

    assert MapSet.new(Map.keys(summary)) ==
             MapSet.new([
               "created",
               "updated",
               "skipped",
               "failed",
               "warnings",
               "security_id",
               "fund_document_id"
             ])
  end

  test "confirmation can be repeated idempotently" do
    security = create_security("CONFIRM-IDEMP")

    assert {:ok, preview} =
             FactsheetAllocationPreview.preview_text(
               @region_text,
               %{"security_id" => security.id}
             )

    assert {:ok, first_summary} = FactsheetAllocationImport.confirm_preview(preview)
    first_allocations = Repo.aggregate(FundAllocation, :count, :id)
    first_items = Repo.aggregate(FundAllocationItem, :count, :id)

    assert {:ok, second_summary} = FactsheetAllocationImport.confirm_preview(preview)

    assert Repo.aggregate(FundAllocation, :count, :id) == first_allocations
    assert Repo.aggregate(FundAllocationItem, :count, :id) == first_items
    assert second_summary["created"]["allocations"] == 0
    assert second_summary["created"]["fund_allocation_items"] == 0
    assert second_summary["skipped"]["allocations"] == first_summary["created"]["allocations"]

    assert second_summary["skipped"]["fund_allocation_items"] ==
             first_summary["created"]["fund_allocation_items"]
  end

  test "confirming duplicate allocation items is deterministic and skipped" do
    security = create_security("CONFIRM-SKIP-ITEM")

    assert {:ok, existing_allocation} =
             Catalog.create_fund_allocation(%{
               security_id: security.id,
               source: "factsheet",
               allocation_type: "region",
               as_of_date: ~D[2026-05-01]
             })

    assert {:ok, _existing_item} =
             Catalog.create_fund_allocation_item(%{
               fund_allocation_id: existing_allocation.id,
               label: "North America",
               weight: Decimal.new("62.5"),
               confidence: Decimal.new("1")
             })

    preview = %{
      "security_id" => security.id,
      "allocations" => [
        %{
          "allocation_type" => "region",
          "as_of_date" => "2026-05-01",
          "items" => [
            %{
              "label" => "North America",
              "weight" => Decimal.new("99.9"),
              "confidence" => Decimal.new("1")
            }
          ]
        }
      ]
    }

    assert {:ok, summary} = FactsheetAllocationImport.confirm_preview(preview)

    assert summary["created"]["fund_allocation_items"] == 0
    assert summary["skipped"]["fund_allocation_items"] == 1
    assert summary["skipped"]["allocations"] == 1

    refreshed_item =
      Repo.get_by!(FundAllocationItem,
        fund_allocation_id: existing_allocation.id,
        label: "North America"
      )

    assert Decimal.equal?(refreshed_item.weight, Decimal.new("62.5"))
  end

  test "preview warnings are preserved in confirmation summary" do
    security = create_security("CONFIRM-WARNINGS")

    preview_text = """
    Regions
    North America 62.5%
    invalid allocation row
    Europe 18.3%
    """

    assert {:ok, preview} =
             FactsheetAllocationPreview.preview_text(preview_text, %{"security_id" => security.id})

    assert Enum.any?(
             preview["warnings"],
             &String.contains?(&1, "Could not parse allocation line")
           )

    assert {:ok, summary} = FactsheetAllocationImport.confirm_preview(preview)

    assert Enum.any?(
             summary["warnings"],
             &String.contains?(&1, "Could not parse allocation line")
           )
  end

  test "preview without allocations writes nothing and returns warning" do
    security = create_security("CONFIRM-NO-ALLOCS")
    before_allocations = Repo.aggregate(FundAllocation, :count, :id)
    before_items = Repo.aggregate(FundAllocationItem, :count, :id)

    assert {:ok, preview} =
             FactsheetAllocationPreview.preview_text("", %{"security_id" => security.id})

    assert {:ok, summary} = FactsheetAllocationImport.confirm_preview(preview)

    assert summary["created"]["allocations"] == 0
    assert summary["created"]["fund_allocation_items"] == 0
    assert summary["skipped"]["allocations"] == 0
    assert summary["skipped"]["fund_allocation_items"] == 0
    assert summary["warnings"] != []

    assert Repo.aggregate(FundAllocation, :count, :id) == before_allocations
    assert Repo.aggregate(FundAllocationItem, :count, :id) == before_items
  end

  test "preview missing security_id returns a clear error and no writes" do
    before_allocations = Repo.aggregate(FundAllocation, :count, :id)
    before_items = Repo.aggregate(FundAllocationItem, :count, :id)

    preview = %{
      "allocations" => [],
      "warnings" => []
    }

    assert {:error, {:missing_security_id, _message}} =
             FactsheetAllocationImport.confirm_preview(preview)

    assert Repo.aggregate(FundAllocation, :count, :id) == before_allocations
    assert Repo.aggregate(FundAllocationItem, :count, :id) == before_items
  end

  test "invalid item weight or missing label is skipped with warning" do
    security = create_security("CONFIRM-INVALID-ITEM")

    preview = %{
      "security_id" => security.id,
      "allocations" => [
        %{
          "allocation_type" => "region",
          "items" => [
            %{"label" => nil, "weight" => Decimal.new("62.5")},
            %{"label" => "Europe", "weight" => "not-a-decimal"},
            %{"label" => "Valid", "weight" => "12.5"}
          ]
        }
      ]
    }

    assert {:ok, summary} = FactsheetAllocationImport.confirm_preview(preview)

    assert summary["created"]["allocations"] == 1
    assert summary["created"]["fund_allocation_items"] == 1
    assert summary["skipped"]["fund_allocation_items"] == 2
    assert Enum.any?(summary["warnings"], &String.contains?(&1, "Invalid allocation item"))
  end

  test "confirmation does not create taxonomy, category assignments, or ledger rows" do
    security = create_security("CONFIRM-NO-SIDE-EFFECTS")

    category_count = Repo.aggregate(Category, :count, :id)
    assignment_count = Repo.aggregate(SecurityCategoryAssignment, :count, :id)
    transaction_count = Repo.aggregate(Transaction, :count, :id)

    assert {:ok, preview} =
             FactsheetAllocationPreview.preview_text(@region_text, %{"security_id" => security.id})

    assert {:ok, _summary} = FactsheetAllocationImport.confirm_preview(preview)

    assert Repo.aggregate(Category, :count, :id) == category_count
    assert Repo.aggregate(SecurityCategoryAssignment, :count, :id) == assignment_count
    assert Repo.aggregate(Transaction, :count, :id) == transaction_count
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
