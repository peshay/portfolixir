defmodule Portfolixir.Dashboards.StartersTest do
  # Sprint 32 S3 (ADR-0062's amendment of 2026-11-25, point 5; I57; board
  # ux-design-2026-11-25-sprint32/02 A): each template marked as a starter
  # is stored once, on the first start of the release that brings it, by a
  # boot task under the system actor, journaled, and recorded in a seed
  # table by its key, so a starter the operator deleted is never stored
  # again. An instance that already stores a dashboard counts „Überblick“
  # as seeded. A read still never writes
  # (test/portfolixir/dashboards/dashboard_test.exs keeps Sprint 31's).
  #
  # group: :dashboards -- a seed creates dashboards under the count lock
  # (LockTable row 30) and takes the starters' lock (row 32).
  use Portfolixir.DataCase, async: true, group: :dashboards

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Dashboards.Seed
  alias Portfolixir.Dashboards.Starters
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Journal

  defp seeds, do: Seed |> Repo.all() |> Enum.map(& &1.template_key) |> Enum.sort()

  # User story:
  # As the operator updating to a release that brings starter dashboards,
  # I want each stored once, as mine from then on, and never brought back
  # once I deleted it,
  # so that the update gives me the screens as dashboards without undoing
  # what I chose.
  #
  # Acceptance criteria:
  # - The starters are the templates marked so; in this release
  #   „Überblick“ only.
  # - On an instance with no dashboard, a run stores „Überblick“ as a copy
  #   (its template_key recorded), journaled under the system actor
  #   „dashboard_starters“, and records the key in the seed table, the
  #   record journaled too.
  # - A second run stores nothing and journals nothing.
  # - After the operator deleted the starter, the run (the task restarted)
  #   stores nothing again.
  test "a starter is stored once, and a deleted one never again" do
    assert Enum.map(Templates.starters(), & &1.key) == ["overview"]

    assert {:ok, %{stored: ["overview"], counted: []}} = Starters.seed()

    assert [%Dashboard{template_key: "overview", name: "Overview"} = stored] =
             Dashboards.list_dashboards()

    {:ok, template} = Templates.fetch("overview")
    assert stored.layout == template.layout
    assert seeds() == ["overview"]

    [create] = Journal.list_entries(resource_type: "dashboard")

    assert {create.operation, create.actor_type, create.actor_label} ==
             {:create, :system_job, "dashboard_starters"}

    [record] = Journal.list_entries(resource_type: "dashboard_seed")
    assert {record.operation, record.after["template_key"]} == {:create, "overview"}

    assert {:ok, %{stored: [], counted: []}} = Starters.seed()
    assert length(Dashboards.list_dashboards()) == 1

    {:ok, _} = Dashboards.delete_dashboard(Actor.owner_ui(), stored.id)

    assert {:ok, %{stored: [], counted: []}} = Starters.seed()
    assert Dashboards.list_dashboards() == []
    assert length(Journal.list_entries(resource_type: "dashboard")) == 2
    assert length(Journal.list_entries(resource_type: "dashboard_seed")) == 1
  end

  # User story:
  # As the operator who already made a dashboard before the update,
  # I want „Überblick“ not stored a second time beside mine,
  # so that the update does not add what I already have (ADR-0062's
  # amendment of 2026-11-25, point 5).
  #
  # Acceptance criteria:
  # - With one dashboard stored, the run stores nothing, records
  #   „Überblick“ as seeded (counted), and journals that record only.
  test "an instance that stores a dashboard counts „Überblick“ as seeded" do
    {:ok, mine} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Meins"})

    assert {:ok, %{stored: [], counted: ["overview"]}} = Starters.seed()
    assert Dashboards.list_dashboards() == [mine]
    assert seeds() == ["overview"]
    assert length(Journal.list_entries(resource_type: "dashboard")) == 1
  end

  # User story:
  # As the operator whose instance starts,
  # I want the boot to seed the starters unless the configuration turns it
  # off, and never stop the boot,
  # so that the update needs nothing from me.
  #
  # Acceptance criteria:
  # - `seed_on_boot/0` with `:seed_starters_on_boot` false stores nothing;
  #   with it true it seeds; it answers :ok either way.
  # - `Portfolixir.Application.after_start/0` names it among its steps.
  test "the boot step is gated by its configuration and wired into the start" do
    original = Application.get_env(:portfolixir, :seed_starters_on_boot)
    on_exit(fn -> Application.put_env(:portfolixir, :seed_starters_on_boot, original) end)

    Application.put_env(:portfolixir, :seed_starters_on_boot, false)
    assert Starters.seed_on_boot() == :ok
    assert Dashboards.list_dashboards() == []

    Application.put_env(:portfolixir, :seed_starters_on_boot, true)
    assert Starters.seed_on_boot() == :ok
    assert [%Dashboard{template_key: "overview"}] = Dashboards.list_dashboards()

    source = File.read!("lib/portfolixir/application.ex")
    assert source =~ "alias Portfolixir.Dashboards.Starters"
    assert source =~ "Starters.seed_on_boot()"
  end
end
