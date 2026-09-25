defmodule Portfolixir.Journal.Cascades do
  @moduledoc """
  Every foreign key that acts on its own when the row it references is
  deleted (`ON DELETE CASCADE` or `SET NULL`), with the context function that
  removes or rewrites the referencing rows **per row, journaled, before** the
  referenced row goes (E25 S6, F43; the #481 pattern).

  The audit journal's guarantee has to hold on every path that removes or
  changes a row, the database's own cascades included: a cascade the journal
  does not see records only the parent. So each delete path listed here first
  deletes its children through their journaled writers, and the cascade stays
  as a backstop that finds nothing left. The foreign keys onto accounts,
  depots and securities restrict instead, and are ADR-0050 §11's
  (`Portfolixir.Lifecycle.ForeignKeys`).

  `removed_by` is either `{module, function, arity}` — the public delete
  whose call removes the rows, one journal entry each, ahead of the row it
  deletes (for a view's bucket sets: the view's own entry, whose before-image
  carries both sets) — or `:no_delete_path`, when no code path deletes the
  referenced row at all (a portfolio is never deleted; accounts, transactions,
  rules and merge records restrict it).

  `test/invariants/cascade_removals_test.exs` enumerates the real foreign keys
  from `pg_constraint` and fails, naming it, on a cascading key missing here,
  listed twice, gone, reshaped or pointing at a function that does not exist.
  The behaviour is pinned per parent in
  `test/portfolixir/journal/cascade_removals_test.exs` and
  `test/portfolixir/buckets/view_definition_journal_test.exs`.
  """

  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.Targets

  @type removed_by :: {module(), atom(), non_neg_integer()} | :no_delete_path

  @type cascade :: %{
          constraint: String.t(),
          table: String.t(),
          columns: [String.t()],
          references: String.t(),
          removed_by: removed_by(),
          basis: String.t()
        }

  @bucket_delete {Buckets, :delete_bucket, 2}
  @view_delete {Buckets, :delete_view, 2}
  @category_delete {Classifications, :delete_category, 2}
  @classification_delete {Classifications, :delete_classification, 2}
  @plan_delete {Targets, :delete_plan_version, 2}

  @no_portfolio_delete "no path deletes a portfolio: its accounts, transactions, rules and " <>
                         "merge records restrict it"

  @cascades [
    # --- a bucket (ADR-0018 as amended, T-10) -----------------------------
    %{
      constraint: "view_include_buckets_bucket_id_fkey",
      table: "view_include_buckets",
      columns: ["bucket_id"],
      references: "buckets",
      removed_by: @bucket_delete,
      basis: "each view naming the bucket is rewritten through set_view_buckets/4, journaled"
    },
    %{
      constraint: "view_exclude_buckets_bucket_id_fkey",
      table: "view_exclude_buckets",
      columns: ["bucket_id"],
      references: "buckets",
      removed_by: @bucket_delete,
      basis: "each view naming the bucket is rewritten through set_view_buckets/4, journaled"
    },
    %{
      constraint: "securities_account_buckets_bucket_id_fkey",
      table: "securities_account_buckets",
      columns: ["bucket_id"],
      references: "buckets",
      removed_by: @bucket_delete,
      basis: "each depot default set is rewritten through set_depot_default_buckets/3"
    },
    %{
      constraint: "cash_account_buckets_bucket_id_fkey",
      table: "cash_account_buckets",
      columns: ["bucket_id"],
      references: "buckets",
      removed_by: @bucket_delete,
      basis: "each cash-account set is rewritten through set_cash_account_buckets/3"
    },
    %{
      constraint: "position_bucket_overrides_bucket_id_fkey",
      table: "position_bucket_overrides",
      columns: ["bucket_id"],
      references: "buckets",
      removed_by: @bucket_delete,
      basis:
        "each override is rewritten through set_position_override/4; one left with no " <>
          "bucket stays explicit-empty"
    },
    # --- a view (ADR-0018, ADR-0027) ----------------------------------------
    %{
      constraint: "view_include_buckets_view_id_fkey",
      table: "view_include_buckets",
      columns: ["view_id"],
      references: "views",
      removed_by: @view_delete,
      basis: "the view's delete entry carries both bucket sets as its before-image (F45)"
    },
    %{
      constraint: "view_exclude_buckets_view_id_fkey",
      table: "view_exclude_buckets",
      columns: ["view_id"],
      references: "views",
      removed_by: @view_delete,
      basis: "the view's delete entry carries both bucket sets as its before-image (F45)"
    },
    %{
      constraint: "portfolio_target_plans_view_id_fkey",
      table: "portfolio_target_plans",
      columns: ["view_id"],
      references: "views",
      removed_by: @view_delete,
      basis: "each plan scoped to the view, its targets first, through the Targets deletes"
    },
    %{
      constraint: "depot_snapshots_view_id_fkey",
      table: "depot_snapshots",
      columns: ["view_id"],
      references: "views",
      removed_by: @view_delete,
      basis: "each snapshot scoped to the view through Snapshots.delete_snapshot/2"
    },
    # --- a plan version (ADR-0027) ------------------------------------------
    %{
      constraint: "portfolio_targets_plan_id_fkey",
      table: "portfolio_targets",
      columns: ["plan_id"],
      references: "portfolio_target_plans",
      removed_by: @plan_delete,
      basis: "each target of the plan, journaled, before the plan (delete_plan/4 alike)"
    },
    # --- a category ---------------------------------------------------------
    %{
      constraint: "classification_categories_parent_id_fkey",
      table: "classification_categories",
      columns: ["parent_id"],
      references: "classification_categories",
      removed_by: @category_delete,
      basis: "the categories below it, leaves first, each journaled"
    },
    %{
      constraint: "security_category_assignments_category_id_fkey",
      table: "security_category_assignments",
      columns: ["category_id"],
      references: "classification_categories",
      removed_by: @category_delete,
      basis: "each assignment in the subtree through the journaled per-row unassign"
    },
    %{
      constraint: "portfolio_targets_category_id_fkey",
      table: "portfolio_targets",
      columns: ["category_id"],
      references: "classification_categories",
      removed_by: @category_delete,
      basis: "each target filed under the subtree through Targets.delete_targets_for_categories/2"
    },
    # --- a classification ---------------------------------------------------
    %{
      constraint: "classification_categories_classification_id_fkey",
      table: "classification_categories",
      columns: ["classification_id"],
      references: "classifications",
      removed_by: @classification_delete,
      basis: "each category of the tree, leaves first, journaled"
    },
    %{
      constraint: "security_category_assignments_classification_id_fkey",
      table: "security_category_assignments",
      columns: ["classification_id"],
      references: "classifications",
      removed_by: @classification_delete,
      basis: "each stored assignment of the tree through the journaled per-row unassign"
    },
    %{
      constraint: "portfolio_target_plans_classification_id_fkey",
      table: "portfolio_target_plans",
      columns: ["classification_id"],
      references: "classifications",
      removed_by: @classification_delete,
      basis: "each plan of the tree through Targets.delete_plans_for_classification/2"
    },
    %{
      constraint: "portfolio_targets_classification_id_fkey",
      table: "portfolio_targets",
      columns: ["classification_id"],
      references: "classifications",
      removed_by: @classification_delete,
      basis: "each target, with its plan, through Targets.delete_plans_for_classification/2"
    },
    # --- a portfolio: never deleted -----------------------------------------
    %{
      constraint: "portfolio_target_plans_portfolio_id_fkey",
      table: "portfolio_target_plans",
      columns: ["portfolio_id"],
      references: "portfolios",
      removed_by: :no_delete_path,
      basis: @no_portfolio_delete
    },
    %{
      constraint: "portfolio_targets_portfolio_id_fkey",
      table: "portfolio_targets",
      columns: ["portfolio_id"],
      references: "portfolios",
      removed_by: :no_delete_path,
      basis: @no_portfolio_delete
    },
    %{
      constraint: "buckets_source_portfolio_id_fkey",
      table: "buckets",
      columns: ["source_portfolio_id"],
      references: "portfolios",
      removed_by: :no_delete_path,
      basis: @no_portfolio_delete <> "; the seed marker would be set to NULL"
    },
    %{
      constraint: "views_source_portfolio_id_fkey",
      table: "views",
      columns: ["source_portfolio_id"],
      references: "portfolios",
      removed_by: :no_delete_path,
      basis: @no_portfolio_delete <> "; the seed marker would be set to NULL"
    }
  ]

  @doc "Every cascading foreign key, with the delete that removes its rows per row first."
  @spec cascades() :: [cascade()]
  def cascades, do: @cascades
end
