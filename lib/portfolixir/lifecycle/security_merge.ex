defmodule Portfolixir.Lifecycle.SecurityMerge do
  @moduledoc """
  The merge of one security into another (ADR-0050 §9 up to and including
  its splits and split events, with §8, §10, §12's record write and §13;
  #608). Risk-tier: quantity identity and import idempotency (ADR-0036).

  A merge of a source S into a target T is a relabelling: every booking of S
  is re-pointed onto T, in whatever portfolio and depot it stands. It removes
  only two kinds of row, each journaled:

    * the source rows paired with a target row of equal #533 key (§8), and
      only when the operator chose `collapse_key_equal: true` — each retires
      its hash as `collapsed_duplicate`, superseded by its target twin;
    * the source's split rows the target carries identically — same
      portfolio, same day, same ratio. They **always** collapse, whatever
      `collapse_key_equal` says, and are listed as `collapsed_split`: a
      portfolio holds at most one split per security and day, so a split can
      never move onto the target's, and the #533 key carries no ratio, so a
      split never enters §8's pairing. A split carries no content hash.

  Every other split row of S moves onto T.

  ## The guards (each a refusal that writes nothing)

  `same_security`, `not_live`; then `currency_mismatch`,
  `benchmark_mismatch`, `retired_target` (the target retired while the
  source is live), `quote_basis_mismatch` (`treat_quotes_as_raw` differs
  while the source has quotes), `research_notes` (ADR-0044 §3: notes can
  neither move nor vanish), `policy_rules` (a rule version naming the source,
  answered in ADR-0049 §8's shape: the guard names the rules and carries
  them), `position_buckets_mismatch` (§7's membership rule, per depot, with
  the target security's position in that depot read as T's and the source's
  as S's — `Portfolixir.Lifecycle.PositionMembership`), and the three split
  refusals:

    * `split_ratio_mismatch` — a split of each security in one portfolio on
      one day with different ratios, refused before anything is paired;
    * `split_event_mismatch` — ADR-0028 §2 derives one split-event set per
      security from its split rows in every portfolio, and every raw close,
      the trade-price fallback and the valuation walk rebase on it. The
      merged set is the union of both, so the merge refuses when the union
      carries an event one side lacks while that side has a booking or a
      quote dated before it, naming the event and the side; and when the
      union carries two ratios on one day. One split booked on two dates is
      refused by the first rule, through each side's own split row;
    * `split_linearity` — per portfolio, depot and date, the merged quantity
      must equal the fold of the target's pre-merge rows plus the fold of the
      source's kept rows, each under its own pre-merge split set, for either
      value of the choice. The check runs in exact rational arithmetic
      (`Portfolixir.Lifecycle.MergeFigures.eod_exact/1`), so a collapsed
      split scaling the combined position once — whose rounding at volume
      scale 6 can differ from the two positions rounded apart by a unit per
      split, listed in the preview — never refuses, and any other difference
      does, naming the split date. This catches a target-side split that
      would rescale moved rows (ADR-0028 §1), and a source split that would
      rescale the target's own history.

  and the **resolvability precondition**, `identity_unresolvable`: the
  identity ladder (`Portfolixir.Imports.SecurityResolver`) over the catalog
  the merge would leave behind — the source gone, the target with the
  identifiers it will carry, every former ISIN of either a former ISIN of
  the target — must resolve to the target, under each value of the identity
  choice, every identity of both securities: the stored one, the one the
  importer's journaled create recorded (its name, ISIN, WKN, ticker and
  currency — a file resolves on the identity it carries, not on identifiers
  added since), and each stored identity with a former ISIN in place of its
  ISIN. A security the importer never created is checked on its stored
  identity. The refusal names each identity, its identifiers and what the
  ladder would answer instead (obligation O2); in v1 such a merge is refused,
  because generalized name, WKN and ticker aliases are deferred (§15).

  ## What the merge carries besides the bookings (§9)

    * **Quotes, gap-filled:** the source's quotes on dates the target lacks
      move, each keeping its `source` and so its ADR-0028 §2 basis; on a
      collision the target's wins, and the source's date, close and source
      go into the manifest. The preview counts both and lists the colliding
      quotes whose source row is **manual**. Written row by row by
      `Portfolixir.Catalog.Quotes.merge_gap_fill/4` without a journal entry
      — ADR-0017's quote exemption names that writer; the manifest is the
      record — and both securities' quote invalidation runs.
    * **Configuration**, every change journaled and listed, across active,
      draft and archived plans: category assignments move where the target
      has none in that classification, otherwise the target's wins and the
      source's is deleted; position targets are then evaluated against the
      target's resulting category in their classification — moved, or
      deleted and listed as `collides` (the target already has a row in that
      plan) or `stale` (the row would no longer sit under the target's
      category); position bucket overrides follow §7's membership rule per
      depot (above); security events move, and a same-kind, same-day pair is
      listed as a possible duplicate.
    * **Identifiers**, under the ISIN write lock: the source's identifier
      aliases are reassigned to the target; the source's ISIN is cleared
      first, then written by the operator's **identity choice** when both
      carry one — required, never preselected: `keep_target_isin` (the
      source's ISIN becomes a former ISIN of the target) or
      `adopt_source_isin` (ADR-0029 §3's wrong-order repair: the target
      takes the source's ISIN and its own becomes the former ISIN), the
      former ISIN's `changed_on` the operator's `isin_changed_on` or the
      merge date. An ISIN only the source carries is adopted without a
      choice. WKN, ticker and feed are adopted only where the target lacks
      them; name, asset class and logo follow the target, and every
      difference is listed.

  **The reverse direction.** A refusal whose cause sits on one side only is
  often lifted by merging the other way, so the preview evaluates the
  reverse direction's guards too and reports whether it is mergeable; a
  one-sided refusal names "merge the other way" as its remedy only when that
  merge would pass (`remedy: :merge_other_way`), and otherwise says to keep
  both (`remedy: :keep_both`).

  ## The preview (`preview/2`) — a read

  Both securities with their split events, the guards, the key-equal pairs,
  the split rows that collapse or move, the split events after the merge,
  each depot's bucket plan, the quotes, the configuration and the events the
  merge carries, the identifiers after **each** value of the identity choice
  (with what the target adopts and every difference that follows the
  target), whether the reverse merge is mergeable, and — because the choices
  are not inputs (§10) — the outcome of **both** values of
  `collapse_key_equal`: every position of S (per depot) with its quantity,
  moving-average cost and realized result for S and for T before and for T
  after (`Portfolixir.Ledger.position_costs/1`; the cost basis is
  legitimately restated, because lots combine), the rounding difference each
  split leaves between the combined position rounded once and the two
  rounded apart, and the cash accounts a collapsed booking changes. Its
  `plan_digest` covers all of it.

  ## The apply (`apply/4`)

  The consent (`Portfolixir.Lifecycle.MergeFlow`), then in one transaction,
  locks in a fixed order — the ISIN write lock every identifier writer takes
  first, both securities `FOR UPDATE` in id order (which keeps any new
  booking of either out), every depot the plan writes an override of `FOR NO
  KEY UPDATE` in id order (the lock the bucket writers take), and every
  booking of either security `FOR UPDATE` — the plan recomputed and its
  digest compared (`plan_changed` with the fresh preview on a mismatch);
  then, through `Portfolixir.Lifecycle.MergeWriter`, one journal entry per
  row:

    1. delete the collapsed pairs (retiring their hashes) and the collapsed
       splits;
    2. re-point every other row of S onto T, per row;
    3. the **linearity check**, read back from the database: per depot and
       date the target's rounded quantity is the planned fold, and its exact
       quantity the sum of both securities' exact folds. Otherwise the merge
       rolls back with `identity_check_failed`, a bug catcher, never an
       expected answer;
    4. the bucket plan, through the journaled Buckets writers (one aggregate
       entry per position);
    5. the quotes, gap-filled (no journal entry; the manifest lists each);
    6. the configuration: category assignments, position targets and
       events, one journal entry per row through their contexts' writers;
    7. the identifiers: aliases reassigned, the source's ISIN cleared, the
       identity choice written, the fields the target lacks adopted;
    8. delete S through the hardened delete (§11);
    9. the resolvability precondition again, over the catalog as the merge
       left it: an identity that no longer resolves to the target rolls the
       merge back with `identity_unresolvable`, naming it;
    10. write the merge record (§12) under the id its retirements already
        name.

  The apply takes `plan_digest` (required), `collapse_key_equal` (required
  when the plan lists key-equal pairs), `identity_choice` (required when
  both securities carry an ISIN: `keep_target_isin` or `adopt_source_isin`,
  as an atom or its name) and `isin_changed_on` (optional, a `Date`).
  """

  import Ecto.Query

  import Portfolixir.Lifecycle.MergeFlow,
    only: [guard: 4, guard: 5, passed?: 1, each: 2, jsonable: 1]

  import Portfolixir.Lifecycle.MergeFigures, only: [sample: 2, quantity: 3, exact: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.PositionBucketOverride
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.IdentifierAlias
  alias Portfolixir.Catalog.IdentifierAliases
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Classifications
  alias Portfolixir.Classifications.Assignment
  alias Portfolixir.Clock
  alias Portfolixir.Imports.DedupKey
  alias Portfolixir.Imports.SecurityResolver
  alias Portfolixir.Input.BoundedDate
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Knowledge.SecurityEvent
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.Delete
  alias Portfolixir.Lifecycle.MergeFigures
  alias Portfolixir.Lifecycle.MergeFlow
  alias Portfolixir.Lifecycle.MergeRecord
  alias Portfolixir.Lifecycle.MergeWriter
  alias Portfolixir.Lifecycle.PlanDigest
  alias Portfolixir.Lifecycle.PositionMembership
  alias Portfolixir.Portfolios.PolicyRule
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Portfolios.Target
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Repo

  @zero Decimal.new("0")

  @empty_figures %{quantity: @zero, cost_basis: @zero, avg_cost: @zero, realized_result: @zero}

  # The guards whose cause sits on one side only: merging the other way may
  # lift them.
  @one_sided [
    :retired_target,
    :quote_basis_mismatch,
    :research_notes,
    :policy_rules,
    :position_buckets_mismatch,
    :identity_unresolvable
  ]

  # The operator's answer when both securities carry an ISIN (§9).
  @identity_choices [:keep_target_isin, :adopt_source_isin]

  # Adopted onto the target only where it lacks them (§9); a feed brings its
  # URL along.
  @adoptable [:wkn, :ticker_symbol, :feed]

  # Follow the target; a source value that differs is listed (§9).
  @following [:name, :asset_class, :logo]

  @type refusal ::
          :not_found
          | {:already_merged, MergeRecord.t()}
          | {:refused, [MergeFlow.guard()]}
          | {:plan_changed, map()}
          | {:choice_required, :collapse_key_equal, pos_integer()}
          | {:choice_required, :identity_choice, map()}
          | {:invalid, :plan_digest | :collapse_key_equal | :identity_choice | :isin_changed_on,
             String.t()}
          | {:identity_check_failed, map()}
          | {:identity_unresolvable, [map()]}
          | {:write_refused, String.t(), integer(), Ecto.Changeset.t()}

  # --- the preview ---------------------------------------------------------------

  @doc """
  The preview of merging the security `source_id` into `target_id`: a read.
  `{:ok, preview}` when every guard passes; `{:error, {:refused, guards}}`
  naming the failed guards otherwise; `{:error, :not_found}` for a source
  that does not exist; `{:error, {:already_merged, record}}` for a source a
  merge already took away.
  """
  @spec preview(integer(), integer()) :: {:ok, map()} | {:error, refusal()}
  def preview(source_id, target_id) when is_integer(source_id) and is_integer(target_id) do
    case Lifecycle.merge_of(:security, source_id) do
      %MergeRecord{} = record ->
        {:error, {:already_merged, record}}

      nil ->
        case Repo.get(Security, source_id) do
          nil ->
            {:error, :not_found}

          source ->
            with {:ok, preview, _plan} <-
                   build(source, target_id, Repo.get(Security, target_id), false),
                 do: {:ok, preview}
        end
    end
  end

  # --- the apply -------------------------------------------------------------------

  @doc """
  Merges the security `source_id` into `target_id` on behalf of `actor`,
  under `params`: `plan_digest` (required, the digest of the preview the
  operator approved), `collapse_key_equal` (required when the preview lists
  key-equal pairs), `identity_choice` (required when both securities carry
  an ISIN, `keep_target_isin` or `adopt_source_isin`) and `isin_changed_on`
  (optional: the day the ISIN changed, the former ISIN's `changed_on`; the
  merge date otherwise). See the moduledoc for the steps.

  Answers `{:ok, record, :applied}`, or `{:ok, record, :already_applied}`
  for a retry of a completed merge of the same pair (nothing journaled), or
  `{:error, refusal}` with nothing written.
  """
  @spec apply(Actor.t(), integer(), integer(), map()) ::
          {:ok, MergeRecord.t(), :applied | :already_applied} | {:error, refusal()}
  def apply(%Actor{} = actor, source_id, target_id, params)
      when is_integer(source_id) and is_integer(target_id) and is_map(params) do
    with {:ok, digest, collapse} <- MergeFlow.consent(params),
         {:ok, identity} <- identity_params(params) do
      case MergeFlow.prior_merge(:security, source_id, target_id) do
        :none -> transact(actor, source_id, target_id, digest, {collapse, identity})
        {:ok, record} -> {:ok, record, :already_applied}
        {:error, _refusal} = refused -> refused
      end
    end
  end

  # §9: the identity choice, when given, is one of the two; the date of the
  # ISIN change, when given, a date in the bounded range.
  defp identity_params(params) do
    with {:ok, choice} <- choice_param(Map.get(params, :identity_choice)),
         {:ok, changed_on} <- changed_on_param(Map.get(params, :isin_changed_on)),
         do: {:ok, %{choice: choice, changed_on: changed_on}}
  end

  defp choice_param(nil), do: {:ok, nil}
  defp choice_param(choice) when choice in @identity_choices, do: {:ok, choice}

  defp choice_param(choice) when is_binary(choice) do
    case Enum.find(@identity_choices, &(Atom.to_string(&1) == choice)) do
      nil -> invalid_choice()
      found -> {:ok, found}
    end
  end

  defp choice_param(_other), do: invalid_choice()

  defp invalid_choice,
    do: {:error, {:invalid, :identity_choice, "must be keep_target_isin or adopt_source_isin"}}

  defp changed_on_param(nil), do: {:ok, nil}

  defp changed_on_param(value) do
    case BoundedDate.parse(value) do
      {:ok, date} -> {:ok, date}
      {:error, :out_of_range} -> {:error, {:invalid, :isin_changed_on, BoundedDate.message()}}
      {:error, :invalid} -> {:error, {:invalid, :isin_changed_on, "is not a date (YYYY-MM-DD)"}}
    end
  end

  defp transact(actor, source_id, target_id, digest, choices) do
    fn ->
      case locked_pair(source_id, target_id) do
        {:ok, source, target, depot_ids} ->
          merge_locked(actor, {source, target_id, target}, depot_ids, digest, choices)

        :gone ->
          source_gone(source_id, target_id)
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, {outcome, record}} ->
        {:ok, record, outcome}

      # A row, an override or a depot another writer changed under the merge
      # (the locks make it a bug catcher) is a changed plan like a stale
      # digest.
      {:error, reason} when reason in [:plan_changed, :raced] ->
        fresh_preview(source_id, target_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The fixed lock order (§10): the ISIN write lock every identifier writer
  # takes first, then both securities FOR UPDATE in id order — a new booking
  # of either waits for the merge, and fails on the deleted source after it
  # — then every depot either security's bookings or overrides name, FOR NO
  # KEY UPDATE in id order: the lock the bucket writers take on the depot of
  # a position, which conflicts with no foreign-key check of a booking.
  defp locked_pair(source_id, target_id) do
    ids = Enum.uniq([source_id, target_id])
    {:ok, :locked} = IdentifierAliases.lock_isin_writes(Repo, %{})

    securities =
      Repo.all(from(s in Security, where: s.id in ^ids, order_by: s.id, lock: "FOR UPDATE"))

    case Enum.find(securities, &(&1.id == source_id)) do
      nil ->
        :gone

      source ->
        depot_ids = named_depots(ids)

        Repo.all(
          from(a in SecuritiesAccount,
            where: a.id in ^depot_ids,
            order_by: a.id,
            lock: "FOR NO KEY UPDATE",
            select: a.id
          )
        )

        {:ok, source, Enum.find(securities, &(&1.id == target_id)), MapSet.new(depot_ids)}
    end
  end

  defp named_depots(security_ids) do
    legs =
      Repo.all(
        from(t in Transaction,
          where: t.security_id in ^security_ids,
          select: [t.securities_account_id, t.counter_securities_account_id]
        )
      )

    overrides =
      Repo.all(
        from(o in PositionBucketOverride,
          where: o.security_id in ^security_ids,
          distinct: true,
          select: o.securities_account_id
        )
      )

    (List.flatten(legs) ++ overrides) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()
  end

  # The source vanished between the pre-check and the lock: a concurrent
  # merge of it committed first, or it was deleted.
  defp source_gone(source_id, target_id) do
    case MergeFlow.prior_merge(:security, source_id, target_id) do
      {:ok, record} -> {:already_applied, record}
      {:error, refusal} -> Repo.rollback(refusal)
      :none -> Repo.rollback(:not_found)
    end
  end

  defp merge_locked(actor, {source, target_id, target}, depot_ids, digest, {collapse, identity}) do
    with {:ok, _preview, plan} <- build(source, target_id, target, true),
         :ok <- same_digest(plan, digest),
         :ok <- depots_locked(plan, depot_ids),
         {:ok, collapse?} <- MergeFlow.choose(plan.pairs, collapse),
         {:ok, choice} <- identity_choice(plan, identity.choice),
         choices = %{
           collapse?: collapse?,
           collapse: collapse,
           choice: choice,
           given: identity.choice,
           changed_on: identity.changed_on
         },
         {:ok, record} <- execute(actor, plan, choices) do
      {:applied, record}
    else
      {:error, refusal} -> Repo.rollback(refusal)
    end
  end

  # §9: with an ISIN on both, the operator's identity choice is required and
  # never assumed; otherwise there is nothing to choose.
  defp identity_choice(%{identifiers: %{choice_required: true}} = plan, nil) do
    {:error,
     {:choice_required, :identity_choice,
      %{source_isin: plan.source.isin, target_isin: plan.target.isin}}}
  end

  defp identity_choice(%{identifiers: %{choice_required: true}}, choice), do: {:ok, choice}
  defp identity_choice(_plan, _given), do: {:ok, :no_choice}

  defp same_digest(%{digest: digest}, digest), do: :ok
  defp same_digest(_plan, _approved), do: {:error, :plan_changed}

  # Every depot the plan writes an override of was locked before the plan
  # was read; one that was not is a booking re-pointed under the merge.
  defp depots_locked(plan, depot_ids) do
    if Enum.all?(plan.memberships, &MapSet.member?(depot_ids, &1.securities_account_id)),
      do: :ok,
      else: {:error, :raced}
  end

  defp fresh_preview(source_id, target_id) do
    case preview(source_id, target_id) do
      {:ok, fresh} -> {:error, {:plan_changed, fresh}}
      {:error, refusal} -> {:error, refusal}
    end
  end

  # --- building the plan -------------------------------------------------------------

  defp build(source, target_id, target, lock?) do
    guards = basic_guards(source, target_id, target)

    if passed?(guards) do
      data = load(source, target, lock?)
      plan = plan(source, target, data)
      reverse = reverse(target, source, data)
      guards = Enum.map(guards ++ plan.guards, &with_remedy(&1, reverse, {source, target}))
      plan = %{plan | guards: guards} |> Map.put(:carry, carry(plan))

      if passed?(guards) do
        preview = view(plan, reverse)
        digest = digest(plan, preview)
        {:ok, Map.put(preview, :plan_digest, digest), %{plan | digest: digest}}
      else
        {:error, {:refused, guards}}
      end
    else
      {:error, {:refused, guards}}
    end
  end

  defp basic_guards(source, target_id, nil) do
    [
      same_security_guard(source, target_id),
      guard(
        :not_live,
        "both securities live",
        false,
        "security ##{target_id} does not exist" <> merged_away(target_id)
      )
    ]
  end

  defp basic_guards(source, target_id, %Security{}) do
    [
      same_security_guard(source, target_id),
      guard(:not_live, "both securities live", true, "both securities exist")
    ]
  end

  defp same_security_guard(source, target_id) do
    guard(
      :same_security,
      "not the same security",
      source.id != target_id,
      "two different securities",
      "a security cannot be merged into itself"
    )
  end

  defp merged_away(id) do
    case Lifecycle.merged_into(:security, id) do
      nil -> ""
      survivor -> " (it was merged into security ##{survivor})"
    end
  end

  # The reverse direction's guards, from the same data: whether merging the
  # target into the source would pass.
  defp reverse(target, source, data) do
    refused =
      target
      |> plan(source, data)
      |> Map.fetch!(:guards)
      |> Enum.reject(& &1.passed)
      |> Enum.map(&%{code: &1.code, detail: &1.detail})

    %{mergeable: refused == [], refused: refused}
  end

  defp with_remedy(%{passed: false, code: code} = guard, reverse, {source, target})
       when code in @one_sided do
    if reverse.mergeable do
      guard
      |> Map.put(:remedy, :merge_other_way)
      |> Map.update!(:detail, fn detail ->
        detail <>
          " Or merge the other way: security ##{target.id} into security ##{source.id} " <>
          "passes every guard."
      end)
    else
      codes = Enum.map_join(reverse.refused, ", ", &Atom.to_string(&1.code))

      guard
      |> Map.put(:remedy, :keep_both)
      |> Map.update!(
        :detail,
        &(&1 <>
            " Keep both: security ##{target.id} into security ##{source.id} is refused too " <>
            "(#{codes}).")
      )
    end
  end

  defp with_remedy(guard, _reverse, _pair), do: guard

  # --- loading ---------------------------------------------------------------------

  # Every booking of either security (splits included), and what else either
  # carries that a guard reads; under the apply's locks the bookings are read
  # FOR UPDATE, so none changes between the digest check and the writes. The
  # bucket state is read under the depots' locks, which every override
  # writer of a depot takes first.
  defp load(source, target, lock?) do
    ids = Enum.uniq([source.id, target.id])

    rows =
      from(t in Transaction, where: t.security_id in ^ids, order_by: t.id)
      |> maybe_lock(lock?)
      |> Repo.all()
      |> Repo.preload([:security, :cash_account])

    depot_ids = named_depots(ids)

    depots =
      Map.new(Repo.all(from(a in SecuritiesAccount, where: a.id in ^depot_ids)), &{&1.id, &1})

    portfolio_ids =
      Enum.uniq(
        Enum.map(Map.values(depots), & &1.portfolio_id) ++ Enum.map(rows, & &1.portfolio_id)
      )

    quote_rows = owned_rows(SecurityQuote, ids, lock?, [:date])

    %{
      rows: rows,
      securities: %{source.id => source, target.id => target},
      depots: depots,
      portfolios:
        Map.new(
          Repo.all(from(p in Portfolio, where: p.id in ^portfolio_ids, select: {p.id, p.name}))
        ),
      overrides: override_depots(ids),
      quotes: quote_spans(quote_rows),
      quote_rows: quote_rows,
      notes: counts("security_notes", ids),
      rules: Map.new(ids, &{&1, PolicyRules.referencing(:security, &1)}),
      assignments:
        Assignment
        |> owned_rows(ids, lock?, [:classification_id])
        |> preload_owned([:classification, :category]),
      position_targets:
        Target
        |> owned_rows(ids, lock?, [:id])
        |> preload_owned([:plan, :category, :classification]),
      events: owned_rows(SecurityEvent, ids, lock?, [:date, :id]),
      aliases: owned_rows(IdentifierAlias, ids, lock?, [:former_isin]),
      # The resolvability precondition's catalog: every security and every
      # former ISIN, read under the ISIN write lock the apply holds, and the
      # identity each security's importer create recorded.
      catalog: Repo.all(from(s in Security, order_by: s.id)),
      former_isins: IdentifierAliases.by_former_isin(),
      imported: Map.new(ids, &{&1, imported_identity(&1)})
    }
  end

  defp maybe_lock(query, true), do: lock(query, "FOR UPDATE")
  defp maybe_lock(query, false), do: query

  # The rows of `schema` either security owns, per security, ordered; under
  # the apply's locks read FOR UPDATE, so none changes between the digest
  # check and the writes (a new one waits on the securities' own locks).
  defp owned_rows(schema, ids, lock?, order) do
    from(r in schema, where: r.security_id in ^ids, order_by: ^order)
    |> maybe_lock(lock?)
    |> Repo.all()
    |> Enum.group_by(& &1.security_id)
  end

  defp preload_owned(grouped, preloads),
    do: Map.new(grouped, fn {id, rows} -> {id, Repo.preload(rows, preloads)} end)

  # §9: the identity the importer's journaled create of the security
  # recorded — the name, ISIN, WKN, ticker and currency the file carried —
  # or nil for a security no import created.
  defp imported_identity(id) do
    from(e in Journal.Entry,
      where:
        e.resource_type == "security" and e.operation == :create and
          e.resource_id == ^Integer.to_string(id) and e.actor_type == :import_session,
      order_by: e.id,
      limit: 1,
      select: e.after
    )
    |> Repo.one()
    |> case do
      nil ->
        nil

      image ->
        SecurityResolver.normalize_ref(%{
          isin: image["isin"],
          wkn: image["wkn"],
          ticker: image["ticker_symbol"],
          name: image["name"],
          currency: image["currency_code"]
        })
    end
  end

  defp override_depots(ids) do
    from(o in PositionBucketOverride,
      where: o.security_id in ^ids,
      distinct: true,
      select: {o.security_id, o.securities_account_id}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  # Per security, its number of quotes and the earliest date one is stored
  # for.
  defp quote_spans(quote_rows) do
    Map.new(quote_rows, fn {id, rows} ->
      {id, {length(rows), rows |> Enum.map(& &1.date) |> Enum.min(Date)}}
    end)
  end

  defp counts(table, ids) do
    from(r in table,
      where: r.security_id in ^ids,
      group_by: r.security_id,
      select: {r.security_id, count()}
    )
    |> Repo.all()
    |> Map.new()
  end

  # --- the plan of one direction ---------------------------------------------------------

  defp plan(source, target, data) do
    s = source.id
    t = target.id
    s_all = Enum.filter(data.rows, &(&1.security_id == s))
    t_all = Enum.filter(data.rows, &(&1.security_id == t))
    {s_splits, s_rows} = Enum.split_with(s_all, &split?/1)
    {t_splits, t_rows} = Enum.split_with(t_all, &split?/1)
    splits = split_plan(s_splits, t_splits)

    base = %{
      source: source,
      target: target,
      data: data,
      s_all: s_all,
      t_all: t_all,
      s_rows: s_rows,
      t_rows: t_rows,
      s_splits: s_splits,
      t_splits: t_splits,
      splits: splits,
      source_depots: depots_of(s_rows),
      target_depots: depots_of(t_rows),
      events: %{source: events(s_splits), target: events(t_splits)},
      identifiers: identifiers(source, target, data),
      check_dates:
        [Clock.today() | Enum.map(data.rows, & &1.date)] |> Enum.uniq() |> Enum.sort(Date),
      guards: [],
      digest: nil
    }

    base = Map.put(base, :memberships, memberships(base))

    # A split of another ratio on the same day in the same portfolio refuses
    # before anything is paired (§9): no pair, no outcome, no linearity.
    base =
      if splits.conflicts == [] do
        pairs = pairs(s_rows, t_rows, t)
        outcomes = %{false => outcome(base, []), true => outcome(base, pairs)}
        Map.merge(base, %{pairs: pairs, outcomes: outcomes})
      else
        Map.merge(base, %{pairs: [], outcomes: %{}})
      end

    %{base | guards: guards(base)}
  end

  defp split?(row), do: row.type == "split"

  defp depots_of(rows) do
    rows
    |> Enum.flat_map(&[&1.securities_account_id, &1.counter_securities_account_id])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Each split row of S against T's split of the same portfolio and day:
  # the same normalized ratio collapses, another ratio conflicts, none moves.
  defp split_plan(s_splits, t_splits) do
    by_day = Map.new(t_splits, &{{&1.portfolio_id, &1.date}, &1})

    Enum.reduce(Enum.sort_by(s_splits, & &1.id), %{collapsed: [], moved: [], conflicts: []}, fn
      split, acc ->
        case Map.get(by_day, {split.portfolio_id, split.date}) do
          nil ->
            Map.update!(acc, :moved, &(&1 ++ [split]))

          twin ->
            if ratio(twin) == ratio(split),
              do: Map.update!(acc, :collapsed, &(&1 ++ [{split, twin}])),
              else: Map.update!(acc, :conflicts, &(&1 ++ [{split, twin}]))
        end
    end)
  end

  # ADR-0028 §1: a ratio is compared in lowest terms.
  defp ratio(%{split_ratio_numerator: p, split_ratio_denominator: q}) do
    gcd = Integer.gcd(p, q)
    {div(p, gcd), div(q, gcd)}
  end

  # The security-level split events (ADR-0028 §2): one per date and
  # normalized ratio, whatever portfolios carry the rows.
  defp events(splits) do
    splits
    |> Enum.map(&{&1.date, ratio(&1)})
    |> Enum.uniq()
    |> Enum.sort_by(fn {date, {p, q}} -> {Date.to_erl(date), p, q} end)
  end

  # §8: a source row other than a split whose #533 key, rewritten onto the
  # target, equals a target row's key is paired with it one-to-one, lowest
  # id first.
  defp pairs(s_rows, t_rows, t) do
    targets = Enum.group_by(t_rows, &DedupKey.of/1)

    s_rows
    |> Enum.group_by(&DedupKey.of(%{&1 | security_id: t}))
    |> Enum.flat_map(fn {key, sources} ->
      Enum.zip(Enum.sort_by(sources, & &1.id), Enum.sort_by(Map.get(targets, key, []), & &1.id))
    end)
    |> Enum.sort_by(fn {source_row, _target_row} -> source_row.id end)
  end

  # --- view membership, per depot ---------------------------------------------------------

  # Every depot where S holds bookings or carries an override: the write
  # that keeps the effective buckets of its position — or `:refuse`.
  defp memberships(base) do
    s = base.source.id
    t = base.target.id

    (base.source_depots ++ Map.get(base.data.overrides, s, []))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn depot_id ->
      defaults = Buckets.depot_default_bucket_ids(depot_id)
      s_override = Buckets.position_override(depot_id, s)
      t_override = Buckets.position_override(depot_id, t)
      s_effective = PositionMembership.effective(s_override, defaults)
      t_effective = PositionMembership.effective(t_override, defaults)
      source_holds = depot_id in base.source_depots
      target_holds = depot_id in base.target_depots

      %{
        securities_account_id: depot_id,
        securities_account_name: depot_name(base, depot_id),
        source_holds: source_holds,
        target_holds: target_holds,
        source_override: s_override,
        target_override: t_override,
        source_buckets: s_effective,
        target_buckets: t_effective,
        action:
          PositionMembership.action(
            %{holds: source_holds, override: s_override, effective: s_effective},
            %{holds: target_holds, override: t_override, effective: t_effective}
          )
      }
    end)
  end

  defp depot_name(base, depot_id) do
    case Map.get(base.data.depots, depot_id) do
      %SecuritiesAccount{name: name} -> name
      nil -> nil
    end
  end

  # --- one value of the choice ------------------------------------------------------------

  defp outcome(base, pairs) do
    collapsed = MapSet.new(pairs, fn {source_row, _target_row} -> source_row.id end)
    moved_rows = Enum.reject(base.s_rows, &MapSet.member?(collapsed, &1.id))
    moved = Enum.sort_by(moved_rows ++ base.splits.moved, & &1.id)

    deleted =
      Enum.map(pairs, fn {source_row, target_row} ->
        %{row: source_row, reason: :collapsed_duplicate, superseded_by: target_row.id}
      end) ++
        Enum.map(base.splits.collapsed, fn {split, twin} ->
          %{row: split, reason: :collapsed_split, superseded_by: twin.id}
        end)

    after_rows = base.t_all ++ Enum.map(moved, &relabel(&1, base.target))
    kept = Enum.reject(base.s_all, &MapSet.member?(collapsed, &1.id))

    folds = %{
      combined: MergeFigures.eod_positions(after_rows),
      target: MergeFigures.eod_positions(base.t_all),
      source: MergeFigures.eod_positions(kept),
      combined_exact: MergeFigures.eod_exact(after_rows),
      target_exact: MergeFigures.eod_exact(base.t_all),
      source_exact: MergeFigures.eod_exact(kept)
    }

    %{
      moved: moved,
      deleted: Enum.sort_by(deleted, & &1.row.id),
      transaction_count: length(after_rows),
      folds: folds,
      linearity: linearity(base, folds),
      positions: positions(base, Ledger.position_costs(after_rows)),
      rounding_differences: rounding_differences(base, folds),
      cash_accounts: MergeFigures.collapsed_cash_accounts(pairs)
    }
  end

  defp relabel(row, %Security{id: id} = target), do: %{row | security_id: id, security: target}

  # Every depot S holds bookings in: its figures for S and for T before, and
  # for T after, from the ledger's own moving-average fold.
  defp positions(base, after_costs) do
    s = base.source.id
    t = base.target.id
    before_costs = Ledger.position_costs(base.data.rows)

    for depot_id <- base.source_depots do
      %{
        securities_account_id: depot_id,
        securities_account_name: depot_name(base, depot_id),
        portfolio_id: depot_portfolio(base, depot_id),
        source: figures(before_costs, {depot_id, s}, true),
        target: figures(before_costs, {depot_id, t}, depot_id in base.target_depots),
        after: figures(after_costs, {depot_id, t}, true)
      }
    end
  end

  defp depot_portfolio(base, depot_id) do
    case Map.get(base.data.depots, depot_id) do
      %SecuritiesAccount{portfolio_id: portfolio_id} -> portfolio_id
      nil -> nil
    end
  end

  defp figures(_costs, _key, false), do: nil
  defp figures(costs, key, true), do: Map.get(costs, key, @empty_figures)

  # §9 linearity, in exact arithmetic: at every date either security has a
  # row and today, per depot, the merged quantity equals the target's fold
  # plus the source's kept fold, each under its own pre-merge splits. The
  # first difference, or nil.
  defp linearity(base, folds) do
    s = base.source.id
    t = base.target.id
    depots = Enum.uniq(base.source_depots ++ base.target_depots) |> Enum.sort()
    combined = sample(folds.combined_exact, base.check_dates)
    target = sample(folds.target_exact, base.check_dates)
    source = sample(folds.source_exact, base.check_dates)

    Enum.find_value(base.check_dates, fn date ->
      Enum.find_value(depots, fn depot_id ->
        merged = exact(combined, date, {depot_id, t})

        apart =
          MergeFigures.add(exact(target, date, {depot_id, t}), exact(source, date, {depot_id, s}))

        if merged != apart,
          do: %{date: date, securities_account_id: depot_id, merged: merged, apart: apart}
      end)
    end)
  end

  # ADR-0028 §3 rounds a split's scaled position once at volume scale 6. The
  # merged security scales the combined position once; apart, each security's
  # position was rounded on its own. Where the two differ at the end of a
  # split's day, per depot of its portfolio, the difference is listed —
  # expected, never a failure.
  defp rounding_differences(base, folds) do
    s = base.source.id
    t = base.target.id
    splits = base.t_splits ++ base.splits.moved
    dates = splits |> Enum.map(& &1.date) |> Enum.uniq()
    combined = sample(folds.combined, dates)
    target = sample(folds.target, dates)
    source = sample(folds.source, dates)
    depots = Enum.uniq(base.source_depots ++ base.target_depots) |> Enum.sort()

    for split <- Enum.sort_by(splits, &{Date.to_erl(&1.date), &1.id}),
        depot_id <- depots,
        depot_portfolio(base, depot_id) == split.portfolio_id,
        merged = quantity(combined, split.date, {depot_id, t}),
        apart =
          Decimal.add(
            quantity(target, split.date, {depot_id, t}),
            quantity(source, split.date, {depot_id, s})
          ),
        not Decimal.equal?(merged, apart) do
      {p, q} = ratio(split)

      %{
        portfolio_id: split.portfolio_id,
        securities_account_id: depot_id,
        securities_account_name: depot_name(base, depot_id),
        date: split.date,
        split_transaction_id: split.id,
        ratio: %{numerator: p, denominator: q},
        combined: merged,
        separate_sum: apart,
        difference: Decimal.sub(merged, apart)
      }
    end
  end

  # --- the guards of one direction ---------------------------------------------------------

  defp guards(base) do
    [
      currency_guard(base),
      benchmark_guard(base),
      retired_guard(base),
      quote_basis_guard(base),
      notes_guard(base),
      rules_guard(base),
      membership_guard(base),
      split_ratio_guard(base),
      split_event_guard(base),
      identity_guard(base)
    ] ++ linearity_guard(base)
  end

  defp currency_guard(%{source: source, target: target}) do
    guard(
      :currency_mismatch,
      "same currency",
      source.currency_code == target.currency_code,
      "both securities trade in #{target.currency_code}",
      "the securities trade in #{source.currency_code} and #{target.currency_code}: a merge " <>
        "never converts a booked amount"
    )
  end

  defp benchmark_guard(%{source: source, target: target}) do
    guard(
      :benchmark_mismatch,
      "both or neither a benchmark",
      source.is_benchmark == target.is_benchmark,
      "both securities are #{benchmark_word(target)}",
      "the source is #{benchmark_word(source)} and the target #{benchmark_word(target)}: mark " <>
        "both the same first, so no comparison changes its reference behind your back"
    )
  end

  defp benchmark_word(%Security{is_benchmark: true}), do: "a benchmark"
  defp benchmark_word(%Security{}), do: "not a benchmark"

  defp retired_guard(%{source: source, target: target}) do
    guard(
      :retired_target,
      "the target not retired while the source is live",
      not (target.is_retired and not source.is_retired),
      "the target is live, or both are retired",
      "security ##{target.id} is retired and security ##{source.id} is live: the merge " <>
        "would move live bookings onto a retired security."
    )
  end

  defp quote_basis_guard(%{source: source, target: target, data: data}) do
    {count, _first} = Map.get(data.quotes, source.id, {0, nil})

    guard(
      :quote_basis_mismatch,
      "the same quote basis while the source has quotes",
      count == 0 or source.treat_quotes_as_raw == target.treat_quotes_as_raw,
      "the quotes keep their basis",
      "security ##{source.id} has #{count} quote(s), and only one of the two treats its " <>
        "synced quotes as raw: the moved quotes would change their basis (ADR-0028 §2). Set " <>
        "the flag the same on both first."
    )
  end

  defp notes_guard(%{source: source, data: data}) do
    count = Map.get(data.notes, source.id, 0)

    guard(
      :research_notes,
      "no research notes on the source",
      count == 0,
      "the source carries no research notes",
      "security ##{source.id} carries #{count} research note(s): the research log is " <>
        "append-only (ADR-0044 §3), so its notes can neither move nor vanish."
    )
  end

  defp rules_guard(%{source: source, data: data}) do
    rules = Map.get(data.rules, source.id, [])
    names = Enum.map_join(rules, ", ", &"\"#{&1.name}\" (#{&1.status})")

    :policy_rules
    |> guard(
      "no policy rule version naming the source",
      rules == [],
      "no policy rule reads the source",
      "security ##{source.id} is read by #{length(rules)} policy rule(s): #{names}. A rule's " <>
        "versions keep their subject as the record of what the standard was (ADR-0049 §8), " <>
        "so a merge can neither re-point nor drop them."
    )
    |> Map.put(:policy_rules, Enum.map(rules, &rule_view/1))
  end

  defp rule_view(%PolicyRule{} = rule),
    do: %{id: rule.id, name: rule.name, status: rule.status}

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: value != nil

  # §9's resolvability precondition: every identity of both securities
  # resolves to the target over the catalog the merge leaves, under each
  # value of the identity choice (see the moduledoc).
  defp identity_guard(base) do
    failures = unresolvable(base)

    :identity_unresolvable
    |> guard(
      "every identity of both securities resolves to the target after the merge",
      failures == [],
      "every stored, imported and former identity of both securities finds the target",
      Enum.map_join(failures, " ", &unresolvable_text(base, &1)) <>
        " A Portfolio Performance file resolves on the identity it carries, not on identifiers " <>
        "added since, so the next import of such a file would create or pick another security. " <>
        "ADR-0050 §9 refuses the merge rather than leave it unresolved (generalized name, WKN " <>
        "and ticker aliases are deferred): give both securities the identifier the file " <>
        "carries, or rename or merge the security it collides with, then preview again."
    )
    |> Map.put(:unresolvable, failures)
  end

  defp unresolvable(base) do
    refs = identity_refs(base.source, base.data) ++ identity_refs(base.target, base.data)

    base.identifiers.outcomes
    |> Enum.sort()
    |> Enum.flat_map(fn {choice, after_identity} ->
      index = post_merge_index(base.source, base.target, after_identity, base.data)

      for entry <- refs,
          outcome = SecurityResolver.resolve(entry.ref, index),
          not resolves_to?(outcome, base.target.id),
          do: Map.merge(entry, %{outcome: resolution_view(outcome), identity_choice: choice})
    end)
    |> Enum.group_by(&Map.take(&1, [:security_id, :identity, :ref, :outcome]))
    |> Enum.map(fn {entry, found} ->
      Map.put(entry, :identity_choices, Enum.map(found, & &1.identity_choice))
    end)
    |> Enum.sort_by(&{&1.security_id, identity_rank(&1.identity), inspect(&1.ref)})
  end

  defp identity_rank(:stored), do: 0
  defp identity_rank(:imported), do: 1
  defp identity_rank(:former_isin), do: 2

  defp resolves_to?({:match, %Security{id: id}, _tier}, id), do: true
  defp resolves_to?(_outcome, _target_id), do: false

  defp resolution_view(:create), do: %{kind: :none, candidates: []}

  defp resolution_view({:match, %Security{id: id}, _tier}),
    do: %{kind: :other_security, candidates: [id]}

  defp resolution_view({:conflict, %{type: type, candidates: candidates}}),
    do: %{kind: type, candidates: Enum.map(candidates, & &1.id)}

  # Every identity through which `security` resolves: the stored one, the
  # one its importer create recorded, and the stored one with each former
  # ISIN in place of its ISIN — blank ones left out, each once.
  defp identity_refs(security, data) do
    stored = stored_ref(security)

    imported =
      case Map.get(data.imported, security.id) do
        nil -> []
        ref -> [{:imported, ref}]
      end

    formers =
      for alias_row <- Map.get(data.aliases, security.id, []),
          do: {:former_isin, %{stored | isin: alias_row.former_isin}}

    ([{:stored, stored}] ++ imported ++ formers)
    |> Enum.reject(fn {_identity, ref} -> SecurityResolver.blank_ref?(ref) end)
    |> Enum.uniq_by(&elem(&1, 1))
    |> Enum.map(fn {identity, ref} ->
      %{security_id: security.id, identity: identity, ref: ref}
    end)
  end

  defp stored_ref(security) do
    SecurityResolver.normalize_ref(%{
      isin: security.isin,
      wkn: security.wkn,
      ticker: security.ticker_symbol,
      name: security.name,
      currency: security.currency_code
    })
  end

  # The catalog the merge leaves: the source gone, the target with the
  # identifiers it will carry, and every former ISIN of either (plus the one
  # the choice records) a former ISIN of the target.
  defp post_merge_index(source, target, after_identity, data) do
    target_after = %{
      target
      | isin: after_identity.isin,
        wkn: after_identity.wkn,
        ticker_symbol: after_identity.ticker_symbol,
        feed: after_identity.feed
    }

    securities =
      Enum.reject(data.catalog, &(&1.id in [source.id, target.id])) ++ [target_after]

    former_isins =
      data.former_isins
      |> Map.new(fn {isin, id} -> {isin, if(id == source.id, do: target.id, else: id)} end)
      |> Map.merge(Map.new(after_identity.former_isins, &{&1, target.id}))

    SecurityResolver.index_from(securities, former_isins)
  end

  defp unresolvable_text(base, failure) do
    choices =
      case failure.identity_choices do
        [:no_choice] -> ""
        [_first, _second] -> ""
        [only] -> " under #{only}"
      end

    "Security ##{failure.security_id}'s #{identity_text(failure)} (#{ref_text(failure.ref)}) " <>
      "#{outcome_text(failure.outcome)} after merging security ##{base.source.id} into " <>
      "security ##{base.target.id}#{choices}."
  end

  defp identity_text(%{identity: :stored}), do: "stored identity"

  defp identity_text(%{identity: :imported}),
    do: "identity as its Portfolio Performance import recorded it"

  defp identity_text(%{identity: :former_isin, ref: ref}), do: "former ISIN #{ref.isin}"

  defp ref_text(ref) do
    [
      {"ISIN", ref.isin},
      {"WKN", ref.wkn},
      {"ticker", ref.ticker},
      {"name", ref.name && "\"#{ref.name}\""},
      {"currency", ref.currency}
    ]
    |> Enum.reject(&is_nil(elem(&1, 1)))
    |> Enum.map_join(", ", fn {label, value} -> "#{label} #{value}" end)
  end

  defp outcome_text(%{kind: :none}),
    do: "would find no security, and an import of a file carrying it would create a new one,"

  defp outcome_text(%{kind: :ambiguous, candidates: ids}),
    do: "would match #{ids_text(ids)} alike, a decision on every import,"

  defp outcome_text(%{kind: :identifier_veto, candidates: ids}),
    do: "would conflict with #{ids_text(ids)} on a stronger identifier"

  defp outcome_text(%{kind: :cross_tier, candidates: ids}),
    do: "would point at #{ids_text(ids)} at once"

  defp outcome_text(%{kind: :other_security, candidates: ids}),
    do: "would resolve to #{ids_text(ids)}"

  defp ids_text(ids), do: Enum.map_join(ids, " and ", &"security ##{&1}")

  # --- the identifiers after each identity choice (§9) ------------------------------------

  defp identifiers(source, target, data) do
    both? = present?(source.isin) and present?(target.isin)
    adopted = adopted_fields(source, target, both?)

    kept =
      Enum.map(
        Map.get(data.aliases, target.id, []) ++ Map.get(data.aliases, source.id, []),
        & &1.former_isin
      )

    outcomes =
      if both? do
        %{
          keep_target_isin: after_identity(target, adopted, target.isin, [source.isin | kept]),
          adopt_source_isin: after_identity(target, adopted, source.isin, [target.isin | kept])
        }
      else
        %{no_choice: after_identity(target, adopted, target.isin || source.isin, kept)}
      end

    %{
      choice_required: both?,
      outcomes: outcomes,
      adopted: adopted,
      differences: differences(source, target, adopted),
      aliases: Map.get(data.aliases, source.id, [])
    }
  end

  # WKN, ticker and feed where the target lacks them (a feed with its URL
  # where the target has none), and an ISIN only the source carries.
  defp adopted_fields(source, target, both_isins?) do
    isin =
      if not both_isins? and present?(source.isin) and not present?(target.isin),
        do: [%{field: :isin, value: source.isin}],
        else: []

    fields =
      for field <- @adoptable,
          not present?(Map.get(target, field)),
          present?(Map.get(source, field)),
          do: %{field: field, value: Map.get(source, field)}

    feed_url =
      if Enum.any?(fields, &(&1.field == :feed)) and present?(source.feed_url) and
           not present?(target.feed_url),
         do: [%{field: :feed_url, value: source.feed_url}],
         else: []

    isin ++ fields ++ feed_url
  end

  defp after_identity(target, adopted, isin, former_isins) do
    adopted = Map.new(adopted, &{&1.field, &1.value})

    %{
      isin: isin,
      wkn: Map.get(adopted, :wkn, target.wkn),
      ticker_symbol: Map.get(adopted, :ticker_symbol, target.ticker_symbol),
      feed: Map.get(adopted, :feed, target.feed),
      name: target.name,
      asset_class: target.asset_class,
      former_isins: former_isins |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()
    }
  end

  # Every value of the source that the target's replaces: name, asset class
  # and logo always follow the target, and so do a WKN, ticker or feed the
  # target already has.
  defp differences(source, target, adopted) do
    adopted_fields = Enum.map(adopted, & &1.field)

    for field <- @following ++ @adoptable,
        field not in adopted_fields,
        from = field_value(source, field),
        from != nil,
        from != field_value(target, field),
        do: %{field: field, source: from, target: field_value(target, field)}
  end

  defp field_value(security, :logo), do: get_in(security.attributes || %{}, ["logo_path"])
  defp field_value(security, field), do: Map.get(security, field)

  # --- what the merge carries besides the bookings (§9) -----------------------------------

  defp carry(plan) do
    %{
      quotes: quote_plan(plan),
      assignments: assignment_plan(plan),
      position_targets: position_target_plan(plan),
      events: event_plan(plan)
    }
  end

  # Quotes, gap-filled: the source's on dates the target lacks move; on a
  # collision the target's wins and the source's is dropped.
  defp quote_plan(%{source: source, target: target, data: data}) do
    t_by_date = Map.new(Map.get(data.quote_rows, target.id, []), &{&1.date, &1})
    s_quotes = Map.get(data.quote_rows, source.id, [])
    {collisions, moved} = Enum.split_with(s_quotes, &Map.has_key?(t_by_date, &1.date))

    %{
      source_count: length(s_quotes),
      moved: moved,
      dropped: Enum.map(collisions, &{&1, Map.fetch!(t_by_date, &1.date)})
    }
  end

  # Per classification of the source: moved where the target has no
  # assignment in it, dropped (the target's wins) otherwise.
  defp assignment_plan(%{source: source, target: target, data: data}) do
    t_by_class = Map.new(Map.get(data.assignments, target.id, []), &{&1.classification_id, &1})

    for assignment <- Map.get(data.assignments, source.id, []) do
      twin = Map.get(t_by_class, assignment.classification_id)
      %{assignment: assignment, twin: twin, action: if(twin, do: :drop, else: :move)}
    end
  end

  # Each position target of the source, in any plan status, against the
  # target's resulting category in its classification: it collides where the
  # target has a row in that plan, goes stale where it would not sit under
  # the target's category, and moves otherwise.
  defp position_target_plan(%{source: source, target: target, data: data}) do
    rows = Map.get(data.position_targets, source.id, [])
    target_plans = MapSet.new(Map.get(data.position_targets, target.id, []), & &1.plan_id)
    classifications = rows |> Enum.map(& &1.classification) |> Enum.uniq_by(& &1.id)

    resulting =
      Map.new(classifications, &{&1.id, resulting_category(&1, source, target, data)})

    ancestors =
      Map.new(classifications, fn classification ->
        {classification.id,
         Targets.category_ancestors(Classifications.list_categories(classification.id))}
      end)

    for row <- rows do
      category = Map.fetch!(resulting, row.classification_id)
      covering = Map.get(Map.fetch!(ancestors, row.classification_id), category, MapSet.new())

      {action, reason} =
        cond do
          MapSet.member?(target_plans, row.plan_id) -> {:drop, :collides}
          not MapSet.member?(covering, row.category_id) -> {:drop, :stale}
          true -> {:move, nil}
        end

      %{row: row, action: action, reason: reason, resulting_category_id: category}
    end
  end

  # The target's category in a classification after the merge: a custom
  # tree's stored assignment of the target, else the source's that moves; a
  # built-in tree's derived one of the target (its fields follow the target).
  defp resulting_category(%{built_in: true} = classification, _source, target, _data) do
    case Classifications.security_category_map(classification.id) do
      {:ok, map} -> Map.get(map, target.id)
      {:error, :not_found} -> nil
    end
  end

  defp resulting_category(classification, source, target, data) do
    Enum.find_value([target, source], fn security ->
      data.assignments
      |> Map.get(security.id, [])
      |> Enum.find_value(&(&1.classification_id == classification.id and &1.category_id))
    end)
  end

  # Every event of the source moves; a same-kind, same-day pair is listed.
  defp event_plan(%{source: source, target: target, data: data}) do
    s_events = Map.get(data.events, source.id, [])
    t_events = Map.get(data.events, target.id, [])

    %{
      moved: s_events,
      possible_duplicates:
        for(
          event <- s_events,
          twin <- t_events,
          event.kind == twin.kind and event.date == twin.date,
          do: %{
            source_event_id: event.id,
            target_event_id: twin.id,
            kind: event.kind,
            date: event.date
          }
        )
    }
  end

  defp membership_guard(base) do
    refused = Enum.filter(base.memberships, &(&1.action in [:refuse, :refuse_carry]))

    guard(
      :position_buckets_mismatch,
      "same view membership for every position",
      refused == [],
      "every position keeps its effective buckets",
      Enum.map_join(refused, " ", &membership_detail/1)
    )
  end

  defp membership_detail(%{action: :refuse} = entry) do
    "In depot \"#{entry.securities_account_name}\" the source's position sits in the buckets " <>
      "#{inspect(entry.source_buckets)} and the target's in " <>
      "#{inspect(entry.target_buckets)}: view membership is retroactive, so the merge would " <>
      "move the target's history between views. Give both positions the same buckets, then " <>
      "preview again."
  end

  defp membership_detail(%{action: :refuse_carry} = entry) do
    "In depot \"#{entry.securities_account_name}\" the source's position carries an override " <>
      "with more than one scope bucket #{inspect(entry.source_buckets)}, stored before a " <>
      "position could hold only one: the target's position cannot take it. Keep one scope " <>
      "bucket in that override, then preview again."
  end

  defp split_ratio_guard(%{splits: %{conflicts: conflicts}} = base) do
    guard(
      :split_ratio_mismatch,
      "no split of another ratio on the same day in the same portfolio",
      conflicts == [],
      "every same-day split of both in one portfolio has one ratio",
      Enum.map_join(conflicts, " ", fn {split, twin} ->
        "On #{split.date} in portfolio \"#{portfolio_name(base, split.portfolio_id)}\" the " <>
          "source splits #{ratio_text(split)} and the target #{ratio_text(twin)}: one split " <>
          "cannot carry two ratios. Delete the wrong split row, then preview again."
      end)
    )
  end

  defp split_event_guard(base) do
    s_events = MapSet.new(base.events.source)
    t_events = MapSet.new(base.events.target)

    issues =
      two_ratios(s_events, t_events) ++
        lacking(base, MapSet.difference(t_events, s_events), :source) ++
        lacking(base, MapSet.difference(s_events, t_events), :target)

    guard(
      :split_event_mismatch,
      "one split-event set for the merged security",
      issues == [],
      "the merged split events rebase no history",
      Enum.join(issues, " ")
    )
  end

  # Two ratios on one day, whatever portfolios carry them.
  defp two_ratios(s_events, t_events) do
    for {date, ratios} <- group_events(MapSet.union(s_events, t_events)),
        length(ratios) > 1 do
      by_side =
        Enum.map_join(ratios, " and ", fn ratio ->
          sides =
            [{s_events, "the source"}, {t_events, "the target"}]
            |> Enum.filter(fn {events, _side} -> MapSet.member?(events, {date, ratio}) end)
            |> Enum.map_join(" and ", &elem(&1, 1))

          "#{event_ratio(ratio)} (#{sides})"
        end)

      "On #{date} the securities split #{by_side}: one event cannot carry two ratios. " <>
        "Delete the wrong split row, then preview again."
    end
  end

  defp group_events(events) do
    events
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort_by(fn {date, _ratios} -> Date.to_erl(date) end)
    |> Enum.map(fn {date, ratios} -> {date, Enum.sort(ratios)} end)
  end

  # An event of the other side this side lacks, while this side has a
  # booking or a quote dated before it.
  defp lacking(base, events, side) do
    security = if side == :source, do: base.source, else: base.target
    rows = if side == :source, do: base.s_all, else: base.t_all
    other = if side == :source, do: "target", else: "source"
    first_row = rows |> Enum.map(& &1.date) |> Enum.min(Date, fn -> nil end)
    {_count, first_quote} = Map.get(base.data.quotes, security.id, {0, nil})

    for {date, ratio} <- Enum.sort_by(events, fn {date, _ratio} -> Date.to_erl(date) end),
        earlier = earlier_record(first_row, first_quote, date),
        earlier != nil do
      "The #{other}'s split of #{date} (#{event_ratio(ratio)}) is not a split of the " <>
        "#{side}, which has #{earlier} before it: the merged split events would rebase the " <>
        "#{side}'s history. Book the split on the #{side} first (ADR-0028 §1), or delete the " <>
        "wrong split row, then preview again."
    end
  end

  defp earlier_record(first_row, first_quote, date) do
    cond do
      first_row != nil and Date.compare(first_row, date) == :lt ->
        "a booking of #{first_row}"

      first_quote != nil and Date.compare(first_quote, date) == :lt ->
        "a quote of #{first_quote}"

      true ->
        nil
    end
  end

  # Only once the ratios agree: a conflict refuses before anything is
  # paired, and the outcomes are not computed.
  defp linearity_guard(%{splits: %{conflicts: [_ | _]}}), do: []

  defp linearity_guard(base) do
    failures =
      for collapse? <- [false, true],
          failure = base.outcomes[collapse?].linearity,
          failure != nil,
          do: {collapse?, failure}

    [
      guard(
        :split_linearity,
        "no split rescales bookings it did not scale before",
        failures == [],
        "every booking is scaled by the same splits after the merge",
        linearity_detail(base, failures)
      )
    ]
  end

  defp linearity_detail(_base, []), do: ""

  defp linearity_detail(base, [{collapse?, failure} | _rest] = failures) do
    depot = Map.get(base.data.depots, failure.securities_account_id)
    portfolio_id = depot && depot.portfolio_id

    split_text =
      (base.t_splits ++ base.s_splits)
      |> Enum.filter(&(&1.portfolio_id == portfolio_id and &1.date == failure.date))
      |> Enum.map(&ratio_text/1)
      |> Enum.uniq()
      |> case do
        [] -> "the split of #{failure.date}"
        ratios -> "the split of #{failure.date} (#{Enum.join(ratios, ", ")})"
      end

    choices =
      case Enum.map(failures, &elem(&1, 0)) do
        [_one] -> if collapse?, do: " with collapse", else: " without collapse"
        _both -> ""
      end

    "#{String.capitalize(split_text)} in portfolio \"#{portfolio_name(base, portfolio_id)}\" " <>
      "would rescale bookings it did not scale before: in depot \"#{depot && depot.name}\" " <>
      "on #{failure.date} the merged position would be " <>
      "#{MergeFigures.to_decimal(failure.merged)}, where the two securities' positions sum to " <>
      "#{MergeFigures.to_decimal(failure.apart)}#{choices}. A split row scales every position " <>
      "of its security in its portfolio, so the merge would change quantities it only moves. " <>
      "Book the split on both securities in the same portfolios first (ADR-0028 §1), or delete " <>
      "the wrong split row, then preview again."
  end

  defp portfolio_name(base, portfolio_id), do: Map.get(base.data.portfolios, portfolio_id)

  defp ratio_text(split), do: event_ratio(ratio(split))
  defp event_ratio({p, q}), do: "#{p}:#{q}"

  # --- the preview's shape -------------------------------------------------------------

  defp view(plan, reverse) do
    %{
      kind: :security,
      source: security_view(plan.source, plan.s_all, plan.events.source),
      target: security_view(plan.target, plan.t_all, plan.events.target),
      guards: plan.guards,
      key_equal_pairs: Enum.map(plan.pairs, &pair_view/1),
      choice_required: plan.pairs != [],
      splits: %{
        collapsed:
          Enum.map(plan.splits.collapsed, fn {split, twin} ->
            %{
              source_transaction_id: split.id,
              target_transaction_id: twin.id,
              portfolio_id: split.portfolio_id,
              date: split.date,
              ratio: ratio_view(ratio(split))
            }
          end),
        moved:
          Enum.map(plan.splits.moved, fn split ->
            %{
              id: split.id,
              portfolio_id: split.portfolio_id,
              date: split.date,
              ratio: ratio_view(ratio(split))
            }
          end)
      },
      split_events: %{
        source: Enum.map(plan.events.source, &event_view/1),
        target: Enum.map(plan.events.target, &event_view/1),
        after:
          (plan.events.source ++ plan.events.target)
          |> Enum.uniq()
          |> Enum.sort_by(fn {date, {p, q}} -> {Date.to_erl(date), p, q} end)
          |> Enum.map(&event_view/1)
      },
      position_buckets: Enum.map(plan.memberships, &membership_view/1),
      quotes: quotes_view(plan.carry.quotes),
      configuration: %{
        category_assignments: Enum.map(plan.carry.assignments, &assignment_view/1),
        position_targets: Enum.map(plan.carry.position_targets, &position_target_view/1)
      },
      events: %{
        moved: Enum.map(plan.carry.events.moved, &%{id: &1.id, kind: &1.kind, date: &1.date}),
        possible_duplicates: plan.carry.events.possible_duplicates
      },
      identifiers: identifiers_view(plan.identifiers),
      reverse: reverse,
      outcomes:
        Map.new(plan.outcomes, fn {collapse?, outcome} -> {collapse?, outcome_view(outcome)} end)
    }
  end

  defp security_view(security, rows, events) do
    %{
      id: security.id,
      name: security.name,
      currency_code: security.currency_code,
      isin: security.isin,
      wkn: security.wkn,
      ticker_symbol: security.ticker_symbol,
      feed: security.feed,
      asset_class: security.asset_class,
      is_benchmark: security.is_benchmark,
      is_retired: security.is_retired,
      treat_quotes_as_raw: security.treat_quotes_as_raw,
      transaction_count: length(rows),
      split_events: Enum.map(events, &event_view/1)
    }
  end

  # The counts, and the collisions whose dropped source quote is manual —
  # a close someone typed — each with both closes.
  defp quotes_view(quotes) do
    %{
      source_count: quotes.source_count,
      moved_count: length(quotes.moved),
      collision_count: length(quotes.dropped),
      manual_collisions:
        for(
          {dropped, kept} <- quotes.dropped,
          dropped.source == "manual",
          do: %{
            date: dropped.date,
            source_close: dropped.close,
            target_close: kept.close,
            target_source: kept.source
          }
        )
    }
  end

  defp assignment_view(%{assignment: assignment, twin: twin, action: action}) do
    %{
      classification_id: assignment.classification_id,
      classification_name: assignment.classification.name,
      source_category_id: assignment.category_id,
      source_category_name: assignment.category.name,
      target_category_id: twin && twin.category_id,
      target_category_name: twin && twin.category.name,
      action: action
    }
  end

  defp position_target_view(%{row: row} = entry) do
    %{
      id: row.id,
      plan_id: row.plan_id,
      plan_name: row.plan.name,
      plan_status: row.plan.status,
      portfolio_id: row.portfolio_id,
      classification_id: row.classification_id,
      category_id: row.category_id,
      category_name: row.category.name,
      target_weight: row.target_weight,
      action: entry.action,
      reason: entry.reason,
      resulting_category_id: entry.resulting_category_id
    }
  end

  defp identifiers_view(identifiers) do
    %{
      choice_required: identifiers.choice_required,
      outcomes: identifiers.outcomes,
      adopted: identifiers.adopted,
      differences: identifiers.differences,
      aliases_reassigned:
        Enum.map(
          identifiers.aliases,
          &%{id: &1.id, former_isin: &1.former_isin, changed_on: &1.changed_on}
        )
    }
  end

  defp event_view({date, ratio}), do: %{date: date, ratio: ratio_view(ratio)}
  defp ratio_view({p, q}), do: %{numerator: p, denominator: q}

  defp pair_view({source_row, target_row}) do
    %{
      source_transaction_id: source_row.id,
      target_transaction_id: target_row.id,
      portfolio_id: source_row.portfolio_id,
      securities_account_id: source_row.securities_account_id,
      date: source_row.date,
      type: source_row.type,
      quantity: source_row.quantity,
      price: source_row.price,
      gross_amount: source_row.gross_amount,
      cash_account_id: source_row.cash_account_id,
      retires_hash: source_row.import_hash != nil
    }
  end

  defp membership_view(entry) do
    %{
      securities_account_id: entry.securities_account_id,
      securities_account_name: entry.securities_account_name,
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
            portfolio_id: row.portfolio_id,
            reason: reason,
            superseded_by: by,
            retires_hash: row.import_hash != nil
          }
        end),
      positions: outcome.positions,
      rounding_differences: outcome.rounding_differences,
      cash_accounts: outcome.cash_accounts
    }
  end

  # §10: both ids and their updated_at, every booking of either security
  # (splits included) with its updated_at and economic fields, every depot
  # the plan reads with its portfolio, every figure the preview shows (the
  # bucket plan and the reverse direction among them) and the guard results.
  #
  # Beside the bookings, every row the merge carries is part of it (§9): each
  # quote, assignment, position target, event and former ISIN of either
  # security with its updated_at, and the identity each importer create
  # recorded — so a quote the sync writes, or an assignment changed, between
  # the preview and the apply is a changed plan.
  defp digest(plan, preview) do
    data = plan.data

    PlanDigest.compute(%{
      preview: preview,
      source: security_fingerprint(plan.source),
      target: security_fingerprint(plan.target),
      rows: Enum.map(data.rows, &PlanDigest.transaction_fingerprint/1),
      depots:
        data.depots
        |> Map.values()
        |> Enum.sort_by(& &1.id)
        |> Enum.map(&[&1.id, &1.updated_at, &1.portfolio_id]),
      quotes:
        owned_fingerprints(data.quote_rows, &[&1.id, &1.date, &1.close, &1.source, &1.updated_at]),
      assignments:
        owned_fingerprints(
          data.assignments,
          &[&1.id, &1.classification_id, &1.category_id, &1.updated_at]
        ),
      position_targets:
        owned_fingerprints(
          data.position_targets,
          &[&1.id, &1.plan_id, &1.plan.status, &1.category_id, &1.target_weight, &1.updated_at]
        ),
      events: owned_fingerprints(data.events, &[&1.id, &1.kind, &1.date, &1.updated_at]),
      aliases:
        owned_fingerprints(data.aliases, &[&1.id, &1.former_isin, &1.changed_on, &1.updated_at]),
      imported: data.imported
    })
  end

  defp owned_fingerprints(grouped, fingerprint) do
    grouped
    |> Enum.sort()
    |> Enum.map(fn {id, rows} -> [id, Enum.map(rows, fingerprint)] end)
  end

  defp security_fingerprint(security) do
    [
      security.id,
      security.updated_at,
      security.currency_code,
      security.is_benchmark,
      security.is_retired,
      security.treat_quotes_as_raw,
      security.name,
      security.isin,
      security.wkn,
      security.ticker_symbol,
      security.feed,
      security.asset_class
    ]
  end

  # --- the writes ---------------------------------------------------------------------

  defp execute(actor, plan, choices) do
    outcome = Map.fetch!(plan.outcomes, choices.collapse?)
    record_id = Lifecycle.reserve_merge_record_id()

    with :ok <- delete_rows(actor, outcome.deleted, record_id),
         :ok <- move_rows(actor, plan, outcome),
         :ok <- linearity_check(plan, outcome),
         {:ok, overrides} <- apply_memberships(actor, plan),
         :ok <- move_quotes(plan),
         :ok <- apply_configuration(actor, plan),
         {:ok, identifiers} <- apply_identifiers(actor, plan, choices),
         {:ok, _deleted} <- delete_source(actor, plan.source),
         :ok <- resolvability_check(plan) do
      Lifecycle.record_merge(
        actor,
        %{
          kind: :security,
          source_id: plan.source.id,
          target_id: plan.target.id,
          portfolio_id: nil,
          source_snapshot: source_snapshot(plan),
          manifest:
            manifest(plan, outcome, choices, %{overrides: overrides, identifiers: identifiers}),
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

  # Each collapsed pair's source row deleted, journaled, and its hash retired
  # under the record as `collapsed_duplicate`, superseded by the target row
  # that stays; each collapsed split deleted, journaled — a split carries no
  # hash (a database CHECK), so it retires none.
  defp delete_rows(actor, deleted, record_id) do
    each(deleted, fn
      %{row: row, reason: :collapsed_split} ->
        with :ok <- no_split_hash(row),
             {:ok, _deleted} <- MergeWriter.delete_transaction(actor, row),
             do: :ok

      %{row: row, reason: reason, superseded_by: by} ->
        with {:ok, _deleted} <- MergeWriter.delete_transaction(actor, row),
             do: MergeWriter.retire_hash(actor, row, record_id, reason, by)
    end)
  end

  defp no_split_hash(%Transaction{import_hash: nil}), do: :ok

  defp no_split_hash(row),
    do: identity_failure(row, "a split row carries a content hash")

  defp move_rows(actor, plan, outcome) do
    each(outcome.moved, fn row ->
      with :ok <- assert_writable(plan, row),
           {:ok, _row} <-
             MergeWriter.reassign_transaction(actor, row, %{security_id: plan.target.id}),
           do: :ok
    end)
  end

  # §13: the merge writer asserts what it writes; the guards make each a bug
  # catcher.
  defp assert_writable(plan, row) do
    cond do
      row.security_id != plan.source.id ->
        identity_failure(row, "not a booking of the source")

      plan.source.currency_code != plan.target.currency_code ->
        identity_failure(row, "another currency")

      true ->
        :ok
    end
  end

  defp identity_failure(row, reason),
    do: {:error, {:identity_check_failed, %{transaction_id: row.id, reason: reason}}}

  # §9, §16 invariant 10, read back from the database after the writes: per
  # depot and at every date either security has a row and today, the
  # target's quantity is the planned fold of the combined rows, and its exact
  # quantity the sum of both securities' exact folds, each under its own
  # pre-merge splits.
  defp linearity_check(plan, outcome) do
    s = plan.source.id
    t = plan.target.id
    rows = Repo.all(from(tx in Transaction, where: tx.security_id == ^t))
    dates = plan.check_dates
    depots = Enum.uniq(plan.source_depots ++ plan.target_depots) |> Enum.sort()
    actual = sample(MergeFigures.eod_positions(rows), dates)
    actual_exact = sample(MergeFigures.eod_exact(rows), dates)
    expected = sample(outcome.folds.combined, dates)
    target_exact = sample(outcome.folds.target_exact, dates)
    source_exact = sample(outcome.folds.source_exact, dates)

    Enum.find_value(dates, :ok, fn date ->
      Enum.find_value(depots, fn depot_id ->
        key = {depot_id, t}
        merged = quantity(actual, date, key)
        planned = quantity(expected, date, key)

        apart =
          MergeFigures.add(
            exact(target_exact, date, key),
            exact(source_exact, date, {depot_id, s})
          )

        cond do
          not Decimal.equal?(merged, planned) ->
            quantity_failure(date, depot_id, t, planned, merged)

          exact(actual_exact, date, key) != apart ->
            quantity_failure(
              date,
              depot_id,
              t,
              MergeFigures.to_decimal(apart),
              MergeFigures.to_decimal(exact(actual_exact, date, key))
            )

          true ->
            nil
        end
      end)
    end)
  end

  defp quantity_failure(date, depot_id, security_id, expected, actual) do
    {:error,
     {:identity_check_failed,
      %{
        date: date,
        securities_account_id: depot_id,
        security_id: security_id,
        expected: expected,
        actual: actual
      }}}
  end

  # The bucket plan (§9 configuration, §7's membership rule per depot),
  # through the journaled Buckets writers: one aggregate entry per position.
  # A position another writer changed under the merge (the depots' locks
  # make it a bug catcher) is a changed plan.
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
    depot = Map.fetch!(plan.data.depots, entry.securities_account_id)

    case PositionMembership.write(
           actor,
           entry.action,
           {{depot, plan.source}, entry.source_override},
           {{depot, plan.target}, entry.target_override}
         ) do
      {:ok, list, facts} ->
        {:ok, list, Map.put(facts, :securities_account_id, entry.securities_account_id)}

      other ->
        other
    end
  end

  # §9 quotes, gap-filled, through the quote module's merge writer: no
  # journal entry (ADR-0017's exemption names the writer), the manifest lists
  # each row, both securities' quote invalidation runs.
  defp move_quotes(%{carry: %{quotes: quotes}} = plan) do
    Quotes.merge_gap_fill(
      plan.source.id,
      plan.target.id,
      quotes.moved,
      Enum.map(quotes.dropped, &elem(&1, 0))
    )
  end

  # §9 configuration, through each context's journaled writer, one entry per
  # row: category assignments, then position targets, then events.
  defp apply_configuration(actor, %{carry: carry} = plan) do
    target_id = plan.target.id

    with :ok <- each(carry.assignments, &assignment_write(actor, &1, plan)),
         :ok <- each(carry.position_targets, &position_target_write(actor, &1, target_id)) do
      each(carry.events.moved, fn event ->
        actor |> Events.reassign_event(event, target_id) |> written("security_event", event.id)
      end)
    end
  end

  defp assignment_write(actor, %{action: :move, assignment: assignment}, plan) do
    actor
    |> Classifications.reassign_assignment(assignment, plan.target.id)
    |> written("security_category_assignment", assignment.id)
  end

  defp assignment_write(actor, %{action: :drop, assignment: assignment}, plan) do
    case Classifications.unassign_security(actor, plan.source.id, assignment.classification_id) do
      {:ok, 1} ->
        :ok

      {:ok, 0} ->
        {:error, :raced}

      {:error, _reason} = refused ->
        written(refused, "security_category_assignment", assignment.id)
    end
  end

  defp position_target_write(actor, %{action: :move, row: row}, target_id) do
    actor
    |> Targets.reassign_position_target(row, target_id)
    |> written("target", row.id)
  end

  defp position_target_write(actor, %{action: :drop, row: row}, _target_id) do
    case Targets.delete_target_rows(actor, [row]) do
      {:ok, 1} -> :ok
      {:ok, 0} -> {:error, :raced}
      {:error, _reason} = refused -> written(refused, "target", row.id)
    end
  end

  # A context writer's answer as the merge reads it: a row another writer
  # changed under the merge (its locks make it a bug catcher) is a changed
  # plan; a changeset the database refused is named.
  defp written({:ok, _row}, _resource, _id), do: :ok

  defp written({:error, %Ecto.Changeset{} = changeset}, resource, id),
    do: {:error, {:write_refused, resource, id, changeset}}

  defp written({:error, _gone}, _resource, _id), do: {:error, :raced}

  # §9 identifiers, under the ISIN write lock the apply took first: the
  # source's former ISINs reassigned to the target; the source's ISIN
  # cleared; the identity choice written; the fields the target lacks
  # adopted, one journaled update.
  defp apply_identifiers(actor, plan, choices) do
    target = plan.target
    changed_on = choices.changed_on || Clock.today()

    with :ok <-
           each(plan.identifiers.aliases, fn alias_row ->
             actor
             |> IdentifierAliases.update_alias(alias_row, %{security_id: target.id})
             |> written("security_identifier_alias", alias_row.id)
           end),
         :ok <- clear_source_isin(actor, plan.source),
         {:ok, created} <- isin_write(actor, plan, choices.choice, changed_on),
         :ok <- adopt(actor, target, plan.identifiers.adopted) do
      {:ok, %{created_alias: created, changed_on: created && changed_on}}
    end
  end

  defp clear_source_isin(_actor, %Security{isin: nil}), do: :ok

  defp clear_source_isin(actor, source) do
    actor |> Catalog.update_security(source, %{isin: nil}) |> written("security", source.id)
  end

  defp isin_write(actor, plan, :keep_target_isin, changed_on) do
    case IdentifierAliases.record_merged_isin(actor, plan.target, plan.source.isin,
           changed_on: changed_on,
           note: merged_note(plan)
         ) do
      {:ok, alias_row} -> {:ok, alias_row.former_isin}
      refused -> written(refused, "security_identifier_alias", plan.target.id)
    end
  end

  defp isin_write(actor, plan, :adopt_source_isin, changed_on) do
    case IdentifierAliases.record_isin_change(actor, plan.target, plan.source.isin,
           changed_on: changed_on,
           note: merged_note(plan)
         ) do
      {:ok, %{alias: alias_row}} -> {:ok, alias_row.former_isin}
      refused -> written(refused, "security", plan.target.id)
    end
  end

  defp isin_write(_actor, _plan, :no_choice, _changed_on), do: {:ok, nil}

  defp merged_note(plan),
    do: "security merge: security ##{plan.source.id} merged into this security (ADR-0050 §9)"

  defp adopt(_actor, _target, []), do: :ok

  defp adopt(actor, target, adopted) do
    actor
    |> Catalog.update_security(target, Map.new(adopted, &{&1.field, &1.value}))
    |> written("security", target.id)
  end

  # §9: the resolvability precondition again, over the catalog as the merge
  # left it — the database, read inside the merge's transaction. Every
  # identity the plan checked must find the target, or the merge rolls back
  # naming the ones that do not.
  defp resolvability_check(plan) do
    index = SecurityResolver.ladder_index()

    (identity_refs(plan.source, plan.data) ++ identity_refs(plan.target, plan.data))
    |> Enum.map(&{&1, SecurityResolver.resolve(&1.ref, index)})
    |> Enum.reject(fn {_entry, outcome} -> resolves_to?(outcome, plan.target.id) end)
    |> case do
      [] ->
        :ok

      failed ->
        {:error,
         {:identity_unresolvable,
          Enum.map(failed, fn {entry, outcome} ->
            Map.put(entry, :outcome, resolution_view(outcome))
          end)}}
    end
  end

  # Through the hardened delete (§11): the source's remaining memberships
  # first, each journaled, then the row. Inside the merge a refusal is a
  # reference the locks and the guards should have kept out: a changed
  # plan, or the database's own answer, named.
  defp delete_source(actor, source) do
    case Delete.remove(actor, source) do
      {:ok, deleted} ->
        {:ok, deleted}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, {:write_refused, "security", source.id, changeset}}

      {:error, _raced_or_gone} ->
        {:error, :raced}
    end
  end

  # --- the record (§12) -----------------------------------------------------------------

  defp source_snapshot(plan) do
    source = plan.source

    jsonable(%{
      id: source.id,
      name: source.name,
      currency_code: source.currency_code,
      isin: source.isin,
      wkn: source.wkn,
      ticker_symbol: source.ticker_symbol,
      asset_class: source.asset_class,
      feed: source.feed,
      feed_url: source.feed_url,
      latest_feed: source.latest_feed,
      latest_feed_url: source.latest_feed_url,
      exchange_code: source.exchange_code,
      provider: source.provider,
      online_id: source.online_id,
      note: source.note,
      attributes: source.attributes,
      is_benchmark: source.is_benchmark,
      is_retired: source.is_retired,
      treat_quotes_as_raw: source.treat_quotes_as_raw,
      former_isins: Enum.map(plan.identifiers.aliases, & &1.former_isin),
      as_imported: Map.get(plan.data.imported, source.id),
      split_events: Enum.map(plan.events.source, &event_view/1),
      position_overrides:
        for(
          %{source_override: override, securities_account_id: id} <- plan.memberships,
          override != :inherit,
          do: %{securities_account_id: id, bucket_ids: PositionMembership.override_ids(override)}
        ),
      transaction_count: length(plan.s_all),
      inserted_at: source.inserted_at,
      updated_at: source.updated_at
    })
  end

  # Per table, every row moved or deleted, every override carried, dropped or
  # cleared, every quote moved or dropped — the dropped ones with their values
  # and the target's close that won, the quotes' only record (§13) — every
  # assignment, position target, event and former ISIN moved, dropped or
  # created, the identifiers the target adopted and the differences that
  # followed it, the split events before and after, the rounding differences
  # and the operator's choices.
  defp manifest(plan, outcome, choices, written) do
    s = plan.source.id
    t = plan.target.id
    carry = plan.carry

    jsonable(%{
      choices: %{
        collapse_key_equal: choices.collapse,
        identity_choice: choices.given,
        isin_changed_on: choices.changed_on
      },
      quotes: %{
        moved:
          Enum.map(carry.quotes.moved, &%{date: &1.date, close: &1.close, source: &1.source}),
        dropped:
          Enum.map(carry.quotes.dropped, fn {dropped, kept} ->
            %{
              date: dropped.date,
              close: dropped.close,
              source: dropped.source,
              target_close: kept.close,
              target_source: kept.source
            }
          end)
      },
      category_assignments: %{
        moved:
          for(
            %{action: :move, assignment: a} <- carry.assignments,
            do: %{id: a.id, classification_id: a.classification_id, category_id: a.category_id}
          ),
        dropped:
          for(
            %{action: :drop, assignment: a, twin: twin} <- carry.assignments,
            do: %{
              id: a.id,
              classification_id: a.classification_id,
              category_id: a.category_id,
              target_category_id: twin.category_id
            }
          )
      },
      position_targets: %{
        moved:
          for(
            %{action: :move, row: row} <- carry.position_targets,
            do: %{id: row.id, plan_id: row.plan_id, category_id: row.category_id}
          ),
        deleted:
          for(
            %{action: :drop, row: row, reason: reason} <- carry.position_targets,
            do: %{
              id: row.id,
              plan_id: row.plan_id,
              plan_status: row.plan.status,
              classification_id: row.classification_id,
              category_id: row.category_id,
              target_weight: row.target_weight,
              reason: reason
            }
          )
      },
      security_events: %{
        moved: Enum.map(carry.events.moved, &%{id: &1.id, kind: &1.kind, date: &1.date}),
        possible_duplicates: carry.events.possible_duplicates
      },
      identifier_aliases: %{
        reassigned:
          Enum.map(plan.identifiers.aliases, &%{id: &1.id, former_isin: &1.former_isin}),
        created:
          written.identifiers.created_alias &&
            %{
              former_isin: written.identifiers.created_alias,
              changed_on: written.identifiers.changed_on
            }
      },
      identifiers: %{
        source_isin: plan.source.isin,
        target_isin: plan.target.isin,
        adopted: plan.identifiers.adopted,
        differences: plan.identifiers.differences
      },
      transactions: %{
        moved: Enum.map(outcome.moved, &%{id: &1.id, type: &1.type, security_id: [s, t]}),
        deleted:
          Enum.map(outcome.deleted, fn %{row: row, reason: reason, superseded_by: by} ->
            %{
              id: row.id,
              date: row.date,
              type: row.type,
              portfolio_id: row.portfolio_id,
              reason: reason,
              superseded_by: by,
              import_hash: row.import_hash
            }
          end)
      },
      position_bucket_overrides: written.overrides,
      split_events: %{
        source: Enum.map(plan.events.source, &event_view/1),
        target: Enum.map(plan.events.target, &event_view/1)
      },
      rounding_differences: outcome.rounding_differences,
      linearity: %{
        dates_checked: length(plan.check_dates),
        depots_checked: length(Enum.uniq(plan.source_depots ++ plan.target_depots))
      }
    })
  end
end
