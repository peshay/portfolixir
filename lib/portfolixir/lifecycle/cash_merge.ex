defmodule Portfolixir.Lifecycle.CashMerge do
  @moduledoc """
  The merge of one cash account into another (ADR-0050 §7's cash half, §8,
  §10, §12 and §13; #328). Risk-tier: money identity and import idempotency
  (ADR-0036).

  A merge of a source S into a target T is a relabelling: every reference to
  S is re-pointed onto T, or resolved by a rule the preview shows. It removes
  only three kinds of ledger row, each journaled with its hash retired:

    * the transfers between S and T, void once both legs are one account
      (§5, reason `internal_transfer`);
    * the source rows paired with a target row of equal #533 key (§8), and
      only when the operator chose `collapse_key_equal: true` (reason
      `collapsed_duplicate`, superseded by the paired target row);
    * on a day where both accounts carry balance anchors, every anchor of
      that day but the target's last, which absorbs them (§7 step 4).

  ## The preview (`preview/2`) — a read

  It checks the guards (each refusal names its code: `same_account`,
  `not_live`, `portfolio_mismatch`, `currency_mismatch`,
  `liquidity_role_mismatch`, `buckets_mismatch`, `legacy_hashed_anchor`),
  then states the plan: the transfers it drops, the key-equal pairs, the
  former names the target gains, and — because the choice is not an input
  (§10) — the outcome of **both** values of `collapse_key_equal`: the
  target's balance and booking count after, every row moved or deleted,
  every surviving balance anchor as "stated + other account = after", the
  external flows a collapse removes or moves, the third accounts and the
  positions a collapsed row changes. Its `plan_digest`
  (`Portfolixir.Lifecycle.PlanDigest`) covers all of it.

  ## The apply (`apply/4`)

  Validates the consent (`plan_digest` required; `collapse_key_equal`
  required when pairs exist), answers a completed merge of the same pair
  with its record, then, in one transaction: the account-identity advisory
  lock of the portfolio (`AccountNames.lock_identity/2`), `FOR UPDATE` on S
  and T in id order, then on every row either references and S's linked
  depots; recomputes the plan and answers `plan_changed` with the fresh
  preview on a digest mismatch; then §7's steps 2–7 through
  `Portfolixir.Lifecycle.MergeWriter`, one journal entry per row:

    1. delete the S↔T transfers, retiring their hashes;
    2. delete the collapsed source rows, retiring their hashes;
    3. restate the anchors: every anchor of one side becomes its stated
       amount plus the other side's end-of-day balance on its date, from the
       Ledger projection over the other side's **kept** rows — its rows
       before the merge, less the source rows collapsed (never a derived
       value, ADR-0039 I7); on a day both sides carry anchors, the target's
       last holds the sum of both last anchors and the others are deleted;
    4. re-point every source row, and S's linked depots;
    5. the **linearity check**: at every date either account has a row and
       today, T's balance equals the fold of S's kept rows plus the fold of
       T's kept rows, each under its own pre-merge anchors, `Decimal`-exact —
       otherwise the merge rolls back with `identity_check_failed`, a bug
       catcher, never an expected answer;
    6. delete S through the hardened delete path
       (`Portfolixir.Lifecycle.Delete.remove/2`: its bucket links first, one
       aggregate journal entry), then append S's names to T's former names
       (`AccountNames.merge_names/2`, checked after S is gone);
    7. write the merge record (§12) under the id its retirements already
       name, with the manifest and the actor.

  One legacy state is refused rather than written: a balance anchor that
  still carries an import hash (a row re-typed before this release, which
  the NOT VALID `transactions_import_hash_kind_check` refuses to update) is
  deleted with its hash retired when a fold removes it, and refuses the
  merge (`legacy_hashed_anchor`) when the merge would have to restate or
  move it.
  """

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Clock
  alias Portfolixir.Imports.DedupKey
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.AccountNames
  alias Portfolixir.Lifecycle.Delete
  alias Portfolixir.Lifecycle.MergeRecord
  alias Portfolixir.Lifecycle.MergeWriter
  alias Portfolixir.Lifecycle.PlanDigest
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Repo

  @zero Decimal.new("0")
  @anchor "balance_adjustment"

  @type guard :: %{code: atom(), check: String.t(), passed: boolean(), detail: String.t()}

  @type refusal ::
          :not_found
          | {:already_merged, MergeRecord.t()}
          | {:refused, [guard()]}
          | {:plan_changed, map()}
          | {:choice_required, :collapse_key_equal, pos_integer()}
          | {:invalid, :plan_digest | :collapse_key_equal, String.t()}
          | {:identity_check_failed, map()}
          | {:write_refused, String.t(), integer(), Ecto.Changeset.t()}

  # --- the preview ---------------------------------------------------------------

  @doc """
  The preview of merging the cash account `source_id` into `target_id`: a
  read. `{:ok, preview}` when every guard passes; `{:error, {:refused,
  guards}}` naming the failed guard otherwise; `{:error, :not_found}` for a
  source that does not exist; `{:error, {:already_merged, record}}` for a
  source a merge already took away.
  """
  @spec preview(integer(), integer()) :: {:ok, map()} | {:error, refusal()}
  def preview(source_id, target_id) when is_integer(source_id) and is_integer(target_id) do
    case Lifecycle.merge_of(:cash_account, source_id) do
      %MergeRecord{} = record ->
        {:error, {:already_merged, record}}

      nil ->
        case Repo.get(CashAccount, source_id) do
          nil ->
            {:error, :not_found}

          source ->
            with {:ok, preview, _plan} <-
                   build(source, target_id, Repo.get(CashAccount, target_id), false),
                 do: {:ok, preview}
        end
    end
  end

  # --- the apply -------------------------------------------------------------------

  @doc """
  Merges the cash account `source_id` into `target_id` on behalf of `actor`,
  under `params`: `plan_digest` (required, the digest of the preview the
  operator approved) and `collapse_key_equal` (required when the preview
  lists key-equal pairs). See the moduledoc for the steps.

  Answers `{:ok, record, :applied}`, or `{:ok, record, :already_applied}`
  for a retry of a completed merge of the same pair (nothing journaled), or
  `{:error, refusal}` with nothing written.
  """
  @spec apply(Actor.t(), integer(), integer(), map()) ::
          {:ok, MergeRecord.t(), :applied | :already_applied} | {:error, refusal()}
  def apply(%Actor{} = actor, source_id, target_id, params)
      when is_integer(source_id) and is_integer(target_id) and is_map(params) do
    with {:ok, digest} <- digest_param(params),
         {:ok, collapse} <- collapse_param(params) do
      case prior_merge(source_id, target_id) do
        :none -> transact(actor, source_id, target_id, digest, collapse)
        {:ok, record} -> {:ok, record, :already_applied}
        {:error, _refusal} = refused -> refused
      end
    end
  end

  defp digest_param(params) do
    case Map.get(params, :plan_digest) do
      digest when is_binary(digest) and digest != "" -> {:ok, digest}
      _missing -> {:error, {:invalid, :plan_digest, "can't be blank"}}
    end
  end

  defp collapse_param(params) do
    case Map.get(params, :collapse_key_equal) do
      value when is_boolean(value) or is_nil(value) -> {:ok, value}
      _other -> {:error, {:invalid, :collapse_key_equal, "must be true or false"}}
    end
  end

  defp prior_merge(source_id, target_id) do
    case Lifecycle.merge_of(:cash_account, source_id) do
      nil -> :none
      %MergeRecord{target_id: ^target_id} = record -> {:ok, record}
      %MergeRecord{} = record -> {:error, {:already_merged, record}}
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

      # A row or a depot another writer removed under the merge (the locks
      # make it a bug catcher) is a changed plan like a stale digest.
      {:error, reason} when reason in [:plan_changed, :raced] ->
        fresh_preview(source_id, target_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The fixed lock order (§10): the account-identity advisory lock of the
  # portfolio first — the lock every writer of account names takes first —
  # then both accounts FOR UPDATE, in id order.
  defp locked_pair(source_id, target_id) do
    ids = Enum.uniq([source_id, target_id])

    from(a in CashAccount, where: a.id in ^ids, select: a.portfolio_id)
    |> Repo.all()
    |> AccountNames.lock_identity()

    accounts =
      Repo.all(from(a in CashAccount, where: a.id in ^ids, order_by: a.id, lock: "FOR UPDATE"))

    case Enum.find(accounts, &(&1.id == source_id)) do
      nil -> :gone
      source -> {:ok, source, Enum.find(accounts, &(&1.id == target_id))}
    end
  end

  # The source vanished between the pre-check and the lock: a concurrent
  # merge of it committed first, or it was deleted.
  defp source_gone(source_id, target_id) do
    case prior_merge(source_id, target_id) do
      {:ok, record} -> {:already_applied, record}
      {:error, refusal} -> Repo.rollback(refusal)
      :none -> Repo.rollback(:not_found)
    end
  end

  defp merge_locked(actor, source, target_id, target, digest, collapse) do
    with {:ok, _preview, plan} <- build(source, target_id, target, true),
         :ok <- same_digest(plan, digest),
         {:ok, collapse?} <- choose(plan, collapse),
         {:ok, record} <- execute(actor, plan, collapse?, collapse) do
      {:applied, record}
    else
      {:error, refusal} -> Repo.rollback(refusal)
    end
  end

  defp same_digest(%{digest: digest}, digest), do: :ok
  defp same_digest(_plan, _approved), do: {:error, :plan_changed}

  defp choose(%{pairs: [_ | _] = pairs}, nil),
    do: {:error, {:choice_required, :collapse_key_equal, length(pairs)}}

  defp choose(_plan, collapse), do: {:ok, collapse == true}

  defp fresh_preview(source_id, target_id) do
    case preview(source_id, target_id) do
      {:ok, fresh} -> {:error, {:plan_changed, fresh}}
      {:error, refusal} -> {:error, refusal}
    end
  end

  # --- the guards (§7, each a 409 that writes nothing) ---------------------------

  defp build(source, target_id, target, lock?) do
    guards = basic_guards(source, target_id, target)

    if passed?(guards) do
      plan = plan(source, target, load(source, target, lock?))
      plan = %{plan | guards: guards ++ [legacy_anchor_guard(plan)]}

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

  defp passed?(guards), do: Enum.all?(guards, & &1.passed)

  defp basic_guards(source, target_id, nil) do
    [
      same_account_guard(source, target_id),
      guard(
        :not_live,
        "both accounts live",
        false,
        "cash account ##{target_id} does not exist" <> merged_away(target_id)
      )
    ]
  end

  defp basic_guards(source, target_id, %CashAccount{} = target) do
    source_buckets = Buckets.cash_account_bucket_ids(source.id)
    target_buckets = Buckets.cash_account_bucket_ids(target.id)

    [
      same_account_guard(source, target_id),
      guard(:not_live, "both accounts live", true, "both accounts exist"),
      guard(
        :portfolio_mismatch,
        "same portfolio",
        source.portfolio_id == target.portfolio_id,
        "both accounts belong to portfolio ##{target.portfolio_id}",
        "the accounts belong to portfolios ##{source.portfolio_id} and ##{target.portfolio_id}: " <>
          "every booking is pinned to its portfolio, so a merge stays inside one"
      ),
      guard(
        :currency_mismatch,
        "same currency",
        source.currency_code == target.currency_code,
        "both accounts hold #{target.currency_code}",
        "the accounts hold #{source.currency_code} and #{target.currency_code}: a merge never " <>
          "converts an amount"
      ),
      guard(
        :liquidity_role_mismatch,
        "same liquidity role",
        source.liquidity_role == target.liquidity_role,
        "both accounts have the liquidity role #{target.liquidity_role}",
        "the accounts have the liquidity roles #{source.liquidity_role} and " <>
          "#{target.liquidity_role}: a merge would change how the history counts as cash"
      ),
      guard(
        :buckets_mismatch,
        "same buckets",
        source_buckets == target_buckets,
        "both accounts sit in the buckets #{inspect(target_buckets)}",
        "the accounts sit in the buckets #{inspect(source_buckets)} and " <>
          "#{inspect(target_buckets)}: view membership is retroactive, so a merge would move " <>
          "history between views"
      )
    ]
  end

  defp same_account_guard(source, target_id) do
    guard(
      :same_account,
      "not the same account",
      source.id != target_id,
      "two different accounts",
      "an account cannot be merged into itself"
    )
  end

  defp merged_away(id) do
    case Lifecycle.merged_into(:cash_account, id) do
      nil -> ""
      survivor -> " (it was merged into cash account ##{survivor})"
    end
  end

  defp guard(code, check, passed?, detail),
    do: %{code: code, check: check, passed: passed?, detail: detail}

  defp guard(code, check, true, passed, _refused), do: guard(code, check, true, passed)
  defp guard(code, check, false, _passed, refused), do: guard(code, check, false, refused)

  # A balance anchor that still carries an import hash — a row re-typed
  # before this release — is refused an update by the NOT VALID kind check,
  # so a merge that would restate or move one is refused up front. A fold
  # deletes such an anchor, which the check allows, and retires its hash.
  defp legacy_anchor_guard(plan) do
    written =
      for {_collapse?, outcome} <- plan.outcomes,
          %{row: row, side: side, stated: stated, after: after_restatement} <-
            Map.values(outcome.restatements),
          row.import_hash != nil,
          side == :source or not Decimal.equal?(stated, after_restatement),
          uniq: true,
          do: row.id

    guard(
      :legacy_hashed_anchor,
      "no hashed balance anchor to restate or move",
      written == [],
      "no balance anchor the merge restates or moves carries an import hash",
      legacy_anchor_detail(Enum.sort(written))
    )
  end

  defp legacy_anchor_detail(ids) do
    rows = Enum.map_join(ids, ", ", &"##{&1}")

    "the balance anchor(s) #{rows} carry an import hash: each was imported as another kind " <>
      "and re-typed before the import-hash kind check existed, which now refuses every edit " <>
      "of it, so the merge cannot restate or move it. Change its type back to the kind it " <>
      "was imported as (the audit journal shows it) or delete it, then preview again"
  end

  # --- loading ---------------------------------------------------------------------

  # Every transaction either account references through either leg, and the
  # depots linked to the source; under the apply's locks, FOR UPDATE, so no
  # booking of either side changes between the digest check and the writes.
  defp load(source, target, lock?) do
    ids = [source.id, target.id]

    rows =
      from(t in Transaction,
        where: t.cash_account_id in ^ids or t.counter_cash_account_id in ^ids,
        order_by: t.id
      )
      |> maybe_lock(lock?)
      |> Repo.all()

    depots =
      from(d in SecuritiesAccount, where: d.cash_account_id == ^source.id, order_by: d.id)
      |> maybe_lock(lock?)
      |> Repo.all()

    %{
      rows: rows,
      depots: depots,
      source_buckets: Buckets.cash_account_bucket_ids(source.id),
      target_buckets: Buckets.cash_account_bucket_ids(target.id)
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
    t_all = Enum.filter(data.rows, &touches?(&1, t))
    pairs = pairs(s_rows, t_rows, s, t)
    {appended, not_kept} = AccountNames.merge_names(source, target)

    base = %{
      source: source,
      target: target,
      rows: data.rows,
      depots: data.depots,
      source_buckets: data.source_buckets,
      target_buckets: data.target_buckets,
      transfers: transfers,
      s_rows: s_rows,
      t_rows: t_rows,
      s_all: Enum.filter(data.rows, &touches?(&1, s)),
      t_all: t_all,
      pairs: pairs,
      s_anchors: anchors(s_rows, s),
      t_anchors: anchors(t_rows, t),
      eod_t: eod(t_all, t),
      appended_names: appended,
      names_not_kept: not_kept,
      check_dates:
        [Clock.today() | Enum.map(data.rows, & &1.date)]
        |> Enum.uniq()
        |> Enum.sort(Date),
      guards: [],
      digest: nil
    }

    base
    |> Map.put(:folds, folds(base.s_anchors, base.t_anchors))
    |> then(&Map.put(&1, :outcomes, %{false => outcome(&1, []), true => outcome(&1, pairs)}))
  end

  defp touches?(row, id), do: row.cash_account_id == id or row.counter_cash_account_id == id

  defp internal_transfer?(%{type: "cash_transfer"} = row, s, t),
    do: Enum.sort([row.cash_account_id, row.counter_cash_account_id]) == Enum.sort([s, t])

  defp internal_transfer?(_row, _s, _t), do: false

  defp anchors(rows, account_id),
    do: Enum.filter(rows, &(&1.type == @anchor and &1.cash_account_id == account_id))

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

  defp pairable?(row), do: row.type not in [@anchor, "split"]

  defp repointed(row, s, t) do
    %{
      row
      | cash_account_id: swap(row.cash_account_id, s, t),
        counter_cash_account_id: swap(row.counter_cash_account_id, s, t)
    }
  end

  defp swap(s, s, t), do: t
  defp swap(other, _s, _t), do: other

  # The days both accounts carry an anchor: the target's last anchor of the
  # day absorbs the source's last, and every other anchor of the day goes.
  defp folds(s_anchors, t_anchors) do
    s_by_day = Enum.group_by(s_anchors, & &1.date)
    t_by_day = Enum.group_by(t_anchors, & &1.date)

    for {date, s_day} <- s_by_day, Map.has_key?(t_by_day, date), into: %{} do
      t_day = Map.fetch!(t_by_day, date)
      t_last = Enum.max_by(t_day, & &1.id)
      s_last = Enum.max_by(s_day, & &1.id)

      {date,
       %{t_last: t_last, s_last: s_last, deleted: Enum.reject(s_day ++ t_day, &(&1 == t_last))}}
    end
  end

  # One value of the choice: what the merge writes, and what it leaves.
  defp outcome(base, pairs) do
    s = base.source.id
    t = base.target.id
    collapsed = MapSet.new(pairs, fn {source_row, _target_row} -> source_row.id end)
    eod_s = eod(Enum.reject(base.s_all, &MapSet.member?(collapsed, &1.id)), s)
    restatements = restatements(base, eod_s)

    folded =
      for {_date, %{deleted: deleted, t_last: t_last}} <- base.folds,
          row <- deleted,
          into: %{},
          do: {row.id, t_last.id}

    moved =
      Enum.reject(base.s_rows, &(MapSet.member?(collapsed, &1.id) or Map.has_key?(folded, &1.id)))

    deleted =
      Enum.map(base.transfers, &%{row: &1, reason: :internal_transfer, superseded_by: nil}) ++
        Enum.map(pairs, fn {source_row, target_row} ->
          %{row: source_row, reason: :collapsed_duplicate, superseded_by: target_row.id}
        end) ++
        for(
          row <- base.s_rows ++ base.t_rows,
          Map.has_key?(folded, row.id),
          do: %{row: row, reason: :folded_anchor, superseded_by: Map.fetch!(folded, row.id)}
        )

    after_rows = simulate(base, moved, folded, restatements)

    %{
      eod_s: eod_s,
      restatements: restatements,
      moved: moved,
      deleted: Enum.sort_by(deleted, & &1.row.id),
      balance: Map.get(Projection.cash_balances(after_rows), t, @zero),
      transaction_count: length(after_rows),
      flow_changes: flow_changes(base, pairs, folded, s),
      other_accounts: other_accounts(base, pairs),
      positions: positions(pairs)
    }
  end

  # §7 step 4: every anchor that survives, restated by the other side's
  # end-of-day balance on its date, or — on a fold day — the target's last
  # anchor holding both last anchors.
  defp restatements(base, eod_s) do
    folded_days = Map.keys(base.folds)

    fold_lines =
      for {_date, %{t_last: t_last, s_last: s_last, deleted: deleted}} <- base.folds,
          do: line(t_last, :target, s_last.gross_amount, Enum.map(deleted, & &1.id))

    source_lines =
      for row <- base.s_anchors,
          row.date not in folded_days,
          do: line(row, :source, balance_on(base.eod_t, row.date), [])

    target_lines =
      for row <- base.t_anchors,
          row.date not in folded_days,
          do: line(row, :target, balance_on(eod_s, row.date), [])

    Map.new(fold_lines ++ source_lines ++ target_lines, &{&1.row.id, &1})
  end

  defp line(row, side, other, folds) do
    %{
      row: row,
      date: row.date,
      side: side,
      stated: row.gross_amount,
      other_balance: other,
      after: Decimal.add(row.gross_amount, other),
      folds: folds
    }
  end

  # The target's rows after the merge, as the writes will leave them: the
  # moved source rows re-pointed, every surviving anchor restated.
  defp simulate(base, moved, folded, restatements) do
    s = base.source.id
    t = base.target.id

    kept_target = Enum.reject(base.t_rows, &Map.has_key?(folded, &1.id))

    (kept_target ++ Enum.map(moved, &repointed(&1, s, t)))
    |> Enum.map(fn row ->
      case Map.get(restatements, row.id) do
        nil -> row
        %{after: amount} -> %{row | gross_amount: amount}
      end
    end)
  end

  # §16 invariant 9: the external flows a collapse removes (a collapsed
  # external row's own flow, on its day) or moves (a collapsed row before one
  # of the source's anchors: that anchor's residual — an external flow —
  # grows by the row's amount, on the anchor's day).
  defp flow_changes(base, pairs, folded, s) do
    Enum.flat_map(pairs, fn {row, _target_row} ->
      effect = Projection.effects(row)
      delta = account_delta(effect, s)

      removed =
        if effect.external and not Decimal.equal?(delta, @zero),
          do: [
            %{
              kind: :removed,
              transaction_id: row.id,
              date: row.date,
              change: Decimal.negate(delta),
              collapsed_transaction_id: row.id
            }
          ],
          else: []

      removed ++ absorbed(base, row, delta, folded)
    end)
  end

  defp absorbed(base, row, delta, folded) do
    key = Projection.replay_key(row)

    case base.s_anchors
         |> Enum.filter(&(Projection.replay_key(&1) > key))
         |> Enum.min_by(&Projection.replay_key/1, fn -> nil end) do
      nil ->
        []

      anchor ->
        if Decimal.equal?(delta, @zero) do
          []
        else
          [
            %{
              kind: :absorbed,
              transaction_id: Map.get(folded, anchor.id, anchor.id),
              date: anchor.date,
              change: delta,
              collapsed_transaction_id: row.id
            }
          ]
        end
    end
  end

  defp account_delta(effect, account_id) do
    for {^account_id, {:add, delta}} <- effect.cash, reduce: @zero do
      acc -> Decimal.add(acc, delta)
    end
  end

  # A collapsed transfer between the source and a third account removes that
  # account's leg too: its balance before and after.
  defp other_accounts(base, pairs) do
    ids = [base.source.id, base.target.id]

    third =
      for {row, _target_row} <- pairs,
          {account_id, _leg} <- Projection.effects(row).cash,
          account_id not in [nil | ids],
          uniq: true,
          do: account_id

    case third do
      [] ->
        []

      third ->
        collapsed = MapSet.new(pairs, fn {row, _target_row} -> row.id end)

        names =
          Map.new(Repo.all(from(a in CashAccount, where: a.id in ^third, select: {a.id, a.name})))

        rows =
          Repo.all(
            from(t in Transaction,
              where: t.cash_account_id in ^third or t.counter_cash_account_id in ^third
            )
          )

        before = Projection.cash_balances(rows)

        after_collapse =
          rows |> Enum.reject(&MapSet.member?(collapsed, &1.id)) |> Projection.cash_balances()

        for id <- Enum.sort(third) do
          %{
            id: id,
            name: Map.get(names, id),
            balance_before: Map.get(before, id, @zero),
            balance_after: Map.get(after_collapse, id, @zero)
          }
        end
    end
  end

  # A collapsed trade removes its quantity from its depot's position.
  defp positions(pairs) do
    pairs
    |> Enum.flat_map(fn {row, _target_row} ->
      for {depot, security, delta} <- Projection.effects(row).quantities,
          do: {{depot, security}, Decimal.negate(delta)}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {{depot, security}, changes} ->
      %{
        securities_account_id: depot,
        security_id: security,
        quantity_change: Enum.reduce(changes, @zero, &Decimal.add/2)
      }
    end)
    |> Enum.sort_by(&{&1.securities_account_id, &1.security_id})
  end

  # --- the Ledger projection, per day -------------------------------------------------

  # `[{date, balance}]`, ascending: the balance of `account_id` at the end of
  # each day `rows` touch it, from the projection's own running balance
  # (`Projection.cash_balance_series/2`), so anchors replay last within their
  # day exactly as every other read does.
  defp eod(rows, account_id) do
    series = Projection.cash_balance_series(rows, account_id)

    rows
    |> Projection.replay_sort()
    |> Enum.filter(&Map.has_key?(series, &1.id))
    |> Enum.reduce([], fn row, acc -> end_of_day(acc, row.date, Map.fetch!(series, row.id)) end)
    |> Enum.reverse()
  end

  # A later row of the same day replaces the day's balance.
  defp end_of_day([{date, _earlier} | rest] = acc, day, balance) do
    if Date.compare(date, day) == :eq, do: [{date, balance} | rest], else: [{day, balance} | acc]
  end

  defp end_of_day([], day, balance), do: [{day, balance}]

  # The balance at the end of `date`: the last day on or before it, or zero.
  defp balance_on(eod, date) do
    Enum.reduce_while(eod, @zero, fn {day, balance}, acc ->
      if Date.compare(day, date) == :gt, do: {:halt, acc}, else: {:cont, balance}
    end)
  end

  # --- the preview's shape -------------------------------------------------------------

  defp view(plan) do
    %{
      kind: :cash_account,
      source: account_view(plan.source, plan.s_all, plan.source_buckets),
      target: account_view(plan.target, plan.t_all, plan.target_buckets),
      guards: plan.guards,
      internal_transfers: Enum.map(plan.transfers, &transfer_view/1),
      key_equal_pairs: Enum.map(plan.pairs, &pair_view(&1, plan.source.id, plan.target.id)),
      choice_required: plan.pairs != [],
      linked_depots: Enum.map(plan.depots, &%{id: &1.id, name: &1.name}),
      former_names: %{
        appended: plan.appended_names,
        not_kept: plan.names_not_kept,
        after: plan.target.former_names ++ plan.appended_names
      },
      outcomes:
        Map.new(plan.outcomes, fn {collapse?, outcome} -> {collapse?, outcome_view(outcome)} end)
    }
  end

  defp account_view(account, rows, bucket_ids) do
    %{
      id: account.id,
      name: account.name,
      portfolio_id: account.portfolio_id,
      currency_code: account.currency_code,
      liquidity_role: account.liquidity_role,
      bucket_ids: bucket_ids,
      former_names: account.former_names,
      balance: Map.get(Projection.cash_balances(rows), account.id, @zero),
      transaction_count: length(rows)
    }
  end

  defp transfer_view(row) do
    %{
      id: row.id,
      date: row.date,
      gross_amount: row.gross_amount,
      cash_account_id: row.cash_account_id,
      counter_cash_account_id: row.counter_cash_account_id,
      retires_hash: row.import_hash != nil
    }
  end

  defp pair_view({source_row, target_row}, s, t) do
    %{
      source_transaction_id: source_row.id,
      target_transaction_id: target_row.id,
      date: source_row.date,
      type: source_row.type,
      gross_amount: source_row.gross_amount,
      quantity: source_row.quantity,
      price: source_row.price,
      security_id: source_row.security_id,
      securities_account_id: source_row.securities_account_id,
      third_cash_account_id: third_leg(source_row, s, t),
      retires_hash: source_row.import_hash != nil
    }
  end

  # The cash account a paired transfer shares with neither side, if any: a
  # collapse removes its leg there too.
  defp third_leg(row, s, t) do
    Enum.find([row.cash_account_id, row.counter_cash_account_id], &(&1 not in [nil, s, t]))
  end

  defp outcome_view(outcome) do
    %{
      balance: outcome.balance,
      transaction_count: outcome.transaction_count,
      moved_transaction_ids: Enum.map(outcome.moved, & &1.id),
      deleted:
        Enum.map(outcome.deleted, fn %{row: row, reason: reason, superseded_by: by} ->
          %{
            id: row.id,
            date: row.date,
            type: row.type,
            reason: reason,
            superseded_by: by,
            retires_hash: row.import_hash != nil
          }
        end),
      restated_anchors:
        outcome.restatements
        |> Map.values()
        |> Enum.sort_by(&{Date.to_erl(&1.date), &1.row.id})
        |> Enum.map(&Map.drop(Map.put(&1, :id, &1.row.id), [:row])),
      flow_changes: outcome.flow_changes,
      other_accounts: outcome.other_accounts,
      positions: outcome.positions
    }
  end

  # §10: both ids and their updated_at, every row either account references
  # with its updated_at and economic fields, the linked depots, every figure
  # the preview shows and the guard results.
  defp digest(plan, preview) do
    PlanDigest.compute(%{
      preview: preview,
      source: [plan.source.id, plan.source.updated_at],
      target: [plan.target.id, plan.target.updated_at],
      rows: Enum.map(plan.rows, &row_fingerprint/1),
      depots: Enum.map(plan.depots, &[&1.id, &1.updated_at, &1.cash_account_id])
    })
  end

  defp row_fingerprint(row) do
    [
      row.id,
      row.updated_at,
      row.portfolio_id,
      row.type,
      row.date,
      row.currency_code,
      row.gross_amount,
      row.fees,
      row.taxes,
      row.quantity,
      row.price,
      row.cash_account_id,
      row.counter_cash_account_id,
      row.securities_account_id,
      row.counter_securities_account_id,
      row.security_id,
      row.import_hash != nil
    ]
  end

  # --- the writes (§7 steps 2–7) ---------------------------------------------------------

  defp execute(actor, plan, collapse?, choice) do
    outcome = Map.fetch!(plan.outcomes, collapse?)
    record_id = Lifecycle.reserve_merge_record_id()

    with :ok <- delete_rows(actor, outcome.deleted, record_id),
         :ok <- restate_target_anchors(actor, outcome),
         :ok <- move_source_rows(actor, plan, outcome),
         :ok <- move_depots(actor, plan),
         :ok <- linearity_check(plan, outcome),
         {:ok, _deleted} <- Delete.remove(actor, plan.source),
         {:ok, appended, not_kept} <- append_names(actor, plan) do
      Lifecycle.record_merge(
        actor,
        %{
          kind: :cash_account,
          source_id: plan.source.id,
          target_id: plan.target.id,
          portfolio_id: plan.target.portfolio_id,
          source_snapshot: source_snapshot(plan),
          manifest: manifest(plan, outcome, choice, appended, not_kept),
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

  # Steps 2 and 3's removals: each row deleted, journaled, and its hash
  # retired under the record — a transfer as `internal_transfer`; a
  # collapsed row, and a folded legacy anchor that still carries a hash, as
  # `collapsed_duplicate` superseded by the row that stays.
  defp delete_rows(actor, deleted, record_id) do
    each(deleted, fn %{row: row, reason: reason, superseded_by: by} ->
      retire_as =
        if reason == :internal_transfer, do: :internal_transfer, else: :collapsed_duplicate

      with {:ok, _deleted} <- MergeWriter.delete_transaction(actor, row),
           do: MergeWriter.retire_hash(actor, row, record_id, retire_as, by)
    end)
  end

  defp restate_target_anchors(actor, outcome) do
    outcome.restatements
    |> Map.values()
    |> Enum.filter(&(&1.side == :target and not Decimal.equal?(&1.stated, &1.after)))
    |> Enum.sort_by(& &1.row.id)
    |> each(fn %{row: row, after: amount} ->
      with {:ok, _row} <- MergeWriter.reassign_transaction(actor, row, %{gross_amount: amount}),
           do: :ok
    end)
  end

  defp move_source_rows(actor, plan, outcome) do
    s = plan.source.id
    t = plan.target.id

    each(outcome.moved, fn row ->
      attrs =
        %{}
        |> put_leg(:cash_account_id, row.cash_account_id, s, t)
        |> put_leg(:counter_cash_account_id, row.counter_cash_account_id, s, t)
        |> put_restated(Map.get(outcome.restatements, row.id))

      with :ok <- assert_writable(plan, row, attrs),
           {:ok, _row} <- MergeWriter.reassign_transaction(actor, row, attrs),
           do: :ok
    end)
  end

  defp put_leg(attrs, field, s, s, t), do: Map.put(attrs, field, t)
  defp put_leg(attrs, _field, _other, _s, _t), do: attrs

  defp put_restated(attrs, nil), do: attrs
  defp put_restated(attrs, %{after: amount}), do: Map.put(attrs, :gross_amount, amount)

  # §13: the merge writer asserts distinct legs, one portfolio and one
  # currency on the columns it writes; the guards make each a bug catcher.
  defp assert_writable(plan, row, attrs) do
    cash = Map.get(attrs, :cash_account_id, row.cash_account_id)
    counter = Map.get(attrs, :counter_cash_account_id, row.counter_cash_account_id)

    cond do
      cash != nil and cash == counter ->
        identity_failure(row, "both legs would name one account")

      row.portfolio_id != plan.target.portfolio_id ->
        identity_failure(row, "another portfolio")

      plan.source.currency_code != plan.target.currency_code ->
        identity_failure(row, "another currency")

      true ->
        :ok
    end
  end

  defp identity_failure(row, reason),
    do: {:error, {:identity_check_failed, %{transaction_id: row.id, reason: reason}}}

  defp move_depots(actor, plan) do
    each(plan.depots, fn depot ->
      with {:ok, _depot} <- MergeWriter.reassign_depot(actor, depot, plan.target.id), do: :ok
    end)
  end

  # §7 step 6, read back from the database after the writes.
  defp linearity_check(plan, outcome) do
    t = plan.target.id

    merged =
      from(tx in Transaction, where: tx.cash_account_id == ^t or tx.counter_cash_account_id == ^t)
      |> Repo.all()
      |> eod(t)

    Enum.find_value(plan.check_dates, :ok, fn date ->
      expected = Decimal.add(balance_on(outcome.eod_s, date), balance_on(plan.eod_t, date))
      actual = balance_on(merged, date)

      unless Decimal.equal?(expected, actual) do
        {:error, {:identity_check_failed, %{date: date, expected: expected, actual: actual}}}
      end
    end)
  end

  # §7 step 7: the source's names, checked by the guard once the source is
  # gone, appended to the target's former names under the lock taken first.
  defp append_names(actor, plan) do
    target = Repo.one!(from(a in CashAccount, where: a.id == ^plan.target.id, lock: "FOR UPDATE"))
    {appended, not_kept} = AccountNames.merge_names(plan.source, target)

    with {:ok, _target} <- MergeWriter.append_former_names(actor, target, appended),
         do: {:ok, appended, not_kept}
  end

  defp each(items, fun) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case fun.(item) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  # --- the record (§12) -----------------------------------------------------------------

  defp source_snapshot(plan) do
    source = plan.source

    jsonable(%{
      id: source.id,
      name: source.name,
      portfolio_id: source.portfolio_id,
      currency_code: source.currency_code,
      liquidity_role: source.liquidity_role,
      notes: source.notes,
      former_names: source.former_names,
      bucket_ids: plan.source_buckets,
      balance: Map.get(Projection.cash_balances(plan.s_all), source.id, @zero),
      transaction_count: length(plan.s_all),
      linked_depot_ids: Enum.map(plan.depots, & &1.id),
      inserted_at: source.inserted_at,
      updated_at: source.updated_at
    })
  end

  # Per table, every row moved, restated, deleted or re-pointed, and the
  # operator's choice. `restated_anchors` names every anchor that stands on
  # the target for the merged account — the import reads it to report a row
  # booked behind one (§2).
  defp manifest(plan, outcome, choice, appended, not_kept) do
    s = plan.source.id
    t = plan.target.id

    jsonable(%{
      choices: %{collapse_key_equal: choice},
      transactions: %{
        moved:
          Enum.map(outcome.moved, fn row ->
            %{
              id: row.id,
              cash_account_id: [row.cash_account_id, swap(row.cash_account_id, s, t)],
              counter_cash_account_id: [
                row.counter_cash_account_id,
                swap(row.counter_cash_account_id, s, t)
              ]
            }
          end),
        restated:
          for(
            %{row: row, stated: stated, after: amount} = line <-
              Enum.sort_by(Map.values(outcome.restatements), & &1.row.id),
            not Decimal.equal?(stated, amount),
            do: %{
              id: row.id,
              date: row.date,
              side: line.side,
              before: stated,
              other_balance: line.other_balance,
              after: amount
            }
          ),
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
      restated_anchors:
        outcome.restatements
        |> Map.values()
        |> Enum.sort_by(& &1.row.id)
        |> Enum.map(&%{id: &1.row.id, date: &1.date, cash_account_id: t}),
      securities_accounts: %{repointed: Enum.map(plan.depots, & &1.id)},
      cash_account_buckets: %{removed: plan.source_buckets},
      former_names: %{appended: appended, not_kept: not_kept},
      linearity: %{dates_checked: length(plan.check_dates)}
    })
  end

  defp jsonable(%Decimal{} = value), do: Decimal.to_string(Decimal.normalize(value), :normal)
  defp jsonable(%Date{} = value), do: Date.to_iso8601(value)
  defp jsonable(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp jsonable(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp jsonable(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), jsonable(value)} end)

  defp jsonable(list) when is_list(list), do: Enum.map(list, &jsonable/1)
  defp jsonable(value) when is_boolean(value) or is_nil(value), do: value
  defp jsonable(value) when is_atom(value), do: Atom.to_string(value)
  defp jsonable(value), do: value
end
