defmodule Portfolixir.Repo.Migrations.RestrictLifecycleMembershipForeignKeys do
  @moduledoc """
  ADR-0050 §11 and §16 invariant 11: no lifecycle path removes a row by
  cascade.

  Seven foreign keys onto `cash_accounts`, `securities_accounts` and
  `securities` deleted their referencing rows silently: a cash account's
  bucket links, a depot's default buckets and position overrides, and a
  security's position overrides, category assignments, position targets and
  identifier aliases. The journal recorded the deleted parent and nothing of
  the memberships it took with it, which ADR-0017 and ADR-0024 point 4 (view
  membership is retroactive) do not allow.

  The hardened delete path (`Portfolixir.Lifecycle.Delete`) now removes each
  of them through its journaled context function before the row. This
  migration turns the seven keys to `ON DELETE RESTRICT`, so the database
  refuses a delete that would still take a membership with it: a future path
  that forgets the journaled removal fails loudly instead of losing the
  membership. The constraint names are kept, because the disposition map
  (`Portfolixir.Lifecycle.ForeignKeys`) and the delete's declared constraints
  name them.
  """
  use Ecto.Migration

  @keys [
    {"cash_account_buckets", "cash_account_id", "cash_accounts"},
    {"securities_account_buckets", "securities_account_id", "securities_accounts"},
    {"position_bucket_overrides", "securities_account_id", "securities_accounts"},
    {"position_bucket_overrides", "security_id", "securities"},
    {"security_category_assignments", "security_id", "securities"},
    {"portfolio_targets", "security_id", "securities"},
    {"security_identifier_aliases", "security_id", "securities"}
  ]

  def up, do: Enum.each(@keys, &replace_key(&1, "RESTRICT"))

  def down, do: Enum.each(@keys, &replace_key(&1, "CASCADE"))

  defp replace_key({table, column, references}, action) do
    name = "#{table}_#{column}_fkey"

    execute("""
    ALTER TABLE #{table}
      DROP CONSTRAINT #{name},
      ADD CONSTRAINT #{name}
        FOREIGN KEY (#{column}) REFERENCES #{references} (id)
        ON DELETE #{action};
    """)
  end
end
