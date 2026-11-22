defmodule Portfolixir.Dashboards.WritesTest do
  # Sprint 31 D1 (FR-60, ADR-0062 §2, §3): every stored write of a
  # dashboard — create, a template's copy, replace, rename, reposition,
  # delete — is journaled under its actor, one entry per write; a replace
  # carries the lock_version it read and a stale one is refused with the
  # stored dashboard; at most 50 dashboards; a delete deletes nothing else.
  #
  # group: :dashboards -- a create takes the transaction advisory lock that
  # counts the dashboards (`Portfolixir.LockTable` row 30), and a sandboxed
  # test never commits: two modules creating at once would wait on each
  # other's lock until the test ended. Every module that creates a
  # dashboard joins this group.
  use Portfolixir.DataCase, async: true, group: :dashboards

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Derived.BlastRadius
  alias Portfolixir.Journal
  alias Portfolixir.Repo

  defp agent, do: Actor.api_token_rw("mcp")

  defp entries, do: Journal.list_entries(resource_type: "dashboard", order: :asc)

  defp due(col, row), do: %{"kind" => "due", "size" => "S", "col" => col, "row" => row}

  defp create!(name, layout \\ []) do
    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => name, "layout" => layout})

    dashboard
  end

  # User story:
  # As the operator, or the agent I run,
  # I want a dashboard I create stored with its layout and journaled under
  # me,
  # so that the menu shows it and the journal says who made it.
  #
  # Acceptance criteria:
  # - A create stores the name (trimmed) and the normalized layout, at the
  #   end of the menu (position one past the last), lock_version 1.
  # - One journal entry, a create under the actor, its after the row.
  # - The list reads by position, and the entries are the stored ones,
  #   marked, with no template once one is stored.
  # - A key the create does not take is refused, and nothing is written.
  test "a create is stored at the end of the menu and journaled under its actor" do
    assert {:ok, %Dashboard{} = first} =
             Dashboards.create_dashboard(agent(), %{name: " Kurzfristig ", layout: [due(1, 1)]})

    assert first.name == "Kurzfristig"
    assert first.position == 1
    assert first.lock_version == 1
    assert first.layout == [Map.put(due(1, 1), "settings", %{})]
    assert Dashboards.get_dashboard(first.id).layout == first.layout

    assert [entry] = entries()
    assert entry.operation == :create
    assert entry.actor_type == :api_token_rw
    assert entry.actor_label == "mcp"
    assert entry.resource_id == to_string(first.id)
    assert entry.after["name"] == "Kurzfristig"
    assert entry.after["layout"] == [Map.put(due(1, 1), "settings", %{})]

    second = create!("Langfristig")
    assert second.position == 2

    assert Enum.map(Dashboards.list_dashboards(), & &1.id) == [first.id, second.id]

    assert [
             %{type: :dashboard, dashboard: %{id: id1}},
             %{type: :dashboard, dashboard: %{id: id2}}
           ] =
             Dashboards.entries()

    assert {id1, id2} == {first.id, second.id}

    assert {:error, {:unknown_fields, %{"position" => [_]}}} =
             Dashboards.create_dashboard(agent(), %{"name" => "X", "position" => 1})

    assert {:error, {:unknown_fields, %{"lock_version" => [_]}}} =
             Dashboards.create_dashboard(agent(), %{"name" => "X", "lock_version" => 9})

    assert length(entries()) == 2
  end

  test "a create refused by its name or its layout writes nothing" do
    assert {:error, %Ecto.Changeset{} = changeset} =
             Dashboards.create_dashboard(agent(), %{"name" => String.duplicate("x", 61)})

    assert Keyword.has_key?(changeset.errors, :name)

    assert {:error, %Ecto.Changeset{errors: [layout: {_message, meta}]}} =
             Dashboards.create_dashboard(agent(), %{
               "name" => "Mine",
               "layout" => [due(1, 1), %{"kind" => "nope", "size" => "S", "col" => 4, "row" => 1}]
             })

    assert meta[:index] == 1
    assert meta[:reason] == :unknown_kind

    assert Dashboards.list_dashboards() == []
    assert entries() == []
  end

  # User story:
  # As the operator,
  # I want a limit of 50 dashboards,
  # so that a runaway agent cannot fill the menu without end.
  #
  # Acceptance criteria:
  # - The 50th create is stored; the 51st is refused and writes nothing,
  #   copies of a template included.
  test "a 51st dashboard is refused" do
    for n <- 1..50, do: create!("Synthetic #{n}")

    assert {:error, :too_many_dashboards} =
             Dashboards.create_dashboard(agent(), %{"name" => "One too many"})

    assert {:error, :too_many_dashboards} =
             Dashboards.copy_template(agent(), "overview", %{"name" => "Mein Überblick"})

    assert length(Dashboards.list_dashboards()) == 50
    assert length(entries()) == 50
  end

  # User story:
  # As the operator on a fresh instance,
  # I want „Anpassen“ to copy the template „Überblick“ into a dashboard of
  # my own,
  # so that I can change it while the template stays as shipped.
  #
  # Acceptance criteria:
  # - The copy stores the template's layout under the name given, or the
  #   template's title when none is given, journaled as a create.
  # - An unknown template key is :not_found; the template is unchanged.
  test "a template's copy is a stored dashboard of the template's layout" do
    {:ok, overview} = Templates.fetch("overview")

    assert {:ok, mine} =
             Dashboards.copy_template(Actor.owner_ui(), "overview", %{"name" => "Mein Überblick"})

    assert mine.name == "Mein Überblick"
    assert mine.layout == overview.layout

    assert {:ok, unnamed} = Dashboards.copy_template(Actor.owner_ui(), "overview", %{})
    assert unnamed.name == "Overview"

    assert [%{operation: :create}, %{operation: :create}] = entries()

    assert Dashboards.copy_template(Actor.owner_ui(), "performance", %{}) == {:error, :not_found}
    assert Dashboards.copy_template(Actor.owner_ui(), :overview, %{}) == {:error, :not_found}

    assert {:error, {:unknown_fields, %{"layout" => [_]}}} =
             Dashboards.copy_template(Actor.owner_ui(), "overview", %{"layout" => []})

    assert Templates.fetch("overview") == {:ok, overview}
  end

  # User story:
  # As the operator editing a dashboard while my agent edits it too,
  # I want a save built on an older read refused with what is stored,
  # so that neither my edit nor the agent's is lost unseen (ADR-0062 §2).
  #
  # Acceptance criteria:
  # - A replace with the lock_version read stores the name and layout,
  #   raises lock_version by one and journals one update with its before.
  # - A second replace carrying the same lock_version is {:error, :stale,
  #   stored}: the stored dashboard as the first left it; nothing is
  #   written and nothing journaled.
  # - A replace without lock_version, or with a key it does not take, is
  #   refused; one of an unknown id is :not_found.
  test "two replaces on one lock_version: the first wins, the second is stale" do
    dashboard = create!("Mine", [due(1, 1)])

    assert {:ok, replaced} =
             Dashboards.replace_dashboard(Actor.owner_ui(), dashboard.id, %{
               "name" => "Mine, moved",
               "layout" => [due(4, 2)],
               "lock_version" => 1
             })

    assert replaced.lock_version == 2
    assert replaced.layout == [Map.put(due(4, 2), "settings", %{})]

    assert {:error, :stale, %Dashboard{} = stored} =
             Dashboards.replace_dashboard(agent(), dashboard.id, %{
               "name" => "The agent's",
               "layout" => [due(7, 3)],
               "lock_version" => 1
             })

    assert stored.id == dashboard.id
    assert stored.lock_version == 2
    assert stored.name == "Mine, moved"
    assert stored.layout == replaced.layout
    assert Dashboards.get_dashboard(dashboard.id).name == "Mine, moved"

    assert [%{operation: :create}, update] = entries()
    assert update.operation == :update
    assert update.actor_type == :owner_ui
    assert update.before["name"] == "Mine"
    assert update.before["lock_version"] == 1
    assert update.after["name"] == "Mine, moved"
    assert update.after["lock_version"] == 2

    assert {:error, {:missing_fields, %{"lock_version" => [_]}}} =
             Dashboards.replace_dashboard(agent(), dashboard.id, %{"name" => "X", "layout" => []})

    assert {:error, %Ecto.Changeset{errors: [lock_version: _]}} =
             Dashboards.replace_dashboard(agent(), dashboard.id, %{
               "name" => "X",
               "layout" => [],
               "lock_version" => "2"
             })

    assert {:error, {:missing_fields, %{"layout" => [_]}}} =
             Dashboards.replace_dashboard(agent(), dashboard.id, %{
               "name" => "X",
               "lock_version" => 2
             })

    assert {:error, {:unknown_fields, %{"position" => [_]}}} =
             Dashboards.replace_dashboard(agent(), dashboard.id, %{
               "name" => "X",
               "layout" => [],
               "lock_version" => 2,
               "position" => 4
             })

    assert Dashboards.replace_dashboard(agent(), dashboard.id + 1_000, %{
             "name" => "X",
             "layout" => [],
             "lock_version" => 1
           }) == {:error, :not_found}

    assert length(entries()) == 2
  end

  test "a replace refused by its layout writes nothing; an unchanged one journals nothing" do
    dashboard = create!("Mine", [due(1, 1)])

    assert {:error, %Ecto.Changeset{errors: [layout: {"overlaps another widget", meta}]}} =
             Dashboards.replace_dashboard(agent(), dashboard.id, %{
               "name" => "Mine",
               "layout" => [due(1, 1), due(2, 1)],
               "lock_version" => 1
             })

    assert meta[:index] == 1
    assert meta[:other] == 0

    assert {:ok, same} =
             Dashboards.replace_dashboard(agent(), dashboard.id, %{
               "name" => "Mine",
               "layout" => [due(1, 1)],
               "lock_version" => 1
             })

    assert same.lock_version == 1
    assert [%{operation: :create}] = entries()
  end

  # User story:
  # As the operator arranging my menu,
  # I want to rename a dashboard and move it in the menu, each journaled,
  # so that the menu reads as I want it and the journal says who changed it.
  #
  # Acceptance criteria:
  # - A rename stores the trimmed name under the name's rules, raises
  #   lock_version and journals an update.
  # - A reposition stores the position (1 to 10,000), the list follows it,
  #   and it journals an update.
  # - An unknown id is :not_found.
  test "a rename and a reposition are each one journaled update" do
    first = create!("First")
    second = create!("Second")

    assert {:ok, renamed} = Dashboards.rename_dashboard(agent(), first.id, "  Erstes ")
    assert renamed.name == "Erstes"
    assert renamed.lock_version == 2

    assert {:error, %Ecto.Changeset{errors: [name: _]}} =
             Dashboards.rename_dashboard(agent(), first.id, "Two\nlines")

    assert {:ok, moved} = Dashboards.reposition_dashboard(agent(), second.id, 1)
    assert moved.position == 1
    assert Enum.map(Dashboards.list_dashboards(), & &1.id) == [first.id, second.id]

    assert {:ok, _moved} = Dashboards.reposition_dashboard(agent(), first.id, 3)
    assert Enum.map(Dashboards.list_dashboards(), & &1.id) == [second.id, first.id]

    for bad <- [0, -1, 10_001, "2", 1.5, nil] do
      assert {:error, %Ecto.Changeset{errors: [position: _]}} =
               Dashboards.reposition_dashboard(agent(), first.id, bad)
    end

    assert Dashboards.rename_dashboard(agent(), second.id + 1_000, "X") == {:error, :not_found}
    assert Dashboards.reposition_dashboard(agent(), second.id + 1_000, 2) == {:error, :not_found}

    assert Enum.map(entries(), & &1.operation) == [:create, :create, :update, :update, :update]
  end

  # User story:
  # As the operator removing a dashboard,
  # I want its dry run to say that nothing else is deleted, and the delete
  # journaled,
  # so that I know a dashboard takes no figure, view or other dashboard with
  # it (ADR-0062 §8).
  #
  # Acceptance criteria:
  # - The dry run names one row of one kind, the dashboard, and writes
  #   nothing: the dashboard stays and nothing is journaled.
  # - The delete removes the row and journals a delete whose before is the
  #   row; the other dashboard stays.
  # - An unknown id is :not_found for both.
  test "a delete deletes the dashboard alone, and its dry run says so" do
    keep = create!("Keep")
    gone = create!("Gone", [due(1, 1)])

    assert Dashboards.dry_run_delete_dashboard(agent(), gone.id) ==
             {:ok, %{dashboards: %{count: 1, ids: [gone.id]}}}

    assert Dashboards.get_dashboard(gone.id)
    assert length(entries()) == 2

    assert {:ok, %Dashboard{id: id}} = Dashboards.delete_dashboard(agent(), gone.id)
    assert id == gone.id
    assert Dashboards.get_dashboard(gone.id) == nil
    assert Enum.map(Dashboards.list_dashboards(), & &1.id) == [keep.id]

    assert %{operation: :delete, before: %{"name" => "Gone"}, after: nil} = List.last(entries())

    assert Dashboards.delete_dashboard(agent(), gone.id) == {:error, :not_found}
    assert Dashboards.dry_run_delete_dashboard(agent(), gone.id) == {:error, :not_found}
  end

  # User story (ADR-0062 §2, "the next save drops the stale id"; the
  # orchestrator's reconciliation with "nothing is repaired silently"):
  # As the operator who deleted a view a dashboard's widget named,
  # I want my next save of that dashboard to go through and drop the id
  # that went stale, while an id that never named a view is still refused,
  # so that a deleted view does not lock the dashboard against every edit.
  #
  # Acceptance criteria:
  # - A replace that moves another widget and resends the item with the
  #   stale id stores it without its view_id.
  # - An agent resending the stale id on that very item alone: the same.
  # - A replace naming a view_id that is not in the stored layout and names
  #   no view is refused, naming the item; a create naming one is refused.
  test "a stale view_id already stored is dropped on the next save; a new unknown one is refused" do
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{"name" => "Synthetic Short"})

    pinned = %{
      "kind" => "movers",
      "size" => "M",
      "col" => 1,
      "row" => 1,
      "settings" => %{"view_id" => view.id, "period" => "1m"}
    }

    moved = create!("Moved", [pinned, due(7, 1)])
    resent = create!("Resent", [pinned])
    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), view)

    assert {:ok, %Dashboard{layout: [movers, due]}} =
             Dashboards.replace_dashboard(Actor.owner_ui(), moved.id, %{
               "name" => "Moved",
               "layout" => [pinned, due(10, 1)],
               "lock_version" => 1
             })

    assert movers["settings"] == %{"period" => "1m"}
    assert due["col"] == 10

    assert {:ok, %Dashboard{layout: [%{"settings" => settings}], lock_version: 2}} =
             Dashboards.replace_dashboard(agent(), resent.id, %{
               "name" => "Resent",
               "layout" => [pinned],
               "lock_version" => 1
             })

    assert settings == %{"period" => "1m"}
    assert Dashboards.get_dashboard(resent.id).layout == [Map.put(pinned, "settings", settings)]

    fresh = put_in(pinned, ["settings", "view_id"], view.id + 1_000)

    assert {:error, %Ecto.Changeset{errors: [layout: {"names no view", meta}]}} =
             Dashboards.replace_dashboard(agent(), resent.id, %{
               "name" => "Resent",
               "layout" => [due(7, 1), fresh],
               "lock_version" => 2
             })

    assert meta[:index] == 1
    assert meta[:field] == "settings.view_id"

    assert {:error, %Ecto.Changeset{errors: [layout: {"names no view", _meta}]}} =
             Dashboards.create_dashboard(agent(), %{"name" => "New", "layout" => [pinned]})
  end

  # Writes a layout past the validation, as a later release whose registry
  # no longer has a kind finds a layout this one stored.
  defp force_layout!(dashboard, layout) do
    Repo.transaction(fn ->
      Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test', true)")

      Repo.query!("UPDATE dashboards SET layout = $1::jsonb WHERE id = $2", [layout, dashboard.id])
    end)
  end

  # User story (ADR-0062 §2; Sprint 31 closing act, C4):
  # As the operator whose dashboard holds a widget a later release no
  # longer registers,
  # I want my next pin, catalogue add or save to go through and drop that
  # widget, as a deleted view's id is dropped, while a kind I send that was
  # never stored is still refused,
  # so that one retired kind does not lock the dashboard against every
  # edit.
  #
  # Acceptance criteria:
  # - A replace resending the stored layout with one item changed (a pin)
  #   stores it without the unregistered item.
  # - The catalogue's add (the stored layout plus one item, placed where
  #   the dropped item stood) goes through: the dropped item meets no
  #   overlap.
  # - A later bad item's refusal still names its place in the list sent.
  # - A replace naming an unregistered kind the stored layout does not hold
  #   is refused (unknown_kind, its index); a create naming one is refused.
  test "a stored item whose kind is no longer registered is dropped on the next save" do
    movers = %{"kind" => "movers", "size" => "M", "col" => 1, "row" => 1, "settings" => %{}}
    gone = %{"kind" => "gone_kind", "size" => "S", "col" => 7, "row" => 1, "settings" => %{}}
    dashboard = create!("Retired", [movers])
    force_layout!(dashboard, [movers, gone])

    pinned = put_in(movers, ["settings", "period"], "1w")

    assert {:ok, %Dashboard{layout: [^pinned], lock_version: 2}} =
             Dashboards.replace_dashboard(Actor.owner_ui(), dashboard.id, %{
               "name" => "Retired",
               "layout" => [pinned, gone],
               "lock_version" => 1
             })

    force_layout!(dashboard, [movers, gone])
    added = %{"kind" => "due", "size" => "S", "col" => 7, "row" => 1, "settings" => %{}}

    assert {:ok, %Dashboard{layout: [^movers, ^added], lock_version: 3}} =
             Dashboards.replace_dashboard(Actor.owner_ui(), dashboard.id, %{
               "name" => "Retired",
               "layout" => [movers, gone, added],
               "lock_version" => 2
             })

    force_layout!(dashboard, [movers, gone])

    assert {:error, %Ecto.Changeset{errors: [layout: {_message, meta}]}} =
             Dashboards.replace_dashboard(Actor.owner_ui(), dashboard.id, %{
               "name" => "Retired",
               "layout" => [movers, gone, Map.put(added, "size", "L")],
               "lock_version" => 3
             })

    assert {meta[:index], meta[:reason]} == {2, :unsupported_size}

    never = Map.put(gone, "kind", "never_kind")

    assert {:error, %Ecto.Changeset{errors: [layout: {_message, meta}]}} =
             Dashboards.replace_dashboard(Actor.owner_ui(), dashboard.id, %{
               "name" => "Retired",
               "layout" => [movers, never],
               "lock_version" => 3
             })

    assert {meta[:index], meta[:reason]} == {1, :unknown_kind}

    assert {:error, %Ecto.Changeset{errors: [layout: {_message, meta}]}} =
             Dashboards.create_dashboard(agent(), %{"name" => "New", "layout" => [gone]})

    assert {meta[:index], meta[:reason]} == {0, :unknown_kind}
  end

  # User story:
  # As the operator who moved a dashboard to the end of the menu's range,
  # I want a new dashboard still stored, at that end,
  # so that a create never stores a position a reposition would refuse.
  #
  # Acceptance criteria:
  # - With a dashboard at the highest position, a create takes that
  #   position too; the menu then reads by id.
  test "a create's position is capped at the highest a reposition takes" do
    last = create!("Last")
    {:ok, _} = Dashboards.reposition_dashboard(agent(), last.id, Dashboard.max_position())

    assert {:ok, %Dashboard{position: position} = after_it} =
             Dashboards.create_dashboard(agent(), %{"name" => "After"})

    assert position == Dashboard.max_position()
    assert Enum.map(Dashboards.list_dashboards(), & &1.id) == [last.id, after_it.id]
  end

  test "a dashboard's write moves no derived figure" do
    assert BlastRadius.for_write("dashboard", %Dashboard{}) == []
    assert BlastRadius.securities_for_write("dashboard", %Dashboard{}) == []
  end
end
