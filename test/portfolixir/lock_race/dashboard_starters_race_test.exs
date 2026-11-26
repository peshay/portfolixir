defmodule Portfolixir.LockRace.DashboardStartersRaceTest do
  # Sprint 32 S3 (ADR-0062's amendment of 2026-11-25, point 5): the boot
  # task that stores the starters, raced on two real connections by the
  # lock-order harness (#996) — against a second boot (two instances on
  # one database, or a restart during the first) and against an operator's
  # create. `Portfolixir.LockTable` row 32 registers the lock: the run's
  # transaction advisory lock on the starters, taken before it reads the
  # seed table, then row 30's for each create.
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits. Every name is synthetic.
  use ExUnit.Case, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Dashboards.Seed
  alias Portfolixir.Dashboards.Starters
  alias Portfolixir.LockRace
  alias Portfolixir.Repo

  @moduletag :lock_race

  setup_all do
    %{db: LockRace.database!()}
  end

  # Each case starts from no dashboard and no seed record.
  setup %{db: db} do
    Repo.put_dynamic_repo(db.repo)

    for dashboard <- Dashboards.list_dashboards(),
        do: {:ok, _} = Dashboards.delete_dashboard(Actor.owner_ui(), dashboard.id)

    # The seed table is armed with the journal guard: its rows go only
    # under an actor.
    {:ok, _} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'owner_ui', true)")
        Repo.delete_all(Seed)
      end)

    :ok
  end

  defp seeds, do: Seed |> Repo.all() |> Enum.map(& &1.template_key) |> Enum.sort()

  # The starters of this release: „Überblick“ and, since Sprint 32 W2,
  # „Allokation & Ziele“.
  @starters ~w(overview allocation_targets)

  # User story:
  # As the operator whose instance starts twice at once (a restart while
  # the first start still seeds),
  # I want each starter stored once,
  # so that the update never doubles a starter.
  #
  # Acceptance criteria:
  # - The second run waits for the first's lock on the starters, then
  #   finds the record and stores nothing.
  # - One dashboard and one seed record per starter.
  test "two boots at once: the second waits on the starters' lock and stores nothing", %{
    db: db
  } do
    {first, second} =
      LockRace.race!(
        db,
        {fn -> Starters.seed() end, LockRace.query?("pg_advisory_xact_lock")},
        fn -> Starters.seed() end
      )

    assert {:ok, %{stored: @starters}} = first
    assert {:ok, %{stored: [], counted: []}} = second
    assert Enum.map(Dashboards.list_dashboards(), & &1.template_key) == @starters
    assert seeds() == Enum.sort(@starters)
  end

  # User story:
  # As the operator who creates a dashboard while the boot seeds,
  # I want my create not to wait for the boot, and the boot to treat my
  # dashboard as the instance's,
  # so that a start never blocks me and never adds „Überblick“ beside a
  # dashboard I made first.
  #
  # Acceptance criteria:
  # - The boot holds the starters' lock; the operator's create passes it
  #   (it takes only the count lock) and commits.
  # - The boot then sees a dashboard and counts „Überblick“ as seeded:
  #   the operator's dashboard and the other starters are stored, and the
  #   records are written.
  test "a boot against the operator's create: the create passes, the boot counts", %{db: db} do
    {first, second} =
      LockRace.race!(
        db,
        {fn -> Starters.seed() end, LockRace.query?("pg_advisory_xact_lock")},
        fn -> Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Meins"}) end,
        second: :passes
      )

    assert {:ok, %{stored: tl(@starters), counted: ["overview"]}} == first
    assert {:ok, %Dashboard{name: "Meins"}} = second
    assert [%Dashboard{name: "Meins"} | others] = Dashboards.list_dashboards()
    assert Enum.map(others, & &1.template_key) == tl(@starters)
    assert seeds() == Enum.sort(@starters)
  end
end
