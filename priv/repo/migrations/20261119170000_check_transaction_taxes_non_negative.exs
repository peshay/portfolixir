defmodule Portfolixir.Repo.Migrations.CheckTransactionTaxesNonNegative do
  @moduledoc """
  Sprint 30 plan, A4 (#1356; risk tier: stored data): a transaction's
  `taxes` is never negative. `Portfolixir.Ledger.Transaction` refuses a
  negative value (a refunded tax is booked as its own `tax_refund`
  transaction, so the ledger keeps one representation of a refund);
  `transactions_taxes_non_negative_check` now refuses it at the database,
  for every writer, and the changeset maps the constraint to the same error.

  The stored rows are counted first. No row should hold negative taxes, since
  every writer of the application goes through the changeset that refuses
  them, so an instance that holds one has a row some writer stored past it: the upgrade stops with an error naming
  each such transaction by id, and changes no row. How a row is corrected
  (its taxes set to zero or to their positive amount, a refund booked as a
  `tax_refund`) is the operator's choice, never the migration's. The release
  migrates before it starts, so the remedy the error names works without it:
  restore the backup taken before the upgrade, start the previous release on
  it, correct each named row there (the transactions page, or
  `PATCH /api/v1/transactions/:id`, both journaled), and upgrade again.
  Adding a CHECK rewrites no row and fires no row trigger, so the journal is
  untouched.
  """
  use Ecto.Migration

  @constraint "transactions_taxes_non_negative_check"

  def up do
    :ok = add_check(repo())
  end

  def down do
    execute("ALTER TABLE transactions DROP CONSTRAINT IF EXISTS #{@constraint}")
  end

  @doc """
  Adds the taxes CHECK on `repo`, or raises naming every transaction whose
  taxes are already negative.
  """
  def add_check(repo) do
    %{rows: rows} = repo.query!("SELECT id FROM transactions WHERE taxes < 0 ORDER BY id")

    if rows != [] do
      raise negative_taxes_message(Enum.map(rows, fn [id] -> id end))
    end

    repo.query!("ALTER TABLE transactions ADD CONSTRAINT #{@constraint} CHECK (taxes >= 0)")

    :ok
  end

  defp negative_taxes_message(ids) do
    rows = Enum.map_join(ids, ", ", &"transaction ##{&1}")

    "transactions holds negative taxes: " <>
      rows <>
      ". A transaction's taxes are never negative: a refunded tax is booked as a separate " <>
      "tax_refund transaction whose positive gross_amount credits the cash account " <>
      "(Sprint 30, A4), and how each row is corrected is your choice. This release cannot " <>
      "start until the rows are corrected: restore the backup taken before this upgrade, " <>
      "start the previous release on it, set each named row's taxes to zero or to their " <>
      "positive amount and book any refund as a tax_refund there (the transactions page, " <>
      "or PATCH /api/v1/transactions/:id), take a new backup and upgrade again " <>
      "(docs/home-deployment.md, \"Upgrade\")."
  end
end
