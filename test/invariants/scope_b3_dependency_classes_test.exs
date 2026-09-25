defmodule Portfolixir.Invariants.ScopeB3DependencyClassesTest do
  use ExUnit.Case, async: true

  # NFR-9 backstop B3 (Sprint 16 Lane N, #885). The gates it backs, as
  # registered in scope_b7_gate_registry_test.exs:
  #   gate:nongoal.order_placing_connection
  #   gate:nongoal.order_creation
  #   gate:nongoal.automated_trading_or_payment
  #   gate:nongoal.raw_news_archive
  #   gate:nongoal.external_llm_calls
  #   gate:gated.b3_3_data_acquisition
  #   gate:gated.b3_7_push_delivery
  #   gate:gated.b3_8_local_model
  #   gate:gated.phase3_readonly_sync
  #
  # User story:
  # As the operator who never reads the code,
  # I want a meta-test that fails when the Hex tree or the MCP companion's npm
  # tree — direct AND transitive — gains a package of a non-goal or gated
  # class (order routing and trading, payment, an LLM client, a news feed, a
  # scraper, a push channel, a local model, a banking protocol),
  # so that a capability the scope line forbids cannot arrive as a dependency
  # before anyone has written the code that uses it.
  #
  # Acceptance criteria:
  # - Every package in mix.lock and in mcp-server/package-lock.json is checked,
  #   which covers transitive dependencies, not only the manifests.
  # - A package matching a permanent non-goal class fails unless an allowlist
  #   entry states a reason; one matching a gated class fails unless its entry
  #   names an accepted ADR.
  # - The denylist names protocols and categories generically and never a
  #   provider any one operator uses — naming one would disclose it.
  # - The matcher catches synthetic violations in both lock formats, so a
  #   clean tree cannot pass vacuously.
  # - An allowlist entry still names a locked package (stale entries fail).
  #
  # The MCP companion's direct dependencies are held to an explicit allowlist
  # by mcp_dependency_allowlist_test.exs (ADR-0002); this file widens the
  # scope-line half of that idea to both trees and to transitive packages.

  # Each class: the gate it backs (and any it also backs), whether it is a
  # permanent non-goal or a gated capability, and its vocabulary. `words` match a whole name token
  # (`order` matches `order-book`, not `ordered-map`); `stems` are distinctive
  # enough to match inside a token (`openai` in `openai_ex`).
  @classes [
    %{
      class: :permanent,
      gate: "nongoal.order_creation",
      category: "order routing and trading",
      words: ~w(order orders trading trader ccxt quickfix fixprotocol),
      stems: ~w(orderbook autotrad tradingbot)
    },
    %{
      class: :permanent,
      gate: "nongoal.automated_trading_or_payment",
      category: "payment",
      words: ~w(pay payment payments sepa),
      stems: ~w(stripe braintree)
    },
    %{
      class: :permanent,
      gate: "nongoal.external_llm_calls",
      category: "LLM client",
      words: ~w(ai genai gpt llm llms),
      stems: ~w(openai anthropic langchain llamaindex cohere mistralai tiktoken)
    },
    %{
      class: :permanent,
      gate: "nongoal.raw_news_archive",
      category: "news feed",
      words: ~w(news rss atom feedparser),
      stems: ~w(newsapi)
    },
    %{
      class: :gated,
      gate: "gated.b3_3_data_acquisition",
      category: "scraping",
      words: ~w(scrape crawl crawly),
      stems: ~w(scraper scraping crawler puppeteer cheerio)
    },
    %{
      class: :gated,
      gate: "gated.b3_7_push_delivery",
      category: "push delivery",
      # Mail, webhooks, web and mobile push, and the chat and SMS channels a
      # self-hosted alert would reach for — generic channels, not providers
      # anyone banks or trades with.
      words: ~w(push mail mailer smtp apns fcm firebase swoosh bamboo pigeon slack sms nadia),
      stems: ~w(webhook webpush nodemailer telegram telegex twilio discord pushover ntfy gotify)
    },
    %{
      class: :gated,
      gate: "gated.b3_8_local_model",
      category: "local model",
      words: ~w(nx exla emlx axon ortex torch torchx transformers),
      stems: ~w(bumblebee onnx tensorflow tfjs ollama llama tesseract)
    },
    %{
      class: :gated,
      gate: "gated.phase3_readonly_sync",
      # A banking or broker SDK is where an order-placing connection would
      # arrive too; it is caught until an ADR admits it as read-only.
      also_backs: ["nongoal.order_placing_connection"],
      category: "banking and broker access",
      words: ~w(bank banks banking broker brokers brokerage wallet ofx xpub bip32 bip39),
      stems: ~w(fints hbci ebics openbanking psd2 xs2a)
    }
  ]

  # `package => %{reason: text}` for a permanent class, or
  # `package => %{adr: "ADR-NNNN", reason: text}` for a gated class. Empty: no
  # locked package belongs to any class today.
  @allowlist %{}

  describe "the locked dependency trees" do
    test "no Hex package, direct or transitive, belongs to a non-goal or gated class" do
      hex = hex_packages(File.read!("mix.lock"))
      direct = Mix.Project.config() |> Keyword.fetch!(:deps) |> length()

      assert "phoenix" in hex, "the mix.lock scan did not see phoenix"
      assert length(hex) > direct, "the mix.lock scan saw no transitive packages"

      offenders = hex |> classify() |> reject_allowlisted()

      assert offenders == [],
             "Hex packages of a non-goal or gated class (NFR-9 B3):\n" <> describe(offenders)
    end

    test "no npm package of the MCP companion, direct or transitive, belongs to one" do
      npm = npm_packages(File.read!("mcp-server/package-lock.json"))
      manifest = "mcp-server/package.json" |> File.read!() |> Jason.decode!()

      direct =
        manifest
        |> Map.take(["dependencies", "devDependencies"])
        |> Map.values()
        |> Enum.flat_map(&Map.keys/1)

      assert "@modelcontextprotocol/sdk" in npm, "the package-lock scan did not see the MCP SDK"
      assert length(npm) > length(direct), "the package-lock scan saw no transitive packages"

      offenders = npm |> classify() |> reject_allowlisted()

      assert offenders == [],
             "npm packages of a non-goal or gated class (NFR-9 B3):\n" <> describe(offenders)
    end
  end

  describe "the matcher (self-test: a clean tree cannot pass vacuously)" do
    test "a synthetic mix.lock with class members is caught, neighbours are not" do
      lock = ~S"""
      %{
        "jason": {:hex, :jason, "1.4.4", "abc", [:mix], [], "hexpm", "def"},
        "openai_ex": {:hex, :openai_ex, "0.9.0", "abc", [:mix], [{:req, "~> 0.5", [hex: :req, repo: "hexpm", optional: false]}], "hexpm", "def"},
        "stripity_stripe": {:hex, :stripity_stripe, "3.2.0", "abc", [:mix], [], "hexpm", "def"},
        "crawly": {:hex, :crawly, "0.17.2", "abc", [:mix], [], "hexpm", "def"},
        "ordered_map": {:hex, :ordered_map, "0.1.0", "abc", [:mix], [], "hexpm", "def"},
        "fints_client": {:git, "https://example.invalid/acme/fints_client.git", "0123abc", []},
        "renamed": {:hex, :bumblebee, "0.6.0", "abc", [:mix], [], "hexpm", "def"},
        "order_router": {:hex, :order_router, "0.1.0", "abc", [:mix], [], "hexpm", "def"},
        "rss_reader": {:hex, :rss_reader, "0.1.0", "abc", [:mix], [], "hexpm", "def"},
        "telegex": {:hex, :telegex, "1.8.0", "abc", [:mix], [], "hexpm", "def"},
        "ex_twilio": {:hex, :ex_twilio, "0.10.0", "abc", [:mix], [], "hexpm", "def"}
      }
      """

      packages = hex_packages(lock)

      assert "fints_client" in packages
      assert "bumblebee" in packages

      caught = lock |> hex_packages() |> classify() |> Enum.map(&elem(&1, 0)) |> MapSet.new()

      assert MapSet.subset?(
               MapSet.new(~w(openai_ex stripity_stripe crawly fints_client bumblebee order_router
                    rss_reader telegex ex_twilio)),
               caught
             )

      refute "jason" in caught
      refute "ordered_map" in caught
    end

    test "a synthetic package-lock with class members is caught, neighbours are not" do
      lock =
        Jason.encode!(%{
          "lockfileVersion" => 3,
          "packages" => %{
            "" => %{"name" => "mcp-server"},
            "node_modules/zod" => %{"version" => "3.0.0"},
            "node_modules/@anthropic-ai/sdk" => %{"version" => "1.0.0"},
            "node_modules/express/node_modules/nodemailer" => %{"version" => "6.0.0"},
            "node_modules/innocent-alias" => %{"name" => "psd2-client", "version" => "1.0.0"},
            "node_modules/strip-ansi" => %{"version" => "7.0.0"},
            "node_modules/discord.js" => %{"version" => "14.0.0"},
            "node_modules/@slack/web-api" => %{"version" => "7.0.0"},
            "node_modules/pushover-notifications" => %{"version" => "1.0.0"}
          }
        })

      packages = npm_packages(lock)

      assert "nodemailer" in packages
      assert "psd2-client" in packages
      refute "" in packages

      caught = packages |> classify() |> Enum.map(&elem(&1, 0)) |> MapSet.new()

      assert MapSet.equal?(
               caught,
               MapSet.new(~w(@anthropic-ai/sdk nodemailer psd2-client discord.js @slack/web-api
                    pushover-notifications))
             )
    end

    test "every gate the file declares is carried by a class that catches a sample" do
      samples =
        ~w(openai_ex stripity_stripe crawly fints_client bumblebee order_router rss_reader
           nodemailer telegex)

      caught_gates =
        for {_package, class} <- classify(samples), gate <- gates(class), into: MapSet.new() do
          gate
        end

      class_gates = @classes |> Enum.flat_map(&gates/1) |> MapSet.new()

      declared =
        ~r/^\s*#\s*gate:([a-z0-9_.]+)\s*$/m
        |> Regex.scan(File.read!(__ENV__.file))
        |> MapSet.new(fn [_, id] -> id end)

      assert declared == class_gates,
             "the gate: lines and the classes' gates differ (NFR-9 B7): declared " <>
               inspect(Enum.sort(declared)) <> ", classes " <> inspect(Enum.sort(class_gates))

      assert MapSet.subset?(class_gates, caught_gates),
             "gates with no caught sample: " <>
               inspect(MapSet.difference(class_gates, caught_gates) |> Enum.sort())
    end

    test "every class names its gate and a vocabulary" do
      for class <- @classes do
        assert class.class in [:permanent, :gated]
        assert Enum.all?(gates(class), &(&1 =~ ~r/^(nongoal|gated)\./))
        assert class.words ++ class.stems != []
      end
    end
  end

  test "every allowlist entry is justified by its class and still names a locked package" do
    locked =
      hex_packages(File.read!("mix.lock")) ++
        npm_packages(File.read!("mcp-server/package-lock.json"))

    matched = locked |> classify() |> Map.new()

    for {package, entry} <- @allowlist do
      assert package in locked, "stale allowlist entry #{package}: remove it"
      assert %{class: class} = Map.fetch!(matched, package)
      assert is_binary(entry[:reason]) and String.length(entry[:reason]) > 20

      if class == :gated do
        assert accepted_adr?(entry[:adr]),
               "#{package} is gated: its entry must name an accepted ADR, got #{inspect(entry[:adr])}"
      end
    end
  end

  # --- matcher -------------------------------------------------------------

  # `[{package, %{class:, gate:, category:}}]` for every package of a class.
  defp classify(packages) do
    for package <- packages, class <- @classes, member?(package, class), do: {package, class}
  end

  # The gate a class backs first, and any other it backs as well.
  defp gates(class), do: [class.gate | Map.get(class, :also_backs, [])]

  defp member?(package, %{words: words, stems: stems}) do
    tokens = package |> String.downcase() |> String.split(~r/[^a-z0-9]+/, trim: true)

    Enum.any?(tokens, fn token ->
      token in words or Enum.any?(stems, &String.contains?(token, &1))
    end)
  end

  # --- lock readers --------------------------------------------------------

  # Every locked package of a mix.lock, read from its AST rather than evaluated,
  # with every atom kept as a string so the lock creates none: the lock key,
  # and the Hex package name when it differs (a renamed dep) or the repository
  # name of a git dep.
  defp hex_packages(lock_source) do
    {:%{}, _, pairs} =
      Code.string_to_quoted!(lock_source,
        emit_warnings: false,
        static_atoms_encoder: fn token, _meta -> {:ok, token} end
      )

    pairs
    |> Enum.flat_map(fn {key, {:{}, _, spec}} -> [key | spec_names(spec)] end)
    |> Enum.uniq()
  end

  defp spec_names(["hex", package | _]) when is_binary(package), do: [package]
  defp spec_names(["git", url | _]) when is_binary(url), do: [Path.basename(url, ".git")]
  defp spec_names(_spec), do: []

  # Every installed package of an npm v2/v3 lockfile, nested ones included,
  # plus the real name of an aliased install.
  defp npm_packages(lock_source) do
    lock_source
    |> Jason.decode!()
    |> Map.fetch!("packages")
    |> Enum.reject(fn {path, _} -> path == "" end)
    |> Enum.flat_map(fn {path, meta} ->
      installed = path |> String.split("node_modules/") |> List.last()
      [installed | List.wrap(meta["name"])]
    end)
    |> Enum.uniq()
  end

  defp reject_allowlisted(offenders),
    do: Enum.reject(offenders, fn {package, _} -> Map.has_key?(@allowlist, package) end)

  defp describe(offenders) do
    Enum.map_join(offenders, "\n", fn {package, class} ->
      "#{package}: #{class.category} (#{class.class}, #{class.gate})"
    end)
  end

  defp accepted_adr?("ADR-" <> number) do
    case Path.wildcard("docs/decisions/#{number}-*.md") do
      [path] -> File.read!(path) =~ ~r/^- \*\*Status:\*\* Accepted/m
      _ -> false
    end
  end

  defp accepted_adr?(_adr), do: false
end
