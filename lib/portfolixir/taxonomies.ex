defmodule Portfolixir.Taxonomies do
  @moduledoc "Taxonomy and category context."

  import Ecto.Query
  alias Portfolixir.Repo
  alias Portfolixir.Taxonomies.{Category, Taxonomy}

  def create_taxonomy(attrs) when is_map(attrs) do
    %Taxonomy{}
    |> Taxonomy.changeset(attrs)
    |> Repo.insert()
  end

  def list_taxonomies do
    Repo.all(Taxonomy)
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
