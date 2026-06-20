defmodule Portfolixir.Portfolios.Targets do
  @moduledoc """
  Stored target weights (SOLL) per portfolio, view and classification category
  (ADR-0020).

  This is the persistence side of the SOLL/IST workflow: a portfolio's desired
  allocation lives in Portfolixir instead of an external document, so
  `Portfolixir.Portfolios.Allocation` can compute drift from a single call.

  Since ADR-0020 a SOLL plan **belongs to a view**. Targets are keyed by their
  `(portfolio, view, classification)` **plan** (`Portfolixir.Portfolios.TargetPlan`);
  the plan also owns the cash target. The `view` option (a `%View{}`, a view id,
  or `nil`) selects the plan; **`view: nil` is the Gesamt/Total plan** — today's
  portfolio-wide behaviour and the default for every function here. A read loads
  **only** the addressed plan, so Gesamt and a named view are independent.

  Setting targets upserts the supplied categories into the addressed plan
  (creating that plan on first write) and leaves the rest untouched; remove a
  category's target with `delete_target/3`.

  These writes are not yet journaled: the owning Portfolios/Targets context is a
  later slice of the leaf-first audit-journal rollout (ADR-0017), so the plan
  tables are deliberately not guard-armed — consistent with the existing
  `portfolio_targets` write path this extends.
  """

  import Ecto.Query

  alias Portfolixir.Buckets.View
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.Target
  alias Portfolixir.Portfolios.TargetPlan
  alias Portfolixir.Repo

  @doc """
  Lists a portfolio's targets for one plan. Pass `classification_id:` to scope to
  one tree and `view:` to select the plan (default `nil` = the Gesamt plan).

  Loads **only** the addressed plan's targets.
  """
  def list_targets(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    view_id = view_id(Keyword.get(opts, :view))

    Target
    |> join(:inner, [t], p in TargetPlan, on: p.id == t.plan_id)
    |> where([t, p], t.portfolio_id == ^portfolio_id)
    |> filter_plan_view(view_id)
    |> filter_classification(Keyword.get(opts, :classification_id))
    |> order_by([t], asc: t.classification_id, asc: t.category_id)
    |> select([t], t)
    |> Repo.all()
  end

  @doc """
  Fetches a single target for `category_id` within the addressed plan
  (default `view: nil` = Gesamt), or `nil`.
  """
  def get_target(portfolio_id, category_id, opts \\ [])
      when is_integer(portfolio_id) and is_integer(category_id) do
    view_id = view_id(Keyword.get(opts, :view))

    Target
    |> join(:inner, [t], p in TargetPlan, on: p.id == t.plan_id)
    |> where([t, p], t.portfolio_id == ^portfolio_id and t.category_id == ^category_id)
    |> filter_plan_view(view_id)
    |> select([t], t)
    |> Repo.one()
  end

  @doc """
  Upserts the given `%{category_id, target_weight}` entries for one portfolio,
  classification and plan. Pass `view:` to select the plan (default `nil` =
  Gesamt). Creates the plan on first write. Every category must belong to the
  classification. Runs in a transaction so an invalid entry rolls back the whole
  batch (including a just-created empty plan).

  Returns `{:ok, [%Target{}]}`, `{:error, :not_found}` (unknown classification),
  `{:error, :category_mismatch}` (a category from another tree), or
  `{:error, %Ecto.Changeset{}}` (e.g. a weight outside `[0, 1]`).
  """
  def set_targets(portfolio_id, classification_id, entries, opts \\ [])
      when is_integer(portfolio_id) and is_integer(classification_id) and is_list(entries) do
    view_id = view_id(Keyword.get(opts, :view))

    with {:ok, _classification} <- fetch_classification(classification_id),
         :ok <- ensure_entries_are_maps(entries),
         :ok <- ensure_categories(classification_id, entries) do
      Repo.transaction(fn ->
        plan = ensure_plan!(portfolio_id, classification_id, view_id)

        Enum.map(entries, fn entry ->
          case upsert_target(plan, portfolio_id, classification_id, entry) do
            {:ok, target} -> target
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)
      end)
    end
  end

  @doc """
  Removes a target for one category within the addressed plan
  (default `view: nil` = Gesamt). Returns `{:ok, count}`. Leaves the plan row
  itself in place.
  """
  def delete_target(portfolio_id, category_id, opts \\ [])
      when is_integer(portfolio_id) and is_integer(category_id) do
    view_id = view_id(Keyword.get(opts, :view))

    plan_ids =
      from(p in TargetPlan,
        where: p.portfolio_id == ^portfolio_id,
        select: p.id
      )
      |> filter_plan_view_root(view_id)
      |> Repo.all()

    {count, _} =
      Target
      |> where([t], t.category_id == ^category_id and t.plan_id in ^plan_ids)
      |> Repo.delete_all()

    {:ok, count}
  end

  @doc """
  Finds or creates the plan for `(portfolio, view, classification)` (default
  `view: nil` = Gesamt). Use this to materialise an **empty** plan (a plan row
  that carries no category targets), which is deliberately distinct from "no plan
  at all". Returns `{:ok, %TargetPlan{}}`.
  """
  def ensure_plan(portfolio_id, classification_id, opts \\ [])
      when is_integer(portfolio_id) and is_integer(classification_id) do
    view_id = view_id(Keyword.get(opts, :view))
    {:ok, ensure_plan!(portfolio_id, classification_id, view_id)}
  end

  @doc """
  Whether a plan row exists for `(portfolio, view, classification)` (default
  `view: nil` = Gesamt). `true` for an empty plan; `false` when no plan exists.
  """
  def plan_exists?(portfolio_id, classification_id, opts \\ [])
      when is_integer(portfolio_id) and is_integer(classification_id) do
    view_id = view_id(Keyword.get(opts, :view))
    not is_nil(get_plan(portfolio_id, classification_id, view_id))
  end

  @doc """
  The cash target weight for a plan, or `nil` when none is steered.

  With no `classification_id:` it reads the portfolio-wide cash plan
  (`classification_id NULL`) — the home of the legacy global cash target — for
  the addressed view (default `view: nil` = Gesamt). Pass `classification_id:` to
  read a per-classification plan's cash target instead.
  """
  def get_cash_target(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    view_id = view_id(Keyword.get(opts, :view))
    classification_id = Keyword.get(opts, :classification_id)

    case get_plan(portfolio_id, classification_id, view_id) do
      %TargetPlan{cash_target_weight: weight} -> weight
      nil -> nil
    end
  end

  @doc """
  Sets (or clears with `nil`) the cash target weight for a plan. With no
  `classification_id:` it steers the portfolio-wide cash plan
  (`classification_id NULL`) for the addressed view (default `view: nil` =
  Gesamt), preserving the legacy global cash-target behaviour. Pass
  `classification_id:` to steer a per-classification plan's cash target.

  Returns `:ok` or `{:error, %Ecto.Changeset{}}` (a weight out of range).
  """
  def set_cash_target(portfolio_id, weight, opts \\ []) when is_integer(portfolio_id) do
    view_id = view_id(Keyword.get(opts, :view))
    classification_id = Keyword.get(opts, :classification_id)

    case {weight, get_plan(portfolio_id, classification_id, view_id)} do
      # Clearing a cash target on a plan that does not exist is a no-op: don't
      # materialise an empty plan just to store "no cash target".
      {nil, nil} ->
        :ok

      {_weight, nil} ->
        write_cash_target(ensure_plan!(portfolio_id, classification_id, view_id), weight)

      {_weight, %TargetPlan{} = plan} ->
        write_cash_target(plan, weight)
    end
  end

  defp write_cash_target(%TargetPlan{} = plan, weight) do
    plan
    |> TargetPlan.changeset(%{cash_target_weight: weight})
    |> Repo.update()
    |> case do
      {:ok, _plan} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  # -- plan resolution -------------------------------------------------------

  # Find-or-create the (portfolio, view, classification) plan. classification_id
  # may be nil (the portfolio-wide cash plan). Relies on the NULLS NOT DISTINCT
  # unique index so concurrent writers converge on one row.
  defp ensure_plan!(portfolio_id, classification_id, view_id) do
    case get_plan(portfolio_id, classification_id, view_id) do
      %TargetPlan{} = plan ->
        plan

      nil ->
        # `on_conflict: :nothing` against the NULLS NOT DISTINCT unique index makes
        # a racing second insert a no-op; we then re-read the winner. PostgreSQL
        # infers the index from the column list (the index's NULLS NOT DISTINCT
        # qualifier is part of its definition, not the ON CONFLICT clause).
        %TargetPlan{}
        |> TargetPlan.changeset(%{
          portfolio_id: portfolio_id,
          view_id: view_id,
          classification_id: classification_id
        })
        |> Repo.insert!(
          on_conflict: :nothing,
          conflict_target: [:portfolio_id, :view_id, :classification_id]
        )
        |> case do
          %TargetPlan{id: nil} -> get_plan(portfolio_id, classification_id, view_id)
          plan -> plan
        end
    end
  end

  defp get_plan(portfolio_id, classification_id, view_id) do
    from(p in TargetPlan, where: p.portfolio_id == ^portfolio_id)
    |> filter_plan_view_root(view_id)
    |> filter_plan_classification_root(classification_id)
    |> Repo.one()
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

  # A `view` option may be a %View{}, an integer view id, or nil (Gesamt).
  defp view_id(nil), do: nil
  defp view_id(%View{id: id}), do: id
  defp view_id(id) when is_integer(id), do: id

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

  defp upsert_target(%TargetPlan{id: plan_id}, portfolio_id, classification_id, entry) do
    attrs = %{
      "plan_id" => plan_id,
      "portfolio_id" => portfolio_id,
      "classification_id" => classification_id,
      "category_id" => entry["category_id"] || entry[:category_id],
      "target_weight" => entry["target_weight"] || entry[:target_weight]
    }

    %Target{}
    |> Target.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:classification_id, :target_weight, :updated_at]},
      conflict_target: [:plan_id, :category_id]
    )
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
