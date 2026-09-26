defmodule Portfolixir.Invariants.ScopeB2OutboundChokepointTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Net.Http

  # NFR-9 backstop B2 (Sprint 16 Lane N, #885). The gates it backs, as
  # registered in scope_b7_gate_registry_test.exs:
  #   gate:nongoal.order_placing_connection
  #   gate:nongoal.external_llm_calls
  #   gate:gated.b3_3_data_acquisition
  #   gate:gated.b3_7_push_delivery
  #   gate:gated.phase3_readonly_sync
  #
  # User story:
  # As the operator whose instance reads quotes, rates, search results and
  # logos from a few public hosts and acts on none of them,
  # I want a meta-test that fails when anything but one bounded, GET-only
  # client opens an outbound connection, when that client gains a caller or a
  # host nobody registered, when the app starts reading an environment
  # variable nobody listed, or when the MCP companion talks to anything but
  # the API base it is configured with,
  # so that an order-placing connection, an LLM call, a push to an external
  # endpoint, a new data source or a bank sync cannot arrive as one more HTTP
  # call and one more secret in the environment before its ADR exists.
  #
  # Acceptance criteria:
  # - No module in lib/, config/, priv/ or mix.exs outside
  #   `Portfolixir.Net.Http` calls an HTTP, socket, mailer or subprocess
  #   client: Req only to merge options into a request the chokepoint built
  #   and to read a response; Finch, Mint, :httpc, :gen_tcp, :ssl and their
  #   kin not at all. Name resolution is registered to the URL policy alone.
  # - `Portfolixir.Net.Http` issues only GET: its one issuing call pins the
  #   method, it makes no other Req call that issues a request, its public
  #   surface is `new/1` and `get/1,2`, and a request merged with another
  #   method, or redirected by a method-preserving status, still arrives as
  #   GET.
  # - Every module that calls `Net.Http` is registered with its purpose, and
  #   every host its allow-list declares — a literal list, a module
  #   attribute, or the application config it reads — is registered for it:
  #   an unregistered host fails by name, a registered one no longer declared
  #   fails as stale, and `:any` needs its own reason. `Net.Http` refuses a
  #   client without an allow-list and a first request outside it, so the
  #   declared list is the reach.
  # - Every environment variable the app and the MCP companion read is listed
  #   with its reason, a name the scan cannot read fails, and a
  #   credential-shaped name must be listed as a credential.
  # - The MCP companion imports only registered modules (no outbound client),
  #   calls fetch at one site with the configured base plus a path, builds
  #   that client once from PORTFOLIXIR_API_BASE_URL, and every tool's path is
  #   an /api/v1/ path, so no argument can move the host.
  # - Each matcher catches synthetic violations, so a clean tree cannot pass
  #   vacuously; every registry entry carries a reason and still names
  #   something real.
  #
  # The limit, stated rather than hidden: B2 reads the application's own
  # source. What a dependency does by itself (Req's connection pool,
  # Postgrex's socket to the operator's database) is B3's to class, and
  # config/test.exs is left out of the host scan because it confines every
  # source to fake names the stubs answer for; no test reaches the network.

  @chokepoint "Portfolixir.Net.Http"

  # `module => %{purpose, hosts}`: every caller of the chokepoint. `hosts` is
  # what its allow-list declares; `hosts_from: :config` reads a computed
  # allow-list from `config :portfolixir, <module>, allowed_hosts: ...`, and
  # `any:` is the reason a declared `:any` is allowed. Quotes and FX sit
  # inside the line B3.3 draws (ADR-0005, ADR-0007); search and logos are
  # catalogue metadata that books nothing.
  @adapters %{
    "Portfolixir.Catalog.QuoteSync.Yahoo" => %{
      purpose: "daily quote history for a security with a ticker (ADR-0005)",
      hosts: ["query1.finance.yahoo.com", "query2.finance.yahoo.com"]
    },
    "Portfolixir.Fx.RateSync.Ecb" => %{
      purpose: "the ECB's reference exchange rates, daily feed and one-shot history (ADR-0007)",
      hosts: ["www.ecb.europa.eu"]
    },
    "Portfolixir.Catalog.SecuritySearch.PortfolioPerformance" => %{
      purpose: "the security search for stocks, ETFs and funds (ADR-0005's search half)",
      hosts: ["api.portfolio-performance.info"]
    },
    "Portfolixir.Catalog.SecuritySearch.CoinGecko" => %{
      purpose: "the security search for crypto assets and a coin's logo image URL (ADR-0005)",
      hosts: ["api.coingecko.com"]
    },
    "Portfolixir.Catalog.LogoLookup.Wikipedia" => %{
      purpose:
        "logo discovery: a page summary, a validated page search and the Wikidata entity " <>
          "that name a security's logo file; presentation metadata only",
      hosts: ["en.wikipedia.org", "www.wikidata.org"]
    },
    "Portfolixir.Catalog.LogoLookup.CompaniesLogo" => %{
      purpose: "logo discovery's fallback: the page that names a company's logo image URL",
      hosts: ["companieslogo.com", ".companieslogo.com"]
    },
    "Portfolixir.Catalog.LogoStore" => %{
      purpose:
        "downloads the logo image a discovery source found, or the one the operator names " <>
          "for a security, and stores its bytes (#762)",
      hosts_from: :config,
      hosts: [
        ".coingecko.com",
        "upload.wikimedia.org",
        "commons.wikimedia.org",
        ".wikipedia.org",
        "companieslogo.com",
        ".companieslogo.com"
      ],
      any:
        "the operator's own logo URL for one security (`manual: :any`): typed by the " <>
          "operator, and still https-only, public-address-only and redirect-guarded"
    }
  }

  # `name => {:config | :credential, reason}`: every environment variable the
  # app (lib/, config/, priv/, mix.exs) and the MCP companion (mcp-server/src)
  # read. A credential here authenticates something local or a read-only data
  # provider; none opens a bank, broker or wallet.
  @env_names %{
    "PHX_HOST" => {:config, "the name the endpoint serves and builds its URLs for"},
    "PORT" => {:config, "the web listener's port"},
    "PHX_BIND_ALL" => {:config, "binds the listener beyond loopback when set (ADR-0045 §2)"},
    "PHX_SERVER" => {:config, "starts the listener in the test configuration for browser runs"},
    "PHX_FORCE_SSL" => {:config, "redirects plain HTTP and sets HSTS behind TLS (#759)"},
    "PORTFOLIXIR_FORCE_SSL_EXCLUDED_HOSTS" =>
      {:config,
       "inbound Host names the forced-TLS redirect leaves on plain HTTP, the companion's " <>
         "Compose name (E25 S7, F23); never an outbound host"},
    "PORTFOLIXIR_ALLOWED_HOSTS" =>
      {:config, "further names the inbound Host guard accepts (#758); never an outbound host"},
    "PORTFOLIXIR_TRUSTED_PROXIES" =>
      {:config, "the proxies whose forwarded headers the throttle and the scheme believe (#771)"},
    "PORTFOLIXIR_LOGO_DIR" => {:config, "the directory stored logos are written to (E25 S2)"},
    "PORTFOLIXIR_SESSION_DAYS" => {:config, "how long a UI login stays valid (ADR-0045)"},
    "TZ" =>
      {:config,
       "the host clock's zone: what \"today\" is, and the zone each database session takes " <>
         "on connect (E25 S6, G08)"},
    "DATABASE_URL" =>
      {:credential,
       "the production database URL, which carries the database role's password; it names " <>
         "the operator's own database"},
    "DATABASE_SSL" => {:config, "turns TLS on for the production database connection"},
    "POOL_SIZE" => {:config, "the database connection pool's size"},
    "DATABASE_HOST" => {:config, "the dev and test database's host (local PostgreSQL)"},
    "DATABASE_PORT" => {:config, "the test database's port (local PostgreSQL)"},
    "DATABASE_NAME" => {:config, "the dev and test database's name (local PostgreSQL)"},
    "DATABASE_USER" => {:config, "the test database's role (local PostgreSQL)"},
    "DATABASE_PASSWORD" =>
      {:credential, "the test database role's password (local PostgreSQL, a throwaway default)"},
    "SECRET_KEY_BASE" =>
      {:credential,
       "signs and encrypts the instance's cookies and derives its salts; checked at boot (F67)"},
    "PORTFOLIXIR_API_TOKEN" =>
      {:credential,
       "the local bearer token the JSON API accepts and the MCP companion presents " <>
         "(AGENTS.md: tokens from environment configuration)"},
    "PORTFOLIXIR_API_PRINCIPAL" =>
      {:config,
       "the name the journal records for writes made with PORTFOLIXIR_API_TOKEN (Compose: " <>
         "mcp); a label, never a credential or a host (E25 S7 review round)"},
    "PORTFOLIXIR_API_TOKENS" =>
      {:credential,
       "named local bearer tokens the JSON API accepts, name=token entries whose name the " <>
         "journal records as the actor label (E25 S7, G26)"},
    "PORTFOLIXIR_UI_PASSWORD" =>
      {:credential, "the optional UI login password (ADR-0045); never stored (B1)"},
    "COINGECKO_API_KEY" =>
      {:credential,
       "an optional key for CoinGecko's public search API, sent only to its registered " <>
         "host and dropped on a hop to another origin (F27); a read-only data key"},
    "PORTFOLIXIR_API_BASE_URL" =>
      {:config, "the MCP companion's one egress: the API base every tool call goes to"},
    "PORTFOLIXIR_MCP_TOKEN" =>
      {:credential, "the bearer token the companion's own HTTP listener accepts (#761)"},
    "PORTFOLIXIR_MCP_TRANSPORT" => {:config, "stdio or the companion's own HTTP listener"},
    "PORTFOLIXIR_MCP_HOST" => {:config, "the address the companion's HTTP listener binds"},
    "PORTFOLIXIR_MCP_PORT" => {:config, "the port the companion's HTTP listener binds"},
    "PORTFOLIXIR_MCP_ALLOWED_HOSTS" =>
      {:config, "further Host names the companion's listener answers under; inbound only"},
    "PORTFOLIXIR_MCP_READ_ONLY" =>
      {:config, "the companion's opt-in switch to list and call only reading tools (E25 S7)"}
  }

  # `{module, call} => reason`: where a host name may be resolved.
  @resolvers %{
    {"Portfolixir.Net.UrlPolicy", ":inet.getaddrs"} =>
      "the URL policy's default resolver: every address a name maps to is judged before " <>
        "the bounded client connects (#762, F32); the test suite plugs a fake"
  }

  # What a module outside the chokepoint may call on Req: merge options into
  # a request the chokepoint built, and read a response it returned.
  @req_outside %{
    {[:Req], :merge} =>
      "an adapter merges its test stub and per-call options into the request Net.Http " <>
        "built; merging issues nothing, and Net.Http pins GET and its guard when it runs",
    {[:Req, :Response], :any} => "reads a response Net.Http returned"
  }

  # The chokepoint's own Req vocabulary. `Req.request/1` is the one call that
  # issues a request, and only with the method pinned to GET.
  @req_chokepoint %{
    {[:Req], :new} => "builds the bounded request; issues nothing",
    {[:Req], :merge} => "merges the caller's options, then turns Req's own redirects off",
    {[:Req], :request} => "the one issuing call, and only as Req.request(%{req | method: :get})",
    {[:Req], :get_headers_list} => "reads the headers to drop on a hop to another origin",
    {[:Req, :Request], :put_private} => "stores the byte cap, allow-list, hop cap and deadline",
    {[:Req, :Request], :get_private} => "reads the byte cap, allow-list, hop cap and deadline",
    {[:Req, :Request], :delete_option} => "drops the first hop's params and the auth option",
    {[:Req, :Request], :delete_header} => "drops a header that could carry a credential",
    {[:Req, :Request], :t} => "the request type in a spec",
    {[:Req, :Response], :any} => "reads a response, and marks one cut at the byte cap"
  }

  # Namespaces and Erlang modules that open a connection or hand a message to
  # a remote endpoint (mailers included); any use of one fails.
  @client_namespaces ~w(Finch Mint HTTPoison HTTPotion Tesla WebSockex Mojito Swoosh Bamboo)a
  @client_erlang ~w(httpc inets hackney gun gen_tcp gen_udp gen_sctp ssl socket ftp tftp ssh
                    ssh_sftp gen_smtp_client)a

  # A subprocess can open any connection.
  @subprocess [
    {{:elixir, [:System]}, :cmd},
    {{:elixir, [:System]}, :shell},
    {{:elixir, [:Port]}, :open},
    {{:erlang, :os}, :cmd},
    {{:erlang, :erlang}, :open_port}
  ]

  @resolver_calls %{inet: ~w(getaddr getaddrs gethostbyname gethostbyaddr)a, inet_res: :all}

  # `specifier => {:all | [names], reason}`: what the MCP companion may import.
  # Its own relative modules are scanned in their turn.
  @mcp_imports %{
    "@modelcontextprotocol/sdk/server/mcp.js" =>
      {:all, "the MCP server object; it answers on a transport and dials nothing"},
    "@modelcontextprotocol/sdk/server/stdio.js" =>
      {:all, "the stdio transport: the agent's own process pipes"},
    "@modelcontextprotocol/sdk/server/streamableHttp.js" =>
      {:all, "the HTTP transport behind the companion's own inbound listener"},
    "@modelcontextprotocol/sdk/types.js" =>
      {["CallToolRequestSchema", "ListToolsRequestSchema", "CallToolResult", "Tool"],
       "the protocol's request schemas and result types the server answers with; data only"},
    "express" => {:all, "the companion's inbound HTTP listener (#761)"},
    "zod" => {:all, "the tools' input schemas"},
    "node:crypto" => {:all, "the constant-time bearer-token compare"},
    "node:http" =>
      {["STATUS_CODES"], "status texts for the listener's error bodies; nothing that dials"}
  }

  # `helper => reason`: functions a tool may build its API path with. Each is
  # checked to keep the path's `/api/v1/` prefix.
  @mcp_path_helpers %{
    "withQuery" => "appends a query string to the /api/v1/ path it is handed",
    "riskPath" => "builds the risk lens's /api/v1/portfolios/<id>/risk path and its query"
  }

  # Name tokens that make an environment variable credential-shaped; stems
  # also match inside a fused token (`PGPASSWORD`).
  @credential_words ~w(password passwd passphrase pwd secret token pin tan otp totp mfa
                       credential credentials login username apikey privkey mnemonic passcode)
  @credential_stems ~w(password passwd secret token credential apikey)
  @credential_phrases [~w(api key), ~w(access key), ~w(private key), ~w(signing key)]

  describe "the chokepoint" do
    test "no module outside Net.Http opens a connection or starts a client" do
      refs = elixir_refs()

      assert Enum.any?(
               refs,
               &match?({_, @chokepoint, {:call, {:elixir, [:Req]}, :request, _, _}}, &1)
             ),
             "the scan did not see the chokepoint's issuing call; the extraction is broken"

      offenders = outbound_violations(refs)

      assert offenders == [],
             "Outbound calls outside the one GET-only chokepoint (NFR-9 B2):\n" <>
               Enum.join(offenders, "\n")
    end

    test "Req is used outside the chokepoint only as registered" do
      used = refs_req_use(elixir_refs())

      assert_registry(used.outside, @req_outside, "Req calls outside the chokepoint")
      assert_registry(used.chokepoint, @req_chokepoint, "Req calls inside the chokepoint")
    end

    test "name resolution runs only where it is registered" do
      found = elixir_refs() |> resolver_uses() |> MapSet.new()

      assert MapSet.size(found) > 0, "the resolver scan found nothing"

      assert_registry(found, @resolvers, "name-resolution call sites")
    end
  end

  describe "the chokepoint issues only GET" do
    test "its one issuing call pins the method and nothing else issues a request" do
      source = File.read!("lib/portfolixir/net/http.ex")

      assert get_only_violations(source, "lib/portfolixir/net/http.ex") == []
    end

    test "its public surface is the builder and the GET" do
      assert Enum.sort(Http.__info__(:functions)) == [get: 1, get: 2, new: 1]
    end

    test "a request merged with another method, and a redirect that keeps methods, arrive as GET" do
      test_pid = self()

      plug = fn conn ->
        send(test_pid, {:request, conn.method, conn.request_path})

        case conn.request_path do
          "/start" ->
            conn
            |> Plug.Conn.put_resp_header("location", "/next")
            |> Plug.Conn.send_resp(307, "")

          _other ->
            Plug.Conn.send_resp(conn, 200, "ok")
        end
      end

      req =
        [max_bytes: 1_000, allowed_hosts: ["b2.example.com"]]
        |> Http.new()
        |> Req.merge(method: :post)

      assert {:ok, %Req.Response{status: 200}} =
               Http.get(req, url: "https://b2.example.com/start", method: :delete, plug: plug)

      assert_received {:request, "GET", "/start"}
      assert_received {:request, "GET", "/next"}
      refute_received {:request, _method, _path}
    end
  end

  describe "the adapter registry and the host allow-list" do
    test "every caller of Net.Http is registered with its purpose" do
      found = elixir_refs() |> chokepoint_callers() |> MapSet.new()

      assert MapSet.size(found) > 3, "the caller scan found too few callers"

      for {module, entry} <- @adapters do
        assert is_binary(entry[:purpose]) and String.length(entry.purpose) > 20,
               "#{module} needs a written purpose"
      end

      assert_registry(
        found,
        Map.new(@adapters, fn {m, e} -> {m, e.purpose} end),
        "Net.Http callers"
      )
    end

    test "every host an adapter may reach is registered for it" do
      declared = declared_hosts_by_module()

      assert map_size(declared) > 3, "the host scan found too few allow-lists"

      # A module that declares hosts without an entry is checked against an
      # empty one, so its hosts are named before it is registered.
      modules = Enum.uniq(Map.keys(@adapters) ++ Map.keys(declared))

      for module <- modules do
        entry = Map.get(@adapters, module, %{hosts: []})
        hosts = hosts_for(module, declared, entry)

        assert hosts != :computed,
               "#{module} builds its allow-list at run time and names no config it reads " <>
                 "(NFR-9 B2): declare the hosts as a literal or register `hosts_from: :config`"

        {any?, names} = Enum.split_with(hosts, &(&1 == :any))

        unregistered = Enum.uniq(names) -- entry.hosts
        stale = entry.hosts -- names

        assert unregistered == [],
               "#{module} may reach hosts nobody registered (NFR-9 B2): #{inspect(unregistered)}"

        assert stale == [],
               "#{module}: registered hosts it no longer declares — remove them: #{inspect(stale)}"

        if any? != [] do
          assert is_binary(entry[:any]) and String.length(entry.any) > 20,
                 "#{module} declares :any, which needs its own reason"
        else
          refute Map.has_key?(entry, :any), "#{module}: stale :any reason — remove it"
        end
      end
    end

    test "a client without an allow-list is refused, and a first request outside it makes none" do
      assert_raise KeyError, fn -> Http.new(max_bytes: 1_000) end

      test_pid = self()

      plug = fn conn ->
        send(test_pid, :requested)
        Plug.Conn.send_resp(conn, 200, "")
      end

      req = Http.new(max_bytes: 1_000, allowed_hosts: ["b2.example.com"])

      assert {:error, {:url_not_allowed, :host_not_allowed}} =
               Http.get(req, url: "https://elsewhere.example.com/", plug: plug)

      refute_received :requested
    end
  end

  describe "the environment-name allow-list" do
    test "every variable the app and the companion read is listed with its reason" do
      {names, computed} = env_reads()

      assert length(names) > 10, "the environment scan found too few names"

      assert computed == [],
             "Environment reads the scan cannot name (NFR-9 B2):\n" <> Enum.join(computed, "\n")

      assert_registry(
        MapSet.new(names),
        Map.new(@env_names, fn {name, {_kind, reason}} -> {name, reason} end),
        "environment variables"
      )
    end

    test "a credential-shaped name is listed as a credential" do
      for {name, {kind, _reason}} <- @env_names do
        assert kind in [:config, :credential], "#{name}: unknown kind #{inspect(kind)}"

        if credential_shaped?(name) do
          assert kind == :credential,
                 "#{name} reads as a credential; list it as :credential and say what it " <>
                   "authenticates (NFR-9 B2)"
        end
      end
    end
  end

  describe "the MCP companion's single egress" do
    test "it imports no outbound client" do
      offenders =
        Enum.flat_map(mcp_sources(), fn path -> import_violations(File.read!(path), path) end)

      assert offenders == [],
             "MCP companion imports outside the registry (NFR-9 B2):\n" <>
               Enum.join(offenders, "\n")

      used =
        mcp_sources()
        |> Enum.flat_map(&(&1 |> File.read!() |> imports() |> Enum.map(fn {spec, _} -> spec end)))
        |> Enum.reject(&relative?/1)
        |> MapSet.new()

      assert_registry(
        used,
        Map.new(@mcp_imports, fn {spec, {_, reason}} -> {spec, reason} end),
        "MCP imports"
      )
    end

    test "it reaches only the configured API base" do
      sources = for path <- mcp_sources(), do: {path, File.read!(path)}

      assert Enum.any?(sources, fn {path, _} -> Path.basename(path) == "api-client.ts" end),
             "the scan did not see the API client"

      offenders =
        Enum.flat_map(sources, fn {path, source} -> egress_violations(source, path) end) ++
          construction_violations(sources)

      assert offenders == [],
             "MCP companion egress outside the configured API base (NFR-9 B2):\n" <>
               Enum.join(offenders, "\n")
    end

    test "every tool's path keeps the API base's host" do
      source = File.read!("mcp-server/src/tools.ts")

      {count, offenders, helpers} = tool_path_violations(source)

      assert count > 100, "the path scan found too few tool calls: #{count}"

      assert offenders == [],
             "Tool paths that could move the API host (NFR-9 B2):\n" <> Enum.join(offenders, "\n")

      assert_registry(MapSet.new(helpers), @mcp_path_helpers, "MCP path helpers")
    end
  end

  describe "the matchers (self-test: a clean tree cannot pass vacuously)" do
    test "synthetic outbound calls outside the chokepoint are caught, innocent ones are not" do
      source = """
      defmodule Portfolixir.SyntheticBroker do
        alias Portfolixir.Net.Http
        alias Req.Request, as: Raw
        alias Mint.HTTP

        def a(url), do: Req.post(url, json: %{side: "buy"})
        def b(req), do: req |> Req.request()
        def c(req), do: Raw.run_request(req)
        def d(req), do: Finch.request(req, SyntheticFinch)
        def e(host), do: HTTP.connect(:https, host, 443)
        def f(url), do: :httpc.request(:post, {url, [], ~c"application/json", "{}"}, [], [])
        def g(host), do: :gen_tcp.connect(host, 443, [])
        def h(host), do: :ssl.connect(host, 443, [])
        def i(url), do: System.cmd("curl", ["-X", "POST", url])
        def j, do: apply(Req, :put, ["https://example.test"])
        def k, do: &Req.get/1
        def l, do: [{Finch, name: SyntheticFinch}]

        def ok(req, stub), do: req |> Req.merge(plug: stub) |> Http.get()
        def ok_read(%Req.Response{} = response), do: Req.Response.get_header(response, "etag")
        def ok_parse(host), do: :inet.parse_strict_address(host)
      end
      """

      offenders = outbound_violations(refs(source, "synthetic.ex"))

      assert length(offenders) == 14, Enum.join(offenders, "\n")
      refute Enum.any?(offenders, &(&1 =~ ~r/Req\.merge|Req\.Response|parse_strict_address/))
    end

    test "a synthetic resolver outside the policy is caught" do
      source = """
      defmodule Portfolixir.SyntheticProbe do
        def a(host), do: :inet.gethostbyname(host)
        def b(host), do: :inet_res.lookup(host, :in, :a)
        def ok(address), do: :inet.ntoa(address)
      end
      """

      assert source |> refs("synthetic.ex") |> resolver_uses() |> Enum.sort() == [
               {"Portfolixir.SyntheticProbe", ":inet.gethostbyname"},
               {"Portfolixir.SyntheticProbe", ":inet_res.lookup"}
             ]
    end

    test "a synthetic chokepoint that issues another method is caught" do
      source = """
      defmodule Portfolixir.Net.Http do
        def new(opts), do: Req.new(method: :post, url: opts[:url])
        def get(req), do: Req.request(%{req | method: :get})
        def put(req), do: Req.request(%{req | method: :put})
        def any(req), do: Req.request(req)
        def post(req, body), do: Req.post(req, body: body)
      end
      """

      offenders = get_only_violations(source, "synthetic.ex")

      assert length(offenders) == 5, Enum.join(offenders, "\n")
      refute Enum.any?(offenders, &(&1 =~ ":get"))
    end

    test "callers are found however the chokepoint is aliased, and their hosts are read" do
      source = """
      defmodule Portfolixir.SyntheticQuotes do
        alias Portfolixir.Net.Http
        @allowed_hosts ["quotes.example.com", ".cdn.example.com"]
        def req, do: Http.new(max_bytes: 10, allowed_hosts: @allowed_hosts)
      end

      defmodule Portfolixir.SyntheticNews do
        alias Portfolixir.Net
        def req, do: Net.Http.new(max_bytes: 10, allowed_hosts: ["news.example.com"])
      end

      defmodule Portfolixir.SyntheticPush do
        alias Portfolixir.Net.{Http, UrlPolicy}
        def req(hosts), do: Http.new(max_bytes: 10, allowed_hosts: hosts)
        def ok(url), do: UrlPolicy.check(url)
      end

      defmodule Portfolixir.SyntheticAny do
        alias Portfolixir.Net.Http, as: Outbound
        def req, do: Outbound.new(max_bytes: 10, allowed_hosts: :any)
        def run(req), do: Outbound.get(req)
      end

      defmodule Portfolixir.SyntheticRates do
        alias Portfolixir.Net.Http
        def req(bounds), do: Http.new([allowed_hosts: ["rates.example.com"]] ++ bounds)
      end

      defmodule Portfolixir.SyntheticOverride do
        alias Portfolixir.Net.Http
        def req(bounds), do: Http.new(bounds ++ [allowed_hosts: ["override.example.com"]])
      end

      defmodule Portfolixir.SyntheticBystander do
        def run(url), do: {:fetch, url}
      end
      """

      refs = refs(source, "synthetic.ex")

      assert refs |> chokepoint_callers() |> Enum.sort() == [
               "Portfolixir.SyntheticAny",
               "Portfolixir.SyntheticNews",
               "Portfolixir.SyntheticOverride",
               "Portfolixir.SyntheticPush",
               "Portfolixir.SyntheticQuotes",
               "Portfolixir.SyntheticRates"
             ]

      declared = declared_hosts(source, refs)

      assert declared["Portfolixir.SyntheticQuotes"] == ["quotes.example.com", ".cdn.example.com"]
      assert declared["Portfolixir.SyntheticNews"] == ["news.example.com"]
      assert declared["Portfolixir.SyntheticPush"] == :computed
      assert declared["Portfolixir.SyntheticAny"] == [:any]
      assert declared["Portfolixir.SyntheticRates"] == ["rates.example.com"]
      assert declared["Portfolixir.SyntheticOverride"] == :computed
    end

    test "a config allow-list is read, and a computed one is refused" do
      source = """
      import Config

      config :portfolixir, Portfolixir.SyntheticStore,
        allowed_hosts: %{feed: ["feed.example.com"], manual: :any},
        storage_dir: "/tmp"

      config :portfolixir, Portfolixir.SyntheticOther, allowed_hosts: System.get_env("HOSTS")
      """

      assert config_hosts(source) == %{
               "Portfolixir.SyntheticStore" => ["feed.example.com", :any],
               "Portfolixir.SyntheticOther" => :computed
             }
    end

    test "synthetic environment reads are named, computed ones are caught" do
      elixir = """
      defmodule Portfolixir.SyntheticEnv do
        @default "x"
        def a, do: System.get_env("BROKER_PIN")
        def b, do: System.get_env("PORTFOLIXIR_FEED", @default)
        def c, do: "BANK_LOGIN" |> System.get_env()
        def d, do: System.fetch_env!("LLM_API_KEY")
        def e, do: :os.getenv(~c"WEBHOOK_URL")
        def f(name), do: System.get_env(name)
        def g, do: System.get_env()
      end
      """

      {names, computed} = elixir_env_reads(elixir, "synthetic.ex")

      assert names == ~w(BROKER_PIN PORTFOLIXIR_FEED BANK_LOGIN LLM_API_KEY WEBHOOK_URL)
      assert length(computed) == 2

      ts = """
      const base = process.env.PORTFOLIXIR_API_BASE_URL ?? "http://127.0.0.1:4000";
      const key = process.env["OPENAI_API_KEY"];
      const { BROKER_TOKEN } = process.env;
      const any = process.env[name];
      """

      {names, computed} = ts_env_reads(ts, "synthetic.ts")

      assert names == ~w(PORTFOLIXIR_API_BASE_URL OPENAI_API_KEY)
      assert length(computed) == 2
    end

    test "credential-shaped names are recognised, configuration names are not" do
      for name <- ~w(SECRET_KEY_BASE PGPASSWORD BROKER_PIN BANK_LOGIN LLM_API_KEY
                     PORTFOLIXIR_MCP_TOKEN DATABASE_PASSWORD SIGNING_KEY) do
        assert credential_shaped?(name), "#{name} should read as a credential"
      end

      for name <- ~w(PHX_HOST PORTFOLIXIR_ALLOWED_HOSTS POOL_SIZE PORTFOLIXIR_SESSION_DAYS
                     PORTFOLIXIR_API_BASE_URL SPINNER TANGENT) do
        refute credential_shaped?(name), "#{name} should not read as a credential"
      end
    end

    test "synthetic companion imports and egress are caught" do
      source = """
      import { request } from "node:https";
      import http from "node:http";
      import { STATUS_CODES, get } from "node:http";
      import type { Request } from "express";
      import { Client } from "@modelcontextprotocol/sdk/client/index.js";
      import { helper } from "./helper.js";
      export { thing } from "undici";

      const lazy = await import("got");
      const legacy = require("axios");
      const socket = new WebSocket("wss://push.example.com");

      export async function leak(data: unknown) {
        await fetch("https://llm.example.com/v1", { method: "POST", body: JSON.stringify(data) });
      }
      """

      imports = import_violations(source, "synthetic.ts")

      assert length(imports) == 7, Enum.join(imports, "\n")
      assert Enum.any?(imports, &(&1 =~ "node:https"))
      assert Enum.any?(imports, &(&1 =~ ~s(node:http" default)))
      assert Enum.any?(imports, &(&1 =~ ~s(node:http" name get)))
      assert Enum.any?(imports, &(&1 =~ "sdk/client"))
      assert Enum.any?(imports, &(&1 =~ "undici"))
      refute Enum.any?(imports, &(&1 =~ ~r/express|helper/))

      egress = egress_violations(source, "synthetic.ts")

      assert length(egress) == 2, Enum.join(egress, "\n")
      assert Enum.any?(egress, &(&1 =~ "WebSocket"))
      assert Enum.any?(egress, &(&1 =~ "fetch"))
    end

    test "an API client built twice, or from another base, is caught" do
      good = """
      const apiBaseUrl = process.env.PORTFOLIXIR_API_BASE_URL ?? "http://127.0.0.1:4000";
      const client = createApiClient({ baseUrl: apiBaseUrl, token: apiToken });
      """

      assert construction_violations([{"index.ts", good}]) == []

      assert [_] =
               construction_violations([
                 {"index.ts", good},
                 {"extra.ts", ~s[const b = createApiClient({ baseUrl: other, token });]}
               ])

      remote = String.replace(good, "http://127.0.0.1:4000", "https://api.example.com")
      assert [_] = construction_violations([{"index.ts", remote}])

      literal = ~s[const client = createApiClient({ baseUrl: "https://api.example.com" });]
      assert [_] = construction_violations([{"index.ts", literal}])
    end

    test "a synthetic API client with a second target is caught" do
      client = """
      export function createApiClient(options: ApiClientOptions): ApiClient {
        const fetchImpl = options.fetch ?? globalThis.fetch.bind(globalThis);
        const baseUrl = options.baseUrl.replace(/\\/+$/, "");
        return {
          async request(method: string, path: string) {
            await fetchImpl("https://telemetry.example.com/ping");
            return fetchImpl(`${baseUrl}${path}`, { method });
          }
        };
      }
      """

      assert [offender] = egress_violations(client, "mcp-server/src/api-client.ts")
      assert offender =~ "fetchImpl"
    end

    test "synthetic tool paths that could move the host are caught" do
      source = """
      function riskPath(args: Record<string, any>): string {
        const path = `/api/v1/portfolios/${args.portfolio_id}/risk`;
        return path;
      }

      function withQuery(path: string, args: Record<string, any>, keys: string[]): string {
        const query = "";
        return query === "" ? path : `${path}?${query}`;
      }

      async function call(client: ApiClient, args: any) {
        await client.request("GET", "/api/v1/portfolios");
        await client.request(
          "GET",
          withQuery(`/api/v1/securities/${args.id}`, args, ["since"])
        );
        await client.request("GET", riskPath(args));
        await client.request("POST", args.url, {});
        await client.request("GET", `${args.host}/api/v1/x`);
        await client.request("GET", withQuery(args.path, args, []));
        await client.request("GET", `@elsewhere.example.com/x`);
      }
      """

      {count, offenders, helpers} = tool_path_violations(source)

      assert count == 7
      assert length(offenders) == 4, Enum.join(offenders, "\n")
      assert Enum.sort(helpers) == ["riskPath", "withQuery"]
    end
  end

  # --- registry assertion --------------------------------------------------

  defp assert_registry(found, registry, label) do
    for {entry, reason} <- registry do
      assert is_binary(reason) and String.length(reason) > 20,
             "#{label}: #{inspect(entry)} needs a written reason"
    end

    missing = MapSet.reject(found, &Map.has_key?(registry, &1))
    stale = registry |> Map.keys() |> MapSet.new() |> MapSet.difference(found)

    assert MapSet.size(missing) == 0,
           "Unregistered #{label} (NFR-9 B2) — register each with its reason:\n" <>
             Enum.map_join(missing, "\n", &inspect/1)

    assert MapSet.size(stale) == 0,
           "Stale #{label} registry entries — remove them:\n" <>
             Enum.map_join(stale, "\n", &inspect/1)
  end

  # --- Elixir sources ------------------------------------------------------

  defp elixir_sources do
    Enum.sort(
      Path.wildcard("lib/**/*.ex") ++
        Path.wildcard("config/**/*.exs") ++ Path.wildcard("priv/**/*.exs") ++ ["mix.exs"]
    )
  end

  defp elixir_refs, do: Enum.flat_map(elixir_sources(), &refs(File.read!(&1), &1))

  # `[{path, module, ref}]` for every call with a module target and every
  # bare alias in a source, aliases expanded, pipes unfolded, each attributed
  # to the innermost `defmodule` around it (the path, in a script). A call's
  # target is not also reported as a bare alias.
  defp refs(source, path) do
    ast = source |> Code.string_to_quoted!() |> Macro.prewalk(&unpipe/1)
    aliases = alias_table(ast)

    ast
    |> walk([], aliases)
    |> Enum.map(fn {module, ref} -> {path, module_name(module, path), ref} end)
  end

  defp module_name([], path), do: path
  defp module_name(segments, _path), do: Enum.map_join(segments, ".", &segment/1)

  defp segment(segment) when is_atom(segment), do: Atom.to_string(segment)
  defp segment(segment), do: Macro.to_string(segment)

  defp walk({:defmodule, _, [{:__aliases__, _, segments}, body]}, outer, aliases),
    do: walk(body, outer ++ segments, aliases)

  # An alias declaration names its source once; its `as:` short name is not
  # a second reference.
  defp walk({:alias, _meta, [source | _opts]}, module, aliases),
    do: walk(source, module, aliases)

  # A capture (`&Req.get/1`) is a call of that arity.
  defp walk({:&, _, [{:/, _, [{{:., _, [target, fun]}, meta, []}, arity]}]}, module, aliases)
       when is_atom(fun) and is_integer(arity),
       do:
         walk(
           {{:., meta, [target, fun]}, meta, List.duplicate(:captured, arity)},
           module,
           aliases
         )

  defp walk({{:., _, [target, fun]}, meta, args}, module, aliases)
       when is_atom(fun) and is_list(args) do
    case call_target(target, aliases) do
      nil ->
        walk(target, module, aliases) ++ walk(args, module, aliases)

      resolved ->
        [{module, {:call, resolved, fun, args, meta[:line]}} | walk(args, module, aliases)]
    end
  end

  defp walk({:__aliases__, meta, segments}, module, aliases),
    do: [{module, {:alias, expand(segments, aliases), meta[:line]}}]

  defp walk({form, _meta, args}, module, aliases),
    do: walk(form, module, aliases) ++ walk(args, module, aliases)

  defp walk({left, right}, module, aliases),
    do: walk(left, module, aliases) ++ walk(right, module, aliases)

  defp walk(list, module, aliases) when is_list(list),
    do: Enum.flat_map(list, &walk(&1, module, aliases))

  defp walk(_leaf, _module, _aliases), do: []

  defp call_target({:__aliases__, _, segments}, aliases),
    do: {:elixir, expand(segments, aliases)}

  defp call_target(module, _aliases) when is_atom(module), do: {:erlang, module}
  defp call_target(_other, _aliases), do: nil

  # `short => full segments` for every `alias` in a source: plain, `as:`,
  # and the `{A, B}` multi-alias form.
  defp alias_table(ast) do
    {_ast, table} =
      Macro.prewalk(ast, %{}, fn
        {:alias, _, [{:__aliases__, _, segments} | opts]} = node, acc ->
          short =
            case opts do
              [[as: {:__aliases__, _, [as]}]] -> as
              _plain -> List.last(segments)
            end

          {node, put_alias(acc, short, segments)}

        {:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, children}]} = node, acc ->
          acc =
            Enum.reduce(children, acc, fn
              {:__aliases__, _, rest}, inner -> put_alias(inner, List.last(rest), base ++ rest)
              _other, inner -> inner
            end)

          {node, acc}

        node, acc ->
          {node, acc}
      end)

    table
  end

  defp put_alias(table, short, segments) when is_atom(short) do
    if Enum.all?(segments, &is_atom/1), do: Map.put(table, short, segments), else: table
  end

  defp put_alias(table, _short, _segments), do: table

  defp expand([first | rest] = segments, aliases) when is_atom(first) do
    case Map.fetch(aliases, first) do
      {:ok, full} -> full ++ rest
      :error -> segments
    end
  end

  defp expand(segments, _aliases), do: segments

  defp unpipe({:|>, _, [left, right]} = node) do
    Macro.pipe(left, right, 0)
  rescue
    ArgumentError -> node
  end

  defp unpipe(node), do: node

  defp inside_chokepoint?(module),
    do: module == @chokepoint or String.starts_with?(module, @chokepoint <> ".")

  defp chokepoint?(segments), do: Enum.take(segments, 3) == [:Portfolixir, :Net, :Http]

  # --- outbound matchers ---------------------------------------------------

  defp outbound_violations(refs), do: Enum.flat_map(refs, &outbound_violation/1)

  defp outbound_violation(
         {path, module, {:call, {:elixir, [:Req | _] = segments}, fun, args, line}}
       ) do
    vocabulary = if inside_chokepoint?(module), do: @req_chokepoint, else: @req_outside

    cond do
      not req_allowed?(vocabulary, segments, fun) ->
        ["#{path}:#{line}: #{Enum.join(segments, ".")}.#{fun}/#{length(args)} in #{module}"]

      segments == [:Req] and fun == :request and not pinned_get?(args) ->
        ["#{path}:#{line}: Req.request/#{length(args)} without the method pinned to GET"]

      true ->
        []
    end
  end

  defp outbound_violation({path, module, {:alias, [:Req | _] = segments, line}}) do
    allowed =
      if inside_chokepoint?(module),
        do: [[:Req, :Response], [:Req, :Request]],
        else: [[:Req, :Response]]

    if segments in allowed,
      do: [],
      else: ["#{path}:#{line}: #{Enum.join(segments, ".")} referenced in #{module}"]
  end

  defp outbound_violation({path, module, {:call, target, fun, args, line}}) do
    cond do
      client?(target) ->
        ["#{path}:#{line}: #{target_name(target)}.#{fun}/#{length(args)} in #{module}"]

      {target, fun} in @subprocess ->
        ["#{path}:#{line}: #{target_name(target)}.#{fun} starts a subprocess in #{module}"]

      true ->
        []
    end
  end

  defp outbound_violation({path, module, {:alias, [namespace | _] = segments, line}})
       when namespace in @client_namespaces,
       do: ["#{path}:#{line}: #{Enum.join(segments, ".")} referenced in #{module}"]

  defp outbound_violation(_ref), do: []

  defp client?({:elixir, [namespace | _]}), do: namespace in @client_namespaces
  defp client?({:erlang, module}), do: module in @client_erlang

  defp target_name({:elixir, segments}), do: Enum.join(segments, ".")
  defp target_name({:erlang, module}), do: ":#{module}"

  defp req_allowed?(vocabulary, segments, fun),
    do: Map.has_key?(vocabulary, {segments, fun}) or Map.has_key?(vocabulary, {segments, :any})

  defp pinned_get?([{:%{}, _, [{:|, _, [_request, fields]}]}]) when is_list(fields),
    do: Keyword.keyword?(fields) and Keyword.get(fields, :method) == :get

  defp pinned_get?(_args), do: false

  # `%{outside: set, chokepoint: set}` of the registry keys each Req call
  # uses, so an entry nothing uses any more fails as stale.
  defp refs_req_use(refs) do
    for {_path, module, {:call, {:elixir, [:Req | _] = segments}, fun, _args, _line}} <- refs,
        reduce: %{outside: MapSet.new(), chokepoint: MapSet.new()} do
      acc ->
        {side, vocabulary} =
          if inside_chokepoint?(module),
            do: {:chokepoint, @req_chokepoint},
            else: {:outside, @req_outside}

        key =
          if Map.has_key?(vocabulary, {segments, :any}),
            do: {segments, :any},
            else: {segments, fun}

        Map.update!(acc, side, &MapSet.put(&1, key))
    end
  end

  # `{module, ":mod.fun"}` for every call that resolves a host name.
  defp resolver_uses(refs) do
    refs
    |> Enum.flat_map(fn
      {_path, module, {:call, {:erlang, erlang}, fun, _args, _line}} ->
        if resolver_call?(erlang, fun), do: [{module, ":#{erlang}.#{fun}"}], else: []

      _ref ->
        []
    end)
    |> Enum.uniq()
  end

  defp resolver_call?(erlang, fun) do
    case Map.get(@resolver_calls, erlang) do
      :all -> true
      funs when is_list(funs) -> fun in funs
      nil -> false
    end
  end

  # The chokepoint's own source: every Req call is in its vocabulary, the one
  # issuing call pins GET, and no `method:` option names anything else.
  defp get_only_violations(source, path) do
    calls =
      source
      |> refs(path)
      |> Enum.filter(&match?({_, _, {:call, {:elixir, [:Req | _]}, _, _, _}}, &1))
      |> Enum.flat_map(fn {p, _module, ref} -> outbound_violation({p, @chokepoint, ref}) end)

    {_ast, methods} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:method, value} = node, acc when value != :get ->
          {node, acc ++ ["#{path}: a method: option naming #{Macro.to_string(value)}"]}

        node, acc ->
          {node, acc}
      end)

    calls ++ methods
  end

  # --- adapters and hosts --------------------------------------------------

  defp chokepoint_callers(refs) do
    for {_path, module, ref} <- refs,
        not inside_chokepoint?(module),
        chokepoint?(ref_segments(ref)),
        uniq: true,
        do: module
  end

  defp ref_segments({:call, {:elixir, segments}, _fun, _args, _line}), do: segments
  defp ref_segments({:alias, segments, _line}), do: segments
  defp ref_segments(_ref), do: []

  defp declared_hosts_by_module do
    Enum.reduce(Path.wildcard("lib/**/*.ex"), %{}, fn path, acc ->
      source = File.read!(path)
      Map.merge(acc, declared_hosts(source, refs(source, path)))
    end)
  end

  # `module => [host | :any] | :computed`: what each `Net.Http.new/1` call's
  # `allowed_hosts:` declares — a literal, or a module attribute holding one.
  defp declared_hosts(source, refs) do
    attributes = host_attributes(source)

    for {_path, module, {:call, {:elixir, [:Portfolixir, :Net, :Http]}, :new, args, _line}} <-
          refs,
        reduce: %{} do
      acc ->
        hosts = args |> allowed_hosts_arg() |> literal_hosts(attributes)
        Map.update(acc, module, hosts, &merge_hosts(&1, hosts))
    end
  end

  defp allowed_hosts_arg([opts]), do: keyword_value(opts, :allowed_hosts)
  defp allowed_hosts_arg(_args), do: :computed

  # A key's value in a literal keyword list, or in `left ++ right` read the
  # way `Keyword.fetch!/2` reads it: the left side's occurrence first.
  defp keyword_value({:++, _, [left, right]}, key) do
    case keyword_value(left, key) do
      :missing -> keyword_value(right, key)
      found -> found
    end
  end

  defp keyword_value(list, key) when is_list(list) do
    if Keyword.keyword?(list), do: Keyword.get(list, key, :missing), else: :computed
  end

  defp keyword_value(_computed, _key), do: :computed

  defp literal_hosts(:any, _attributes), do: [:any]

  defp literal_hosts(list, _attributes) when is_list(list) do
    if Enum.all?(list, &is_binary/1), do: list, else: :computed
  end

  defp literal_hosts({:@, _, [{name, _, context}]}, attributes) when is_atom(context) do
    case Map.fetch(attributes, name) do
      {:ok, value} -> literal_hosts(value, %{})
      :error -> :computed
    end
  end

  defp literal_hosts(_computed, _attributes), do: :computed

  defp merge_hosts(:computed, _hosts), do: :computed
  defp merge_hosts(_hosts, :computed), do: :computed
  defp merge_hosts(left, right), do: Enum.uniq(left ++ right)

  defp host_attributes(source) do
    {_ast, attributes} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk(%{}, fn
        {:@, _, [{name, _, [value]}]} = node, acc when is_atom(name) ->
          {node, Map.put(acc, name, value)}

        node, acc ->
          {node, acc}
      end)

    attributes
  end

  defp hosts_for(module, declared, entry) do
    case {Map.get(declared, module, []), Map.get(entry, :hosts_from)} do
      {:computed, :config} -> configured_hosts(module)
      {hosts, _} -> hosts
    end
  end

  # The hosts `config :portfolixir, <module>, allowed_hosts:` declares in the
  # configuration an instance runs with; config/test.exs holds fakes only.
  defp configured_hosts(module) do
    "config/*.exs"
    |> Path.wildcard()
    |> Enum.reject(&(Path.basename(&1) == "test.exs"))
    |> Enum.map(&(&1 |> File.read!() |> config_hosts() |> Map.get(module, [])))
    |> Enum.reduce([], &merge_hosts/2)
  end

  # `module => [host | :any] | :computed` for every `allowed_hosts:` in a
  # config file: a literal list, `:any`, or a map of such per source.
  defp config_hosts(source) do
    {_ast, found} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk(%{}, fn
        {:config, _, [:portfolixir, {:__aliases__, _, segments}, opts]} = node, acc
        when is_list(opts) ->
          if Keyword.keyword?(opts) and Keyword.has_key?(opts, :allowed_hosts) do
            module = Enum.join(segments, ".")
            {node, Map.put(acc, module, config_value_hosts(opts[:allowed_hosts]))}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp config_value_hosts({:%{}, _, pairs}) do
    Enum.reduce(pairs, [], fn
      {source, value}, acc when is_atom(source) -> merge_hosts(acc, literal_hosts(value, %{}))
      _computed, _acc -> :computed
    end)
  end

  defp config_value_hosts(value), do: literal_hosts(value, %{})

  # --- environment names ---------------------------------------------------

  defp env_reads do
    elixir = Enum.map(elixir_sources(), &elixir_env_reads(File.read!(&1), &1))
    ts = Enum.map(mcp_sources(), &ts_env_reads(File.read!(&1), &1))

    Enum.reduce(elixir ++ ts, {[], []}, fn {n, c}, {names, computed} ->
      {Enum.uniq(names ++ n), computed ++ c}
    end)
  end

  # `{names, computed}`: every `System.get_env/fetch_env` and `:os.getenv`
  # name a source reads; a name the scan cannot read is `computed`.
  defp elixir_env_reads(source, path) do
    source
    |> refs(path)
    |> Enum.flat_map(fn
      {_p, _m, {:call, {:elixir, [:System]}, fun, args, line}}
      when fun in [:get_env, :fetch_env, :fetch_env!] ->
        [env_name(args, "#{path}:#{line}: System.#{fun}/#{length(args)}")]

      {_p, _m, {:call, {:erlang, :os}, :getenv, args, line}} ->
        [env_name(args, "#{path}:#{line}: :os.getenv/#{length(args)}")]

      _ref ->
        []
    end)
    |> Enum.reduce({[], []}, fn
      {:name, name}, {names, computed} -> {Enum.uniq(names ++ [name]), computed}
      {:computed, where}, {names, computed} -> {names, computed ++ [where]}
    end)
  end

  defp env_name([name | _], _where) when is_binary(name), do: {:name, name}

  defp env_name([{:sigil_c, _, [{:<<>>, _, [name]}, _modifiers]} | _], _where)
       when is_binary(name),
       do: {:name, name}

  defp env_name(_args, where), do: {:computed, where <> " reads a name the scan cannot read"}

  # `{names, computed}` of a TypeScript source: `process.env.NAME` and
  # `process.env["NAME"]` are read; any other use of `process.env` (a
  # computed key, a destructuring, the whole object) is `computed`.
  defp ts_env_reads(source, path) do
    ~r/process\s*\.\s*env\b(?:\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)|\s*\[\s*["']([A-Za-z_][A-Za-z0-9_]*)["']\s*\])?/
    |> Regex.scan(source, return: :index)
    |> Enum.map(fn [{start, _} | groups] ->
      case Enum.find(groups, &match?({s, _} when s >= 0, &1)) do
        {s, l} ->
          {:name, binary_part(source, s, l)}

        nil ->
          {:computed,
           "#{path}:#{line_of(source, start)}: process.env read whole or by a computed key"}
      end
    end)
    |> Enum.reduce({[], []}, fn
      {:name, name}, {names, computed} -> {Enum.uniq(names ++ [name]), computed}
      {:computed, where}, {names, computed} -> {names, computed ++ [where]}
    end)
  end

  defp credential_shaped?(name) do
    tokens = name |> String.downcase() |> String.split(~r/[^a-z0-9]+/, trim: true)

    Enum.any?(tokens, &(&1 in @credential_words)) or
      Enum.any?(tokens, fn token -> Enum.any?(@credential_stems, &String.contains?(token, &1)) end) or
      Enum.any?(Enum.chunk_every(tokens, 2, 1, :discard), &(&1 in @credential_phrases))
  end

  # --- the MCP companion ---------------------------------------------------

  defp mcp_sources, do: Enum.sort(Path.wildcard("mcp-server/src/**/*.ts"))

  defp relative?(specifier), do: String.starts_with?(specifier, ".")

  # `[{specifier, clause}]` of every static `import ... from` and
  # `export ... from`, and every side-effect `import "..."`.
  defp imports(source) do
    from =
      ~r/^\s*(?:import|export)\s+(?:type\s+)?([^;]*?)\s+from\s+["']([^"']+)["']/ms
      |> Regex.scan(source)
      |> Enum.map(fn [_, clause, spec] -> {spec, clause} end)

    bare =
      ~r/^\s*import\s+["']([^"']+)["']/m
      |> Regex.scan(source)
      |> Enum.map(fn [_, spec] -> {spec, ""} end)

    from ++ bare
  end

  defp import_violations(source, path) do
    static =
      source
      |> imports()
      |> Enum.reject(fn {spec, _clause} -> relative?(spec) end)
      |> Enum.flat_map(fn {spec, clause} ->
        case Map.fetch(@mcp_imports, spec) do
          :error -> ["#{path}: imports \"#{spec}\", which the registry does not list"]
          {:ok, {:all, _reason}} -> []
          {:ok, {names, _reason}} -> restricted_import(spec, clause, names, path)
        end
      end)

    dynamic =
      ~r/\b(import|require)\s*\(/
      |> Regex.scan(source, return: :index)
      |> Enum.map(fn [{start, _} | _] ->
        "#{path}:#{line_of(source, start)}: a dynamic import or require the scan cannot read"
      end)

    static ++ dynamic
  end

  # A module registered for some of its names: only a braced list of those.
  defp restricted_import(spec, clause, names, path) do
    case Regex.run(~r/^\{(.*)\}$/s, String.trim(clause)) do
      [_, inner] ->
        inner
        |> String.split(",", trim: true)
        |> Enum.map(&(&1 |> String.trim() |> String.replace_prefix("type ", "")))
        |> Enum.map(&(&1 |> String.split(~r/\s+as\s+/) |> hd()))
        |> Enum.reject(&(&1 == "" or &1 in names))
        |> Enum.map(&"#{path}: \"#{spec}\" name #{&1} is not registered")

      nil ->
        ["#{path}: \"#{spec}\" default or namespace import: #{String.trim(clause)}"]
    end
  end

  # Egress the companion could open without an import: the global fetch
  # outside the API client's one site, and the other network globals. In the
  # API client, fetch is called at one site, with the base plus a path.
  defp egress_violations(source, path) do
    client? = Path.basename(path) == "api-client.ts"

    stripped =
      if client?,
        do:
          Enum.reduce(
            ["fetch?: FetchLike", "options.fetch ??", "globalThis.fetch.bind(globalThis)"],
            source,
            &String.replace(&2, &1, "")
          ),
        else: source

    globals =
      ~r/\b(fetch|WebSocket|EventSource|XMLHttpRequest|sendBeacon)\b/
      |> Regex.scan(stripped, return: :index)
      |> Enum.map(fn [{start, length} | _] ->
        "#{path}:#{line_of(stripped, start)}: #{binary_part(stripped, start, length)}"
      end)

    globals ++ if(client?, do: client_violations(source, path), else: [])
  end

  defp client_violations(source, path) do
    sites = Regex.scan(~r/\bfetchImpl\s*\(\s*([^,)]+)/, source)

    sites_ok =
      case sites do
        [[_, "`${baseUrl}${path}`"]] -> []
        _ -> ["#{path}: fetchImpl is called other than once with `${baseUrl}${path}`"]
      end

    base_ok =
      if source =~ ~r/const baseUrl = options\.baseUrl\b/,
        do: [],
        else: ["#{path}: the base is not the configured options.baseUrl"]

    sites_ok ++ base_ok
  end

  # The companion builds its one API client once, from
  # PORTFOLIXIR_API_BASE_URL, whose default is loopback.
  defp construction_violations(sources) do
    calls =
      for {path, source} <- sources,
          [_, arg] <- Regex.scan(~r/(?<!function )\bcreateApiClient\s*\(([^)]*)\)/, source),
          do: {path, source, arg}

    case calls do
      [{path, source, arg}] ->
        with [_, base] <- Regex.run(~r/^\s*\{\s*baseUrl:\s*([A-Za-z_]+)\b/, arg),
             [_, default] <-
               Regex.run(
                 ~r/const #{base} = process\.env\.PORTFOLIXIR_API_BASE_URL \?\? "([^"]+)"/,
                 source
               ),
             true <- URI.parse(default).host in ["127.0.0.1", "localhost", "[::1]", "::1"] do
          []
        else
          _other ->
            [
              "#{path}: the API client's base is not PORTFOLIXIR_API_BASE_URL with a loopback default"
            ]
        end

      other ->
        ["the API client is built #{length(other)} times; the companion builds it once"]
    end
  end

  # `{calls, offenders, helpers}` of tools.ts: each `client.request(...)`
  # path starts with `/api/v1/`, directly or through a registered helper.
  defp tool_path_violations(source) do
    count = length(Regex.scan(~r/\bclient\.request\(/, source))

    parsed =
      Regex.scan(
        ~r/\bclient\.request\(\s*"[A-Z]+"\s*,\s*(withQuery\(\s*|([A-Za-z_]+)\(|)(.{0,12})/s,
        source
      )

    {offenders, helpers} =
      Enum.reduce(parsed, {[], []}, fn [whole, wrapper, helper, start], {offenders, helpers} ->
        cond do
          wrapper =~ "withQuery" and api_path?(start) and
              helper_keeps_prefix?(source, "withQuery") ->
            {offenders, helpers ++ ["withQuery"]}

          wrapper == "" and api_path?(start) ->
            {offenders, helpers}

          helper != "" and helper_keeps_prefix?(source, helper) ->
            {offenders, helpers ++ [helper]}

          true ->
            {offenders ++ [String.trim(whole)], helpers}
        end
      end)

    unparsed =
      if length(parsed) == count, do: [], else: ["#{count - length(parsed)} unreadable calls"]

    {count, offenders ++ unparsed, Enum.uniq(helpers)}
  end

  defp api_path?(start), do: String.starts_with?(start, ["\"/api/v1/", "`/api/v1/"])

  # A helper keeps the prefix when its body builds the path from a literal
  # `/api/v1/` start (`riskPath`) or hands its own `path` argument back
  # (`withQuery`).
  defp helper_keeps_prefix?(source, helper) do
    case Regex.run(~r/function #{helper}\(([^)]*)\)[^{]*\{(.*?)\n\}/s, source) do
      [_, _params, body] ->
        body =~ ~r/const path = [`"]\/api\/v1\// or
          body =~ ~r/return query === "" \? path : `\$\{path\}\?\$\{query\}`;/

      nil ->
        false
    end
  end

  defp line_of(source, offset),
    do: source |> binary_part(0, offset) |> String.split("\n") |> length()
end
