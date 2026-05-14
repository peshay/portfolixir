defmodule Portfolixir.DocsFoundationTest do
  use ExUnit.Case, async: true

  @doc_files [
    "README.md",
    "CONTRIBUTING.md",
    "AGENTS.md",
    "docs/index.md"
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
  # As a public reader of the reboot foundation,
  # I want the Pages domain and public docs to be accurate and modest,
  # so that I understand this branch is a foundation reset and not a finished MVP.
  #
  # Acceptance criteria:
  # - docs/CNAME contains exactly portfolixir.app.
  # - Public docs contain a minimal honest GitHub Pages landing page.
  # - Public docs describe future MVP functionality as Epic-by-Epic staging work.
  test "public docs use the correct Pages domain and describe an honest reboot foundation" do
    assert File.read!("docs/CNAME") == "portfolixir.app\n"

    docs_text =
      @doc_files
      |> Enum.map(&File.read!/1)
      |> Enum.join("\n")

    refute docs_text =~ "portfilixir.app"
    assert docs_text =~ "foundation reset"
    assert docs_text =~ "not a finished MVP"
    assert docs_text =~ "Epic-by-Epic"
    assert docs_text =~ "staging review"

    for claim <- @deferred_claims do
      refute docs_text =~ claim
    end
  end
end
