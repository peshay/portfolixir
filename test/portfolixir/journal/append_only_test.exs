defmodule Portfolixir.Journal.AppendOnlyTest do
  # Runs OUTSIDE the Ecto SQL sandbox (real commits) so the database triggers
  # behave exactly as in production: the sandbox's outer transaction would
  # otherwise keep the transaction-local journal-actor GUC alive past a business
  # transaction and hide a missing-actor bug (ADR-0016, architecture amendment 2).
  # async: false — these tests own their connection and clean up explicitly.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Journal
  alias Portfolixir.Repo

  describe "audit_journal append-only enforcement" do
    test "UPDATE, DELETE and TRUNCATE of journal rows raise" do
      Sandbox.unboxed_run(Repo, fn ->
        marker = "append_only_#{System.unique_integer([:positive])}"
        id = insert_journal_row!(marker)

        assert_raise Postgrex.Error, ~r/append-only/, fn ->
          Repo.query!("UPDATE audit_journal SET actor_label = 'tampered' WHERE id = $1", [id])
        end

        assert_raise Postgrex.Error, ~r/append-only/, fn ->
          Repo.query!("DELETE FROM audit_journal WHERE id = $1", [id])
        end

        assert_raise Postgrex.Error, ~r/append-only/, fn ->
          Repo.query!("TRUNCATE audit_journal")
        end

        cleanup_journal(marker)
      end)
    end
  end

  describe "journaled-table guard (securities armed)" do
    test "a raw write without a journal actor is rejected" do
      Sandbox.unboxed_run(Repo, fn ->
        assert_raise Postgrex.Error, ~r/requires a journal actor/, fn ->
          Repo.query!(
            "INSERT INTO securities (name, currency_code, inserted_at, updated_at) " <>
              "VALUES ('Guard Probe', 'EUR', now(), now())"
          )
        end
      end)
    end

    test "an actor-first write commits the business row and its journal entry together" do
      Sandbox.unboxed_run(Repo, fn ->
        marker = "guard_ok_#{System.unique_integer([:positive])}"
        actor = Actor.system_job(marker)

        {:ok, security} =
          Catalog.create_security(actor, %{name: marker, currency_code: "EUR"})

        assert [entry] =
                 Journal.list_entries(
                   resource_type: "security",
                   resource_id: to_string(security.id)
                 )

        assert entry.operation == :create
        assert entry.actor_type == :system_job
        assert entry.actor_label == marker

        {:ok, _} = Catalog.delete_security(actor, security)
        cleanup_security(security.id)
        cleanup_journal_for_resource(to_string(security.id))
      end)
    end
  end

  # audit_journal is not itself guard-armed (only business tables are), so a raw
  # insert is allowed; the append-only triggers fire only on UPDATE/DELETE/TRUNCATE.
  defp insert_journal_row!(marker) do
    %{rows: [[id]]} =
      Repo.query!(
        "INSERT INTO audit_journal (actor_type, operation, resource_type, resource_id, inserted_at) " <>
          "VALUES ('system_job', 'create', $1, '0', now()) RETURNING id",
        [marker]
      )

    id
  end

  # Cleanup uses the documented escape hatch (session_replication_role = replica,
  # ADR-0016) — the only sanctioned way to remove rows from the append-only table.
  defp cleanup_journal(marker),
    do: delete_unguarded("DELETE FROM audit_journal WHERE resource_type = $1", [marker])

  defp cleanup_journal_for_resource(resource_id),
    do: delete_unguarded("DELETE FROM audit_journal WHERE resource_id = $1", [resource_id])

  defp cleanup_security(id),
    do: delete_unguarded("DELETE FROM securities WHERE id = $1", [id])

  defp delete_unguarded(sql, params) do
    {:ok, _} =
      Repo.transaction(fn ->
        Repo.query!("SET LOCAL session_replication_role = replica")
        Repo.query!(sql, params)
      end)

    :ok
  end
end
