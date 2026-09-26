defmodule Portfolixir.Lifecycle.DepotMerge do
  @moduledoc """
  The merge of one depot (securities account) into another (ADR-0050 §7's
  depot half, §8, §10, §12 and §13; #328). Risk-tier: quantity identity and
  import idempotency (ADR-0036).

  A merge of a source S into a target T is a relabelling: every booking that
  names S through either depot leg is re-pointed onto T. It removes only two
  kinds of row, each journaled with its hash retired:

    * the security transfers between S and T, void once both legs are one
      depot (§5, reason `internal_transfer`);
    * the source rows paired with a target row of equal #533 key (§8), and
      only when the operator chose `collapse_key_equal: true` (reason
      `collapsed_duplicate`, superseded by the paired target row).

  A booking keeps its cash leg: T keeps its own linked cash account, and S's
  stays as an account of its own. Splits are rows of the portfolio, not of a
  depot, so none moves; each one scales the merged position once.

  ## The guards (each a refusal that writes nothing)

  `same_account` (a depot into itself), `not_live`, `portfolio_mismatch`,
  `buckets_mismatch` (the two depots' **default** view-bucket sets differ) and
  `position_buckets_mismatch`: view membership is retroactive (ADR-0024
  point 4), so every position must keep its **effective** buckets. Per
  security S holds rows of:

    * where T holds rows of it, S's effective set must equal T's — S's
      override, then redundant, is dropped; any difference refuses, naming the
      position, because moving an override onto a position T holds would
      re-view T's own history;
    * where T holds none, S's effective set is carried onto T: S's override
      moves; a position S lets inherit the default clears a dead override T
      carries for a security it does not hold.

  An override S carries for a security it holds no rows of is dropped. An
  override to carry that holds more than one scope-dimension bucket (stored
  before ADR-0024's one-scope rule held for overrides) refuses too, naming
  the position: the target's position cannot take it.

  ## The preview (`preview/2`) — a read

  Both depots, the guards, the transfers the merge deletes, the key-equal
  pairs, each position's bucket plan, the former names the target gains and —
  because the choice is not an input (§10) — the outcome of **both** values of
  `collapse_key_equal`: every affected position (every security S holds rows
  of) with its quantity, moving-average cost and realized result for S and T
  before and for T after (`Portfolixir.Ledger.position_costs/1`; the cost
  basis is legitimately restated, because lots combine), the rounding
  difference each split leaves between the combined position rounded once and
  the two positions rounded apart, and the cash accounts whose balance a
  collapsed booking changes. Its `plan_digest` covers all of it.

  ## The apply (`apply/4`)

  The consent (`Portfolixir.Lifecycle.MergeFlow`), then in one transaction:
  the account-identity advisory lock of the portfolio, `FOR UPDATE` on S and T
  in id order, on every booking either depot names and on the portfolio's
  split rows of their securities; the plan recomputed and its digest
  compared (`plan_changed` with the fresh preview on a mismatch); then,
  through `Portfolixir.Lifecycle.MergeWriter`, one journal entry per row:

    1. delete the S↔T transfers and the collapsed source rows, retiring their
       hashes;
    2. re-point every other source row onto T, per row;
    3. the **linearity check** (§7, §16 invariant 10): at every date either
       depot has a row, every split date and today, T's quantity of each
       security equals the fold of both depots' kept rows as one depot, each
       split scaling the combined position once — and, before a security's
       first split, the sum of both depots' quantities. Otherwise the merge
       rolls back with `identity_check_failed`, a bug catcher, never an
       expected answer. From a split on, the combined position rounded once
       may differ from the sum of the two rounded apart by a unit of the
       volume scale; that is expected, listed in the preview, never a
       failure;
    4. the bucket plan, through the journaled `Portfolixir.Buckets` writers
       (one aggregate entry per position);
    5. delete S through the hardened delete (its default buckets first, one
       aggregate entry), then append S's names to T's former names;
    6. write the merge record (§12) under the id its retirements already name.
  """

  import Ecto.Query

  import Portfolixir.Lifecycle.MergeFlow,
    only: [guard: 4, guard: 5, passed?: 1, each: 2, jsonable: 1]

  import Portfolixir.Lifecycle.MergeFigures, only: [sample: 2, quantity: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.PositionBucketOverride
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Clock
  alias Portfolixir.Imports.DedupKey
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.AccountNames
  alias Portfolixir.Lifecycle.Delete
  alias Portfolixir.Lifecycle.MergeFigures
  alias Portfolixir.Lifecycle.MergeFlow
  alias Portfolixir.Lifecycle.MergeRecord
  alias Portfolixir.Lifecycle.MergeWriter
  alias Portfolixir.Lifecycle.PlanDigest
  alias Portfolixir.Lifecycle.PositionMembership
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Repo

  @zero Decimal.new("0")

  @empty_figures %{quantity: @zero, cost_basis: @zero, avg_cost: @zero, realized_result: @zero}

  @type refusal ::
          :not_found
          | {:already_merged, MergeRecord.t()}
          | {:refused, [MergeFlow.guard()]}
          | {:plan_changed, map()}
          | {:choice_required, :collapse_key_equal, pos_integer()}
          | {:invalid, :plan_digest | :collapse_key_equal, String.t()}
          | {:identity_check_failed, map()}
          | {:write_refused, String.t(), integer(), Ecto.Changeset.t()}

  # --- the preview ---------------------------------------------------------------

  @doc """
  The preview of merging the depot `source_id` into `target_id`: a read.
  `{:ok, preview}` when every guard passes; `{:error, {:refused, guards}}`
  naming the failed guard otherwise; `{:error, :not_found}` for a source that
  does not exist; `{:error, {:already_merged, record}}` for a source a merge
  already took away.
  """
  @spec preview(integer(), integer()) :: {:ok, map()} | {:error, refusal()}
  def preview(source_id, target_id) when is_integer(source_id) and is_integer(target_id) do
    case Lifecycle.merge_of(:securities_account, source_id) do
      %MergeRecord{} = record ->
        {:error, {:already_merged, record}}

      nil ->
        case Repo.get(SecuritiesAccount, source_id) do
          nil ->
            {:error, :not_found}

          source ->
            with {:ok, preview, _plan} <-
                   build(source, target_id, Repo.get(SecuritiesAccount, target_id), false),
                 do: {:ok, preview}
        end
    end
  end

  # --- the apply -------------------------------------------------------------------

  @doc """
  Merges the depot `source_id` into `target_id` on behalf of `actor`, under
  `params`: `plan_digest` (required, the digest of the preview the operator
  approved) and `collapse_key_equal` (required when the preview lists
  key-equal pairs). See the moduledoc for the steps.

  Answers `{:ok, record, :applied}`, or `{:ok, record, :already_applied}`
  for a retry of a completed merge of the same pair (nothing journaled), or
  `{:error, refusal}` with nothing written.
  """
  @spec apply(Actor.t(), integer(), integer(), map()) ::
          {:ok, MergeRecord.t(), :applied | :already_applied} | {:error, refusal()}
  def apply(%Actor{} = actor, source_id, target_id, params)
      when is_integer(source_id) and is_integer(target_id) and is_map(params) do
    with {:ok, digest, collapse} <- MergeFlow.consent(params) do
      case MergeFlow.prior_merge(:securities_account, source_id, target_id) do
        :none -> transact(actor, source_id, target_id, digest, collapse)
        {:ok, record} -> {:ok, record, :already_applied}
        {:error, _refusal} = refused -> refused
      end
    end
  end

  defp transact(actor, source_id, target_id, digest, collapse) do
    fn ->
      case locked_pair(source_id, target_id) do
        {:ok, source, target} -> merge_locked(actor, source, target_id, target, digest, collapse)
        :gone -> source_gone(source_id, target_id)
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, {outcome, record}} ->
        {:ok, record, outcome}

      # A row, an override or a bucket another writer removed under the merge
      # (the locks make it a bug catcher) is a changed plan like a stale
      # digest.
      {:error, reason} when reason in [:plan_changed, :raced] ->
        fresh_preview(source_id, target_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The fixed lock order (§10): the account-identity advisory lock of the
  # portfolio first — the lock every writer of account names takes first —
  # then both depots FOR UPDATE, in id order.
  defp locked_pair(source_id, target_id) do
    ids = Enum.uniq([source_id, target_id])

    from(a in SecuritiesAccount, where: a.id in ^ids, select: a.portfolio_id)
    |> Repo.all()
    |> AccountNames.lock_identity()

    depots =
      Repo.all(
        from(a in SecuritiesAccount, where: a.id in ^ids, order_by: a.id, lock: "FOR UPDATE")
      )

    case Enum.find(depots, &(&1.id == source_id)) do
      nil -> :gone
      source -> {:ok, source, Enum.find(depots, &(&1.id == target_id))}
    end
  end

  # The source vanished between the pre-check and the lock: a concurrent
  # merge of it committed first, or it was deleted.
  defp source_gone(source_id, target_id) do
    case MergeFlow.prior_merge(:securities_account, source_id, target_id) do
      {:ok, record} -> {:already_applied, record}
      {:error, refusal} -> Repo.rollback(refusal)
      :none -> Repo.rollback(:not_found)
    end
  end

  defp merge_locked(actor, source, target_id, target, digest, collapse) do
    with {:ok, _preview, plan} <- build(source, target_id, target, true),
         :ok <- same_digest(plan, digest),
         {:ok, collapse?} <- MergeFlow.choose(plan.pairs, collapse),
         {:ok, record} <- execute(actor, plan, collapse?, collapse) do
      {:applied, record}
    else
      {:error, refusal} -> Repo.rollback(refusal)
    end
  end

  defp same_digest(%{digest: digest}, digest), do: :ok
  defp same_digest(_plan, _approved), do: {:error, :plan_changed}

  defp fresh_preview(source_id, target_id) do
    case preview(source_id, target_id) do
      {:ok, fresh} -> {:error, {:plan_changed, fresh}}
      {:error, refusal} -> {:error, refusal}
    end
  end

  # --- the guards (§7, each a refusal that writes nothing) ------------------------

  defp build(source, target_id, target, lock?) do
    guards = basic_guards(source, target_id, target)

    if passed?(guards) do
      plan = plan(source, target, load(source, target, lock?))
      plan = %{plan | guards: guards ++ [membership_guard(plan)]}

      if passed?(plan.guards) do
        preview = view(plan)
        digest = digest(plan, preview)
        {:ok, Map.put(preview, :plan_digest, digest), %{plan | digest: digest}}
      else
        {:error, {:refused, plan.guards}}
      end
    else
      {:error, {:refused, guards}}
    end
  end

  defp basic_guards(source, target_id, nil) do
    [
      same_account_guard(source, target_id),
      guard(
        :not_live,
        "both depots live",
        false,
        "securities account ##{target_id} does not exist" <> merged_away(target_id)
      )
    ]
  end

  defp basic_guards(source, target_id, %SecuritiesAccount{} = target) do
    source_buckets = Buckets.depot_default_bucket_ids(source.id)
    target_buckets = Buckets.depot_default_bucket_ids(target.id)

    [
      same_account_guard(source, target_id),
      guard(:not_live, "both depots live", true, "both depots exist"),
      guard(
        :portfolio_mismatch,
        "same portfolio",
        source.portfolio_id == target.portfolio_id,
        "both depots belong to portfolio ##{target.portfolio_id}",
        "the depots belong to portfolios ##{source.portfolio_id} and ##{target.portfolio_id}: " <>
          "every booking is pinned to its portfolio, so a merge stays inside one"
      ),
      guard(
        :buckets_mismatch,
        "same default buckets",
        source_buckets == target_buckets,
        "both depots default to the buckets #{inspect(target_buckets)}",
        "the depots default to the buckets #{inspect(source_buckets)} and " <>
          "#{inspect(target_buckets)}: view membership is retroactive, so a merge would move " <>
          "history between views"
      )
    ]
  end

  defp same_account_guard(source, target_id) do
    guard(
      :same_account,
      "not the same depot",
      source.id != target_id,
      "two different depots",
      "a depot cannot be merged into itself"
    )
  end

  defp merged_away(id) do
    case Lifecycle.merged_into(:securities_account, id) do
      nil -> ""
      survivor -> " (it was merged into securities account ##{survivor})"
    end
  end

  # A refusal also names its positions as data (L5a), so the operator's page
  # can say it in the operator's language; a passing guard carries nothing
  # more, so the preview and its digest are unchanged.
  defp membership_guard(plan) do
    refused = Enum.filter(plan.memberships, &(&1.action in [:refuse, :refuse_carry]))

    :position_buckets_mismatch
    |> guard(
      "same view membership for every position",
      refused == [],
      "every position keeps its effective buckets",
      Enum.map_join(refused, " ", &membership_detail/1)
    )
    |> put_refused_positions(refused)
  end

  defp put_refused_positions(guard, []), do: guard

  defp put_refused_positions(guard, refused) do
    Map.put(
      guard,
      :positions,
      Enum.map(
        refused,
        &Map.take(&1, [:security_id, :security_name, :source_buckets, :target_buckets, :action])
      )
    )
  end

  defp membership_detail(%{action: :refuse} = entry) do
    "#{position_name(entry)} sits in the buckets #{inspect(entry.source_buckets)} in the " <>
      "source and #{inspect(entry.target_buckets)} in the target: view membership is " <>
      "retroactive, so the merge would move the target's history between views. Give the " <>
      "position the same buckets in both depots, then preview again."
  end

  defp membership_detail(%{action: :refuse_carry} = entry) do
    "#{position_name(entry)} carries an override in the source with more than one scope " <>
      "bucket #{inspect(entry.source_buckets)}, stored before a position could hold only one: " <>
      "the target's position cannot take it. Keep one scope bucket in the source's override, " <>
      "then preview again."
  end

  defp position_name(entry), do: "#{entry.security_name} (security ##{entry.security_id})"

  # --- loading ---------------------------------------------------------------------

  # Every booking either depot names through either leg, and the portfolio's
  # split rows of their securities; under the apply's locks, FOR UPDATE, so no
  # booking of either side changes between the digest check and the writes.
  # The bucket state is read under the depots' locks, which every bucket and
  # override writer of a depot takes first.
  defp load(source, target, lock?) do
    ids = [source.id, target.id]

    rows =
      from(t in Transaction,
        where: t.securities_account_id in ^ids or t.counter_securities_account_id in ^ids,
        order_by: t.id
      )
      |> maybe_lock(lock?)
      |> Repo.all()
      |> Repo.preload([:security, :cash_account])

    securities = rows |> Enum.map(& &1.security_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    splits =
      from(t in Transaction,
        where:
          t.type == "split" and t.portfolio_id == ^target.portfolio_id and
            t.security_id in ^securities,
        order_by: t.id
      )
      |> maybe_lock(lock?)
      |> Repo.all()

    %{
      rows: rows,
      splits: splits,
      source_buckets: Buckets.depot_default_bucket_ids(source.id),
      target_buckets: Buckets.depot_default_bucket_ids(target.id),
      source_override_securities:
        Repo.all(
          from(o in PositionBucketOverride,
            where: o.securities_account_id == ^source.id,
            distinct: true,
            select: o.security_id
          )
        )
    }
  end

  defp maybe_lock(query, true), do: lock(query, "FOR UPDATE")
  defp maybe_lock(query, false), do: query

  # --- the plan ----------------------------------------------------------------------

  defp plan(source, target, data) do
    s = source.id
    t = target.id
    {transfers, rest} = Enum.split_with(data.rows, &internal_transfer?(&1, s, t))
    s_rows = Enum.filter(rest, &touches?(&1, s))
    t_rows = Enum.filter(rest, &touches?(&1, t))
    s_all = Enum.filter(data.rows, &touches?(&1, s))
    t_all = Enum.filter(data.rows, &touches?(&1, t))
    source_securities = security_ids(s_all)
    target_securities = security_ids(t_all)
    all_securities = Enum.sort(Enum.uniq(source_securities ++ target_securities))
    names = security_names(all_securities ++ data.source_override_securities)
    {appended, not_kept} = AccountNames.merge_names(source, target)

    base = %{
      source: source,
      target: target,
      rows: data.rows,
      splits: data.splits,
      source_buckets: data.source_buckets,
      target_buckets: data.target_buckets,
      transfers: transfers,
      s_rows: s_rows,
      t_rows: t_rows,
      s_all: s_all,
      t_all: t_all,
      source_securities: source_securities,
      target_securities: target_securities,
      securities: all_securities,
      names: names,
      currencies: security_currencies(data.rows),
      pairs: pairs(s_rows, t_rows, s, t),
      before_costs: Ledger.position_costs(data.rows ++ data.splits),
      appended_names: appended,
      names_not_kept: not_kept,
      check_dates:
        [Clock.today() | Enum.map(data.rows ++ data.splits, & &1.date)]
        |> Enum.uniq()
        |> Enum.sort(Date),
      guards: [],
      digest: nil
    }

    base
    |> Map.put(:memberships, memberships(base, data.source_override_securities))
    |> then(&Map.put(&1, :outcomes, %{false => outcome(&1, []), true => outcome(&1, &1.pairs)}))
  end

  defp touches?(row, id),
    do: row.securities_account_id == id or row.counter_securities_account_id == id

  defp internal_transfer?(%{type: "security_transfer"} = row, s, t),
    do:
      Enum.sort([row.securities_account_id, row.counter_securities_account_id]) ==
        Enum.sort([s, t])

  defp internal_transfer?(_row, _s, _t), do: false

  defp security_ids(rows),
    do: rows |> Enum.map(& &1.security_id) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()

  defp security_names([]), do: %{}

  defp security_names(ids) do
    ids = Enum.uniq(ids)
    Map.new(Repo.all(from(s in Security, where: s.id in ^ids, select: {s.id, s.name})))
  end

  defp security_currencies(rows) do
    for %{security: %Security{id: id, currency_code: currency}} <- rows,
        into: %{},
        do: {id, currency}
  end

  # §8: a source row other than an anchor or a split whose #533 key,
  # rewritten onto the target, equals a target row's key is paired with it
  # one-to-one, lowest id first.
  defp pairs(s_rows, t_rows, s, t) do
    targets =
      t_rows
      |> Enum.filter(&pairable?/1)
      |> Enum.group_by(&DedupKey.of/1)

    s_rows
    |> Enum.filter(&pairable?/1)
    |> Enum.group_by(&DedupKey.of(repointed(&1, s, t)))
    |> Enum.flat_map(fn {key, sources} ->
      Enum.zip(Enum.sort_by(sources, & &1.id), Enum.sort_by(Map.get(targets, key, []), & &1.id))
    end)
    |> Enum.sort_by(fn {source_row, _target_row} -> source_row.id end)
  end

  defp pairable?(row), do: row.type not in ["balance_adjustment", "split"]

  defp repointed(row, s, t) do
    %{
      row
      | securities_account_id: swap(row.securities_account_id, s, t),
        counter_securities_account_id: swap(row.counter_securities_account_id, s, t)
    }
  end

  defp swap(s, s, t), do: t
  defp swap(other, _s, _t), do: other

  # --- view membership ------------------------------------------------------------------

  # Every security S holds rows of or carries an override for, with the
  # write that keeps its effective buckets — or `:refuse`.
  defp memberships(base, source_override_securities) do
    s = base.source.id
    t = base.target.id

    (base.source_securities ++ source_override_securities)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn security_id ->
      s_override = Buckets.position_override(s, security_id)
      t_override = Buckets.position_override(t, security_id)
      s_effective = PositionMembership.effective(s_override, base.source_buckets)
      t_effective = PositionMembership.effective(t_override, base.target_buckets)
      source_holds = security_id in base.source_securities
      target_holds = security_id in base.target_securities

      action =
        PositionMembership.action(
          %{holds: source_holds, override: s_override, effective: s_effective},
          %{holds: target_holds, override: t_override, effective: t_effective}
        )

      %{
        security_id: security_id,
        security_name: Map.get(base.names, security_id),
        source_holds: source_holds,
        target_holds: target_holds,
        source_override: s_override,
        target_override: t_override,
        source_buckets: s_effective,
        target_buckets: t_effective,
        action: action
      }
    end)
  end

  # --- one value of the choice ------------------------------------------------------------

  defp outcome(base, pairs) do
    s = base.source.id
    t = base.target.id
    collapsed = MapSet.new(pairs, fn {source_row, _target_row} -> source_row.id end)
    moved = Enum.reject(base.s_rows, &MapSet.member?(collapsed, &1.id))

    deleted =
      Enum.map(base.transfers, &%{row: &1, reason: :internal_transfer, superseded_by: nil}) ++
        Enum.map(pairs, fn {source_row, target_row} ->
          %{row: source_row, reason: :collapsed_duplicate, superseded_by: target_row.id}
        end)

    after_rows = base.t_rows ++ Enum.map(moved, &repointed(&1, s, t))
    kept = Enum.reject(base.rows, &MapSet.member?(collapsed, &1.id))
    combined = MergeFigures.eod_positions(after_rows ++ base.splits)
    separate = MergeFigures.eod_positions(kept ++ base.splits)

    %{
      moved: moved,
      deleted: Enum.sort_by(deleted, & &1.row.id),
      transaction_count: length(after_rows),
      combined: combined,
      separate: separate,
      positions: positions(base, Ledger.position_costs(after_rows ++ base.splits)),
      rounding_differences: rounding_differences(base, combined, separate),
      cash_accounts: MergeFigures.collapsed_cash_accounts(pairs),
      flow_changes: MergeFigures.collapse_flow_changes(pairs)
    }
  end

  # Every security S holds rows of: its figures on S and on T before, and on
  # T after, from the ledger's own moving-average fold.
  defp positions(base, after_costs) do
    s = base.source.id
    t = base.target.id

    for security_id <- base.source_securities do
      %{
        security_id: security_id,
        security_name: Map.get(base.names, security_id),
        currency_code: Map.get(base.currencies, security_id),
        source: figures(base.before_costs, {s, security_id}, true),
        target:
          figures(base.before_costs, {t, security_id}, security_id in base.target_securities),
        after: figures(after_costs, {t, security_id}, true)
      }
    end
  end

  defp figures(_costs, _key, false), do: nil
  defp figures(costs, key, true), do: Map.get(costs, key, @empty_figures)

  # ADR-0028 §3 rounds a split's scaled position once at volume scale 6. The
  # merged depot scales the combined position once; apart, each depot's
  # position was rounded on its own. Where the two differ at the end of a
  # split's day, the difference is listed — expected, never a failure.
  defp rounding_differences(base, combined, separate) do
    s = base.source.id
    t = base.target.id
    dates = base.splits |> Enum.map(& &1.date) |> Enum.uniq()
    combined_at = sample(combined, dates)
    separate_at = sample(separate, dates)

    base.splits
    |> Projection.replay_sort()
    |> Enum.filter(&(&1.security_id in base.source_securities))
    |> Enum.flat_map(fn split ->
      key = fn depot -> {depot, split.security_id} end
      merged = quantity(combined_at, split.date, key.(t))

      apart =
        Decimal.add(
          quantity(separate_at, split.date, key.(s)),
          quantity(separate_at, split.date, key.(t))
        )

      if Decimal.equal?(merged, apart),
        do: [],
        else: [rounding_line(base, split, merged, apart)]
    end)
  end

  defp rounding_line(base, split, merged, apart) do
    %{
      security_id: split.security_id,
      security_name: Map.get(base.names, split.security_id),
      date: split.date,
      split_transaction_id: split.id,
      ratio: %{numerator: split.split_ratio_numerator, denominator: split.split_ratio_denominator},
      combined: merged,
      separate_sum: apart,
      difference: Decimal.sub(merged, apart)
    }
  end

  # --- the preview's shape -------------------------------------------------------------

  defp view(plan) do
    %{
      kind: :securities_account,
      source: depot_view(plan.source, plan.s_all, plan.source_buckets),
      target: depot_view(plan.target, plan.t_all, plan.target_buckets),
      guards: plan.guards,
      internal_transfers: Enum.map(plan.transfers, &transfer_view/1),
      key_equal_pairs: Enum.map(plan.pairs, &pair_view/1),
      choice_required: plan.pairs != [],
      position_buckets: Enum.map(plan.memberships, &membership_view/1),
      former_names: %{
        appended: plan.appended_names,
        not_kept: plan.names_not_kept,
        after: plan.target.former_names ++ plan.appended_names
      },
      outcomes:
        Map.new(plan.outcomes, fn {collapse?, outcome} -> {collapse?, outcome_view(outcome)} end)
    }
  end

  defp depot_view(depot, rows, bucket_ids) do
    %{
      id: depot.id,
      name: depot.name,
      portfolio_id: depot.portfolio_id,
      cash_account_id: depot.cash_account_id,
      bucket_ids: bucket_ids,
      former_names: depot.former_names,
      transaction_count: length(rows)
    }
  end

  defp transfer_view(row) do
    %{
      id: row.id,
      date: row.date,
      security_id: row.security_id,
      quantity: row.quantity,
      securities_account_id: row.securities_account_id,
      counter_securities_account_id: row.counter_securities_account_id,
      retires_hash: row.import_hash != nil
    }
  end

  defp pair_view({source_row, target_row}) do
    %{
      source_transaction_id: source_row.id,
      target_transaction_id: target_row.id,
      date: source_row.date,
      type: source_row.type,
      security_id: source_row.security_id,
      quantity: source_row.quantity,
      price: source_row.price,
      gross_amount: source_row.gross_amount,
      cash_account_id: source_row.cash_account_id,
      retires_hash: source_row.import_hash != nil
    }
  end

  defp membership_view(entry) do
    %{
      security_id: entry.security_id,
      security_name: entry.security_name,
      source_holds: entry.source_holds,
      target_holds: entry.target_holds,
      source_override: PositionMembership.override_ids(entry.source_override),
      target_override: PositionMembership.override_ids(entry.target_override),
      source_buckets: entry.source_buckets,
      target_buckets: entry.target_buckets,
      action: entry.action
    }
  end

  defp outcome_view(outcome) do
    %{
      transaction_count: outcome.transaction_count,
      moved_transaction_ids: Enum.map(outcome.moved, & &1.id),
      deleted:
        Enum.map(outcome.deleted, fn %{row: row, reason: reason, superseded_by: by} ->
          %{
            id: row.id,
            date: row.date,
            type: row.type,
            security_id: row.security_id,
            reason: reason,
            superseded_by: by,
            retires_hash: row.import_hash != nil
          }
        end),
      positions: outcome.positions,
      rounding_differences: outcome.rounding_differences,
      cash_accounts: outcome.cash_accounts,
      flow_changes: outcome.flow_changes
    }
  end

  # §10: both ids and their updated_at, every row either depot references and
  # every split row of their securities with its updated_at and economic
  # fields, every figure the preview shows (the bucket plan among them) and
  # the guard results.
  defp digest(plan, preview) do
    PlanDigest.compute(%{
      preview: preview,
      source: [plan.source.id, plan.source.updated_at, plan.source.cash_account_id],
      target: [plan.target.id, plan.target.updated_at, plan.target.cash_account_id],
      rows: Enum.map(plan.rows ++ plan.splits, &PlanDigest.transaction_fingerprint/1)
    })
  end

  # --- the writes (§7 depot steps) ---------------------------------------------------------

  defp execute(actor, plan, collapse?, choice) do
    outcome = Map.fetch!(plan.outcomes, collapse?)
    record_id = Lifecycle.reserve_merge_record_id()

    with :ok <- delete_rows(actor, outcome.deleted, record_id),
         :ok <- move_rows(actor, plan, outcome),
         :ok <- linearity_check(plan, outcome),
         {:ok, overrides} <- apply_memberships(actor, plan),
         {:ok, _deleted} <- delete_source(actor, plan.source),
         {:ok, appended, not_kept} <- append_names(actor, plan) do
      Lifecycle.record_merge(
        actor,
        %{
          kind: :securities_account,
          source_id: plan.source.id,
          target_id: plan.target.id,
          portfolio_id: plan.target.portfolio_id,
          source_snapshot: source_snapshot(plan),
          manifest: manifest(plan, outcome, choice, overrides, {appended, not_kept}),
          plan_digest: plan.digest
        },
        id: record_id
      )
      |> case do
        {:ok, record} -> {:ok, record}
        {:error, changeset} -> {:error, {:write_refused, "merge_record", record_id, changeset}}
      end
    end
  end

  # Each removed row deleted, journaled, and its hash retired under the
  # record: a transfer as `internal_transfer`, a collapsed row as
  # `collapsed_duplicate` superseded by the target row that stays.
  defp delete_rows(actor, deleted, record_id) do
    each(deleted, fn %{row: row, reason: reason, superseded_by: by} ->
      with {:ok, _deleted} <- MergeWriter.delete_transaction(actor, row),
           do: MergeWriter.retire_hash(actor, row, record_id, reason, by)
    end)
  end

  defp move_rows(actor, plan, outcome) do
    s = plan.source.id
    t = plan.target.id

    each(outcome.moved, fn row ->
      attrs =
        %{}
        |> put_leg(:securities_account_id, row.securities_account_id, s, t)
        |> put_leg(:counter_securities_account_id, row.counter_securities_account_id, s, t)

      with :ok <- assert_writable(plan, row, attrs),
           {:ok, _row} <- MergeWriter.reassign_transaction(actor, row, attrs),
           do: :ok
    end)
  end

  defp put_leg(attrs, field, s, s, t), do: Map.put(attrs, field, t)
  defp put_leg(attrs, _field, _other, _s, _t), do: attrs

  # §13: the merge writer asserts distinct legs and one portfolio on the
  # columns it writes; the guards make each a bug catcher.
  defp assert_writable(plan, row, attrs) do
    depot = Map.get(attrs, :securities_account_id, row.securities_account_id)
    counter = Map.get(attrs, :counter_securities_account_id, row.counter_securities_account_id)

    cond do
      depot != nil and depot == counter ->
        identity_failure(row, "both depot legs would name one depot")

      row.portfolio_id != plan.target.portfolio_id ->
        identity_failure(row, "another portfolio")

      true ->
        :ok
    end
  end

  defp identity_failure(row, reason),
    do: {:error, {:identity_check_failed, %{transaction_id: row.id, reason: reason}}}

  # §7, §16 invariant 10, read back from the database after the writes: at
  # every date either depot has a row, every split date and today, T's
  # quantity of each security equals the fold of both depots' kept rows as
  # one depot — each split scaling the combined position once — and, before
  # the security's first split, the sum of both depots' quantities.
  defp linearity_check(plan, outcome) do
    s = plan.source.id
    t = plan.target.id

    rows =
      Repo.all(
        from(tx in Transaction,
          where: tx.securities_account_id == ^t or tx.counter_securities_account_id == ^t
        )
      )

    splits =
      Repo.all(
        from(tx in Transaction,
          where:
            tx.type == "split" and tx.portfolio_id == ^plan.target.portfolio_id and
              tx.security_id in ^plan.securities
        )
      )

    actual = sample(MergeFigures.eod_positions(rows ++ splits), plan.check_dates)
    expected = sample(outcome.combined, plan.check_dates)
    separate = sample(outcome.separate, plan.check_dates)
    first_split = first_split_dates(plan.splits)

    Enum.find_value(plan.check_dates, :ok, fn date ->
      Enum.find_value(plan.securities, fn security_id ->
        merged = quantity(actual, date, {t, security_id})
        combined = quantity(expected, date, {t, security_id})

        apart =
          Decimal.add(
            quantity(separate, date, {s, security_id}),
            quantity(separate, date, {t, security_id})
          )

        cond do
          not Decimal.equal?(merged, combined) ->
            quantity_failure(date, security_id, combined, merged)

          before_first_split?(first_split, security_id, date) and
              not Decimal.equal?(combined, apart) ->
            quantity_failure(date, security_id, apart, combined)

          true ->
            nil
        end
      end)
    end)
  end

  defp quantity_failure(date, security_id, expected, actual) do
    {:error,
     {:identity_check_failed,
      %{date: date, security_id: security_id, expected: expected, actual: actual}}}
  end

  defp first_split_dates(splits) do
    Enum.reduce(splits, %{}, fn split, acc ->
      Map.update(acc, split.security_id, split.date, &Enum.min([&1, split.date], Date))
    end)
  end

  defp before_first_split?(first_split, security_id, date) do
    case Map.get(first_split, security_id) do
      nil -> true
      first -> Date.compare(date, first) == :lt
    end
  end

  # The bucket plan (§7 depot guards), through the journaled Buckets writers:
  # one aggregate entry per position and depot. A position another writer
  # changed under the merge (the depots' locks make it a bug catcher) is a
  # changed plan.
  defp apply_memberships(actor, plan) do
    Enum.reduce_while(
      plan.memberships,
      {:ok, %{carried: [], dropped: [], cleared: []}},
      fn entry, {:ok, acc} ->
        case membership_write(actor, plan, entry) do
          :none -> {:cont, {:ok, acc}}
          {:ok, list, item} -> {:cont, {:ok, Map.update!(acc, list, &(&1 ++ [item]))}}
          {:error, _reason} -> {:halt, {:error, :raced}}
        end
      end
    )
  end

  defp membership_write(actor, plan, entry) do
    security = %Security{id: entry.security_id}

    case PositionMembership.write(
           actor,
           entry.action,
           {{plan.source, security}, entry.source_override},
           {{plan.target, security}, entry.target_override}
         ) do
      {:ok, list, facts} -> {:ok, list, Map.put(facts, :security_id, entry.security_id)}
      other -> other
    end
  end

  # Through the hardened delete (§11): the source's default buckets first,
  # one aggregate entry, then the row. Inside the merge a refusal is a
  # reference the locks should have kept out: a changed plan, or the
  # database's own answer, named.
  defp delete_source(actor, source) do
    case Delete.remove(actor, source) do
      {:ok, deleted} ->
        {:ok, deleted}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, {:write_refused, "securities_account", source.id, changeset}}

      {:error, _raced_or_gone} ->
        {:error, :raced}
    end
  end

  # The source's names, checked by the guard once the source is gone,
  # appended to the target's former names under the lock taken first.
  defp append_names(actor, plan) do
    target =
      Repo.one!(from(a in SecuritiesAccount, where: a.id == ^plan.target.id, lock: "FOR UPDATE"))

    {appended, not_kept} = AccountNames.merge_names(plan.source, target)

    with {:ok, _target} <- MergeWriter.append_former_names(actor, target, appended),
         do: {:ok, appended, not_kept}
  end

  # --- the record (§12) -----------------------------------------------------------------

  defp source_snapshot(plan) do
    source = plan.source

    jsonable(%{
      id: source.id,
      name: source.name,
      portfolio_id: source.portfolio_id,
      cash_account_id: source.cash_account_id,
      notes: source.notes,
      former_names: source.former_names,
      bucket_ids: plan.source_buckets,
      position_overrides:
        for(
          %{source_override: override, security_id: id} <- plan.memberships,
          override != :inherit,
          do: %{security_id: id, bucket_ids: PositionMembership.override_ids(override)}
        ),
      transaction_count: length(plan.s_all),
      inserted_at: source.inserted_at,
      updated_at: source.updated_at
    })
  end

  # Per table, every row moved or deleted, every override carried, dropped or
  # cleared, the default buckets removed, the names appended, the rounding
  # differences and the operator's choice.
  defp manifest(plan, outcome, choice, overrides, {appended, not_kept}) do
    s = plan.source.id
    t = plan.target.id

    jsonable(%{
      choices: %{collapse_key_equal: choice},
      transactions: %{
        moved:
          Enum.map(outcome.moved, fn row ->
            %{
              id: row.id,
              securities_account_id: [
                row.securities_account_id,
                swap(row.securities_account_id, s, t)
              ],
              counter_securities_account_id: [
                row.counter_securities_account_id,
                swap(row.counter_securities_account_id, s, t)
              ]
            }
          end),
        deleted:
          Enum.map(outcome.deleted, fn %{row: row, reason: reason, superseded_by: by} ->
            %{
              id: row.id,
              date: row.date,
              type: row.type,
              reason: reason,
              superseded_by: by,
              import_hash: row.import_hash
            }
          end)
      },
      position_bucket_overrides: overrides,
      securities_account_buckets: %{removed: plan.source_buckets},
      former_names: %{appended: appended, not_kept: not_kept},
      rounding_differences: outcome.rounding_differences,
      linearity: %{
        dates_checked: length(plan.check_dates),
        securities_checked: length(plan.securities)
      }
    })
  end
end
