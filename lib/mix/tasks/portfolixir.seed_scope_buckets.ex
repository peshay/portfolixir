defmodule Mix.Tasks.Portfolixir.SeedScopeBuckets do
  @shortdoc "Seeds the ADR-0024 portfolio scope buckets and views (idempotent)"

  @moduledoc """
  Runs the ADR-0024 portfolio migration seed on demand:

      mix portfolixir.seed_scope_buckets

  For installs that migrated an **empty** database and restored their data
  afterwards (fix round): the schema migration's one-time seed found no
  portfolios back then, so the restored portfolios never got their scope
  bucket + view pair. This task re-runs exactly the same seed —
  `Portfolixir.Buckets.seed_portfolio_scope_buckets/1` under the
  `portfolio_scope_seed` system actor — and prints the summary. It is
  idempotent: already-seeded portfolios are skipped, so running it twice (or
  on an already-migrated install) changes nothing.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    actor = Portfolixir.Actor.system_job("portfolio_scope_seed")

    case Portfolixir.Buckets.seed_portfolio_scope_buckets(actor) do
      {:ok, summary} ->
        Mix.shell().info("""
        Portfolio scope seed complete:
          buckets created:        #{summary.buckets_created}
          views created:          #{summary.views_created}
          accounts tagged:        #{summary.accounts_tagged}
          skipped (other scope):  #{summary.skipped_existing_scope}
        """)

      {:error, %{portfolio_id: id, portfolio_name: name, reason: reason}} ->
        Mix.raise("Seeding failed for portfolio #{inspect(name)} (id #{id}): #{inspect(reason)}")
    end
  end
end
