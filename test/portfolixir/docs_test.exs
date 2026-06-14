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
  # As a local integrator with a business account,
  # I want the docs to document the counts-toward-cash-quote flag,
  # so that I can exclude an account from the cash quote over the API or MCP
  # without reading source files.
  #
  # Acceptance criteria:
  # - The API and MCP page documents counts_toward_cash_quote on cash accounts
  #   and its effect on the valuation's cash_quote.
  # - The product handbook describes the flag instead of listing it as planned.
  test "docs document the counts-toward-cash-quote flag" do
    api_docs = File.read!("docs/integration/api-and-mcp.md")
    product_docs = File.read!("docs/product-documentation.md")

    assert api_docs =~ "counts_toward_cash_quote"
    assert api_docs =~ "cash_quote"

    assert product_docs =~ "counts toward the cash quote"
    refute product_docs =~ "Still planned: a per-account flag"
  end

  # User story:
  # As a local integrator holding a store-of-value position,
  # I want the docs to document the excluded-from-allocation-targets flag,
  # so that I can keep a security (e.g. Bitcoin) out of the allocation steering
  # basis over the API or MCP without reading source files.
  #
  # Acceptance criteria:
  # - The API and MCP page documents excluded_from_allocation_targets on
  #   securities and the allocation's excluded block.
  # - The product handbook describes the flag and the "outside the steering
  #   basis" block.
  test "docs document the excluded-from-allocation-targets flag" do
    api_docs = File.read!("docs/integration/api-and-mcp.md")
    product_docs = File.read!("docs/product-documentation.md")

    assert api_docs =~ "excluded_from_allocation_targets"
    assert api_docs =~ "steering basis"
    assert api_docs =~ "`excluded`"

    assert product_docs =~ "excluded from allocation targets"
    assert product_docs =~ "Outside the steering basis"
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
    assert normalized_api_docs =~ "plus the cash that counts toward the cash quote"

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
          "counts_toward_cash_quote",
          "excluded_from_allocation_targets",
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

  defp api_routes_from_router do
    router = File.read!("lib/portfolixir_web/router.ex")

    ~r/\b(get|post|put|patch|delete)\("([^"]+)"/
    |> Regex.scan(router)
    |> Enum.map(fn
      [_, verb, "/health"] ->
        "#{String.upcase(verb)} /health"

      [_, verb, path] ->
        "#{String.upcase(verb)} /api/v1#{path}"
    end)
    |> Enum.reject(&(&1 == "GET /health"))
  end

  defp mcp_tools_from_source do
    tools = File.read!("mcp-server/src/tools.ts")

    ~r/tool\("([^"]+)"/
    |> Regex.scan(tools)
    |> Enum.map(fn [_, tool] -> tool end)
  end
end
