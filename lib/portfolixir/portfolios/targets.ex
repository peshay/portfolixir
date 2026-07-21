defmodule Portfolixir.Portfolios.Targets do
  @moduledoc """
  Stored target weights (SOLL) per portfolio, view and classification category
  (ADR-0020), organised into named plan versions (ADR-0027).

  This is the persistence side of the SOLL/IST workflow: a portfolio's desired
  allocation lives in Portfolixir instead of an external document, so
  `Portfolixir.Portfolios.Allocation` can compute drift from a single call.

  Since ADR-0020 a SOLL plan **belongs to a view**. Targets are keyed by their
  `(portfolio, view, classification)` **plan** (`Portfolixir.Portfolios.TargetPlan`);
  the plan also owns the cash target. The `view` option (a `%View{}`, a view id,
  or `nil`) selects the plan; **`view: nil` is the Gesamt/Total plan** — today's
  portfolio-wide behaviour and the default for every function here.

  Since ADR-0027 a plan is a **named version** with a status (`active` /
  `draft` / `archived`). View-addressed reads and writes resolve the **active**
  plan of the scope; pass `plan:` (a `%TargetPlan{}` or id) to address a
  specific version instead — that is how a draft is edited while the active
  plan keeps steering the SOLL surface. `duplicate_plan/3` copies a plan into a
  draft; `activate_plan/2` swaps it in, archiving the previously active plan in
  the same transaction.

  Every write is journaled (ADR-0017, FR-28): the tables are guard-armed, all
  write functions are actor-first, and each row write commits together with its
  `audit_journal` entry.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Buckets.View
  alias Portfolixir.Classifications
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios.Target
  alias Portfolixir.Portfolios.TargetPlan
  alias Portfolixir.Repo

  # -- reads -------------------------------------------------------------------

  @doc """
  Lists a portfolio's targets for one plan. Pass `classification_id:` to scope to
  one tree and `view:` to select the **active** plan (default `nil` = the Gesamt
  plan), or `plan:` to read a specific plan version (e.g. a draft).

  Loads **only** the addressed plan's targets.
  """
  def list_targets(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    portfolio_id
    |> scoped_query(opts)
    |> where([t], is_nil(t.security_id))
    |> filter_classification(Keyword.get(opts, :classification_id))
    |> order_by([t], asc: t.classification_id, asc: t.category_id)
    |> select([t], t)
    |> Repo.all()
  end

  @doc """
  Fetches a single **category** target for `category_id` within the addressed
  plan (default `view: nil` = the active Gesamt plan; `plan:` addresses a
  specific version), or `nil`. Position rows (ADR-0030) are excluded — read them
  with `list_position_targets/2` / `get_position_target/4`.
  """
  def get_target(portfolio_id, category_id, opts \\ [])
      when is_integer(portfolio_id) and is_integer(category_id) do
    portfolio_id
    |> scoped_query(opts)
    |> where([t], t.category_id == ^category_id and is_nil(t.security_id))
    |> select([t], t)
    |> Repo.one()
  end

  @doc """
  Lists a portfolio's **position** targets (ADR-0030, #481): the rows that carry
  a `security_id`, i.e. SOLL weights on individual securities under a category.
  Same scoping options as `list_targets/2` (`classification_id:`, `view:`,
  `plan:`).

  Each row's virtual `:stale` flag is populated (#481 fix round): `true` when
  the security no longer sits under the stored category in that classification
  (reassigned elsewhere or unassigned). A stale row keeps counting where it was
  filed — re-filing it is the operator's move; the flag only surfaces it.

  Each row's `:security` association is preloaded (one batched query, no
  per-row lookup) so serializers can name the position without a second fetch.

  A caller that already holds a classification's category data (the allocation
  breakdown does) can pass `lookup: {classification_id, security_categories,
  categories}` so the stale annotation reuses it instead of re-deriving the
  category map per call (#481 slice 2a fix round, perf). Without the option the
  lookups are built here as before.
  """
  def list_position_targets(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    portfolio_id
    |> scoped_query(opts)
    |> where([t], not is_nil(t.security_id))
    |> filter_classification(Keyword.get(opts, :classification_id))
    |> order_by([t], asc: t.classification_id, asc: t.category_id, asc: t.security_id)
    |> select([t], t)
    |> Repo.all()
    |> Repo.preload(:security)
    |> annotate_stale(preloaded_lookups(opts))
  end

  @doc """
  Fetches a single **position** target for `(category_id, security_id)` within
  the addressed plan (ADR-0030), or `nil`.
  """
  def get_position_target(portfolio_id, category_id, security_id, opts \\ [])
      when is_integer(portfolio_id) and is_integer(category_id) and is_integer(security_id) do
    portfolio_id
    |> scoped_query(opts)
    |> where([t], t.category_id == ^category_id and t.security_id == ^security_id)
    |> select([t], t)
    |> Repo.one()
  end

  @doc """
  Computes a category's **effective** target (ADR-0030, #481) within the
  addressed plan, or `nil` when the category has neither an explicit category
  target nor any position targets.

  Positions are the source of truth: when position rows exist, their **sum** is
  the effective steering number; otherwise the explicit category-row weight is
  used. Both the explicit weight and the position sum are returned, and
  `:conflict` is `true` when both are present and disagree, so a mismatch is
  **surfaced, never silently dropped** (the target-consistency advisory). Fields:

    * `:category_id`
    * `:explicit` — the category-row weight, or `nil`;
    * `:position_sum` — the sum of the category's position rows, or `nil` when
      it has none;
    * `:effective` — the resolved steering weight (position sum wins);
    * `:conflict` — `true` when explicit and position sum both exist and differ;
    * `:has_stale` — `true` when any of the category's position rows is stale
      (its security no longer sits under this category — #481 fix round). The
      stale row still counts in `:position_sum`; the flag surfaces it.
  """
  def effective_target(portfolio_id, category_id, opts \\ [])
      when is_integer(portfolio_id) and is_integer(category_id) do
    explicit = get_target(portfolio_id, category_id, opts)

    positions =
      portfolio_id
      |> scoped_query(opts)
      |> where([t], t.category_id == ^category_id and not is_nil(t.security_id))
      |> Repo.all()
      |> annotate_stale()

    build_effective(category_id, explicit, positions)
  end

  @doc """
  The effective target roll-up (ADR-0030) for **every category that carries
  position targets** within the addressed plan, one `effective_target/3` map per
  category (in `list_position_targets/2` order). Categories steered only at the
  category level are not included — read those with `list_targets/2`.
  """
  def effective_targets(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    portfolio_id
    |> list_position_targets(opts)
    |> Enum.map(& &1.category_id)
    |> Enum.uniq()
    |> Enum.map(&effective_target(portfolio_id, &1, opts))
    |> Enum.reject(&is_nil/1)
  end

  defp build_effective(category_id, explicit, positions) do
    explicit_weight = explicit && explicit.target_weight

    position_sum =
      case positions do
        [] -> nil
        rows -> Enum.reduce(rows, Decimal.new(0), &Decimal.add(&2, &1.target_weight))
      end

    effective = position_sum || explicit_weight

    if is_nil(effective) do
      nil
    else
      %{
        category_id: category_id,
        explicit: explicit_weight,
        position_sum: position_sum,
        effective: effective,
        conflict:
          not is_nil(position_sum) and not is_nil(explicit_weight) and
            not Decimal.equal?(position_sum, explicit_weight),
        has_stale: Enum.any?(positions, & &1.stale)
      }
    end
  end

  # An injected `lookup: {classification_id, security_categories, categories}`
  # (from a caller that already loaded the classification's category data)
  # becomes a preloaded per-classification stale lookup; anything else means
  # "derive everything here" (#481 slice 2a fix round, perf).
  defp preloaded_lookups(opts) do
    case Keyword.get(opts, :lookup) do
      {classification_id, security_categories, categories}
      when is_integer(classification_id) and is_map(security_categories) and is_list(categories) ->
        %{classification_id => {security_categories, ancestor_sets(categories)}}

      _none ->
        %{}
    end
  end

  # Populates each position row's virtual `:stale` flag (#481 fix round): a row
  # is stale when its security's CURRENT assignment in the row's classification
  # no longer sits under the stored category. Rows keep their query order; the
  # per-classification lookups are built once per classification in the batch
  # (reusing a preloaded lookup when the caller injected one). A vanished
  # classification (unresolvable lookup) marks its rows stale rather than
  # crashing — the row is then by definition steering nothing current.
  defp annotate_stale(rows, preloaded \\ %{})

  defp annotate_stale([], _preloaded), do: []

  defp annotate_stale(rows, preloaded) do
    lookups =
      rows
      |> Enum.map(& &1.classification_id)
      |> Enum.uniq()
      |> Map.new(fn classification_id ->
        {classification_id,
         Map.get_lazy(preloaded, classification_id, fn -> stale_lookup(classification_id) end)}
      end)

    Enum.map(rows, fn row ->
      %{row | stale: stale?(row, Map.fetch!(lookups, row.classification_id))}
    end)
  end

  defp stale_lookup(classification_id) do
    case Classifications.security_category_map(classification_id) do
      {:ok, security_categories} ->
        {security_categories, ancestor_sets(Classifications.list_categories(classification_id))}

      {:error, :not_found} ->
        :missing
    end
  end

  defp stale?(_row, :missing), do: true

  defp stale?(row, {security_categories, ancestor_sets}) do
    not position_under_category?(
      row.security_id,
      row.category_id,
      security_categories,
      ancestor_sets
    )
  end

  # A target query scoped to the addressed plan: the active plan for the view
  # (default `view: nil` = Gesamt), or a specific `plan:` version. Callers add
  # the category / security filters. The first binding is always the target, so
  # category-only clauses read `[t]` in both branches.
  defp scoped_query(portfolio_id, opts) do
    case plan_ref(opts) do
      nil ->
        Target
        |> join(:inner, [t], p in TargetPlan, on: p.id == t.plan_id)
        |> where([t, p], t.portfolio_id == ^portfolio_id and p.status == "active")
        |> filter_plan_view(view_id(Keyword.get(opts, :view)))

      plan_id ->
        Target
        |> where([t], t.plan_id == ^plan_id and t.portfolio_id == ^portfolio_id)
    end
  end

  @doc """
  Lists a portfolio's plan versions (ADR-0027), active first, then drafts and
  archived plans, each group oldest-first. Filters (all optional):
  `classification_id:` scopes to one tree; `view:` scopes to one view's plans
  where `nil` means the Gesamt scope (pass the key to filter — omitting it
  returns plans across all views).
  """
  def list_plans(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    from(p in TargetPlan, where: p.portfolio_id == ^portfolio_id)
    |> filter_plan_classification_option(opts)
    |> filter_plan_view_option(opts)
    |> order_by(
      [p],
      asc: fragment("CASE ? WHEN 'active' THEN 0 WHEN 'draft' THEN 1 ELSE 2 END", p.status),
      asc: p.inserted_at,
      asc: p.id
    )
    |> Repo.all()
  end

  @doc """
  Fetches one plan version by id (or passes a loaded `%TargetPlan{}` through).
  Returns `{:ok, %TargetPlan{}}` or `{:error, :not_found}`.
  """
  def fetch_plan(%TargetPlan{} = plan), do: {:ok, plan}

  def fetch_plan(plan_id) when is_integer(plan_id) do
    case Repo.get(TargetPlan, plan_id) do
      nil -> {:error, :not_found}
      plan -> {:ok, plan}
    end
  end

  @doc """
  Whether an **active** plan row exists for `(portfolio, view, classification)`
  (default `view: nil` = Gesamt). `true` for an empty plan; `false` when the
  scope has no active plan (drafts don't count — the SOLL surface is IST-only
  until a draft is activated).
  """
  def plan_exists?(portfolio_id, classification_id, opts \\ [])
      when is_integer(portfolio_id) and is_integer(classification_id) do
    view_id = view_id(Keyword.get(opts, :view))
    not is_nil(get_active_plan(portfolio_id, classification_id, view_id))
  end

  @doc """
  The cash target weight for the addressed plan, or `nil` when none is steered.

  With no `classification_id:` it reads the portfolio-wide cash plan
  (`classification_id NULL`) — the home of the legacy global cash target — for
  the addressed view (default `view: nil` = Gesamt). Pass `classification_id:`
  to read a per-classification plan's cash target, or `plan:` to read a
  specific plan version.
  """
  def get_cash_target(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    case resolve_read_plan(portfolio_id, opts) do
      %TargetPlan{cash_target_weight: weight} -> weight
      nil -> nil
    end
  end

  # -- writes (actor-first, journaled — ADR-0017/ADR-0027) ---------------------

  @doc """
  Upserts the given `%{category_id, target_weight}` entries for one portfolio,
  classification and plan, on behalf of `actor`. Pass `view:` to address the
  **active** plan (default `nil` = Gesamt; created on first write) or `plan:`
  to edit a specific version (e.g. a draft). Every category must belong to the
  classification. Runs in a transaction so an invalid entry rolls back the
  whole batch (including a just-created empty plan); each upsert commits with
  its audit-journal entry.

  An entry may carry a `security_id` (ADR-0030, #481): the row then targets that
  individual position **under** `category_id`. The security must sit under the
  category (its assignment in this classification is `category_id` or a
  descendant of it); an unassigned or foreign security is rejected. A category
  row (no `security_id`) and its position rows are stored side by side. A
  present `security_id` must normalize to a positive integer (`nil` keeps
  meaning "category row"); garbage is rejected, never silently coerced into a
  category write. A plan carries at most **one** position row per security:
  filing a security under a second category — within the batch or against an
  existing row — is rejected, as is naming the same `(category, security)`
  twice in one batch.

  Returns `{:ok, [%Target{}]}`, `{:error, :not_found}` (unknown classification),
  `{:error, :category_mismatch}` (a category from another tree),
  `{:error, {:security_category_mismatch, security_id, category_id}}` (a
  position whose security is not under the named category — the ids identify
  the offending pair), `{:error, :invalid_security_id}` (a present but
  non-positive-integer `security_id`), `{:error, {:duplicate_position,
  security_id}}` (a second position row for one security), `{:error,
  :plan_mismatch}` (a `plan:` that does not belong to the addressed
  portfolio/classification), or `{:error, %Ecto.Changeset{}}`.
  """
  def set_targets(%Actor{} = actor, portfolio_id, classification_id, entries, opts \\ [])
      when is_integer(portfolio_id) and is_integer(classification_id) and is_list(entries) do
    with {:ok, _classification} <- fetch_classification(classification_id),
         :ok <- ensure_entries_are_maps(entries),
         :ok <- ensure_security_ids(entries),
         :ok <- ensure_categories(classification_id, entries),
         :ok <- ensure_positions(classification_id, entries) do
      batch = fn -> run_targets_batch(actor, portfolio_id, classification_id, entries, opts) end
      retry_once_on_plan_race(batch.(), batch)
    end
  end

  # Plan resolution runs INSIDE the batch transaction (review finding): a
  # rejected entry must also roll back a plan row created for this batch —
  # otherwise a failed first save leaves an empty active plan behind and flips
  # the Wealth page from IST-only into SOLL mode.
  defp run_targets_batch(actor, portfolio_id, classification_id, entries, opts) do
    Repo.transaction(fn ->
      with {:ok, plan} <- resolve_write_plan(actor, portfolio_id, classification_id, opts),
           :ok <- ensure_single_position_per_security(plan.id, entries) do
        Enum.map(entries, fn entry ->
          case upsert_target(actor, plan, portfolio_id, classification_id, entry) do
            {:ok, target} -> target
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # One position row per (plan, security) — #481 fix round. A position entry
  # whose security already carries a position row under a DIFFERENT category of
  # the same plan is rejected; the same (category, security) pair stays a
  # legitimate upsert. Runs inside the batch transaction, after the plan is
  # resolved (in-batch duplicates are rejected earlier, before any write).
  defp ensure_single_position_per_security(plan_id, entries) do
    pairs =
      for entry <- entries,
          sid = normalize_id(entry["security_id"] || entry[:security_id]),
          not is_nil(sid),
          do: {sid, normalize_id(entry["category_id"] || entry[:category_id])}

    if pairs == [] do
      :ok
    else
      security_ids = Enum.map(pairs, &elem(&1, 0))

      existing_categories =
        from(t in Target,
          where: t.plan_id == ^plan_id and t.security_id in ^security_ids,
          select: {t.security_id, t.category_id}
        )
        |> Repo.all()
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

      Enum.reduce_while(pairs, :ok, fn {security_id, category_id}, :ok ->
        stored = Map.get(existing_categories, security_id, [])

        if Enum.all?(stored, &(&1 == category_id)) do
          {:cont, :ok}
        else
          {:halt, {:error, {:duplicate_position, security_id}}}
        end
      end)
    end
  end

  # A racing first-writer beat this call to the active-unique index: one fresh
  # attempt converges on the winner's plan instead of surfacing a spurious save
  # failure (the behaviour the pre-versioning `ensure_plan!` guaranteed). The
  # retry runs in a NEW transaction — the losing one is already rolled back.
  defp retry_once_on_plan_race({:error, %Ecto.Changeset{errors: errors}} = result, retry) do
    if unique_violation?(errors), do: retry.(), else: result
  end

  defp retry_once_on_plan_race(result, _retry), do: result

  @doc """
  Removes the **category** target for one category within the addressed plan
  (default `view: nil` = the active Gesamt plan; `plan:` addresses a version), on
  behalf of `actor`. Position rows (ADR-0030) for the category are left in place;
  remove those with `delete_position_target/5`. Returns `{:ok, count}`. Leaves
  the plan row itself in place.
  """
  def delete_target(%Actor{} = actor, portfolio_id, category_id, opts \\ [])
      when is_integer(portfolio_id) and is_integer(category_id) do
    portfolio_id
    |> scoped_query(opts)
    |> where([t], t.category_id == ^category_id and is_nil(t.security_id))
    |> select([t], t)
    |> Repo.all()
    |> delete_targets(actor)
  end

  @doc """
  Removes a single **position** target for `(category_id, security_id)` within
  the addressed plan (ADR-0030), on behalf of `actor`. Returns `{:ok, count}`
  (0 when none existed). The category row and other positions are untouched.
  """
  def delete_position_target(%Actor{} = actor, portfolio_id, category_id, security_id, opts \\ [])
      when is_integer(portfolio_id) and is_integer(category_id) and is_integer(security_id) do
    portfolio_id
    |> scoped_query(opts)
    |> where([t], t.category_id == ^category_id and t.security_id == ^security_id)
    |> select([t], t)
    |> Repo.all()
    |> delete_targets(actor)
  end

  @doc """
  Removes **every** position-target row referencing `security_id` — across all
  portfolios, plans and plan statuses (active, draft, archived) — on behalf of
  `actor`, journaled per row (ADR-0017), in one transaction. Returns
  `{:ok, count}`.

  This is the explicit seam `Portfolixir.Catalog.delete_security/2` calls
  (#481 fix round) so removing a security leaves a `"target"` journal delete
  entry for each SOLL row it takes with it, instead of relying on the silent
  `ON DELETE CASCADE` of the `security_id` foreign key (which stays in place as
  a backstop only).
  """
  def delete_position_targets_for_security(%Actor{} = actor, security_id)
      when is_integer(security_id) do
    from(t in Target, where: t.security_id == ^security_id)
    |> Repo.all()
    |> delete_targets(actor)
  end

  defp delete_targets(targets, actor) do
    Repo.transaction(fn ->
      Enum.each(targets, fn target ->
        case journaled_delete(actor, target, "target") do
          {:ok, _} -> :ok
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

      length(targets)
    end)
  end

  @doc """
  Removes the addressed **active** plan for `(portfolio, view, classification)`
  (default `view: nil` = Gesamt), on behalf of `actor`: the plan row and — via
  the `plan_id` foreign key's `ON DELETE CASCADE` — every category target
  hanging off it, plus the plan's cash target. Draft/archived versions of the
  scope are untouched. After this `plan_exists?/3` is `false`, so the portfolio
  page falls back to IST-only for that `(view, classification)`. Returns
  `{:ok, count}` with the number of plan rows removed (0 when there was none).
  """
  def delete_plan(%Actor{} = actor, portfolio_id, classification_id, opts \\ [])
      when is_integer(portfolio_id) and is_integer(classification_id) do
    view_id = view_id(Keyword.get(opts, :view))

    case get_active_plan(portfolio_id, classification_id, view_id) do
      nil ->
        {:ok, 0}

      %TargetPlan{} = plan ->
        with {:ok, _} <- journaled_delete(actor, plan, "target_plan") do
          {:ok, 1}
        end
    end
  end

  @doc """
  Deletes one plan **version** by id (any status), on behalf of `actor` — the
  cleanup path for drafts and archived plans. Cascades its targets. Returns
  `{:ok, %TargetPlan{}}` or `{:error, :not_found}`.
  """
  def delete_plan_version(%Actor{} = actor, plan_or_id) do
    with {:ok, plan} <- fetch_plan(plan_or_id) do
      journaled_delete(actor, plan, "target_plan")
    end
  end

  @doc """
  Finds or creates the **active** plan for `(portfolio, view, classification)`
  (default `view: nil` = Gesamt), on behalf of `actor`. Use this to materialise
  an **empty** plan (a plan row that carries no category targets), which is
  deliberately distinct from "no plan at all". Returns `{:ok, %TargetPlan{}}`.
  """
  def ensure_plan(%Actor{} = actor, portfolio_id, classification_id, opts \\ [])
      when is_integer(portfolio_id) and is_integer(classification_id) do
    view_id = view_id(Keyword.get(opts, :view))
    ensure_plan_journaled(actor, portfolio_id, classification_id, view_id)
  end

  @doc """
  Duplicates a plan version into a **draft** (ADR-0027): copies the plan row
  (cash target included) and all its category targets, on behalf of `actor`.

  `attrs` may carry `:name` (default: `"<source name> (copy)"`) and `:view_id`
  to retarget the copy to another view scope (e.g. copy the Gesamt plan into a
  strategy view). Returns `{:ok, %TargetPlan{}}`, `{:error, :not_found}`, or
  `{:error, %Ecto.Changeset{}}`.
  """
  def duplicate_plan(%Actor{} = actor, plan_or_id, attrs \\ %{}) do
    with {:ok, source} <- fetch_plan(plan_or_id) do
      copy_attrs = %{
        portfolio_id: source.portfolio_id,
        view_id: attr(attrs, :view_id, source.view_id),
        classification_id: source.classification_id,
        cash_target_weight: source.cash_target_weight,
        # The default copy name is clamped to the 120-char limit so a
        # maximum-length source name still duplicates (review finding).
        name: attr(attrs, :name, String.slice(source.name <> " (copy)", 0, 120)),
        status: "draft"
      }

      Repo.transaction(fn ->
        copy =
          case journaled_insert(
                 actor,
                 TargetPlan.changeset(%TargetPlan{}, copy_attrs),
                 "target_plan"
               ) do
            {:ok, copy} -> copy
            {:error, changeset} -> Repo.rollback(changeset)
          end

        source.id
        |> targets_of_plan()
        |> Enum.each(fn target ->
          changeset =
            Target.changeset(%Target{}, %{
              plan_id: copy.id,
              portfolio_id: target.portfolio_id,
              classification_id: target.classification_id,
              category_id: target.category_id,
              security_id: target.security_id,
              target_weight: target.target_weight
            })

          case journaled_insert(actor, changeset, "target") do
            {:ok, _} -> :ok
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)

        copy
      end)
    end
  end

  @doc """
  Activates a plan version (ADR-0027), on behalf of `actor`: the previously
  active plan of the same `(portfolio, view, classification)` scope is archived
  in the same transaction, so the scope always carries at most one active plan.
  Activating the already-active plan is a no-op. Returns `{:ok, %TargetPlan{}}`,
  `{:error, :not_found}`, or `{:error, %Ecto.Changeset{}}`.
  """
  def activate_plan(%Actor{} = actor, plan_or_id) do
    with {:ok, plan} <- fetch_plan(plan_or_id) do
      if plan.status == "active" do
        {:ok, plan}
      else
        Repo.transaction(fn ->
          archive_current_active!(actor, plan)

          case journaled_update(actor, plan, %{status: "active"}, "target_plan") do
            {:ok, activated} -> activated
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)
      end
    end
  end

  # Archives the scope's currently active plan (if any) inside the caller's
  # activation transaction; a failed archive rolls the whole activation back.
  defp archive_current_active!(actor, plan) do
    case get_active_plan(plan.portfolio_id, plan.classification_id, plan.view_id) do
      nil ->
        :ok

      %TargetPlan{} = current ->
        case journaled_update(actor, current, %{status: "archived"}, "target_plan") do
          {:ok, _} -> :ok
          {:error, changeset} -> Repo.rollback(changeset)
        end
    end
  end

  @doc """
  Renames a plan version, on behalf of `actor`. Returns `{:ok, %TargetPlan{}}`,
  `{:error, :not_found}`, or `{:error, %Ecto.Changeset{}}`.
  """
  def rename_plan(%Actor{} = actor, plan_or_id, name) when is_binary(name) do
    # An empty name would be silently dropped by cast/3 (empty values), turning
    # the rename into a confusing no-op — reject it explicitly instead.
    case String.trim(name) do
      "" ->
        {:error, :invalid_name}

      trimmed ->
        with {:ok, plan} <- fetch_plan(plan_or_id) do
          journaled_update(actor, plan, %{name: trimmed}, "target_plan")
        end
    end
  end

  @doc """
  Sets (or clears with `nil`) the cash target weight for a plan, on behalf of
  `actor`. With no `classification_id:` it steers the portfolio-wide cash plan
  (`classification_id NULL`) for the addressed view (default `view: nil` =
  Gesamt), preserving the legacy global cash-target behaviour. Pass
  `classification_id:` to steer a per-classification plan's cash target, or
  `plan:` to steer a specific version.

  Returns `:ok`, `{:error, :not_found}` / `{:error, :plan_mismatch}` (bad
  `plan:`), or `{:error, %Ecto.Changeset{}}` (a weight out of range).
  """
  def set_cash_target(%Actor{} = actor, portfolio_id, weight, opts \\ [])
      when is_integer(portfolio_id) do
    case {weight, resolve_read_plan(portfolio_id, opts), plan_ref(opts)} do
      # Clearing a cash target on a plan that does not exist is a no-op: don't
      # materialise an empty plan just to store "no cash target".
      {nil, nil, nil} ->
        :ok

      {_weight, nil, nil} ->
        classification_id = Keyword.get(opts, :classification_id)
        view_id = view_id(Keyword.get(opts, :view))

        write = fn ->
          run_cash_target_create(actor, portfolio_id, classification_id, view_id, weight)
        end

        retry_once_on_plan_race(write.(), write)

      {_weight, nil, _plan_ref} ->
        {:error, :not_found}

      {_weight, %TargetPlan{} = plan, _} ->
        write_cash_target(actor, plan, weight)
    end
  end

  # One transaction, so a rejected weight also rolls back a plan row created
  # for this write (mirrors set_targets — review finding).
  defp run_cash_target_create(actor, portfolio_id, classification_id, view_id, weight) do
    Repo.transaction(fn ->
      with {:ok, plan} <-
             ensure_plan_journaled(actor, portfolio_id, classification_id, view_id),
           :ok <- write_cash_target(actor, plan, weight) do
        :ok
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_cash_target(actor, %TargetPlan{} = plan, weight) do
    case journaled_update(actor, plan, %{cash_target_weight: weight}, "target_plan") do
      {:ok, _plan} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  # -- journaled write helpers -------------------------------------------------

  # Each helper runs one row write together with its audit-journal entry in one
  # (possibly nested) transaction — the seam the guard triggers require.
  defp journaled_insert(actor, changeset, resource_type, insert_opts \\ []) do
    Multi.new()
    |> Multi.insert(:record, changeset, insert_opts)
    |> Journal.record(actor, resource_type: resource_type, operation: :create, source: :record)
    |> Repo.transaction()
    |> normalize_write()
  end

  defp journaled_update(actor, record, attrs, resource_type) do
    Multi.new()
    |> Multi.update(:record, TargetPlan.changeset(record, attrs))
    |> Journal.record(actor,
      resource_type: resource_type,
      operation: :update,
      source: :record,
      before: record
    )
    |> Repo.transaction()
    |> normalize_write()
  end

  defp journaled_delete(actor, record, resource_type) do
    Multi.new()
    |> Multi.delete(:record, record)
    |> Journal.record(actor,
      resource_type: resource_type,
      operation: :delete,
      source: :record,
      before: record
    )
    |> Repo.transaction()
    |> normalize_write()
  end

  defp normalize_write({:ok, %{record: record}}), do: {:ok, record}
  defp normalize_write({:error, :record, changeset, _changes}), do: {:error, changeset}

  # -- plan resolution -----------------------------------------------------------

  # The plan a write addresses: an explicit `plan:` (verified against the
  # portfolio/classification scope), or the active plan of the view scope,
  # created on first write.
  defp resolve_write_plan(actor, portfolio_id, classification_id, opts) do
    case plan_ref(opts) do
      nil ->
        view_id = view_id(Keyword.get(opts, :view))
        ensure_plan_journaled(actor, portfolio_id, classification_id, view_id)

      plan_id ->
        with {:ok, plan} <- fetch_plan(plan_id) do
          if plan.portfolio_id == portfolio_id and plan.classification_id == classification_id do
            {:ok, plan}
          else
            {:error, :plan_mismatch}
          end
        end
    end
  end

  # The plan a read addresses: an explicit `plan:` (scope-checked against the
  # portfolio), or the active plan for (view, classification).
  defp resolve_read_plan(portfolio_id, opts) do
    case plan_ref(opts) do
      nil ->
        classification_id = Keyword.get(opts, :classification_id)
        get_active_plan(portfolio_id, classification_id, view_id(Keyword.get(opts, :view)))

      plan_id ->
        case fetch_plan(plan_id) do
          {:ok, %TargetPlan{portfolio_id: ^portfolio_id} = plan} -> plan
          _ -> nil
        end
    end
  end

  defp ensure_plan_journaled(actor, portfolio_id, classification_id, view_id) do
    case get_active_plan(portfolio_id, classification_id, view_id) do
      %TargetPlan{} = plan ->
        {:ok, plan}

      nil ->
        changeset =
          TargetPlan.changeset(%TargetPlan{}, %{
            portfolio_id: portfolio_id,
            view_id: view_id,
            classification_id: classification_id,
            name: "Plan",
            status: "active"
          })

        journaled_insert(actor, changeset, "target_plan")
    end
  end

  defp unique_violation?(errors) do
    match?({_msg, opts} when is_list(opts), errors[:portfolio_id]) and
      Keyword.get(elem(errors[:portfolio_id], 1), :constraint) == :unique
  end

  defp get_active_plan(portfolio_id, classification_id, view_id) do
    from(p in TargetPlan, where: p.portfolio_id == ^portfolio_id and p.status == "active")
    |> filter_plan_view_root(view_id)
    |> filter_plan_classification_root(classification_id)
    |> Repo.one()
  end

  defp targets_of_plan(plan_id) do
    Repo.all(from(t in Target, where: t.plan_id == ^plan_id))
  end

  # -- query helpers ---------------------------------------------------------

  defp filter_classification(query, nil), do: query

  defp filter_classification(query, classification_id),
    do: where(query, [t], t.classification_id == ^classification_id)

  # Scope a target query (joined to its plan as the 2nd binding) to one plan view.
  defp filter_plan_view(query, nil), do: where(query, [_t, p], is_nil(p.view_id))
  defp filter_plan_view(query, view_id), do: where(query, [_t, p], p.view_id == ^view_id)

  # Scope a plan query (plan as the 1st binding) to one view.
  defp filter_plan_view_root(query, nil), do: where(query, [p], is_nil(p.view_id))
  defp filter_plan_view_root(query, view_id), do: where(query, [p], p.view_id == ^view_id)

  defp filter_plan_classification_root(query, nil),
    do: where(query, [p], is_nil(p.classification_id))

  defp filter_plan_classification_root(query, classification_id),
    do: where(query, [p], p.classification_id == ^classification_id)

  # list_plans option filters: the key's *presence* opts in (so both "all
  # classifications" and "the Gesamt scope, view NULL" stay expressible).
  defp filter_plan_classification_option(query, opts) do
    case Keyword.fetch(opts, :classification_id) do
      {:ok, classification_id} -> filter_plan_classification_root(query, classification_id)
      :error -> query
    end
  end

  defp filter_plan_view_option(query, opts) do
    case Keyword.fetch(opts, :view) do
      {:ok, view} -> filter_plan_view_root(query, view_id(view))
      :error -> query
    end
  end

  # A `view` option may be a %View{}, an integer view id, or nil (Gesamt).
  defp view_id(nil), do: nil
  defp view_id(%View{id: id}), do: id
  defp view_id(id) when is_integer(id), do: id

  # A `plan` option may be a %TargetPlan{} or an integer plan id.
  defp plan_ref(opts) do
    case Keyword.get(opts, :plan) do
      nil -> nil
      %TargetPlan{id: id} -> id
      id when is_integer(id) -> id
    end
  end

  # Duplicate attrs may arrive with atom or string keys (API); an explicitly
  # present key wins over the source-plan default, even when set to nil.
  defp attr(attrs, key, default) do
    cond do
      Map.has_key?(attrs, key) -> Map.get(attrs, key)
      Map.has_key?(attrs, Atom.to_string(key)) -> Map.get(attrs, Atom.to_string(key))
      true -> default
    end
  end

  defp fetch_classification(classification_id) do
    case Classifications.get_classification(classification_id) do
      nil -> {:error, :not_found}
      classification -> {:ok, classification}
    end
  end

  # Each entry must be an object; a bare scalar (e.g. `targets: [1]`) is rejected
  # here so it surfaces as a 422 instead of crashing on `entry["category_id"]`.
  defp ensure_entries_are_maps(entries) do
    if Enum.all?(entries, &is_map/1), do: :ok, else: {:error, :invalid_entry}
  end

  # #481 fix round: an entry whose `security_id` KEY is present must carry a
  # value that normalizes to a positive integer (or an explicit `nil`, which
  # keeps meaning "category row" — the JSON-null back-compat). Garbage (`"abc"`,
  # a float, `true`, zero, a negative id) is rejected here; letting
  # `normalize_id/1`'s nil-on-garbage fallback swallow it would silently turn
  # the position write into a category write that overwrites the category row.
  # The nil fallback stays correct for ABSENT keys.
  defp ensure_security_ids(entries) do
    if Enum.all?(entries, &valid_security_id_entry?/1) do
      :ok
    else
      {:error, :invalid_security_id}
    end
  end

  defp valid_security_id_entry?(entry) do
    case fetch_present(entry, :security_id) do
      :absent ->
        true

      {:present, nil} ->
        true

      {:present, value} ->
        case normalize_id(value) do
          id when is_integer(id) and id > 0 -> true
          _ -> false
        end
    end
  end

  # Fetches a key that may arrive as a string (API) or an atom (internal),
  # distinguishing "absent" from "present with any value" (including nil).
  defp fetch_present(entry, key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(entry, string_key) -> {:present, Map.get(entry, string_key)}
      Map.has_key?(entry, key) -> {:present, Map.get(entry, key)}
      true -> :absent
    end
  end

  defp ensure_categories(classification_id, entries) do
    valid =
      classification_id
      |> Classifications.list_categories()
      |> MapSet.new(& &1.id)

    if Enum.any?(entries, &foreign_category?(&1, valid)) do
      {:error, :category_mismatch}
    else
      :ok
    end
  end

  # A supplied category is foreign when it names a category id that is not part
  # of the target classification. A missing id is left for the changeset to flag.
  defp foreign_category?(entry, valid) do
    case normalize_id(entry["category_id"] || entry[:category_id]) do
      nil -> false
      id -> not MapSet.member?(valid, id)
    end
  end

  # ADR-0030 (#481): a position entry (one carrying a `security_id`) must name a
  # category the security actually sits **under** — its assignment in this
  # classification is `category_id` itself or a descendant of it. An unassigned
  # or otherwise foreign security is rejected, so a position target can never be
  # filed against a category the security is not in. Category-only entries (no
  # `security_id`) skip this check entirely, keeping the legacy behaviour intact.
  defp ensure_positions(classification_id, entries) do
    position_entries = Enum.filter(entries, &position_entry?/1)

    if position_entries == [] do
      :ok
    else
      # A racing classification delete between fetch_classification/1 and here
      # degrades to the existing not-found error instead of a MatchError
      # (#481 fix round).
      with :ok <- ensure_unique_batch_positions(position_entries),
           {:ok, security_categories} <- Classifications.security_category_map(classification_id) do
        ancestor_sets = ancestor_sets(Classifications.list_categories(classification_id))

        Enum.reduce_while(position_entries, :ok, fn entry, :ok ->
          security_id = normalize_id(entry["security_id"] || entry[:security_id])
          category_id = normalize_id(entry["category_id"] || entry[:category_id])

          if position_under_category?(
               security_id,
               category_id,
               security_categories,
               ancestor_sets
             ) do
            {:cont, :ok}
          else
            {:halt, {:error, {:security_category_mismatch, security_id, category_id}}}
          end
        end)
      end
    end
  end

  # #481 fix round: one batch may name a security at most once as a position.
  # Twice under the same category would be a silent last-wins write; under two
  # different categories it would violate one-position-row-per-security. Both
  # are rejected outright before anything is written.
  defp ensure_unique_batch_positions(position_entries) do
    position_entries
    |> Enum.map(&normalize_id(&1["security_id"] || &1[:security_id]))
    |> Enum.frequencies()
    |> Enum.find(fn {_security_id, count} -> count > 1 end)
    |> case do
      nil -> :ok
      {security_id, _count} -> {:error, {:duplicate_position, security_id}}
    end
  end

  defp position_entry?(entry) do
    not is_nil(normalize_id(entry["security_id"] || entry[:security_id]))
  end

  # The security sits under `category_id` when its assigned category (in this
  # classification) is `category_id` or one of its descendants — i.e. the target
  # category is in the assigned category's self-and-ancestors set.
  defp position_under_category?(security_id, category_id, security_categories, ancestor_sets) do
    with assigned_id when not is_nil(assigned_id) <- Map.get(security_categories, security_id),
         ancestors when not is_nil(ancestors) <- Map.get(ancestor_sets, assigned_id) do
      MapSet.member?(ancestors, category_id)
    else
      _ -> false
    end
  end

  # For each category, the set of its own id plus all its ancestors' ids (walking
  # `parent_id` up to a root), so an assigned leaf can be checked against a target
  # set at any level above it. The `seen` guard makes a corrupt parent cycle safe.
  defp ancestor_sets(categories) do
    parent_by_id = Map.new(categories, &{&1.id, &1.parent_id})

    Map.new(categories, fn %{id: id} ->
      {id, self_and_ancestors(id, parent_by_id, MapSet.new())}
    end)
  end

  defp self_and_ancestors(nil, _parent_by_id, acc), do: acc

  defp self_and_ancestors(id, parent_by_id, acc) do
    if MapSet.member?(acc, id) do
      acc
    else
      self_and_ancestors(Map.get(parent_by_id, id), parent_by_id, MapSet.put(acc, id))
    end
  end

  # Upsert one target into the plan, journaled as an :upsert with the pre-image
  # (nil for a first write) — `returning: true` so the after-image carries the
  # replaced row's identity on conflict. A category row (security_id NULL) and a
  # position row (security_id set) are backed by different partial unique indexes
  # (ADR-0030), so the ON CONFLICT target names the matching partial index.
  defp upsert_target(actor, %TargetPlan{id: plan_id}, portfolio_id, classification_id, entry) do
    security_id = normalize_id(entry["security_id"] || entry[:security_id])

    attrs = %{
      "plan_id" => plan_id,
      "portfolio_id" => portfolio_id,
      "classification_id" => classification_id,
      "category_id" => entry["category_id"] || entry[:category_id],
      "security_id" => security_id,
      "target_weight" => entry["target_weight"] || entry[:target_weight]
    }

    {conflict_target, before} =
      upsert_conflict(plan_id, normalize_id(attrs["category_id"]), security_id)

    Multi.new()
    |> Multi.insert(:record, Target.changeset(%Target{}, attrs),
      on_conflict: {:replace, [:classification_id, :target_weight, :updated_at]},
      conflict_target: conflict_target,
      returning: true
    )
    |> Journal.record(actor,
      resource_type: "target",
      operation: :upsert,
      source: :record,
      before: before
    )
    |> Repo.transaction()
    |> normalize_write()
  end

  @category_conflict {:unsafe_fragment, "(plan_id, category_id) WHERE security_id IS NULL"}
  @position_conflict {:unsafe_fragment,
                      "(plan_id, category_id, security_id) WHERE security_id IS NOT NULL"}

  # A missing category id: the changeset rejects the row, so no pre-image lookup.
  defp upsert_conflict(_plan_id, nil, _security_id), do: {@category_conflict, nil}

  # A category row: the pre-image is the existing category row (security_id NULL).
  defp upsert_conflict(plan_id, category_id, nil) do
    before =
      Repo.one(
        from(t in Target,
          where: t.plan_id == ^plan_id and t.category_id == ^category_id and is_nil(t.security_id)
        )
      )

    {@category_conflict, before}
  end

  # A position row: the pre-image is the existing (category, security) position.
  defp upsert_conflict(plan_id, category_id, security_id) do
    before =
      Repo.get_by(Target, plan_id: plan_id, category_id: category_id, security_id: security_id)

    {@position_conflict, before}
  end

  defp normalize_id(value) when is_integer(value), do: value

  defp normalize_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp normalize_id(_value), do: nil
end
