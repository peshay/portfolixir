defmodule PortfolixirWeb.SecurityManagementLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Repo

  setup do
    Catalog.ensure_mvp_currencies!()
    :ok
  end

  test "visiting / renders dashboard content", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Dashboard"
    assert html =~ "Securities"
    assert html =~ "Transactions"
    refute html =~ "No securities yet"
  end

  test "visiting /securities renders All Securities", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/securities")

    assert html =~ "All Securities"
  end

  test "security form uses a seeded currency select with EUR selected by default", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/securities")
    view |> element("#security-add-toggle") |> render_click()

    assert has_element?(
             view,
             "select#security-currency-code[name='security[currency_code]'] option[value='EUR'][selected]"
           )

    assert has_element?(view, "select#security-currency-code option[value='USD']", "USD")
    assert has_element?(view, "select#security-active option[value='true'][selected]")
    refute has_element?(view, "input#security-currency-code")

    html =
      view
      |> form("#security-form", %{
        "security" => %{
          "name" => "Synthetic EUR ETF",
          "symbol" => "SEUR",
          "currency_code" => "EUR"
        }
      })
      |> render_submit()

    assert html =~ "Security added."
    assert html =~ "Synthetic EUR ETF"
    assert html =~ "EUR"
  end

  test "All Securities page includes a working Export CSV action", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(
             view,
             "a#security-export-csv[href='/securities/export.csv']",
             "Export CSV"
           )
  end

  test "security table column menu renders with stable column keys and local storage script", %{
    conn: conn
  } do
    {:ok, view, html} = live(conn, "/securities")

    assert has_element?(view, "#security-column-menu")
    assert has_element?(view, "#security-column-menu-button[aria-label]")

    assert has_element?(
             view,
             "#security-column-menu-button[aria-controls='security-column-form']"
           )

    assert has_element?(
             view,
             "#security-column-form[aria-labelledby='security-column-menu-legend']"
           )

    assert has_element?(view, "#security-column-menu-legend", "Visible columns")
    assert has_element?(view, "#security-column-name[value='name'][disabled]")
    assert has_element?(view, "#security-column-symbol[value='symbol']")
    assert has_element?(view, "#security-column-provider_symbol[value='provider_symbol']")
    assert has_element?(view, "#security-column-latest_quote[value='latest_quote']")
    assert has_element?(view, "#security-column-latest_quote_date[value='latest_quote_date']")
    assert has_element?(view, "#security-column-position_quantity[value='position_quantity']")
    assert has_element?(view, "#security-column-actions[value='actions'][disabled]")
    assert html =~ "portfolixir.securities.visibleColumns"
    assert html =~ "security-column-preferences-script"
  end

  test "security table renders sensible default columns with stable metadata", %{conn: conn} do
    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Synthetic ETF",
               symbol: "SYN",
               currency_code: "USD",
               isin: "US0000000001",
               wkn: "WKN1",
               provider_symbol: "SYN.US",
               exchange_code: "XNYS"
             })

    {:ok, view, html} = live(conn, "/securities")

    assert has_element?(
             view,
             "#security-list caption",
             "Securities workbench table with identifiers, valuation, status, and row actions."
           )

    assert html =~
             ~r/<th scope="col" id="security-column-header-name" data-column-key="name">Name<\/th>/

    assert html =~
             ~r/<th scope="row" data-column-key="name"><strong>Synthetic ETF<\/strong><\/th>/

    assert has_element?(view, "#security-list th[data-column-key='name']")
    refute has_element?(view, "#security-list td[data-column-key='name']")

    for key <-
          ~w(symbol currency isin wkn latest_quote latest_quote_date position_quantity provider_symbol exchange status actions) do
      assert has_element?(view, "#security-list th[data-column-key='#{key}']")
      assert has_element?(view, "#security-list td[data-column-key='#{key}']")
    end
  end

  test "security row actions expose row-specific accessible names", %{conn: conn} do
    assert {:ok, alpha_security} =
             Catalog.create_security(%{
               name: "Alpha Fund",
               symbol: "ALP",
               currency_code: "EUR",
               active: true
             })

    assert {:ok, beta_security} =
             Catalog.create_security(%{
               name: "Beta Fund",
               symbol: "BET",
               currency_code: "EUR",
               active: true
             })

    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(
             view,
             "#security-detail-link-#{alpha_security.id}[aria-label='Open detail for Alpha Fund (ALP)']",
             "Open detail"
           )

    assert has_element?(
             view,
             "#security-detail-link-#{beta_security.id}[aria-label='Open detail for Beta Fund (BET)']",
             "Open detail"
           )

    assert has_element?(
             view,
             "#security-archive-#{alpha_security.id}[aria-label='Archive Alpha Fund (ALP)']",
             "Archive"
           )

    assert has_element?(
             view,
             "#security-archive-#{beta_security.id}[aria-label='Archive Beta Fund (BET)']",
             "Archive"
           )

    assert has_element?(
             view,
             "#security-edit-#{alpha_security.id}[aria-label='Edit security for Alpha Fund (ALP)']",
             "Edit security"
           )

    assert has_element?(
             view,
             "#security-edit-#{beta_security.id}[aria-label='Edit security for Beta Fund (BET)']",
             "Edit security"
           )
  end

  test "hidden security columns do not render and no data writes occur", %{conn: conn} do
    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Synthetic ETF",
               symbol: "SYN",
               currency_code: "USD",
               isin: "US0000000001",
               wkn: "WKN1",
               provider_symbol: "SYN.US",
               exchange_code: "XNYS"
             })

    initial_count = Repo.aggregate(Security, :count, :id)
    {:ok, view, _html} = live(conn, "/securities")

    view
    |> form("#security-column-form", %{"columns" => ["name", "symbol", "actions"]})
    |> render_change()

    assert has_element?(view, "#security-list th[data-column-key='name']")
    assert has_element?(view, "#security-list th[data-column-key='symbol']")
    assert has_element?(view, "#security-list th[data-column-key='actions']")
    refute has_element?(view, "#security-list th[data-column-key='currency']")
    refute has_element?(view, "#security-list th[data-column-key='provider_symbol']")
    refute has_element?(view, "#security-list td[data-column-key='currency']")
    refute has_element?(view, "#security-list td[data-column-key='provider_symbol']")
    assert Repo.aggregate(Security, :count, :id) == initial_count
  end

  test "securities page renders shared toolbar controls and keeps status filters", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(view, "#security-workbench-toolbar")

    assert has_element?(
             view,
             "#security-workbench-toolbar-actions[role='group'][aria-labelledby='security-workbench-toolbar-actions-label']"
           )

    assert has_element?(view, "#security-workbench-toolbar-actions-label")

    assert has_element?(
             view,
             "#security-workbench-toolbar-ranges[role='group'][aria-labelledby='security-workbench-toolbar-ranges-label']"
           )

    assert has_element?(view, "#security-workbench-toolbar-ranges-label")
    assert has_element?(view, "#security-workbench-search")
    assert has_element?(view, "#security-workbench-toolbar-filter[disabled]")
    assert has_element?(view, "#security-workbench-toolbar-export[disabled]")
    assert has_element?(view, "#security-workbench-toolbar-columns[disabled]")

    assert has_element?(
             view,
             "#security-workbench-toolbar-range-1m[disabled][aria-pressed=\"false\"]"
           )

    assert has_element?(
             view,
             "#security-workbench-toolbar-range-3m[disabled][aria-pressed=\"false\"]"
           )

    assert has_element?(
             view,
             "#security-workbench-toolbar-range-6m[disabled][aria-pressed=\"false\"]"
           )

    assert has_element?(
             view,
             "#security-workbench-toolbar-range-1y[disabled][aria-pressed=\"false\"]"
           )

    assert has_element?(
             view,
             "#security-workbench-toolbar-range-ytd[disabled][aria-pressed=\"false\"]"
           )

    assert has_element?(
             view,
             "#security-workbench-toolbar-range-all[disabled][aria-pressed=\"true\"]"
           )

    assert has_element?(
             view,
             "#security-list-actions[role='group'][aria-labelledby='security-list-actions-label']"
           )

    assert has_element?(
             view,
             "#security-status-filter[role='group'][aria-labelledby='security-status-filter-label']"
           )

    assert has_element?(view, "#security-filter-active[aria-pressed=\"true\"]")
    assert has_element?(view, "#security-filter-inactive[aria-pressed=\"false\"]")
    assert has_element?(view, "#security-filter-all[aria-pressed=\"false\"]")

    assert has_element?(view, "#security-filter-active")
    assert has_element?(view, "#security-filter-inactive")
    assert has_element?(view, "#security-filter-all")
  end

  test "shows CSV preview section on the securities page", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(view, "#security-csv-preview")
    assert has_element?(view, "#security-csv-preview-form")
    assert has_element?(view, "button", "Preview CSV")
  end

  test "previews a pasted securities CSV with row status", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/securities")

    csv = """
    name,symbol,currency_code,active,isin,wkn,provider_symbol,exchange_code,notes
    Test Security,TEST,USD,true,US123,123,WTEST,XNYS,Example
    """

    html =
      view
      |> form("#security-csv-preview-form", %{
        "security_csv_text" => csv
      })
      |> render_submit()

    assert html =~ "security-preview-row-1"
    assert has_element?(view, "#security-preview-status-1", "valid")
    assert has_element?(view, "#security-preview-row-1", "Test Security")
    assert has_element?(view, "#security-csv-preview-table caption", "Security CSV preview table")
    refute has_element?(view, "button", "Confirm import")
  end

  test "can clear preview and clears preview-only feedback", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/securities")

    csv = """
    name,symbol,currency_code,active,isin,wkn,provider_symbol,exchange_code,notes
    Test Security,TEST,USD,,ISIN,CODE,PS,X,Example
    """

    view
    |> form("#security-csv-preview-form", %{
      "security_csv_text" => csv
    })
    |> render_submit()

    assert has_element?(view, "#security-csv-preview-table")
    assert has_element?(view, "#security-csv-clear-preview")

    view |> element("#security-csv-clear-preview") |> render_click()

    refute has_element?(view, "#security-csv-preview-table")
    refute has_element?(view, "#security-csv-error")
  end

  test "previewing CSV does not create securities", %{conn: conn} do
    assert Repo.aggregate(Security, :count, :id) == 0

    {:ok, view, _html} = live(conn, "/securities")

    csv = """
    name,symbol,currency_code,active,isin,wkn,provider_symbol,exchange_code,notes
    Test Security,TEST,USD,,ISIN,CODE,PS,X,Example
    """

    view
    |> form("#security-csv-preview-form", %{
      "security_csv_text" => csv
    })
    |> render_submit()

    assert Repo.aggregate(Security, :count, :id) == 0
    refute has_element?(view, "#security-list tbody tr", "Test Security")
  end

  test "German security terminology renders for the securities page", %{conn: conn} do
    assert {:ok, security} =
             Catalog.create_security(%{
               name: "Active Security",
               symbol: "AS",
               currency_code: "USD",
               active: true
             })

    conn = put_req_header(conn, "accept-language", "de-DE,de;q=0.9,en;q=0.8")

    {:ok, view, html} = live(conn, "/securities")

    assert html =~ "Alle Wertpapiere"
    assert has_element?(view, "#security-export-csv", "CSV exportieren")
    assert has_element?(view, "#security-filter-active", "Aktiv")
    assert has_element?(view, "#security-filter-inactive", "Inaktiv")
    assert has_element?(view, "#security-filter-all", "Alle")
    assert has_element?(view, "#security-csv-preview h2", "CSV-Importvorschau")
    assert has_element?(view, "label[for='security-csv-text']", "CSV-Inhalt")

    assert has_element?(
             view,
             "#security-csv-preview .app-shell-form-actions button",
             "CSV prüfen"
           )

    assert has_element?(view, "#security-archive-#{security.id}", "Archivieren")
    assert has_element?(view, "#security-edit-#{security.id}", "Wertpapier bearbeiten")
    assert has_element?(view, "#security-list th", "Anbieter-Symbol")
    assert has_element?(view, "#security-list th", "Börse")
    assert has_element?(view, "#security-list th", "Aktionen")
    assert has_element?(view, "#security-list th", "Status")

    csv = """
    name,symbol,currency_code,active,isin,wkn,provider_symbol,exchange_code,notes
    Valid Security,VAL,USD,true,ISIN1,WKN1,PS1,XNYS,Example
    ,BAD,USD,true,ISIN2,WKN2,PS2,XNYS,Invalid Name
    """

    view |> element("#security-add-toggle") |> render_click()
    assert render(view) =~ "Wertpapier anlegen"
    assert has_element?(view, "#security-add-toggle", "Formular schließen")
    assert has_element?(view, "#security-create .app-shell-section-title", "Wertpapier anlegen")

    html =
      view
      |> form("#security-csv-preview-form", %{"security_csv_text" => csv})
      |> render_submit()

    assert html =~ "Vorschau löschen"
    assert has_element?(view, "#security-csv-preview-table th", "Zeile")
    assert has_element?(view, "#security-csv-preview-table th", "Fehler")
    assert has_element?(view, "#security-csv-preview-table th", "Notizen")
    assert has_element?(view, "#security-preview-status-1", "gültig")
    assert has_element?(view, "#security-preview-status-2", "ungültig")

    view |> element("#security-edit-#{security.id}") |> render_click()

    assert has_element?(
             view,
             "#security-create .app-shell-section-title",
             "Wertpapier bearbeiten"
           )

    assert has_element?(
             view,
             "#security-create .app-shell-form-actions button",
             "Wertpapier speichern"
           )

    assert has_element?(view, "#security-add-toggle", "Formular schließen")
  end

  test "Add security form renders before CSV preview when opened", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(view, "#security-listing")
    assert has_element?(view, "#security-csv-preview")
    refute has_element?(view, "#security-create")

    html = view |> element("#security-add-toggle") |> render_click()

    assert {listing_index, _} = :binary.match(html, "id=\"security-listing\"")
    assert {form_index, _} = :binary.match(html, "id=\"security-create\"")
    assert {preview_index, _} = :binary.match(html, "id=\"security-csv-preview\"")

    assert listing_index < form_index
    assert form_index < preview_index

    assert has_element?(view, "#security-create .app-shell-section-title", "Add security")
    assert has_element?(view, "#security-add-toggle", "Close form")
  end

  test "visiting /securities renders shared app shell", %{conn: conn} do
    {:ok, view, html} = live(conn, "/securities")

    assert has_element?(view, "a[href=\"/securities\"]")
    assert has_element?(view, "a[href=\"/taxonomies\"]")
    assert has_element?(view, "img#app-shell-brand-mark[src='/images/logo-mark.svg']")
    assert has_element?(view, ".app-shell-brand-text", "Portfolixir")
    assert has_element?(view, "#sidebar-toggle")
    assert has_element?(view, "#theme-toggle")
    assert html =~ "id=\"theme-toggle-script\""
    assert html =~ "All Securities"
  end

  test "securities workspace uses list-first structure", %{conn: conn} do
    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Synthetic ETF",
               symbol: "SYN",
               currency_code: "USD"
             })

    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(view, "#security-workspace.app-shell-workspace-stack")
    assert has_element?(view, "#security-listing[data-priority='primary']")
    assert has_element?(view, "#security-listing", "Securities")

    assert has_element?(view, "#security-add-toggle")
    refute has_element?(view, "#security-create")

    view |> element("#security-add-toggle") |> render_click()

    assert has_element?(view, "#security-create[data-priority='secondary']")
    assert has_element?(view, "#security-form.app-shell-form-grid")
    assert has_element?(view, "#security-create .app-shell-panel-intro")
  end

  test "renders an empty state when there are no securities", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(
             view,
             "#security-workbench-toolbar-actions[role='group'][aria-labelledby='security-workbench-toolbar-actions-label']"
           )

    assert has_element?(
             view,
             "#security-workbench-toolbar-ranges[role='group'][aria-labelledby='security-workbench-toolbar-ranges-label']"
           )

    assert has_element?(
             view,
             "#security-list-actions[role='group'][aria-labelledby='security-list-actions-label']"
           )

    assert has_element?(
             view,
             "#security-status-filter[role='group'][aria-labelledby='security-status-filter-label']"
           )

    assert has_element?(
             view,
             "#security-results-status[role='status'][aria-live='polite']",
             "No securities yet"
           )

    assert has_element?(
             view,
             "#no-securities[role='status'][aria-describedby='security-results-status']"
           )

    assert has_element?(view, "#no-securities h3", "No securities yet")

    assert has_element?(
             view,
             "#no-securities p",
             "Add your first security to start building your portfolio."
           )
  end

  test "shows active securities by default", %{conn: conn} do
    assert {:ok, _active_security} =
             Catalog.create_security(%{
               name: "Active Security",
               symbol: "AC",
               currency_code: "USD",
               active: true
             })

    assert {:ok, _inactive_security} =
             Catalog.create_security(%{
               name: "Inactive Security",
               symbol: "IN",
               currency_code: "USD",
               active: false
             })

    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(view, "#security-filter-active.app-shell-primary", "Active")
    assert has_element?(view, "#security-list tbody tr", "Active Security")
    refute has_element?(view, "#security-list tbody tr", "Inactive Security")
  end

  test "shows archive action for active securities and hides it for inactive securities", %{
    conn: conn
  } do
    assert {:ok, active_security} =
             Catalog.create_security(%{
               name: "Active Security",
               symbol: "AC",
               currency_code: "USD",
               active: true
             })

    assert {:ok, inactive_security} =
             Catalog.create_security(%{
               name: "Inactive Security",
               symbol: "IN",
               currency_code: "USD",
               active: false
             })

    {:ok, view, _html} = live(conn, "/securities")
    view |> element("#security-filter-all") |> render_click()

    assert has_element?(view, "#security-archive-#{active_security.id}", "Archive")
    refute has_element?(view, "#security-archive-#{inactive_security.id}")
  end

  test "shows inactive securities when inactive filter is selected", %{conn: conn} do
    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Active Security",
               symbol: "AC",
               currency_code: "USD",
               active: true
             })

    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Inactive Security",
               symbol: "IN",
               currency_code: "USD",
               active: false
             })

    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(
             view,
             "#security-filter-active.app-shell-primary[aria-pressed=\"true\"]",
             "Active"
           )

    view |> element("#security-filter-inactive") |> render_click()

    assert has_element?(view, "#security-filter-active[aria-pressed=\"false\"]", "Active")

    assert has_element?(
             view,
             "#security-filter-inactive.app-shell-primary[aria-pressed=\"true\"]",
             "Inactive"
           )

    assert has_element?(view, "#security-list tbody tr", "Inactive Security")
    refute has_element?(view, "#security-list tbody tr", "Active Security")
  end

  test "shows active-empty state when active filter matches no rows but other securities exist",
       %{conn: conn} do
    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Inactive Security",
               symbol: "IN",
               currency_code: "USD",
               active: false
             })

    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(view, "#security-filter-active.app-shell-primary", "Active")

    assert has_element?(
             view,
             "#security-results-status[role='status'][aria-live='polite']",
             "No active securities"
           )

    assert has_element?(
             view,
             "#no-securities[role='status'][aria-describedby='security-results-status']"
           )

    assert has_element?(view, "#no-securities h3", "No active securities")

    assert has_element?(
             view,
             "#no-securities p",
             "Only active securities are shown. Mark one active to appear here."
           )

    refute has_element?(view, "#security-list tbody tr", "Inactive Security")
  end

  test "shows inactive-empty state when inactive filter matches no rows", %{conn: conn} do
    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Active Security",
               symbol: "AC",
               currency_code: "USD",
               active: true
             })

    {:ok, view, _html} = live(conn, "/securities")
    view |> element("#security-filter-inactive") |> render_click()

    assert has_element?(view, "#security-filter-inactive.app-shell-primary", "Inactive")
    assert has_element?(view, "#no-securities h3", "No inactive securities")
    assert has_element?(view, "#no-securities p", "No inactive securities match this filter.")
    refute has_element?(view, "#security-list tbody tr", "Active Security")
  end

  test "shows all filter generic empty state when no securities exist", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/securities")
    view |> element("#security-filter-all") |> render_click()

    assert has_element?(view, "#security-filter-all.app-shell-primary", "All")
    assert has_element?(view, "#no-securities h3", "No securities yet")

    assert has_element?(
             view,
             "#no-securities p",
             "Add your first security to start building your portfolio."
           )
  end

  test "shows all securities and status indicator when all filter is selected", %{conn: conn} do
    assert {:ok, active_security} =
             Catalog.create_security(%{
               name: "Active Security",
               symbol: "AC",
               currency_code: "USD",
               active: true
             })

    assert {:ok, _inactive_security} =
             Catalog.create_security(%{
               name: "Inactive Security",
               symbol: "IN",
               currency_code: "USD",
               active: false
             })

    {:ok, view, _html} = live(conn, "/securities")
    view |> element("#security-filter-all") |> render_click()

    assert has_element?(view, "#security-filter-all.app-shell-primary", "All")

    assert has_element?(
             view,
             "#security-results-status[role='status'][aria-live='polite']",
             "Showing 2 securities"
           )

    assert has_element?(
             view,
             "#security-row-#{active_security.id} td[data-column-key='status'][aria-labelledby='security-status-label-#{active_security.id} security-status-value-#{active_security.id}']"
           )

    assert has_element?(view, "#security-status-label-#{active_security.id}", "Status")
    assert has_element?(view, "#security-status-value-#{active_security.id}", "Active")
    assert has_element?(view, "#security-list tbody tr", "Active Security")
    assert has_element?(view, "#security-list tbody tr", "Inactive Security")
    assert has_element?(view, "span.app-shell-badge", "Active")
    assert has_element?(view, "span.app-shell-badge", "Inactive")
  end

  test "archives an active security from the list and removes it from the active view", %{
    conn: conn
  } do
    assert {:ok, security} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL",
               currency_code: "USD",
               active: true
             })

    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(view, "#security-list tbody tr", "Apple Inc.")
    assert has_element?(view, "#security-archive-#{security.id}", "Archive")

    html = view |> element("#security-archive-#{security.id}") |> render_click()

    assert html =~ "Security archived."
    refute has_element?(view, "#security-list tbody tr", "Apple Inc.")

    view |> element("#security-filter-all") |> render_click()
    assert has_element?(view, "#security-list tbody tr", "Apple Inc.")
    assert has_element?(view, "#security-list tbody tr span", "Inactive")

    view |> element("#security-filter-inactive") |> render_click()
    assert has_element?(view, "#security-list tbody tr", "Apple Inc.")
  end

  test "creates a security with success feedback", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/securities")
    view |> element("#security-add-toggle") |> render_click()

    html =
      view
      |> form("#security-form", %{
        "security" => %{
          "name" => "Apple Inc.",
          "symbol" => "AAPL",
          "currency_code" => "USD",
          "isin" => "US0378331005",
          "wkn" => "865985"
        }
      })
      |> render_submit()

    assert html =~ "Security added."
    assert html =~ "Apple Inc."
    assert html =~ "AAPL"
    assert html =~ "USD"
    assert html =~ "US0378331005"
    assert html =~ "865985"
  end

  test "existing create flow still works with existing records", %{conn: conn} do
    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Existing security",
               symbol: "EXS",
               currency_code: "USD"
             })

    {:ok, view, _html} = live(conn, "/securities")
    view |> element("#security-add-toggle") |> render_click()

    html =
      view
      |> form("#security-form", %{
        "security" => %{
          "name" => "Created after existing",
          "symbol" => "CAE",
          "currency_code" => "EUR"
        }
      })
      |> render_submit()

    assert html =~ "Security added."
    assert html =~ "Created after existing"
    assert html =~ "CAE"
    assert has_element?(view, "#security-create > .app-shell-section-header h2", "Add security")
  end

  test "renders optional fields and valuation fallbacks explicitly when omitted", %{conn: conn} do
    assert {:ok, _} =
             Catalog.create_security(%{
               name: "No IDs Security",
               symbol: "NIS",
               currency_code: "USD"
             })

    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(view, "#security-list tbody tr")
    assert has_element?(view, "#security-list tbody tr td:nth-child(4)", "—")
    assert has_element?(view, "#security-list tbody tr td:nth-child(5)", "—")
    assert has_element?(view, "#security-list tbody tr td:nth-child(6)", "Valuation unavailable")

    assert has_element?(
             view,
             "#security-list tbody tr td:nth-child(6).app-shell-muted[data-valuation-state='missing']",
             "Valuation unavailable"
           )

    assert has_element?(
             view,
             "#security-list tbody tr td:nth-child(7)",
             "Valuation source timestamp unavailable"
           )

    assert has_element?(
             view,
             "#security-list tbody tr td:nth-child(7).app-shell-muted[data-valuation-state='missing']",
             "Valuation source timestamp unavailable"
           )
  end

  test "shows validation error when name is missing", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/securities")
    view |> element("#security-add-toggle") |> render_click()

    html =
      view
      |> form("#security-form", %{
        "security" => %{
          "name" => "",
          "symbol" => "AAPL",
          "currency_code" => "EUR"
        }
      })
      |> render_submit()

    assert html =~ "id=\"security-form-error\""
    assert has_element?(view, "#security-form-error[role='alert']")
    assert html =~ "name"
  end

  test "shows understandable currency validation error and keeps field values", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/securities")
    view |> element("#security-add-toggle") |> render_click()

    html =
      view
      |> form("#security-form", %{
        "security" => %{
          "name" => "Bad Currency",
          "symbol" => "BCY",
          "currency_code" => ""
        }
      })
      |> render_submit()

    assert html =~ "id=\"security-form-error\""
    assert html =~ "currency"
    assert html =~ "value=\"Bad Currency\""
    assert html =~ "value=\"BCY\""
  end

  test "shows an Edit action for existing securities", %{conn: conn} do
    assert {:ok, security} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL",
               currency_code: "USD"
             })

    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(view, "#security-edit-#{security.id}", "Edit security")
  end

  test "prefills the edit form with selected security values", %{conn: conn} do
    assert {:ok, security} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL",
               currency_code: "USD",
               isin: "US0378331005",
               wkn: "865985",
               exchange_code: "NASDAQ",
               provider_symbol: "APPL",
               notes: "Existing note"
             })

    {:ok, view, _html} = live(conn, "/securities")

    assert view |> element("#security-edit-#{security.id}") |> render_click()

    assert has_element?(view, "#security-create > .app-shell-section-header h2", "Edit security")
    assert has_element?(view, "#security-name[value='Apple Inc.']")
    assert has_element?(view, "#security-symbol[value='AAPL']")
    assert has_element?(view, "#security-currency-code option[value='USD'][selected='selected']")
    assert has_element?(view, "#security-isin[value='US0378331005']")
    assert has_element?(view, "#security-wkn[value='865985']")
    assert has_element?(view, "#security-exchange-code[value='NASDAQ']")
    assert has_element?(view, "#security-provider-symbol[value='APPL']")
    assert has_element?(view, "#security-notes", "Existing note")
    assert has_element?(view, "#security-active option[value='true'][selected]", "Active")
  end

  test "updates a security to inactive in the edit form", %{conn: conn} do
    assert {:ok, security} =
             Catalog.create_security(%{
               name: "Active Security",
               symbol: "AAPL",
               currency_code: "USD"
             })

    {:ok, view, _html} = live(conn, "/securities")
    assert view |> element("#security-edit-#{security.id}") |> render_click()

    _html =
      view
      |> form("#security-form", %{
        "security" => %{
          "name" => "Active Security",
          "symbol" => "AAPL",
          "currency_code" => "USD",
          "active" => "false"
        }
      })
      |> render_submit()

    refute has_element?(view, "#security-list tbody tr", "Active Security")
    view |> element("#security-filter-all") |> render_click()
    assert has_element?(view, "#security-list tbody tr", "Active Security")
    assert has_element?(view, "#security-list tbody tr span", "Inactive")
  end

  test "updates a security from the edit form", %{conn: conn} do
    assert {:ok, security} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL",
               currency_code: "USD"
             })

    {:ok, view, _html} = live(conn, "/securities")
    assert view |> element("#security-edit-#{security.id}") |> render_click()

    html =
      view
      |> form("#security-form", %{
        "security" => %{
          "name" => "Apple Corporation",
          "symbol" => "APC",
          "currency_code" => "EUR",
          "isin" => "US0000000000",
          "wkn" => "999111"
        }
      })
      |> render_submit()

    assert html =~ "Apple Corporation"
    assert html =~ "APC"
    assert html =~ "EUR"
    assert html =~ "US0000000000"
    assert html =~ "999111"
    refute has_element?(view, "#security-form")
  end

  test "cancels edit without saving changes", %{conn: conn} do
    assert {:ok, security} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL",
               currency_code: "USD"
             })

    {:ok, view, _html} = live(conn, "/securities")
    assert view |> element("#security-edit-#{security.id}") |> render_click()

    assert has_element?(view, "#security-cancel-edit")

    view |> element("#security-cancel-edit") |> render_click()

    refute has_element?(view, "#security-form")
    assert has_element?(view, "#security-edit-#{security.id}", "Edit security")
    refute has_element?(view, "#security-create > .app-shell-section-header h2", "Edit security")
  end

  test "keeps edit mode open with validation errors", %{conn: conn} do
    assert {:ok, security} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL",
               currency_code: "USD"
             })

    {:ok, view, _html} = live(conn, "/securities")
    assert view |> element("#security-edit-#{security.id}") |> render_click()

    html =
      view
      |> form("#security-form", %{
        "security" => %{
          "name" => "",
          "symbol" => "AAPL",
          "currency_code" => "USD"
        }
      })
      |> render_submit()

    assert html =~ "id=\"security-form-error\""
    assert has_element?(view, "#security-create > .app-shell-section-header h2", "Edit security")
    assert has_element?(view, "#security-cancel-edit")
    assert html =~ "value=\"AAPL\""
  end

  test "lists existing securities", %{conn: conn} do
    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Zebra Holdings",
               symbol: "ZB",
               currency_code: "USD"
             })

    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL",
               currency_code: "USD"
             })

    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Apex Fund",
               symbol: "AXP",
               currency_code: "USD"
             })

    {:ok, _view, html} = live(conn, "/securities")

    assert html =~ "Apex Fund"
    assert html =~ "Apple Inc."
    assert html =~ "Zebra Holdings"
    assert html =~ "security-list"
  end

  test "securities table shows latest quote, quote date, position quantity and search", %{
    conn: conn
  } do
    alias Portfolixir.Ledger
    alias Portfolixir.Portfolios

    {:ok, portfolio} = Portfolios.create_portfolio(%{name: "Main", base_currency_code: "EUR"})

    {:ok, securities_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        name: "Depot",
        currency_code: "EUR"
      })

    {:ok, security} =
      Catalog.create_security(%{
        name: "Synthetic Growth ETF",
        symbol: "SGE",
        currency_code: "EUR",
        provider_symbol: "SGE.DE"
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        type: "buy",
        date: ~D[2026-05-02],
        currency_code: "EUR",
        amount: Decimal.new("300"),
        quantity: Decimal.new("3"),
        price: Decimal.new("100"),
        securities_account_id: securities_account.id,
        security_id: security.id
      })

    {:ok, _} =
      Catalog.create_security_quote(%{
        security_id: security.id,
        date: ~D[2026-05-02],
        source: "manual",
        currency_code: "EUR",
        close: Decimal.new("111.11")
      })

    {:ok, view, _html} = live(conn, "/securities")
    copy = PortfolixirWeb.SecurityManagementLive.valuation_state_copy_matrix()

    assert has_element?(view, "#security-list th", "Latest quote")

    assert has_element?(
             view,
             "#security-list th#security-column-header-latest_quote",
             "Latest quote"
           )

    assert has_element?(view, "#security-list th", "Latest quote date")

    assert has_element?(
             view,
             "#security-list th#security-column-header-latest_quote_date",
             "Latest quote date"
           )

    assert has_element?(view, "#security-list th", "Position quantity")
    assert has_element?(view, "#security-list tbody", "111.11 EUR")
    assert has_element?(view, "#security-list tbody", "2026-05-02")
    assert has_element?(view, "#security-list tbody", "3")

    assert has_element?(
             view,
             "#security-valuation-source-label-#{security.id}",
             "Valuation source: manual"
           )

    assert has_element?(
             view,
             "#security-selected-valuation-source-label",
             "Valuation source: manual"
           )

    assert has_element?(
             view,
             "[data-testid='security-valuation-source-label-#{security.id}'][aria-label='Valuation source: manual']",
             "Valuation source: manual"
           )

    assert has_element?(
             view,
             "#security-selected-valuation-source-label[data-testid='security-selected-valuation-source-label'][aria-label='Valuation source: manual']",
             "Valuation source: manual"
           )

    assert has_element?(
             view,
             "#security-valuation-source-timestamp-#{security.id}[aria-label='Valuation source as of 2026-05-02'] time[datetime='2026-05-02']",
             "Valuation source as of 2026-05-02"
           )

    assert has_element?(
             view,
             "#security-selected-valuation-source-timestamp[aria-label='Valuation source as of 2026-05-02'] time[datetime='2026-05-02']",
             "Valuation source as of 2026-05-02"
           )

    assert has_element?(
             view,
             "#security-list td[data-column-key='latest_quote_date'][headers='security-column-header-latest_quote_date'][aria-label='Valuation source as of 2026-05-02']",
             "Valuation source as of 2026-05-02"
           )

    assert has_element?(
             view,
             "#security-valuation-source-legend-#{security.id}",
             "Source legend: latest stored quote source is shown for this valuation."
           )

    assert has_element?(
             view,
             "#security-valuation-panel-#{security.id}[aria-describedby='security-valuation-source-legend-#{security.id}']"
           )

    assert has_element?(
             view,
             "#security-selected-valuation-source-legend",
             "Source legend: latest stored quote source is shown for this valuation."
           )

    assert has_element?(
             view,
             "#security-selected-summary[aria-describedby='security-selected-valuation-source-legend']"
           )

    assert has_element?(
             view,
             "#security-list td[data-column-key='latest_quote'][headers='security-column-header-latest_quote'][aria-label='111.11 EUR']",
             "111.11 EUR"
           )

    assert has_element?(
             view,
             "#security-selected-summary p[aria-labelledby='security-selected-latest-quote-label security-selected-latest-quote-value']"
           )

    assert has_element?(
             view,
             "#security-selected-latest-quote-label",
             "Latest quote"
           )

    assert has_element?(
             view,
             "#security-selected-latest-quote-value",
             "111.11 EUR"
           )

    assert has_element?(
             view,
             "#security-valuation-panel-#{security.id}[role='group'][aria-labelledby='security-valuation-panel-title-#{security.id}']"
           )

    assert has_element?(
             view,
             "#security-valuation-panel-title-#{security.id}",
             "Security valuation panel"
           )

    assert has_element?(
             view,
             "#security-selected-summary[role='group'][aria-labelledby='security-selected-valuation-summary-title security-selected-valuation-freshness']"
           )

    assert has_element?(
             view,
             "#security-selected-valuation-summary-title",
             "Selected security valuation summary"
           )

    assert has_element?(
             view,
             "#security-valuation-freshness-summary-#{security.id}",
             "Valuation freshness: #{copy.current}"
           )

    assert has_element?(
             view,
             "#security-selected-valuation-freshness-summary",
             "Valuation freshness: #{copy.current}"
           )

    assert has_element?(
             view,
             "#security-selected-valuation-freshness-summary[data-testid='security-selected-valuation-freshness-summary'][aria-label='Valuation freshness summary label']",
             "Valuation freshness: #{copy.current}"
           )

    assert has_element?(
             view,
             "#security-selected-summary p[aria-labelledby='security-selected-latest-quote-date-label security-selected-latest-quote-date-value']"
           )

    assert has_element?(
             view,
             "#security-selected-latest-quote-date-label",
             "Latest quote date"
           )

    assert has_element?(
             view,
             "#security-selected-latest-quote-date-value",
             "2026-05-02"
           )

    assert has_element?(
             view,
             "#security-valuation-freshness-compact-summary",
             "Valuation freshness summary: 1 #{copy.current} · 0 #{copy.stale} · 0 #{copy.missing}"
           )

    refute has_element?(view, "#security-valuation-warning-#{security.id}[role='status']")
    refute has_element?(view, "#security-selected-valuation-warning[role='status']")

    view
    |> element("#security-search-form")
    |> render_change(%{"q" => "growth"})

    assert has_element?(view, "#security-list tbody", "Synthetic Growth ETF")

    view
    |> element("#security-search-form")
    |> render_change(%{"q" => "nomatch"})

    refute has_element?(view, "#security-list tbody tr")
  end

  test "security search is labeled and keeps status filters working", %{conn: conn} do
    assert {:ok, _active_security} =
             Catalog.create_security(%{
               name: "Alpha Search Target",
               symbol: "AST",
               currency_code: "EUR",
               active: true
             })

    assert {:ok, _inactive_security} =
             Catalog.create_security(%{
               name: "Beta Search Target",
               symbol: "BST",
               currency_code: "EUR",
               active: false
             })

    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(
             view,
             "#security-search-form[role='search'][aria-label='Search securities']"
           )

    assert has_element?(view, "label[for='security-search']", "Search securities")
    assert has_element?(view, "#security-search[type='search'][placeholder='Search securities']")
    assert has_element?(view, "#security-search[value='']")

    view
    |> element("#security-search-form")
    |> render_change(%{"q" => "Alpha"})

    assert has_element?(view, "#security-list tbody tr", "Alpha Search Target")
    refute has_element?(view, "#security-list tbody tr", "Beta Search Target")

    assert has_element?(
             view,
             "#security-results-status[role='status'][aria-live='polite']",
             "Showing 1 active security"
           )

    view |> element("#security-filter-inactive") |> render_click()

    assert has_element?(view, "#security-search[value='Alpha']")

    assert has_element?(
             view,
             "#security-results-status[role='status'][aria-live='polite']",
             "No inactive securities match your search."
           )

    assert has_element?(
             view,
             "#no-securities[role='status'][aria-describedby='security-results-status']"
           )

    assert has_element?(view, "#no-securities h3", "No inactive securities")
    assert has_element?(view, "#no-securities p", "No inactive securities match this filter.")
    refute has_element?(view, "#security-list tbody tr", "Alpha Search Target")
    refute has_element?(view, "#security-list tbody tr", "Beta Search Target")
  end

  test "shows missing quote valuation warning for positioned securities", %{
    conn: conn
  } do
    alias Portfolixir.Ledger
    alias Portfolixir.Portfolios

    {:ok, portfolio} = Portfolios.create_portfolio(%{name: "Main", base_currency_code: "EUR"})

    {:ok, securities_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        name: "Depot",
        currency_code: "EUR"
      })

    {:ok, security} =
      Catalog.create_security(%{
        name: "Missing Quote Security",
        symbol: "MQS",
        currency_code: "EUR"
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        type: "buy",
        date: ~D[2026-05-02],
        currency_code: "EUR",
        amount: Decimal.new("500"),
        quantity: Decimal.new("5"),
        price: Decimal.new("100"),
        securities_account_id: securities_account.id,
        security_id: security.id
      })

    {:ok, view, _html} = live(conn, "/securities")
    copy = PortfolixirWeb.SecurityManagementLive.valuation_state_copy_matrix()

    assert has_element?(
             view,
             "#security-valuation-warning-#{security.id}[role='status'][aria-live='polite']",
             "Missing quote for valuation."
           )

    assert has_element?(
             view,
             "#security-selected-valuation-warning[role='status'][aria-live='polite']",
             "Missing quote for valuation."
           )

    assert has_element?(
             view,
             "#security-selected-valuation-warning[data-testid='security-selected-valuation-warning'][aria-label='Valuation warning label']",
             "Missing quote for valuation."
           )

    assert has_element?(
             view,
             "#security-valuation-warning-detail-#{security.id}",
             "No latest quote is available for this positioned security."
           )

    assert has_element?(
             view,
             "#security-selected-valuation-warning-detail",
             "No latest quote is available for this positioned security."
           )

    assert has_element?(
             view,
             "#security-valuation-source-label-#{security.id}",
             "Valuation source #{copy.unavailable}"
           )

    assert has_element?(
             view,
             "#security-selected-valuation-source-label",
             "Valuation source #{copy.unavailable}"
           )

    assert has_element?(
             view,
             "[data-testid='security-valuation-source-label-#{security.id}'][aria-label='Valuation source unavailable']",
             "Valuation source #{copy.unavailable}"
           )

    assert has_element?(
             view,
             "#security-selected-valuation-source-label[data-testid='security-selected-valuation-source-label'][aria-label='Valuation source unavailable']",
             "Valuation source #{copy.unavailable}"
           )

    assert has_element?(
             view,
             "#security-valuation-source-label-#{security.id}.app-shell-muted[data-valuation-state='missing']",
             "Valuation source #{copy.unavailable}"
           )

    assert has_element?(
             view,
             "#security-selected-valuation-source-label.app-shell-muted[data-valuation-state='missing']",
             "Valuation source #{copy.unavailable}"
           )

    assert has_element?(
             view,
             "#security-valuation-source-timestamp-#{security.id}",
             "Valuation source timestamp #{copy.unavailable}"
           )

    assert has_element?(
             view,
             "#security-selected-valuation-source-timestamp",
             "Valuation source timestamp #{copy.unavailable}"
           )

    assert has_element?(
             view,
             "#security-valuation-source-timestamp-#{security.id}[aria-label='Valuation source timestamp unavailable']",
             "Valuation source timestamp #{copy.unavailable}"
           )

    assert has_element?(
             view,
             "#security-selected-valuation-source-timestamp[aria-label='Valuation source timestamp unavailable']",
             "Valuation source timestamp #{copy.unavailable}"
           )

    assert has_element?(
             view,
             "#security-valuation-source-timestamp-#{security.id}.app-shell-muted[data-valuation-state='missing']",
             "Valuation source timestamp #{copy.unavailable}"
           )

    assert has_element?(
             view,
             "#security-selected-valuation-source-timestamp.app-shell-muted[data-valuation-state='missing']",
             "Valuation source timestamp #{copy.unavailable}"
           )

    refute has_element?(
             view,
             "#security-valuation-source-timestamp-#{security.id} time[datetime]"
           )

    refute has_element?(view, "#security-selected-valuation-source-timestamp time[datetime]")

    assert has_element?(
             view,
             "#security-valuation-source-legend-#{security.id}",
             "Source legend: no stored quote source is available for this valuation."
           )

    assert has_element?(
             view,
             "#security-valuation-panel-#{security.id}[aria-describedby='security-valuation-source-legend-#{security.id} security-valuation-warning-detail-#{security.id}']"
           )

    assert has_element?(
             view,
             "#security-selected-valuation-source-legend",
             "Source legend: no stored quote source is available for this valuation."
           )

    assert has_element?(
             view,
             "#security-selected-summary[aria-describedby='security-selected-valuation-source-legend security-selected-valuation-warning-detail']"
           )

    assert has_element?(
             view,
             "#security-valuation-warning-#{security.id}[aria-describedby='security-valuation-warning-detail-#{security.id}']",
             "Missing quote for valuation."
           )

    assert has_element?(
             view,
             "#security-selected-valuation-warning[aria-describedby='security-selected-valuation-warning-detail']",
             "Missing quote for valuation."
           )

    assert has_element?(
             view,
             "#security-list td[data-column-key='latest_quote'][headers='security-column-header-latest_quote'][aria-label='Valuation unavailable']",
             "Valuation unavailable"
           )

    assert has_element?(
             view,
             "#security-list td[data-column-key='latest_quote'].app-shell-muted[data-valuation-state='missing']",
             "Valuation unavailable"
           )

    assert has_element?(
             view,
             "#security-list td[data-column-key='latest_quote_date'][headers='security-column-header-latest_quote_date'][aria-label='Valuation source timestamp unavailable']",
             "Valuation source timestamp unavailable"
           )

    assert has_element?(
             view,
             "#security-list td[data-column-key='latest_quote_date'].app-shell-muted[data-valuation-state='missing']",
             "Valuation source timestamp unavailable"
           )

    assert has_element?(
             view,
             "#security-selected-summary p[aria-labelledby='security-selected-latest-quote-date-label security-selected-latest-quote-date-value'][aria-label='Valuation source timestamp unavailable']"
           )

    assert has_element?(
             view,
             "#security-selected-summary p[aria-labelledby='security-selected-latest-quote-label security-selected-latest-quote-value'][aria-label='Valuation unavailable'][data-valuation-state='missing']"
           )

    assert has_element?(
             view,
             "#security-selected-summary p[aria-labelledby='security-selected-latest-quote-date-label security-selected-latest-quote-date-value'][aria-label='Valuation source timestamp unavailable'][data-valuation-state='missing']"
           )

    assert has_element?(
             view,
             "#security-valuation-freshness-summary-#{security.id}",
             "Valuation freshness: #{copy.missing}"
           )

    assert has_element?(
             view,
             "#security-selected-valuation-freshness-summary",
             "Valuation freshness: #{copy.missing}"
           )

    assert has_element?(
             view,
             "#security-valuation-freshness-compact-summary",
             "Valuation freshness summary: 0 #{copy.current} · 0 #{copy.stale} · 1 #{copy.missing}"
           )

    assert has_element?(
             view,
             "#security-valuation-panel-#{security.id}[role='group'][aria-labelledby='security-valuation-panel-title-#{security.id}']"
           )

    assert has_element?(
             view,
             "#security-selected-summary[role='group'][aria-labelledby='security-selected-valuation-summary-title security-selected-valuation-freshness']"
           )

    assert has_element?(view, "#security-selected-summary", "Valuation unavailable")
  end

  test "shows stale quote valuation warning when latest quote predates latest transaction", %{
    conn: conn
  } do
    alias Portfolixir.Ledger
    alias Portfolixir.Portfolios

    {:ok, portfolio} = Portfolios.create_portfolio(%{name: "Main", base_currency_code: "EUR"})

    {:ok, securities_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        name: "Depot",
        currency_code: "EUR"
      })

    {:ok, security} =
      Catalog.create_security(%{
        name: "Stale Quote Security",
        symbol: "SQS",
        currency_code: "EUR"
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        type: "buy",
        date: ~D[2026-05-10],
        currency_code: "EUR",
        amount: Decimal.new("200"),
        quantity: Decimal.new("2"),
        price: Decimal.new("100"),
        securities_account_id: securities_account.id,
        security_id: security.id
      })

    {:ok, _} =
      Catalog.create_security_quote(%{
        security_id: security.id,
        date: ~D[2026-05-01],
        source: "manual",
        currency_code: "EUR",
        close: Decimal.new("98.00")
      })

    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(
             view,
             "#security-valuation-warning-#{security.id}[role='status'][aria-live='polite']",
             "Stale quote used for valuation."
           )

    assert has_element?(
             view,
             "#security-selected-valuation-warning[role='status'][aria-live='polite']",
             "Stale quote used for valuation."
           )

    assert has_element?(
             view,
             "#security-valuation-warning-detail-#{security.id}",
             "Latest quote date 2026-05-01 is older than recent transactions."
           )

    assert has_element?(
             view,
             "#security-selected-valuation-warning-detail",
             "Latest quote date 2026-05-01 is older than recent transactions."
           )

    assert has_element?(
             view,
             "#security-valuation-freshness-summary-#{security.id}",
             "Valuation freshness: stale"
           )

    assert has_element?(
             view,
             "#security-selected-valuation-freshness-summary",
             "Valuation freshness: stale"
           )

    assert has_element?(
             view,
             "#security-valuation-freshness-compact-summary",
             "Valuation freshness summary: 0 current · 1 stale · 0 missing"
           )

    assert has_element?(
             view,
             "#security-valuation-source-legend-#{security.id}",
             "Source legend: latest stored quote source is shown; quote date may be older than recent transactions."
           )

    assert has_element?(
             view,
             "#security-selected-valuation-source-legend",
             "Source legend: latest stored quote source is shown; quote date may be older than recent transactions."
           )
  end

  test "uses neutral valuation freshness summary for no-position rows" do
    {:ok, security} =
      Catalog.create_security(%{name: "Neutral Security", symbol: "NEU", currency_code: "EUR"})

    {:ok, view, _html} = live(build_conn(), "/securities")
    copy = PortfolixirWeb.SecurityManagementLive.valuation_state_copy_matrix()

    assert has_element?(
             view,
             "#security-valuation-freshness-summary-#{security.id}",
             "Valuation freshness #{copy.unavailable}"
           )

    assert has_element?(
             view,
             "#security-selected-valuation-freshness-summary",
             "Valuation freshness #{copy.unavailable}"
           )

    assert has_element?(
             view,
             "#security-valuation-freshness-compact-summary",
             "Valuation freshness summary #{copy.unavailable}"
           )
  end

  test "valuation warning fallback uses one neutral phrase when supporting context is missing" do
    assert PortfolixirWeb.SecurityManagementLive.valuation_warning_label("unknown_warning") ==
             "Valuation warning unavailable."

    assert PortfolixirWeb.SecurityManagementLive.valuation_warning_detail_label(
             "unknown_warning",
             nil
           ) == "Valuation warning unavailable."
  end

  test "split view shows selected security and chart placeholder", %{conn: conn} do
    {:ok, security} =
      Catalog.create_security(%{name: "Alpha Corp", symbol: "ALP", currency_code: "EUR"})

    {:ok, _} =
      Catalog.create_security(%{name: "Beta Corp", symbol: "BET", currency_code: "EUR"})

    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(
             view,
             "#security-selected-detail[aria-labelledby='security-selected-detail-title']"
           )

    assert has_element?(view, "#security-selected-detail-title", "Selected security")

    assert has_element?(
             view,
             "#security-selected-summary[aria-labelledby='security-selected-valuation-summary-title security-selected-valuation-freshness']"
           )

    assert has_element?(
             view,
             "#security-selected-valuation-summary-title",
             "Selected security valuation summary"
           )

    assert has_element?(view, "#security-selected-summary", "Alpha Corp")

    assert has_element?(
             view,
             "#security-selected-chart-placeholder[role='region'][aria-labelledby='security-selected-chart-placeholder-title']"
           )

    assert has_element?(view, "#security-selected-chart-placeholder-title", "Chart preview")

    assert has_element?(
             view,
             "#security-selected-open-detail[href='/securities/#{security.id}']"
           )
  end

  test "freshness accessibility labels cover current stale missing and neutral states", %{
    conn: conn
  } do
    alias Portfolixir.Ledger
    alias Portfolixir.Portfolios

    today = Date.utc_today()
    yesterday = Date.add(today, -1)

    {:ok, portfolio} = Portfolios.create_portfolio(%{name: "Main", base_currency_code: "EUR"})

    {:ok, securities_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        name: "Depot",
        currency_code: "EUR"
      })

    {:ok, neutral_security} =
      Catalog.create_security(%{name: "Alpha Neutral", symbol: "ALP", currency_code: "EUR"})

    {:ok, current_security} =
      Catalog.create_security(%{name: "Beta Current", symbol: "CUR", currency_code: "EUR"})

    {:ok, stale_security} =
      Catalog.create_security(%{name: "Gamma Stale", symbol: "STA", currency_code: "EUR"})

    {:ok, missing_security} =
      Catalog.create_security(%{name: "Omega Missing", symbol: "MIS", currency_code: "EUR"})

    for security <- [current_security, stale_security, missing_security] do
      {:ok, _} =
        Ledger.create_transaction(%{
          portfolio_id: portfolio.id,
          type: "buy",
          date: today,
          currency_code: "EUR",
          amount: Decimal.new("300"),
          quantity: Decimal.new("3"),
          price: Decimal.new("100"),
          securities_account_id: securities_account.id,
          security_id: security.id
        })
    end

    {:ok, _} =
      Catalog.create_security_quote(%{
        security_id: current_security.id,
        date: today,
        source: "manual",
        currency_code: "EUR",
        close: Decimal.new("111.11")
      })

    {:ok, _} =
      Catalog.create_security_quote(%{
        security_id: stale_security.id,
        date: yesterday,
        source: "manual",
        currency_code: "EUR",
        close: Decimal.new("99.99")
      })

    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(view, "#security-selected-summary")

    assert has_element?(
             view,
             "#security-selected-summary[aria-labelledby='security-selected-valuation-summary-title security-selected-valuation-freshness']",
             "No position freshness"
           )

    assert has_element?(
             view,
             "#security-selected-valuation-summary-title",
             "Selected security valuation summary"
           )

    assert has_element?(
             view,
             "#security-row-#{neutral_security.id}[aria-label='No position freshness']"
           )

    assert has_element?(
             view,
             "#security-row-#{current_security.id}[aria-label='Current quote freshness']"
           )

    assert has_element?(
             view,
             "#security-row-#{stale_security.id}[aria-label='Stale quote freshness']"
           )

    assert has_element?(
             view,
             "#security-row-#{missing_security.id}[aria-label='Missing quote freshness']"
           )

    view
    |> element("#security-row-#{current_security.id}")
    |> render_click()

    assert has_element?(view, "#security-selected-summary", "Current quote freshness")

    view
    |> element("#security-row-#{stale_security.id}")
    |> render_click()

    assert has_element?(view, "#security-selected-summary", "Stale quote freshness")

    view
    |> element("#security-row-#{missing_security.id}")
    |> render_click()

    assert has_element?(view, "#security-selected-summary", "Missing quote freshness")

    view
    |> element("#security-row-#{neutral_security.id}")
    |> render_click()

    assert has_element?(view, "#security-selected-summary")
  end

  test "clicking another row updates selected security detail area", %{conn: conn} do
    {:ok, first_security} =
      Catalog.create_security(%{name: "Alpha Corp", symbol: "ALP", currency_code: "EUR"})

    {:ok, second_security} =
      Catalog.create_security(%{name: "Beta Corp", symbol: "BET", currency_code: "EUR"})

    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(view, "#security-selected-summary", "Alpha Corp")

    view
    |> element("#security-row-#{second_security.id}")
    |> render_click()

    assert has_element?(view, "#security-selected-summary", "Beta Corp")

    refute has_element?(
             view,
             "#security-selected-open-detail[href='/securities/#{first_security.id}']"
           )

    assert has_element?(
             view,
             "#security-selected-open-detail[href='/securities/#{second_security.id}']"
           )
  end
end
