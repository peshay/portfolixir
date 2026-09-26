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

  @security_positions_basis "quantity: the position fold of each depot's bookings of the " <>
                              "security and its portfolio's splits, each split scaling the " <>
                              "position once, rounded at volume scale 6 (ADR-0028 §3). " <>
                              "cost_basis and avg_cost: the moving-average cost GET " <>
                              "/api/v1/portfolios/:id/holdings states, in the security's " <>
                              "currency, fees and taxes not included; after the merge both " <>
                              "securities' lots in a depot combine, so the cost is restated. " <>
                              "realized_result: over the position's sales, each sale's quantity " <>
                              "times its price less the cost it removed at the running average, " <>
                              "fees and taxes not included; null where not derivable. source and " <>
                              "target are before the merge (null where the depot holds no " <>
                              "booking of that security), after is the target afterwards, per " <>
                              "depot the source holds. rounding_differences: each split where " <>
                              "the combined position rounded once differs, at the end of the " <>
                              "split's day, from the two positions rounded apart — expected, " <>
                              "never a refusal."

  @security_reimport_note "After the merge every identity of the source resolves to the target: " <>
                            "its ISIN, as the target's ISIN or as a former ISIN of the target " <>
                            "(the identity choice decides which), its former ISINs, and its WKN, " <>
                            "ticker and feed where the target took them. A Portfolio Performance " <>
                            "import naming the source books onto the target, and a re-import of an " <>
                            "export already applied creates nothing, because every booking the " <>
                            "merge removes has its content hash retired. A merge that would leave " <>
                            "an identity unresolved is refused (identity_unresolvable)."

  @doc """
  A security merge preview (§9): the parts of a depot preview — positions per
  depot, pairs, splits, the bucket plan — and the quotes, the configuration,
  the events and the identifiers the merge carries.
  """
  def security_preview(preview) do
    %{
      kind: "security",
      plan_digest: preview.plan_digest,
      source: security(preview.source),
      target: security(preview.target),
      guards: Enum.map(preview.guards, &guard/1),
      key_equal_pairs: Enum.map(preview.key_equal_pairs, &security_pair/1),
      choice_required: preview.choice_required,
      identity_choice_required: preview.identifiers.choice_required,
      splits: %{
        collapsed:
          Enum.map(preview.splits.collapsed, fn split ->
            %{
              source_transaction_id: split.source_transaction_id,
              target_transaction_id: split.target_transaction_id,
              portfolio_id: split.portfolio_id,
              date: JSON.date(split.date),
              ratio: split.ratio
            }
          end),
        moved:
          Enum.map(preview.splits.moved, fn split ->
            %{
              id: split.id,
              portfolio_id: split.portfolio_id,
              date: JSON.date(split.date),
              ratio: split.ratio
            }
          end)
      },
      split_events:
        Map.new(preview.split_events, fn {side, events} -> {side, split_events(events)} end),
      position_buckets: Enum.map(preview.position_buckets, &depot_buckets/1),
      quotes: %{
        source_count: preview.quotes.source_count,
        moved_count: preview.quotes.moved_count,
        collision_count: preview.quotes.collision_count,
        manual_collisions:
          Enum.map(preview.quotes.manual_collisions, fn collision ->
            %{
              date: JSON.date(collision.date),
              source_close: JSON.decimal(collision.source_close),
              target_close: JSON.decimal(collision.target_close),
              target_source: collision.target_source
            }
          end)
      },
      configuration: %{
        category_assignments:
          Enum.map(preview.configuration.category_assignments, fn assignment ->
            Map.update!(assignment, :action, &Atom.to_string/1)
          end),
        position_targets:
          Enum.map(preview.configuration.position_targets, fn target ->
            %{
              target
              | target_weight: JSON.decimal(target.target_weight),
                action: Atom.to_string(target.action),
                reason: target.reason && Atom.to_string(target.reason)
            }
          end)
      },
      events: %{
        moved:
          Enum.map(preview.events.moved, fn event ->
            %{id: event.id, kind: Atom.to_string(event.kind), date: JSON.date(event.date)}
          end),
        possible_duplicates:
          Enum.map(preview.events.possible_duplicates, fn pair ->
            %{pair | kind: Atom.to_string(pair.kind), date: JSON.date(pair.date)}
          end)
      },
      identifiers: identifiers(preview.identifiers),
      reverse: %{
        mergeable: preview.reverse.mergeable,
        refused:
          Enum.map(preview.reverse.refused, &%{code: Atom.to_string(&1.code), detail: &1.detail})
      },
      outcome_by_collapse_key_equal: %{
        "false" => security_outcome(Map.fetch!(preview.outcomes, false)),
        "true" => security_outcome(Map.fetch!(preview.outcomes, true))
      },
      positions_basis: @security_positions_basis,
      reimport_note: @security_reimport_note
    }
  end

  @doc """
  What a failed guard carries beside its code and detail, for the refusal's
  `errors`: the rules that name the source (`policy_rules`), the identities
  that would no longer resolve (`unresolvable`), the balance anchors a cash
  merge cannot restate (`anchors`) and the bookings that make one
  unstorable (`bookings`).
  """
  def guard_facts(%{policy_rules: [_ | _] = rules}), do: %{policy_rules: rules}

  def guard_facts(%{unresolvable: [_ | _] = failures}),
    do: %{unresolvable: Enum.map(failures, &unresolvable/1)}

  def guard_facts(%{anchors: [_ | _] = anchors} = guard) do
    %{anchors: Enum.map(anchors, &booking_ref/1)}
    |> Map.merge(
      case Map.get(guard, :bookings, []) do
        [] -> %{}
        bookings -> %{bookings: Enum.map(bookings, &booking_ref/1)}
      end
    )
  end

  def guard_facts(_guard), do: %{}

  defp booking_ref(ref),
    do: %{id: ref.id, date: JSON.date(ref.date), cash_account_id: ref.cash_account_id}

  @doc """
  One identity that would not resolve to the target (§9): whose it is, which
  one (`stored`, `imported`, `former_isin`, or for a security merged into
  either before `merged_stored`, `merged_imported`), its identifiers, what
  the ladder
  answers instead (`kind` `none`, `ambiguous`, `identifier_veto`,
  `cross_tier` or `other_security`, with the securities it names) and under
  which identity choices.
  """
  def unresolvable(failure) do
    %{
      security_id: failure.security_id,
      identity: Atom.to_string(failure.identity),
      ref: failure.ref,
      outcome: %{
        kind: Atom.to_string(failure.outcome.kind),
        candidates: failure.outcome.candidates
      },
      identity_choices: Enum.map(Map.get(failure, :identity_choices, []), &Atom.to_string/1)
    }
  end

  defp security(security) do
    Map.update!(security, :split_events, &split_events/1)
  end

  defp split_events(events),
    do: Enum.map(events, fn event -> %{date: JSON.date(event.date), ratio: event.ratio} end)

  defp security_pair(pair) do
    %{
      source_transaction_id: pair.source_transaction_id,
      target_transaction_id: pair.target_transaction_id,
      portfolio_id: pair.portfolio_id,
      securities_account_id: pair.securities_account_id,
      date: JSON.date(pair.date),
      type: pair.type,
      quantity: JSON.decimal(pair.quantity),
      price: JSON.decimal(pair.price),
      gross_amount: JSON.decimal(pair.gross_amount),
      cash_account_id: pair.cash_account_id,
      retires_hash: pair.retires_hash
    }
  end

  defp depot_buckets(entry) do
    %{
      securities_account_id: entry.securities_account_id,
      securities_account_name: entry.securities_account_name,
      source_holds: entry.source_holds,
      target_holds: entry.target_holds,
      source_override: entry.source_override,
      target_override: entry.target_override,
      source_buckets: entry.source_buckets,
      target_buckets: entry.target_buckets,
      action: Atom.to_string(entry.action)
    }
  end

  defp identifiers(identifiers) do
    outcomes = identifiers.outcomes

    %{
      choice_required: identifiers.choice_required,
      after_by_identity_choice:
        if(identifiers.choice_required,
          do: %{
            "keep_target_isin" => Map.fetch!(outcomes, :keep_target_isin),
            "adopt_source_isin" => Map.fetch!(outcomes, :adopt_source_isin)
          }
        ),
      after: if(identifiers.choice_required, do: nil, else: Map.fetch!(outcomes, :no_choice)),
      adopted:
        Enum.map(identifiers.adopted, &%{field: Atom.to_string(&1.field), value: &1.value}),
      differences:
        Enum.map(identifiers.differences, fn difference ->
          %{difference | field: Atom.to_string(difference.field)}
        end),
      aliases_reassigned:
        Enum.map(identifiers.aliases_reassigned, fn alias_row ->
          %{alias_row | changed_on: JSON.date(alias_row.changed_on)}
        end)
    }
  end

  defp security_outcome(outcome) do
    %{
      transaction_count: outcome.transaction_count,
      moved_transaction_ids: outcome.moved_transaction_ids,
      deleted:
        Enum.map(outcome.deleted, fn deleted ->
          %{
            id: deleted.id,
            date: JSON.date(deleted.date),
            type: deleted.type,
            portfolio_id: deleted.portfolio_id,
            reason: Atom.to_string(deleted.reason),
            superseded_by: deleted.superseded_by,
            retires_hash: deleted.retires_hash
          }
        end),
      positions:
        Enum.map(outcome.positions, fn position ->
          %{
            securities_account_id: position.securities_account_id,
            securities_account_name: position.securities_account_name,
            portfolio_id: position.portfolio_id,
            source: figures(position.source),
            target: figures(position.target),
            after: figures(position.after)
          }
        end),
      rounding_differences:
        Enum.map(outcome.rounding_differences, fn difference ->
          %{
            portfolio_id: difference.portfolio_id,
            securities_account_id: difference.securities_account_id,
            securities_account_name: difference.securities_account_name,
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
        end),
      flow_changes: flow_changes(outcome.flow_changes)
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

  @doc """
  One merge record as `GET /api/v1/merges` lists it (§12): what went into
  what — the source's name as its snapshot recorded it, the target's live
  name, or for a target a later merge took away the name that merge
  recorded and the live end of the chain in `merged_into` — who did it,
  when, and the manifest summarized: every list replaced by its count,
  every other value as stored (the operator's choices among them). The full
  manifest and snapshot stay on the record the merge answered.
  """
  def listed(%{record: %MergeRecord{} = record} = listed) do
    %{
      id: record.id,
      kind: Atom.to_string(record.kind),
      source: %{id: record.source_id, name: listed.source_name},
      target: %{
        id: record.target_id,
        name: listed.target_name,
        merged_into: listed.target_merged_into
      },
      portfolio_id: record.portfolio_id,
      actor_type: Atom.to_string(record.actor_type),
      actor_label: record.actor_label,
      inserted_at: JSON.datetime(record.inserted_at),
      manifest_summary: summarize(record.manifest)
    }
  end

  defp summarize(list) when is_list(list), do: length(list)
  defp summarize(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, summarize(v)} end)
  defp summarize(value), do: value

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
      securities_account_id: pair.securities_account_id,
      counter_securities_account_id: pair.counter_securities_account_id,
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
        end),
      flow_changes: flow_changes(outcome.flow_changes),
      other_depots:
        Enum.map(outcome.other_depots, fn depot ->
          %{
            securities_account_id: depot.securities_account_id,
            securities_account_name: depot.securities_account_name,
            security_id: depot.security_id,
            security_name: depot.security_name,
            quantity_before: JSON.decimal(depot.quantity_before),
            quantity_after: JSON.decimal(depot.quantity_after)
          }
        end)
    }
  end

  # §16 invariant 9: each flow a collapse removes or moves, and the cash
  # account whose leg it is.
  defp flow_changes(changes) do
    Enum.map(changes, fn change ->
      %{
        kind: Atom.to_string(change.kind),
        cash_account_id: change.cash_account_id,
        transaction_id: change.transaction_id,
        date: JSON.date(change.date),
        change: JSON.decimal(change.change),
        collapsed_transaction_id: change.collapsed_transaction_id
      }
    end)
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
      flow_changes: flow_changes(outcome.flow_changes),
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
