defmodule Portfolixir.Invariants.ScopeB4NonGoalNamesTest do
  use Portfolixir.DataCase, async: true

  # NFR-9 backstop B4 (Sprint 16 Lane N, #885). The gates it backs, as
  # registered in scope_b7_gate_registry_test.exs:
  #   gate:nongoal.order_placing_connection
  #   gate:nongoal.order_creation
  #   gate:nongoal.automated_trading_or_payment
  #   gate:nongoal.advice
  #   gate:nongoal.raw_news_archive
  #   gate:nongoal.external_llm_calls
  #   gate:gated.level_d_backtesting
  #   gate:gated.b3_3_data_acquisition
  #   gate:gated.b3_7_push_delivery
  #   gate:gated.b3_8_local_model
  #   gate:gated.phase3_readonly_sync
  #
  # User story:
  # As the operator who reads decisions rather than code,
  # I want a meta-test that fails when a route, an MCP tool, a LiveView event,
  # a table or a module is named for a permanent non-goal (orders, trading,
  # payment, moving money, executing a rebalance, advice, a news archive, an
  # LLM call) or for a gated capability that has no accepted ADR,
  # so that the first file of a forbidden feature is refused by name, before
  # its behaviour exists to be reviewed.
  #
  # Acceptance criteria:
  # - Every router route, every tool in mcp-server/src/tools.ts, every literal
  #   `handle_event/3` name under lib/portfolixir_web, every table of the
  #   database schema and every application module is checked.
  # - Legitimate words are excused by phrase, never by dropping the word: an
  #   allowance order is a tax record (ADR-0031), quote and FX sync are inside
  #   the line B3.3 draws (ADR-0005, ADR-0007). A permanent-class excuse carries
  #   a reason; a gated-class excuse names an accepted ADR.
  # - The ledger's transfer kinds and ADR-0023's display-only rebalancing hints
  #   are values and payload fields, not names of a surface, so nothing is
  #   excused for them today; a surface named for one takes an entry with
  #   ADR-0023 or the ledger's reason.
  # - The matcher catches synthetic violations of every kind of name, so a
  #   clean tree cannot pass vacuously, and an excuse still excuses a real name.

  # `{class, gate, words}` or `{class, gate, phrases}`: a name violates when a
  # word, or a phrase's tokens in order, appears among its tokens. Words with
  # an innocent ledger meaning on their own (`trade` for a recorded buy, `feed`
  # for a quote source) are listed only inside phrases.
  @vocabulary [
    # Permanent non-goals: identity, not backlog.
    {:permanent, "nongoal.order_placing_connection",
     [~w(broker connection), ~w(broker api), ~w(order routing)]},
    {:permanent, "nongoal.order_creation", ~w(order orders rebalance rebalancing rebalancer)},
    {:permanent, "nongoal.automated_trading_or_payment",
     ~w(trading autotrade autotrading pay payment payments transfer transfers remittance wire)},
    {:permanent, "nongoal.automated_trading_or_payment",
     [~w(trade execution), ~w(execute trade), ~w(execute trades), ~w(auto trade)]},
    {:permanent, "nongoal.automated_trading_or_payment", [~w(send money), ~w(move money)]},
    {:permanent, "nongoal.advice",
     ~w(advice advisor advisory recommendation recommendations robo)},
    {:permanent, "nongoal.raw_news_archive", ~w(news newsfeed headline headlines)},
    {:permanent, "nongoal.external_llm_calls",
     ~w(llm llms chat chatbot completion completions openai gpt genai)},
    # Gated: each opens only with its own ADR.
    {:gated, "gated.level_d_backtesting",
     ~w(backtest backtests backtesting simulator simulation simulate scenario scenarios
        whatif counterfactual replay)},
    {:gated, "gated.level_d_backtesting", [~w(what if)]},
    {:gated, "gated.b3_3_data_acquisition", ~w(scrape scraper scraping crawl crawler rss)},
    {:gated, "gated.b3_7_push_delivery",
     ~w(webhook webhooks push notify notifier notification notifications mailer email smtp
        sms)},
    {:gated, "gated.b3_8_local_model", ~w(ollama llama inference embedding embeddings ocr)},
    {:gated, "gated.phase3_readonly_sync",
     ~w(sync broker brokers brokerage bank banks banking fints hbci psd2 openbanking wallet
        wallets xpub)}
  ]

  @terms (for {class, gate, entries} <- @vocabulary, entry <- entries do
            %{tokens: List.wrap(entry), class: class, gate: gate}
          end)

  # An excuse masks a phrase in a name before the terms are matched, so
  # `portfolixir.quotes.sync_broker` still fails on `broker`. `kinds: :all` or a
  # list of name kinds. A permanent-class excuse needs a `reason`, a gated-class
  # one an accepted `adr`.
  @excuses [
    %{
      phrases: [~w(allowance order), ~w(allowance orders)],
      kinds: :all,
      class: :permanent,
      reason:
        "a tax-exemption instruction (Freistellungsauftrag) transcribed as a " <>
          "recorded tax parameter (ADR-0031) — not a market order"
    },
    %{
      phrases: [~w(quote sync), ~w(quotes sync), ~w(sync quotes)],
      kinds: :all,
      class: :gated,
      adr: "ADR-0005",
      reason: "quote history acquisition, inside the line B3.3 draws ('beyond quotes and FX')"
    },
    %{
      phrases: [~w(rate sync), ~w(rates sync), ~w(sync rates)],
      kinds: :all,
      class: :gated,
      adr: "ADR-0007",
      reason: "ECB exchange-rate acquisition, inside the line B3.3 draws ('beyond quotes and FX')"
    },
    %{
      phrases: [~w(sync now)],
      kinds: [:event],
      class: :gated,
      adr: "ADR-0005",
      reason: "the securities page's button that runs the quote sync (QuoteSync.sync_all/0)"
    }
  ]

  test "no route, MCP tool, LiveView event, table or module is named for a non-goal or an unopened gate" do
    names = live_names()

    for kind <- [:route, :tool, :event, :table, :module] do
      assert Enum.count(names, &match?({^kind, _}, &1)) > 5,
             "the #{kind} scan found too few names to be meaningful"
    end

    offenders = Enum.flat_map(names, &violations/1)

    assert offenders == [],
           "Names for a non-goal or a gated capability without its ADR (NFR-9 B4):\n" <>
             Enum.map_join(offenders, "\n", fn {{kind, name}, term} ->
               "#{kind} #{name}: '#{Enum.join(term.tokens, " ")}' (#{term.class}, #{term.gate})"
             end)
  end

  describe "the matcher (self-test: a clean tree cannot pass vacuously)" do
    test "synthetic names of every kind are caught" do
      for name <- [
            {:route, "POST /api/v1/orders"},
            {:route, "GET /api/v1/portfolios/:portfolio_id/backtest"},
            {:tool, "portfolixir.broker.sync"},
            {:tool, "portfolixir.quotes.sync_broker"},
            {:tool, "portfolixir.accounts.sync_now"},
            {:event, "place_order"},
            {:event, "execute_rebalance"},
            {:table, "news_articles"},
            {:table, "money_transfers"},
            {:module, "Portfolixir.Llm.ChatCompletion"},
            {:module, "Portfolixir.Notifications.WebhookDelivery"},
            {:module, "PortfolixirWeb.Api.V1.PaymentController"}
          ] do
        assert violations(name) != [], "#{inspect(name)} should be caught"
      end
    end

    test "excused phrases and innocent neighbours are not caught" do
      for name <- [
            {:tool, "portfolixir.allowance_orders.list"},
            {:route, "DELETE /api/v1/tax/allowance_orders/:id"},
            {:tool, "portfolixir.quotes.sync"},
            {:route, "POST /api/v1/exchange_rates/sync"},
            {:module, "Portfolixir.Catalog.QuoteSync.Yahoo"},
            {:event, "sync_now"},
            {:module, "Portfolixir.Ledger.TradeMatcher"},
            {:route, "GET /api/v1/portfolios/:portfolio_id/allocation"},
            {:table, "security_notes"}
          ] do
        assert violations(name) == [], "#{inspect(name)} should not be caught"
      end
    end

    test "literal handle_event names are extracted, guarded clauses included" do
      source = """
      defmodule PortfolixirWeb.SyntheticLive do
        def handle_event("place_order", _params, socket), do: {:noreply, socket}

        def handle_event("bank_sync", params, socket) when is_map(params),
          do: {:noreply, socket}

        def handle_info(:tick, socket), do: {:noreply, socket}
      end
      """

      assert event_names(source) == ["place_order", "bank_sync"]
    end
  end

  test "every excuse is justified by its class and still excuses a real name" do
    names = live_names()

    for excuse <- @excuses do
      assert is_binary(excuse[:reason]) and String.length(excuse.reason) > 20

      if excuse.class == :gated do
        assert accepted_adr?(excuse[:adr]),
               "a gated-class excuse must name an accepted ADR: #{inspect(excuse)}"
      end

      for phrase <- excuse.phrases do
        assert Enum.any?(names, &excuses_a_term?(excuse, phrase, &1)),
               "stale excuse #{inspect(phrase)}: no current name needs it"
      end
    end
  end

  # --- matcher -------------------------------------------------------------

  # `[{name, term}]` for every term occurring in the name's unmasked tokens.
  defp violations({kind, name} = named) do
    tokens = tokens(name)

    masked =
      for excuse <- @excuses,
          applies?(excuse, kind),
          phrase <- excuse.phrases,
          at <- occurrences(tokens, phrase),
          position <- span(at, phrase),
          into: MapSet.new(),
          do: position

    for term <- @terms,
        at <- occurrences(tokens, term.tokens),
        not Enum.any?(span(at, term.tokens), &MapSet.member?(masked, &1)),
        uniq: true,
        do: {named, term}
  end

  # The excuse's phrase occurs in the name and covers a term there — the
  # excuse is still needed.
  defp excuses_a_term?(excuse, phrase, {kind, name}) do
    tokens = tokens(name)

    applies?(excuse, kind) and
      Enum.any?(occurrences(tokens, phrase), fn at ->
        covered = span(at, phrase)

        Enum.any?(@terms, fn term ->
          Enum.any?(occurrences(tokens, term.tokens), &(span(&1, term.tokens) -- covered == []))
        end)
      end)
  end

  defp applies?(%{kinds: :all}, _kind), do: true
  defp applies?(%{kinds: kinds}, kind), do: kind in kinds

  defp occurrences(tokens, phrase) do
    size = length(phrase)
    last = length(tokens) - size

    if last < 0, do: [], else: Enum.filter(0..last, &(Enum.slice(tokens, &1, size) == phrase))
  end

  defp span(at, phrase), do: Enum.to_list(at..(at + length(phrase) - 1))

  # `Portfolixir.Catalog.QuoteSync`, `portfolixir.quotes.sync_broker` and
  # `POST /api/v1/exchange_rates/sync` all split into lowercase word tokens.
  defp tokens(name) do
    name
    |> to_string()
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1_\\2")
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
  end

  # --- sources -------------------------------------------------------------

  defp live_names do
    routes = for r <- PortfolixirWeb.Router.__routes__(), do: {:route, "#{r.verb} #{r.path}"}

    tools =
      ~r/tool\(\s*"(portfolixir\.[a-z0-9_.]+)"/
      |> Regex.scan(File.read!("mcp-server/src/tools.ts"))
      |> Enum.map(fn [_, name] -> {:tool, name} end)

    events =
      "lib/portfolixir_web/**/*.ex"
      |> Path.wildcard()
      |> Enum.flat_map(&event_names(File.read!(&1)))
      |> Enum.uniq()
      |> Enum.map(&{:event, &1})

    %{rows: rows} =
      Repo.query!(
        "SELECT table_name FROM information_schema.tables WHERE table_schema = current_schema()"
      )

    tables = for [table] <- rows, do: {:table, table}

    {:ok, modules} = :application.get_key(:portfolixir, :modules)

    routes ++ tools ++ events ++ tables ++ Enum.map(modules, &{:module, inspect(&1)})
  end

  defp event_names(source) do
    {_ast, names} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:def, _, [{:when, _, [{:handle_event, _, [name | _]} | _]} | _]} = node, acc
        when is_binary(name) ->
          {node, acc ++ [name]}

        {:def, _, [{:handle_event, _, [name | _]} | _]} = node, acc when is_binary(name) ->
          {node, acc ++ [name]}

        node, acc ->
          {node, acc}
      end)

    names
  end

  defp accepted_adr?("ADR-" <> number) do
    case Path.wildcard("docs/decisions/#{number}-*.md") do
      [path] -> File.read!(path) =~ ~r/^- \*\*Status:\*\* Accepted/m
      _ -> false
    end
  end

  defp accepted_adr?(_adr), do: false
end
