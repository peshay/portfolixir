defmodule Portfolixir.Catalog.SecurityCategoryAssignment do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Taxonomies.Category

  schema "security_category_assignments" do
    field(:weight, :decimal)

    belongs_to(:security, Security)
    belongs_to(:category, Category)

    timestamps()
  end

  @doc false
  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, [:security_id, :category_id, :weight])
    |> validate_required([:security_id, :category_id])
    |> ensure_default_weight()
    |> validate_number(:weight, greater_than: 0)
    |> unique_constraint(:security_id,
      name: :security_category_assignments_security_id_category_id_index
    )
    |> assoc_constraint(:security)
    |> assoc_constraint(:category)
  end

  defp ensure_default_weight(changeset) do
    if get_change(changeset, :weight) in [nil, :not_present] do
      put_change(changeset, :weight, Decimal.new("1.0"))
    else
      changeset
    end
  end
end
