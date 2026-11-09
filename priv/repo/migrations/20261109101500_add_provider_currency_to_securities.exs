defmodule Portfolixir.Repo.Migrations.AddProviderCurrencyToSecurities do
  @moduledoc """
  #1415 (Sprint 28 Q3, OQ-2 of the triage of 2026-11-07): the currency the
  quote provider stated for a security, `provider_currency`, and when the
  sync that stored it read it, `provider_currency_at`. The quote sync writes
  both whenever it reads a currency that differs from the stored one, a
  refused answer's too (#1411); the `currency_mismatch` data-quality set
  reads them.

  Additive and nullable, no backfill: a security synced before this
  migration reads null, not yet known, until its next sync reads a currency,
  and null is never a mismatch. Three characters, as ISO 4217 codes and the
  minor-unit codes Yahoo states (`GBp`, `ZAc`, `ILA`) are; the changeset
  keeps anything else out.
  """
  use Ecto.Migration

  def change do
    alter table(:securities) do
      add(:provider_currency, :string, size: 3)
      add(:provider_currency_at, :utc_datetime)
    end
  end
end
