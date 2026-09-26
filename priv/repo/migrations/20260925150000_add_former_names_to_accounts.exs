defmodule Portfolixir.Repo.Migrations.AddFormerNamesToAccounts do
  @moduledoc """
  ADR-0050 §4 second bullet (L2, #884): `cash_accounts` and
  `securities_accounts` gain `former_names text[] NOT NULL DEFAULT '{}'` — the
  names an account was known by, which the importer's resolution reads after
  the live name (exact live name first, then former name).

  Both tables are already journal-armed (`arm_accounts_journal`), so every
  later change of the column is journaled with its before and after. Adding a
  column with a constant default rewrites no row and fires no row trigger.

  There is deliberately **no unique index**: a former name sits in an array
  that no plain index keeps distinct across rows or from another account's
  live name, and existing duplicate names would have to be migrated first. The
  name guard (`Portfolixir.Lifecycle.AccountNames`) is the single enforcement
  point, under a transaction-scoped advisory lock.

  The journaled renames made before this column existed are replayed into it
  by the next migration (`backfill_account_former_names`), a separate file
  because the backfill writes through the application's own connection, which
  cannot share this DDL transaction (the `20260712120000`/`20260712130000`
  precedent).
  """
  use Ecto.Migration

  def change do
    for table <- [:cash_accounts, :securities_accounts] do
      alter table(table) do
        add(:former_names, {:array, :text}, null: false, default: [])
      end
    end
  end
end
