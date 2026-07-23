defmodule Portfolixir.Repo.Migrations.CreateSecurityIdentifierAliases do
  @moduledoc """
  Identifier aliases for recorded ISIN changes (ADR-0029 §3).

  Recording an ISIN change moves the security's current ISIN into one of these
  rows and writes the new ISIN onto the same security row, both journaled in one
  transaction. The import ladder's ISIN tier consults current ISINs first, then
  this table, so old exports keep matching after a corporate-action ISIN change.

  `former_isin` carries a unique index (one former ISIN can alias only one
  security). The cross-table half of the invariant — no live `securities.isin`
  may equal any alias, and vice versa — cannot live in one index; it is enforced
  as a serialized application check inside the journaled write transactions
  (ADR-0029 §3 bidirectional guard).

  Alias rows delete with their security (`on_delete: :delete_all`); the
  security's existing delete guard (no deletion while transactions or quotes
  exist) protects history. The table is guard-armed like `securities`
  (ADR-0017): every write must run through `Portfolixir.Journal.record/3`.
  """
  use Ecto.Migration

  def change do
    create table(:security_identifier_aliases) do
      add(:security_id, references(:securities, on_delete: :delete_all), null: false)
      add(:former_isin, :string, null: false)
      add(:changed_on, :date, null: false)
      add(:note, :string)

      timestamps()
    end

    create(
      unique_index(:security_identifier_aliases, [:former_isin],
        name: :security_identifier_aliases_former_isin_unique_index
      )
    )

    create(index(:security_identifier_aliases, [:security_id]))

    execute(
      """
      CREATE TRIGGER security_identifier_aliases_require_journal_actor
        BEFORE INSERT OR UPDATE OR DELETE ON security_identifier_aliases
        FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
      """,
      """
      DROP TRIGGER IF EXISTS security_identifier_aliases_require_journal_actor
        ON security_identifier_aliases;
      """
    )
  end
end
