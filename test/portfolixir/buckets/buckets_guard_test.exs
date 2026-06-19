defmodule Portfolixir.Buckets.BucketsGuardTest do
  # Runs OUTSIDE the Ecto SQL sandbox (real commits) so the journal-actor guard
  # trigger on the armed `buckets` table behaves exactly as in production
  # (ADR-0017, architecture amendment 2). async: false — owns its connection.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Journal
  alias Portfolixir.Repo

  # User story:
  # As a maintainer relying on mechanical audit completeness,
  # I want a raw write to the armed `buckets` table without a journal actor to be
  # rejected by the database,
  # so that no bucket-definition write can bypass attribution (ADR-0017/ADR-0018).
  describe "buckets guard trigger (armed)" do
    test "a raw insert without a journal actor is rejected" do
      Sandbox.unboxed_run(Repo, fn ->
        assert_raise Postgrex.Error, ~r/requires a journal actor/, fn ->
          Repo.query!(
            "INSERT INTO buckets (name, inserted_at, updated_at) " <>
              "VALUES ('Guard Probe', now(), now())"
          )
        end
      end)
    end

    test "an actor-first create commits the bucket and its journal entry together" do
      Sandbox.unboxed_run(Repo, fn ->
        marker = "guard_ok_#{System.unique_integer([:positive])}"

        {:ok, bucket} = Buckets.create_bucket(Actor.system_job(marker), %{name: marker})

        assert [entry] =
                 Journal.list_entries(
                   resource_type: "bucket",
                   resource_id: to_string(bucket.id)
                 )

        assert entry.operation == :create
        assert entry.actor_type == :system_job
        assert entry.actor_label == marker

        {:ok, _} = Buckets.delete_bucket(Actor.system_job(marker), bucket)
        cleanup_bucket(bucket.id)
        cleanup_journal_for_resource(to_string(bucket.id))
      end)
    end
  end

  # Cleanup uses the documented escape hatch (session_replication_role = replica,
  # ADR-0017): the append-only journal and the guard trigger both stand down.
  defp cleanup_bucket(id),
    do: delete_unguarded("DELETE FROM buckets WHERE id = $1", [id])

  defp cleanup_journal_for_resource(resource_id),
    do: delete_unguarded("DELETE FROM audit_journal WHERE resource_id = $1", [resource_id])

  defp delete_unguarded(sql, params) do
    {:ok, _} =
      Repo.transaction(fn ->
        Repo.query!("SET LOCAL session_replication_role = replica")
        Repo.query!(sql, params)
      end)

    :ok
  end
end
