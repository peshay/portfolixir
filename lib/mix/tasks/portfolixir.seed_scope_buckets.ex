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

  The seed is frozen to its migration's schema
  (`Portfolixir.Buckets.ScopeSeed`, #1042), where no derived value exists, so
  it invalidates none. This task runs at head, where they do: after a seed
  that created or tagged anything it bumps the data version of every
  portfolio, and the global one (`Portfolixir.Derived.DataVersion.bump/1`),
  as the journal bumps after a bucket or assignment write.
  """

  use Mix.Task

  alias Portfolixir.Derived.DataVersion

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    actor = Portfolixir.Actor.system_job("portfolio_scope_seed")

    case Portfolixir.Buckets.seed_portfolio_scope_buckets(actor) do
      {:ok, summary} ->
        invalidate_derived(summary)

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

  # A seeded bucket or a tagged account changes which holdings a view
  # reads; a write the journal cannot narrow widens to every portfolio.
  defp invalidate_derived(%{buckets_created: 0, views_created: 0, accounts_tagged: 0}), do: :ok
  defp invalidate_derived(_summary), do: DataVersion.bump(:all)
end
