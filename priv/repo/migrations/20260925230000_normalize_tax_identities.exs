defmodule Portfolixir.Repo.Migrations.NormalizeTaxIdentities do
  @moduledoc """
  E25 S6 (#891) review round, G21: the holder and institution values stored
  before the identity rule tightened in this batch are normalised the way a
  write normalises them (NFC, format characters removed, every Unicode space
  collapsed), so the lookups — which normalise the value they are given —
  reach them again, and a bank recorded under two such spellings rolls up
  once. Each changed row is journaled under a `system_job` actor
  (`Portfolixir.Tax.IdentityBackfill`).

  A row whose normalised spelling another row of its table already holds
  under the unique key is **reported here and not written**: which of the
  two rows stays is the operator's choice, made on the Tax page once the
  instance runs. The upgrade does not stop on it.

  - **Idempotent:** a second run finds nothing to normalise.
  - **Not reverted:** the rollback writes nothing; the journal holds every
    row's stored spelling as its before-image.

  `IdentityBackfill.run/1` is referenced from this immutable migration — keep
  its signature stable.
  """
  use Ecto.Migration

  require Logger

  alias Portfolixir.Actor
  alias Portfolixir.Tax.IdentityBackfill

  def up do
    {:ok, report} = IdentityBackfill.run(Actor.system_job("tax_identity_backfill"))

    for refusal <- report.refused do
      Logger.warning(
        "tax identity backfill (E25 S6, G21): " <> IdentityBackfill.describe(refusal)
      )
    end

    :ok
  end

  def down, do: :ok
end
