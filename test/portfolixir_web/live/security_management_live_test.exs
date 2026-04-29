defmodule PortfolixirWeb.SecurityManagementLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog

  setup do
    Catalog.ensure_mvp_currencies!()
    :ok
  end

  test "visiting / renders All Securities", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "All Securities"
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

  test "German security terminology renders for the create flow", %{conn: conn} do
    conn = put_req_header(conn, "accept-language", "de-DE,de;q=0.9,en;q=0.8")

    {:ok, view, html} = live(conn, "/securities")

    assert html =~ "Alle Wertpapiere"

    view |> element("#security-add-toggle") |> render_click()

    assert render(view) =~ "Währung"
    assert has_element?(view, "#security-currency-code")
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
    {:ok, _view, html} = live(conn, "/securities")

    assert html =~ "All Securities"
    assert html =~ "No securities yet"
    assert html =~ "Add your first security to start building your portfolio."
  end

  test "shows active securities by default", %{conn: conn} do
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
    assert has_element?(view, "#security-filter-active.app-shell-primary", "Active")

    view |> element("#security-filter-inactive") |> render_click()

    assert has_element?(view, "#security-filter-inactive.app-shell-primary", "Inactive")
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
    view |> element("#security-filter-all") |> render_click()

    assert has_element?(view, "#security-filter-all.app-shell-primary", "All")
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

  test "renders optional fields as em dashes when omitted", %{conn: conn} do
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
    assert has_element?(view, "#security-list tbody tr td:nth-child(6)", "—")
    assert has_element?(view, "#security-list tbody tr td:nth-child(7)", "—")
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

    assert has_element?(view, "#security-edit-#{security.id}", "Edit")
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
    assert has_element?(view, "#security-edit-#{security.id}", "Edit")
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
end
