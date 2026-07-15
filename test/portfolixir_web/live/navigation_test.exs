defmodule PortfolixirWeb.NavigationTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Portfolios

  # User story:
  # As a local portfolio maintainer,
  # I want the dashboard navigation to show the active local workflow
  # plus the PP-import tool (AGENTS.md goal #9),
  # so that the supported surfaces are visible and prototype document/
  # taxonomy/report surfaces do not guide my work.
  #
  # Acceptance criteria:
  # - The dashboard exposes securities, accounts & depots, and transactions as
  #   primary navigation (imports live on the Transactions tab bar, ADR-0022).
  # - Prototype routes for documents, taxonomies, and reports are absent.
  # - The dashboard describes the manual workflow path in order.
  test "dashboard renders only the active local workflow navigation", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#nav-dashboard[href='/']")
    assert has_element?(view, "#nav-securities[href='/securities']")
    assert has_element?(view, "#nav-portfolios[href='/portfolios']")
    assert has_element?(view, "#nav-transactions[href='/transactions']")

    refute has_element?(view, "a[href='/documents/new']")
    refute has_element?(view, "a[href='/taxonomies']")
    refute has_element?(view, "a[href='/reports/fund-allocations']")

    assert has_element?(view, "#workflow-path", "Create securities")
    assert has_element?(view, "#workflow-path", "Create one cash account")
    assert has_element?(view, "#workflow-path", "Link one depot to one cash account")
    assert has_element?(view, "#workflow-path", "Record manual buy and sell transactions")
  end

  # User story (ADR-0024, supersedes Steve cold-start #4):
  # As a new user reading the dashboard's workflow path,
  # I want its first step to be creating a depot with its cash account —
  # with no portfolio decision anywhere,
  # so that the onboarding matches the bucket/view grouping model and the
  # empty-state prerequisites of the Wealth and Income screens.
  #
  # Acceptance criteria:
  # - The workflow path's first step links to /portfolios (Accounts & depots)
  #   and asks for a cash account, not a portfolio.
  # - No wizard step mentions creating a portfolio.
  test "workflow path starts with the cash account and depot, never a portfolio",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(
             view,
             "#workflow-path ol li:first-child a[href='/portfolios']",
             "Create one cash account"
           )

    html = render(view)
    refute html =~ "Create one portfolio"
    {cash_at, _} = :binary.match(html, "Create one cash account")
    {securities_at, _} = :binary.match(html, "Create securities")
    assert cash_at < securities_at
  end

  # User story (Steve cold-start #3):
  # As a new user on the dashboard,
  # I want the big count cards — the most clickable-looking thing on an empty
  # screen — to actually take me to where I create that data,
  # so that clicking "Securities 0" is not a dead end.
  #
  # Acceptance criteria:
  # - Each dashboard count card is a link to its owning surface (securities,
  #   cash accounts, depots → /portfolios; transactions).
  # - No portfolio count card exists (ADR-0024: portfolios left the UI).
  test "dashboard count cards link to their owning surface", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "a#dashboard-securities-count[href='/securities']")
    refute has_element?(view, "a#dashboard-portfolios-count")
    assert has_element?(view, "a#dashboard-cash-accounts-count[href='/portfolios']")
    assert has_element?(view, "a#dashboard-securities-accounts-count[href='/portfolios']")
    assert has_element?(view, "a#dashboard-transactions-count[href='/transactions']")
  end

  # User story (ADR-0022):
  # As a local portfolio maintainer,
  # I want the sidebar organised into task-oriented areas — Overview, Wealth,
  # Securities, Transactions, and an Administration group — with no roadmap
  # placeholders and no per-classification tree,
  # so that every destination answers a task ("how is my wealth doing?",
  # "record/import data", "configure the system") instead of mirroring the
  # issue history.
  #
  # Acceptance criteria:
  # - Top level: Overview (/), Wealth (/portfolio), Securities (/securities),
  #   Transactions (/transactions).
  # - An "Administration" group holds Accounts & depots (/portfolios),
  #   Views (/buckets), and Classifications (/classifications).
  # - The "Portfolio"/"Portfolios" naming collision is resolved: the holdings
  #   view is labelled Wealth, the master-data page Accounts & depots.
  # - Disabled "Soon" placeholders, the Income nav entry (now a Wealth tab),
  #   the Imports nav entry (now a Transactions tab), the developer-facing
  #   group titles, and the sidebar classification tree are gone.
  test "sidebar shows the five task-oriented areas without placeholders", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "#nav-dashboard[href='/']", "Overview")
    assert has_element?(view, "#nav-portfolio[href='/portfolio']", "Wealth")
    assert has_element?(view, "#nav-securities[href='/securities']", "Securities")
    assert has_element?(view, "#nav-transactions[href='/transactions']", "Transactions")

    assert html =~ "Administration"
    assert has_element?(view, "#nav-portfolios[href='/portfolios']", "Accounts & depots")
    # ADR-0024 modification 6: the sidebar entry is about views (the task of
    # scoping analytics); bucket CRUD is reachable from account-row chips and
    # from the views management page, never as its own sidebar destination.
    assert has_element?(view, "#nav-buckets[href='/buckets']", "Views")
    refute has_element?(view, "#nav-buckets", "Buckets & views")
    assert has_element?(view, "#nav-classifications[href='/classifications']", "Classifications")

    # Income and Imports moved into their areas' tab bars (ADR-0022).
    refute has_element?(view, "#nav-dividends")
    refute has_element?(view, "#nav-imports")

    # No roadmap placeholders: the nav promises only what exists.
    refute has_element?(view, ".nav-link.is-disabled")
    refute has_element?(view, ".nav-pill")

    # Developer-facing group titles are gone.
    refute html =~ "Master data"
    refute html =~ ">Tools<"
    refute html =~ ">Reports<"

    # The per-classification tree left the sidebar; the Classifications page
    # owns tree management.
    refute has_element?(view, "#app-sidebar a[href='/classifications/new']")
  end

  # User story (ADR-0022):
  # As a local portfolio maintainer,
  # I want the Wealth area to carry tabs for Holdings, Allocation & targets,
  # and Income, and the Transactions area tabs for History and Import,
  # so that analytics live in one place and importing is just another way to
  # record transactions.
  #
  # Acceptance criteria:
  # - /portfolio shows the Wealth tab bar with Holdings active; the allocation
  #   tab is a link to /portfolio?tab=allocation and Income links to /income.
  # - /income shows the same tab bar with Income active, and the sidebar
  #   highlights Wealth.
  # - /transactions and /imports share a History/Import tab bar, and /imports
  #   keeps the sidebar's Transactions entry active.
  test "wealth and transactions areas expose their tab bars", %{conn: conn} do
    # The Wealth pages render their tab bar on the loaded (non-empty) state.
    # Built-in classification trees are seeded at boot in production (#529);
    # the sandboxed test DB needs one explicitly.
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Local Portfolio",
        base_currency_code: "EUR"
      })

    # ADR-0024: the Wealth pages key their loaded state on the bookkeeping
    # entities, so the fixture needs a cash account and a depot.
    {:ok, cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Local Cash",
        currency_code: "EUR"
      })

    {:ok, _depot} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Main Depot"
      })

    {:ok, _classification} =
      Portfolixir.Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{
        name: "Strategy"
      })

    {:ok, portfolio_view, _html} = live(conn, "/portfolio")

    assert has_element?(
             portfolio_view,
             ~s([data-role="area-tabs"] a[href="/portfolio"][aria-current="page"]),
             "Holdings"
           )

    assert has_element?(
             portfolio_view,
             ~s([data-role="area-tabs"] a[href="/portfolio?tab=allocation"]),
             "Allocation & targets"
           )

    assert has_element?(
             portfolio_view,
             ~s([data-role="area-tabs"] a[href="/income"]),
             "Income"
           )

    {:ok, income_view, _html} = live(conn, "/income")

    assert has_element?(
             income_view,
             ~s([data-role="area-tabs"] a[href="/income"][aria-current="page"]),
             "Income"
           )

    assert has_element?(income_view, "#nav-portfolio[aria-current='page']")

    {:ok, transactions_view, _html} = live(conn, "/transactions")

    assert has_element?(
             transactions_view,
             ~s([data-role="area-tabs"] a[href="/transactions"][aria-current="page"]),
             "History"
           )

    assert has_element?(
             transactions_view,
             ~s([data-role="area-tabs"] a[href="/imports"]),
             "Import"
           )

    {:ok, imports_view, _html} = live(conn, "/imports")

    assert has_element?(
             imports_view,
             ~s([data-role="area-tabs"] a[href="/imports"][aria-current="page"]),
             "Import"
           )

    assert has_element?(imports_view, "#nav-transactions[aria-current='page']")
  end

  # User story (ADR-0022 follow-up, review finding):
  # As a local portfolio maintainer reading the Allocation & targets tab,
  # I want switching the active view or the language to keep me on that tab,
  # so that changing the view-bound SOLL plan context does not silently throw
  # me back to Holdings.
  #
  # Acceptance criteria:
  # - On /portfolio?tab=allocation the view-switcher chips and the locale
  #   links carry the tab param alongside their own.
  # - On plain /portfolio (Holdings) they keep working without a tab param.
  test "view and locale switches keep the active wealth tab", %{conn: conn} do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Local Portfolio",
        base_currency_code: "EUR"
      })

    # ADR-0024: the Wealth pages key their loaded state on the bookkeeping
    # entities, so the fixture needs a cash account and a depot.
    {:ok, cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Local Cash",
        currency_code: "EUR"
      })

    {:ok, _depot} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Main Depot"
      })

    {:ok, _classification} =
      Portfolixir.Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{
        name: "Strategy"
      })

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
    html = render_async(view)

    # The Total view chip keeps the tab param next to its own view param.
    total_chip = view |> element("#view-switch-total") |> render()
    assert total_chip =~ "tab=allocation"
    assert total_chip =~ "view=total"

    # The locale links keep the tab param too.
    assert html =~ ~r/id="locale-en"[^>]*href="[^"]*tab=allocation[^"]*"/

    # Plain Holdings keeps the untabbed links.
    {:ok, holdings_view, _html} = live(conn, "/portfolio")
    render_async(holdings_view)
    holdings_chip = holdings_view |> element("#view-switch-total") |> render()
    refute holdings_chip =~ "tab=allocation"
    assert holdings_chip =~ "view=total"
  end

  # User story:
  # As a local portfolio maintainer,
  # I want a responsive Portfolixir design shell with matching light and dark themes,
  # so that the local workflow has a coherent app frame on desktop, tablet, and phone.
  #
  # Acceptance criteria:
  # - The root layout loads the app stylesheet, color-scheme metadata, and favicon assets.
  # - The app shell renders a logo, hamburger toggle, collapsible sidebar, and active navigation state.
  # - The stylesheet defines shared light/dark theme tokens from the logo palette.
  # - The stylesheet includes responsive sidebar and compact navigation rules.
  test "app shell establishes the responsive light and dark design system", %{
    conn: conn
  } do
    {:ok, view, html} = live(conn, "/")

    assert html =~ ~s(href="/app.css")
    assert html =~ ~s(rel="icon")
    assert html =~ ~s(name="color-scheme")

    assert html =~ ~s(id="app-sidebar-toggle")
    assert html =~ ~s(class="sidebar-toggle")
    assert html =~ ~s(src="/images/logo-mark-light.svg")
    assert html =~ ~s(src="/images/logo-mark-dark.svg")
    assert html =~ ~s(class="brand-wordmark")
    assert has_element?(view, "#app-sidebar")
    assert has_element?(view, "#nav-dashboard[aria-current='page']")
    refute html =~ ~s(id="nav-securities" aria-current)

    app_css = File.read!("priv/static/app.css")

    for token <- [
          "--color-accent-violet: #7c3aed",
          "--color-accent-teal: #0f766e",
          "--color-accent-coral: #e11d48",
          "--color-positive",
          "--color-danger"
        ] do
      assert app_css =~ token
    end

    assert app_css =~ "@media (prefers-color-scheme: dark)"
    assert app_css =~ ~s([data-theme="light"])
    assert app_css =~ ~s([data-theme="dark"])
    assert app_css =~ "@media (max-width: 900px)"
    assert app_css =~ "#app-sidebar-toggle:checked"
    assert app_css =~ ".app-shell"
  end

  # User story:
  # As a local portfolio maintainer,
  # I want theme and language controls in the top bar instead of a second sidebar collapse control,
  # so that display preferences are obvious and the navigation frame stays simple.
  #
  # Acceptance criteria:
  # - The bottom sidebar collapse control is not rendered.
  # - The top bar contains a compact theme dropdown with system, light, and dark icon choices.
  # - The top bar contains language links for English and German.
  # - Light and dark logo marks exist without bundled wordmark text.
  test "top bar contains display controls and sidebar has no duplicate collapse control", %{
    conn: conn
  } do
    {:ok, _view, html} = live(conn, "/")

    refute html =~ "sidebar-collapse"
    assert html =~ ~s(id="theme-mode")
    assert html =~ ~s(class="theme-menu")
    assert html =~ ~s(class="theme-menu-trigger")
    assert html =~ ~s(data-theme-choice="system")
    assert html =~ ~s(data-theme-choice="light")
    assert html =~ ~s(data-theme-choice="dark")
    assert html =~ ~s(data-theme-icon="monitor")
    assert html =~ ~s(data-theme-icon="sun")
    assert html =~ ~s(data-theme-icon="moon")
    assert html =~ ~s(title="System")
    assert html =~ ~s(title="Light")
    assert html =~ ~s(title="Dark")
    assert html =~ ~s(id="locale-en")
    assert html =~ ~s(id="locale-de")
    assert html =~ ~s(src="/images/logo-mark-light.svg")
    assert html =~ ~s(src="/images/logo-mark-dark.svg")

    logo_mark_light = File.read!("priv/static/images/logo-mark-light.svg")
    logo_mark_dark = File.read!("priv/static/images/logo-mark-dark.svg")

    refute logo_mark_light =~ "<text"
    refute logo_mark_dark =~ "<text"
    assert logo_mark_light =~ ~s(stroke="#201631")
    assert logo_mark_dark =~ ~s(stroke="#F5F3FF")
  end

  # User story:
  # As a local portfolio maintainer,
  # I want the active section title in the top bar instead of above the content,
  # so that data-heavy views can use the available vertical space.
  #
  # Acceptance criteria:
  # - Every active menu route renders its current page title in the top bar.
  # - The main content no longer repeats the page-level h1 header.
  # - Every active menu route uses the full-width workspace layout.
  test "active page title is rendered in the top bar for every menu route", %{conn: conn} do
    for {path, title, workspace_selector} <- [
          {"/", "Overview", "#dashboard-workspace.workspace-page"},
          {"/securities", "Securities", "#securities-panel.workspace-panel"},
          {"/portfolios", "Accounts & depots", "#portfolios-workspace.workspace-page"},
          {"/transactions", "Transactions", "#transactions-workspace.workspace-page"},
          {"/imports", "Imports", "#imports-workspace.workspace-page"}
        ] do
      {:ok, view, _html} = live(conn, path)

      assert has_element?(view, "#app-topbar-title", title)
      assert has_element?(view, "main.app-main.app-main--workspace")
      assert has_element?(view, workspace_selector)
      refute has_element?(view, ".app-main .page-header")
      refute has_element?(view, ".app-main h1", title)
    end
  end

  # User story:
  # As a local portfolio maintainer,
  # I want the theme selector to use compact system, light, and dark icon buttons,
  # so that display mode selection is recognizable without custom CSS glyphs.
  #
  # Acceptance criteria:
  # - The trigger exposes the currently selected mode icon.
  # - The choices expose monitor, sun, and moon icons.
  # - The old CSS-drawn theme glyph classes are not rendered.
  test "theme selector renders compact monitor sun and moon icon buttons", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ ~s(data-current-theme-icon="system")
    assert html =~ ~s(data-theme-icon="monitor")
    assert html =~ ~s(data-theme-icon="sun")
    assert html =~ ~s(data-theme-icon="moon")
    refute html =~ "theme-icon-system"
    refute html =~ "theme-icon-light"
    refute html =~ "theme-icon-dark"
  end

  # User story:
  # As a local portfolio maintainer,
  # I want to try the three logo accent colors from the top bar,
  # so that I can compare the app design without changing code.
  #
  # Acceptance criteria:
  # - The top bar contains an accent dropdown next to the theme control.
  # - The dropdown offers only Violet, Teal, and Coral.
  # - The layout boot script restores the accent choice before the page paints.
  # - Accentable UI states use the selected accent token instead of hard-coded violet.
  # - Non-semantic success/info/badge highlights use selected accent tokens instead of fixed teal.
  test "top bar exposes logo accent choices and the stylesheet uses selected accent tokens", %{
    conn: conn
  } do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ ~s(id="accent-color")
    assert html =~ ~s(data-accent-control)
    assert html =~ ~s(data-accent-choice="violet")
    assert html =~ ~s(data-accent-choice="teal")
    assert html =~ ~s(data-accent-choice="coral")
    assert html =~ ~s(title="Violet")
    assert html =~ ~s(title="Teal")
    assert html =~ ~s(title="Coral")
    assert html =~ "portfolixir-accent"

    app_css = File.read!("priv/static/app.css")

    assert app_css =~ "--color-accent:"
    assert app_css =~ "--color-accent-soft:"
    assert app_css =~ ~s([data-accent="violet"])
    assert app_css =~ ~s([data-accent="teal"])
    assert app_css =~ ~s([data-accent="coral"])
    assert app_css =~ ".button-primary"
    assert app_css =~ "background: var(--color-accent);"
    assert app_css =~ "accent-color: var(--color-accent);"
    assert app_css =~ ".security-chart .quote-line"
    assert app_css =~ "stroke: var(--color-accent);"

    for selector <- [".alert-success", ".alert-info", ".badge"] do
      rule = css_rule(app_css, selector)

      assert rule =~ "color: var(--color-accent);"
      assert rule =~ "background: var(--color-accent-soft);"
      refute rule =~ "var(--color-accent-teal"
      refute rule =~ "var(--color-positive"
    end
  end

  # User story:
  # As a local portfolio maintainer,
  # I want Portfolixir to default to my browser language while still offering a manual switch,
  # so that I can use German or English without changing the application scope.
  #
  # Acceptance criteria:
  # - German browser language renders the dashboard navigation in German.
  # - The locale query parameter overrides the browser language.
  # - Locale switching avoids creating atoms from request input.
  test "browser language defaults to german and locale query can switch back to english", %{
    conn: conn
  } do
    german_conn = put_req_header(conn, "accept-language", "de-DE,de;q=0.9,en;q=0.8")

    {:ok, view, _html} = live(german_conn, "/")

    assert has_element?(view, "#nav-securities", "Wertpapiere")
    assert has_element?(view, "#locale-de[aria-current='true']")
    assert has_element?(view, "#locale-en[href='/?locale=en']")

    {:ok, english_view, _html} = live(german_conn, "/?locale=en")

    assert has_element?(english_view, "#nav-securities", "Securities")
    assert has_element?(english_view, "#locale-en[aria-current='true']")
  end

  # User story:
  # As a local portfolio maintainer,
  # I want a stale automatically stored session locale to be ignored on first open,
  # so that a German browser still sees German unless I explicitly picked English.
  #
  # Acceptance criteria:
  # - A session-only locale value does not override Accept-Language.
  # - An explicit locale cookie still overrides Accept-Language.
  # - The explicit query parameter still persists the chosen locale.
  test "browser language beats stale automatic session locale unless an explicit cookie exists",
       %{
         conn: conn
       } do
    stale_session_conn =
      conn
      |> init_test_session(%{"locale" => "en"})
      |> put_req_header("accept-language", "de-DE,de;q=0.9,en;q=0.8")

    {:ok, german_view, _html} = live(stale_session_conn, "/")

    assert has_element?(german_view, "#nav-securities", "Wertpapiere")
    assert has_element?(german_view, "#locale-de[aria-current='true']")

    explicit_cookie_conn =
      build_conn()
      |> put_req_header("accept-language", "de-DE,de;q=0.9,en;q=0.8")
      |> put_req_cookie("portfolixir_locale", "en")

    {:ok, english_view, _html} = live(explicit_cookie_conn, "/")

    assert has_element?(english_view, "#nav-securities", "Securities")
    assert has_element?(english_view, "#locale-en[aria-current='true']")
  end

  # User story:
  # As a local portfolio maintainer recording a manual trade,
  # I want to select only the depot and see its linked cash account as context,
  # so that I cannot choose an inconsistent cash account in the transaction form.
  #
  # Acceptance criteria:
  # - The transaction form has no independent cash-account select field.
  # - Each depot option names its linked cash account as a quiet caption (#472).
  # - The currency in force is derived from the depot, shown as a caption (#473).
  test "transaction form derives cash account from depot instead of asking for it", %{conn: conn} do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Local Portfolio",
        base_currency_code: "EUR"
      })

    {:ok, cash_account} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Cash EUR",
        currency_code: "EUR"
      })

    {:ok, _depot} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash_account.id,
        name: "Depot"
      })

    {:ok, _security} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Synthetic Global ETF",
        ticker_symbol: "SYN",
        currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/transactions")

    refute has_element?(view, "#transaction-form select[name='transaction[cash_account_id]']")
    refute has_element?(view, "#transaction-form input[name='transaction[currency_code]']")
    assert has_element?(view, "#transaction-form", "Depot (Cash EUR)")
    assert has_element?(view, "#transaction-form [data-role='derived-currency']")
  end

  defp css_rule(css, selector) do
    escaped_selector = Regex.escape(selector)
    [_, rule] = Regex.run(~r/#{escaped_selector}\s*\{([^}]*)\}/, css)
    rule
  end
end
