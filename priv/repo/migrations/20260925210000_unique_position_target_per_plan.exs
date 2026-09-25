defmodule Portfolixir.Repo.Migrations.UniquePositionTargetPerPlan do
  @moduledoc """
  E25 S6 (#891), G13: a plan carries one position row per security.

  `Portfolixir.Portfolios.Targets` checked the rule with a read that held
  nothing, so two writes filing one security under two categories of a plan
  could both pass the check and both insert. A partial unique index on
  `(plan_id, security_id) WHERE security_id IS NOT NULL` now holds the rule
  in the database, and the writer maps its violation to the
  duplicate-position refusal (422) it already answered for the check.

  An instance that already holds such a pair stops the upgrade with an error
  naming each plan, security and row: which row stays is the operator's
  choice, never the migration's. The release migrates before it starts, so
  the remedy the error names works without it (E25 S6 review round, D1):
  restore the backup taken before the upgrade, start the previous release on
  it, remove all but one row of each pair there (the plan editor, or
  `DELETE /api/v1/portfolios/:portfolio_id/position_targets/:category_id/
  :security_id`, both journaled), and upgrade again. Creating an index
  rewrites no row and fires no row trigger, so the journal is untouched.
  """
  use Ecto.Migration

  @index "portfolio_targets_plan_security_index"

  def up do
    :ok = create_index(repo())
  end

  def down do
    execute("DROP INDEX IF EXISTS #{@index}")
  end

  @doc """
  Creates the index on `repo`, or raises naming every `(plan, security)`
  pair that already holds more than one position row.
  """
  def create_index(repo) do
    %{rows: duplicates} =
      repo.query!("""
      SELECT plan_id, security_id, array_agg(category_id ORDER BY category_id),
             array_agg(id ORDER BY category_id)
      FROM portfolio_targets
      WHERE security_id IS NOT NULL
      GROUP BY plan_id, security_id
      HAVING count(*) > 1
      ORDER BY plan_id, security_id
      """)

    if duplicates != [] do
      raise duplicate_message(duplicates)
    end

    repo.query!("""
    CREATE UNIQUE INDEX #{@index}
      ON portfolio_targets (plan_id, security_id)
      WHERE security_id IS NOT NULL
    """)

    :ok
  end

  defp duplicate_message(duplicates) do
    pairs =
      Enum.map_join(duplicates, "; ", fn [plan_id, security_id, category_ids, row_ids] ->
        "plan #{plan_id}, security #{security_id} (categories #{Enum.join(category_ids, ", ")}; " <>
          "portfolio_targets rows #{Enum.join(row_ids, ", ")})"
      end)

    "portfolio_targets holds more than one position row for one security in a plan: " <>
      pairs <>
      ". A plan carries one position row per security (E25 S6, G13), and which row stays " <>
      "is your choice. This release cannot start until the rows are gone: restore the " <>
      "backup taken before this upgrade, start the previous release on it, remove all but " <>
      "one row of each pair there (the plan editor, or DELETE " <>
      "/api/v1/portfolios/:portfolio_id/position_targets/:category_id/:security_id), take " <>
      "a new backup and upgrade again (docs/home-deployment.md, \"Upgrade\")."
  end
end
