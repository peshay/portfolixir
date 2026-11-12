defmodule Portfolixir.Repo.Migrations.CreateChainReads do
  @moduledoc """
  ADR-0059 §8, §9 (Sprint 29 H3, FR-58): the chain source's health and the
  inputs of the next halving's estimate, **one row per chain with a
  source**, overwritten by each run of `Portfolixir.Chains.Reader`.

  State, not history: no answer body, no block beyond the three timestamps
  of §6, and not journaled (operational state a system job writes four
  times a day, like a feed's health columns). `chain` is one of the
  registry's chains, checked here as well; `last_error` is a short code
  and its reason per source.
  """
  use Ecto.Migration

  def change do
    create table(:chain_reads) do
      add(:chain, :string, size: 32, null: false)
      add(:source_host, :string, size: 255)
      add(:last_tried_at, :utc_datetime)
      add(:last_ok_at, :utc_datetime)
      add(:last_error, :string, size: 512)
      add(:tip_height, :bigint)
      add(:tip_at, :utc_datetime)
      add(:tip_2016_at, :utc_datetime)
      add(:genesis_checked_on, :date)
      add(:genesis_checked_host, :string, size: 255)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:chain_reads, [:chain]))

    # Mirrors Portfolixir.Chains.Registry.names/0 exactly.
    create(
      constraint(:chain_reads, :chain_reads_chain_check,
        check: "chain IN ('bitcoin', 'bitcoin_cash', 'litecoin')"
      )
    )
  end
end
