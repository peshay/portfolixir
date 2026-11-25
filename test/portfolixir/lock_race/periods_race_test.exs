defmodule Portfolixir.LockRace.PeriodsRaceTest do
  # Sprint 32 T2 (ADR-0062's amendment of 2026-11-25, point 6): two creates
  # at the 50th stored period, and two replaces carrying the same
  # lock_version, raced on two real connections by the lock-order harness
  # (#996). `Portfolixir.LockTable` row 31 registers the locks: a create's
  # advisory lock on the count, a replace's row lock.
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits. Every name is synthetic.
  use ExUnit.Case, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.LockRace
  alias Portfolixir.Periods
  alias Portfolixir.Periods.SavedPeriod
  alias Portfolixir.Repo

  @moduletag :lock_race

  setup_all do
    %{db: LockRace.database!()}
  end

  # Each case starts from no stored period: the scratch database outlives
  # a case, and the limit case fills it to 50.
  setup %{db: db} do
    Repo.put_dynamic_repo(db.repo)

    for period <- Periods.list_saved(),
        do: {:ok, _} = Periods.delete_saved(Actor.owner_ui(), period.id)

    :ok
  end

  # User story:
  # As the operator,
  # I want the limit of 50 periods to hold when two creates meet at the
  # 50th,
  # so that the screen and an agent together cannot store a 51st.
  #
  # Acceptance criteria:
  # - With 49 stored, the second create waits for the first's lock on the
  #   count; one is stored, the other refused.
  test "two creates at the 50th period: one stored, one refused", %{db: db} do
    for n <- 1..49 do
      {:ok, _} =
        Periods.create_saved(Actor.owner_ui(), %{
          "name" => "Synthetic #{n}",
          "from" => "2025-01-01"
        })
    end

    create = fn name ->
      fn -> Periods.create_saved(Actor.owner_ui(), %{"name" => name, "from" => "2025-01-01"}) end
    end

    {first, second} =
      LockRace.race!(
        db,
        {create.("Fiftieth"), LockRace.query?("pg_advisory_xact_lock")},
        create.("Fifty-first")
      )

    assert {:ok, %SavedPeriod{name: "Fiftieth"}} = first
    assert second == {:error, :too_many_periods}
    assert length(Periods.list_saved()) == 50
  end

  # User story:
  # As the operator changing a period while my agent changes the same one,
  # I want the change that comes second, though both read the same
  # lock_version, refused with the stored period,
  # so that neither change overwrites the other unseen.
  #
  # Acceptance criteria:
  # - The second replace waits for the first's row lock, then answers
  #   {:error, :stale, stored} with the first's span and lock_version 2.
  # - One update is journaled, the first's.
  test "two replaces on one lock_version: the second waits, then is stale", %{db: db} do
    {:ok, period} =
      Periods.create_saved(Actor.owner_ui(), %{"name" => "Raced", "from" => "2025-01-01"})

    replace = fn actor, from ->
      fn ->
        Periods.replace_saved(actor, period.id, %{
          "name" => "Raced",
          "from" => from,
          "to" => nil,
          "lock_version" => 1
        })
      end
    end

    {first, second} =
      LockRace.race!(
        db,
        {replace.(Actor.owner_ui(), "2025-02-01"), LockRace.query?("FOR NO KEY UPDATE")},
        replace.(Actor.api_token_rw("mcp"), "2025-03-01")
      )

    assert {:ok, %SavedPeriod{lock_version: 2}} = first
    assert {:error, :stale, %SavedPeriod{lock_version: 2, from: ~D[2025-02-01]}} = second
    assert %SavedPeriod{from: ~D[2025-02-01]} = Periods.get_saved(period.id)

    updates =
      Journal.list_entries(
        resource_type: "period",
        resource_id: to_string(period.id),
        operation: :update
      )

    assert [%{actor_type: :owner_ui}] = updates
  end
end
