defmodule Portfolixir.Portfolios.Targets do
  @moduledoc """
  Stored target weights (SOLL) per portfolio and classification category.

  This is the persistence side of the SOLL/IST workflow: a portfolio's desired
  allocation lives in Portfolixir instead of an external document, so
  `Portfolixir.Portfolios.Allocation` can compute drift from a single call.

  Setting targets upserts the supplied categories and leaves the rest untouched;
  remove a category's target with `delete_target/2`.
  """

  import Ecto.Query

  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.Target
  alias Portfolixir.Repo

  @doc """
  Lists a portfolio's targets. Pass `classification_id:` to scope to one tree.
  """
  def list_targets(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    Target
    |> where([t], t.portfolio_id == ^portfolio_id)
    |> filter_classification(Keyword.get(opts, :classification_id))
    |> order_by([t], asc: t.classification_id, asc: t.category_id)
    |> Repo.all()
  end

  def get_target(portfolio_id, category_id)
      when is_integer(portfolio_id) and is_integer(category_id) do
    Repo.get_by(Target, portfolio_id: portfolio_id, category_id: category_id)
  end

  @doc """
  Upserts the given `%{category_id, target_weight}` entries for one portfolio and
  classification. Every category must belong to the classification. Runs in a
  transaction so an invalid entry rolls back the whole batch.

  Returns `{:ok, [%Target{}]}`, `{:error, :not_found}` (unknown classification),
  `{:error, :category_mismatch}` (a category from another tree), or
  `{:error, %Ecto.Changeset{}}` (e.g. a weight outside `[0, 1]`).
  """
  def set_targets(portfolio_id, classification_id, entries)
      when is_integer(portfolio_id) and is_integer(classification_id) and is_list(entries) do
    with {:ok, _classification} <- fetch_classification(classification_id),
         :ok <- ensure_categories(classification_id, entries) do
      Repo.transaction(fn ->
        Enum.map(entries, fn entry ->
          case upsert_target(portfolio_id, classification_id, entry) do
            {:ok, target} -> target
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)
      end)
    end
  end

  @doc "Removes a portfolio's target for one category. Returns `{:ok, count}`."
  def delete_target(portfolio_id, category_id)
      when is_integer(portfolio_id) and is_integer(category_id) do
    {count, _} =
      Target
      |> where([t], t.portfolio_id == ^portfolio_id and t.category_id == ^category_id)
      |> Repo.delete_all()

    {:ok, count}
  end

  defp filter_classification(query, nil), do: query

  defp filter_classification(query, classification_id),
    do: where(query, [t], t.classification_id == ^classification_id)

  defp fetch_classification(classification_id) do
    case Classifications.get_classification(classification_id) do
      nil -> {:error, :not_found}
      classification -> {:ok, classification}
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

  defp upsert_target(portfolio_id, classification_id, entry) do
    attrs = %{
      "portfolio_id" => portfolio_id,
      "classification_id" => classification_id,
      "category_id" => entry["category_id"] || entry[:category_id],
      "target_weight" => entry["target_weight"] || entry[:target_weight]
    }

    %Target{}
    |> Target.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:classification_id, :target_weight, :updated_at]},
      conflict_target: [:portfolio_id, :category_id]
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
