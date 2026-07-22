defmodule Portfolixir.Repo.Migrations.AddTreatQuotesAsRawToSecurities do
  use Ecto.Migration

  # ADR-0028 §2 escape hatch: a per-security override flag ("treat this synced
  # series as raw") for provider listings that never — or only belatedly —
  # back-adjust their history after a split. With the flag set, the quote
  # adjustment engine applies the raw basis (divide pre-split closes by the
  # cumulative ratio of later splits) to that security's synced rows too,
  # instead of trusting them as an already-adjusted provider mirror.
  def change do
    alter table(:securities) do
      add(:treat_quotes_as_raw, :boolean, null: false, default: false)
    end
  end
end
