defmodule Portfolixir.LockRace.DryRunDeleteTest do
  # A cascading delete's dry run (Sprint 25 X1, #894; plan D-4) against a
  # writer it shares the database with, on two real connections of a scratch
  # database (#996): the SQL sandbox runs every connection of a test inside
  # one transaction, where no isolation level can be set and no concurrent
  # commit can land between two reads.
  #
  # The closing act of Sprint 25 found that the dry run read the ids before
  # and after the delete at READ COMMITTED, each statement a fresh snapshot,
  # so a row a concurrent transaction deleted in between was listed as one
  # the delete would remove. The dry run's transaction is REPEATABLE READ:
  # both reads see one snapshot plus the transaction's own deletes, and a
  # delete that meets a concurrent change answers a refusal, never a list.
  #
  # async: false -- the races share the barrier's limits.
  #
  # Every name, figure and identifier is synthetic.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Classifications.Classification
  alias Portfolixir.DryRun
  alias Portfolixir.LockRace
  alias Portfolixir.Repo
  alias Portfolixir.ScratchDatabase

  @endpoint PortfolixirWeb.Endpoint

  @moduletag :lock_race

  setup_all do
    %{db: LockRace.database!()}
  end

  setup %{db: db} do
    Repo.put_dynamic_repo(db.repo)
    :ok
  end

  defp owner, do: Actor.owner_ui()

  # A custom tree with one category holding one security.
  defp tree do
    suffix = System.unique_integer([:positive])

    {:ok, security} =
      Portfolixir.Catalog.create_security(owner(), %{
        name: "Saltmarsh Grid Holdings #{suffix}",
        currency_code: "EUR"
      })

    {:ok, classification} =
      Classifications.create_classification(owner(), %{name: "Grid themes #{suffix}"})

    {:ok, category} =
      Classifications.create_category(owner(), %{
        classification_id: classification.id,
        name: "Transmission"
      })

    {:ok, _} =
      Classifications.assign_security(owner(), security.id, classification.id, category.id)

    %{security: security, classification: classification, category: category}
  end

  # User story (Sprint 25 closing act, X1, #894):
  # As the operator's agent reading a dry run while other writers run,
  # I want its reads before and after the delete to see one snapshot,
  # so that it never lists a row someone else deleted as one this delete
  # removes.
  #
  # Acceptance criteria:
  # - Inside the dry run's transaction, transaction_isolation reads
  #   repeatable read.
  test "the dry run's transaction is REPEATABLE READ", %{db: db} do
    parent = self()

    ScratchDatabase.run(db, fn ->
      assert {:ok, %{classifications: %{count: 0, ids: []}}} =
               DryRun.run([classifications: Classification], fn ->
                 %{rows: rows} = Repo.query!("SHOW transaction_isolation")
                 send(parent, {:isolation, rows})
                 {:ok, :nothing}
               end)
    end)

    assert_received {:isolation, [["repeatable read"]]}
  end

  # User story (Sprint 25 closing act, X1, #894):
  # As the operator's agent asking a dry run while another writer unassigns
  # a security of the tree,
  # I want the dry run refused with a 409 saying a concurrent change
  # intervened,
  # so that I retry instead of telling the operator a list that is wrong.
  #
  # Acceptance criteria:
  # - The dry run held after its reads before the delete; a concurrent
  #   unassign of the tree's one assignment commits without waiting for it.
  # - The dry run then answers 409 with a detail saying a concurrent change
  #   intervened and to retry, never 200 listing the unassigned row, never
  #   500.
  # - Nothing is deleted: the tree and its category are still there.
  test "a concurrent delete between the dry run's reads answers 409, never a wrong list",
       %{db: db} do
    t = tree()

    {conn, unassigned} =
      LockRace.race!(
        db,
        {fn -> dry_run_delete("/api/v1/classifications/#{t.classification.id}") end,
         LockRace.query?(~s(FROM "portfolio_targets"))},
        fn ->
          Classifications.unassign_security(owner(), t.security.id, t.classification.id)
        end,
        second: :passes
      )

    assert {:ok, 1} = unassigned

    assert %{"errors" => %{"code" => "concurrent_change", "detail" => detail}} =
             json_response(conn, 409)

    assert detail =~ "concurrent change"
    assert detail =~ "retry"

    ScratchDatabase.run(db, fn ->
      assert Classifications.get_classification(t.classification.id)
      assert Classifications.get_category(t.category.id)
    end)
  end

  defp dry_run_delete(path) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> delete(path <> "?dry_run=true")
  end
end
