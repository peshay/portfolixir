defmodule Portfolixir.Repo.Migrations.SeedPortfolioScopeBuckets do
  @moduledoc """
  ADR-0024 (epic story 2, modifications 2 + 6): one-time data migration that
  converts existing portfolios into the buckets/views model — per portfolio
  one exclusive-dimension ("scope") bucket plus one fully editable view over
  it, with every depot and cash account assigned to its bucket.

  The seed goes through `Portfolixir.Buckets` rather than raw SQL because the
  `buckets` table is guard-armed (ADR-0017): bucket creations and account
  assignments must commit together with their audit-journal entries, recorded
  here under a `system_job` actor. View definitions stay unjournaled per
  ADR-0018 §5.

  - **Idempotent:** seeded records carry `source_portfolio_id`; an
    already-seeded portfolio is skipped, so re-running is a no-op.
  - **Reversible:** the rollback deletes ONLY records carrying the seed
    marker; user-created buckets, views, and assignments survive.
  """
  use Ecto.Migration

  alias Portfolixir.Actor
  alias Portfolixir.Buckets

  def up do
    {:ok, _summary} = Buckets.seed_portfolio_scope_buckets(seed_actor())
    :ok
  end

  def down do
    :ok = Buckets.rollback_portfolio_scope_seed(seed_actor())
  end

  defp seed_actor, do: Actor.system_job("portfolio_scope_seed")
end
