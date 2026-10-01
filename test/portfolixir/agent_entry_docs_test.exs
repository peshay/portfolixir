defmodule Portfolixir.AgentEntryDocsTest do
  # Sprint 17 A5 (#982): the entry written for an agent rather than a person
  # (docs/llms.txt, served at the docs site's root) and the "Connect an agent"
  # page beside it, in English and German. The schema figures the entry states
  # are held to the measured ones by the companion's own test
  # (mcp-server/test/llms-entry.test.ts).
  use ExUnit.Case, async: true

  @site "https://portfolixir.app"
  @repo "https://github.com/peshay/portfolixir"

  @connect_en "docs/integration/connect-an-agent.md"
  @connect_de "docs/de/integration/connect-an-agent.md"

  defp normalized(path), do: path |> File.read!() |> String.replace(~r/\s+/, " ")

  # A site URL resolves when docs/ holds the page it renders from: a .html
  # page from its .md (or .html) source, any other file as itself.
  defp page_exists?("/" <> path) do
    path = path |> String.split("#") |> hd()

    cond do
      path == "" ->
        File.exists?("docs/index.md")

      String.ends_with?(path, ".html") ->
        base = String.replace_suffix(path, ".html", "")
        File.exists?("docs/#{base}.md") or File.exists?("docs/#{path}")

      true ->
        File.exists?("docs/#{path}")
    end
  end

  # `name => default` for every `process.env.NAME ?? "default"` the companion
  # reads with a non-empty default.
  defp companion_defaults do
    "mcp-server/src/*.ts"
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      Regex.scan(~r/process\.env\.([A-Z_]+) \?\? "([^"]+)"/, File.read!(path),
        capture: :all_but_first
      )
    end)
    |> Map.new(fn [name, default] -> {name, default} end)
  end

  defp companion_variables do
    "mcp-server/src/*.ts"
    |> Path.wildcard()
    |> Enum.flat_map(
      &Regex.scan(~r/process\.env\.([A-Z_]+)/, File.read!(&1), capture: :all_but_first)
    )
    |> List.flatten()
    |> MapSet.new()
  end

  # User story (A5, #982):
  # As an agent deciding whether to recommend Portfolixir and how to set it up,
  # I want one entry written for me at the docs site's root,
  # so that I can tell my user what it is, when it is the wrong choice, how to
  # install it, how to connect, what it costs to connect, and where to read on.
  #
  # Acceptance criteria:
  # - docs/llms.txt exists, is plain text Jekyll copies as it is (no front
  #   matter), and opens with the product's name and a one-line summary.
  # - It says when not to recommend it (no broker sync, no phone app, no
  #   hosted service, no advice), how to install it, how to connect the
  #   companion and pick a profile (PORTFOLIXIR_MCP_PROFILE with read, book
  #   and full), names both prompts, and gives the schema cost per profile.
  # - Every link it carries is the repository or a page of the docs site that
  #   exists in docs/, the API and MCP reference and the Connect page among
  #   them.
  test "llms.txt is the agent's entry and links only to pages that exist" do
    entry = File.read!("docs/llms.txt")
    flat = String.replace(entry, ~r/\s+/, " ")

    assert String.starts_with?(entry, "# Portfolixir\n\n> ")
    refute String.starts_with?(entry, "---")

    for fragment <- [
          "## When not to recommend it",
          "no broker or bank sync",
          "no phone app",
          "no hosted service",
          "no advice",
          "## Install",
          "docker compose up --build",
          "## Connect the MCP companion",
          "`PORTFOLIXIR_MCP_PROFILE`",
          "`read`",
          "`book`",
          "`full`",
          "A profile narrows the companion, not the API token.",
          "## Prompts",
          "`first_setup`",
          "`import_converter`",
          "## What connecting costs",
          "## Read on"
        ] do
      assert flat =~ fragment, fragment
    end

    links =
      ~r/\]\((https?:\/\/[^)\s]+)\)/
      |> Regex.scan(entry, capture: :all_but_first)
      |> List.flatten()

    assert "#{@site}/integration/api-and-mcp.html" in links
    assert "#{@site}/integration/connect-an-agent.html" in links

    for link <- links do
      cond do
        link == @repo ->
          :ok

        String.starts_with?(link, @site <> "/") ->
          assert page_exists?(String.replace_prefix(link, @site, "")), "#{link} has no page"

        true ->
          flunk("llms.txt links outside the docs site and the repository: #{link}")
      end
    end
  end

  # User story (A5, #982):
  # As the operator connecting my agent's MCP client,
  # I want a page with configurations I can copy, for stdio and for HTTP,
  # in English and German,
  # so that connecting is a paste, not a reading of the companion's source.
  #
  # Acceptance criteria:
  # - The EN and DE pages exist with the docs layout and both language links,
  #   and the navigation lists the page under Integration.
  # - Each carries a stdio configuration (node and the built dist/index.js,
  #   the API base URL and token, the profile) and an HTTP one (the /mcp URL
  #   and the bearer header with PORTFOLIXIR_MCP_TOKEN).
  # - Every companion variable they name is one the companion reads, and
  #   every default the companion's source gives a variable is the default
  #   both pages state for it.
  test "the Connect an agent page carries copy-paste configurations in EN and DE" do
    navigation = File.read!("docs/_data/navigation.yml")
    assert navigation =~ "title: Connect an Agent"
    assert navigation =~ "url: /integration/connect-an-agent.html"

    for {path, lang} <- [{@connect_en, "en"}, {@connect_de, "de"}] do
      page = File.read!(path)
      flat = normalized(path)

      assert page =~ ~r/\A---\nlayout: docs\n/
      assert page =~ "lang: #{lang}"
      assert page =~ "lang_en: /integration/connect-an-agent.html"
      assert page =~ "lang_de: /de/integration/connect-an-agent.html"

      for fragment <- [
            ~s("command": "node"),
            "mcp-server/dist/index.js",
            ~s("PORTFOLIXIR_API_BASE_URL": "http://127.0.0.1:4000"),
            ~s("PORTFOLIXIR_MCP_PROFILE": "book"),
            "http://127.0.0.1:4001/mcp",
            "Authorization: Bearer",
            "PORTFOLIXIR_MCP_TOKEN",
            "first_setup",
            "import_converter"
          ] do
        assert flat =~ fragment, "#{path}: #{fragment}"
      end

      named =
        ~r/PORTFOLIXIR_(?:MCP_[A-Z_]+|API_BASE_URL)/
        |> Regex.scan(page)
        |> List.flatten()
        |> MapSet.new()

      assert MapSet.subset?(named, companion_variables()),
             "#{path} names variables the companion does not read: " <>
               inspect(MapSet.difference(named, companion_variables()))

      for {name, default} <- companion_defaults() do
        assert flat =~ "| `#{name}` | `#{default}` |", "#{path}: #{name} defaults to #{default}"
      end
    end
  end
end
