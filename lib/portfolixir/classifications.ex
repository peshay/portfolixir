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

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.AssetClasses
  alias Portfolixir.Catalog.Currencies
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Classifications.Assignment
  alias Portfolixir.Classifications.Category
  alias Portfolixir.Classifications.Classification
  alias Portfolixir.Journal
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
    "leverage_products" => "#7e22ce",
    "warrant" => "#a855f7",
    "knock_out" => "#d946ef",
    "factor_certificate" => "#ec4899",
    "investment_products" => "#0f766e",
    "discount_certificate" => "#14b8a6",
    "bonus_certificate" => "#22c55e",
    "express_certificate" => "#0ea5e9",
    "reverse_convertible" => "#fb7185",
    "other" => "#6b7280"
  }

  # Built-in asset-class tree (DDV-style): the flat classes plus a Leverage and
  # an Investment group with their certificate sub-types, as `{key, parent_key}`.
  # The group keys are NOT valid security asset_class codes — they only group
  # their children, which are the real codes a security can hold.
  @asset_class_tree [
    {"equity", nil},
    {"etf", nil},
    {"fund", nil},
    {"government_bond", nil},
    {"bond", nil},
    {"crypto", nil},
    {"commodity", nil},
    {"index", nil},
    {"leverage_products", nil},
    {"warrant", "leverage_products"},
    {"knock_out", "leverage_products"},
    {"factor_certificate", "leverage_products"},
    {"investment_products", nil},
    {"discount_certificate", "investment_products"},
    {"bonus_certificate", "investment_products"},
    {"express_certificate", "investment_products"},
    {"reverse_convertible", "investment_products"},
    {"other", nil}
  ]

  # -- read -----------------------------------------------------------------

  @doc """
  Lists every classification as a tree with its categories and the (derived or
  stored) security assignments.

  The built-in trees are seeded once at startup (`ensure_builtins/0`, #529), not
  on this read path; tests seed them explicitly within their sandbox.

  Each entry is `%{classification:, categories:, assignments:}` where
  `assignments` is a list of `%{security_id:, category_id:}`.
  """
  def list_trees do
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

  @doc """
  The default steering tree: the first **custom** classification, else the
  built-in asset-class tree. This is the rule the Wealth page's allocation
  selector uses; the dashboard's drift alerts must follow the same rule so a
  plan on the custom strategy tree is never silently missed (built-ins are
  seeded first at boot, so "the first classification" would pick asset_class).
  Returns `nil` when no classification exists.
  """
  def default_classification(classifications \\ list_classifications()) do
    Enum.find(classifications, &(not &1.built_in)) ||
      Enum.find(classifications, &(&1.key == "asset_class")) ||
      List.first(classifications)
  end

  @doc """
  Lists one classification's categories, ordered the same way as the trees.

  Works for built-in and custom classifications alike; built-in categories are
  seeded rows that exist after the startup seed (`seed_builtins_on_boot/0`, #529)
  — tests seed them explicitly via `ensure_builtins/0` within their sandbox.
  """
  def list_categories(classification_id) when is_integer(classification_id) do
    classification_id
    |> categories_query()
    |> Repo.all()
  end

  @doc """
  Returns `%{security_id => category_id}` for one classification: the derived
  assignments for a built-in tree, or the stored assignments for a custom tree.

  Built-in trees are seeded at startup (#529), so a built-in classification id
  resolves. Returns `{:error, :not_found}` when the classification does not exist.
  """
  def security_category_map(classification_id) when is_integer(classification_id) do
    case Repo.get(Classification, classification_id) do
      nil ->
        {:error, :not_found}

      %Classification{} = classification ->
        classification = Repo.preload(classification, categories: ordered_categories())

        map =
          classification
          |> assignments_for(Catalog.list_securities())
          |> Map.new(fn %{security_id: security_id, category_id: category_id} ->
            {security_id, category_id}
          end)

        {:ok, map}
    end
  end

  @doc """
  Securities-table column descriptors (#565): every classification with the
  number of levels its category tree currently has, in display order. Each
  `(classification, level)` pair can back one configurable list column; an
  empty tree still reports one level so the column stays offerable.
  """
  def column_specs do
    Classification
    |> order_by([c], asc: c.position, asc: c.id)
    |> preload(categories: ^ordered_categories())
    |> Repo.all()
    |> Enum.map(fn classification ->
      %{classification: classification, levels: max_level(classification.categories)}
    end)
  end

  @doc """
  Returns `{:ok, %{security_id => category_name}}` for one classification and
  level (1-based, root = 1): the assigned category's ancestor on that level.
  A security assigned above the requested level has no entry. Works for custom
  (stored) and built-in (derived) trees alike (#565).

  Pass `securities` to resolve against an already-loaded list; defaults to the
  full catalog. Returns `{:error, :not_found}` for an unknown classification.
  """
  def security_level_names(classification_id, level, securities \\ nil)
      when is_integer(classification_id) and is_integer(level) and level >= 1 do
    case Repo.get(Classification, classification_id) do
      nil ->
        {:error, :not_found}

      %Classification{} = classification ->
        classification = Repo.preload(classification, categories: ordered_categories())
        securities = securities || Catalog.list_securities()
        by_id = Map.new(classification.categories, &{&1.id, &1})

        names =
          classification
          |> assignments_for(securities)
          |> Enum.reduce(%{}, fn %{security_id: security_id, category_id: category_id}, acc ->
            case category_at_level(by_id, category_id, level) do
              %Category{name: name} -> Map.put(acc, security_id, name)
              nil -> acc
            end
          end)

        {:ok, names}
    end
  end

  # Root-to-category path capped at @max_tree_depth as a cycle guard; a
  # corrupted parent chain yields a truncated path instead of an endless loop.
  @max_tree_depth 32

  defp category_at_level(by_id, category_id, level) do
    by_id
    |> Map.get(category_id)
    |> path_to_root(by_id, [], @max_tree_depth)
    |> Enum.at(level - 1)
  end

  defp path_to_root(category, by_id, acc, depth_left)

  defp path_to_root(nil, _by_id, acc, _depth_left), do: acc
  defp path_to_root(_category, _by_id, acc, 0), do: acc

  defp path_to_root(%Category{parent_id: nil} = category, _by_id, acc, _depth_left),
    do: [category | acc]

  defp path_to_root(%Category{parent_id: parent_id} = category, by_id, acc, depth_left) do
    path_to_root(Map.get(by_id, parent_id), by_id, [category | acc], depth_left - 1)
  end

  defp max_level([]), do: 1

  defp max_level(categories) do
    by_id = Map.new(categories, &{&1.id, &1})

    categories
    |> Enum.map(&length(path_to_root(&1, by_id, [], @max_tree_depth)))
    |> Enum.max()
  end

  def get_classification(id) when is_integer(id), do: Repo.get(Classification, id)

  def get_classification_by_key(key) when is_binary(key) do
    Repo.get_by(Classification, key: key)
  end

  def builtin_key?(key), do: key in @builtin_keys

  # -- custom classifications -----------------------------------------------

  def create_classification(%Actor{} = actor, attrs) when is_map(attrs) do
    Multi.new()
    |> Multi.insert(:classification, Classification.changeset(%Classification{}, attrs))
    |> Journal.record(actor,
      resource_type: "classification",
      operation: :create,
      source: :classification
    )
    |> Repo.transaction()
    |> classification_result()
  end

  def update_classification(%Actor{}, %Classification{built_in: true}, _attrs),
    do: {:error, :builtin_locked}

  def update_classification(%Actor{} = actor, %Classification{} = classification, attrs) do
    Multi.new()
    |> Multi.update(:classification, Classification.changeset(classification, attrs))
    |> Journal.record(actor,
      resource_type: "classification",
      operation: :update,
      source: :classification,
      before: classification
    )
    |> Repo.transaction()
    |> classification_result()
  end

  def delete_classification(%Actor{}, %Classification{built_in: true}),
    do: {:error, :builtin_locked}

  def delete_classification(%Actor{} = actor, %Classification{} = classification) do
    Multi.new()
    |> Multi.delete(:classification, classification)
    |> Journal.record(actor,
      resource_type: "classification",
      operation: :delete,
      source: :classification,
      before: classification
    )
    |> Repo.transaction()
    |> classification_result()
  end

  defp classification_result({:ok, %{classification: classification}}), do: {:ok, classification}

  defp classification_result({:error, :classification, %Ecto.Changeset{} = changeset, _}),
    do: {:error, changeset}

  defp category_result({:ok, %{category: category}}), do: {:ok, category}

  defp category_result({:error, :category, %Ecto.Changeset{} = changeset, _}),
    do: {:error, changeset}

  # -- custom categories ----------------------------------------------------

  def create_category(%Actor{} = actor, attrs) when is_map(attrs) do
    with {:ok, classification} <- fetch_classification(attrs),
         :ok <- ensure_custom(classification) do
      Multi.new()
      |> Multi.insert(:category, Category.changeset(%Category{}, attrs))
      |> Journal.record(actor, resource_type: "category", operation: :create, source: :category)
      |> Repo.transaction()
      |> category_result()
    end
  end

  def update_category(%Actor{} = actor, %Category{} = category, attrs) do
    with :ok <- ensure_custom_category(category) do
      Multi.new()
      |> Multi.update(:category, Category.changeset(category, attrs))
      |> Journal.record(actor,
        resource_type: "category",
        operation: :update,
        source: :category,
        before: category
      )
      |> Repo.transaction()
      |> category_result()
    end
  end

  def delete_category(%Actor{} = actor, %Category{} = category) do
    with :ok <- ensure_custom_category(category) do
      Multi.new()
      |> Multi.delete(:category, category)
      |> Journal.record(actor,
        resource_type: "category",
        operation: :delete,
        source: :category,
        before: category
      )
      |> Repo.transaction()
      |> category_result()
    end
  end

  def get_category(id) when is_integer(id), do: Repo.get(Category, id)

  @doc """
  Updates only a category's color. Allowed for built-in categories too, since
  recoloring does not change the locked structure (names, keys, hierarchy).
  """
  def recolor_category(%Actor{} = actor, %Category{} = category, color) do
    Multi.new()
    |> Multi.update(:category, Category.color_changeset(category, color))
    |> Journal.record(actor,
      resource_type: "category",
      operation: :update,
      source: :category,
      before: category
    )
    |> Repo.transaction()
    |> category_result()
  end

  # -- assignments (custom only) --------------------------------------------

  @doc """
  Assigns a security to one category of a custom classification, replacing any
  existing assignment for that `(security, classification)` pair.
  """
  def assign_security(%Actor{} = actor, security_id, classification_id, category_id) do
    with {:ok, classification} <- fetch_classification_by_id(classification_id),
         :ok <- ensure_custom(classification),
         :ok <- ensure_category_in_classification(category_id, classification_id) do
      upsert_assignment(actor, security_id, classification_id, category_id)
    end
  end

  # One journaled upsert of a `(security, classification)` assignment. A new pair
  # journals a `:create`; reassigning an existing pair to another category
  # journals an `:update` with the prior assignment as `before` (FR-28, 2(a):
  # one entry per affected security, including in the bulk path).
  defp upsert_assignment(actor, security_id, classification_id, category_id) do
    existing = get_assignment(security_id, classification_id)
    operation = if existing, do: :update, else: :create

    Multi.new()
    |> Multi.insert(
      :assignment,
      Assignment.changeset(%Assignment{}, %{
        security_id: security_id,
        classification_id: classification_id,
        category_id: category_id
      }),
      on_conflict: {:replace, [:category_id, :updated_at]},
      conflict_target: [:security_id, :classification_id]
    )
    |> Journal.record(actor,
      resource_type: "security_category_assignment",
      operation: operation,
      source: :assignment,
      before: existing
    )
    |> Repo.transaction()
    |> assignment_result()
  end

  defp delete_assignment(actor, %Assignment{} = assignment) do
    Multi.new()
    |> Multi.delete(:assignment, assignment)
    |> Journal.record(actor,
      resource_type: "security_category_assignment",
      operation: :delete,
      source: :assignment,
      before: assignment
    )
    |> Repo.transaction()
    |> assignment_result()
  end

  defp assignment_result({:ok, %{assignment: assignment}}), do: {:ok, assignment}

  defp assignment_result({:error, :assignment, %Ecto.Changeset{} = changeset, _}),
    do: {:error, changeset}

  @doc """
  The set of security ids carrying at least one stored (custom-tree) category
  assignment. Used by the import ladder's config-at-risk warning and pre-apply
  inverse check (ADR-0029 §2): these are the securities whose strategy
  configuration a duplicated import row would strand.
  """
  def security_ids_with_assignments do
    from(a in Assignment, distinct: true, select: a.security_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc "Returns the stored assignment for a `(security, classification)` pair, or nil."
  def get_assignment(security_id, classification_id) do
    Repo.get_by(Assignment, security_id: security_id, classification_id: classification_id)
  end

  def unassign_security(%Actor{} = actor, security_id, classification_id) do
    case get_assignment(security_id, classification_id) do
      nil ->
        {:ok, 0}

      %Assignment{} = assignment ->
        with {:ok, _} <- delete_assignment(actor, assignment), do: {:ok, 1}
    end
  end

  @doc """
  Assigns many securities to one category of a custom classification in a single
  statement, replacing any existing assignment for each `(security, classification)`
  pair. Returns `{:ok, count}` or `{:error, reason}`.
  """
  def assign_securities(%Actor{} = actor, security_ids, classification_id, category_id)
      when is_list(security_ids) do
    with {:ok, classification} <- fetch_classification_by_id(classification_id),
         :ok <- ensure_custom(classification),
         :ok <- ensure_category_in_classification(category_id, classification_id) do
      ids = Enum.uniq(security_ids)

      # 2(a): one journal entry per affected security, all in one transaction
      # (all-or-nothing), instead of a single un-attributable bulk insert_all.
      Repo.transaction(fn ->
        Enum.each(ids, fn security_id ->
          case upsert_assignment(actor, security_id, classification_id, category_id) do
            {:ok, _} -> :ok
            {:error, reason} -> Repo.rollback(reason)
          end
        end)

        length(ids)
      end)
    end
  end

  @doc "Removes the given securities' assignments from a classification."
  def unassign_securities(%Actor{} = actor, security_ids, classification_id)
      when is_list(security_ids) do
    Repo.transaction(fn ->
      assignments =
        Assignment
        |> where(
          [a],
          a.classification_id == ^classification_id and a.security_id in ^security_ids
        )
        |> Repo.all()

      Enum.each(assignments, fn assignment ->
        case delete_assignment(actor, assignment) do
          {:ok, _} -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

      length(assignments)
    end)
  end

  # -- asset-class reclassification -----------------------------------------

  @doc """
  Moves securities within the built-in **asset class** tree by setting each
  security's persisted `asset_class` to the target category's code. Unlike the
  stored custom-tree assignments, the asset-class tree is derived from the
  security field, so a "move" here edits the security (see ADR-0006). Only the
  `asset_class` built-in tree is reclassifiable; the currency tree is intrinsic.
  """
  def reclassify_securities(security_ids, category_id) when is_list(security_ids) do
    with %Category{} = category <- Repo.get(Category, category_id),
         {:ok, classification} <- fetch_classification_by_id(category.classification_id),
         :ok <- ensure_asset_class(classification) do
      # FR-28 transitional: a fixed owner actor until Classifications is made
      # actor-first (leaf-first slice 2); the journal still attributes the write.
      {:ok, Catalog.set_asset_class(Actor.owner_ui(), security_ids, category.key)}
    else
      nil -> {:error, :category_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Resets the given securities' `asset_class` to automatic (inferred on read),
  i.e. dragging them to the asset-class tree's "Unsorted" bucket.
  """
  def reset_asset_class(security_ids) when is_list(security_ids) do
    {:ok, Catalog.set_asset_class(Actor.owner_ui(), security_ids, nil)}
  end

  defp ensure_asset_class(%Classification{key: "asset_class"}), do: :ok
  defp ensure_asset_class(%Classification{}), do: {:error, :not_reclassifiable}

  # -- built-in seeding ------------------------------------------------------

  @doc "Idempotently seeds the built-in classification trees. Returns :ok."
  def ensure_builtins do
    ensure_builtin("asset_class", "Asset class", builtin_asset_class_categories())
    ensure_builtin("currency", "Currency", builtin_currency_categories())
    :ok
  end

  @doc """
  Seeds the built-in trees at application startup when enabled (#529), so reads
  never have to. Gated by the `:seed_builtins_on_boot` config (default true; off
  in the test environment, where each test seeds within its own sandbox).
  Returns `:ok` either way.
  """
  def seed_builtins_on_boot do
    if Application.get_env(:portfolixir, :seed_builtins_on_boot, true) do
      ensure_builtins()
    else
      :ok
    end
  end

  # Each spec is `{key, label, color, parent_key}`; parents are listed before
  # their children so parent ids resolve in a single pass.
  defp builtin_asset_class_categories do
    Enum.map(@asset_class_tree, fn {key, parent_key} ->
      {key, AssetClasses.label(key), Map.get(@asset_class_colors, key), parent_key}
    end)
  end

  defp builtin_currency_categories do
    Enum.map(Currencies.options(), fn {label, code} -> {code, label, nil, nil} end)
  end

  defp ensure_builtin(key, name, categories) do
    classification = ensure_builtin_classification(key, name)
    ensure_builtin_categories(classification, categories)
  end

  # Built-in trees are derived/system data seeded on first access. The write is
  # attributed to a fixed `system_job` actor so it passes the armed-table guard
  # and stays auditable (FR-28). The `Repo.get_by` check above means a re-seed on
  # a later read does NOT insert (no guard trigger, no journal noise) — only the
  # genuine first creation writes and journals.
  defp builtin_actor, do: Actor.system_job("builtin_seed")

  defp ensure_builtin_classification(key, name) do
    case Repo.get_by(Classification, key: key) do
      %Classification{} = classification ->
        classification

      nil ->
        {:ok, classification} =
          Multi.new()
          |> Multi.insert(
            :classification,
            Classification.builtin_changeset(%Classification{}, %{
              name: name,
              key: key,
              built_in: true,
              position: 0
            }),
            on_conflict: :nothing,
            conflict_target: :key
          )
          |> Journal.record(builtin_actor(),
            resource_type: "classification",
            operation: :create,
            source: :classification
          )
          |> Repo.transaction()
          |> classification_result()

        # Re-fetch the canonical row: `on_conflict: :nothing` is a race backstop
        # (a concurrent first seed past the `get_by` check), and the conflicting
        # insert returns a row without the persisted id.
        Repo.get_by(Classification, key: key) || classification
    end
  end

  defp ensure_builtin_categories(classification, categories) do
    existing =
      Category
      |> where([c], c.classification_id == ^classification.id)
      |> Repo.all()
      |> Map.new(&{&1.key, &1})

    _seen =
      categories
      |> Enum.with_index()
      |> Enum.reduce(existing, fn {{key, label, color, parent_key}, index}, seen ->
        parent_id =
          case parent_key && Map.get(seen, parent_key) do
            %Category{id: id} -> id
            _ -> nil
          end

        category = seed_category(classification, seen, key, label, color, index, parent_id)
        Map.put(seen, key, category)
      end)

    :ok
  end

  defp seed_category(classification, seen, key, label, color, index, parent_id) do
    case Map.get(seen, key) do
      nil ->
        {:ok, category} =
          Multi.new()
          |> Multi.insert(
            :category,
            Category.builtin_changeset(%Category{}, %{
              classification_id: classification.id,
              key: key,
              name: label,
              color: color,
              position: index,
              parent_id: parent_id
            }),
            on_conflict: :nothing,
            conflict_target: [:classification_id, :key]
          )
          |> Journal.record(builtin_actor(),
            resource_type: "category",
            operation: :create,
            source: :category
          )
          |> Repo.transaction()
          |> category_result()

        # Re-fetch the canonical row (id available for child parents) — see the
        # race-backstop note on ensure_builtin_classification/2.
        Repo.get_by(Category, classification_id: classification.id, key: key) || category

      %Category{color: nil} = category when not is_nil(color) ->
        # Backfill a default color, but never overwrite a user-chosen one. This
        # one-time write is journaled under the same built-in seed actor.
        {:ok, updated} =
          Multi.new()
          |> Multi.update(:category, Ecto.Changeset.change(category, color: color))
          |> Journal.record(builtin_actor(),
            resource_type: "category",
            operation: :update,
            source: :category,
            before: category
          )
          |> Repo.transaction()
          |> category_result()

        updated

      category ->
        category
    end
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

  defp categories_query(classification_id) do
    from(c in Category,
      where: c.classification_id == ^classification_id,
      order_by: [asc: c.position, asc: c.id]
    )
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
