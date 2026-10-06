defmodule Portfolixir.AgentEntryDocsTest do
  # Sprint 17 A5 (#982): the entry written for an agent rather than a person
  # (docs/llms.txt, served at the docs site's root) and the "Connect an agent"
  # page beside it, in English and German. The schema figures the entry states
  # are held to the measured ones by the companion's own test
  # (mcp-server/test/llms-entry.test.ts).
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

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
  # - It names the total across every portfolio as a read with no view
  #   (#1007, Sprint 18 plan D-5) and no longer sends the agent to create a
  #   view for it.
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
          "## Read on",
          "The total across every portfolio needs no view: `portfolixir.views.valuation` without an id"
        ] do
      assert flat =~ fragment, fragment
    end

    refute flat =~ "one created with `portfolixir.views.create`"
    refute flat =~ "The view tools need a view."

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

  # User story (the launch test's run on PR β, D-1):
  # As the fresh agent that installed Portfolixir from the README and
  # llms.txt alone,
  # I want the seven things I had to find elsewhere written where I read,
  # so that the next agent does not have to look.
  #
  # Acceptance criteria:
  # - The README's Compose step names both tokens it means.
  # - The README and llms.txt say that the Compose companion's profile goes in
  #   .env and the mcp service is recreated.
  # - The README, llms.txt and the deployment guide (EN, DE) say what the
  #   first build downloads, and how a proxy and an intercepting CA reach it.
  # - llms.txt, the README and the deployment guide agree on the UI password:
  #   set it for a Compose install.
  # - The Connect pages (EN, DE) name the HTTP transport: Streamable HTTP,
  #   POSTs to /mcp with both Accept types, stateless.
  # - The deployment guide (EN, DE) names the scheduled ECB exchange-rate
  #   fetch and the quote sync among the outbound calls.
  test "the launch test's documentation gaps are closed where an agent reads" do
    readme = normalized("README.md")
    llms = normalized("docs/llms.txt")
    guide_en = normalized("docs/home-deployment.md")
    guide_de = normalized("docs/de/home-deployment.md")

    assert readme =~
             "`PORTFOLIXIR_API_TOKEN`, `PORTFOLIXIR_MCP_TOKEN` and `SECRET_KEY_BASE` each from `openssl rand -base64 48`"

    for doc <- [readme, llms] do
      assert doc =~ "`PORTFOLIXIR_MCP_PROFILE=book` in `.env`"
      assert doc =~ "`docker compose up -d mcp`"
    end

    for doc <- [readme, llms, guide_en] do
      assert doc =~
               "Debian packages, Hex packages from hex.pm and npm packages from the npm registry"

      assert doc =~ "`HTTPS_PROXY`"
    end

    assert guide_de =~ "Debian-Pakete, Hex-Pakete von hex.pm und npm-Pakete aus der npm-Registry"
    assert guide_de =~ "`HTTPS_PROXY`"

    for doc <- [readme, llms, guide_en] do
      assert doc =~ "Set `PORTFOLIXIR_UI_PASSWORD` for a Compose install"
    end

    refute llms =~ "before the instance is reachable from anywhere but its own machine"

    for {path, stateless} <- [{@connect_en, "stateless"}, {@connect_de, "zustandslos"}] do
      page = normalized(path)
      assert page =~ "Streamable HTTP", path

      assert page =~ "`application/json` and `text/event-stream`" or
               page =~ "`application/json` und `text/event-stream`",
             path

      assert page =~ stateless, path
      assert page =~ "`Mcp-Session-Id`", path
    end

    for guide <- [guide_en, guide_de] do
      assert guide =~ "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml"
      assert guide =~ "`config/prod.exs`"
    end
  end

  # User story (the launch test's second run, #1037):
  # As the fresh agent installing Portfolixir from the README and llms.txt
  # through a shell,
  # I want the start command to return, and the Imports page's address and
  # the login's one field written where I read,
  # so that I do not have to find them by trying.
  #
  # Acceptance criteria:
  # - The README, llms.txt and the Connect pages (EN, DE) start the stack
  #   detached, `docker compose up --build -d`, and none of them starts it in
  #   the foreground.
  # - Each names the Imports page's address, `/imports`, a route the router
  #   serves.
  # - The README and llms.txt say the login, `/login`, asks only for
  #   `PORTFOLIXIR_UI_PASSWORD`, with no user name.
  test "the entry points start Compose detached and name the Imports address and the login" do
    paths = PortfolixirWeb.Router.__routes__() |> Enum.map(& &1.path) |> MapSet.new()
    assert "/imports" in paths
    assert "/login" in paths

    for path <- ["README.md", "docs/llms.txt", @connect_en, @connect_de] do
      doc = normalized(path)
      assert doc =~ "docker compose up --build -d", path

      refute doc =~ ~r/docker compose up --build(?! -d)/,
             "#{path} starts Compose in the foreground"

      assert doc =~ "`/imports`", path
    end

    for path <- ["README.md", "docs/llms.txt"] do
      doc = normalized(path)
      assert doc =~ "The login, at `/login`, asks only for `PORTFOLIXIR_UI_PASSWORD`", path
      assert doc =~ "there is no user name", path
    end
  end

  # User story (#1093, Sprint 19 B2a):
  # As a stranger following the Compose quick start,
  # I want its secrets step to have me set the web UI's password, and the
  # entry points to say where Import sits in the UI,
  # so that my instance does not start with an open web UI, and I find the
  # Imports page from the sidebar.
  #
  # Acceptance criteria:
  # - The secrets step of the README ("Run with Docker Compose") and of
  #   llms.txt (step 2) names `PORTFOLIXIR_UI_PASSWORD`, how to generate it
  #   (`openssl rand -base64 24`, or a passphrase in single quotes, which
  #   Compose does not interpolate, holding no single quote and not ending in
  #   a backslash), and that left empty the web UI is open.
  # - .env.example keeps the variable empty, under a comment that says the web
  #   UI is open while it is empty.
  # - The README, llms.txt and the Connect pages name Import where the UI puts
  #   it, next to `/imports`: the Transactions area's Import tab, in the labels
  #   the application renders ("Transactions → Import", in German
  #   "Transaktionen → Import"); the sidebar has no Import entry.
  test "the quick start sets the UI password in its secrets step and places Import under Transactions" do
    flat = &String.replace(&1, ~r/\s+/, " ")

    readme_step =
      "README.md"
      |> File.read!()
      |> String.split("### Run with Docker Compose")
      |> Enum.at(1)
      |> String.split("docker compose up --build -d")
      |> hd()
      |> flat.()

    llms_step =
      "docs/llms.txt"
      |> File.read!()
      |> String.split(~r/^2\. /m)
      |> Enum.at(1)
      |> String.split(~r/^3\. /m)
      |> hd()
      |> flat.()

    for {path, step} <- [{"README.md", readme_step}, {"docs/llms.txt", llms_step}] do
      assert step =~ "`PORTFOLIXIR_UI_PASSWORD`", path
      assert step =~ "`openssl rand -base64 24`", path
      assert step =~ "passphrase", path
      assert step =~ "in single quotes in `.env`", path
      # #1093 review round: a single quote ends the quoted value, and a
      # trailing backslash escapes the closing quote.
      assert step =~ "holds no single quote", path
      assert step =~ "does not end in a backslash", path
      assert step =~ "left empty, the web UI is open", path
    end

    assert [_, comment] =
             Regex.run(~r/((?:^#.*\n)+)PORTFOLIXIR_UI_PASSWORD=\n/m, File.read!(".env.example"))

    assert flat.(String.replace(comment, ~r/^# ?/m, "")) =~ "web UI is open while it is empty"

    # The sidebar's Transactions entry, then the tab of its area that opens
    # /imports, as the application renders them in each language; no sidebar
    # entry opens /imports itself.
    place = fn locale ->
      Gettext.with_locale(PortfolixirWeb.Gettext, locale, fn ->
        sidebar =
          render_component(&PortfolixirWeb.AppShell.shell/1, %{inner_block: []})
          |> Floki.parse_fragment!()
          |> Floki.find("nav.primary-nav")

        assert sidebar != [], "no primary navigation rendered"

        refute "/imports" in Floki.attribute(sidebar, "a", "href"),
               "a sidebar entry opens /imports"

        area =
          sidebar |> Floki.find("#nav-transactions .nav-label") |> Floki.text() |> String.trim()

        assert area != "", "the sidebar has no entry nav-transactions"

        import_tab = Enum.find(PortfolixirWeb.AppShell.transactions_tabs(:import), & &1.current)
        assert import_tab, "AppShell.transactions_tabs(:import) marks no tab as current"
        assert import_tab.href == "/imports"
        "#{area} → #{import_tab.label}"
      end)
    end

    assert place.("en") == "Transactions → Import"
    assert place.("de") == "Transaktionen → Import"

    for {path, locale} <- [
          {"README.md", "en"},
          {"docs/llms.txt", "en"},
          {@connect_en, "en"},
          {@connect_de, "de"}
        ] do
      doc = normalized(path)
      expected = Regex.escape(place.(locale))

      assert doc =~ ~r/#{expected}.{0,80}`\/imports`|`\/imports`.{0,80}#{expected}/u,
             "#{path}: #{place.(locale)} is not named next to `/imports`"
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
