defmodule Portfolixir.DocsFoundationTest do
  use ExUnit.Case, async: true

  @doc_files [
    "README.md",
    "CONTRIBUTING.md",
    "AGENTS.md",
    "docs/index.md",
    "docs/home-deployment.md"
  ]

  @process_claims [
    "staging review",
    "human-reviewed Epics on staging",
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
    "MCP tools exist",
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
  # - The README explains what Portfolixir is without reboot or backlog process language.
  # - The README documents how to start the app from source.
  # - The README links to CONTRIBUTING.md, AGENTS.md, docs, support, and LICENSE.
  test "readme is a concise project entry page without reboot process context" do
    assert File.read!("docs/CNAME") == "portfolixir.app\n"

    readme = File.read!("README.md")

    for expected <- [
          "priv/static/images/logo-wordmark.svg",
          "actions/workflows/ci.yml/badge.svg",
          "Elixir-Phoenix",
          "github/license",
          "Support-Maintenance",
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
          "Review derived holdings and stored quote history.",
          "Open a security detail chart from local quote history."
        ] do
      assert readme =~ expected
    end

    for rejected <- [
          "reboot",
          "foundation reset",
          "not a finished MVP",
          "Product backlog",
          "Planka",
          "story cards",
          "human-reviewed Epics",
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

    for claim <- @deferred_claims do
      refute docs_text =~ claim
    end

    for claim <- @process_claims do
      refute docs_text =~ claim
    end
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
    docs_css = File.read!("docs/styles.css")
    app_css = File.read!("priv/static/app.css")

    assert docs_index =~ ~s(href="styles.css")
    assert docs_index =~ "Portfolixir"
    assert docs_index =~ "Local portfolio tracking"
    assert docs_index =~ "Theme and Language"
    assert docs_index =~ "system theme"
    assert docs_index =~ "browser language"
    assert docs_index =~ "System, Light, and Dark"
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
end
