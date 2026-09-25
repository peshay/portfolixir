defmodule Portfolixir.Lifecycle.ForeignKeys do
  @moduledoc """
  The foreign-key disposition map of ADR-0050 §14: every foreign key whose
  target is `securities`, `cash_accounts` or `securities_accounts`, composite
  ones included, with what a **merge** does with the referencing rows and what
  a **delete** does with them.

  `test/invariants/lifecycle_foreign_key_dispositions_test.exs` enumerates the
  real foreign keys from `pg_constraint` and fails, naming it, on any key
  missing here, listed twice, declared but gone, or declared with another
  shape. A table added later that references one of the three therefore
  fails the build until someone decides both dispositions — otherwise it
  would break every merge (RESTRICT) or lose data silently (CASCADE).

  ## Merge dispositions

    * `:repoint` — every referencing row is re-pointed onto the target, per
      row and journaled, after the removals the kind declares (void internal
      transfers, §5; key-equal pairs by explicit choice, §8; folded anchors,
      §7; collapsed same-day splits, §9).
    * `:follows_repoint` — a composite `(id, portfolio_id)` key: it follows its
      single-column twin, and the same-portfolio guard (§7) keeps it
      satisfied.
    * `:gap_fill` — quotes: the source's move onto dates the target lacks; on
      a collision the target wins and the source's values go into the
      manifest (§9).
    * `:move_unless_target_has` — category assignments: moved where the
      target has none in that classification, otherwise the target's wins
      (§9).
    * `:move_or_drop` — position targets: moved, or deleted and listed where
      they would collide or go stale (§9).
    * `:membership_rule` — position bucket overrides: carried where the
      target holds no rows of the security, dropped where redundant, otherwise
      the merge refuses (§7).
    * `:remove_journaled` — the source's view-bucket links, removed through
      their journaled context function once the guard has found both sets
      equal (§7).
    * `:refuse` — a reference that can neither move nor vanish refuses the
      merge (§9: research notes, ADR-0044 §3; rule versions, ADR-0049 §8).

  ## Delete dispositions

    * `:restrict` — a referenced row is not deletable: the answer is a 409
      with `referenced_by` and the merge remedy (§11), and the database
      refuses the delete itself (RESTRICT or NO ACTION).
    * `:remove_journaled` — removed through its journaled context function
      before the row is deleted (§11); no cascade removes it silently.
  """

  @merge_dispositions [
    :repoint,
    :follows_repoint,
    :gap_fill,
    :move_unless_target_has,
    :move_or_drop,
    :membership_rule,
    :remove_journaled,
    :refuse
  ]

  @delete_dispositions [:restrict, :remove_journaled]

  @type merge_disposition ::
          :repoint
          | :follows_repoint
          | :gap_fill
          | :move_unless_target_has
          | :move_or_drop
          | :membership_rule
          | :remove_journaled
          | :refuse

  @type delete_disposition :: :restrict | :remove_journaled

  @type disposition :: %{
          constraint: String.t(),
          table: String.t(),
          columns: [String.t()],
          references: String.t(),
          merge: merge_disposition(),
          delete: delete_disposition(),
          basis: String.t()
        }

  @leg_basis "§7: S↔T transfers deleted with their hashes retired, key-equal pairs by " <>
               "choice, anchors restated, the rest re-pointed per row; §11: referenced " <>
               "through either leg, the account is not deletable"

  @composite_basis "the composite twin of the single-column key; the same-portfolio " <>
                     "guard keeps it satisfied (§7); it refuses a delete like its twin (§11)"

  @dispositions [
    # --- securities ---------------------------------------------------------
    %{
      constraint: "transactions_security_id_fkey",
      table: "transactions",
      columns: ["security_id"],
      references: "securities",
      merge: :repoint,
      delete: :restrict,
      basis:
        "§9: re-pointed per row after key-equal pairs and same-day, same-ratio splits; " <>
          "§11: a security with bookings is not deletable"
    },
    %{
      constraint: "security_quotes_security_id_fkey",
      table: "security_quotes",
      columns: ["security_id"],
      references: "securities",
      merge: :gap_fill,
      delete: :restrict,
      basis:
        "§9: gap-filled onto the target, the target winning a collision, values in " <>
          "the manifest; a security with quotes is not deletable"
    },
    %{
      constraint: "security_category_assignments_security_id_fkey",
      table: "security_category_assignments",
      columns: ["security_id"],
      references: "securities",
      merge: :move_unless_target_has,
      delete: :remove_journaled,
      basis:
        "§9: moved where the target has none in the classification; §11: removed " <>
          "through the journaled Classifications writers before the row"
    },
    %{
      constraint: "portfolio_targets_security_id_fkey",
      table: "portfolio_targets",
      columns: ["security_id"],
      references: "securities",
      merge: :move_or_drop,
      delete: :remove_journaled,
      basis:
        "§9: moved or deleted and listed, across active, draft and archived plans; " <>
          "removed per row, journaled, before a delete (ADR-0030)"
    },
    %{
      constraint: "position_bucket_overrides_security_id_fkey",
      table: "position_bucket_overrides",
      columns: ["security_id"],
      references: "securities",
      merge: :membership_rule,
      delete: :remove_journaled,
      basis:
        "§7, §9: effective view membership unchanged or the merge refuses; §11: " <>
          "removed through the Buckets context before the row"
    },
    %{
      constraint: "security_identifier_aliases_security_id_fkey",
      table: "security_identifier_aliases",
      columns: ["security_id"],
      references: "securities",
      merge: :repoint,
      delete: :remove_journaled,
      basis:
        "§9: identifier aliases are reassigned to the target; removed per row, " <>
          "journaled, before a delete (ADR-0029 §3)"
    },
    %{
      constraint: "security_notes_security_id_fkey",
      table: "security_notes",
      columns: ["security_id"],
      references: "securities",
      merge: :refuse,
      delete: :restrict,
      basis: "§9 guard and ADR-0044 §3: research notes can neither move nor vanish"
    },
    %{
      constraint: "security_events_security_id_fkey",
      table: "security_events",
      columns: ["security_id"],
      references: "securities",
      merge: :repoint,
      delete: :restrict,
      basis:
        "§9: events move and same-kind, same-date pairs are listed; ADR-0048: a " <>
          "security with events is not deletable"
    },
    %{
      constraint: "policy_rule_versions_security_id_fkey",
      table: "policy_rule_versions",
      columns: ["security_id"],
      references: "securities",
      merge: :refuse,
      delete: :restrict,
      basis: "§9 guard and ADR-0049 §8: a rule version naming the source refuses both"
    },
    # --- cash accounts ------------------------------------------------------
    %{
      constraint: "securities_accounts_cash_account_id_fkey",
      table: "securities_accounts",
      columns: ["cash_account_id"],
      references: "cash_accounts",
      merge: :repoint,
      delete: :restrict,
      basis:
        "§7 step 5: the source's linked depots are re-pointed, journaled; §11: an " <>
          "account a depot links to is not deletable"
    },
    %{
      constraint: "securities_accounts_cash_account_portfolio_fkey",
      table: "securities_accounts",
      columns: ["cash_account_id", "portfolio_id"],
      references: "cash_accounts",
      merge: :follows_repoint,
      delete: :restrict,
      basis: @composite_basis
    },
    %{
      constraint: "transactions_cash_account_id_fkey",
      table: "transactions",
      columns: ["cash_account_id"],
      references: "cash_accounts",
      merge: :repoint,
      delete: :restrict,
      basis: @leg_basis
    },
    %{
      constraint: "transactions_cash_account_portfolio_fkey",
      table: "transactions",
      columns: ["cash_account_id", "portfolio_id"],
      references: "cash_accounts",
      merge: :follows_repoint,
      delete: :restrict,
      basis: @composite_basis
    },
    %{
      constraint: "transactions_counter_cash_account_id_fkey",
      table: "transactions",
      columns: ["counter_cash_account_id"],
      references: "cash_accounts",
      merge: :repoint,
      delete: :restrict,
      basis: @leg_basis
    },
    %{
      constraint: "transactions_counter_cash_account_portfolio_fkey",
      table: "transactions",
      columns: ["counter_cash_account_id", "portfolio_id"],
      references: "cash_accounts",
      merge: :follows_repoint,
      delete: :restrict,
      basis: @composite_basis
    },
    %{
      constraint: "cash_account_buckets_cash_account_id_fkey",
      table: "cash_account_buckets",
      columns: ["cash_account_id"],
      references: "cash_accounts",
      merge: :remove_journaled,
      delete: :remove_journaled,
      basis:
        "§7: equal view-bucket sets or the merge refuses, then the source's links are " <>
          "removed journaled; §11: removed through Buckets before a delete"
    },
    # --- securities accounts (depots) ---------------------------------------
    %{
      constraint: "transactions_securities_account_id_fkey",
      table: "transactions",
      columns: ["securities_account_id"],
      references: "securities_accounts",
      merge: :repoint,
      delete: :restrict,
      basis: @leg_basis
    },
    %{
      constraint: "transactions_securities_account_portfolio_fkey",
      table: "transactions",
      columns: ["securities_account_id", "portfolio_id"],
      references: "securities_accounts",
      merge: :follows_repoint,
      delete: :restrict,
      basis: @composite_basis
    },
    %{
      constraint: "transactions_counter_securities_account_id_fkey",
      table: "transactions",
      columns: ["counter_securities_account_id"],
      references: "securities_accounts",
      merge: :repoint,
      delete: :restrict,
      basis: @leg_basis
    },
    %{
      constraint: "transactions_counter_securities_account_portfolio_fkey",
      table: "transactions",
      columns: ["counter_securities_account_id", "portfolio_id"],
      references: "securities_accounts",
      merge: :follows_repoint,
      delete: :restrict,
      basis: @composite_basis
    },
    %{
      constraint: "securities_account_buckets_securities_account_id_fkey",
      table: "securities_account_buckets",
      columns: ["securities_account_id"],
      references: "securities_accounts",
      merge: :remove_journaled,
      delete: :remove_journaled,
      basis:
        "§7: equal default view-bucket sets or the merge refuses, then the source's " <>
          "links are removed journaled; §11: removed through Buckets before a delete"
    },
    %{
      constraint: "position_bucket_overrides_securities_account_id_fkey",
      table: "position_bucket_overrides",
      columns: ["securities_account_id"],
      references: "securities_accounts",
      merge: :membership_rule,
      delete: :remove_journaled,
      basis:
        "§7: carried where the target holds no rows of the security, dropped where " <>
          "redundant, otherwise refused; §11: removed through Buckets before a delete"
    }
  ]

  @doc "Every foreign key onto the three lifecycle tables, with both dispositions."
  @spec dispositions() :: [disposition()]
  def dispositions, do: @dispositions

  @doc "The closed vocabulary of merge dispositions."
  @spec merge_dispositions() :: [merge_disposition()]
  def merge_dispositions, do: @merge_dispositions

  @doc "The closed vocabulary of delete dispositions."
  @spec delete_dispositions() :: [delete_disposition()]
  def delete_dispositions, do: @delete_dispositions
end
