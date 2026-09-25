defmodule Portfolixir.Repo.Migrations.BoundAppendOnlyFreeText do
  @moduledoc """
  E25 S6, G01 (#891): the free text of the append-only and fully journaled
  knowledge records gets a code-point cap in the database, behind the same
  cap in each changeset (`Portfolixir.Input.Text.entry_body_max/0` and
  `free_text_max/0`; the numbers are written out here because a migration is
  frozen): a research-log entry's body and invalidation condition, an
  event's note and a policy-rule version's note.

  Each CHECK is added `NOT VALID` — it binds every new or changed row at once
  — and is validated when no stored row breaks it. When one does, the
  Sprint 16 review round's lesson on a `NOT VALID` CHECK holds (it is checked
  against the whole new row on every update, so it would lock a mutable row
  stored before the cap): on the append-only research log, whose rows are
  never updated, the CHECK stays `NOT VALID` and binds every new entry; on
  the mutable tables it is removed, and the upgrade logs how many rows are
  over the cap. The changesets refuse an over-cap value on every write either
  way, and no stored row is changed. Adding, validating or removing a CHECK
  rewrites no row and fires no row trigger, so the journal is untouched.
  """
  use Ecto.Migration

  require Logger

  @checks [
    {"security_notes", "body", 20_000, :append_only},
    {"security_notes", "invalidation_condition", 10_000, :append_only},
    {"security_events", "note", 10_000, :mutable},
    {"policy_rule_versions", "note", 10_000, :mutable}
  ]

  def up do
    apply_checks(repo())
  end

  def down do
    for {table, column, _max, _kind} <- @checks do
      execute("ALTER TABLE #{table} DROP CONSTRAINT IF EXISTS #{table}_#{column}_length_check")
    end
  end

  @doc """
  Adds each length CHECK `NOT VALID` and settles it on `repo`: validated
  when no stored row breaks it, kept `NOT VALID` on the append-only log,
  removed on a mutable table. Returns `[{table, column, :validated |
  :not_valid | :removed}]`.
  """
  def apply_checks(repo) do
    for {table, column, max, kind} <- @checks do
      name = "#{table}_#{column}_length_check"

      repo.query!("""
      ALTER TABLE #{table}
        ADD CONSTRAINT #{name} CHECK (char_length(#{column}) <= #{max}) NOT VALID
      """)

      {table, column, settle(repo, table, column, name, max, kind)}
    end
  end

  defp settle(repo, table, column, name, max, kind) do
    %{rows: [[over]]} =
      repo.query!("SELECT count(*) FROM #{table} WHERE char_length(#{column}) > #{max}")

    cond do
      over == 0 ->
        repo.query!("ALTER TABLE #{table} VALIDATE CONSTRAINT #{name}")
        :validated

      kind == :append_only ->
        warn(table, column, over, max, "binds every new row")
        :not_valid

      true ->
        repo.query!("ALTER TABLE #{table} DROP CONSTRAINT #{name}")
        warn(table, column, over, max, "is not added")
        :removed
    end
  end

  defp warn(table, column, over, max, outcome) do
    Logger.warning(
      "free-text cap (E25 S6, G01): #{over} stored #{table}.#{column} value(s) are longer " <>
        "than #{max} characters, so the database check #{outcome}; every new write still " <>
        "meets the cap, and no stored row was changed."
    )
  end
end
