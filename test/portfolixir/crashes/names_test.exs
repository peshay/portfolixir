defmodule Portfolixir.Crashes.NamesTest do
  # Sprint 29 C3 (FR-54, #1421; ADR-0058 §3): a detected window is named by
  # its key, d:<benchmark>:<start>; the name is stored with that key and
  # journaled, never moves the window's dates, and is never re-attached to
  # another window by a guess. Risk tier: money math. Every name and figure
  # is synthetic.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [create_security!: 1, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Crashes
  alias Portfolixir.Crashes.WindowName
  alias Portfolixir.Derived.BlastRadius
  alias Portfolixir.Journal
  alias Portfolixir.Settings

  defp agent, do: Actor.api_token_rw("mcp")

  defp choose!(security) do
    {:ok, _security} = Settings.set_crash_benchmark(Actor.owner_ui(), security.id)
  end

  # One fall of 33.9 % from 19 February 2020, recovered on 18 August.
  defp spring_index! do
    index = create_security!(name: "Synthetic Broad Index", ticker: "SBI", currency: "USD")

    put_quotes!(index, [
      {~D[2020-02-19], "3386.15"},
      {~D[2020-02-20], "3373.23"},
      {~D[2020-03-23], "2237.40"},
      {~D[2020-08-18], "3389.78"},
      {~D[2020-08-19], "3374.85"}
    ])

    index
  end

  # One fall of 20 % from 3 January 2022, not recovered.
  defp bear_index! do
    index = create_security!(name: "Synthetic Europe Index", ticker: "SEI")

    put_quotes!(index, [
      {~D[2022-01-03], "500"},
      {~D[2022-03-07], "450"},
      {~D[2022-10-12], "400"}
    ])

    index
  end

  defp names(%{detected: detected}), do: Enum.map(detected, &{&1.key, &1.name})

  # User story (ADR-0058 §3):
  # As the operator, or the agent I run,
  # I want to name a detected crash window by its key, and rename or unname
  # it later,
  # so that every agent and the screen call the same crash the same thing.
  #
  # Acceptance criteria:
  # - A name is stored with the key's benchmark and start and read back on
  #   the window it names; the window's dates stay the rule's.
  # - A second name for the same key renames it; unnaming deletes it; each
  #   write is journaled under its actor (create, update, delete).
  test "a detected window is named, renamed and unnamed by its key, journaled under its actor" do
    index = spring_index!()
    choose!(index)
    key = "d:#{index.id}:2020-02-19"

    assert names(Crashes.list_windows()) == [{key, nil}]

    assert {:ok, %WindowName{} = named} =
             Crashes.name_window(agent(), key, %{"name" => "Synthetic Spring Fall"})

    assert {named.benchmark_security_id, named.start, named.name} ==
             {index.id, ~D[2020-02-19], "Synthetic Spring Fall"}

    assert %{detected: [window], unmatched_names: []} = Crashes.list_windows()
    assert {window.key, window.name} == {key, "Synthetic Spring Fall"}

    assert {window.start, window.trough, window.kind} ==
             {~D[2020-02-19], ~D[2020-03-23], "detected"}

    assert {:ok, renamed} = Crashes.name_window(agent(), key, %{name: "Synthetic Spring Crash"})
    assert renamed.id == named.id
    assert names(Crashes.list_windows()) == [{key, "Synthetic Spring Crash"}]

    assert {:ok, _gone} = Crashes.unname_window(agent(), key)
    assert names(Crashes.list_windows()) == [{key, nil}]

    assert [deleted, updated, created] = Journal.list_entries(resource_type: "crash_window_name")

    assert {created.operation, updated.operation, deleted.operation} ==
             {:create, :update, :delete}

    for entry <- [created, updated, deleted],
        do: assert({entry.actor_type, entry.actor_label} == {:api_token_rw, "mcp"})

    assert created.after["name"] == "Synthetic Spring Fall"
    assert created.after["start"] == "2020-02-19"
    assert created.after["benchmark_security_id"] == index.id
    assert updated.before["name"] == "Synthetic Spring Fall"
    assert updated.after["name"] == "Synthetic Spring Crash"
    assert deleted.before["name"] == "Synthetic Spring Crash"
    assert deleted.after == nil
  end

  # Acceptance criteria (ADR-0058 §2, §3):
  # - A key that names no detected window of the current crash benchmark is
  #   refused as :not_found and writes nothing: another start, another
  #   benchmark, a key not spelled as the read spells it, no benchmark
  #   chosen. Unnaming a key that carries no name is :not_found too.
  test "a key that names no detected window is refused and nothing is written" do
    index = spring_index!()
    other = bear_index!()
    attrs = %{"name" => "Synthetic Fall"}

    assert Crashes.name_window(agent(), "d:#{index.id}:2020-02-19", attrs) ==
             {:error, :not_found}

    choose!(index)

    for key <- [
          "d:#{index.id}:2020-02-20",
          "d:#{other.id}:2022-01-03",
          "d:0#{index.id}:2020-02-19",
          "d:#{index.id}:2020-2-19",
          "d:#{index.id}",
          "m:1",
          "x"
        ] do
      assert Crashes.name_window(agent(), key, attrs) == {:error, :not_found}, key
    end

    assert Crashes.unname_window(agent(), "d:#{index.id}:2020-02-19") == {:error, :not_found}
    assert Journal.list_entries(resource_type: "crash_window_name") == []
    assert names(Crashes.list_windows()) == [{"d:#{index.id}:2020-02-19", nil}]
  end

  # Acceptance criteria (ADR-0058 §4's name rule, applied to a name;
  # ADR-0054 §4; ADR-0058 §9):
  # - A name is required, at most 80 characters, one line, without the
  #   characters an operator cannot see; 80 is accepted.
  # - A field the write does not take is refused naming it, and nothing is
  #   written.
  test "a name is one visible line of at most 80 characters, and an unknown field is refused" do
    index = spring_index!()
    choose!(index)
    key = "d:#{index.id}:2020-02-19"

    assert {:error, blank} = Crashes.name_window(agent(), key, %{"name" => "  "})
    assert errors_on(blank) == %{name: ["can't be blank"]}

    assert {:error, missing} = Crashes.name_window(agent(), key, %{})
    assert errors_on(missing) == %{name: ["can't be blank"]}

    assert {:error, long} =
             Crashes.name_window(agent(), key, %{"name" => String.duplicate("a", 81)})

    assert errors_on(long) == %{name: ["should be at most 80 character(s)"]}

    assert {:error, hidden} =
             Crashes.name_window(agent(), key, %{"name" => "Fall" <> <<0x200B::utf8>> <> "A"})

    assert [message] = errors_on(hidden).name
    assert message =~ "U+200B"

    assert {:error, two_lines} = Crashes.name_window(agent(), key, %{"name" => "Fall\nA"})
    assert Map.has_key?(errors_on(two_lines), :name)

    assert Crashes.name_window(agent(), key, %{"name" => "Fall", "start" => "2020-02-20"}) ==
             {:error,
              {:unknown_fields, %{"start" => ["is unknown: a window's name takes only name"]}}}

    assert Journal.list_entries(resource_type: "crash_window_name") == []

    assert {:ok, %{name: eighty}} =
             Crashes.name_window(agent(), key, %{"name" => String.duplicate("ä", 80)})

    assert String.length(eighty) == 80
  end

  # User story (ADR-0058 §3, §7.4):
  # As the operator whose benchmark's closes were corrected,
  # I want a name whose window moved to be shown as a name without a window,
  # so that a name never slides onto another crash by a guess.
  #
  # Acceptance criteria:
  # - When the closes give the window another start, the new window reads
  #   without a name and the name is listed under unmatched_names with its
  #   stored key, benchmark and start, for the current benchmark.
  # - The name can be deleted by its stored key.
  test "a name whose key loses its window is listed unmatched, never re-attached" do
    index = spring_index!()
    choose!(index)
    old_key = "d:#{index.id}:2020-02-19"
    {:ok, _named} = Crashes.name_window(agent(), old_key, %{"name" => "Synthetic Spring Fall"})

    # A later, higher close: the peak moves to 21 February.
    put_quotes!(index, [{~D[2020-02-21], "3390.00"}])
    new_key = "d:#{index.id}:2020-02-21"

    assert %{detected: [window], unmatched_names: [unmatched]} = Crashes.list_windows()
    assert {window.key, window.name} == {new_key, nil}

    assert unmatched == %{
             key: old_key,
             name: "Synthetic Spring Fall",
             benchmark_security_id: index.id,
             benchmark_name: "Synthetic Broad Index",
             start: ~D[2020-02-19],
             for_current_benchmark: true
           }

    assert Crashes.name_window(agent(), old_key, %{"name" => "Renamed"}) == {:error, :not_found}

    assert {:ok, _gone} = Crashes.unname_window(agent(), old_key)
    assert %{unmatched_names: [], detected: [%{name: nil}]} = Crashes.list_windows()
  end

  # User story (ADR-0058 §1, §3, §7.6):
  # As the operator switching the crash benchmark,
  # I want the names given for the former one hidden, not lost,
  # so that switching back restores them.
  #
  # Acceptance criteria:
  # - After a switch, the former benchmark's names are listed under
  #   unmatched_names with that benchmark named and
  #   for_current_benchmark: false; the new benchmark's windows read without
  #   them.
  # - With no crash benchmark, every name is unmatched.
  # - Switching back puts each name on its window again.
  test "a benchmark switch hides the names under unmatched_names and switching back restores them" do
    spring = spring_index!()
    bear = bear_index!()
    choose!(spring)
    spring_key = "d:#{spring.id}:2020-02-19"
    {:ok, _named} = Crashes.name_window(agent(), spring_key, %{"name" => "Synthetic Spring Fall"})

    choose!(bear)
    bear_key = "d:#{bear.id}:2022-01-03"

    assert %{detected: [bear_window], unmatched_names: [hidden]} = Crashes.list_windows()
    assert {bear_window.key, bear_window.name} == {bear_key, nil}

    assert hidden == %{
             key: spring_key,
             name: "Synthetic Spring Fall",
             benchmark_security_id: spring.id,
             benchmark_name: "Synthetic Broad Index",
             start: ~D[2020-02-19],
             for_current_benchmark: false
           }

    {:ok, _named} = Crashes.name_window(agent(), bear_key, %{"name" => "Synthetic Bear Market"})

    {:ok, nil} = Settings.set_crash_benchmark(Actor.owner_ui(), nil)

    assert %{detected: [], reason: "no_crash_benchmark", unmatched_names: unmatched} =
             Crashes.list_windows()

    assert Enum.map(unmatched, &{&1.key, &1.for_current_benchmark}) ==
             [{spring_key, false}, {bear_key, false}]

    choose!(spring)

    assert %{detected: [window], unmatched_names: [%{key: ^bear_key}]} = Crashes.list_windows()
    assert {window.key, window.name} == {spring_key, "Synthetic Spring Fall"}
  end

  # Acceptance criteria (ADR-0039; ADR-0032 §3.3's allowlist):
  # - A name write resolves to no portfolio and no security: a name is no
  #   figure, and the rankings read it at request time.
  test "a name write moves no derived figure" do
    assert BlastRadius.for_write("crash_window_name", %WindowName{}) == []
    assert BlastRadius.securities_for_write("crash_window_name", %WindowName{}) == []
  end
end
