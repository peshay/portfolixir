defmodule Portfolixir.Dashboards.UpdateTest do
  # Sprint 31 D2 (FR-60, ADR-0062 §2, §8): the one write behind
  # `PATCH /api/v1/dashboards/:id` — a rename and a reposition, either or
  # both, in one journaled update, with an optional lock_version: sent and
  # stale, it is refused with the stored dashboard, so a rename racing a
  # screen's save is never lost unseen; not sent, the write applies to the
  # row as stored (the orchestrator's decision for D2).
  #
  # group: :dashboards -- every module that creates a dashboard joins it
  # (the create's count lock, `Portfolixir.LockTable` row 30).
  use Portfolixir.DataCase, async: true, group: :dashboards

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Journal

  defp agent, do: Actor.api_token_rw("mcp")

  defp entries, do: Journal.list_entries(resource_type: "dashboard", order: :asc)

  defp create!(name) do
    {:ok, dashboard} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => name})
    dashboard
  end

  # User story (ADR-0062 §8):
  # As the agent the operator runs,
  # I want to rename a dashboard and move it in the menu in one write,
  # carrying the lock_version I read when I want my change refused if the
  # operator saved in between,
  # so that my rename never silently lands on a layout I have not seen, and
  # never silently undoes the operator's.
  #
  # Acceptance criteria:
  # - name and position, either or both, are one update, one journal entry
  #   under the actor; lock_version rises by one.
  # - With the stored lock_version the write applies; with another it
  #   answers {:error, :stale, stored} and writes and journals nothing.
  # - Without lock_version the write applies to the row as stored.
  # - Neither name nor position, a key it does not take, a lock_version that
  #   is no whole number from 1, and an unknown id are refused, writing
  #   nothing; one that changes nothing journals nothing.
  test "a rename and a reposition in one write, with an optional lock_version" do
    first = create!("Erstes")
    second = create!("Zweites")
    created = length(entries())

    assert {:ok, both} =
             Dashboards.update_dashboard(agent(), first.id, %{
               "name" => " Kurzfristig ",
               "position" => 5,
               "lock_version" => 1
             })

    assert {both.name, both.position, both.lock_version} == {"Kurzfristig", 5, 2}
    assert [entry] = Enum.drop(entries(), created)
    assert entry.operation == :update
    assert entry.actor_label == "mcp"
    assert entry.before["name"] == "Erstes"
    assert entry.after["name"] == "Kurzfristig"
    assert entry.after["position"] == 5

    assert {:error, :stale, stored} =
             Dashboards.update_dashboard(agent(), first.id, %{name: "Verloren", lock_version: 1})

    assert {stored.name, stored.lock_version} == {"Kurzfristig", 2}
    assert Dashboards.get_dashboard(first.id).name == "Kurzfristig"
    assert length(entries()) == created + 1

    assert {:ok, renamed} =
             Dashboards.update_dashboard(agent(), second.id, %{name: "Langfristig"})

    assert {renamed.name, renamed.position, renamed.lock_version} == {"Langfristig", 2, 2}

    assert {:ok, moved} = Dashboards.update_dashboard(agent(), second.id, %{"position" => 1})
    assert {moved.name, moved.position, moved.lock_version} == {"Langfristig", 1, 3}
    assert length(entries()) == created + 3

    assert {:ok, same} =
             Dashboards.update_dashboard(agent(), second.id, %{"name" => "Langfristig"})

    assert same.lock_version == 3
    assert length(entries()) == created + 3

    assert {:error, {:missing_fields, %{"name" => [_], "position" => [_]}}} =
             Dashboards.update_dashboard(agent(), second.id, %{"lock_version" => 3})

    assert {:error, {:unknown_fields, %{"layout" => [_]}}} =
             Dashboards.update_dashboard(agent(), second.id, %{"name" => "X", "layout" => []})

    for bad <- [0, "3", 3.0, nil, 9_223_372_036_854_775_808] do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Dashboards.update_dashboard(agent(), second.id, %{
                 "name" => "X",
                 "lock_version" => bad
               }),
             inspect(bad)

      assert Keyword.has_key?(changeset.errors, :lock_version)
    end

    for {attrs, field} <- [
          {%{"name" => "Two\nlines"}, :name},
          {%{"name" => ""}, :name},
          {%{"position" => "2"}, :position},
          {%{"position" => 0}, :position},
          {%{"name" => "Gut", "position" => 10_001}, :position}
        ] do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Dashboards.update_dashboard(agent(), second.id, attrs),
             inspect(attrs)

      assert Keyword.has_key?(changeset.errors, field), inspect(attrs)
    end

    assert Dashboards.get_dashboard(second.id).name == "Langfristig"
    assert length(entries()) == created + 3

    assert Dashboards.update_dashboard(agent(), second.id + 1_000, %{"name" => "X"}) ==
             {:error, :not_found}
  end
end
