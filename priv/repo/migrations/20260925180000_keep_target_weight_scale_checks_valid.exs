defmodule Portfolixir.Repo.Migrations.KeepTargetWeightScaleChecksValid do
  @moduledoc """
  E25 S4, G14 (#889), from the S3/S4 review round: the database's
  weight-scale CHECK is kept only where the stored weights meet it.

  `20260925170000_bound_target_weight_scale` added each CHECK `NOT VALID`
  whatever the tables held, expecting a row stored before the bound to stay
  readable until its next write. PostgreSQL checks a `NOT VALID` constraint
  against the whole new row on every update, though, so a plan carrying such
  a weight could no longer be archived, renamed or saved even when the write
  left the weight alone.

  `reconcile/1` settles each CHECK the earlier migration left unvalidated:

    * no stored row finer than six decimal places — the CHECK is validated
      and binds every writer;
    * otherwise the CHECK is removed, and the upgrade logs how many weights
      are finer and how to round them (saving the plan in the SOLL editor
      does). The changesets still refuse a finer weight on every write,
      and a duplicate or a SOLL save rounds a stored one to the six places a
      plan holds. No stored weight is changed by the upgrade.

  A CHECK already validated, or absent, is left as it is, so the step is
  idempotent. Adding, validating or removing a CHECK rewrites no row and fires
  no row trigger, so the journal is untouched.
  """
  use Ecto.Migration

  require Logger

  @checks [
    {"portfolio_targets", "portfolio_targets_target_weight_scale_check", "target_weight"},
    {"portfolio_target_plans", "portfolio_target_plans_cash_target_weight_scale_check",
     "cash_target_weight"}
  ]

  @scale 6

  def up do
    reconcile(repo())
  end

  # The earlier migration's own down removes the constraints; there is
  # nothing for this step to restore.
  def down, do: :ok

  @doc """
  Validates or removes each weight-scale CHECK left `NOT VALID`, on `repo`.
  Returns `[{table, :validated | :removed | :unchanged}]`.
  """
  def reconcile(repo) do
    for {table, name, column} <- @checks do
      {table, reconcile_check(repo, table, name, column)}
    end
  end

  defp reconcile_check(repo, table, name, column) do
    case repo.query!("SELECT convalidated FROM pg_constraint WHERE conname = $1", [name]) do
      %{rows: [[false]]} -> settle(repo, table, name, column)
      _validated_or_absent -> :unchanged
    end
  end

  defp settle(repo, table, name, column) do
    %{rows: [[finer]]} =
      repo.query!("SELECT count(*) FROM #{table} WHERE #{column} <> round(#{column}, #{@scale})")

    if finer == 0 do
      repo.query!("ALTER TABLE #{table} VALIDATE CONSTRAINT #{name}")
      :validated
    else
      repo.query!("ALTER TABLE #{table} DROP CONSTRAINT #{name}")

      Logger.warning(
        "target weight scale (E25 S4, G14): #{finer} stored #{column} value(s) in #{table} " <>
          "carry more than #{@scale} decimal places, so the database check is not added; " <>
          "every new write still meets the bound, and saving a plan in the SOLL editor " <>
          "rounds its weights."
      )

      :removed
    end
  end
end
