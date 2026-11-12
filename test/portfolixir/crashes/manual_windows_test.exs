defmodule Portfolixir.Crashes.ManualWindowsTest do
  # Sprint 29 C3 (FR-54, #1421; ADR-0058 §4 and its amendment's F1): a
  # manual window is stored with the dates a person chose, marked manual on
  # every read, may overlap any other window, and is created, edited and
  # deleted under its actor, journaled. A name without a window becomes one
  # only with a trough the caller gives. Risk tier: money math. Every name
  # and figure is synthetic.
  # group: :crash_benchmark -- the async modules that choose the crash
  # benchmark never run at the same time (the closing act of Sprint 29). The
  # choice is one settings row for the instance (settings_key_index), taken
  # under an advisory lock on its key, and a sandboxed test never commits: a
  # module choosing beside another one waited on the other's lock and row
  # until that test ended, into the 15 s query timeout under load. The key
  # is the setting's, so no fixture of a test's own avoids it.
  use Portfolixir.DataCase, async: true, group: :crash_benchmark

  import Portfolixir.WorldFixtures, only: [create_security!: 1, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Crashes
  alias Portfolixir.Crashes.ManualWindow
  alias Portfolixir.Derived.BlastRadius
  alias Portfolixir.Journal
  alias Portfolixir.Settings

  defp agent, do: Actor.api_token_rw("mcp")

  defp choose!(security) do
    {:ok, _security} = Settings.set_crash_benchmark(Actor.owner_ui(), security.id)
  end

  # One fall of 25 % from 3 January 2022, recovered on 18 January 2024.
  defp bear_index! do
    index = create_security!(name: "Synthetic Broad Index", ticker: "SBI")

    put_quotes!(index, [
      {~D[2022-01-03], "400"},
      {~D[2022-03-07], "340"},
      {~D[2022-10-12], "300"},
      {~D[2024-01-18], "401"}
    ])

    index
  end

  defp war,
    do: %{"name" => "Synthetic War Outbreak", "start" => "2022-02-16", "trough" => "2022-03-07"}

  defp manual_shape(window) do
    Map.take(window, [:key, :kind, :name, :start, :trough, :author, :actor])
  end

  defp entries, do: Journal.list_entries(resource_type: "crash_manual_window")

  # User story (ADR-0058 §4):
  # As the operator, or the agent I run,
  # I want to record a crash the rule folds into a longer one as a window
  # of my own,
  # so that the outbreak of a war inside a bear market can be ranked too,
  # marked as a span a person chose.
  #
  # Acceptance criteria:
  # - A manual window stores its name, start and trough, and the creating
  #   token (author and actor), and is journaled as a create under it.
  # - The read lists it under manual with key m:<id> and kind "manual",
  #   beside the detected windows, even with no crash benchmark chosen.
  # - It may overlap a detected window and another manual window.
  test "a manual window is stored, marked manual on the read, and may overlap any window" do
    assert {:ok, %ManualWindow{} = window} = Crashes.create_manual_window(agent(), war())
    key = "m:#{window.id}"

    assert %{reason: "no_crash_benchmark", detected: [], manual: [listed]} =
             Crashes.list_windows()

    assert manual_shape(listed) == %{
             key: key,
             kind: "manual",
             name: "Synthetic War Outbreak",
             start: ~D[2022-02-16],
             trough: ~D[2022-03-07],
             author: :agent,
             actor: "mcp"
           }

    assert [created] = entries()

    assert {created.operation, created.actor_type, created.actor_label} ==
             {:create, :api_token_rw, "mcp"}

    assert created.after["start"] == "2022-02-16"
    assert created.after["trough"] == "2022-03-07"

    index = bear_index!()
    choose!(index)

    # Inside the detected window, and overlapping the first manual one.
    assert {:ok, second} =
             Crashes.create_manual_window(Actor.owner_ui(), %{
               name: "Synthetic Spring Leg",
               start: ~D[2022-03-01],
               trough: ~D[2022-10-12]
             })

    assert %{detected: [detected], manual: manual} = Crashes.list_windows()
    assert {detected.key, detected.kind} == {"d:#{index.id}:2022-01-03", "detected"}

    assert Enum.map(manual, &{&1.key, &1.kind, &1.author, &1.actor}) == [
             {key, "manual", :agent, "mcp"},
             {"m:#{second.id}", "manual", :operator, nil}
           ]
  end

  # Acceptance criteria (ADR-0058 §4; ADR-0054 §4; ADR-0058 §9):
  # - start and trough are required ISO dates; the trough lies after the
  #   start (the same day is refused), and neither lies in the future
  #   (today is allowed).
  # - The name follows the name rule: required, at most 80 characters.
  # - A field the write does not take is refused naming it, the creating
  #   token's fields included.
  # - A refusal writes nothing and journals nothing.
  test "start before trough, neither in the future, a name of 80, no unknown field" do
    today = Clock.today()
    tomorrow = Date.add(today, 1)

    refused = fn attrs ->
      assert {:error, %Ecto.Changeset{} = changeset} =
               Crashes.create_manual_window(agent(), Map.merge(war(), attrs))

      errors_on(changeset)
    end

    assert refused.(%{"trough" => "2022-02-16"}) == %{trough: ["must be after start"]}
    assert refused.(%{"trough" => "2022-02-15"}) == %{trough: ["must be after start"]}

    assert refused.(%{"trough" => Date.to_iso8601(tomorrow)}) ==
             %{trough: ["must not be in the future"]}

    assert refused.(%{
             "start" => Date.to_iso8601(tomorrow),
             "trough" => Date.to_iso8601(Date.add(today, 2))
           }) == %{
             start: ["must not be in the future"],
             trough: ["must not be in the future"]
           }

    assert refused.(%{"start" => nil, "trough" => nil}) ==
             %{start: ["can't be blank"], trough: ["can't be blank"]}

    assert refused.(%{"start" => "16.02.2022"}) == %{start: ["is invalid"]}
    assert refused.(%{"name" => ""}) == %{name: ["can't be blank"]}

    assert refused.(%{"name" => String.duplicate("x", 81)}) ==
             %{name: ["should be at most 80 character(s)"]}

    assert Crashes.create_manual_window(
             agent(),
             Map.merge(war(), %{"kind" => "detected", "actor" => "x"})
           ) ==
             {:error,
              {:unknown_fields,
               %{
                 "actor" => ["is unknown: a manual window takes only name, start, trough"],
                 "kind" => ["is unknown: a manual window takes only name, start, trough"]
               }}}

    assert entries() == []
    assert %{manual: []} = Crashes.list_windows()

    assert {:ok, %{trough: ^today}} =
             Crashes.create_manual_window(agent(), %{
               "name" => String.duplicate("x", 80),
               "start" => Date.add(today, -1),
               "trough" => today
             })
  end

  # User story (ADR-0058 §4):
  # As the operator who drew a window,
  # I want to rename it, move its dates or delete it, journaled,
  # so that a mistake in a span a person chose is corrected on the record.
  #
  # Acceptance criteria:
  # - An edit by its key takes any of name, start and trough under the same
  #   rules on the edited window; the creating token stays the creator's;
  #   journaled as an update with its before-image.
  # - A delete by its key is journaled with its before-image.
  # - A key that names no manual window is :not_found; an edit that breaks
  #   a rule, or names a field the write does not take, writes nothing.
  test "a manual window is renamed, moved and deleted by its key, journaled" do
    {:ok, window} = Crashes.create_manual_window(agent(), war())
    key = "m:#{window.id}"

    assert {:ok, renamed} =
             Crashes.update_manual_window(Actor.owner_ui(), key, %{"name" => "Synthetic War"})

    assert {renamed.name, renamed.start, renamed.trough} ==
             {"Synthetic War", ~D[2022-02-16], ~D[2022-03-07]}

    assert {renamed.author, renamed.actor} == {:agent, "mcp"}

    assert {:ok, moved} = Crashes.update_manual_window(agent(), key, %{"trough" => "2022-03-08"})
    assert moved.trough == ~D[2022-03-08]

    assert {:error, changeset} =
             Crashes.update_manual_window(agent(), key, %{"start" => "2022-03-08"})

    assert errors_on(changeset) == %{trough: ["must be after start"]}

    assert Crashes.update_manual_window(agent(), key, %{"author" => "operator"}) ==
             {:error,
              {:unknown_fields,
               %{"author" => ["is unknown: a manual window takes only name, start, trough"]}}}

    for missing <- ["m:#{window.id + 1}", "m:0#{window.id}", "m:x", "d:1:2022-02-16"] do
      assert Crashes.update_manual_window(agent(), missing, %{"name" => "X"}) ==
               {:error, :not_found},
             missing

      assert Crashes.delete_manual_window(agent(), missing) == {:error, :not_found}, missing
    end

    assert %{manual: [listed]} = Crashes.list_windows()
    assert {listed.name, listed.trough} == {"Synthetic War", ~D[2022-03-08]}

    assert {:ok, _deleted} = Crashes.delete_manual_window(agent(), key)
    assert %{manual: []} = Crashes.list_windows()
    assert Crashes.delete_manual_window(agent(), key) == {:error, :not_found}

    assert [deleted, second_edit, first_edit, _created] = entries()

    assert {first_edit.operation, first_edit.actor_type} == {:update, :owner_ui}
    assert first_edit.before["name"] == "Synthetic War Outbreak"
    assert first_edit.after["name"] == "Synthetic War"
    assert second_edit.before["trough"] == "2022-03-07"
    assert second_edit.after["trough"] == "2022-03-08"
    assert {deleted.operation, deleted.actor_label, deleted.after} == {:delete, "mcp", nil}
    assert deleted.before["name"] == "Synthetic War"
  end

  # User story (ADR-0058 §3; amendment of 2026-11-12, F1):
  # As the operator whose name lost its window,
  # I want to keep the crash as a manual window from the name's start and a
  # trough I give,
  # so that nothing is guessed from closes that can no longer be trusted.
  #
  # Acceptance criteria:
  # - A name without a window becomes a manual window with the name's
  #   stored start, the caller's trough and the stored name (or a name the
  #   caller gives); the name is deleted in the same transaction; both
  #   writes are journaled under the actor.
  # - Without a trough it is refused and the name stays; a start given by
  #   the caller is refused as a field the write does not take; the trough
  #   follows §4's rules.
  # - A name that still has its window, or a key that carries no name, is
  #   refused and nothing is written.
  test "a name without a window becomes a manual window only with the trough the caller gives" do
    index = bear_index!()
    choose!(index)
    key = "d:#{index.id}:2022-01-03"
    {:ok, _named} = Crashes.name_window(agent(), key, %{"name" => "Synthetic Bear Market"})

    assert Crashes.manual_window_from_name(agent(), key, %{"trough" => "2022-10-12"}) ==
             {:error, :name_has_window}

    # A later, higher close moves the window's start: the name loses it.
    put_quotes!(index, [{~D[2022-01-04], "410"}])
    assert %{unmatched_names: [%{key: ^key}]} = Crashes.list_windows()

    assert {:error, missing} = Crashes.manual_window_from_name(agent(), key, %{})
    assert errors_on(missing) == %{trough: ["can't be blank"]}

    assert {:error, same_day} =
             Crashes.manual_window_from_name(agent(), key, %{"trough" => "2022-01-03"})

    assert errors_on(same_day) == %{trough: ["must be after start"]}

    assert Crashes.manual_window_from_name(agent(), key, %{
             "start" => "2022-01-04",
             "trough" => "2022-10-12"
           }) ==
             {:error,
              {:unknown_fields,
               %{"start" => ["is unknown: a window made from a name takes only name, trough"]}}}

    assert Crashes.manual_window_from_name(agent(), "d:#{index.id}:2022-01-05", %{
             "trough" => "2022-10-12"
           }) == {:error, :not_found}

    assert entries() == []
    assert %{manual: [], unmatched_names: [_still]} = Crashes.list_windows()

    assert {:ok, %ManualWindow{} = made} =
             Crashes.manual_window_from_name(agent(), key, %{"trough" => "2022-10-12"})

    assert {made.name, made.start, made.trough, made.author, made.actor} ==
             {"Synthetic Bear Market", ~D[2022-01-03], ~D[2022-10-12], :agent, "mcp"}

    assert %{manual: [listed], unmatched_names: []} = Crashes.list_windows()
    assert {listed.key, listed.kind} == {"m:#{made.id}", "manual"}

    assert [created] = entries()
    assert {created.operation, created.actor_label} == {:create, "mcp"}

    assert [unnamed | _named] = Journal.list_entries(resource_type: "crash_window_name")
    assert {unnamed.operation, unnamed.actor_label} == {:delete, "mcp"}
    assert unnamed.before["name"] == "Synthetic Bear Market"
  end

  # Acceptance criteria (ADR-0058 F1): the caller may name the new window.
  test "a window made from a name may take a name the caller gives" do
    index = bear_index!()
    choose!(index)
    key = "d:#{index.id}:2022-01-03"
    {:ok, _named} = Crashes.name_window(agent(), key, %{"name" => "Synthetic Bear Market"})
    {:ok, nil} = Settings.set_crash_benchmark(Actor.owner_ui(), nil)

    assert {:ok, made} =
             Crashes.manual_window_from_name(Actor.owner_ui(), key, %{
               "name" => "Synthetic Bear Leg",
               "trough" => "2022-03-07"
             })

    assert {made.name, made.start, made.trough, made.author} ==
             {"Synthetic Bear Leg", ~D[2022-01-03], ~D[2022-03-07], :operator}
  end

  # Acceptance criteria (ADR-0058 §9): one put and one delete by key, as the
  # API's PUT and DELETE /api/v1/crashes/:key take them.
  # - put_window/3 names a detected window for a d: key and edits a manual
  #   one for an m: key; delete_window/2 unnames or deletes.
  test "a key's kind chooses the write" do
    index = bear_index!()
    choose!(index)
    detected_key = "d:#{index.id}:2022-01-03"
    {:ok, manual} = Crashes.create_manual_window(agent(), war())
    manual_key = "m:#{manual.id}"

    assert {:ok, %{name: "Synthetic Bear"}} =
             Crashes.put_window(agent(), detected_key, %{"name" => "Synthetic Bear"})

    assert {:ok, %ManualWindow{name: "Synthetic Leg"}} =
             Crashes.put_window(agent(), manual_key, %{"name" => "Synthetic Leg"})

    assert Crashes.put_window(agent(), "x:1", %{"name" => "X"}) == {:error, :not_found}

    assert {:ok, _unnamed} = Crashes.delete_window(agent(), detected_key)
    assert {:ok, _deleted} = Crashes.delete_window(agent(), manual_key)
    assert Crashes.delete_window(agent(), "x:1") == {:error, :not_found}

    assert %{detected: [%{name: nil}], manual: []} = Crashes.list_windows()
  end

  # Acceptance criteria (ADR-0039; ADR-0032 §3.3's allowlist):
  # - A manual window's write resolves to no portfolio and no security: its
  #   rankings are read at request time.
  test "a manual window's write moves no derived figure" do
    assert BlastRadius.for_write("crash_manual_window", %ManualWindow{}) == []
    assert BlastRadius.securities_for_write("crash_manual_window", %ManualWindow{}) == []
  end
end
