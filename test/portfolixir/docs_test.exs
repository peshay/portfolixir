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
    "docs/features.md",
    "docs/de/features.md",
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

  # User story (Sprint 17 A6, #981):
  # As a newcomer landing on the repository, or the agent reading it for them,
  # I want the first screen to say what Portfolixir is and how my existing
  # data gets in, before badges, pictures and philosophy,
  # so that I can tell in one screen whether it fits.
  #
  # Acceptance criteria:
  # - Above the badges the README states what it is (self-hosted, for the
  #   operator and their agent, no broker connection, no advice) and how data
  #   gets in: a Portfolio Performance CSV or JSON export on the Imports page,
  #   the import_converter prompt, booking by hand; that there is no bank or
  #   broker sync; and that broker-PDF intake is decided but not built.
  # - No picture but the logo sits above the badges, and it points an agent to
  #   llms.txt.
  # - One line says how the project is built: with LLM coding agents, every
  #   commit owned by an accountable human.
  test "the README's first screen says what it is and how data gets in" do
    readme = File.read!("README.md")
    [first_screen, _rest] = String.split(readme, "[![CI]", parts: 2)
    flat = String.replace(first_screen, ~r/\s+/, " ")

    for fragment <- [
          "self-hosted",
          "the LLM agent you run",
          "## How your data gets in",
          "Portfolio Performance",
          "CSV or JSON v1",
          "Imports page",
          "`import_converter`",
          "By hand",
          "There is no bank or broker sync",
          "Broker PDFs",
          "not built",
          "https://portfolixir.app/llms.txt"
        ] do
      assert flat =~ fragment, fragment
    end

    refute first_screen =~ "![", "a picture above the badges"
    assert readme =~ "## What is Portfolixir"

    assert String.replace(readme, ~r/\s+/, " ") =~
             "written with LLM coding agents, and every commit is owned by an accountable human"
  end

  # User story (#935, F76's follow-up):
  # As someone who runs `docker compose up --build` straight from the README,
  # I want the README's prerequisites to name the minimum Docker Engine and
  # point to why,
  # so that the loopback-only reach the guide promises holds on my engine.
  #
  # Acceptance criteria:
  # - The README's prerequisites name Docker Engine 28.3.3 or newer and link
  #   the home deployment guide's prerequisites for the reason.
  test "the README names the Docker Engine minimum and points to the reason" do
    readme = File.read!("README.md") |> String.replace(~r/\s+/, " ")

    assert readme =~ "Docker Engine 28.3.3 or newer"
    assert readme =~ "(docs/home-deployment.md#prerequisites)"
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
          "--color-accent-coral: #ce1b42"
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
          "--color-accent-coral: #ce1b42"
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

  # User story (closing-act findings SR-3 and SR-4):
  # As an operator who publishes the application and the MCP companion on the
  # host's loopback, as the Compose file does,
  # I want the guide to say that every client on the host reaches them from
  # the one Docker bridge gateway address,
  # so that I know naming that address trusts every local process's
  # forwarding headers, and that a local process sending wrong tokens to the
  # companion locks my agent out with it.
  #
  # Acceptance criteria:
  # - The Reverse proxy section (EN, DE) says every client on the host arrives
  #   from the gateway address, so naming it trusts their forwarding headers
  #   too, and names the way to trust the proxy alone: attach it to the
  #   stack's network and name its container address.
  # - The companion's section (EN, DE) says the companion counts failed tokens
  #   per connecting address, that a local process sending wrong tokens locks
  #   the agent out, and that restarting the companion clears the counts.
  # - SECURITY.md says both.
  test "the guide says every host client shares the bridge gateway address" do
    read = fn path -> path |> File.read!() |> String.replace(~r/\s+/, " ") end

    for {path, shared, network, lockout, restart} <- [
          {"docs/home-deployment.md", "every client on the host arrives from that same address",
           "attach the proxy to the stack's network and name its container address",
           "a process on the host that sends a wrong token locks your agent out too",
           "`docker compose restart mcp`"},
          {"docs/de/home-deployment.md", "jeder Client auf dem Host kommt von derselben Adresse",
           "hänge den Proxy an das Netzwerk des Stacks und nenne seine Container-Adresse",
           "ein Prozess auf dem Host, der ein falsches Token schickt, sperrt auch deinen Agenten aus",
           "`docker compose restart mcp`"}
        ] do
      doc = read.(path)

      for fragment <- [shared, network, lockout, restart] do
        assert doc =~ fragment, "#{path}: #{fragment}"
      end
    end

    security = read.("SECURITY.md")

    assert security =~
             "every client on the host reaches the published ports from that one address"

    assert security =~ "the MCP companion counts failed tokens per connecting address"
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

  # User story (E25 S2, F50; T-6 of the 2026-09-24 triage: documented, not
  # migrated):
  # As an operator setting up a new instance,
  # I want the deployment guide to give me a table-owner role that is not a
  # superuser and a runtime role without TRUNCATE, with the SQL,
  # so that the append-only and journal triggers bind the credential the
  # application holds, not only its code.
  #
  # Acceptance criteria:
  # - EN and DE carry the SQL: the two roles, the database handed to the owner,
  #   and the runtime role's grants by default privileges, with no TRUNCATE.
  # - Both wire it: the application connects as the runtime role, the
  #   migrations run as the owner in a one-off service, and a restore runs as
  #   the owner.
  # - Both say it is for a new install and that an existing instance's move is
  #   not described; SECURITY.md names the shipped default as a known limit.
  test "the deployment guide recommends an owner role and a runtime role without TRUNCATE" do
    read = fn path -> path |> File.read!() |> String.replace(~r/\s+/, " ") end

    for {path, owner_words, runtime_words, new_install} <- [
          {"docs/home-deployment.md", "not a superuser", "holds no `TRUNCATE`",
           "Moving an existing instance onto these roles"},
          {"docs/de/home-deployment.md", "kein Superuser", "hat kein `TRUNCATE`",
           "Eine bestehende Instanz auf diese Rollen umzustellen"}
        ] do
      doc = read.(path)

      for fragment <- [
            "CREATE ROLE portfolixir_owner LOGIN",
            "CREATE ROLE portfolixir_app LOGIN",
            "ALTER DATABASE portfolixir_prod OWNER TO portfolixir_owner;",
            "GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO portfolixir_app;",
            "GRANT USAGE, SELECT ON SEQUENCES TO portfolixir_app;",
            "DATABASE_URL: postgres://portfolixir_app:",
            "DATABASE_URL: postgres://portfolixir_owner:",
            "docker compose run --rm --build migrate",
            "--role=portfolixir_owner",
            owner_words,
            runtime_words,
            new_install
          ] do
        assert doc =~ fragment, "#{path}: #{fragment}"
      end

      refute doc =~ ~r/GRANT[^;]*TRUNCATE[^;]*TO portfolixir_app/, path
    end

    security = read.("SECURITY.md")
    assert security =~ "connects as the database's bootstrap superuser"
  end

  # User story (E25 S2, F76):
  # As an operator running the Compose deployment,
  # I want the guide to say what actually keeps the instance on my machine,
  # which Docker Engine that needs, and why the startup warning appears,
  # so that I rely on the loopback reach only where it holds, and set a UI
  # password where it does not.
  #
  # Acceptance criteria:
  # - EN and DE name Docker Engine 28.3.3 or newer as a prerequisite, with why.
  # - Both qualify the reach: in Compose the port mapping, not the application,
  #   keeps it on the host's loopback; the unqualified "binds loopback" claim
  #   for the Compose instance is gone.
  # - Both recommend a UI password for a Compose install and explain why the
  #   warning appears there.
  # - ADR-0045 records the qualification as an amendment.
  test "the Compose reach is qualified and the engine prerequisite named" do
    read = fn path -> path |> File.read!() |> String.replace(~r/\s+/, " ") end

    for {path, engine, reach, password, gone} <- [
          {"docs/home-deployment.md", "Docker Engine 28.3.3 or newer",
           "the port mapping, not the application, keeps it on the host's loopback",
           "Set `PORTFOLIXIR_UI_PASSWORD` for a Compose install",
           "the instance binds loopback and refuses"},
          {"docs/de/home-deployment.md", "Docker Engine 28.3.3 oder neuer",
           "die Port-Zuordnung, nicht die Anwendung, hält sie auf dem Loopback des Hosts",
           "Setze für eine Compose-Installation `PORTFOLIXIR_UI_PASSWORD`",
           "die Instanz bindet Loopback und weist"}
        ] do
      doc = read.(path)
      assert doc =~ engine, path
      assert doc =~ "CVE-2025-54388", path
      assert doc =~ reach, path
      assert doc =~ password, path
      refute doc =~ gone, path
    end

    adr = read.("docs/decisions/0045-optional-built-in-authentication.md")
    assert adr =~ "Amendment, 2026-09-24 (E25 S2, #887): the loopback-only reach, qualified."
    assert adr =~ "Docker Engine 28.3.3"
  end

  # User story (E25 S1 and S2, review round):
  # As an operator upgrading an instance that already runs,
  # I want the upgrade steps to name what this security pass changes for it,
  # and the guide to say how the login comes back when the ceiling holds it,
  # so that the upgrade brings no redirect loop, no cookie silently without
  # Secure, no refused start and no login I cannot reach.
  #
  # Acceptance criteria:
  # - The Upgrade section (EN, DE) says to name a proxy that reaches the
  #   container through the Docker bridge in PORTFOLIXIR_TRUSTED_PROXIES before
  #   upgrading, or PHX_FORCE_SSL loops and the cookie loses Secure; that every
  #   browser logs in once; and that the MCP token and SECRET_KEY_BASE must meet
  #   their floors.
  # - EN, DE and SECURITY.md say that restarting the application lifts the
  #   login ceiling, and that sessions already logged in keep working.
  # - EN and DE say to check the bridge gateway's address again when the
  #   stack's network is recreated.
  test "the upgrade names the security pass's changes and the ceiling its way out" do
    read = fn path -> path |> File.read!() |> String.replace(~r/\s+/, " ") end

    upgrade_section = fn doc ->
      [_, rest] = String.split(doc, "## Upgrade ", parts: 2)
      rest |> String.split(" ## ", parts: 2) |> hd()
    end

    for {path, from, login, restart, recheck} <- [
          {"docs/home-deployment.md", "Upgrading from 0.15.x or earlier",
           "every browser logs in once after the upgrade",
           "Restarting the application clears the counts, the ceiling's included",
           "check it again whenever the stack's network is recreated"},
          {"docs/de/home-deployment.md", "Beim Upgrade von 0.15.x oder älter",
           "jeder Browser meldet sich nach dem Upgrade einmal neu an",
           "Ein Neustart der Anwendung löscht die Zählungen, die der Obergrenze eingeschlossen",
           "prüfe sie erneut, wann immer das Netzwerk des Stacks neu angelegt wird"}
        ] do
      doc = read.(path)
      upgrade = upgrade_section.(doc)

      for fragment <- [
            from,
            login,
            "PORTFOLIXIR_TRUSTED_PROXIES",
            "PHX_FORCE_SSL=true",
            "`Secure`",
            "PORTFOLIXIR_MCP_TOKEN",
            "SECRET_KEY_BASE"
          ] do
        assert upgrade =~ fragment, "#{path} (Upgrade): #{fragment}"
      end

      assert doc =~ restart, path
      assert doc =~ recheck, path
    end

    security = read.("SECURITY.md")
    assert security =~ "restarting the application clears it"
  end

  # User story (E25 S2, F56):
  # As an operator keeping the instance's secrets and backups,
  # I want the guide's commands to create them readable by me only, outside
  # the checkout, and to keep the token off every command line,
  # so that another local user cannot read my secrets file, a full backup of
  # my data, or the token in the process list.
  #
  # Acceptance criteria:
  # - EN and DE create .env with mode 600 and take backups under umask 077 into
  #   a directory outside the checkout, and say to encrypt a copy that leaves
  #   the machine.
  # - The restore check passes the token to curl on standard input, never as a
  #   command-line argument.
  # - .gitignore covers dump files and the logo archives.
  test "secrets and backups are created private and the token stays off the command line" do
    for {path, encrypt} <- [
          {"docs/home-deployment.md", "encrypt it first"},
          {"docs/de/home-deployment.md", "vorher verschlüsseln"}
        ] do
      doc = path |> File.read!() |> String.replace(~r/\s+/, " ")

      for fragment <- [
            "install -m 600 .env.example .env",
            "umask 077",
            "> ~/portfolixir-backups/portfolixir-$(date +%F).dump",
            "< ~/portfolixir-backups/portfolixir-2026-09-23.dump",
            "curl -s -H @-",
            encrypt
          ] do
        assert doc =~ fragment, "#{path}: #{fragment}"
      end

      refute doc =~ ~s(-H "Authorization: Bearer $TOKEN"), path
    end

    assert File.read!("README.md") =~ "install -m 600 .env.example .env"

    gitignore = File.read!(".gitignore")
    assert gitignore =~ ~r/^\*\.dump$/m
    assert gitignore =~ ~r/^portfolixir-logos-\*\.tar$/m
  end

  # User story:
  # As the operator or the agent correcting an account or a security,
  # I want the handbook and the API page to say, in English and German, when
  # a currency or a portfolio binding freezes and what a frozen change
  # answers,
  # so that a refused edit is expected, not a surprise (ADR-0050 §11).
  #
  # Acceptance criteria:
  # - The API page, both languages, states the currency freeze on the
  #   security and the cash-account PATCH with its 422 and its counted error.
  # - The handbook, both languages, states the security freeze on every path
  #   including the search dialog's merge, and the accounts' currency and
  #   binding freeze.
  test "the docs state the identity-field freezes in English and German" do
    for {path, fragments} <- [
          {"docs/integration/api-and-mcp.md",
           [
             "`currency_code` **freezes** once it has a transaction or a quote",
             "`currency_code` **freezes** once a transaction references the account",
             "is frozen once referenced (1 securities account, 12 transactions)"
           ]},
          {"docs/de/integration/api-and-mcp.md",
           [
             "**friert ein**, sobald es eine Transaktion oder einen Kurs hat",
             "**friert ein**, sobald eine Transaktion über eines ihrer beiden Konten",
             "is frozen once referenced (1 securities account, 12 transactions)"
           ]},
          {"docs/product-documentation.md",
           [
             "### Identity fields that freeze (ADR-0050 §11)",
             "**Merge online fields** and **Update existing**",
             "**Currency and binding freeze once referenced**"
           ]},
          {"docs/de/product-documentation.md",
           [
             "### Identitätsfelder, die einfrieren (ADR-0050 §11)",
             "**Online-Felder übernehmen** und **Vorhandenes aktualisieren**",
             "**Währung und Bindung frieren ein, sobald verwiesen**"
           ]}
        ] do
      doc = path |> File.read!() |> String.replace(~r/\s+/, " ")

      for fragment <- fragments do
        assert doc =~ fragment, "#{path}: #{fragment}"
      end
    end
  end

  # User story:
  # As the operator re-importing an export, or the agent that renamed an
  # imported account,
  # I want the handbook and the API page to say, in English and German, what
  # the import checks before it creates anything, when an account is created,
  # what happens to an internal transfer and which rows collapse,
  # so that a skipped row or an account that was not created is expected
  # (ADR-0050 §3–§6, L2, #884).
  #
  # Acceptance criteria:
  # - The handbook, both languages, states the hash-first check with the
  #   retired hash, the lazy account creation with the bucket tag and the
  #   rename case, the internal-transfer skip, and the collapse scoped by the
  #   file's accounts.
  # - The API page, both languages, states the rename case for the two
  #   account update routes and tools.
  test "the docs state the re-import contract's importer half in English and German" do
    for {path, fragments} <- [
          {"docs/product-documentation.md",
           [
             "### What a re-import checks first (ADR-0050)",
             "**before anything is resolved or created**",
             "**retired content hash**",
             "created **with their first imported booking**, never up front",
             "the bucket tag lands on exactly the accounts the import created",
             "creates no empty account under the old name",
             "**transfer whose two sides lead to the same account or depot**",
             "Only rows of the same Portfolio Performance account collapse"
           ]},
          {"docs/de/product-documentation.md",
           [
             "### Was ein erneuter Import zuerst prüft (ADR-0050)",
             "**bevor irgendetwas aufgelöst oder angelegt wird**",
             "**stillgelegter Inhalts-Hash**",
             "entstehen **mit ihrer ersten importierten Buchung**, nie vorab",
             "der Bucket-Tag landet auf genau den Konten, die der Import angelegt hat",
             "legt kein leeres Konto unter dem alten Namen an",
             "**Umbuchung, deren beide Seiten auf dasselbe Konto oder Depot führen**",
             "Zusammengefasst werden nur Zeilen desselben Portfolio-Performance-Kontos"
           ]},
          {"docs/integration/api-and-mcp.md",
           [
             "The hash is checked before anything resolves",
             "a cash account or depot is created only with its first new booking",
             "leaves no empty account under the old name"
           ]},
          {"docs/de/integration/api-and-mcp.md",
           [
             "Der Hash wird geprüft, bevor irgendetwas aufgelöst wird",
             "ein Verrechnungskonto oder Depot entsteht erst mit seiner ersten neuen Buchung",
             "kein leeres Konto unter dem alten Namen hinterlässt"
           ]}
        ] do
      doc = path |> File.read!() |> String.replace(~r/\s+/, " ")

      for fragment <- fragments do
        assert doc =~ fragment, "#{path}: #{fragment}"
      end
    end
  end

  # User story:
  # As the operator or the agent renaming an imported account, or mapping an
  # export's account onto one of another name,
  # I want the handbook and the API page to say, in English and German, that
  # the old name is kept as a former name, how the import resolves a name,
  # what remembering a remap does and what removing a former name costs,
  # so that a routed row is expected and a refused name is understood
  # (ADR-0050 §4, §10; L2, #884).
  #
  # Acceptance criteria:
  # - The handbook, both languages, states the name rule on Accounts &
  #   depots, and on the import the live-then-former resolution, the drifted
  #   re-export, the undecided ambiguous name, the remembered remap (a
  #   changed prefill only; a move said in the row before the confirm, L5b)
  #   and its limit, the refreshed stale mapping and the upgrade's backfill.
  # - The API page, both languages, states former_names on the payloads, the
  #   rename cases, the guard's 422 and the removal route with its cost.
  test "the docs state former names, the name guard and the remembered remap in English and German" do
    for {path, fragments} <- [
          {"docs/product-documentation.md",
           [
             "**Names and former names** (ADR-0050 §4)",
             "keeps its previous name as a **former name**",
             "**Accounts are found by name, then by former name.**",
             "a re-export that changed inside Portfolio Performance",
             "A name two accounts carry is prefilled with nothing",
             "**remembers** the mapping by default",
             "A prefill you leave as it is remembers nothing",
             "remembering **moves** it",
             "the choice holds for this import only",
             "merged or deleted before you confirm",
             "the upgrade replays the renames the audit journal holds"
           ]},
          {"docs/de/product-documentation.md",
           [
             "**Namen und frühere Namen** (ADR-0050 §4)",
             "behält seinen bisherigen Namen als **früheren Namen**",
             "**Konten werden über den Namen gefunden, dann über einen früheren Namen.**",
             "ein Export, der sich in Portfolio Performance verändert hat",
             "Ein Name, den zwei Konten tragen, wird mit nichts vorbelegt",
             "wird die Zuordnung standardmäßig **gemerkt**",
             "Eine unveränderte Vorbelegung merkt nichts",
             "**verschiebt** das Merken ihn",
             "gilt die Wahl nur für diesen Import",
             "vor dem Bestätigen zusammengeführt oder gelöscht",
             "das Update spielt die Umbenennungen nach, die das Audit-Journal hält"
           ]},
          {"docs/integration/api-and-mcp.md",
           [
             "`former_names`",
             "`DELETE /api/v1/cash_accounts/:id/former_names?name=`",
             "`DELETE /api/v1/securities_accounts/:id/former_names?name=`",
             "An import that still names '<name>' will then create a new account.",
             "the previous name is not kept: an import naming it books to that other account",
             "answers `422` with `errors.name`",
             "resolves a file's account name by the live name first, then by the former names"
           ]},
          {"docs/de/integration/api-and-mcp.md",
           [
             "`former_names`",
             "`DELETE /api/v1/cash_accounts/:id/former_names?name=`",
             "`DELETE /api/v1/securities_accounts/:id/former_names?name=`",
             "Ein Import, der '<name>' noch nennt, legt dann ein neues Konto an.",
             "wird der bisherige Name nicht behalten: Ein Import, der ihn nennt, bucht auf jenes andere Konto",
             "antwortet `422` mit `errors.name`",
             "löst den Kontonamen einer Datei zuerst über den aktuellen Namen auf, dann über die früheren Namen"
           ]}
        ] do
      doc = path |> File.read!() |> String.replace(~r/\s+/, " ")

      for fragment <- fragments do
        assert doc =~ fragment, "#{path}: #{fragment}"
      end
    end
  end

  # User story (L5b, #608, #884):
  # As the operator merging a duplicate security on the securities page, or
  # reading what an import preview's account rows now say,
  # I want the handbook, in English and German, to describe the security
  # merge dialog and the import preview's per-row states, and the API page
  # to stop announcing both as "to follow",
  # so that the screen and the handbook say the same thing.
  #
  # Acceptance criteria:
  # - The handbook, both languages, names the row menu's Merge into…, the
  #   searched target, the ISIN choice without a default, the disabled
  #   confirm, "Merge the other way" and the survivor's overview line.
  # - The handbook, both languages, names the per-row counts, "Remember this
  #   mapping", the told-apart same-named accounts, the disabled "+ Create
  #   new", and the result's remembered names, grouped duplicates and the
  #   bookings a restated set balance absorbs.
  # - Neither API page says the security merge dialog still follows or that
  #   the import page never moves a former name.
  test "the docs describe the security merge dialog and the import preview's row states" do
    for {path, fragments} <- [
          {"docs/product-documentation.md",
           [
             "**Merge into…** in the duplicate's row menu",
             "the first step searches the security to keep",
             "neither is preselected",
             "stays disabled, with the missing choice named beside it",
             "**Merge the other way**",
             "its overview line names the former ISIN and the merge",
             "**already imported**",
             "*nothing to create*",
             "**Remember this mapping**",
             "Two accounts of the same name are told apart",
             "stays in the list, disabled, with the reason",
             "grouped by the check that skipped it",
             "that balance absorbs its amount"
           ]},
          {"docs/de/product-documentation.md",
           [
             "**Zusammenführen in…** im Zeilenmenü des Duplikats",
             "sucht der erste Schritt das Wertpapier, das bleibt",
             "keine ist vorausgewählt",
             "bleibt gesperrt, die fehlende Wahl daneben genannt",
             "**Andersherum zusammenführen**",
             "seine Übersichtszeile nennt die frühere ISIN und die Zusammenführung",
             "**bereits importiert**",
             "*nichts anzulegen*",
             "**Zuordnung merken**",
             "Zwei Konten gleichen Namens werden in der Liste durch das unterschieden",
             "bleibt in der Liste, gesperrt, mit dem Grund",
             "gruppiert nach der Prüfung, die ihn übersprungen hat",
             "dieser Stand nimmt ihren Betrag auf"
           ]}
        ] do
      doc = path |> File.read!() |> String.replace(~r/\s+/, " ")

      for fragment <- fragments do
        assert doc =~ fragment, "#{path}: #{fragment}"
      end
    end

    for {path, stale} <- [
          {"docs/integration/api-and-mcp.md",
           ["merge dialog on the securities page follows", "The import page never moves"]},
          {"docs/de/integration/api-and-mcp.md",
           ["auf der Wertpapierseite folgt im selben Batch", "Vorschau kann das noch nicht"]},
          {"docs/product-documentation.md", ["the dialog on the securities page follows"]},
          {"docs/de/product-documentation.md", ["der Dialog auf der Wertpapierseite folgt"]}
        ] do
      doc = path |> File.read!() |> String.replace(~r/\s+/, " ")

      for fragment <- stale do
        refute doc =~ fragment, "#{path} still says: #{fragment}"
      end
    end
  end

  # User story (#871, pick G6-A):
  # As the operator whose delete was refused because rules read the object,
  # I want the handbook to say where the named rules are,
  # so that I know the names take me to the rule in the view it applies in.
  test "the docs state that a refusal links each rule to Risk in its view" do
    for {path, fragment} <- [
          {"docs/product-documentation.md",
           "each name links to Risk in the view the rule applies in"},
          {"docs/de/product-documentation.md",
           "jeder Name führt auf „Risiko“ in der Ansicht, in der die Regel gilt"}
        ] do
      doc = path |> File.read!() |> String.replace(~r/\s+/, " ")
      assert doc =~ fragment, "#{path}: #{fragment}"
    end
  end

  # User story (#872, ADR-0049 §4 and §8 as amended by the Sprint 16 plan D-6):
  # As the operator, or the operator's agent, reading the handbook,
  # I want a policy rule's rename stated where the rules are described,
  # so that a rename is not mistaken for a new version, nor replaced by a
  # retire-and-recreate that splits the rule's history.
  #
  # Acceptance criteria:
  # - The product docs, in English and German, say the rule's name opens its
  #   dialog and that a rename creates no version.
  # - The integration docs, in English and German, document the PATCH route,
  #   that it is outside the versioning, what it refuses, and the MCP tool.
  test "the docs state a policy rule's rename in English and German" do
    for {path, fragments} <- [
          {"docs/product-documentation.md",
           [
             "A rule's **name is a link** that opens its dialog",
             "A rename changes only the label: it creates no version"
           ]},
          {"docs/de/product-documentation.md",
           [
             "Der **Name einer Regel ist ein Link** und öffnet ihren Dialog",
             "Umbenennen ändert nur die Bezeichnung: Es entsteht keine Version"
           ]},
          {"docs/integration/api-and-mcp.md",
           [
             "`PATCH /api/v1/policy_rules/:id` — body `{\"name\": \"…\"}`",
             "a rule-level edit **outside the versioning**",
             "a `422` naming each such field, and nothing is written",
             "`portfolixir.policy_rules.rename`"
           ]},
          {"docs/de/integration/api-and-mcp.md",
           [
             "`PATCH /api/v1/policy_rules/:id` — Rumpf `{\"name\": \"…\"}`",
             "**außerhalb der Versionen**",
             "ein `422`, das jedes solche Feld nennt, und nichts wird geschrieben",
             "`portfolixir.policy_rules.rename`"
           ]}
        ] do
      doc = path |> File.read!() |> String.replace(~r/\s+/, " ")

      for fragment <- fragments do
        assert doc =~ fragment, "#{path}: #{fragment}"
      end
    end
  end

  # E25 S3, F32 (#888), the S3/S4 review round (R3): the local-use NAT64
  # prefix is a special-purpose block the outbound policy refuses; an
  # IPv6-only operator reads which prefix works before a logo download fails.
  test "the docs state which NAT64 prefix the outbound policy accepts" do
    for {path, fragments} <- [
          {"docs/home-deployment.md",
           ["well-known NAT64 prefix `64:ff9b::/96`", "`64:ff9b:1::/48` is a special-purpose"]},
          {"docs/de/home-deployment.md",
           ["bekannte NAT64-Präfix `64:ff9b::/96`", "`64:ff9b:1::/48` ist wie die privaten"]},
          {"SECURITY.md", ["local-use IPv4/IPv6 translation prefix (`64:ff9b:1::/48`)"]}
        ] do
      doc = path |> File.read!() |> String.replace(~r/\s+/, " ")

      for fragment <- fragments do
        assert doc =~ fragment, "#{path}: #{fragment}"
      end
    end
  end

  # User story (FR-41, ADR-0051 §12, board pick A):
  # As a local portfolio maintainer reading the handbook's performance
  # section,
  # I want it to say what the contribution table under the chart shows and
  # that it adds up to the period's money result,
  # so that I can read the table without reverse-engineering it.
  #
  # Acceptance criteria:
  # - The English and German handbooks name the table, its formula, the three
  #   remainder lines, the ten-largest limit with "show all", the unvalued
  #   note, and that the sum row equals the money figure beside the TTWROR.
  test "the docs describe the contribution table and its sum in English and German" do
    for {path, fragments} <- [
          {"docs/product-documentation.md",
           [
             "### Contribution by position",
             "end value − start value − flows + income − costs",
             "interest, standalone fees and taxes, and the currency effect on cash",
             "the sum row equals the money figure in the badge",
             "the ten largest by absolute amount",
             "counted zero"
           ]},
          {"docs/de/product-documentation.md",
           [
             "### Beitrag je Position",
             "Endwert − Anfangswert − Zu-/Abflüsse + Erträge − Kosten",
             "Zinsen, einzelne Gebühren und Steuern sowie der Währungseffekt auf Bargeld",
             "die Summenzeile ist genau der Betrag im Abzeichen",
             "die zehn mit dem größten Betrag",
             "null gezählt"
           ]}
        ] do
      doc = path |> File.read!() |> String.replace(~r/\s+/, " ")

      for fragment <- fragments do
        assert doc =~ fragment, "#{path}: #{fragment}"
      end
    end
  end

  # User story (#330, ADR-0052; pick H3 = A):
  # As a local portfolio maintainer holding bonds,
  # I want the handbook and the API reference, in English and German, to say
  # what a bond's master data is, the quantity convention, how the remaining
  # term and both yields are computed, and what "priced on two scales" means,
  # so that I can read the figures and check a bond against its statement.
  #
  # Acceptance criteria:
  # - The handbooks name the section, the hundredth convention (the nominal
  #   is quantity × 100), both formulas, the 365-day year, what is excluded,
  #   and the two-scales note with its place in the Wealth data quality.
  # - The API references name the six fields, the bond block with each
  #   metric's computation basis, and the two-scales rule.
  test "the docs describe bond master data, its metrics and the two scales in English and German" do
    for {path, fragments} <- [
          {"docs/product-documentation.md",
           [
             "### Bonds: master data and key metrics (ADR-0052)",
             "a hundredth of its face amount",
             "the nominal held is quantity × 100",
             "current yield** = coupon ÷ price",
             "(coupon + (100 − price) ÷ remaining term in years) ÷ price",
             "in years of 365 days",
             "Accrued interest, fees and taxes are not included",
             "20 to 500 times a booked price per unit",
             "bonds **priced on two scales**",
             "**No yield from a price per unit.**"
           ]},
          {"docs/de/product-documentation.md",
           [
             "### Anleihen: Stammdaten und Kennzahlen (ADR-0052)",
             "ein Hundertstel des Nominals",
             "das Nominal im Bestand ist Stück × 100",
             "laufende Rendite** = Kupon ÷ Kurs",
             "(Kupon + (100 − Kurs) ÷ Restlaufzeit in Jahren) ÷ Kurs",
             "in Jahren zu 365 Tagen",
             "Stückzinsen, Gebühren und Steuern sind nicht enthalten",
             "20- bis 500-Fache eines gebuchten Preises je Stück",
             "**auf zwei Skalen bepreist**",
             "**Keine Rendite aus einem Preis je Stück.**"
           ]},
          {"docs/integration/api-and-mcp.md",
           [
             "### Bonds: master data and the bond reading (ADR-0052)",
             "`coupon_rate`",
             "`coupon_frequency`",
             "`face_value_currency_code`",
             "**quantity × 100**",
             "Every metric carries its own `computation_basis`",
             "a latest quote 20 to 500 times a booked price per unit",
             "`null` with `price_on_unit_scale: true`",
             "each a ratio rounded half up at scale 6",
             "`coupon_rate` and `face_value` keep 6 decimal places",
             "a bond's `coupon_rate` and `face_value` (6)"
           ]},
          {"docs/de/integration/api-and-mcp.md",
           [
             "### Anleihen: Stammdaten und Anleihe-Lesung (ADR-0052)",
             "`coupon_rate`",
             "`coupon_frequency`",
             "`face_value_currency_code`",
             "**Stück × 100**",
             "Jede Kennzahl trägt ihre eigene `computation_basis`",
             "ein letzter Kurs vom 20- bis 500-Fachen eines gebuchten Preises je Stück",
             "`null` mit `price_on_unit_scale: true`",
             "jeweils eine Verhältniszahl, kaufmännisch auf sechs Nachkommastellen gerundet",
             "`coupon_rate` und `face_value` halten 6 Nachkommastellen",
             "`coupon_rate` und `face_value` einer Anleihe (6)"
           ]}
        ] do
      doc = path |> File.read!() |> String.replace(~r/\s+/, " ")

      for fragment <- fragments do
        assert doc =~ fragment, "#{path}: #{fragment}"
      end
    end
  end

  # User story (#330, closing act on U7, finding 6):
  # As the maintainer reading ADR-0052 after the merge,
  # I want its status to say plainly what kind of decision it is and which
  # merge adopted it, and its consequences to name the cases its two rules
  # get wrong,
  # so that the record does not borrow a planning PR's adoption rule, and a
  # distressed bond named by the guard is a known case, not a surprise.
  #
  # Acceptance criteria:
  # - The status names a story-level decision recorded by #330's story and
  #   adopted by the merge of Sprint 18's PR γ (#1054); it no longer cites
  #   ADR-0026 step 1 or PR #780, which concern planning PRs.
  # - The consequences name the guard's known false positive (a distressed
  #   bond legitimately booked at about 3 % of par and quoted at 65) and the
  #   price-at-most-5 rule's.
  test "ADR-0052 states its adoption plainly and names its known false positives" do
    adr =
      "docs/decisions/0052-bond-master-data-in-dedicated-columns.md"
      |> File.read!()
      |> String.replace(~r/\s+/, " ")

    [status] = Regex.run(~r/\*\*Status:\*\*[^*]*/, adr)

    assert status =~ "a story-level decision, recorded by #330's story"
    assert status =~ "adopted by the merge of Sprint 18's PR γ (#1054)"
    refute status =~ "ADR-0026"
    refute status =~ "#780"

    [consequences] = Regex.run(~r/## Consequences.*/s, adr)
    assert consequences =~ "a known false positive"
    assert consequences =~ "about 3 % of par and quoted at 65"
    assert consequences =~ "at most 5"
  end

  @features_en "docs/features.md"
  @features_de "docs/de/features.md"

  # The four claims the 2026-09-30 research names as open ground (its
  # executive summary and cross-dimension insights 1 and 4), then the
  # calculation breakdown (FR-41), then what Portfolixir is not -- in this
  # order, per language.
  @features_sections %{
    @features_en => [
      "## The app never calls a language model; your agent does",
      "## A research log your agent reads and writes, on the record",
      "## Prompts that carry the no-advice stance",
      "## Figures that say how they were computed",
      "## The calculation breakdown: which position made how much",
      "## What Portfolixir is not"
    ],
    @features_de => [
      "## Die App ruft nie ein Sprachmodell auf; Ihr Agent tut es",
      "## Ein Research-Log, das Ihr Agent liest und schreibt, nachvollziehbar",
      "## Prompts, die die Haltung ohne Beratung mittragen",
      "## Zahlen, die sagen, wie sie berechnet wurden",
      "## Die Aufschlüsselung: welche Position wie viel beigetragen hat",
      "## Was Portfolixir nicht ist"
    ]
  }

  # User story (Sprint 18 plan, PR δ, D1 "what is better here"):
  # As a stranger deciding whether Portfolixir fits -- or the agent reading
  # the documentation for them --
  # I want one page, in English and German, that says first what Portfolixir
  # does that I should know, each claim with the page that shows it, and
  # then what Portfolixir is not,
  # so that I can check every claim instead of believing it.
  #
  # Acceptance criteria:
  # - docs/features.md and docs/de/features.md exist with the docs layout and
  #   the language-switcher front matter, and the navigation lists the page
  #   under Home.
  # - Each page leads with the four open-ground claims (no in-app model call,
  #   the research log, the prompts' no-advice stance, figures that state their
  #   computation basis), then the calculation breakdown (FR-41), then "What
  #   Portfolixir is not", in that order; every claim section links at least
  #   one page that shows it.
  # - Every link is a page of the docs site that exists in docs/ (or the
  #   repository), and every #anchor is a heading id Jekyll gives its target.
  # - The "not" section names the non-goals llms.txt and AGENTS.md name and
  #   claims no production readiness; no other product is named.
  # - The docs home and the README link the page; the README's first screen
  #   still carries no picture but the logo.
  test "a features page leads with the open ground, links what it shows, and says what it is not" do
    navigation = File.read!("docs/_data/navigation.yml")
    assert navigation =~ "title: Features"
    assert navigation =~ "url: /features.html"

    for {path, lang} <- [{@features_en, "en"}, {@features_de, "de"}] do
      page = File.read!(path)

      assert page =~ ~r/\A---\nlayout: docs\n/, path
      assert page =~ "lang: #{lang}", path
      assert page =~ "lang_en: /features.html", path
      assert page =~ "lang_de: /de/features.html", path

      headings = Map.fetch!(@features_sections, path)
      positions = Enum.map(headings, &position_of(page, &1, path))
      assert positions == Enum.sort(positions), "#{path}: the sections are out of order"

      for section <- page |> String.split("\n## ") |> Enum.drop(1) do
        assert section =~ "](",
               "#{path}: section without a link: #{hd(String.split(section, "\n"))}"
      end

      for target <- links_of(page) do
        assert_link_resolves(path, target)
      end

      refute page =~ ~r/Ghostfolio|Wealthfolio|Parqet|getquin|Finanzfluss|rotki|unlike /i, path
    end

    en = normalized_text(@features_en)
    de = normalized_text(@features_de)

    for fragment <- [
          "never calls a language model",
          "`computation_basis`",
          "`portfolixir.notes.append`",
          "`first_setup`",
          "`import_converter`",
          "Do not recommend buying, selling or weighting anything; describe what is recorded.",
          "`portfolixir.portfolios.contribution`",
          "`portfolixir.views.contribution`",
          "**Wealth → Holdings**",
          "no order-placing broker connection",
          "no bank or broker sync",
          "no advice",
          "no hosted service",
          "no phone app",
          "There is no upgrade guarantee and no claim of production readiness."
        ] do
      assert en =~ fragment, "#{@features_en}: #{fragment}"
    end

    for fragment <- [
          "nie ein Sprachmodell auf",
          "`computation_basis`",
          "`portfolixir.notes.append`",
          "`first_setup`",
          "`import_converter`",
          "Do not recommend buying, selling or weighting anything; describe what is recorded.",
          "`portfolixir.portfolios.contribution`",
          "`portfolixir.views.contribution`",
          "**Vermögen → Bestände**",
          "keine Broker-Anbindung, die Orders platziert",
          "keine Bank- oder Broker-Synchronisierung",
          "keine Beratung",
          "keinen gehosteten Dienst",
          "keine Telefon-App",
          "Es gibt keine Upgrade-Garantie und keinen Anspruch auf Produktionsreife."
        ] do
      assert de =~ fragment, "#{@features_de}: #{fragment}"
    end

    assert File.read!("docs/index.md") =~ "](features.html)"

    readme = File.read!("README.md")
    [first_screen, _rest] = String.split(readme, "[![CI]", parts: 2)
    assert first_screen =~ "(https://portfolixir.app/features.html)"
    refute first_screen =~ "![", "a picture above the badges"
    assert readme =~ "[Features](docs/features.md)"
  end

  defp normalized_text(path), do: path |> File.read!() |> String.replace(~r/\s+/, " ")

  defp position_of(page, heading, path) do
    case :binary.match(page, "\n" <> heading <> "\n") do
      {position, _length} -> position
      :nomatch -> flunk("#{path}: no heading #{heading}")
    end
  end

  defp links_of(page) do
    ~r/\]\(([^)\s]+)\)/
    |> Regex.scan(page, capture: :all_but_first)
    |> List.flatten()
  end

  # A link from a docs page resolves when it is the repository, or a page of
  # the site whose source exists in docs/ -- a .html page from its .md, any
  # other file as itself -- and its #anchor, if any, is a heading id of that
  # source.
  defp assert_link_resolves(page_path, target) do
    if String.starts_with?(target, "https://github.com/peshay/portfolixir") do
      :ok
    else
      refute target =~ ~r/\A[a-z]+:/, "#{page_path}: #{target} leaves the docs site"

      [path | anchor] = String.split(target, "#", parts: 2)

      source =
        cond do
          path == "" -> page_path
          String.starts_with?(path, "/") -> "docs" <> path
          true -> path |> Path.expand("/" <> Path.dirname(page_path)) |> String.trim_leading("/")
        end
        |> String.replace_suffix(".html", ".md")

      assert File.exists?(source), "#{page_path}: #{target} has no page (#{source})"

      for id <- anchor do
        # kramdown's own id scheme drops non-ASCII letters and leading digits
        # where its GFM scheme keeps them; an anchor both agree on survives a
        # change of the site's Markdown input.
        assert id =~ ~r/\A[a-z][a-z0-9-]*\z/,
               "#{page_path}: #{target} needs an ASCII anchor that starts with a letter"

        assert id in heading_ids(File.read!(source)),
               "#{page_path}: #{target} names no heading of #{source}"
      end
    end
  end

  # The ids Jekyll's kramdown gives headings under GitHub Pages' default GFM
  # input: the raw heading text lowercased, every character that is neither a
  # word character, a hyphen nor a space dropped, each space a hyphen, and a
  # repeat numbered -1, -2 and so on. A line inside fenced code is no heading.
  defp heading_ids(markdown) do
    {_fenced, headings} =
      markdown
      |> String.split("\n")
      |> Enum.reduce({false, []}, fn line, {fenced, headings} ->
        cond do
          String.starts_with?(String.trim_leading(line), "```") ->
            {not fenced, headings}

          fenced ->
            {fenced, headings}

          match = Regex.run(~r/\A#+[ \t]+(.+?)[ \t]*\z/, line) ->
            {fenced, [List.last(match) | headings]}

          true ->
            {fenced, headings}
        end
      end)

    {ids, _seen} =
      headings
      |> Enum.reverse()
      |> Enum.map(fn text ->
        text
        |> String.downcase()
        |> String.replace(~r/[^\w\- \t]/u, "")
        |> String.replace(~r/[ \t]/, "-")
      end)
      |> Enum.map_reduce(%{}, fn id, seen ->
        case Map.fetch(seen, id) do
          :error -> {id, Map.put(seen, id, 0)}
          {:ok, count} -> {"#{id}-#{count + 1}", Map.put(seen, id, count + 1)}
        end
      end)

    ids
  end

  # User story (#952):
  # As the operator's agent relying on the audit journal, or a German-speaking
  # reader of the API reference,
  # I want the journal's coverage stated as the code has it, and the German
  # reference to carry the recorded tax statements and their tools,
  # so that neither language understates the guarantee agent writes rely on,
  # and the tax surface is not documented in English alone.
  #
  # Acceptance criteria:
  # - No API or product page, in English or German, still says the journal
  #   covers only security master data with the rest to follow; each says
  #   that every financial write context journals.
  # - The German reference has the recorded-tax-statements section with each
  #   of its routes, and its MCP list names each tax tool.
  # - The German sentence on a recorded statement's system-set `source` sits
  #   with the statement's POST, not in the Audit-Journal section.
  test "the docs state the journal's coverage and the German tax reference (#952)" do
    for {path, stale, current} <- [
          {"docs/integration/api-and-mcp.md",
           ["covers the Catalog/Fx contexts", "armed in sequence"],
           "Every financial write context journals"},
          {"docs/de/integration/api-and-mcp.md",
           ["deckt derzeit die Kontexte Catalog/Fx ab", "nacheinander scharfgeschaltet"],
           "Jeder Schreibkontext mit Finanzdaten journalisiert"},
          {"docs/product-documentation.md",
           ["currently covers security master-data writes", "covered in sequence"],
           "It covers every area that writes financial data"},
          {"docs/de/product-documentation.md",
           ["deckt derzeit Wertpapier-Stammdaten ab", "folgen nacheinander"],
           "Es deckt jeden Bereich ab, der Finanzdaten schreibt"}
        ] do
      doc = path |> File.read!() |> String.replace(~r/\s+/, " ")

      for fragment <- stale do
        refute doc =~ fragment, "#{path} still says: #{fragment}"
      end

      assert doc =~ current, "#{path}: #{current}"
    end

    de_api = File.read!("docs/de/integration/api-and-mcp.md")

    [_, tax_section] =
      String.split(de_api, "### Erfasste Steuerbescheinigungen (ADR-0031)\n", parts: 2)

    [tax_section, _] = String.split(tax_section, "\n## ", parts: 2)

    for route <- [
          "GET /api/v1/tax/parameters",
          "PUT /api/v1/tax/parameters",
          "GET /api/v1/tax/profiles",
          "POST /api/v1/tax/profiles",
          "PATCH /api/v1/tax/profiles/:id",
          "DELETE /api/v1/tax/profiles/:id",
          "GET /api/v1/tax/allowance_orders",
          "PUT /api/v1/tax/allowance_orders",
          "DELETE /api/v1/tax/allowance_orders/:id",
          "GET /api/v1/tax/statement_snapshots",
          "POST /api/v1/tax/statement_snapshots",
          "GET /api/v1/tax/trim_budget",
          "GET /api/v1/tax/statement_snapshots/:id",
          "PATCH /api/v1/tax/statement_snapshots/:id",
          "DELETE /api/v1/tax/statement_snapshots/:id"
        ] do
      assert tax_section =~ "`#{route}", "German tax section lacks #{route}"
    end

    [_, mcp_list] = String.split(de_api, "\n## MCP-Tools\n", parts: 2)

    for tool <- [
          "tax_parameters.list",
          "tax_parameters.upsert",
          "tax_profiles.list",
          "tax_profiles.create",
          "tax_profiles.update",
          "tax_profiles.delete",
          "allowance_orders.list",
          "allowance_orders.put",
          "allowance_orders.delete",
          "tax_snapshots.list",
          "tax_snapshots.get",
          "tax_snapshots.create",
          "tax_snapshots.update",
          "tax_snapshots.delete",
          "tax_snapshots.trim_budget"
        ] do
      assert mcp_list =~ "- `portfolixir.#{tool}`", "German MCP list lacks #{tool}"
    end

    [_, journal_section] = String.split(de_api, "\n## Audit-Journal\n", parts: 2)
    [journal_section, _] = String.split(journal_section, "\n## ", parts: 2)
    source_rule = "Die Quelle einer erfassten Steuerbescheinigung setzt das System (`manual`)"

    refute String.replace(journal_section, ~r/\s+/, " ") =~ source_rule
    assert String.replace(tax_section, ~r/\s+/, " ") =~ source_rule
  end

  # User story (#960):
  # As a reader of ADR-0029 after Sprint 16,
  # I want its ADR-0050 §9 note to name the security merge dialog as shipped,
  # so that the one record still written in the future tense agrees with the
  # API reference and the handbook, which describe the dialog as built.
  #
  # Acceptance criteria:
  # - The note no longer says the operator's dialog follows.
  # - It names **Merge into…** in the securities row menu beside the API
  #   route and the MCP tool.
  test "ADR-0029's ADR-0050 §9 note names the shipped security merge dialog (#960)" do
    adr =
      "docs/decisions/0029-stable-identities-and-reimport-survival.md"
      |> File.read!()
      |> String.replace(~r/\s*\n\s*>?\s*/, " ")

    [note] = Regex.run(~r/\*\*Amended by \[ADR-0050\]\([^)]*\) §9 .*?\*\*Rejected/, adr)

    refute note =~ "follows in the same batch"
    assert note =~ "**Merge into…** in the securities row menu"
    assert note =~ "`POST /api/v1/securities/:id/merge`"
    assert note =~ "`portfolixir.securities.merge`"
  end

  # User story (#929):
  # As the operator wondering why a security shows the asset class it shows,
  # I want the handbook's inference section, in English and German, and
  # ADR-0012's pipeline to describe what `Security.effective_asset_class/1`
  # runs,
  # so that I can predict a class instead of reading the code.
  #
  # Acceptance criteria:
  # - Each section names the classes the inference returns in the code's
  #   order, every leaf class `derivative_class/1` returns among them, and the
  #   company-logo equity fallback (#408) after the fund rule.
  # - Neither section claims an ISIN prefix (or `IE00`) as a signal, a generic
  #   `derivative` class, GmbH or NV as a legal form, or that a better
  #   heuristic reclassifies every security retroactively.
  # - ADR-0012 carries a dated note that corrects its pipeline summary the
  #   same way, leaving the decision as it was taken.
  test "the asset-class inference docs and ADR-0012 match the code (#929)" do
    source = File.read!("lib/portfolixir/catalog/security.ex")

    [_, cond_body] =
      Regex.run(
        ~r/defp infer_asset_class_code\(name, _isin, ticker_symbol\) do(.*?)\n  end/s,
        source
      )

    [_, derivative_body] =
      Regex.run(~r/defp derivative_class\(name\) when is_binary\(name\) do(.*?)\n  end/s, source)

    classes_of = fn body ->
      ~r/-> "([a-z_]+)"/ |> Regex.scan(body) |> Enum.map(fn [_, class] -> class end)
    end

    leaf_classes = Enum.uniq(classes_of.(derivative_body))
    ordered = classes_of.(cond_body) ++ [hd(leaf_classes), "equity", "fund"]

    assert ordered == [
             "government_bond",
             "etf",
             "crypto",
             "commodity",
             "knock_out",
             "equity",
             "fund"
           ]

    for {path, heading, logo} <- [
          {"docs/product-documentation.md", "### Asset class inference\n", "logo"},
          {"docs/de/product-documentation.md", "### Inferenz der Anlageklasse\n", "Logo"}
        ] do
      [_, section] = path |> File.read!() |> String.split(heading, parts: 2)
      [section, _] = String.split(section, "\n### ", parts: 2)
      section = String.replace(section, ~r/\s+/, " ")

      positions = Enum.map(ordered, fn class -> :binary.match(section, "**#{class}**") end)

      refute :nomatch in positions, "#{path}: a class of #{inspect(ordered)} is missing"
      assert positions == Enum.sort(positions), "#{path}: classes out of the code's order"

      for class <- leaf_classes do
        assert section =~ "**#{class}**", "#{path}: #{class}"
      end

      assert section =~ "#408"
      assert section =~ logo

      for stale <- [
            "IE00",
            "**derivative**",
            "GmbH",
            ", NV,",
            "country-code prefix",
            "Länderpräfix"
          ] do
        refute section =~ stale, "#{path} still says: #{stale}"
      end

      refute section =~ "retroactively reclassifies all matching securities"
      refute section =~ "klassifiziert eine verbesserte Heuristik im Code alle passenden"
    end

    adr =
      "docs/decisions/0012-asset-class-inference-at-read-time.md"
      |> File.read!()
      |> String.replace(~r/\s*\n\s*>?\s*/, " ")

    [note] = Regex.run(~r/\*\*Note 2026-10-03 \(#929.*/, adr)

    for fragment <- ["`_isin`", "#408", "`changeset/2`", "`is_nil`" | leaf_classes] do
      assert note =~ fragment, "ADR-0012's note: #{fragment}"
    end
  end
end
