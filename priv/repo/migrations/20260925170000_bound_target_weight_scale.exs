defmodule Portfolixir.Repo.Migrations.BoundTargetWeightScale do
  @moduledoc """
  E25 S4, G14 (#889): a target weight and a plan's cash target carry at most
  six decimal places (`Portfolixir.Portfolios.Target.weight_scale/0`); the
  changesets refuse a finer one, and this CHECK refuses it at the database,
  for every writer.

  The stored rows are verified before the constraint is trusted: each CHECK is
  added `NOT VALID` — it binds every new or changed row at once — and is then
  validated only when no stored row breaks it. A row stored before the bound
  existed therefore never stops an instance from migrating; it stays readable,
  and the next write of it must meet the bound. Adding and validating a CHECK
  rewrites no row and fires no row trigger, so the journal is untouched.
  """
  use Ecto.Migration

  @checks [
    {"portfolio_targets", "portfolio_targets_target_weight_scale_check", "target_weight"},
    {"portfolio_target_plans", "portfolio_target_plans_cash_target_weight_scale_check",
     "cash_target_weight"}
  ]

  def up do
    for {table, name, column} <- @checks do
      execute("""
      ALTER TABLE #{table}
        ADD CONSTRAINT #{name} CHECK (#{column} = round(#{column}, 6)) NOT VALID
      """)

      execute("""
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM #{table} WHERE #{column} <> round(#{column}, 6)) THEN
          ALTER TABLE #{table} VALIDATE CONSTRAINT #{name};
        END IF;
      END
      $$
      """)
    end
  end

  def down do
    for {table, name, _column} <- @checks do
      execute("ALTER TABLE #{table} DROP CONSTRAINT #{name}")
    end
  end
end
