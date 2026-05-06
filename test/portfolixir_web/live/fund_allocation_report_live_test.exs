defmodule PortfolixirWeb.FundAllocationReportLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.{FundAllocation, FundAllocationItem}
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo
  alias Portfolixir.Taxonomies.Category

  setup do
    Catalog.ensure_mvp_currencies!()
    :ok
  end

  test "fund allocation report lists grouped allocations by security", %{conn: conn} do
    security_alpha = create_security("Allocated Alpha", "ALP")
    security_beta = create_security("Allocated Beta", "BET")

    {:ok, alpha_country} =
      Catalog.create_fund_allocation(%{
        security_id: security_alpha.id,
        source: "manual",
        allocation_type: "country"
      })

    {:ok, alpha_region_nodate} =
      Catalog.create_fund_allocation(%{
        security_id: security_alpha.id,
        source: "factsheet",
        allocation_type: "region"
      })

    {:ok, alpha_region_early} =
      Catalog.create_fund_allocation(%{
        security_id: security_alpha.id,
        source: "factsheet",
        allocation_type: "region",
        as_of_date: ~D[2026-05-01]
      })

    {:ok, alpha_region_late} =
      Catalog.create_fund_allocation(%{
        security_id: security_alpha.id,
        source: "factsheet",
        allocation_type: "region",
        as_of_date: ~D[2026-05-10]
      })

    {:ok, beta_sector} =
      Catalog.create_fund_allocation(%{
        security_id: security_beta.id,
        source: "factsheet",
        allocation_type: "sector"
      })

    {:ok, alpha_country_item} =
      Catalog.create_fund_allocation_item(%{
        fund_allocation_id: alpha_country.id,
        label: "Germany",
        weight: Decimal.new("35.0")
      })

    {:ok, alpha_country_item_low_weight} =
      Catalog.create_fund_allocation_item(%{
        fund_allocation_id: alpha_country.id,
        label: "France",
        weight: Decimal.new("15.0")
      })

    {:ok, alpha_region_nodate_item} =
      Catalog.create_fund_allocation_item(%{
        fund_allocation_id: alpha_region_nodate.id,
        label: "Africa",
        weight: Decimal.new("5.0")
      })

    {:ok, alpha_region_early_item} =
      Catalog.create_fund_allocation_item(%{
        fund_allocation_id: alpha_region_early.id,
        label: "Asia",
        weight: Decimal.new("20.0")
      })

    {:ok, alpha_region_late_item} =
      Catalog.create_fund_allocation_item(%{
        fund_allocation_id: alpha_region_late.id,
        label: "North America",
        weight: Decimal.new("62.5"),
        confidence: Decimal.new("0.85")
      })

    {:ok, beta_sector_item} =
      Catalog.create_fund_allocation_item(%{
        fund_allocation_id: beta_sector.id,
        label: "Health",
        weight: Decimal.new("55.0")
      })

    {:ok, view, html} = live(conn, "/reports/fund-allocations")

    assert has_element?(view, "h1", "Fund allocation report")
    assert has_element?(view, "#nav-reports.app-shell-nav-link.is-active")
    assert has_element?(view, "#nav-reports[href='/reports/fund-allocations']")

    assert has_element?(view, "#fund-allocation-security-#{security_alpha.id}", "Allocated Alpha")
    assert has_element?(view, "#fund-allocation-security-#{security_alpha.id}", "(ALP)")
    assert has_element?(view, "#fund-allocation-security-#{security_beta.id}", "Allocated Beta")
    assert has_element?(view, "#fund-allocation-security-#{security_beta.id}", "(BET)")

    assert has_element?(
             view,
             "#fund-allocation-row-#{alpha_country.id}-#{alpha_country_item.id}",
             "35.0%"
           )

    assert has_element?(
             view,
             "#fund-allocation-row-#{alpha_country.id}-#{alpha_country_item_low_weight.id}",
             "15.0%"
           )

    assert has_element?(
             view,
             "#fund-allocation-row-#{alpha_region_late.id}-#{alpha_region_late_item.id}",
             "62.5%"
           )

    assert has_element?(
             view,
             "#fund-allocation-row-#{alpha_region_late.id}-#{alpha_region_late_item.id}",
             "factsheet"
           )

    assert has_element?(
             view,
             "#fund-allocation-row-#{alpha_region_late.id}-#{alpha_region_late_item.id}",
             "0.85%"
           )

    assert has_element?(
             view,
             "#fund-allocation-row-#{beta_sector.id}-#{beta_sector_item.id}",
             "sector"
           )

    alpha_country_row =
      :binary.match(html, "fund-allocation-row-#{alpha_country.id}-#{alpha_country_item.id}")
      |> elem(0)

    alpha_region_late_row =
      :binary.match(
        html,
        "fund-allocation-row-#{alpha_region_late.id}-#{alpha_region_late_item.id}"
      )
      |> elem(0)

    alpha_region_early_row =
      :binary.match(
        html,
        "fund-allocation-row-#{alpha_region_early.id}-#{alpha_region_early_item.id}"
      )
      |> elem(0)

    alpha_region_nodate_row =
      :binary.match(
        html,
        "fund-allocation-row-#{alpha_region_nodate.id}-#{alpha_region_nodate_item.id}"
      )
      |> elem(0)

    assert alpha_country_row < alpha_region_late_row
    assert alpha_region_late_row < alpha_region_early_row
    assert alpha_region_early_row < alpha_region_nodate_row

    alpha_section_index =
      :binary.match(html, "fund-allocation-security-#{security_alpha.id}")
      |> elem(0)

    beta_section_index =
      :binary.match(html, "fund-allocation-security-#{security_beta.id}")
      |> elem(0)

    assert alpha_section_index < beta_section_index

    assert has_element?(
             view,
             "#fund-allocation-row-#{alpha_country.id}-#{alpha_country_item.id}",
             "country"
           )

    assert has_element?(
             view,
             "#fund-allocation-row-#{alpha_region_late.id}-#{alpha_region_late_item.id}",
             "region"
           )

    assert has_element?(
             view,
             "#fund-allocation-row-#{alpha_region_late.id}-#{alpha_region_late_item.id}",
             "2026-05-10"
           )

    assert has_element?(
             view,
             "#fund-allocation-row-#{alpha_region_nodate.id}-#{alpha_region_nodate_item.id}",
             "—"
           )
  end

  test "fund allocation report shows empty state with factsheet upload link when no allocations exist",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/reports/fund-allocations")

    assert has_element?(view, "#fund-allocation-empty-state")

    assert has_element?(
             view,
             "#fund-allocation-empty-state h2",
             "No confirmed fund allocations yet"
           )

    assert has_element?(
             view,
             "#fund-allocation-empty-state-link[href='/documents/new']",
             "Upload a factsheet"
           )
  end

  test "fund allocation report renders shared toolbar with planned controls", %{conn: conn} do
    security = create_security("Toolbar Security", "TBR")

    {:ok, _allocation} =
      Catalog.create_fund_allocation(%{
        security_id: security.id,
        source: "manual",
        allocation_type: "region"
      })

    {:ok, view, _html} = live(conn, "/reports/fund-allocations")

    assert has_element?(view, "#fund-allocation-workbench-toolbar")

    assert has_element?(
             view,
             "#fund-allocation-toolbar-actions[role='group'][aria-labelledby='fund-allocation-toolbar-actions-label']"
           )

    assert has_element?(view, "#fund-allocation-toolbar-actions-label")

    assert has_element?(
             view,
             "#fund-allocation-toolbar-ranges[role='group'][aria-labelledby='fund-allocation-toolbar-ranges-label']"
           )

    assert has_element?(view, "#fund-allocation-toolbar-ranges-label")
    assert has_element?(view, "#fund-allocation-search")
    assert has_element?(view, "#fund-allocation-toolbar-filter[disabled]")
    assert has_element?(view, "#fund-allocation-toolbar-export[disabled]")
    assert has_element?(view, "#fund-allocation-toolbar-columns[disabled]")
    assert has_element?(view, "#fund-allocation-toolbar-range-1m[disabled]")
    assert has_element?(view, "#fund-allocation-toolbar-range-3m[disabled]")
    assert has_element?(view, "#fund-allocation-toolbar-range-6m[disabled]")
    assert has_element?(view, "#fund-allocation-toolbar-range-1y[disabled]")
    assert has_element?(view, "#fund-allocation-toolbar-range-ytd[disabled]")
    assert has_element?(view, "#fund-allocation-toolbar-range-all[disabled]")
  end

  test "report route is read-only and does not create allocations, items, categories, or ledger rows",
       %{conn: conn} do
    security = create_security("Immutable Report", "IMM")

    {:ok, allocation} =
      Catalog.create_fund_allocation(%{
        security_id: security.id,
        source: "manual",
        allocation_type: "asset_class"
      })

    {:ok, _item} =
      Catalog.create_fund_allocation_item(%{
        fund_allocation_id: allocation.id,
        label: "Core",
        weight: Decimal.new("1.0")
      })

    before_allocation_count = Repo.aggregate(FundAllocation, :count, :id)
    before_item_count = Repo.aggregate(FundAllocationItem, :count, :id)
    before_category_count = Repo.aggregate(Category, :count, :id)
    before_transaction_count = Repo.aggregate(Transaction, :count, :id)

    {:ok, _view, _html} = live(conn, "/reports/fund-allocations")

    assert Repo.aggregate(FundAllocation, :count, :id) == before_allocation_count
    assert Repo.aggregate(FundAllocationItem, :count, :id) == before_item_count
    assert Repo.aggregate(Category, :count, :id) == before_category_count
    assert Repo.aggregate(Transaction, :count, :id) == before_transaction_count
  end

  test "existing dashboard and securities routes still work", %{conn: conn} do
    {:ok, dashboard_view, _html} = live(conn, "/")
    assert has_element?(dashboard_view, "h1", "Dashboard")

    {:ok, securities_view, _html} = live(conn, "/securities")
    assert has_element?(securities_view, "h1", "All Securities")
  end

  defp create_security(name, symbol) do
    {:ok, security} =
      Catalog.create_security(%{
        name: name,
        symbol: symbol,
        currency_code: "USD"
      })

    security
  end
end
