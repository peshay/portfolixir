defmodule Portfolixir.LockRace.DashboardsRaceTest do
  # Sprint 31 D1 (ADR-0062 §2; the plan's D-8 point 10, "the 409 against two
  # concurrent writers: the screen and an agent's put on the same
  # lock_version"): two replaces carrying the same lock_version, and two
  # creates at the 50th dashboard, raced on two real connections by the
  # lock-order harness (#996). `Portfolixir.LockTable` row 28 registers the
  # locks: a create's advisory lock on the count, a replace's row lock.
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits. Every name is synthetic.
  use ExUnit.Case, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Journal
  alias Portfolixir.LockRace
  alias Portfolixir.Repo

  @moduletag :lock_race

  setup_all do
    %{db: LockRace.database!()}
  end

  # Each case starts from no dashboard: the scratch database outlives a
  # case, and the limit case fills it to 50.
  setup %{db: db} do
    Repo.put_dynamic_repo(db.repo)

    for dashboard <- Dashboards.list_dashboards(),
        do: {:ok, _} = Dashboards.delete_dashboard(Actor.owner_ui(), dashboard.id)

    :ok
  end

  defp due(col), do: %{"kind" => "due", "size" => "S", "col" => col, "row" => 1}

  # User story:
  # As the operator saving a dashboard while my agent saves the same one,
  # I want the save that comes second, though both read the same
  # lock_version, refused with the stored dashboard,
  # so that neither edit overwrites the other unseen.
  #
  # Acceptance criteria:
  # - The second replace waits for the first's row lock, then answers
  #   {:error, :stale, stored} with the first's layout and lock_version 2.
  # - One update is journaled, the first's.
  test "two replaces on one lock_version: the second waits, then is stale", %{db: db} do
    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Raced", "layout" => [due(1)]})

    replace = fn actor, col ->
      fn ->
        Dashboards.replace_dashboard(actor, dashboard.id, %{
          "name" => "Raced",
          "layout" => [due(col)],
          "lock_version" => 1
        })
      end
    end

    {first, second} =
      LockRace.race!(
        db,
        {replace.(Actor.owner_ui(), 4), LockRace.query?("FOR NO KEY UPDATE")},
        replace.(Actor.api_token_rw("mcp"), 7)
      )

    assert {:ok, %Dashboard{lock_version: 2}} = first
    assert {:error, :stale, %Dashboard{lock_version: 2, layout: [%{"col" => 4}]}} = second

    assert %Dashboard{lock_version: 2, layout: [%{"col" => 4}]} =
             Dashboards.get_dashboard(dashboard.id)

    updates =
      Journal.list_entries(
        resource_type: "dashboard",
        resource_id: to_string(dashboard.id),
        operation: :update
      )

    assert [%{actor_type: :owner_ui}] = updates
  end

  # User story:
  # As the operator,
  # I want the limit of 50 dashboards to hold when two creates meet at the
  # 50th,
  # so that the screen and an agent together cannot store a 51st.
  #
  # Acceptance criteria:
  # - With 49 stored, the second create waits for the first's lock on the
  #   count; one is stored, the other refused.
  test "two creates at the 50th dashboard: one stored, one refused", %{db: db} do
    for n <- 1..49 do
      {:ok, _} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Synthetic #{n}"})
    end

    create = fn name ->
      fn -> Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => name}) end
    end

    {first, second} =
      LockRace.race!(
        db,
        {create.("Fiftieth"), LockRace.query?("pg_advisory_xact_lock")},
        create.("Fifty-first")
      )

    assert {:ok, %Dashboard{name: "Fiftieth"}} = first
    assert second == {:error, :too_many_dashboards}
    assert length(Dashboards.list_dashboards()) == 50
  end
end
