defmodule Portfolixir.Repo.Migrations.BackfillInferredAssetClasses do
  use Ecto.Migration

  # One-time data backfill: persist inferred asset classes for legacy
  # securities imported before asset-class inference existed, so the
  # securities list display matches the column-backed asset_class filter.
  def up do
    Portfolixir.Catalog.backfill_inferred_asset_classes()
  end

  def down do
    :ok
  end
end
