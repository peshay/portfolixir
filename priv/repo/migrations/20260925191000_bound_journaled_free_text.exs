defmodule Portfolixir.Repo.Migrations.BoundJournaledFreeText do
  @moduledoc """
  E25 S6, G02 (#891): every other free-text column gets a code-point cap in
  the database, behind the same cap in its changeset
  (`Portfolixir.Input.Text.free_text_max/0`; a category's description keeps
  its 2000; the numbers are written out here because a migration is frozen),
  and a security's attributes get a size bound: the journal copies these rows
  whole on every change, so an unbounded note or map grew the journal too.

  The attributes CHECK bounds the jsonb's text form at twice the byte bound
  the changeset puts on the compact JSON (`Text.attributes_max_bytes/0`), a
  size a map the changeset accepts never reaches.

  Each CHECK is added `NOT VALID` and validated when no stored row breaks it.
  Every table here is mutable, and PostgreSQL checks a `NOT VALID` constraint
  against the whole new row on every update, so where a stored row breaks it
  the CHECK is removed and the upgrade logs how many rows are over (the
  Sprint 16 review round's lesson on locked rows): the changesets still
  refuse an over-cap value on every write, and no stored row is changed.
  Adding, validating or removing a CHECK rewrites no row and fires no row
  trigger, so the journal is untouched.
  """
  use Ecto.Migration

  require Logger

  @free_text 10_000

  @checks [
    {"portfolios", "notes", "char_length(notes) <= #{@free_text}"},
    {"cash_accounts", "notes", "char_length(notes) <= #{@free_text}"},
    {"securities_accounts", "notes", "char_length(notes) <= #{@free_text}"},
    {"transactions", "notes", "char_length(notes) <= #{@free_text}"},
    {"securities", "note", "char_length(note) <= #{@free_text}"},
    {"classifications", "description", "char_length(description) <= #{@free_text}"},
    {"classification_categories", "description", "char_length(description) <= 2000"},
    {"tax_profiles", "note", "char_length(note) <= #{@free_text}"},
    {"allowance_orders", "note", "char_length(note) <= #{@free_text}"},
    {"tax_statement_snapshots", "note", "char_length(note) <= #{@free_text}"},
    {"securities", "attributes", "octet_length(attributes::text) <= 131072"}
  ]

  def up do
    apply_checks(repo())
  end

  def down do
    for {table, column, _predicate} <- @checks do
      execute("ALTER TABLE #{table} DROP CONSTRAINT IF EXISTS #{table}_#{column}_length_check")
    end
  end

  @doc """
  Adds each CHECK `NOT VALID` and settles it on `repo`: validated when no
  stored row breaks it, removed otherwise. Returns
  `[{table, column, :validated | :removed}]`.
  """
  def apply_checks(repo) do
    for {table, column, predicate} <- @checks do
      name = "#{table}_#{column}_length_check"

      repo.query!("ALTER TABLE #{table} ADD CONSTRAINT #{name} CHECK (#{predicate}) NOT VALID")

      {table, column, settle(repo, table, column, name, predicate)}
    end
  end

  defp settle(repo, table, column, name, predicate) do
    %{rows: [[over]]} = repo.query!("SELECT count(*) FROM #{table} WHERE NOT (#{predicate})")

    if over == 0 do
      repo.query!("ALTER TABLE #{table} VALIDATE CONSTRAINT #{name}")
      :validated
    else
      repo.query!("ALTER TABLE #{table} DROP CONSTRAINT #{name}")

      Logger.warning(
        "free-text bound (E25 S6, G02): #{over} stored #{table}.#{column} value(s) are past " <>
          "the bound, so the database check is not added; every new write still meets it, " <>
          "and no stored row was changed."
      )

      :removed
    end
  end
end
