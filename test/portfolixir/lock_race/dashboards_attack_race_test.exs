defmodule Portfolixir.LockRace.DashboardsAttackRaceTest do
  # Sprint 31 D1's attack lens (ADR-0062 §2; the plan's D-8 point 10, "the
  # 409 against two concurrent writers: the screen and an agent's put on
  # the same lock_version"): writers on real connections of a scratch
  # database, outside the sandbox -- many at once, released together, and
  # the lock-order harness (#996) for a rename or a delete meeting a
  # replace. Written by a reviewer who did not write the context.
  #
  # async: false -- the cases share a scratch database. Every name is
  # synthetic.
  use ExUnit.Case, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Journal
  alias Portfolixir.LockRace
  alias Portfolixir.Repo
  alias Portfolixir.ScratchDatabase

  @moduletag :lock_race

  @writers 8

  setup_all do
    db = ScratchDatabase.start!(suffix: "dashattack", pool_size: @writers + 1)
    ScratchDatabase.migrate!(db, :head)
    %{db: db}
  end

  setup %{db: db} do
    Repo.put_dynamic_repo(db.repo)

    for dashboard <- Dashboards.list_dashboards(),
        do: {:ok, _} = Dashboards.delete_dashboard(Actor.owner_ui(), dashboard.id)

    :ok
  end

  defp due(col), do: %{"kind" => "due", "size" => "S", "col" => col, "row" => 1}

  defp updates(id),
    do:
      Journal.list_entries(
        resource_type: "dashboard",
        resource_id: to_string(id),
        operation: :update
      )

  # Starts one process per function, each on a connection of its own, all
  # released by one message, and answers their results in order.
  defp released_together(db, funs) do
    parent = self()

    tasks =
      for fun <- funs do
        Task.async(fn ->
          ScratchDatabase.run(db, fn ->
            Repo.checkout(fn ->
              send(parent, {:ready, self()})

              receive do
                :go -> fun.()
              end
            end)
          end)
        end)
      end

    # A pool smaller than the writers holds the rest in its queue: release
    # the ones that hold a connection, and the queue follows as they end.
    ready =
      for _ <- 1..min(length(funs), @writers) do
        assert_receive {:ready, pid}, 10_000
        pid
      end

    Enum.each(ready, &send(&1, :go))

    for _ <- (length(ready) + 1)..length(funs)//1 do
      assert_receive {:ready, pid}, 30_000
      send(pid, :go)
    end

    Task.await_many(tasks, 60_000)
  end

  # User story:
  # As the operator saving a dashboard while my agent saves the same one,
  # I want exactly one of several saves on one lock_version stored, however
  # they meet,
  # so that no edit overwrites another unseen.
  #
  # Acceptance criteria:
  # - Round after round, eight replaces carrying the same lock_version,
  #   released together on eight connections: exactly one is stored, the
  #   other seven answer stale with the winner's layout.
  # - The lock_version rises by exactly one per round, and one update is
  #   journaled per round.
  test "eight replaces on one lock_version, released together: exactly one wins", %{db: db} do
    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Raced", "layout" => [due(1)]})

    for round <- 1..5 do
      results =
        released_together(
          db,
          for n <- 1..@writers do
            fn ->
              Dashboards.replace_dashboard(Actor.api_token_rw("writer #{n}"), dashboard.id, %{
                "name" => "Raced",
                # The second item starts below the first one's two rows (an
                # S is 3 × 2 since Sprint 32 E4), so every writer's layout
                # is valid and a refusal can only be the stale one.
                "layout" => [due(rem(round + n, 4) * 3 + 1), %{due(1) | "row" => 2 + n}],
                "lock_version" => round
              })
            end
          end
        )

      assert [{:ok, %Dashboard{lock_version: version, layout: layout}}] =
               Enum.filter(results, &match?({:ok, _}, &1))

      assert version == round + 1
      stale = Enum.reject(results, &match?({:ok, _}, &1))
      assert length(stale) == @writers - 1

      for refusal <- stale do
        assert {:error, :stale, %Dashboard{lock_version: ^version, layout: ^layout}} = refusal
      end

      assert %Dashboard{lock_version: ^version, layout: ^layout} =
               Dashboards.get_dashboard(dashboard.id)

      assert length(updates(dashboard.id)) == round
    end
  end

  # User story:
  # As the operator,
  # I want the limit of 50 dashboards to hold when many creates meet,
  # so that the screen and agents together cannot store a 51st.
  #
  # Acceptance criteria:
  # - 51 creates (half of them a template's copy) released together on an
  #   empty table: exactly 50 are stored, one is refused.
  # - The 50 take the positions 1 to 50, each once, and 50 creates are
  #   journaled.
  test "51 creates released together: exactly 50 stored, each on its own place", %{db: db} do
    results =
      released_together(
        db,
        for n <- 1..51 do
          if rem(n, 2) == 0 do
            fn -> Dashboards.copy_template(Actor.api_token_rw("agent"), "overview", %{}) end
          else
            fn -> Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Synthetic #{n}"}) end
          end
        end
      )

    assert Enum.count(results, &match?({:ok, %Dashboard{}}, &1)) == 50
    assert Enum.count(results, &(&1 == {:error, :too_many_dashboards})) == 1

    stored = Dashboards.list_dashboards()
    assert length(stored) == 50
    assert Enum.map(stored, & &1.position) == Enum.to_list(1..50)

    assert length(Journal.list_entries(resource_type: "dashboard", operation: :create)) >= 50

    ids = MapSet.new(stored, &to_string(&1.id))

    creates =
      Journal.list_entries(resource_type: "dashboard", operation: :create)
      |> Enum.filter(&MapSet.member?(ids, &1.resource_id))

    assert length(creates) == 50
  end

  # User story:
  # As the operator replacing a dashboard while my agent renames it,
  # I want the replace that comes second refused with the renamed
  # dashboard, and a rename that comes second applied on top of the replace,
  # so that neither the name nor the layout is lost unseen.
  #
  # Acceptance criteria:
  # - A rename holding the row lock, then a replace on the lock_version
  #   read before it: the replace waits, then is stale, carrying the new
  #   name.
  # - A replace holding the row lock, then a rename: the rename waits, then
  #   renames the replaced dashboard; the stored row has the replace's
  #   layout and the rename's name, lock_version 3, and two updates are
  #   journaled, the rename's before-image the replace's after-image.
  test "a rename meeting a replace: neither is lost unseen", %{db: db} do
    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Raced", "layout" => [due(1)]})

    rename = fn name ->
      fn -> Dashboards.rename_dashboard(Actor.api_token_rw("mcp"), dashboard.id, name) end
    end

    replace = fn version ->
      fn ->
        Dashboards.replace_dashboard(Actor.owner_ui(), dashboard.id, %{
          "name" => "Raced",
          "layout" => [due(4)],
          "lock_version" => version
        })
      end
    end

    {renamed, stale} =
      LockRace.race!(
        db,
        {rename.("Agent's"), LockRace.query?("FOR NO KEY UPDATE")},
        replace.(1)
      )

    assert {:ok, %Dashboard{name: "Agent's", lock_version: 2}} = renamed
    assert {:error, :stale, %Dashboard{name: "Agent's", lock_version: 2}} = stale

    {replaced, renamed_again} =
      LockRace.race!(
        db,
        {replace.(2), LockRace.query?("FOR NO KEY UPDATE")},
        rename.("Agent's again")
      )

    assert {:ok, %Dashboard{name: "Raced", lock_version: 3}} = replaced

    assert {:ok, %Dashboard{name: "Agent's again", layout: [%{"col" => 4}], lock_version: 4}} =
             renamed_again

    assert [_rename, replace_entry, rename_entry] = updates(dashboard.id) |> Enum.sort_by(& &1.id)
    assert replace_entry.after["name"] == "Raced"
    assert rename_entry.before["name"] == "Raced"
    assert rename_entry.before["layout"] == [Map.put(due(4), "settings", %{})]
  end

  # User story:
  # As the operator deleting a dashboard while my agent replaces it,
  # I want the replace that comes second told the dashboard is gone,
  # so that it neither raises nor writes a row back.
  #
  # Acceptance criteria:
  # - A delete holding the row lock, then a replace: the replace waits,
  #   then answers not found; no row is left and no update journaled.
  test "a replace meeting a delete answers not found", %{db: db} do
    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Raced", "layout" => [due(1)]})

    {deleted, replaced} =
      LockRace.race!(
        db,
        {fn -> Dashboards.delete_dashboard(Actor.owner_ui(), dashboard.id) end,
         LockRace.query?("FOR UPDATE")},
        fn ->
          Dashboards.replace_dashboard(Actor.api_token_rw("mcp"), dashboard.id, %{
            "name" => "Raced",
            "layout" => [due(4)],
            "lock_version" => 1
          })
        end
      )

    assert {:ok, %Dashboard{}} = deleted
    assert replaced == {:error, :not_found}
    assert Dashboards.get_dashboard(dashboard.id) == nil
    assert updates(dashboard.id) == []
  end
end
