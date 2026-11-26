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
  # async: false -- the refusals below are a trigger installed on
  # `dashboards` or `dashboard_seeds` inside the test's own sandbox
  # transaction, and creating a trigger locks its table against every
  # concurrent writer until the test ends; the boot step's test also sets
  # the application's configuration, which every process reads.
  use Portfolixir.DataCase, async: false

  import ExUnit.CaptureLog

  require Logger

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Dashboards.Seed
  alias Portfolixir.Dashboards.Starters
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Journal

  # The starters of this release, in the menu's order: „Überblick“ and,
  # since Sprint 32 W2 to W4, „Bestände“, „Allokation & Ziele“,
  # „Snapshots“ and „Risiko“.
  @starters ~w(overview holdings allocation_targets snapshots risk)

  defp seeds, do: Seed |> Repo.all() |> Enum.map(& &1.template_key) |> Enum.sort()

  defp journaled(type), do: Journal.list_entries(resource_type: type)

  # The database refuses every insert into `table` for the rest of the
  # test's transaction: as a check constraint the write's changeset names
  # (`constraint`, answered as a changeset error), or, without one, as an
  # error no changeset knows (raised). Rolled back with the test.
  defp refuse_inserts_into!(table, constraint \\ nil) do
    raise_clause =
      if constraint,
        do: "USING ERRCODE = 'check_violation', CONSTRAINT = '#{constraint}'",
        else: ""

    Repo.query!("""
    CREATE FUNCTION synthetic_refused_#{table}() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'synthetic refusal of an insert into #{table}' #{raise_clause};
    END
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER synthetic_refused_#{table} BEFORE INSERT ON #{table}
    FOR EACH ROW EXECUTE FUNCTION synthetic_refused_#{table}()
    """)

    :ok
  end

  defp allow_inserts_into!(table) do
    Repo.query!("DROP TRIGGER synthetic_refused_#{table} ON #{table}")
    :ok
  end

  # User story:
  # As the operator updating to a release that brings starter dashboards,
  # I want each stored once, as mine from then on, and never brought back
  # once I deleted it,
  # so that the update gives me the screens as dashboards without undoing
  # what I chose.
  #
  # Acceptance criteria:
  # - The starters are the templates marked so; in this release
  #   „Überblick“, „Allokation & Ziele“, „Snapshots“ and „Risiko“
  #   (Sprint 32 W2 to W4).
  # - On an instance with no dashboard, a run stores each as a copy (its
  #   template_key recorded), journaled under the system actor
  #   „dashboard_starters“, and records each key in the seed table, the
  #   records journaled too.
  # - A second run stores nothing and journals nothing.
  # - After the operator deleted a starter, the run (the task restarted)
  #   stores nothing again.
  test "a starter is stored once, and a deleted one never again" do
    assert Enum.map(Templates.starters(), & &1.key) == @starters

    assert {:ok, %{stored: @starters, counted: []}} = Starters.seed()

    stored_all = Dashboards.list_dashboards()
    assert Enum.map(stored_all, & &1.template_key) == @starters
    [%Dashboard{name: "Overview"} = stored | _others] = stored_all

    for dashboard <- stored_all do
      {:ok, template} = Templates.fetch(dashboard.template_key)
      assert dashboard.layout == template.layout
      assert dashboard.name == template.title
    end

    assert seeds() == Enum.sort(@starters)

    creates = Journal.list_entries(resource_type: "dashboard")
    assert length(creates) == length(@starters)

    for create <- creates do
      assert {create.operation, create.actor_type, create.actor_label} ==
               {:create, :system_job, "dashboard_starters"}
    end

    records = Journal.list_entries(resource_type: "dashboard_seed")

    assert Enum.sort(Enum.map(records, &{&1.operation, &1.after["template_key"]})) ==
             Enum.sort(Enum.map(@starters, &{:create, &1}))

    assert {:ok, %{stored: [], counted: []}} = Starters.seed()
    assert length(Dashboards.list_dashboards()) == length(@starters)

    {:ok, _} = Dashboards.delete_dashboard(Actor.owner_ui(), stored.id)

    assert {:ok, %{stored: [], counted: []}} = Starters.seed()
    assert Enum.map(Dashboards.list_dashboards(), & &1.template_key) == tl(@starters)

    assert length(Journal.list_entries(resource_type: "dashboard")) ==
             length(@starters) + 1

    assert length(Journal.list_entries(resource_type: "dashboard_seed")) == length(@starters)
  end

  # User story:
  # As the operator who already made a dashboard before the update,
  # I want „Überblick“ not stored a second time beside mine,
  # so that the update does not add what I already have (ADR-0062's
  # amendment of 2026-11-25, point 5).
  #
  # Acceptance criteria:
  # - With one dashboard stored, the run stores no „Überblick“ and
  #   records it as seeded (counted); the other starters are stored beside
  #   the operator's (Sprint 32 W2), each recorded.
  test "an instance that stores a dashboard counts „Überblick“ as seeded" do
    {:ok, mine} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Meins"})

    assert {:ok, %{stored: tl(@starters), counted: ["overview"]}} == Starters.seed()
    assert [^mine | others] = Dashboards.list_dashboards()
    assert Enum.map(others, & &1.template_key) == tl(@starters)
    assert seeds() == Enum.sort(@starters)

    assert length(Journal.list_entries(resource_type: "dashboard")) ==
             1 + length(tl(@starters))
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
    assert Enum.map(Dashboards.list_dashboards(), & &1.template_key) == @starters

    source = File.read!("lib/portfolixir/application.ex")
    assert source =~ "alias Portfolixir.Dashboards.Starters"
    assert source =~ "Starters.seed_on_boot()"
  end

  # User story:
  # As the operator reading the instance's log after an update,
  # I want the start to say which starters it stored or counted, and to
  # say nothing on a start that had nothing to do,
  # so that the log shows what the update did without repeating it on
  # every restart.
  #
  # Acceptance criteria:
  # - The first boot step logs the starters stored („overview“,
  #   „allocation_targets“, „snapshots“ and „risk“) and counted (none) at
  #   info.
  # - The next one stores nothing and logs nothing about the starters.
  test "the boot step logs what it stored, and nothing on a start with nothing to do" do
    original = Application.get_env(:portfolixir, :seed_starters_on_boot)
    on_exit(fn -> Application.put_env(:portfolixir, :seed_starters_on_boot, original) end)
    Application.put_env(:portfolixir, :seed_starters_on_boot, true)
    # The test environment logs from warning up; the run's info is read.
    Logger.put_module_level(Starters, :info)
    on_exit(fn -> Logger.delete_module_level(Starters) end)

    first = capture_log([level: :info], fn -> assert Starters.seed_on_boot() == :ok end)
    assert first =~ "starter dashboards: stored #{inspect(@starters)}, counted []"

    again = capture_log([level: :info], fn -> assert Starters.seed_on_boot() == :ok end)
    refute again =~ "starter dashboards"
    assert length(Dashboards.list_dashboards()) == length(@starters)
  end

  # User story:
  # As the operator whose database refuses a starter's write,
  # I want the run to store nothing at all and the start to go on,
  # so that no half-seeded state is left and the next start tries again.
  #
  # Acceptance criteria:
  # - The dashboard's insert refused: `seed/1` answers {:error, changeset}
  #   naming the refused field; no dashboard, no seed record, no journal
  #   entry.
  # - The boot step answers :ok and logs a warning „not seeded“.
  # - The record's insert refused after the dashboard was stored: the
  #   dashboard is taken back with it — nothing stored, nothing recorded,
  #   nothing journaled —, so the next start cannot store it twice.
  # - Once the database takes the writes again, the next run stores each
  #   starter once.
  test "a refused write stores and records nothing, and the next start tries again" do
    original = Application.get_env(:portfolixir, :seed_starters_on_boot)
    on_exit(fn -> Application.put_env(:portfolixir, :seed_starters_on_boot, original) end)
    Application.put_env(:portfolixir, :seed_starters_on_boot, true)

    refuse_inserts_into!("dashboards", "dashboards_template_key_check")

    assert {:error, %Ecto.Changeset{} = refused} = Starters.seed()
    assert Keyword.has_key?(refused.errors, :template_key)
    assert Dashboards.list_dashboards() == []
    assert seeds() == []
    assert journaled("dashboard") == []

    log = capture_log(fn -> assert Starters.seed_on_boot() == :ok end)
    assert log =~ "starter dashboards not seeded"
    assert seeds() == []

    allow_inserts_into!("dashboards")
    refuse_inserts_into!("dashboard_seeds", "dashboard_seeds_template_key_check")

    assert {:error, %Ecto.Changeset{} = unrecorded} = Starters.seed()
    assert Keyword.has_key?(unrecorded.errors, :template_key)
    assert Dashboards.list_dashboards() == []
    assert seeds() == []
    assert journaled("dashboard") == []
    assert journaled("dashboard_seed") == []

    allow_inserts_into!("dashboard_seeds")

    assert {:ok, %{stored: @starters, counted: []}} == Starters.seed()
    assert Enum.map(Dashboards.list_dashboards(), & &1.template_key) == @starters
    assert seeds() == Enum.sort(@starters)
  end

  # User story:
  # As the operator whose instance starts while its database fails in a
  # way no write expects,
  # I want the start to go on and the failure logged,
  # so that a starter never stops the instance.
  #
  # Acceptance criteria:
  # - An error the run does not answer as a refusal (raised by the
  #   database) is logged as a warning „not seeded“ with its message; the
  #   boot step answers :ok, and nothing is stored.
  test "an error the run does not expect is logged, never raised" do
    original = Application.get_env(:portfolixir, :seed_starters_on_boot)
    on_exit(fn -> Application.put_env(:portfolixir, :seed_starters_on_boot, original) end)
    Application.put_env(:portfolixir, :seed_starters_on_boot, true)

    refuse_inserts_into!("dashboards")

    log = capture_log(fn -> assert Starters.seed_on_boot() == :ok end)
    assert log =~ "starter dashboards not seeded"
    assert log =~ "synthetic refusal of an insert into dashboards"
    assert Dashboards.list_dashboards() == []
    assert seeds() == []
  end
end
