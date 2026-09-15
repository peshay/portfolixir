defmodule Portfolixir.Repo.Migrations.AddIsBenchmarkToSecurities do
  use Ecto.Migration

  # ADR-0046 §1 (#572): a benchmark is a catalog security carrying this flag,
  # fed by the existing quote sync — an index proxied by an ETF, gold by an
  # ETC — so the comparison has a price series without a new quote source.
  # Additive and off by default; the flag is never offered in a booking form
  # and is left alone by the catalog-hygiene checks, and a flagged security
  # may still be held.
  def change do
    alter table(:securities) do
      add(:is_benchmark, :boolean, null: false, default: false)
    end
  end
end
