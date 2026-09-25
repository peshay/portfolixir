defmodule Portfolixir.Knowledge.FreeTextLegacyTest do
  # E25 S6, G01 (#891): the length CHECKs are added `NOT VALID`, and
  # PostgreSQL checks such a constraint against the whole row on every update
  # — so on a mutable table a row stored over the cap before this sprint would
  # be locked by it (the Sprint 16 review round's lesson on the weight
  # scale). The migration validates a CHECK no stored row breaks, keeps it
  # `NOT VALID` on the append-only log, and removes it from a mutable table.
  #
  # The migrator cannot be driven under the SQL sandbox, so, like
  # target_weight_legacy_test.exs, the state is rebuilt inside the sandbox
  # transaction (the constraints dropped, legacy text written past the
  # changeset) and the migration's own step is run on it; everything rolls
  # back at the end of the test.
  #
  # async: false — the test drops and re-adds constraints on three tables.
  use Portfolixir.DataCase, async: false

  import ExUnit.CaptureLog

  alias Portfolixir.Actor
  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.WorldFixtures

  @migration "priv/repo/migrations/20260925190000_bound_append_only_free_text.exs"
  @migration_module Portfolixir.Repo.Migrations.BoundAppendOnlyFreeText

  @constraints [
    {"security_notes", "security_notes_body_length_check"},
    {"security_notes", "security_notes_invalidation_condition_length_check"},
    {"security_events", "security_events_note_length_check"},
    {"policy_rule_versions", "policy_rule_versions_note_length_check"}
  ]

  setup do
    for {table, name} <- @constraints do
      Repo.query!("ALTER TABLE #{table} DROP CONSTRAINT #{name}")
    end

    :ok
  end

  defp migration do
    case Code.ensure_loaded(@migration_module) do
      {:module, module} ->
        module

      {:error, _not_loaded} ->
        [{module, _bytecode}] = Code.require_file(@migration)
        module
    end
  end

  defp as_actor(fun) do
    {:ok, result} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'owner_ui', true)")
        fun.()
      end)

    result
  end

  defp convalidated(name) do
    case Repo.query!("SELECT convalidated FROM pg_constraint WHERE conname = $1", [name]) do
      %{rows: [[valid?]]} -> valid?
      %{rows: []} -> :absent
    end
  end

  # User story:
  # As the operator upgrading an instance that holds text written before the
  # caps,
  # I want the upgrade to leave every stored row readable and every mutable
  # row editable,
  # so that the caps bind new writes without locking what is already there.
  #
  # Acceptance criteria:
  # - With a legacy over-cap event note, the event CHECK is removed and the
  #   event can still be confirmed; the upgrade logs the count.
  # - With a legacy over-cap research body, the body CHECK stays NOT VALID
  #   and still refuses a new over-cap entry.
  # - A column without legacy text gets a validated CHECK.
  test "legacy over-cap text keeps mutable rows editable and still binds the log" do
    security = WorldFixtures.create_security!(name: "Northern Pier Holdings", ticker: "NPH")

    {:ok, event} =
      Events.create_event(Actor.owner_ui(), %{
        security_id: security.id,
        kind: "earnings",
        date: ~D[2026-11-20],
        timing: "estimated",
        source_quality: "awareness"
      })

    {:ok, note} =
      Knowledge.append_note(Actor.owner_ui(), %{
        security_id: security.id,
        author: "operator",
        kind: "evidence",
        body: "Short at first.",
        source_quality: "primary",
        as_of: ~D[2026-08-01]
      })

    as_actor(fn ->
      Repo.query!("UPDATE security_events SET note = repeat('x', 10001) WHERE id = $1", [
        event.id
      ])

      # The log refuses an UPDATE, so a legacy body is a new row written past
      # the changeset.
      Repo.query!(
        """
        INSERT INTO security_notes
          (security_id, author, machine_generated, kind, body, source_quality, as_of, inserted_at)
        VALUES ($1, 'operator', false, 'evidence', repeat('y', 20001), 'primary', $2, now())
        """,
        [security.id, ~D[2026-08-02]]
      )
    end)

    log =
      capture_log(fn ->
        assert migration().apply_checks(Repo) == [
                 {"security_notes", "body", :not_valid},
                 {"security_notes", "invalidation_condition", :validated},
                 {"security_events", "note", :removed},
                 {"policy_rule_versions", "note", :validated}
               ]
      end)

    assert log =~ "1 stored security_events.note value(s)"
    assert log =~ "1 stored security_notes.body value(s)"

    assert convalidated("security_events_note_length_check") == :absent
    assert convalidated("security_notes_body_length_check") == false
    assert convalidated("policy_rule_versions_note_length_check") == true

    assert {:ok, confirmed} = Events.update_event(Actor.owner_ui(), event, %{confirmed: true})
    assert confirmed.confirmed

    error =
      assert_raise Postgrex.Error, fn ->
        as_actor(fn ->
          Repo.query!(
            """
            INSERT INTO security_notes
              (security_id, author, machine_generated, kind, body, source_quality, as_of,
               inserted_at)
            VALUES ($1, 'operator', false, 'evidence', repeat('z', 20001), 'primary', $2, now())
            """,
            [security.id, ~D[2026-08-03]]
          )
        end)
      end

    assert error.postgres.code == :check_violation
    assert note.id in Enum.map(Knowledge.list_notes(security.id), & &1.id)
  end
end
