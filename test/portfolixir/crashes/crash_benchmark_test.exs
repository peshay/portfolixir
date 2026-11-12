defmodule Portfolixir.Crashes.CrashBenchmarkTest do
  # Sprint 29 C1 (FR-54, #1421; ADR-0058 §1): the crash benchmark, one
  # instance setting the rule reads. Every name and figure is synthetic.
  # group: :crash_benchmark -- the async modules that choose the crash
  # benchmark never run at the same time (the closing act of Sprint 29). The
  # choice is one settings row for the instance (settings_key_index), taken
  # under an advisory lock on its key, and a sandboxed test never commits: a
  # module choosing beside another one waited on the other's lock and row
  # until that test ended, into the 15 s query timeout under load. The key
  # is the setting's, so no fixture of a test's own avoids it.
  use Portfolixir.DataCase, async: true, group: :crash_benchmark

  import Portfolixir.WorldFixtures, only: [create_security!: 1, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Crashes
  alias Portfolixir.Journal
  alias Portfolixir.Lifecycle
  alias Portfolixir.Settings

  defp bare!(name) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{name: name, currency_code: "EUR"})

    security
  end

  defp merge!(source, target) do
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    {:ok, _record, :applied} =
      Lifecycle.merge_security(Actor.owner_ui(), source.id, target.id, %{
        plan_digest: preview.plan_digest
      })
  end

  defp agent, do: Actor.api_token_rw("mcp")

  # User story (ADR-0058 §1):
  # As the operator, or the agent I run,
  # I want to name one security whose closes the crash rule reads,
  # so that every agent and the screen read the same crash windows.
  #
  # Acceptance criteria:
  # - Unset, the setting reads nil.
  # - Any security with a stored quote may be named, flagged or not (Lane
  #   B's rule, `BenchmarkSecurity.resolve/1`); it reads back as its id.
  # - The write is journaled under its setter's actor as a "setting" upsert,
  #   its after-image carrying the id; clearing it journals a delete.
  test "any quoted security is the crash benchmark, set and cleared under its actor" do
    assert Settings.crash_benchmark_security_id() == nil

    fund = create_security!(name: "Synthetic Watched Fund", ticker: "SWF")
    put_quote!(fund, ~D[2025-03-03], "10")

    assert {:ok, %{id: id}} = Settings.set_crash_benchmark(agent(), fund.id)
    assert id == fund.id
    assert Settings.crash_benchmark_security_id() == fund.id

    assert [set] = Journal.list_entries(resource_type: "setting")
    assert {set.actor_type, set.actor_label} == {:api_token_rw, "mcp"}
    assert set.operation == :upsert
    assert set.after["key"] == "crash_benchmark_security_id"
    assert set.after["value"] == to_string(fund.id)

    assert {:ok, nil} = Settings.set_crash_benchmark(agent(), nil)
    assert Settings.crash_benchmark_security_id() == nil

    assert [cleared, ^set] = Journal.list_entries(resource_type: "setting")
    assert cleared.operation == :delete
    assert {cleared.actor_type, cleared.actor_label} == {:api_token_rw, "mcp"}
  end

  # Acceptance criteria (ADR-0058 §1; ADR-0046's amendment, #959):
  # - A security without a stored quote is refused as :no_quote, an unknown
  #   id as :not_found, a merged-away one naming its survivor; none of them
  #   writes the setting or the journal.
  # - A refused write leaves a setting made before it in place.
  test "an unquoted, unknown or merged-away security is refused and nothing is written" do
    unquoted = create_security!(name: "Synthetic Unquoted Fund", ticker: "SUF")

    target = bare!("Synthetic Harbour Fund")
    source = bare!("Synthetic Harbour Fund")
    put_quote!(target, ~D[2025-03-03], "20")
    merge!(source, target)

    before = Journal.list_entries(resource_type: "setting")

    assert Settings.set_crash_benchmark(agent(), unquoted.id) == {:error, :no_quote}
    assert Settings.set_crash_benchmark(agent(), 999_999_999) == {:error, :not_found}

    assert Settings.set_crash_benchmark(agent(), source.id) ==
             {:error, {:merged_into, target.id}}

    assert Settings.crash_benchmark_security_id() == nil
    assert Journal.list_entries(resource_type: "setting") == before

    {:ok, _target} = Settings.set_crash_benchmark(agent(), target.id)
    assert Settings.set_crash_benchmark(agent(), unquoted.id) == {:error, :no_quote}
    assert Settings.crash_benchmark_security_id() == target.id
  end

  # User story (ADR-0058 §1):
  # As the agent reading the crash windows,
  # I want an instance without a crash benchmark to say so,
  # so that an empty list is never read as "no crash happened".
  #
  # Acceptance criteria:
  # - Unset, the detected windows are [] with reason "no_crash_benchmark"
  #   and no benchmark.
  test "unset, the read detects nothing and says why" do
    assert %{benchmark: nil, detected: [], reason: "no_crash_benchmark"} = Crashes.detected()
  end

  # Acceptance criteria (ADR-0058 §1, read with Lane B's rule):
  # - A crash benchmark merged away after it was chosen detects nothing and
  #   says so with its own reason, never an empty list that reads as "no
  #   crash" and never the survivor by a guess; the stored id stays until
  #   the operator chooses again.
  test "a chosen benchmark merged away since detects nothing and says why" do
    source = bare!("Synthetic Harbour Fund")
    target = bare!("Synthetic Harbour Fund")
    put_quote!(source, ~D[2025-03-03], "20")
    {:ok, _source} = Settings.set_crash_benchmark(agent(), source.id)

    merge!(source, target)

    assert %{benchmark: nil, detected: [], reason: "crash_benchmark_unavailable"} =
             Crashes.detected()

    assert Settings.crash_benchmark_security_id() == source.id
  end
end
