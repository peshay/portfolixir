defmodule Portfolixir.Repo.Migrations.WidenSourceUrlOnSecurityNotesAndEvents do
  @moduledoc """
  ADR-0056 E2 (#1443, Sprint 29 N2): an entry's and an event's link hold
  what the news parser accepts. `security_notes.source_url` and
  `security_events.source_url` widen from `character varying(255)` to
  `character varying(2048)`, the parser's own cap, so an aggregator's
  redirect link (often 250 to 400 characters) can become a research entry's
  or an event's source.

  Widening a `character varying` is a catalog change in PostgreSQL: no
  stored row is rewritten, no index rebuilt and no row trigger fires, so the
  append-only research log stays as it was written. The changesets bound
  the link at the same 2,048 code points (`Portfolixir.Input.Text`).

  The `down` narrows both columns back to 255 and is refused by the
  database while a longer link is stored: a rollback never cuts a link.
  """
  use Ecto.Migration

  def change do
    for table <- [:security_notes, :security_events] do
      alter table(table) do
        modify(:source_url, :string, size: 2048, from: {:string, size: 255})
      end
    end
  end
end
