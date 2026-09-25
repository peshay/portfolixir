defmodule Portfolixir.Repo.Migrations.BackfillAccountFormerNames do
  @moduledoc """
  ADR-0050 §4 third bullet (L2, #884): renames made before `former_names`
  existed are backfilled. Every journaled update of a cash account or a depot
  whose name changed is replayed, in journal order, through the writer rules —
  renaming back consumes a name, and a name another live account of the kind
  in the portfolio carries is not recorded — and each written row is journaled
  under a `system_job` actor (`Portfolixir.Lifecycle.FormerNamesBackfill`).

  A name the guard would refuse is **reported here and not written**:
  typically a zombie account an import created under the old name after the
  rename, repaired by merging it into the renamed account with collapse
  (ADR-0050 §8). A rename older than the accounts' journal arming leaves no
  trace to replay; that limit is stated in ADR-0050 §2.

  - **Additive and idempotent:** the backfill only adds former names, so a
    re-run writes nothing and journals nothing.
  - **Reversible:** the rollback of `add_former_names_to_accounts` drops the
    column; this data step has nothing of its own to undo.

  `FormerNamesBackfill.run/1` is referenced from this immutable migration —
  keep its signature stable.
  """
  use Ecto.Migration

  require Logger

  alias Portfolixir.Actor
  alias Portfolixir.Lifecycle.FormerNamesBackfill

  def up do
    {:ok, report} = FormerNamesBackfill.run(Actor.system_job("former_names_backfill"))

    for refusal <- report.refused do
      Logger.warning(
        "former-name backfill (ADR-0050 §4): " <> FormerNamesBackfill.describe(refusal)
      )
    end

    :ok
  end

  def down, do: :ok
end
