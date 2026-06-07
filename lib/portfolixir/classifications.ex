defmodule Portfolixir.Classifications do
  @moduledoc """
  Classification (taxonomy) trees: user-defined hierarchies plus auto-managed
  built-in trees derived from security data (see ADR-0006).

  Built-in classifications (`"asset_class"`, `"currency"`) are seeded once with a
  locked category structure; their assignments are **derived on read** from each
  security's `effective_asset_class/1` and `currency_code`, so they stay current
  without being stored or coupled into the `Catalog` write path. Custom
  classifications are fully editable and their assignments are stored.
  """

  import Ecto.Query

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.AssetClasses
  alias Portfolixir.Catalog.Currencies
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Classifications.Assignment
  alias Portfolixir.Classifications.Category
  alias Portfolixir.Classifications.Classification
  alias Portfolixir.Repo

  @builtin_keys ~w(asset_class currency)

  # Distinct, asset-appropriate default colors so built-in asset-class
  # categories are already differentiable in charts. Users may override them.
  @asset_class_colors %{
    "equity" => "#2563eb",
    "etf" => "#0891b2",
    "fund" => "#7c3aed",
    "government_bond" => "#16a34a",
    "bond" => "#65a30d",
    "crypto" => "#f59e0b",
    "commodity" => "#b45309",
    "index" => "#475569",
    "other" => "#6b7280"
  }

  # -- read -----------------------------------------------------------------

  @doc """
  Lists every classification as a tree with its categories and the (derived or
  stored) security assignments. Ensures the built-in trees exist first.

  Each entry is `%{classification:, categories:, assignments:}` where
  `assignments` is a list of `%{security_id:, category_id:}`.
  """
  def list_trees do
    ensure_builtins()
    securities = Catalog.list_securities()

    Classification
    |> order_by([c], asc: c.position, asc: c.id)
    |> preload(categories: ^ordered_categories())
    |> Repo.all()
    |> Enum.map(fn classification ->
      %{
        classification: classification,
        categories: classification.categories,
        assignments: assignments_for(classification, securities)
      }
    end)
  end

  def list_classifications do
    Classification
    |> order_by([c], asc: c.position, asc: c.id)
    |> Repo.all()
  end

  def get_classification(id) when is_integer(id), do: Repo.get(Classification, id)

  def get_classification_by_key(key) when is_binary(key) do
    Repo.get_by(Classification, key: key)
  end

  def builtin_key?(key), do: key in @builtin_keys

  # -- custom classifications -----------------------------------------------

  def create_classification(attrs) when is_map(attrs) do
    %Classification{}
    |> Classification.changeset(attrs)
    |> Repo.insert()
  end

  def update_classification(%Classification{built_in: true}, _attrs),
    do: {:error, :builtin_locked}

  def update_classification(%Classification{} = classification, attrs) do
    classification
    |> Classification.changeset(attrs)
    |> Repo.update()
  end

  def delete_classification(%Classification{built_in: true}), do: {:error, :builtin_locked}
  def delete_classification(%Classification{} = classification), do: Repo.delete(classification)

  def change_classification(%Classification{} = classification, attrs \\ %{}) do
    Classification.changeset(classification, attrs)
  end

  # -- custom categories ----------------------------------------------------

  def create_category(attrs) when is_map(attrs) do
    with {:ok, classification} <- fetch_classification(attrs),
         :ok <- ensure_custom(classification) do
      %Category{}
      |> Category.changeset(attrs)
      |> Repo.insert()
    end
  end

  def update_category(%Category{} = category, attrs) do
    with :ok <- ensure_custom_category(category) do
      category
      |> Category.changeset(attrs)
      |> Repo.update()
    end
  end

  def delete_category(%Category{} = category) do
    with :ok <- ensure_custom_category(category) do
      Repo.delete(category)
    end
  end

  def get_category(id) when is_integer(id), do: Repo.get(Category, id)

  @doc """
  Updates only a category's color. Allowed for built-in categories too, since
  recoloring does not change the locked structure (names, keys, hierarchy).
  """
  def recolor_category(%Category{} = category, color) do
    category
    |> Category.color_changeset(color)
    |> Repo.update()
  end

  # -- assignments (custom only) --------------------------------------------

  @doc """
  Assigns a security to one category of a custom classification, replacing any
  existing assignment for that `(security, classification)` pair.
  """
  def assign_security(security_id, classification_id, category_id) do
    with {:ok, classification} <- fetch_classification_by_id(classification_id),
         :ok <- ensure_custom(classification),
         :ok <- ensure_category_in_classification(category_id, classification_id) do
      %Assignment{}
      |> Assignment.changeset(%{
        security_id: security_id,
        classification_id: classification_id,
        category_id: category_id
      })
      |> Repo.insert(
        on_conflict: {:replace, [:category_id, :updated_at]},
        conflict_target: [:security_id, :classification_id]
      )
    end
  end

  def unassign_security(security_id, classification_id) do
    {count, _} =
      Assignment
      |> where([a], a.security_id == ^security_id and a.classification_id == ^classification_id)
      |> Repo.delete_all()

    {:ok, count}
  end

  @doc """
  Assigns many securities to one category of a custom classification in a single
  statement, replacing any existing assignment for each `(security, classification)`
  pair. Returns `{:ok, count}` or `{:error, reason}`.
  """
  def assign_securities(security_ids, classification_id, category_id)
      when is_list(security_ids) do
    with {:ok, classification} <- fetch_classification_by_id(classification_id),
         :ok <- ensure_custom(classification),
         :ok <- ensure_category_in_classification(category_id, classification_id) do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      entries =
        security_ids
        |> Enum.uniq()
        |> Enum.map(fn security_id ->
          %{
            security_id: security_id,
            classification_id: classification_id,
            category_id: category_id,
            inserted_at: now,
            updated_at: now
          }
        end)

      {count, _} =
        Repo.insert_all(Assignment, entries,
          on_conflict: {:replace, [:category_id, :updated_at]},
          conflict_target: [:security_id, :classification_id]
        )

      {:ok, count}
    end
  end

  @doc "Removes the given securities' assignments from a classification."
  def unassign_securities(security_ids, classification_id) when is_list(security_ids) do
    {count, _} =
      Assignment
      |> where([a], a.classification_id == ^classification_id and a.security_id in ^security_ids)
      |> Repo.delete_all()

    {:ok, count}
  end

  # -- built-in seeding ------------------------------------------------------

  @doc "Idempotently seeds the built-in classification trees. Returns :ok."
  def ensure_builtins do
    ensure_builtin("asset_class", "Asset class", builtin_asset_class_categories())
    ensure_builtin("currency", "Currency", builtin_currency_categories())
    :ok
  end

  defp builtin_asset_class_categories do
    Enum.map(AssetClasses.options(), fn {label, code} ->
      {code, label, Map.get(@asset_class_colors, code)}
    end)
  end

  defp builtin_currency_categories do
    Enum.map(Currencies.options(), fn {label, code} -> {code, label, nil} end)
  end

  defp ensure_builtin(key, name, categories) do
    classification = ensure_builtin_classification(key, name)
    ensure_builtin_categories(classification, categories)
  end

  defp ensure_builtin_classification(key, name) do
    case Repo.get_by(Classification, key: key) do
      %Classification{} = classification ->
        classification

      nil ->
        {:ok, classification} =
          %Classification{}
          |> Classification.builtin_changeset(%{
            name: name,
            key: key,
            built_in: true,
            position: 0
          })
          |> Repo.insert(on_conflict: :nothing, conflict_target: :key)

        Repo.get_by(Classification, key: key) || classification
    end
  end

  defp ensure_builtin_categories(classification, categories) do
    existing =
      Category
      |> where([c], c.classification_id == ^classification.id)
      |> Repo.all()
      |> Map.new(&{&1.key, &1})

    categories
    |> Enum.with_index()
    |> Enum.each(fn {{code, label, color}, index} ->
      case Map.get(existing, code) do
        nil ->
          %Category{}
          |> Category.builtin_changeset(%{
            classification_id: classification.id,
            key: code,
            name: label,
            color: color,
            position: index
          })
          |> Repo.insert(on_conflict: :nothing, conflict_target: [:classification_id, :key])

        %Category{color: nil} = category when not is_nil(color) ->
          # Backfill a default color, but never overwrite a user-chosen one.
          category |> Ecto.Changeset.change(color: color) |> Repo.update()

        _ ->
          :ok
      end
    end)
  end

  # -- internals ------------------------------------------------------------

  defp assignments_for(%Classification{built_in: true, key: key} = classification, securities) do
    by_code = Map.new(classification.categories, &{&1.key, &1.id})

    Enum.flat_map(securities, fn security ->
      case Map.get(by_code, builtin_code(key, security)) do
        nil -> []
        category_id -> [%{security_id: security.id, category_id: category_id}]
      end
    end)
  end

  defp assignments_for(%Classification{id: id}, _securities) do
    Assignment
    |> where([a], a.classification_id == ^id)
    |> select([a], %{security_id: a.security_id, category_id: a.category_id})
    |> Repo.all()
  end

  defp builtin_code("asset_class", %Security{} = security) do
    Security.effective_asset_class(security)
  end

  defp builtin_code("currency", %Security{currency_code: currency_code}), do: currency_code

  defp ordered_categories do
    from(c in Category, order_by: [asc: c.position, asc: c.id])
  end

  defp fetch_classification(attrs) do
    case fetch_classification_by_id(attr_integer(attrs, :classification_id)) do
      {:ok, classification} -> {:ok, classification}
      error -> error
    end
  end

  defp fetch_classification_by_id(id) when is_integer(id) do
    case Repo.get(Classification, id) do
      %Classification{} = classification -> {:ok, classification}
      nil -> {:error, :not_found}
    end
  end

  defp fetch_classification_by_id(_id), do: {:error, :not_found}

  defp ensure_custom(%Classification{built_in: true}), do: {:error, :builtin_locked}
  defp ensure_custom(%Classification{}), do: :ok

  defp ensure_custom_category(%Category{classification_id: classification_id}) do
    case fetch_classification_by_id(classification_id) do
      {:ok, classification} -> ensure_custom(classification)
      error -> error
    end
  end

  defp ensure_category_in_classification(category_id, classification_id) do
    case Repo.get(Category, category_id) do
      %Category{classification_id: ^classification_id} -> :ok
      %Category{} -> {:error, :category_mismatch}
      nil -> {:error, :category_not_found}
    end
  end

  defp attr_integer(attrs, field) do
    case Map.get(attrs, field) || Map.get(attrs, Atom.to_string(field)) do
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end
end
