defmodule Portfolixir.Repo.Migrations.MarkPendingDataVersionEvents do
  @moduledoc """
  E25 S6, F47 (#891): a basis's data version is the highest event id, and an
  event id is taken when the bump runs inside the writing transaction, not
  when that transaction commits. A writer that took a lower id and commits
  after another writer leaves the version where the other put it, so a value
  read between the two commits stays current without the late writer's data.

  A bump inside a transaction is therefore marked `pending`, and
  `Portfolixir.Derived.PostCommit` bumps every basis whose pending events have
  become visible — that is, committed — once more, with a fresh id taken after
  the commit, and clears the mark. The mark lives in the table rather than in
  memory so a restart between a commit and its second bump loses nothing.

  The column is added with a constant default, which rewrites no row, and the
  partial index holds only the pending rows the sweep reads.
  """
  use Ecto.Migration

  def change do
    alter table(:derived_data_version_events) do
      add(:pending, :boolean, null: false, default: false)
    end

    create(
      index(:derived_data_version_events, [:id],
        where: "pending",
        name: :derived_data_version_events_pending_index
      )
    )
  end
end
