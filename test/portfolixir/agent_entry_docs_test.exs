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

  # User story (#1172, the Sprint 19 close-out's launch test):
  # As the fresh agent installing Portfolixir on a host whose Compose build
  # reaches no Debian mirror,
  # I want llms.txt to name the from-source route, .env.example to say which
  # database setting that route reads, and the README to say how to lock its
  # web UI,
  # so that I find the fallback where I read, point it at the right database,
  # and do not leave its web UI open.
  #
  # Acceptance criteria:
  # - llms.txt's Install names the README's "Run from source" as the fallback
  #   for a host that reaches no Debian mirror: a `MIX_ENV=dev` server, not a
  #   release; `mix` reads no `.env`; it names `PORTFOLIXIR_UI_PASSWORD` and
  #   the database variables config/dev.exs reads.
  # - .env.example no longer says that route reads DATABASE_URL and carries
  #   no DATABASE_URL line; it names DATABASE_NAME, DATABASE_HOST and
  #   DATABASE_PORT, each read by config/dev.exs, which reads no DATABASE_URL.
  # - The README's "Run from source" says the same, and says the web UI asks
  #   for a login only with PORTFOLIXIR_UI_PASSWORD exported, with the
  #   command that exports it.
  # - The deployment guide (EN, DE) names the route for a host that reaches
  #   no Debian mirror and has no second machine.
  test "the from-source route is named where an agent reads, with its database and its login" do
    flat = &String.replace(&1, ~r/\s+/, " ")

    dev_reads =
      ~r/"([A-Z][A-Z0-9_]+)"/
      |> Regex.scan(File.read!("config/dev.exs"), capture: :all_but_first)
      |> List.flatten()

    database = ~w(DATABASE_NAME DATABASE_HOST DATABASE_PORT)

    for name <- database, do: assert(name in dev_reads, "config/dev.exs does not read #{name}")
    refute "DATABASE_URL" in dev_reads

    section = fn path, from, to ->
      path |> File.read!() |> String.split(from) |> Enum.at(1) |> String.split(to) |> hd()
    end

    install = flat.(section.("docs/llms.txt", "## Install", "## Connect the MCP companion"))
    readme = flat.(section.("README.md", "### Run from source", "### API and MCP"))

    for {path, doc} <- [{"docs/llms.txt", install}, {"README.md", readme}] do
      for fragment <-
            [
              "reaches no Debian mirror",
              "`MIX_ENV=dev`",
              "not a release",
              "`mix` reads no `.env`",
              "`PORTFOLIXIR_UI_PASSWORD`",
              "`portfolixir_dev` on `127.0.0.1:5432`"
            ] ++ Enum.map(database, &"`#{&1}`") do
        assert doc =~ fragment, "#{path}: #{fragment}"
      end
    end

    assert install =~ ~s(the README's "Run from source")

    assert readme =~
             "asks for a login only when `PORTFOLIXIR_UI_PASSWORD` is exported before `mix phx.server`"

    assert readme =~ "read -rs PORTFOLIXIR_UI_PASSWORD && export PORTFOLIXIR_UI_PASSWORD"

    env_example = File.read!(".env.example")
    refute env_example =~ "reads DATABASE_URL directly"
    refute env_example =~ ~r/^DATABASE_URL=/m

    assert flat.(String.replace(env_example, ~r/^# ?/m, "")) =~
             "reads no .env and no DATABASE_URL"

    for name <- database, do: assert(env_example =~ name, ".env.example: #{name}")

    for {path, words} <- [
          {"docs/home-deployment.md",
           ~s(Without a second machine, the README's "Run from source")},
          {"docs/de/home-deployment.md", "Ohne zweiten Rechner startet „Run from source“"}
        ] do
      assert normalized(path) =~ words, path
    end
  end

  # User story (#1172, Sprint 20 γ closing act, the install lens):
  # As a stranger installing Portfolixir from source, by the README alone,
  # I want the database it needs, the order of its first commands, the way
  # to start the companion and the token to give it written where I read,
  # so that the first `mix ecto.setup` meets the right database, and the
  # companion speaks JSON-RPC on its stdout from the first byte.
  #
  # Acceptance criteria:
  # - The README (its prerequisites and "Run from source"), llms.txt's
  #   Install and the development guide name "PostgreSQL 15 or newer, with
  #   its contrib modules (btree_gist)", the floor the migrations set
  #   (`NULLS NOT DISTINCT`, `CREATE EXTENSION ... btree_gist`).
  # - The README's "Run from source" sets its exports, the database, the
  #   UI password and the API token, before `mix deps.get`, and says they
  #   are set before `mix ecto.setup`.
  # - The README and CONTRIBUTING.md start the companion with
  #   `node mcp-server/dist/index.js`, never `npm start --prefix mcp-server`,
  #   whose banner precedes the JSON-RPC on stdout.
  # - The Connect page's stdio section (EN, DE) takes the token the instance
  #   runs with: from `.env` for Compose, the exported value for a server
  #   run from source; it no longer says "from the instance's `.env`".
  test "the from-source install names its database floor, its order and its companion start" do
    flat = &String.replace(&1, ~r/\s+/, " ")
    floor = "PostgreSQL 15 or newer, with its contrib modules (btree_gist)"

    migrations = Path.wildcard("priv/repo/migrations/*.exs") |> Enum.map(&File.read!/1)
    assert Enum.any?(migrations, &(&1 =~ "NULLS NOT DISTINCT"))
    assert Enum.any?(migrations, &(&1 =~ "CREATE EXTENSION IF NOT EXISTS btree_gist"))

    section = fn path, from, to ->
      path |> File.read!() |> String.split(from) |> Enum.at(1) |> String.split(to) |> hd()
    end

    readme = File.read!("README.md")
    prerequisites = flat.(section.("README.md", "### Prerequisites", "\n## "))
    from_source = section.("README.md", "### Run from source", "### API and MCP")
    install = flat.(section.("docs/llms.txt", "## Install", "## Connect the MCP companion"))
    guide = normalized("docs/development/guide.md")

    for {where, text} <- [
          {"README prerequisites", prerequisites},
          {"README Run from source", flat.(from_source)},
          {"llms.txt Install", install},
          {"docs/development/guide.md", guide}
        ] do
      assert text =~ floor, "#{where}: #{floor}"
    end

    at = fn needle ->
      case :binary.match(from_source, needle) do
        {at, _length} -> at
        :nomatch -> flunk("README Run from source lacks #{needle}")
      end
    end

    for export <- [
          "export DATABASE_NAME=",
          "read -rs PORTFOLIXIR_UI_PASSWORD",
          "export PORTFOLIXIR_API_TOKEN="
        ] do
      assert at.(export) < at.("mix deps.get"), "README: #{export} comes after mix deps.get"
    end

    assert flat.(from_source) =~ "Set them before `mix ecto.setup`"

    for {path, text} <- [
          {"README.md", readme},
          {"CONTRIBUTING.md", File.read!("CONTRIBUTING.md")}
        ] do
      refute text =~ "npm start --prefix mcp-server", path
      assert text =~ "node mcp-server/dist/index.js", path
    end

    for {path, token} <- [
          {@connect_en,
           "the token the instance runs with: from `.env` for Compose, the value you exported for a server run from source"},
          {@connect_de,
           "dem Token, mit dem die Instanz läuft: aus der `.env` für Compose, dem Wert, den Sie für einen aus dem Quellcode gestarteten Server exportiert haben"}
        ] do
      page = normalized(path)
      assert page =~ token, path
      refute page =~ "from the instance's `.env`", path
      refute page =~ "aus der `.env` der Instanz", path
      refute page =~ "PORTFOLIXIR_API_TOKEN from .env>", path
      refute page =~ "PORTFOLIXIR_API_TOKEN aus .env>", path
    end
  end

  # User story (the Sprint 20 launch test, finding 1):
  # As the fresh agent installing Portfolixir from source by the README and
  # llms.txt alone,
  # I want the port and the database settings the server reads named where I
  # read, and its fixed database login said to be fixed,
  # so that I move the port without reading config/dev.exs, and do not look
  # for a variable that changes the database user.
  #
  # Acceptance criteria:
  # - config/dev.exs reads PORT, DATABASE_NAME, DATABASE_HOST and
  #   DATABASE_PORT, each with a default, and fixes the database user and
  #   password at `postgres`, with no variable for either.
  # - The README's "Run from source" and llms.txt's Install name `PORT` with
  #   its default, and the two, the deployment guide (EN) and .env.example say
  #   the user and the password `postgres` are fixed in config/dev.exs; none
  #   of them lists "user and password `postgres`" among the defaults.
  # - The deployment guide (EN, DE) gives the from-source route a table of the
  #   four variables, each with the default config/dev.exs gives it.
  test "the from-source route names its port and the database settings it reads" do
    flat = &String.replace(&1, ~r/\s+/, " ")
    dev = File.read!("config/dev.exs")

    defaults =
      ~r/System\.get_env\("([A-Z_]+)", "([^"]+)"\)/
      |> Regex.scan(dev, capture: :all_but_first)
      |> Map.new(fn [name, default] -> {name, default} end)
      |> Map.take(~w(PORT DATABASE_NAME DATABASE_HOST DATABASE_PORT))

    assert map_size(defaults) == 4, "config/dev.exs reads with a default: #{inspect(defaults)}"
    assert dev =~ ~r/username: "postgres",\s+password: "postgres",/

    section = fn path, from, to ->
      path |> File.read!() |> String.split(from) |> Enum.at(1) |> String.split(to) |> hd()
    end

    readme = flat.(section.("README.md", "### Run from source", "### API and MCP"))
    install = flat.(section.("docs/llms.txt", "## Install", "## Connect the MCP companion"))
    guide_en = normalized("docs/home-deployment.md")
    guide_de = normalized("docs/de/home-deployment.md")
    env_example = flat.(String.replace(File.read!(".env.example"), ~r/^# ?/m, ""))

    fixed =
      "user `postgres` with password `postgres`, which `config/dev.exs` fixes: " <>
        "no variable changes them"

    for {path, doc} <- [{"README.md", readme}, {"docs/llms.txt", install}] do
      assert doc =~ "`PORT` (default `#{defaults["PORT"]}`)", path
      assert doc =~ fixed, path
      refute doc =~ "user and password `postgres`", path
    end

    assert guide_en =~ fixed

    assert guide_de =~
             "Benutzer `postgres` mit dem Passwort `postgres`, die `config/dev.exs` festlegt: " <>
               "keine Variable ändert sie"

    assert env_example =~ "user postgres with password postgres, which config/dev.exs fixes"
    refute env_example =~ "user and password postgres"

    for {path, guide} <- [
          {"docs/home-deployment.md", guide_en},
          {"docs/de/home-deployment.md", guide_de}
        ],
        {name, default} <- defaults do
      assert guide =~ "| `#{name}` | `#{default}` |", "#{path}: #{name} defaults to #{default}"
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
