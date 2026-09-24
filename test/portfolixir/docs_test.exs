defmodule Portfolixir.DocsTest do
  use ExUnit.Case, async: true

  @doc_files [
    "README.md",
    "CONTRIBUTING.md",
    "AGENTS.md",
    "docs/index.md",
    "docs/home-deployment.md"
  ]

  @public_doc_files [
    "docs/index.md",
    "docs/product-documentation.md",
    "docs/guides/buckets-and-views.md",
    "docs/home-deployment.md",
    "docs/integration/api-and-mcp.md",
    "docs/development/story-workflow.md",
    "docs/development/guide.md"
  ]

  @process_claims [
    "staging review",
    "human-reviewed " <> "Epics on staging",
    "GHCR",
    "LXC",
    "Scotty",
    "Judy"
  ]

  @deferred_claims [
    "Yahoo Finance exists",
    "Portfolio Performance import exists",
    "PDF import exists",
    "CSV import exists",
    "broker sync exists",
    "bank sync exists",
    "LLM features exist",
    "trading exists",
    "payment exists",
    "order placement exists",
    "rebalancing exists"
  ]

  # User story:
  # As a public reader evaluating Portfolixir,
  # I want the README to act as the project entry page,
  # so that I see the logo, status badges, purpose, startup steps, contribution links, and license.
  #
  # Acceptance criteria:
  # - The README shows the logo and CI, Elixir/Phoenix, license, and maintenance support badges.
  # - The README explains what Portfolixir is without stale process language.
  # - The README documents how to start the app from source.
  # - The README links to CONTRIBUTING.md, AGENTS.md, docs, support, and LICENSE.
  test "readme is a concise project entry page without stale process context" do
    assert File.read!("docs/CNAME") == "portfolixir.app\n"

    readme = File.read!("README.md")

    for expected <- [
          "priv/static/images/logo-wordmark.svg",
          "actions/workflows/ci.yml/badge.svg",
          "Elixir-Phoenix",
          "github/license",
          "Support-bunq",
          "What is Portfolixir",
          "Quick start",
          "mix deps.get",
          "mix ecto.setup",
          "mix phx.server",
          "[CONTRIBUTING.md](CONTRIBUTING.md)",
          "[AGENTS.md](AGENTS.md)",
          "[docs](docs/index.md)",
          "[LICENSE](LICENSE)"
        ] do
      assert readme =~ expected
    end

    for expected <- [
          "Create securities, one portfolio, and linked cash/depot accounts.",
          "Record manual buy and sell transactions.",
          "Review derived holdings, cash balances, and stored quote history.",
          "Open a security detail chart from local quote history.",
          "Use `/api/v1` and the MCP companion"
        ] do
      assert readme =~ expected
    end

    for rejected <- [
          "re" <> "boot",
          "found" <> "ation reset",
          "not a finished " <> "M" <> "VP",
          "Product backlog",
          "Planka",
          "story cards",
          "human-reviewed " <> "Epics",
          "Use the app in light or dark mode"
        ] do
      refute readme =~ rejected
    end
  end

  # User story:
  # As a public reader of the project docs,
  # I want the Pages domain and public docs to stay accurate and modest,
  # so that the documentation describes the current local self-hosted scope without process claims.
  #
  # Acceptance criteria:
  # - docs/CNAME contains exactly portfolixir.app.
  # - Public docs contain the GitHub Pages landing page and home deployment guide.
  # - Public docs avoid deployment process and deferred capability claims.
  test "public docs use the correct Pages domain and avoid stale capability claims" do
    assert File.read!("docs/CNAME") == "portfolixir.app\n"

    docs_text =
      @doc_files
      |> Enum.map(&File.read!/1)
      |> Enum.join("\n")

    refute docs_text =~ "portfilixir.app"
    assert docs_text =~ "portfolixir.app"
    assert docs_text =~ "Home Deployment"
    assert docs_text =~ "docker compose up --build"
    assert docs_text =~ "mcp-server/"
    assert docs_text =~ "/api/v1"

    for claim <- @deferred_claims do
      refute docs_text =~ claim
    end

    for claim <- @process_claims do
      refute docs_text =~ claim
    end
  end

  # User story:
  # As a public reader using portfolixir.app,
  # I want every public documentation page to render inside one handbook layout with HTML navigation,
  # so that I can move between app, operations, and development docs without landing on raw Markdown.
  #
  # Acceptance criteria:
  # - Public docs pages use the shared Jekyll docs layout.
  # - The docs navigation is data-driven and groups app, operations, and development pages.
  # - Public docs content links to rendered .html pages instead of raw .md files.
  # - The docs stylesheet defines the responsive sidebar layout and Portfolixir accent tokens.
  test "public docs use a shared handbook layout with rendered html navigation" do
    layout = File.read!("docs/_layouts/docs.html")
    navigation = File.read!("docs/_data/navigation.yml")
    docs_css = File.read!("docs/styles.css")

    for doc_file <- @public_doc_files do
      assert File.read!(doc_file) =~ ~r/\A---\nlayout: docs\n/
    end

    assert layout =~ "site.data.navigation"
    assert layout =~ "docs-sidebar"
    assert layout =~ "docs-mobile-nav"
    assert layout =~ "{{ content }}"

    for expected <- [
          "title: Home",
          "title: App Handbook",
          "title: Overview",
          "title: Securities",
          "title: Portfolios and Accounts",
          "title: Transactions and Holdings",
          "title: Quotes and Charts",
          "title: Operations",
          "title: Home Deployment",
          "title: Integration",
          "title: API and MCP",
          "title: Development",
          "title: Story Workflow",
          "title: Development Guide"
        ] do
      assert navigation =~ expected
    end

    for expected <- [
          "url: /index.html",
          "url: /product-documentation.html",
          "url: /product-documentation.html#securities",
          "url: /home-deployment.html",
          "url: /integration/api-and-mcp.html",
          "url: /development/story-workflow.html",
          "url: /development/guide.html"
        ] do
      assert navigation =~ expected
    end

    docs_text =
      @public_doc_files
      |> Enum.map(&File.read!/1)
      |> Enum.join("\n")

    refute docs_text =~ ~r/\]\([^)\n]+\.md(?:#[^)\n]+)?\)/
    refute docs_text =~ ~r/href=["'][^"']+\.md(?:#[^"']*)?["']/

    for selector <- [
          ".docs-layout",
          ".docs-sidebar",
          ".docs-mobile-nav",
          ".docs-main",
          ".docs-content"
        ] do
      assert docs_css =~ selector
    end

    for token <- [
          "--color-accent-violet: #7c3aed",
          "--color-accent-teal: #0f766e",
          "--color-accent-coral: #e11d48"
        ] do
      assert docs_css =~ token
    end
  end

  # User story:
  # As a local integrator using Portfolixir from another tool,
  # I want API and MCP documentation in its own section with the current routes and tools,
  # so that integrations can use the supported local contract without reading source files.
  #
  # Acceptance criteria:
  # - The docs layout serves light and dark logo assets through a theme-aware picture element.
  # - The navigation exposes API and MCP as an Integration section.
  # - The API and MCP page documents authentication, string decimals, every current /api/v1 route,
  #   and every current MCP tool.
  # - The product handbook links to the Integration page instead of embedding the endpoint reference.
  test "integration docs document api routes, mcp tools, and theme-aware logos" do
    layout = File.read!("docs/_layouts/docs.html")
    navigation = File.read!("docs/_data/navigation.yml")
    api_docs = File.read!("docs/integration/api-and-mcp.md")
    normalized_api_docs = String.replace(api_docs, ~r/\s+/, " ")
    product_docs = File.read!("docs/product-documentation.md")

    assert File.exists?("docs/assets/logo-light.svg")
    assert File.exists?("docs/assets/logo-dark.svg")
    assert layout =~ "<picture"
    assert layout =~ "prefers-color-scheme: dark"
    assert layout =~ "logo-dark.svg"
    assert layout =~ "logo-light.svg"

    assert navigation =~ "title: Integration"
    assert navigation =~ "title: API and MCP"
    assert navigation =~ "url: /integration/api-and-mcp.html"

    assert product_docs =~ "[API and MCP](integration/api-and-mcp.html)"
    refute product_docs =~ "## API and MCP"

    for expected <- [
          "Authorization: Bearer <PORTFOLIXIR_API_TOKEN>",
          "`PORTFOLIXIR_API_TOKEN`",
          "`PORTFOLIXIR_MCP_TOKEN`",
          "`PORTFOLIXIR_MCP_TOKEN` is required for HTTP transport",
          "Financial decimals are serialized as strings",
          "`DELETE /api/v1/securities/:id` is the success exception: it returns `204 No Content` with an empty body",
          "holding_status (`all`, `held`, or `not_held`)",
          "MCP tools call the JSON API only"
        ] do
      assert normalized_api_docs =~ expected
    end

    for route <- api_routes_from_router() do
      assert api_docs =~ route
    end

    for tool <- mcp_tools_from_source() do
      assert api_docs =~ tool
    end
  end

  # User story:
  # As an API or MCP client,
  # I want the integration docs to document the money-weighted IRR field on the
  # performance endpoint,
  # so that I can read and interpret it without inspecting source.
  #
  # Acceptance criteria:
  # - The API and MCP page documents the irr field, its money-weighted meaning,
  #   that it is a Decimal string or null, and when no rate exists.
  test "docs document the money-weighted IRR on the performance endpoint" do
    api_docs = File.read!("docs/integration/api-and-mcp.md")
    normalized_api_docs = String.replace(api_docs, ~r/\s+/, " ")

    assert api_docs =~ "`irr`"
    assert normalized_api_docs =~ "money-weighted return"
    assert normalized_api_docs =~ "Decimal string, or `null` when no rate exists"
  end

  # User story:
  # As a local portfolio maintainer configuring quote history,
  # I want the docs to state the researched boundaries for bonds and leveraged products,
  # so that I know which existing providers may help without expecting new adapters or API keys.
  #
  # Acceptance criteria:
  # - The product docs document Portfolio Performance search and Yahoo symbol reuse.
  # - The docs explicitly exclude Ariva, generic Bundesbank ISIN coverage, and API-key defaults.
  # - The docs do not claim a new quote adapter was implemented.
  test "product docs document quote-provider research boundaries" do
    product_docs = File.read!("docs/product-documentation.md")

    for expected <- [
          "Portfolio Performance search can provide symbols for some bonds and leveraged products",
          "Yahoo remains usable when a suitable symbol exists",
          "Ariva is not used as a quote adapter",
          "Bundesbank is relevant for German federal securities and yield data, not a general ISIN quote provider",
          "No API-key-based providers",
          "No new bond or leveraged-product quote adapter is implemented in this batch",
          "Logo discovery runs through a single background queue",
          "logo candidates on startup",
          "triggered after imports",
          "ETF logo discovery tries known issuer names before the individual fund name",
          "Government bonds use the `government_bond` asset class for ISIN country flag fallbacks"
        ] do
      assert product_docs =~ expected
    end
  end

  # User story:
  # As a local integrator with overdraft/reserve accounts,
  # I want the docs to document the cash-account liquidity_role,
  # so that I can classify an account (free cash, credit line, reserve) over the
  # API or MCP without reading source files.
  #
  # Acceptance criteria:
  # - The API and MCP page documents liquidity_role on cash accounts and its
  #   effect on the valuation's deployable cash and cash_quote.
  # - The product handbook describes the role instead of listing it as planned.
  test "docs document the cash-account liquidity_role" do
    api_docs = File.read!("docs/integration/api-and-mcp.md")
    product_docs = File.read!("docs/product-documentation.md")

    assert api_docs =~ "liquidity_role"
    assert api_docs =~ "cash_quote"

    assert product_docs =~ "liquidity role"
    refute product_docs =~ "Still planned: a per-account flag"
  end

  # User story:
  # As a local integrator who steers a cash quote,
  # I want the docs to document the cash target weight and the allocation cash
  # row, so that I can set the cash target and read its drift over the API or
  # MCP without reading source files.
  #
  # Acceptance criteria:
  # - The API and MCP page documents cash_target_weight on the portfolio and the
  #   allocation's cash row (actual/target/drift over the securities + counting
  #   cash basis).
  # - The product handbook describes the cash target as part of the allocation.
  test "docs document the cash target weight and allocation cash row" do
    api_docs = File.read!("docs/integration/api-and-mcp.md")
    normalized_api_docs = String.replace(api_docs, ~r/\s+/, " ")
    product_docs = File.read!("docs/product-documentation.md")

    assert api_docs =~ "cash_target_weight"
    assert normalized_api_docs =~ "carries a `cash` object"
    assert normalized_api_docs =~ "plus the deployable cash"

    assert product_docs =~ "cash target"
  end

  # User story:
  # As a public reader of the Portfolixir docs,
  # I want the documentation page to use the same Portfolixir theme accents as the app,
  # so that the project identity is consistent across app and docs.
  #
  # Acceptance criteria:
  # - The docs landing page links a readable stylesheet.
  # - The docs stylesheet defines the same violet, teal, and coral accent tokens as the app stylesheet.
  # - The docs stylesheet includes light and dark theme rules.
  # - The docs landing page keeps the visible scope focused on local portfolio tracking.
  test "public docs landing page uses the shared light and dark design palette" do
    docs_index = File.read!("docs/index.md")
    docs_layout = File.read!("docs/_layouts/docs.html")
    docs_css = File.read!("docs/styles.css")
    app_css = File.read!("priv/static/app.css")

    assert docs_layout =~ "styles.css"
    assert docs_index =~ "Portfolixir"
    assert docs_index =~ "Local portfolio tracking"
    assert docs_index =~ "Theme, Accent, and Language"
    assert docs_index =~ "system theme"
    assert docs_index =~ "browser language"
    assert docs_index =~ "System, Light, and Dark"
    assert docs_index =~ "Violet, Teal, and Coral"
    assert docs_index =~ "English and German"

    for token <- [
          "--color-accent-violet: #7c3aed",
          "--color-accent-teal: #0f766e",
          "--color-accent-coral: #e11d48"
        ] do
      assert docs_css =~ token
      assert app_css =~ token
    end

    assert docs_css =~ "@media (prefers-color-scheme: dark)"
    assert docs_css =~ ".docs-shell"
  end

  # User story:
  # As a local integrator reviewing received income,
  # I want the docs to document the income report endpoint and tool,
  # so that I can read the dividends and interest aggregation over the API or
  # MCP without reading source files.
  #
  # Acceptance criteria:
  # - The API and MCP page documents the income endpoint, its annual matrix,
  #   per-position rows (gross, withheld tax, net), and the EUR-hub conversion.
  # - The product handbook describes the Income report (dividends and interest)
  #   and no longer lists Dividends as a planned "Soon" entry.
  test "docs document the income report endpoint and tool" do
    api_docs = File.read!("docs/integration/api-and-mcp.md")
    normalized_api_docs = String.replace(api_docs, ~r/\s+/, " ")
    product_docs = File.read!("docs/product-documentation.md")

    assert api_docs =~ "GET /api/v1/portfolios/:portfolio_id/income"
    assert api_docs =~ "portfolixir.portfolios.income"
    assert normalized_api_docs =~ "retrospective income report"
    assert normalized_api_docs =~ "the withheld tax, from the dividend's TAX units"
    assert normalized_api_docs =~ "converted via the EUR hub"

    assert product_docs =~ "## Income (dividends and interest)"
    assert product_docs =~ "`portfolixir.portfolios.income`"
    refute product_docs =~ "**Watchlist**, **Dividends**, and **Returns & risk**"
  end

  # User story:
  # As a local integrator (and the LLM I connect over MCP),
  # I want the docs to document the global per-security EUR valuation endpoint
  # and tool, so that I can read every held security's hub value over the API or
  # MCP without reading source files.
  #
  # Acceptance criteria:
  # - The API and MCP page documents the by_security endpoint and tool, the EUR
  #   hub currency, the as_of read date, the note and the valued flag.
  # - The documented surface appears in both the English and German pages.
  test "docs document the global per-security EUR valuation endpoint and tool" do
    en_api = File.read!("docs/integration/api-and-mcp.md")
    de_api = File.read!("docs/de/integration/api-and-mcp.md")

    for page <- [en_api, de_api] do
      assert page =~ "GET /api/v1/holdings/by_security"
      assert page =~ "portfolixir.holdings.by_security"
      assert page =~ "EUR"
      assert page =~ "as_of"
      assert page =~ "valued"
    end

    en_normalized = String.replace(en_api, ~r/\s+/, " ")
    assert en_normalized =~ "global per-security"
    assert en_normalized =~ "EUR hub"
  end

  # User story:
  # As an API or MCP client reconciling an external position list,
  # I want the docs to document the read-only reconcile endpoint and tool,
  # so that I know the request contract, the ladder matching, the boundary
  # (nothing persisted or logged) and the booking guidance without reading
  # source (ADR-0029 6, FR-35).
  #
  # Acceptance criteria:
  # - EN and DE pages document the endpoint, the tool, matched_via, the
  #   dot-decimal 422 contract and the read-only boundary.
  # - The EN page carries the resolution guidance and the weak-match caveat.
  test "docs document the read-only holdings reconcile endpoint and tool" do
    en_api = File.read!("docs/integration/api-and-mcp.md")
    de_api = File.read!("docs/de/integration/api-and-mcp.md")

    for page <- [en_api, de_api] do
      assert page =~ "POST /api/v1/holdings/reconcile"
      assert page =~ "portfolixir.holdings.reconcile"
      assert page =~ "matched_via"
      assert page =~ "missing_from_list"
      assert page =~ "currency_required"
    end

    en_normalized = String.replace(en_api, ~r/\s+/, " ")
    assert en_normalized =~ "never persisted or logged"
    assert en_normalized =~ "canonical dot-decimal string"

    assert en_normalized =~
             "resolve a difference by booking the missing transaction of the correct kind"

    assert en_normalized =~ "balance snapshots and unpriced deliveries are last resorts"
    assert en_normalized =~ "confirm the security before booking"
  end

  # User story:
  # As a German-speaking reader of the Portfolixir docs,
  # I want the core product handbook and the API/MCP reference available in
  # German alongside English with a language switcher,
  # so that I can read the documented surface in my own language and switch back
  # to the English baseline at will.
  #
  # Acceptance criteria:
  # - The English baseline pages stay in place and carry the EN/DE counterpart
  #   front matter used by the switcher.
  # - German counterparts exist under docs/de/ with the docs layout and DE
  #   front matter, and document the key surface (income endpoint/tool, the
  #   cash/allocation flags) in German.
  # - The shared layout renders a dependency-free language switcher that defaults
  #   to the browser language and persists the choice.
  # - The decision is recorded in ADR-0014 and listed in the ADR index.
  test "core docs are available in English and German with a language switcher" do
    en_product = File.read!("docs/product-documentation.md")
    en_api = File.read!("docs/integration/api-and-mcp.md")

    for baseline <- [en_product, en_api] do
      assert baseline =~ ~r/\A---\nlayout: docs\n/
      assert baseline =~ "lang: en"
      assert baseline =~ "lang_en:"
      assert baseline =~ "lang_de:"
    end

    assert File.exists?("docs/de/product-documentation.md")
    assert File.exists?("docs/de/integration/api-and-mcp.md")

    de_product = File.read!("docs/de/product-documentation.md")
    de_api = File.read!("docs/de/integration/api-and-mcp.md")

    for page <- [de_product, de_api] do
      assert page =~ ~r/\A---\nlayout: docs\n/
      assert page =~ "lang: de"
      assert page =~ "lang_en:"
      assert page =~ "lang_de:"
    end

    # The documented API/MCP surface stays identical (untranslated identifiers).
    for surface <- [
          "GET /api/v1/portfolios/:portfolio_id/income",
          "portfolixir.portfolios.income",
          "GET /api/v1/holdings/by_security",
          "portfolixir.holdings.by_security",
          "liquidity_role",
          "cash_target_weight"
        ] do
      assert en_api =~ surface
      assert de_api =~ surface
    end

    # German prose is actually present (not an English copy).
    assert de_product =~ "Produktdokumentation"
    assert de_product =~ "Bestände"
    assert de_api =~ "Authentifizierung"
    assert de_api =~ "Wertpapiere"

    # The shared layout carries the dependency-free switcher and its behavior.
    layout = File.read!("docs/_layouts/docs.html")
    assert layout =~ "docs-lang-switch"
    assert layout =~ "data-lang=\"en\""
    assert layout =~ "data-lang=\"de\""
    assert layout =~ "localStorage"
    assert layout =~ "navigator.language"
    assert layout =~ "portfolixir-docs-lang"

    # The decision is recorded.
    adr = File.read!("docs/decisions/0014-bilingual-docs-site.md")
    assert adr =~ "ADR-0014"
    assert adr =~ "Status:** Accepted"
    assert File.read!("docs/decisions/index.md") =~ "0014-bilingual-docs-site.html"
  end

  # User story:
  # As a local portfolio maintainer tracking currency exposure,
  # I want the docs to document that the Currency allocation view attributes
  # cash to its currency bucket (EUR cash → EUR, USD cash → USD),
  # so that I understand the behaviour without reading source code (issue #407).
  #
  # Acceptance criteria:
  # - The product handbook describes that cash is attributed to currency
  #   buckets in the Currency classification view.
  # - The API/MCP page documents the `distributed` field on the cash object.
  # - The German product handbook also carries the description.
  test "docs document currency allocation cash attribution (issue #407)" do
    product_docs = File.read!("docs/product-documentation.md")
    api_docs = File.read!("docs/integration/api-and-mcp.md")
    de_product = File.read!("docs/de/product-documentation.md")
    de_api = File.read!("docs/de/integration/api-and-mcp.md")

    assert product_docs =~ "Currency allocation: cash by currency"
    assert product_docs =~ "currency bucket"
    assert product_docs =~ "asset-class view is unaffected"

    assert api_docs =~ "distributed"
    assert api_docs =~ "currency classification"

    assert de_product =~ "Währungsallokation"
    assert de_api =~ "distributed"
  end

  # User story:
  # As a Portfolixir user mapping real grouping needs onto buckets and views,
  # I want a worked use-case guide in English and German,
  # so that I can set up a household split, strategy views, my old Portfolio
  # Performance habits, and steering exclusions without reverse-engineering
  # the model (issue #573, ADR-0024).
  #
  # Acceptance criteria:
  # - The guide exists as an EN baseline with a DE counterpart, carries the
  #   docs layout and language-switcher front matter, and is in the navigation.
  # - It covers the household split (counts-once guarantee and overlap badge),
  #   a strategy view with a view-bound target plan, the PP-migrator habit
  #   (import tag, seeded buckets/views, compatibility panel), and the
  #   count-but-don't-steer exclusion.
  # - It offers a "bucket or view?" decision paragraph, warns that re-tagging
  #   changes historical series ("Composition as of today"), and links
  #   ADR-0024. Screenshot placeholders mark where images belong.
  # - The product handbook and the guide cross-link in both languages.
  test "docs provide a worked bucket/view use-case guide in English and German (#573)" do
    en = File.read!("docs/guides/buckets-and-views.md")
    de = File.read!("docs/de/guides/buckets-and-views.md")
    navigation = File.read!("docs/_data/navigation.yml")
    en_product = File.read!("docs/product-documentation.md")
    de_product = File.read!("docs/de/product-documentation.md")

    for page <- [en, de] do
      assert page =~ ~r/\A---\nlayout: docs\n/
      assert page =~ "lang_en: /guides/buckets-and-views.html"
      assert page =~ "lang_de: /de/guides/buckets-and-views.html"
      assert page =~ "0024-buckets-and-views-replace-portfolios-in-the-ui.html"
      assert page =~ "<!-- screenshot:"
    end

    assert en =~ "lang: en"
    assert de =~ "lang: de"

    assert navigation =~ "title: Buckets & Views Guide"
    assert navigation =~ "url: /guides/buckets-and-views.html"

    # The four worked use cases, the decision help, and the retroactivity
    # warning use the exact UI labels of each language.
    en_normalized = String.replace(en, ~r/\s+/, " ")

    for expected <- [
          "Which do I need — a bucket or a view?",
          "counted exactly once",
          "Overlapping buckets — accounts counted once",
          "Set as default",
          "Views",
          "Everything",
          "Target plan for view:",
          "Save plan",
          "PP Import",
          "Portfolio records (compatibility)",
          "No tag — leave the new accounts untagged",
          "Exclude buckets",
          "Composition as of today"
        ] do
      assert en_normalized =~ expected
    end

    de_normalized = String.replace(de, ~r/\s+/, " ")

    for expected <- [
          "Brauche ich einen Bucket oder eine Ansicht?",
          "genau einmal gezählt",
          "Überlappende Buckets – Konten nur einmal gezählt",
          "Als Standard festlegen",
          "Ansichten",
          "Alles",
          "Soll-Plan für Sicht:",
          "Plan speichern",
          "PP Import",
          "Portfoliodatensätze (Kompatibilität)",
          "Kein Tag – die neuen Konten bleiben ohne Bucket",
          "Buckets ausschließen",
          "Zusammensetzung per heute"
        ] do
      assert de_normalized =~ expected
    end

    # The handbook and the guide cross-link in both languages.
    assert en_product =~ "guides/buckets-and-views.html"
    assert de_product =~ "guides/buckets-and-views.html"
    assert en =~ "/product-documentation.html"
    assert de =~ "/de/product-documentation.html"
  end

  # Only the `/api/v1` scope, not every verb macro in the file. The browser
  # scopes carry routes that are not API surface at all -- the `/income` ->
  # `/cashflow` rename redirect (#672) is one -- and scanning the whole router
  # asserted they were undocumented endpoints. `/health` lives outside the
  # scope and is documented separately, so it keeps its own case.
  defp api_routes_from_router do
    router = File.read!("lib/portfolixir_web/router.ex")

    ~r/\b(get|post|put|patch|delete)\("([^"]+)"/
    |> Regex.scan(api_v1_scope(router))
    |> Enum.map(fn [_, verb, path] -> "#{String.upcase(verb)} /api/v1#{path}" end)
  end

  # The body of `scope "/api/v1", ... do ... end`, to the end of the file --
  # it is the last scope in the router, and a new scope after it would show up
  # here as an obvious over-match rather than as a silent under-match.
  defp api_v1_scope(router) do
    case String.split(router, ~s|scope "/api/v1"|, parts: 2) do
      [_before, scope] -> scope
      [_only] -> ""
    end
  end

  defp mcp_tools_from_source do
    tools = File.read!("mcp-server/src/tools.ts")

    ~r/tool\("([^"]+)"/
    |> Regex.scan(tools)
    |> Enum.map(fn [_, tool] -> tool end)
  end

  # User story (#776 — Sprint 11 Lane W):
  # As the operator's agent reading the API reference in either language,
  # I want every collection read of the limit family to name its bound,
  # so that the surface check of the close-out can point at the sentence
  # instead of at a promise.
  #
  # Acceptance criteria:
  # - Each of the twelve reads (the four #771 reads, the four research-log
  #   reads, the snapshot list, the three roll-ups, the trades read) has a
  #   bullet in the English and the German reference that mentions `limit`
  #   — as its bound, or as the bound it deliberately does not carry.
  test "every collection read of the limit family names its bound, in English and German" do
    en = File.read!("docs/integration/api-and-mcp.md")
    de = File.read!("docs/de/integration/api-and-mcp.md")

    endpoints = [
      "GET /api/v1/securities/:security_id/notes",
      "GET /api/v1/notes/unreviewed",
      "GET /api/v1/notes/uncorroborated",
      "GET /api/v1/notes/expiring",
      "GET /api/v1/securities/:security_id/quotes",
      "GET /api/v1/transactions",
      "GET /api/v1/realized_gains",
      "GET /api/v1/external_flows",
      "GET /api/v1/costs",
      "GET /api/v1/snapshots",
      "GET /api/v1/securities/:security_id/trades",
      "GET /api/v1/exchange_rates"
    ]

    for endpoint <- endpoints, {language, text} <- [{"en", en}, {"de", de}] do
      bullet =
        text
        |> String.split("\n- ")
        |> Enum.find(&String.starts_with?(&1, "`" <> endpoint))

      assert bullet, "#{language}: no bullet for #{endpoint}"
      assert bullet =~ "`limit`", "#{language}: #{endpoint} does not name its bound"
    end
  end

  # User story (#844):
  # As a reader of the published documentation site,
  # I want every page's front matter to parse,
  # so that no page is published as an unstyled fragment without its layout,
  # title and description.
  #
  # Acceptance criteria:
  # - No front-matter value in `docs/**/*.md` is an unquoted (plain) scalar
  #   that YAML cannot parse: a plain value may not contain ": " or " #", nor
  #   end in ":". Such a value makes Psych — the parser Jekyll uses — raise
  #   "mapping values are not allowed in this context"; without
  #   `strict_front_matter` Jekyll then drops the whole front matter and
  #   publishes the page with no layout, no <title> and no meta description.
  #
  # The check is deliberately narrower than a full YAML parse: `yaml_elixir`
  # is only a transitive dependency (of `mix_audit`, dev/test, runtime: false),
  # and making it a direct one is a dependency change outside this story. The
  # front matter in `docs/` is flat `key: value` lines, and the three rules
  # above are the plain-scalar restrictions such a line can break.
  test "every docs page's front matter is flat key: value lines YAML can parse" do
    pages = Path.wildcard("docs/**/*.md")
    refute pages == []

    offenders =
      for path <- pages,
          [_, front_matter] <- [Regex.run(~r/\A---\r?\n(.*?)\r?\n---\r?\n/s, File.read!(path))],
          line <- String.split(front_matter, ~r/\r?\n/),
          [_, key, value] <- [Regex.run(~r/\A([A-Za-z_][\w-]*):[ \t]+(\S.*)\z/, line)],
          not String.starts_with?(value, ["\"", "'", "|", ">", "[", "{"]),
          String.contains?(value, [": ", " #"]) or String.ends_with?(value, ":") do
        "#{path}: #{key}"
      end

    assert offenders == [], """
    these front-matter values are unquoted but contain ": " or " #" (or end
    in ":"), so YAML cannot parse them and Jekyll publishes the page without
    its front matter. Quote the value:

    #{Enum.join(offenders, "\n")}
    """
  end

  # User story (#354, FR-29 rescoped 2026-07-22):
  # As a self-hoster without PostgreSQL knowledge,
  # I want the deployment guide to carry the backup, the restore and the
  # check that the restore lost nothing,
  # so that retiring my external copies is safe.
  #
  # Acceptance criteria:
  # - EN and DE both carry the pg_dump backup and the pg_restore restore as
  #   `docker compose exec` invocations for the shipped Compose file, with the
  #   application stopped before the restore (it migrates on start).
  # - Both name the verification: total value, holdings count, one position.
  # - Both state that the dump holds all data, strategy configuration and the
  #   audit journal included, and that `.env` is not in it.
  test "the deployment guide documents backup, restore and the restore check" do
    for path <- ["docs/home-deployment.md", "docs/de/home-deployment.md"] do
      doc = File.read!(path)

      assert doc =~ "pg_dump -U portfolixir -d portfolixir_prod --format=custom", path
      assert doc =~ "docker compose stop app mcp", path

      assert doc =~
               "pg_restore -U portfolixir -d portfolixir_prod --no-owner --exit-on-error",
             path

      assert doc =~ "/portfolios/1/valuation", path
      assert doc =~ "/portfolios/1/holdings", path
      assert doc =~ "`.env`", path
    end

    # Prose wraps at any word; compare it with the line breaks folded.
    en = "docs/home-deployment.md" |> File.read!() |> String.replace(~r/\s+/, " ")
    assert en =~ "total value, the number of holdings, and one position"
    assert en =~ "target plans"
    assert en =~ "audit journal"

    de = "docs/de/home-deployment.md" |> File.read!() |> String.replace(~r/\s+/, " ")
    assert de =~ "Gesamtwert, die Anzahl der Bestände und eine bekannte Position"
    assert de =~ "SOLL-Pläne"
    assert de =~ "Audit-Journal"
  end

  # User story (E25 S1, F05; T-4 of the 2026-09-24 triage):
  # As an operator deciding how to end a login,
  # I want SECURITY.md and the deployment guide to say what a logout and a
  # zero session lifetime actually do,
  # so that I reach for the lever that also ends a copied session cookie.
  #
  # Acceptance criteria:
  # - SECURITY.md and the EN and DE deployment pages say that a logout clears
  #   the login in that browser only, and that a copy of the cookie stays valid.
  # - All three say that a lifetime of 0 turns the server-side expiry off.
  # - All three name the two levers that end every session: changing the UI
  #   password and rotating SECRET_KEY_BASE.
  # - The former wording (a logout ends the session; 0 ends the login when the
  #   browser closes) is gone; .env.example carries the corrected lifetime line.
  test "the revocation and lifetime wording says what the code does" do
    read = fn path -> path |> File.read!() |> String.replace(~r/\s+/, " ") end

    security = read.("SECURITY.md")
    assert security =~ "a logout clears the login in that browser only"
    assert security =~ "a copy of the session cookie taken earlier stays valid"
    assert security =~ "`PORTFOLIXIR_SESSION_DAYS=0` turns the server-side expiry off"
    assert security =~ "changing `PORTFOLIXIR_UI_PASSWORD`"
    assert security =~ "rotating `SECRET_KEY_BASE` ends every session everywhere"
    refute security =~ "a logout ends that session"

    en = read.("docs/home-deployment.md")
    assert en =~ "A logout clears the login in that browser only"
    assert en =~ "a copy of the session cookie taken earlier stays valid"
    assert en =~ "`0` turns the server-side expiry off"
    assert en =~ "change `PORTFOLIXIR_UI_PASSWORD` or rotate `SECRET_KEY_BASE`"
    refute en =~ "`0` ends the login when the browser closes."

    de = read.("docs/de/home-deployment.md")
    assert de =~ "Eine Abmeldung beendet die Anmeldung nur in diesem Browser"
    assert de =~ "eine vorher genommene Kopie des Sitzungs-Cookies bleibt gültig"
    assert de =~ "`0` schaltet den serverseitigen Ablauf ab"
    assert de =~ "ändere `PORTFOLIXIR_UI_PASSWORD` oder rotiere `SECRET_KEY_BASE`"
    refute de =~ "`0` beendet die Anmeldung mit dem Schließen des Browsers."

    env_example = read.(".env.example")
    assert env_example =~ "0 turns the server-side expiry off"
    refute env_example =~ "0 means the login ends when the browser closes"
  end

  # User story (E25 S1, F57):
  # As an operator configuring the reverse proxy,
  # I want the proxy contract to have the proxy set or append the forwarding
  # headers itself, and to name one exact proxy address,
  # so that no client can hand the throttle a source of its own choosing.
  #
  # Acceptance criteria:
  # - EN and DE say the proxy appends the connecting address to X-Forwarded-For
  #   or overwrites it, sets X-Forwarded-Proto itself, and never passes a value
  #   the client sent through; the "forwarded unchanged" wording is gone.
  # - Both give the nginx and the HAProxy directives.
  # - Both recommend a single trusted-proxy address and no longer suggest a
  #   broad private block.
  # - SECURITY.md states the same contract.
  test "the reverse-proxy contract has the proxy set or append the forwarding headers" do
    read = fn path -> path |> File.read!() |> String.replace(~r/\s+/, " ") end

    for {path, append, never, unchanged} <- [
          {"docs/home-deployment.md",
           "appends the connecting address to `X-Forwarded-For` or overwrites it",
           "never passes a value the client sent through", "`X-Forwarded-For` unchanged"},
          {"docs/de/home-deployment.md",
           "hängt die verbindende Adresse an `X-Forwarded-For` an oder überschreibt den Header",
           "reicht nie einen Wert durch, den der Client geschickt hat",
           "`X-Forwarded-For` unverändert"}
        ] do
      doc = read.(path)
      assert doc =~ append, path
      assert doc =~ never, path
      refute doc =~ unchanged, path

      assert doc =~ "proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;", path
      assert doc =~ "proxy_set_header X-Forwarded-Proto $scheme;", path
      assert doc =~ "option forwardfor", path
      assert doc =~ "http-request set-header X-Forwarded-Proto https if { ssl_fc }", path

      assert doc =~ "PORTFOLIXIR_TRUSTED_PROXIES=172.18.0.1", path
      refute doc =~ "172.16.0.0/12", path
    end

    security = read.("SECURITY.md")
    assert security =~ "appends the connecting address to `X-Forwarded-For` or overwrites it"
    assert security =~ "never passes a value the client sent through"
    refute security =~ "`X-Forwarded-For` unchanged"
  end

  # User story (E25 S2, F54):
  # As an operator restoring a backup,
  # I want the restore to be all or nothing, the instance started only after
  # it succeeded, and a check that the database's guards came back,
  # so that a failed restore can never leave a database without its
  # append-only and journal triggers behind a running instance.
  #
  # Acceptance criteria:
  # - The restore step (EN, DE) runs pg_restore with --exit-on-error and
  #   --single-transaction.
  # - Both say to start the instance only once the restore ended without error.
  # - Both compare the number of database triggers before the backup and
  #   after the restore.
  test "the restore is one transaction, and its check counts the triggers" do
    trigger_count = "SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal"

    for {path, start_only} <- [
          {"docs/home-deployment.md", "Only if step 3 ended without an error"},
          {"docs/de/home-deployment.md", "Nur wenn Schritt 3 ohne Fehler endete"}
        ] do
      doc = path |> File.read!() |> String.replace(~r/\s*\\\n\s*/, " ")

      assert doc =~
               "pg_restore -U portfolixir -d portfolixir_prod --no-owner --exit-on-error --single-transaction",
             path

      assert doc =~ start_only, path
      assert doc =~ trigger_count, path
    end
  end
end
