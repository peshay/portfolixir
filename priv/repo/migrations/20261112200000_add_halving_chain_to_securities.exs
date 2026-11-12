defmodule Portfolixir.Repo.Migrations.AddHalvingChainToSecurities do
  @moduledoc """
  ADR-0059 §4 (Sprint 29 H1, FR-58): a security's binding to a registered
  block chain, `halving_chain`, nullable.

  The value is one of `Portfolixir.Chains.Registry`'s chains, checked here as
  well as in the changeset, so a row can never name a chain the registry
  does not know. Nothing sets it by itself: it is written by the operator or
  an agent through the security's update, journaled like every other field
  of the guard-armed table.

  Additive and nullable, no backfill: every stored security reads unbound.
  """
  use Ecto.Migration

  def change do
    alter table(:securities) do
      add(:halving_chain, :string, size: 32)
    end

    # Mirrors Portfolixir.Chains.Registry.names/0 exactly.
    create(
      constraint(:securities, :securities_halving_chain_check,
        check: "halving_chain IN ('bitcoin', 'bitcoin_cash', 'litecoin')"
      )
    )
  end
end
