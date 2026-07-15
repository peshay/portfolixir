defmodule Portfolixir.Repo.Migrations.AddBucketScopeDimensionAndSeedMarkers do
  @moduledoc """
  ADR-0024 (epic story 2, modification 2): buckets gain the exclusive `"scope"`
  dimension — a depot/cash account carries at most one scope bucket (enforced
  at the `Portfolixir.Buckets` context boundary), while `"tag"` buckets stay
  free overlapping tags.

  Both `buckets` and `views` also gain a `source_portfolio_id` seed marker for
  the portfolio -> bucket/view data migration that follows in the next
  migration file (the seed runs on a separate Repo connection, so it cannot
  share this migration's DDL transaction): NULL means user-created; a set id
  links the record to the portfolio it was seeded from, so the data
  migration's rollback removes only seeded records.

  Additive with explicit defaults — every existing bucket becomes a `"tag"`
  bucket and every existing record is user-created (`NULL` marker).
  """
  use Ecto.Migration

  def change do
    alter table(:buckets) do
      add(:dimension, :string, null: false, default: "tag")
      add(:source_portfolio_id, references(:portfolios, on_delete: :nilify_all))
    end

    alter table(:views) do
      add(:source_portfolio_id, references(:portfolios, on_delete: :nilify_all))
    end
  end
end
