defmodule Portfolixir.Imports.PortfolioPerformanceXmlPreviewTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Imports.PortfolioPerformanceXmlPreview
  alias Portfolixir.Imports.RawImportItem
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  @fixture_path Path.expand(
                  "../../support/fixtures/portfolio_performance/synthetic_pp_preview.xml",
                  __DIR__
                )

  defp fixture_xml do
    File.read!(@fixture_path)
  end

  test "preview parses a synthetic Portfolio Performance XML fixture" do
    assert {:ok, preview} = PortfolioPerformanceXmlPreview.preview(fixture_xml())
    assert is_map(preview)
    assert Map.has_key?(preview, "securities")
  end

  test "preview returns stable top-level keys" do
    assert {:ok, preview} = PortfolioPerformanceXmlPreview.preview(fixture_xml())

    assert Map.keys(preview) |> MapSet.new() ==
             MapSet.new([
               "securities",
               "accounts",
               "portfolios",
               "transactions",
               "taxonomies",
               "categories",
               "warnings",
               "counts"
             ])
  end

  test "preview extracts at least one security" do
    assert {:ok, preview} = PortfolioPerformanceXmlPreview.preview(fixture_xml())

    assert length(preview["securities"]) == 1

    security = hd(preview["securities"])
    assert security["external_id"] == "security-synthetic-etf-1"
    assert security["name"] == "Synthetic ETF"
    assert security["isin"] == "US0000000001"
    assert security["ticker"] == "COREETF"
    assert security["currency"] == "USD"
  end

  test "preview extracts at least one account" do
    assert {:ok, preview} = PortfolioPerformanceXmlPreview.preview(fixture_xml())

    assert length(preview["accounts"]) == 1

    account = hd(preview["accounts"])
    assert account["external_id"] == "account-cash-1"
    assert account["name"] == "Synthetic Cash Account"
    assert account["currency"] == "USD"
    assert account["type"] == "cash"
  end

  test "preview extracts portfolio and base currency" do
    assert {:ok, preview} = PortfolioPerformanceXmlPreview.preview(fixture_xml())

    assert length(preview["portfolios"]) == 1

    portfolio = hd(preview["portfolios"])
    assert portfolio["name"] == "Synthetic Portfolio"
    assert portfolio["base_currency"] == "USD"
  end

  test "preview extracts at least one normalized-like transaction" do
    assert {:ok, preview} = PortfolioPerformanceXmlPreview.preview(fixture_xml())

    assert length(preview["transactions"]) == 1

    transaction = hd(preview["transactions"])
    assert transaction["external_id"] == "txn-synthetic-1"
    assert transaction["type"] == "BUY"
    assert transaction["date"] == "2026-01-10"
    assert transaction["amount"] == "1000.00"
    assert transaction["currency"] == "USD"
    assert transaction["security_reference_id"] == "security-synthetic-etf-1"
    assert transaction["account_reference_id"] == "account-cash-1"
  end

  test "preview extracts taxonomies and categories" do
    assert {:ok, preview} = PortfolioPerformanceXmlPreview.preview(fixture_xml())

    assert length(preview["taxonomies"]) == 1
    assert length(preview["categories"]) == 1

    taxonomy = hd(preview["taxonomies"])
    assert taxonomy["external_id"] == "taxonomy-strategy"
    assert taxonomy["name"] == "Strategy"

    category = hd(preview["categories"])
    assert category["external_id"] == "category-core-etf"
    assert category["name"] == "Core ETF"
    assert category["taxonomy_external_id"] == "taxonomy-strategy"
  end

  test "preview counts match extracted collections" do
    assert {:ok, preview} = PortfolioPerformanceXmlPreview.preview(fixture_xml())

    assert preview["counts"] == %{
             "securities" => length(preview["securities"]),
             "accounts" => length(preview["accounts"]),
             "portfolios" => length(preview["portfolios"]),
             "transactions" => length(preview["transactions"]),
             "taxonomies" => length(preview["taxonomies"]),
             "categories" => length(preview["categories"])
           }
  end

  test "malformed XML returns an error tuple" do
    assert {:error, {:invalid_xml, _reason}} =
             PortfolioPerformanceXmlPreview.preview(
               "<portfolioReport><missing></portfolioReport>"
             )
  end

  test "doctype XML is rejected" do
    assert {
             :error,
             {:unsafe_xml, "DOCTYPE declarations are not allowed in preview."}
           } =
             PortfolioPerformanceXmlPreview.preview(
               "<!DOCTYPE portfolioReport><portfolioReport><portfolio id=\"1\" /></portfolioReport>"
             )
  end

  test "external entity declaration is rejected" do
    assert {
             :error,
             {:unsafe_xml, _}
           } =
             PortfolioPerformanceXmlPreview.preview(
               "<!DOCTYPE portfolioReport [<!ENTITY ext SYSTEM \"http://example.com/evil.xml\">]]>\n<portfolioReport><portfolio id=\"1\" /></portfolioReport>"
             )
  end

  test "preview does not create raw import items" do
    initial_count = Repo.aggregate(RawImportItem, :count, :id)

    assert {:ok, _preview} = PortfolioPerformanceXmlPreview.preview(fixture_xml())

    assert Repo.aggregate(RawImportItem, :count, :id) == initial_count
  end

  test "preview does not create ledger transactions" do
    existing_count = Repo.aggregate(Transaction, :count, :id)

    assert {:ok, _preview} = PortfolioPerformanceXmlPreview.preview(fixture_xml())

    assert Repo.aggregate(Transaction, :count, :id) == existing_count
  end
end
