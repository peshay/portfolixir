defmodule Portfolixir.Repo.Migrations.SeedTaxParameters do
  @moduledoc """
  ADR-0031 §3 (story 19.2): seeds the German statutory tax parameters from 2009
  (introduction of the Abgeltungsteuer) through 2026.

  The seed goes through `Portfolixir.Tax` rather than raw SQL because
  `tax_parameters` is guard-armed (ADR-0017): the insert must commit together
  with its audit-journal entry, recorded here under a `system_job` actor.

  It is a separate migration file from the DDL on purpose — the context writes
  on its own Repo connection and cannot share the DDL transaction (the same
  reason `20260712120000` and `20260712130000` are split).

  - **Idempotent:** an existing `(jurisdiction, tax_year)` row is skipped
    entirely, so a re-run inserts nothing and produces no journal noise, and an
    operator-edited value is never overwritten.
  - **Reversible:** the rollback deletes ONLY rows carrying `built_in = true`;
    parameters the operator added survive.

  `seed_builtin_parameters/1` and `rollback_builtin_parameters/1` are referenced
  from this immutable migration — keep their signatures stable.
  """
  use Ecto.Migration

  alias Portfolixir.Actor
  alias Portfolixir.Tax

  def up do
    {:ok, _summary} = Tax.seed_builtin_parameters(seed_actor())
    :ok
  end

  def down do
    :ok = Tax.rollback_builtin_parameters(seed_actor())
  end

  defp seed_actor, do: Actor.system_job("tax_parameters_seed")
end
