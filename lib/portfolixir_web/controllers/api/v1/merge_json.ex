defmodule PortfolixirWeb.Api.V1.MergeJSON do
  @moduledoc """
  The payloads of the lifecycle merges (ADR-0050 §7, §10, §12): a merge
  preview (a cash account's, a depot's) and a merge record. Every financial decimal and every quantity is
  a string; dates are ISO 8601; the preview's outcomes are keyed by the
  value of `collapse_key_equal` they follow from, `"false"` and `"true"`.
  """

  alias Portfolixir.Lifecycle.MergeRecord
  alias PortfolixirWeb.Api.V1.JSON

  @balance_basis "balance: the fold of every booking of the account, as GET " <>
                   "/api/v1/cash_accounts reports it. A restated anchor: its stated amount " <>
                   "plus the other account's balance at the end of that day, from that " <>
                   "account's bookings before the merge; on a day both accounts carry " <>
                   "anchors, the target's last one holds both and the others are deleted."

  @reimport_note "After the merge the source's name and former names are former names of " <>
                   "the target: a Portfolio Performance import naming them books onto the " <>
                   "target, and a re-import of an export already applied creates nothing, " <>
                   "because every row the merge removes has its content hash retired."

  @doc "A cash-account merge preview."
  def cash_preview(preview) do
    %{
      kind: "cash_account",
      plan_digest: preview.plan_digest,
      source: account(preview.source),
      target: account(preview.target),
      guards: Enum.map(preview.guards, &guard/1),
      internal_transfers: Enum.map(preview.internal_transfers, &transfer/1),
      key_equal_pairs: Enum.map(preview.key_equal_pairs, &pair/1),
      choice_required: preview.choice_required,
      linked_depots: preview.linked_depots,
      former_names: %{
        appended: preview.former_names.appended,
        not_kept: Enum.map(preview.former_names.not_kept, &not_kept/1),
        after: preview.former_names.after
      },
      outcome_by_collapse_key_equal: %{
        "false" => outcome(Map.fetch!(preview.outcomes, false)),
        "true" => outcome(Map.fetch!(preview.outcomes, true))
      },
      balance_basis: @balance_basis,
      reimport_note: @reimport_note
    }
  end

  @positions_basis "quantity: the position fold of the depot's bookings and its " <>
                     "portfolio's splits, each split scaling the position once, rounded at " <>
                     "volume scale 6 (ADR-0028 §3). cost_basis and avg_cost: the moving-average " <>
                     "cost GET /api/v1/portfolios/:id/holdings states, in the security's " <>
                     "currency, fees and taxes not included; after the merge both depots' lots " <>
                     "combine, so the cost is restated. realized_result: over the position's " <>
                     "sales, each sale's quantity times its price in the security's currency " <>
                     "less the cost it removed at the running average, fees and taxes not " <>
                     "included; null where a price or cost in the security's currency is not " <>
                     "derivable. source and target are before the merge (null where the depot " <>
                     "holds no booking of the security), after is the target afterwards. " <>
                     "rounding_differences: each split of an affected security where the " <>
                     "combined position rounded once differs, at the end of the split's day, " <>
                     "from the two positions rounded apart — expected, never a refusal."

  @depot_reimport_note "After the merge the source depot's name and former names are former " <>
                         "names of the target: a Portfolio Performance import naming them books " <>
                         "onto the target, and a re-import of an export already applied creates " <>
                         "nothing, because every row the merge removes has its content hash " <>
                         "retired."

  @doc "A depot merge preview."
  def depot_preview(preview) do
    %{
      kind: "securities_account",
      plan_digest: preview.plan_digest,
      source: depot(preview.source),
      target: depot(preview.target),
      guards: Enum.map(preview.guards, &guard/1),
      internal_transfers: Enum.map(preview.internal_transfers, &security_transfer/1),
      key_equal_pairs: Enum.map(preview.key_equal_pairs, &depot_pair/1),
      choice_required: preview.choice_required,
      position_buckets: Enum.map(preview.position_buckets, &position_buckets/1),
      former_names: %{
        appended: preview.former_names.appended,
        not_kept: Enum.map(preview.former_names.not_kept, &not_kept/1),
        after: preview.former_names.after
      },
      outcome_by_collapse_key_equal: %{
        "false" => depot_outcome(Map.fetch!(preview.outcomes, false)),
        "true" => depot_outcome(Map.fetch!(preview.outcomes, true))
      },
      positions_basis: @positions_basis,
      reimport_note: @depot_reimport_note
    }
  end

  @doc "One merge record (§12): the source's snapshot and the manifest as stored."
  def record(%MergeRecord{} = record) do
    %{
      id: record.id,
      kind: Atom.to_string(record.kind),
      source_id: record.source_id,
      target_id: record.target_id,
      portfolio_id: record.portfolio_id,
      source_snapshot: record.source_snapshot,
      manifest: record.manifest,
      plan_digest: record.plan_digest,
      actor_type: Atom.to_string(record.actor_type),
      actor_label: record.actor_label,
      inserted_at: JSON.datetime(record.inserted_at)
    }
  end

  @doc "A guard's result, its code the refusal it answers when it fails."
  def guard(guard) do
    %{
      code: Atom.to_string(guard.code),
      check: guard.check,
      passed: guard.passed,
      detail: guard.detail
    }
  end

  defp account(account) do
    %{
      id: account.id,
      name: account.name,
      portfolio_id: account.portfolio_id,
      currency_code: account.currency_code,
      liquidity_role: account.liquidity_role,
      bucket_ids: account.bucket_ids,
      former_names: account.former_names,
      balance: JSON.decimal(account.balance),
      transaction_count: account.transaction_count
    }
  end

  defp depot(depot) do
    %{
      id: depot.id,
      name: depot.name,
      portfolio_id: depot.portfolio_id,
      cash_account_id: depot.cash_account_id,
      bucket_ids: depot.bucket_ids,
      former_names: depot.former_names,
      transaction_count: depot.transaction_count
    }
  end

  defp security_transfer(transfer) do
    %{
      id: transfer.id,
      date: JSON.date(transfer.date),
      security_id: transfer.security_id,
      quantity: JSON.decimal(transfer.quantity),
      securities_account_id: transfer.securities_account_id,
      counter_securities_account_id: transfer.counter_securities_account_id,
      retires_hash: transfer.retires_hash
    }
  end

  defp depot_pair(pair) do
    %{
      source_transaction_id: pair.source_transaction_id,
      target_transaction_id: pair.target_transaction_id,
      date: JSON.date(pair.date),
      type: pair.type,
      security_id: pair.security_id,
      quantity: JSON.decimal(pair.quantity),
      price: JSON.decimal(pair.price),
      gross_amount: JSON.decimal(pair.gross_amount),
      cash_account_id: pair.cash_account_id,
      retires_hash: pair.retires_hash
    }
  end

  defp position_buckets(entry) do
    %{
      security_id: entry.security_id,
      security_name: entry.security_name,
      source_holds: entry.source_holds,
      target_holds: entry.target_holds,
      source_override: entry.source_override,
      target_override: entry.target_override,
      source_buckets: entry.source_buckets,
      target_buckets: entry.target_buckets,
      action: Atom.to_string(entry.action)
    }
  end

  defp depot_outcome(outcome) do
    %{
      transaction_count: outcome.transaction_count,
      moved_transaction_ids: outcome.moved_transaction_ids,
      deleted:
        Enum.map(outcome.deleted, fn deleted ->
          %{
            id: deleted.id,
            date: JSON.date(deleted.date),
            type: deleted.type,
            security_id: deleted.security_id,
            reason: Atom.to_string(deleted.reason),
            superseded_by: deleted.superseded_by,
            retires_hash: deleted.retires_hash
          }
        end),
      positions:
        Enum.map(outcome.positions, fn position ->
          %{
            security_id: position.security_id,
            security_name: position.security_name,
            currency_code: position.currency_code,
            source: figures(position.source),
            target: figures(position.target),
            after: figures(position.after)
          }
        end),
      rounding_differences:
        Enum.map(outcome.rounding_differences, fn difference ->
          %{
            security_id: difference.security_id,
            security_name: difference.security_name,
            date: JSON.date(difference.date),
            split_transaction_id: difference.split_transaction_id,
            ratio: difference.ratio,
            combined: JSON.decimal(difference.combined),
            separate_sum: JSON.decimal(difference.separate_sum),
            difference: JSON.decimal(difference.difference)
          }
        end),
      cash_accounts:
        Enum.map(outcome.cash_accounts, fn account ->
          %{
            id: account.id,
            name: account.name,
            balance_before: JSON.decimal(account.balance_before),
            balance_after: JSON.decimal(account.balance_after)
          }
        end)
    }
  end

  defp figures(nil), do: nil

  defp figures(figures) do
    %{
      quantity: JSON.decimal(figures.quantity),
      cost_basis: JSON.decimal(figures.cost_basis),
      avg_cost: JSON.decimal(figures.avg_cost),
      realized_result: JSON.decimal(figures.realized_result)
    }
  end

  defp transfer(transfer) do
    %{
      id: transfer.id,
      date: JSON.date(transfer.date),
      gross_amount: JSON.decimal(transfer.gross_amount),
      cash_account_id: transfer.cash_account_id,
      counter_cash_account_id: transfer.counter_cash_account_id,
      retires_hash: transfer.retires_hash
    }
  end

  defp pair(pair) do
    %{
      source_transaction_id: pair.source_transaction_id,
      target_transaction_id: pair.target_transaction_id,
      date: JSON.date(pair.date),
      type: pair.type,
      gross_amount: JSON.decimal(pair.gross_amount),
      quantity: JSON.decimal(pair.quantity),
      price: JSON.decimal(pair.price),
      security_id: pair.security_id,
      securities_account_id: pair.securities_account_id,
      third_cash_account_id: pair.third_cash_account_id,
      retires_hash: pair.retires_hash
    }
  end

  defp not_kept(entry),
    do: %{name: entry.name, held_by: entry.held_by, as: Atom.to_string(entry.as)}

  defp outcome(outcome) do
    %{
      balance: JSON.decimal(outcome.balance),
      transaction_count: outcome.transaction_count,
      moved_transaction_ids: outcome.moved_transaction_ids,
      deleted:
        Enum.map(outcome.deleted, fn deleted ->
          %{
            id: deleted.id,
            date: JSON.date(deleted.date),
            type: deleted.type,
            reason: Atom.to_string(deleted.reason),
            superseded_by: deleted.superseded_by,
            retires_hash: deleted.retires_hash
          }
        end),
      restated_anchors:
        Enum.map(outcome.restated_anchors, fn anchor ->
          %{
            id: anchor.id,
            date: JSON.date(anchor.date),
            side: Atom.to_string(anchor.side),
            stated: JSON.decimal(anchor.stated),
            other_balance: JSON.decimal(anchor.other_balance),
            after: JSON.decimal(anchor.after),
            folds: anchor.folds
          }
        end),
      flow_changes:
        Enum.map(outcome.flow_changes, fn change ->
          %{
            kind: Atom.to_string(change.kind),
            transaction_id: change.transaction_id,
            date: JSON.date(change.date),
            change: JSON.decimal(change.change),
            collapsed_transaction_id: change.collapsed_transaction_id
          }
        end),
      other_accounts:
        Enum.map(outcome.other_accounts, fn account ->
          %{
            id: account.id,
            name: account.name,
            balance_before: JSON.decimal(account.balance_before),
            balance_after: JSON.decimal(account.balance_after)
          }
        end),
      positions:
        Enum.map(outcome.positions, fn position ->
          %{
            securities_account_id: position.securities_account_id,
            security_id: position.security_id,
            quantity_change: JSON.decimal(position.quantity_change)
          }
        end)
    }
  end
end
