defmodule Portfolixir.Dashboards.OwnScopeTest do
  # Sprint 32 S1 (ADR-0062's amendment of 2026-11-25, point 4; I61; board
  # ux-design-2026-11-25-sprint32/03 ②): a dashboard may hold a view of its
  # own, `view_id`, validated as an item's is, and records the template it
  # was copied from, `template_key`, which reads nothing.
  #
  # group: :dashboards -- a create takes the count lock (LockTable row 30).
  use Portfolixir.DataCase, async: true, group: :dashboards

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Journal

  defp agent, do: Actor.api_token_rw("mcp")

  defp view!(name) do
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: name, include_all: true})
    view
  end

  defp errors(changeset), do: Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)

  # User story:
  # As the operator, or the agent I run, composing a dashboard for one part
  # of my holdings,
  # I want the dashboard to hold a view of its own, checked as a widget's is,
  # so that every widget on it reads that view without my pinning each one.
  #
  # Acceptance criteria:
  # - A create and a template's copy store `view_id` when it names a view;
  #   one that names none (an unknown id, a string, a number past bigint) is
  #   refused on `view_id`, and nothing is written.
  # - A copy records the template's key in `template_key`; a create from
  #   empty records none; `template_key` is no field a write takes.
  # - A rename and move (`update_dashboard/3`) sets, changes or clears the
  #   view (`nil`), journaled as an update; the view alone is enough.
  test "a dashboard's own view is stored when it names a view, refused when it names none" do
    krypto = view!("Krypto")

    assert {:ok, %Dashboard{} = own} =
             Dashboards.create_dashboard(agent(), %{
               "name" => "Mein Krypto",
               "layout" => [],
               "view_id" => krypto.id
             })

    assert own.view_id == krypto.id
    assert own.template_key == nil
    assert Dashboards.get_dashboard(own.id).view_id == krypto.id

    for bad <- [999_999_999, "1", 9_223_372_036_854_775_808, 0, -1] do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Dashboards.create_dashboard(agent(), %{"name" => "X", "view_id" => bad})

      assert %{view_id: ["names no view"]} = errors(changeset)
    end

    assert {:error, {:unknown_fields, %{"template_key" => _}}} =
             Dashboards.create_dashboard(agent(), %{"name" => "X", "template_key" => "overview"})

    assert {:ok, copy} =
             Dashboards.copy_template(agent(), "overview", %{
               "name" => "Kopie",
               "view_id" => krypto.id
             })

    assert copy.template_key == "overview"
    assert copy.view_id == krypto.id

    assert {:error, %Ecto.Changeset{} = refused} =
             Dashboards.copy_template(agent(), "overview", %{"view_id" => 999_999_999})

    assert %{view_id: ["names no view"]} = errors(refused)
    assert length(Dashboards.list_dashboards()) == 2

    other = view!("Andere")
    assert {:ok, moved} = Dashboards.update_dashboard(agent(), own.id, %{"view_id" => other.id})
    assert moved.view_id == other.id
    assert moved.lock_version == own.lock_version + 1

    assert {:ok, cleared} = Dashboards.update_dashboard(agent(), own.id, %{"view_id" => nil})
    assert cleared.view_id == nil

    assert {:error, %Ecto.Changeset{} = unknown} =
             Dashboards.update_dashboard(agent(), own.id, %{"view_id" => 999_999_999})

    assert %{view_id: ["names no view"]} = errors(unknown)

    [_create, _create_copy, set, clear] =
      Journal.list_entries(resource_type: "dashboard", order: :asc)

    assert {set.operation, set.before["view_id"], set.after["view_id"]} ==
             {:update, krypto.id, other.id}

    assert {clear.operation, clear.after["view_id"]} == {:update, nil}
  end

  # User story:
  # As the operator who deleted a view a dashboard held,
  # I want the dashboard kept and its view read as the default, said where I
  # look, and the stale id dropped on its next save,
  # so that a deleted view never breaks a dashboard (ADR-0062 §2, as for an
  # item's view).
  #
  # Acceptance criteria:
  # - After the view's delete the read still answers the stored `view_id`
  #   and `Dashboards.own_view/1` answers `{:dangling, id}`; before it,
  #   `{:own, id}`; a dashboard without one `:none`.
  # - The next replace (the edit's save) drops the stale id and is journaled;
  #   a rename sending the stale id is refused, as a create's is.
  test "a deleted view leaves the dashboard's view dangling until its next save" do
    gone = view!("Weg")

    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{
        "name" => "Mit Ansicht",
        "layout" => [],
        "view_id" => gone.id
      })

    assert Dashboards.own_view(dashboard) == {:own, gone.id}

    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), gone)

    read = Dashboards.get_dashboard(dashboard.id)
    assert read.view_id == gone.id
    assert Dashboards.own_view(read) == {:dangling, gone.id}

    assert {:error, %Ecto.Changeset{}} =
             Dashboards.update_dashboard(Actor.owner_ui(), dashboard.id, %{"view_id" => gone.id})

    assert {:ok, saved} =
             Dashboards.replace_dashboard(Actor.owner_ui(), dashboard.id, %{
               "name" => "Mit Ansicht",
               "layout" => [%{"kind" => "due", "size" => "S", "col" => 1, "row" => 1}],
               "lock_version" => read.lock_version
             })

    assert saved.view_id == nil
    assert Dashboards.own_view(saved) == :none

    [_create, replace] = Journal.list_entries(resource_type: "dashboard", order: :asc)
    assert {replace.before["view_id"], replace.after["view_id"]} == {gone.id, nil}
  end
end
