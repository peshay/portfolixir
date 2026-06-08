defmodule Portfolixir.Classifications.Assignment do
  @moduledoc """
  Places one security into one category of a classification.

  Uniqueness is `(security_id, classification_id)`: a security sits in at most
  one category per classification. Target weights per category now exist
  (`Portfolixir.Portfolios.Targets` and `Portfolixir.Portfolios.Allocation`, see
  ADR-0008); splitting a single security across several categories with partial
  weights remains out of scope.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Classifications.Category
  alias Portfolixir.Classifications.Classification

  schema "security_category_assignments" do
    belongs_to(:security, Security)
    belongs_to(:classification, Classification)
    belongs_to(:category, Category)

    timestamps()
  end

  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, [:security_id, :classification_id, :category_id])
    |> validate_required([:security_id, :classification_id, :category_id])
    |> assoc_constraint(:security)
    |> assoc_constraint(:classification)
    |> assoc_constraint(:category)
    |> unique_constraint([:security_id, :classification_id],
      name: :security_category_assignments_security_id_classification_id_index
    )
  end
end
