defmodule Portfolixir.Imports.PortfolioPerformanceXmlImportTest do
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Imports.PortfolioPerformanceXmlImport
  alias Portfolixir.Imports.{ImportConflict, ImportRun, ImportSource, RawImportItem}
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Taxonomies.Taxonomy
  alias Portfolixir.Taxonomies.Category
  alias Portfolixir.Repo

  @source_name "Portfolio Performance XML"
  @source_type "pp_xml"

  setup do
    cleanup_import_test_data()

    on_exit(fn ->
      run_cleanup_outside_sandbox()
    end)

    :ok
  end

  defp cleanup_import_test_data do
    Repo.delete_all(
      from(
        i in RawImportItem,
        join: s in ImportSource,
        on: i.import_source_id == s.id,
        where: s.name == @source_name and s.type == @source_type
      )
    )

    Repo.delete_all(
      from(c in ImportConflict,
        join: s in ImportSource,
        on: c.import_source_id == s.id,
        where: s.name == @source_name and s.type == @source_type
      )
    )

    Repo.delete_all(
      from(i in ImportRun,
        join: s in ImportSource,
        on: i.import_source_id == s.id,
        where: s.name == @source_name and s.type == @source_type
      )
    )

    Repo.delete_all(
      from(s in ImportSource, where: s.name == @source_name and s.type == @source_type)
    )

    Repo.delete_all(from(t in Transaction, where: t.notes == "pp_import:txn-synthetic-1"))

    Repo.delete_all(
      from(a in Portfolixir.Portfolios.DepositAccount, where: a.name == "Synthetic Cash Account")
    )

    Repo.delete_all(from(p in Portfolio, where: p.name == "Synthetic Portfolio"))

    security_ids =
      from(s in Portfolixir.Catalog.Security, where: s.name == "Synthetic ETF", select: s.id)

    Repo.delete_all(
      from(a in Portfolixir.Catalog.SecurityCategoryAssignment,
        where: a.security_id in subquery(security_ids)
      )
    )

    Repo.delete_all(from(s in Portfolixir.Catalog.Security, where: s.name == "Synthetic ETF"))
    Repo.delete_all(from(c in Category, where: c.name == "Core ETF"))
    Repo.delete_all(from(t in Taxonomy, where: t.name == "Strategy"))
  end

  defp run_cleanup_outside_sandbox do
    task =
      Task.async(fn ->
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
        cleanup_import_test_data()
        :ok = Ecto.Adapters.SQL.Sandbox.checkin(Repo)
      end)

    Task.await(task)
  end

  @fixture_path Path.expand(
                  "../../support/fixtures/portfolio_performance/synthetic_pp_preview.xml",
                  __DIR__
                )
  @unsafe_doctype "<!DOCTYPE portfolioReport><portfolioReport><portfolio id=\"1\" /></portfolioReport>"
  @unsafe_entity "<!DOCTYPE portfolioReport [<!ENTITY ext SYSTEM \"http://example.com/evil.xml\">]]>\n<portfolioReport><portfolio id=\"1\" /></portfolioReport>"

  defp fixture_xml do
    File.read!(@fixture_path)
  end

  defp do_import do
    PortfolioPerformanceXmlImport.confirm(fixture_xml())
  end

  test "confirm returns summary with deterministic top-level keys" do
    assert {:ok, summary} = do_import()

    assert MapSet.new(Map.keys(summary)) ==
             MapSet.new(["created", "updated", "skipped", "failed", "warnings", "import_run_id"])

    assert is_map(summary["created"])
    assert is_map(summary["updated"])
    assert is_map(summary["skipped"])
    assert is_map(summary["failed"])
    assert is_list(summary["warnings"])
    assert is_integer(summary["import_run_id"])
  end

  test "confirm creates or reuses the Portfolio Performance XML import source" do
    initial_import_sources = Repo.aggregate(ImportSource, :count, :id)

    assert {:ok, summary} = do_import()
    assert Repo.aggregate(ImportSource, :count, :id) == initial_import_sources + 1

    run = Repo.get!(ImportRun, summary["import_run_id"])
    source = Repo.get!(ImportSource, run.import_source_id)

    assert source.name == "Portfolio Performance XML"
    assert source.type == "pp_xml"
    assert source.status == "active"

    assert {:ok, _summary_retry} = do_import()
    assert Repo.aggregate(ImportSource, :count, :id) == 1
  end

  test "confirm creates an import run" do
    initial_import_runs = Repo.aggregate(ImportRun, :count, :id)
    currencies_before = Repo.aggregate(Portfolixir.Catalog.Currency, :count, :code)

    assert {:ok, summary} = do_import()
    run = Repo.get!(ImportRun, summary["import_run_id"])

    assert run.import_source_id ==
             Repo.get_by!(ImportSource, name: "Portfolio Performance XML", type: "pp_xml").id

    assert run.status == "completed"
    assert run.summary["created"]["currencies"] >= 0
    assert Repo.aggregate(ImportRun, :count, :id) == initial_import_runs + 1

    assert Repo.get_by!(Portfolixir.Catalog.Currency, code: "USD") != nil
    assert Repo.aggregate(Portfolixir.Catalog.Currency, :count, :code) >= currencies_before
  end

  test "confirm creates raw import items using external ids and content hashes" do
    initial_raw_items = Repo.aggregate(RawImportItem, :count, :id)

    assert {:ok, summary} = do_import()
    run_id = summary["import_run_id"]
    assert summary["created"]["raw_items"] >= 6

    assert Repo.aggregate(RawImportItem, :count, :id) ==
             initial_raw_items + summary["created"]["raw_items"]

    items = Repo.all(RawImportItem)
    assert Enum.all?(items, &(&1.import_run_id == run_id))
    assert Enum.all?(items, fn item -> item.external_id || item.content_hash end)

    assert {:ok, _second_summary} = do_import()
    assert Repo.aggregate(RawImportItem, :count, :id) == summary["created"]["raw_items"]
  end

  test "confirm persists one synthetic portfolio" do
    initial_portfolios = Repo.aggregate(Portfolio, :count, :id)

    assert {:ok, _} = do_import()

    assert Repo.aggregate(Portfolio, :count, :id) == initial_portfolios + 1
    portfolio = Repo.get_by!(Portfolio, name: "Synthetic Portfolio")
    assert portfolio.base_currency_code == "USD"
  end

  test "confirm persists one synthetic security" do
    assert {:ok, _} = do_import()

    security = Repo.get_by!(Portfolixir.Catalog.Security, name: "Synthetic ETF")
    assert security.symbol == "COREETF"
    assert security.currency_code == "USD"
  end

  test "confirm persists one synthetic deposit account" do
    initial_accounts = Repo.aggregate(Portfolixir.Portfolios.DepositAccount, :count, :id)

    assert {:ok, _} = do_import()

    assert Repo.aggregate(Portfolixir.Portfolios.DepositAccount, :count, :id) ==
             initial_accounts + 1

    deposit_account =
      Repo.get_by!(Portfolixir.Portfolios.DepositAccount, name: "Synthetic Cash Account")

    assert deposit_account.currency_code == "USD"
  end

  test "confirm persists one ledger transaction from the synthetic PP transaction" do
    initial_transactions = Repo.aggregate(Transaction, :count, :id)

    assert {:ok, _} = do_import()

    assert Repo.aggregate(Transaction, :count, :id) == initial_transactions + 1

    transaction = Repo.one!(from(transaction in Transaction, order_by: [asc: transaction.id]))
    assert transaction.type in ["deposit", "withdrawal"]
    assert transaction.date == ~D[2026-01-10]
    assert Decimal.equal?(transaction.amount, Decimal.new("1000.00"))
    assert transaction.currency_code == "USD"
  end

  test "confirm persists taxonomy and category when APIs are usable" do
    initial_taxonomies = Repo.aggregate(Taxonomy, :count, :id)
    initial_categories = Repo.aggregate(Category, :count, :id)

    assert {:ok, _} = do_import()

    assert Repo.aggregate(Taxonomy, :count, :id) >= initial_taxonomies + 1
    assert Repo.aggregate(Category, :count, :id) >= initial_categories + 1
    taxonomy = Repo.get_by!(Taxonomy, name: "Strategy")
    assert Repo.get_by!(Category, taxonomy_id: taxonomy.id, name: "Core ETF")
  end

  test "category create failures preserve summary counters and warnings" do
    preview = %{
      "taxonomies" => [
        %{
          "external_id" => "taxonomy-invalid-category",
          "name" => "Strategy"
        }
      ],
      "categories" => [
        %{
          "external_id" => "category-invalid-name",
          "name" => nil,
          "taxonomy_external_id" => "taxonomy-invalid-category"
        }
      ]
    }

    assert {:ok, summary} = PortfolioPerformanceXmlImport.confirm_preview(preview)
    assert summary["failed"]["categories"] == 1

    assert Enum.any?(
             summary["warnings"],
             &String.contains?(&1, "Could not create category")
           )
  end

  test "confirm is idempotent for repeated confirmation calls" do
    assert {:ok, _summary} = do_import()
    first_portfolios = Repo.aggregate(Portfolio, :count, :id)
    first_securities = Repo.aggregate(Portfolixir.Catalog.Security, :count, :id)
    first_accounts = Repo.aggregate(Portfolixir.Portfolios.DepositAccount, :count, :id)
    first_transactions = Repo.aggregate(Transaction, :count, :id)
    first_raw_items = Repo.aggregate(RawImportItem, :count, :id)
    first_runs = Repo.aggregate(ImportRun, :count, :id)

    assert {:ok, _second_summary} = do_import()

    assert Repo.aggregate(Portfolio, :count, :id) == first_portfolios
    assert Repo.aggregate(Portfolixir.Catalog.Security, :count, :id) == first_securities
    assert Repo.aggregate(Portfolixir.Portfolios.DepositAccount, :count, :id) == first_accounts
    assert Repo.aggregate(Transaction, :count, :id) == first_transactions
    assert Repo.aggregate(RawImportItem, :count, :id) == first_raw_items
    assert Repo.aggregate(ImportRun, :count, :id) == first_runs + 1
  end

  test "malformed XML returns an error and does not persist domain rows" do
    initial_portfolios = Repo.aggregate(Portfolio, :count, :id)
    initial_securities = Repo.aggregate(Portfolixir.Catalog.Security, :count, :id)
    initial_accounts = Repo.aggregate(Portfolixir.Portfolios.DepositAccount, :count, :id)
    initial_raw_runs = Repo.aggregate(ImportRun, :count, :id)
    initial_transactions = Repo.aggregate(Transaction, :count, :id)

    assert {:error, {:invalid_xml, _}} =
             PortfolioPerformanceXmlImport.confirm("<portfolioReport><missing></portfolioReport>")

    assert Repo.aggregate(Portfolio, :count, :id) == initial_portfolios
    assert Repo.aggregate(Portfolixir.Catalog.Security, :count, :id) == initial_securities
    assert Repo.aggregate(Portfolixir.Portfolios.DepositAccount, :count, :id) == initial_accounts
    assert Repo.aggregate(Portfolixir.Portfolios.Portfolio, :count, :id) == initial_portfolios
    assert Repo.aggregate(Transaction, :count, :id) == initial_transactions
    assert Repo.aggregate(ImportRun, :count, :id) == initial_raw_runs
  end

  test "unsafe doctype XML is rejected" do
    assert {:error, {:unsafe_xml, _}} = PortfolioPerformanceXmlImport.confirm(@unsafe_doctype)
  end

  test "external entity declarations are rejected" do
    assert {:error, {:unsafe_xml, _}} = PortfolioPerformanceXmlImport.confirm(@unsafe_entity)
  end

  test "confirm accepts a preview map" do
    assert {:ok, preview} =
             Portfolixir.Imports.PortfolioPerformanceXmlPreview.preview(fixture_xml())

    assert {:ok, summary} = PortfolioPerformanceXmlImport.confirm_preview(preview)
    assert is_map(summary)
  end

  test "confirm persists transaction conflicts for missing mapped security references" do
    assert {:ok, preview} =
             Portfolixir.Imports.PortfolioPerformanceXmlPreview.preview(fixture_xml())

    [first_transaction | remaining_transactions] = Map.fetch!(preview, "transactions")

    conflict_preview =
      Map.put(preview, "transactions", [
        Map.put(first_transaction, "security_reference_id", "sec-missing")
        | remaining_transactions
      ])

    assert {:ok, summary} = PortfolioPerformanceXmlImport.confirm_preview(conflict_preview)

    run_id = summary["import_run_id"]

    conflicts =
      Repo.all(
        from(c in ImportConflict,
          where: c.import_run_id == ^run_id,
          order_by: [asc: c.id]
        )
      )

    assert Enum.any?(conflicts, fn conflict ->
             conflict.conflict_type == "missing_security" and
               conflict.summary =~ "Transaction conflict" and
               is_map(conflict.details)
           end)
  end
end
