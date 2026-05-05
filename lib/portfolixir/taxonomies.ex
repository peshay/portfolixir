defmodule Portfolixir.Taxonomies do
  @moduledoc "Taxonomy and category context."

  import Ecto.Query
  alias Portfolixir.Catalog.{FundAllocation, FundAllocationItem}
  alias Portfolixir.Repo
  alias Portfolixir.Taxonomies.{Category, FundAllocationCategoryMapping, Taxonomy}

  @portfolio_performance_presets [
    %{
      name: "Strategien",
      description: "Klassifizierungssystem im Stil von Portfolio Performance fuer Strategien."
    },
    %{
      name: "Regionen",
      description: "Klassifizierungssystem im Stil von Portfolio Performance fuer Regionen."
    },
    %{
      name: "Branchen",
      description: "Klassifizierungssystem im Stil von Portfolio Performance fuer Branchen."
    },
    %{
      name: "Wertpapierarten",
      description:
        "Klassifizierungssystem im Stil von Portfolio Performance fuer Wertpapierarten."
    }
  ]

  def create_taxonomy(attrs) when is_map(attrs) do
    %Taxonomy{}
    |> Taxonomy.changeset(attrs)
    |> Repo.insert()
  end

  def list_taxonomies do
    Repo.all(from(t in Taxonomy, order_by: [asc: t.id]))
  end

  def get_taxonomy_by_name(name) when is_binary(name) do
    Repo.get_by(Taxonomy, name: name)
  end

  def ensure_portfolio_performance_presets! do
    Enum.each(@portfolio_performance_presets, fn attrs ->
      case get_taxonomy_by_name(attrs.name) do
        nil ->
          {:ok, _taxonomy} = create_taxonomy(attrs)

        _taxonomy ->
          {:ok, :already_exists}
      end
    end)
  end

  def create_category(attrs) when is_map(attrs) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  def list_categories(taxonomy_id) do
    Repo.all(
      from(c in Category,
        where: c.taxonomy_id == ^taxonomy_id,
        order_by: [asc: c.sort_order, asc: c.name],
        preload: [:security_category_assignments]
      )
    )
  end

  def update_category(%Category{} = category, attrs) when is_map(attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  def delete_category(%Category{} = category) do
    Repo.delete(category)
  end

  def get_category!(id), do: Repo.get!(Category, id)

  def upsert_fund_allocation_category_mapping(attrs) when is_map(attrs) do
    with {:ok, attrs} <- ensure_matching_taxonomy_and_category(attrs) do
      %FundAllocationCategoryMapping{}
      |> FundAllocationCategoryMapping.changeset(attrs)
      |> Repo.insert(
        on_conflict: {:replace, [:category_id, :metadata, :updated_at]},
        conflict_target: [:allocation_type, :source_label, :taxonomy_id]
      )
    end
  end

  def resolve_mapped_fund_allocation_exposures(security_id) when is_integer(security_id) do
    allocations =
      Repo.all(
        from(fa in FundAllocation,
          where: fa.security_id == ^security_id and fa.status == "active",
          preload: [
            fund_allocation_items:
              ^from(i in FundAllocationItem, order_by: [desc: i.weight, asc: i.label])
          ]
        )
      )

    mapping_index =
      Repo.all(
        from(m in FundAllocationCategoryMapping,
          order_by: [asc: m.id],
          preload: [:taxonomy, :category]
        )
      )
      |> Enum.group_by(fn m -> {m.allocation_type, m.source_label} end)

    results =
      Enum.flat_map(allocations, fn allocation ->
        Enum.flat_map(allocation.fund_allocation_items, fn item ->
          mappings = Map.get(mapping_index, {allocation.allocation_type, item.label}, [])

          if mappings == [] do
            [
              %{
                allocation_type: allocation.allocation_type,
                source_label: item.label,
                weight: item.weight,
                taxonomy_id: nil,
                taxonomy_name: nil,
                category_id: nil,
                category_name: nil,
                status: :unmapped
              }
            ]
          else
            Enum.map(mappings, fn mapping ->
              %{
                allocation_type: allocation.allocation_type,
                source_label: item.label,
                weight: item.weight,
                taxonomy_id: mapping.taxonomy_id,
                taxonomy_name: mapping.taxonomy.name,
                category_id: mapping.category_id,
                category_name: mapping.category.name,
                status: :mapped
              }
            end)
          end
        end)
      end)

    warnings =
      results
      |> Enum.filter(&(&1.status == :unmapped))
      |> Enum.map(fn result ->
        "Unmapped allocation label #{result.allocation_type}:#{result.source_label}"
      end)
      |> Enum.uniq()

    %{items: results, warnings: warnings}
  end

  defp ensure_matching_taxonomy_and_category(attrs) do
    taxonomy_id = Map.get(attrs, :taxonomy_id) || Map.get(attrs, "taxonomy_id")
    category_id = Map.get(attrs, :category_id) || Map.get(attrs, "category_id")

    case Repo.get(Category, category_id) do
      %Category{taxonomy_id: ^taxonomy_id} ->
        {:ok, attrs}

      %Category{} ->
        {:error,
         Ecto.Changeset.change(%FundAllocationCategoryMapping{})
         |> Ecto.Changeset.add_error(:category_id, "must belong to taxonomy")}

      nil ->
        {:ok, attrs}
    end
  end
end
