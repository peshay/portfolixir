defmodule Portfolixir.Taxonomies do
  @moduledoc "Taxonomy and category context."

  import Ecto.Query
  alias Portfolixir.Repo
  alias Portfolixir.Taxonomies.{Category, Taxonomy}

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
        order_by: [asc: c.sort_order, asc: c.name]
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
end
