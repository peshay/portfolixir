defmodule Portfolixir.Repo.Migrations.AddBondMasterDataToSecurities do
  @moduledoc """
  #330 (ADR-0052 §1): a bond's master data as six typed columns on
  `securities` — the coupon in percent of face per year, its payment
  frequency, the maturity, the optional issue date, the denomination and the
  denomination's currency.

  Every column is nullable and added without a default, a constraint or a
  backfill: the stored rows keep NULL, which reads as "not entered", so no
  row an older instance holds can stop the upgrade. The rules live in
  `Portfolixir.Catalog.Security.changeset/2`, the one writer of the table,
  as they do for the security's other closed sets.
  """
  use Ecto.Migration

  def change do
    alter table(:securities) do
      add(:coupon_rate, :decimal, precision: 9, scale: 6)
      add(:coupon_frequency, :string)
      add(:maturity_date, :date)
      add(:issue_date, :date)
      add(:face_value, :decimal, precision: 20, scale: 6)
      add(:face_value_currency_code, :string)
    end
  end
end
