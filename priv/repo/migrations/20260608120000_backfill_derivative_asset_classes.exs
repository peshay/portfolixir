defmodule Portfolixir.Repo.Migrations.BackfillDerivativeAssetClasses do
  use Ecto.Migration

  # One-time data backfill: the asset-class inference now recognises
  # certificate and leverage products (warrants, knock-outs, factor, discount,
  # bonus, express certificates, reverse convertibles). Re-run the inference for
  # securities that still have no persisted class so the existing portfolio is
  # sorted into the new categories. Securities with a class already set (manual
  # or previously inferred) are left untouched.
  def up do
    Portfolixir.Catalog.backfill_inferred_asset_classes()
  end

  def down do
    :ok
  end
end
