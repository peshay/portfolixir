defmodule Portfolixir.Repo.Migrations.CreateNewsDigestConsumers do
  @moduledoc """
  ADR-0056 §9 (Sprint 28, N3): `news_digest_consumers`, the confirmed
  position of each named reader of the digest, at least once.

    * `name` — the consumer's name, an identifier of 1 to 64 letters,
      digits or `. _ : / @ + -`, starting with a letter or a digit (the
      shape of a label's model and prompt version): it names a reader, so
      a space, a control or an invisible character could make two
      consumers look like one. Unique.
    * `position` — the confirmed position: the digest of this consumer
      reads the stories that entered their scope after it. It only moves
      forward (the write is `GREATEST`), so of two confirmations that race
      the newer stays.

  **Not journaled, and not armed with the journal-actor guard**
  (`Portfolixir.Journal.Allowlist`, its non-journaled tables): a reader's
  bookmark, which every digest call with a confirmation moves, not a
  record of the operator's data. No foreign key: a consumer names no row. Nothing secret is stored
  here: a cursor is signed with a key derived from the server's
  `SECRET_KEY_BASE` (`Portfolixir.News.DigestCursor`).
  """
  use Ecto.Migration

  def change do
    create table(:news_digest_consumers) do
      add(:name, :string, size: 64, null: false)
      add(:position, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:news_digest_consumers, [:name]))

    create(
      constraint(:news_digest_consumers, :news_digest_consumers_name_check,
        check: "name ~ '^[A-Za-z0-9][A-Za-z0-9._:/@+-]{0,63}$'"
      )
    )
  end
end
