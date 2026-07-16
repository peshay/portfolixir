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
    case plan_ref(opts) do
      nil ->
        Target
        |> join(:inner, [t], p in TargetPlan, on: p.id == t.plan_id)
        |> where([t, p], t.portfolio_id == ^portfolio_id and p.status == "active")
        |> filter_plan_view(view_id(Keyword.get(opts, :view)))
        |> filter_classification(Keyword.get(opts, :classification_id))
        |> order_by([t], asc: t.classification_id, asc: t.category_id)
        |> select([t], t)
        |> Repo.all()

      plan_id ->
        Target
        |> where([t], t.plan_id == ^plan_id and t.portfolio_id == ^portfolio_id)
        |> filter_classification(Keyword.get(opts, :classification_id))
        |> order_by([t], asc: t.classification_id, asc: t.category_id)
        |> Repo.all()
    end
  end

  @doc """
  Fetches a single target for `category_id` within the addressed plan
  (default `view: nil` = the active Gesamt plan; `plan:` addresses a specific
  version), or `nil`.
  """
  def get_target(portfolio_id, category_id, opts \\ [])
      when is_integer(portfolio_id) and is_integer(category_id) do
    case plan_ref(opts) do
      nil ->
        Target
        |> join(:inner, [t], p in TargetPlan, on: p.id == t.plan_id)
        |> where(
          [t, p],
          t.portfolio_id == ^portfolio_id and t.category_id == ^category_id and
            p.status == "active"
        )
        |> filter_plan_view(view_id(Keyword.get(opts, :view)))
        |> select([t], t)
        |> Repo.one()

      plan_id ->
        Repo.get_by(Target,
          plan_id: plan_id,
          portfolio_id: portfolio_id,
          category_id: category_id
        )
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

  Returns `{:ok, [%Target{}]}`, `{:error, :not_found}` (unknown classification),
  `{:error, :category_mismatch}` (a category from another tree),
  `{:error, :plan_mismatch}` (a `plan:` that does not belong to the addressed
  portfolio/classification), or `{:error, %Ecto.Changeset{}}`.
  """
  def set_targets(%Actor{} = actor, portfolio_id, classification_id, entries, opts \\ [])
      when is_integer(portfolio_id) and is_integer(classification_id) and is_list(entries) do
    with {:ok, _classification} <- fetch_classification(classification_id),
         :ok <- ensure_entries_are_maps(entries),
         :ok <- ensure_categories(classification_id, entries),
         {:ok, plan} <- resolve_write_plan(actor, portfolio_id, classification_id, opts) do
      Repo.transaction(fn ->
        Enum.map(entries, fn entry ->
          case upsert_target(actor, plan, portfolio_id, classification_id, entry) do
            {:ok, target} -> target
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)
      end)
    end
  end

  @doc """
  Removes a target for one category within the addressed plan (default
  `view: nil` = the active Gesamt plan; `plan:` addresses a version), on behalf
  of `actor`. Returns `{:ok, count}`. Leaves the plan row itself in place.
  """
  def delete_target(%Actor{} = actor, portfolio_id, category_id, opts \\ [])
      when is_integer(portfolio_id) and is_integer(category_id) do
    base =
      Target
      |> join(:inner, [t], p in TargetPlan, on: p.id == t.plan_id)
      |> where([t, p], t.portfolio_id == ^portfolio_id and t.category_id == ^category_id)

    targets =
      case plan_ref(opts) do
        nil ->
          base
          |> where([_t, p], p.status == "active")
          |> filter_plan_view(view_id(Keyword.get(opts, :view)))
          |> select([t], t)
          |> Repo.all()

        plan_id ->
          base |> where([t], t.plan_id == ^plan_id) |> select([t], t) |> Repo.all()
      end

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
        name: attr(attrs, :name, source.name <> " (copy)"),
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
    with {:ok, plan} <- fetch_plan(plan_or_id) do
      journaled_update(actor, plan, %{name: name}, "target_plan")
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

        with {:ok, plan} <-
               ensure_plan_journaled(actor, portfolio_id, classification_id, view_id) do
          write_cash_target(actor, plan, weight)
        end

      {_weight, nil, _plan_ref} ->
        {:error, :not_found}

      {_weight, %TargetPlan{} = plan, _} ->
        write_cash_target(actor, plan, weight)
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

  # Upsert one category target into the plan, journaled as an :upsert with the
  # pre-image (nil for a first write) — `returning: true` so the after-image
  # carries the replaced row's identity on conflict.
  defp upsert_target(actor, %TargetPlan{id: plan_id}, portfolio_id, classification_id, entry) do
    attrs = %{
      "plan_id" => plan_id,
      "portfolio_id" => portfolio_id,
      "classification_id" => classification_id,
      "category_id" => entry["category_id"] || entry[:category_id],
      "target_weight" => entry["target_weight"] || entry[:target_weight]
    }

    before =
      case normalize_id(attrs["category_id"]) do
        nil -> nil
        category_id -> Repo.get_by(Target, plan_id: plan_id, category_id: category_id)
      end

    Multi.new()
    |> Multi.insert(:record, Target.changeset(%Target{}, attrs),
      on_conflict: {:replace, [:classification_id, :target_weight, :updated_at]},
      conflict_target: [:plan_id, :category_id],
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

  defp normalize_id(value) when is_integer(value), do: value

  defp normalize_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp normalize_id(_value), do: nil
end
