defmodule Portfolixir.Invariants.ScopeB7GateRegistryTest do
  use ExUnit.Case, async: true

  # NFR-9 backstop B7 (Sprint 16 Lane N, #885): the registry that couples every
  # hard gate's sentence in AGENTS.md to the invariant files that back it.
  #
  # User story:
  # As the owner who is author, approver and enforcer of the scope line,
  # I want the gate sentences in AGENTS.md and their mechanical backstops tied
  # to each other in both directions,
  # so that amending a sentence without its backstops, or dropping a backstop
  # without amending the sentence, fails the build — which is what NFR-9 means
  # by "removable only in the same PR as the ADR and the AGENTS.md amendment".
  #
  # Acceptance criteria:
  # - Each item of the permanent non-goals sentence and of the gated list is
  #   read out of AGENTS.md by its stable lead-in, and has exactly one registry
  #   entry; an entry whose item is no longer in the sentence fails as stale.
  # - The gates stated elsewhere (Phase 3 read-only sync, the document-intake
  #   hard rule, the level-(d) ladder rung) are found by their marker phrase.
  # - Every backstop the registry names exists and declares the gate in a
  #   `gate:<id>` line; every gate a backstop declares is registered for it;
  #   every scope_b*_test.exs file is named by the registry.
  # - The extraction and the coupling catch a synthetic amendment in each
  #   direction, so a clean tree cannot pass vacuously.
  #
  # B2 (the outbound chokepoint) lands after Lane S3 changes Net.Http's
  # redirect handling; it joins the entries for external LLM calls, B3.3 data
  # acquisition and Phase 3 then, with its own `gate:` lines.

  @b1 "test/invariants/scope_b1_no_stored_credentials_test.exs"
  @b3 "test/invariants/scope_b3_dependency_classes_test.exs"
  @b4 "test/invariants/scope_b4_non_goal_names_test.exs"
  @b5 "test/invariants/scope_b5_system_writers_and_schedulers_test.exs"
  @b6 "test/invariants/scope_b6_intake_formats_test.exs"

  @non_goals_lead_in "Permanent non-goals — identity, not backlog, and no capacity argument " <>
                       "reopens them: "
  @gated_lead_in "Gated, and none of them openable by citing the ladder: "

  @registry [
    %{
      id: "nongoal.order_placing_connection",
      sentence: {:non_goal, "no order-placing broker connection"},
      backstops: [@b1, @b3, @b4]
    },
    %{
      id: "nongoal.order_creation",
      sentence: {:non_goal, "no order creation or transmission"},
      backstops: [@b3, @b4]
    },
    %{
      id: "nongoal.automated_trading_or_payment",
      sentence: {:non_goal, "no automated trading or payment"},
      backstops: [@b3, @b4, @b5]
    },
    %{id: "nongoal.advice", sentence: {:non_goal, "no advice"}, backstops: [@b4]},
    %{
      id: "nongoal.raw_news_archive",
      sentence: {:non_goal, "no raw news archive"},
      backstops: [@b3, @b4]
    },
    %{
      id: "nongoal.external_llm_calls",
      sentence: {:non_goal, "no external LLM calls from the app"},
      backstops: [@b3, @b4]
    },
    %{
      id: "gated.level_d_backtesting",
      sentence: {:gated, "rule backtesting (level (d))"},
      markers: ["(d) backtesting rules against stored price history: forbidden"],
      backstops: [@b4, @b5]
    },
    %{
      id: "gated.b3_3_data_acquisition",
      sentence: {:gated, "data acquisition beyond quotes and FX (B3.3)"},
      backstops: [@b3, @b4, @b5]
    },
    %{
      id: "gated.b3_7_push_delivery",
      sentence: {:gated, "push delivery to external endpoints (B3.7)"},
      backstops: [@b3, @b4, @b5]
    },
    %{
      id: "gated.b3_8_local_model",
      sentence: {:gated, "a local model beyond ADR-0021's PDF-intake path (B3.8)"},
      backstops: [@b3, @b4]
    },
    %{
      id: "gated.phase3_readonly_sync",
      sentence:
        {:marker,
         "read-only acquisition stays permitted in principle and gated in practice " <>
           "(Phase 3, still forbidden here until its ADR lands)"},
      backstops: [@b1, @b3, @b4, @b5]
    },
    %{
      id: "gated.document_intake",
      sentence: {:marker, "Do not implement document intake (binary `.portfolio`, PP XML)"},
      backstops: [@b6]
    }
  ]

  setup_all do
    {:ok, agents: normalize(File.read!("AGENTS.md"))}
  end

  describe "AGENTS.md against the registry" do
    test "every permanent non-goal has exactly one entry, and none is stale", %{agents: agents} do
      items = list_items(agents, :non_goal)

      assert length(items) >= 6, "the non-goals sentence yielded too few items: #{inspect(items)}"

      assert_same_items(items, :non_goal, @registry)
    end

    test "every gated capability has exactly one entry, and none is stale", %{agents: agents} do
      items = list_items(agents, :gated)

      assert length(items) >= 4, "the gated list yielded too few items: #{inspect(items)}"

      assert_same_items(items, :gated, @registry)
    end

    test "every marker-found gate is still stated", %{agents: agents} do
      for entry <- @registry,
          marker <- markers(entry) do
        assert String.contains?(agents, marker),
               "#{entry.id}: AGENTS.md no longer states #{inspect(marker)} — amend the " <>
                 "registry and its backstops in the same change (NFR-9 B7)"
      end
    end
  end

  describe "the registry against the backstops" do
    test "every named backstop exists and declares the gate it backs" do
      for entry <- @registry, backstop <- entry.backstops do
        assert File.exists?(backstop), "#{entry.id}: backstop #{backstop} does not exist"

        assert entry.id in declared_gates(File.read!(backstop)),
               "#{backstop} does not declare gate:#{entry.id}"
      end
    end

    test "every gate a backstop declares is registered for it, and every backstop is named" do
      named = @registry |> Enum.flat_map(& &1.backstops) |> MapSet.new()
      files = backstop_files()

      assert MapSet.new(files) == named,
             "scope_b*_test.exs files and registry backstops differ — register a new " <>
               "backstop, or remove a dropped one from the registry with its sentence " <>
               "(NFR-9 B7): files #{inspect(files)}, registry #{inspect(MapSet.to_list(named))}"

      for file <- files do
        for id <- declared_gates(File.read!(file)) do
          assert Enum.any?(@registry, &(&1.id == id and file in &1.backstops)),
                 "#{file} declares gate:#{id}, which the registry does not list for it"
        end
      end
    end
  end

  describe "the coupling (self-test: a clean tree cannot pass vacuously)" do
    @synthetic """
    - Gated, and none of them openable by citing the ladder: rule backtesting
      (level (d)); push delivery to external endpoints (B3.7); scraping
      marketplaces (B3.9).
    - **Permanent non-goals — identity, not backlog**, and no capacity argument
      reopens them: no **order-placing** broker connection, no advice, no
      crypto lending. The system prepares decisions; the operator executes them.
    """

    test "a synthetic amendment reads out item by item" do
      text = normalize(@synthetic)

      assert list_items(text, :non_goal) ==
               ["no order-placing broker connection", "no advice", "no crypto lending"]

      assert list_items(text, :gated) == [
               "rule backtesting (level (d))",
               "push delivery to external endpoints (B3.7)",
               "scraping marketplaces (B3.9)"
             ]
    end

    test "an added sentence item is unregistered and a removed one is stale" do
      text = normalize(@synthetic)

      {unregistered, stale} = compare_items(list_items(text, :non_goal), :non_goal, @registry)

      assert unregistered == ["no crypto lending"]

      assert stale == [
               "no order creation or transmission",
               "no automated trading or payment",
               "no raw news archive",
               "no external LLM calls from the app"
             ]

      {unregistered, _stale} = compare_items(list_items(text, :gated), :gated, @registry)

      assert unregistered == ["scraping marketplaces (B3.9)"]
    end

    test "a reworded lead-in is refused rather than read as an empty list" do
      assert_raise ExUnit.AssertionError, ~r/lead-in/, fn ->
        list_items(normalize("Permanent goals: no advice."), :non_goal)
      end
    end

    test "gate declarations are read from a backstop's comment lines" do
      source = """
      defmodule Portfolixir.Invariants.SyntheticBackstopTest do
        # The gates it backs:
        #   gate:nongoal.advice
        #   gate:gated.b3_9_marketplaces
        @moduledoc false
        def text, do: "gate:not.a.declaration"
      end
      """

      assert declared_gates(source) == ["nongoal.advice", "gated.b3_9_marketplaces"]
    end
  end

  # --- AGENTS.md reading -----------------------------------------------------

  # One line of prose: emphasis markers dropped, every run of whitespace (the
  # Markdown line wraps and list indentation) collapsed to one space.
  defp normalize(text) do
    text
    |> String.replace("*", "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # The items of the non-goals sentence or the gated list, read after the
  # stable lead-in up to the sentence's full stop. A missing lead-in fails
  # loudly: a reworded sentence is an amendment the registry must follow, not
  # an empty list.
  defp list_items(text, kind) do
    {lead_in, separator} =
      case kind do
        :non_goal -> {@non_goals_lead_in, ", "}
        :gated -> {@gated_lead_in, "; "}
      end

    case String.split(text, lead_in, parts: 2) do
      [_before, rest] ->
        rest |> String.split(". ", parts: 2) |> hd() |> String.split(separator)

      [_no_lead_in] ->
        flunk(
          "AGENTS.md no longer carries the #{kind} lead-in #{inspect(lead_in)} — the " <>
            "sentence was amended; amend this registry and its backstops with it (NFR-9 B7)"
        )
    end
  end

  defp markers(%{sentence: {:marker, marker}} = entry),
    do: [marker | Map.get(entry, :markers, [])]

  defp markers(entry), do: Map.get(entry, :markers, [])

  # `{unregistered, stale}`: items the sentence states without an entry, and
  # entries whose item the sentence no longer states.
  defp compare_items(items, kind, registry) do
    registered = for %{sentence: {^kind, item}} <- registry, do: item

    {items -- registered, registered -- items}
  end

  defp assert_same_items(items, kind, registry) do
    registered = for %{sentence: {^kind, item}} <- registry, do: item

    assert registered == Enum.uniq(registered), "a #{kind} item is registered twice"

    {unregistered, stale} = compare_items(items, kind, registry)

    assert unregistered == [],
           "AGENTS.md states #{kind} gates without a registry entry and backstop " <>
             "(NFR-9 B7): #{inspect(unregistered)}"

    assert stale == [],
           "Registry entries whose #{kind} item AGENTS.md no longer states — amend them " <>
             "with their backstops in the same change: #{inspect(stale)}"
  end

  # --- backstops -------------------------------------------------------------

  defp backstop_files do
    "test/invariants/scope_b*_test.exs"
    |> Path.wildcard()
    |> Enum.reject(&(&1 == "test/invariants/scope_b7_gate_registry_test.exs"))
  end

  # The ids of a backstop's `# gate:<id>` comment lines.
  defp declared_gates(source) do
    ~r/^\s*#\s*gate:([a-z0-9_.]+)\s*$/m
    |> Regex.scan(source)
    |> Enum.map(fn [_, id] -> id end)
  end
end
