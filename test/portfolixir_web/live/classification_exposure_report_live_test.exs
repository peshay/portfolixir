defmodule PortfolixirWeb.ClassificationExposureReportLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo
  alias Portfolixir.Taxonomies
  alias Portfolixir.Catalog.SecurityCategoryAssignment

  setup do
    Catalog.ensure_mvp_currencies!()
    {:ok, portfolio} = Portfolios.create_portfolio(%{name: "Main", base_currency_code: "EUR"})

    {:ok, deposit_account} =
      Portfolios.create_deposit_account(%{
        portfolio_id: portfolio.id,
        name: "Cash",
        currency_code: "EUR"
      })

    {:ok, securities_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        name: "Depot",
        currency_code: "EUR",
        reference_deposit_account_id: deposit_account.id
      })

    %{
      portfolio: portfolio,
      deposit_account: deposit_account,
      securities_account: securities_account
    }
  end

  test "renders empty state when no positions exist", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/reports/classification-exposure")

    assert has_element?(
             view,
             "#classification-exposure-empty-state[role='status'][aria-live='polite'][aria-labelledby='classification-exposure-empty-state-status-title'][aria-describedby='classification-exposure-empty-state-status-description']"
           )

    assert has_element?(
             view,
             "#classification-exposure-empty-state-title",
             "No classification exposure data yet"
           )

    assert has_element?(
             view,
             "#classification-exposure-empty-state-description",
             "Add positions and category mappings to populate this report."
           )

    assert has_element?(
             view,
             "#classification-exposure-empty-state-status-title.app-shell-visually-hidden",
             "No classification exposure data yet"
           )

    assert has_element?(
             view,
             "#classification-exposure-empty-state-status-description.app-shell-visually-hidden",
             "Add positions and category mappings to populate this report."
           )
  end

  test "direct and weighted mappings contribute to exposure report", %{
    conn: conn,
    portfolio: portfolio,
    securities_account: securities_account
  } do
    {:ok, stock} =
      Catalog.create_security(%{name: "Stock A", symbol: "STA", currency_code: "EUR"})

    {:ok, fund} = Catalog.create_security(%{name: "Fund B", symbol: "FDB", currency_code: "EUR"})

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: stock.id,
        type: "buy",
        date: ~D[2026-01-10],
        currency_code: "EUR",
        quantity: Decimal.new("10"),
        price: Decimal.new("10"),
        amount: Decimal.new("100")
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: fund.id,
        type: "buy",
        date: ~D[2026-01-11],
        currency_code: "EUR",
        quantity: Decimal.new("5"),
        price: Decimal.new("20"),
        amount: Decimal.new("100")
      })

    {:ok, _} =
      Catalog.create_security_quote(%{
        security_id: stock.id,
        source: "test",
        date: ~D[2026-01-12],
        close: Decimal.new("12"),
        currency_code: "EUR"
      })

    {:ok, _} =
      Catalog.create_security_quote(%{
        security_id: fund.id,
        source: "test",
        date: ~D[2026-01-12],
        close: Decimal.new("20"),
        currency_code: "EUR"
      })

    {:ok, taxonomy} = Taxonomies.create_taxonomy(%{name: "Exposure"})
    {:ok, core} = Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Core"})
    {:ok, growth} = Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Growth"})

    {:ok, _} = Catalog.assign_category_to_security(stock.id, core.id)

    {:ok, allocation} =
      Catalog.create_fund_allocation(%{
        security_id: fund.id,
        source: "factsheet",
        allocation_type: "region",
        status: "active"
      })

    {:ok, _} =
      Catalog.create_fund_allocation_item(%{
        fund_allocation_id: allocation.id,
        label: "Europe",
        weight: Decimal.new("60")
      })

    {:ok, _} =
      Catalog.create_fund_allocation_item(%{
        fund_allocation_id: allocation.id,
        label: "Unmapped Region",
        weight: Decimal.new("40")
      })

    {:ok, _} =
      Taxonomies.upsert_fund_allocation_category_mapping(%{
        allocation_type: "region",
        source_label: "Europe",
        taxonomy_id: taxonomy.id,
        category_id: growth.id
      })

    {:ok, view, html} = live(conn, "/reports/classification-exposure")

    assert html =~ ~r/<th scope="col">Category<\/th>/
    assert html =~ ~r/<th scope="col">Exposure<\/th>/

    assert has_element?(
             view,
             "#classification-exposure-table[aria-describedby='classification-exposure-table-caption']"
           )

    assert has_element?(
             view,
             "#classification-exposure-table-caption.app-shell-visually-hidden",
             "Classification exposure report table with category, exposure, weight, and source securities."
           )

    assert has_element?(view, "#classification-exposure-sunburst-chart")

    assert has_element?(
             view,
             "#classification-exposure-sunburst[aria-labelledby='classification-exposure-sunburst-heading'][aria-describedby='classification-exposure-sunburst-description']"
           )

    assert has_element?(view, "#classification-exposure-sunburst-heading", "Sunburst")

    assert has_element?(
             view,
             "#classification-exposure-sunburst-description",
             "Read-only chart view based on the current classification exposure rows."
           )

    assert has_element?(view, "#classification-exposure-row-core", "Core")
    assert has_element?(view, "#classification-exposure-row-growth", "Growth")
    assert has_element?(view, "#classification-exposure-row-unmapped", "Unmapped")
    assert has_element?(view, "#classification-exposure-row-core", "Stock A")
    assert has_element?(view, "#classification-exposure-row-growth", "Fund B")

    assert has_element?(
             view,
             "#classification-exposure-sunburst-hierarchy",
             "Classification exposure"
           )

    assert has_element?(view, "#classification-exposure-sunburst-hierarchy", "Core")
    assert has_element?(view, "#classification-exposure-sunburst-hierarchy", "Growth")

    assert has_element?(
             view,
             "#classification-exposure-drilldown[aria-labelledby='classification-exposure-drilldown-heading'][aria-describedby='classification-exposure-drilldown-description']"
           )

    assert has_element?(
             view,
             "#classification-exposure-drilldown-heading",
             "Category drilldown details"
           )

    assert has_element?(
             view,
             "#classification-exposure-drilldown-description",
             "Read-only detail view from the existing classification exposure rows."
           )

    assert has_element?(
             view,
             "#classification-exposure-drilldown-empty[role='status'][aria-live='polite'][aria-labelledby='classification-exposure-drilldown-empty-status-title'][aria-describedby='classification-exposure-drilldown-empty-status-description']"
           )

    assert has_element?(
             view,
             "#classification-exposure-drilldown-empty-title",
             "No category selected"
           )

    assert has_element?(
             view,
             "#classification-exposure-drilldown-empty-description",
             "Select a category row to inspect direct-assignment and weighted-allocation source details."
           )

    assert has_element?(
             view,
             "#classification-exposure-drilldown-empty-status-title.app-shell-visually-hidden",
             "No category selected"
           )

    assert has_element?(
             view,
             "#classification-exposure-drilldown-empty-status-description.app-shell-visually-hidden",
             "Select a category row to inspect direct-assignment and weighted-allocation source details."
           )

    view
    |> element("#classification-exposure-select-core")
    |> render_click()

    rendered = render(view)
    assert rendered =~ ~r/<th scope="row" data-column-key="category">/
    assert rendered =~ ~r/<th scope="col">Source<\/th>/

    assert has_element?(view, "#classification-exposure-drilldown-summary", "Core")

    assert has_element?(
             view,
             "#classification-exposure-drilldown-detail-table[aria-describedby='classification-exposure-drilldown-detail-table-caption']",
             "Direct assignment"
           )

    assert has_element?(
             view,
             "#classification-exposure-drilldown-detail-table-caption.app-shell-visually-hidden",
             "Category drilldown detail table for Core with source type, status, security, input, exposure, and note rows."
           )

    assert has_element?(
             view,
             "#classification-exposure-drilldown-detail-table",
             "Direct category assignment"
           )

    assert has_element?(view, "#classification-exposure-drilldown-detail-table", "Stock A")

    view
    |> element("#classification-exposure-select-growth")
    |> render_click()

    assert has_element?(view, "#classification-exposure-drilldown-summary", "Growth")

    assert has_element?(
             view,
             "#classification-exposure-drilldown-detail-table",
             "Weighted allocation"
           )

    assert has_element?(view, "#classification-exposure-drilldown-detail-table", "region: Europe")
    assert has_element?(view, "#classification-exposure-drilldown-detail-table", "Fund B")

    view
    |> element("#classification-exposure-select-unmapped")
    |> render_click()

    assert has_element?(view, "#classification-exposure-drilldown-summary", "Unmapped")
    assert has_element?(view, "#classification-exposure-drilldown-detail-table", "Unmapped")
    assert has_element?(view, "#classification-exposure-drilldown-detail-table", "Unknown")

    assert has_element?(
             view,
             "#classification-exposure-drilldown-detail-table",
             "region: Unmapped Region"
           )

    assert has_element?(
             view,
             "#classification-exposure-drilldown-detail-table",
             "No category mapping"
           )

    rendered_unmapped = render(view)
    assert :binary.match(rendered_unmapped, "region: Unmapped Region") != :nomatch
    assert :binary.match(rendered_unmapped, "No category mapping") != :nomatch

    {unmapped_input_index, _} = :binary.match(rendered_unmapped, "region: Unmapped Region")
    {unmapped_note_index, _} = :binary.match(rendered_unmapped, "No category mapping")
    assert unmapped_input_index < unmapped_note_index

    view
    |> element("#classification-exposure-drilldown-clear")
    |> render_click()

    assert has_element?(
             view,
             "#classification-exposure-drilldown-empty[role='status'][aria-live='polite'][aria-labelledby='classification-exposure-drilldown-empty-status-title'][aria-describedby='classification-exposure-drilldown-empty-status-description']"
           )

    assert has_element?(
             view,
             "#classification-exposure-drilldown-empty-title",
             "No category selected"
           )

    assert has_element?(
             view,
             "#classification-exposure-drilldown-empty-description",
             "Select a category row to inspect direct-assignment and weighted-allocation source details."
           )

    assert has_element?(
             view,
             "#classification-exposure-drilldown-empty-status-title.app-shell-visually-hidden",
             "No category selected"
           )

    assert has_element?(
             view,
             "#classification-exposure-drilldown-empty-status-description.app-shell-visually-hidden",
             "Select a category row to inspect direct-assignment and weighted-allocation source details."
           )
  end

  test "missing quote fallback stays explicit and does not distort percentages", %{
    conn: conn,
    portfolio: portfolio,
    securities_account: securities_account
  } do
    {:ok, valued} =
      Catalog.create_security(%{name: "Valued", symbol: "VAL", currency_code: "EUR"})

    {:ok, unquoted} =
      Catalog.create_security(%{name: "Unquoted", symbol: "UNQ", currency_code: "EUR"})

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: valued.id,
        type: "buy",
        date: ~D[2026-01-10],
        currency_code: "EUR",
        quantity: Decimal.new("10"),
        price: Decimal.new("10"),
        amount: Decimal.new("100")
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: unquoted.id,
        type: "buy",
        date: ~D[2026-01-11],
        currency_code: "EUR",
        quantity: Decimal.new("5"),
        price: Decimal.new("10"),
        amount: Decimal.new("50")
      })

    {:ok, _} =
      Catalog.create_security_quote(%{
        security_id: valued.id,
        source: "test",
        date: ~D[2026-01-12],
        close: Decimal.new("12"),
        currency_code: "EUR"
      })

    {:ok, taxonomy} = Taxonomies.create_taxonomy(%{name: "Fallback"})
    {:ok, core} = Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Core"})
    {:ok, satellite} = Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Satellite"})

    {:ok, _} = Catalog.assign_category_to_security(valued.id, core.id)
    {:ok, _} = Catalog.assign_category_to_security(unquoted.id, satellite.id)

    {:ok, view, _html} = live(conn, "/reports/classification-exposure")

    assert has_element?(view, "#classification-exposure-row-core", "120.00 EUR")
    assert has_element?(view, "#classification-exposure-row-core", "100.00%")
    assert has_element?(view, "#classification-exposure-row-satellite", "Valuation unavailable")

    assert has_element?(
             view,
             "#classification-exposure-warnings",
             "missing_quote_fallback_quantity"
           )
  end

  test "viewing report does not create security category assignments", %{conn: conn} do
    assignments_before = Repo.aggregate(SecurityCategoryAssignment, :count, :id)

    {:ok, _view, _html} = live(conn, "/reports/classification-exposure")

    assert Repo.aggregate(SecurityCategoryAssignment, :count, :id) == assignments_before
  end
end
