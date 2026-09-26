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

  @type t :: %__MODULE__{}

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

  @doc """
  Re-points a stored assignment onto `security_id` and nothing else (ADR-0050
  §9: a security merge moves the source's assignment where the target has
  none in that classification). The classification and the category stay;
  the unique `(security, classification)` index is declared, so a target
  that gained an assignment meanwhile is a changeset error.
  """
  def reassign_changeset(%__MODULE__{} = assignment, security_id) when is_integer(security_id) do
    assignment
    |> change(security_id: security_id)
    |> assoc_constraint(:security)
    |> unique_constraint([:security_id, :classification_id],
      name: :security_category_assignments_security_id_classification_id_index
    )
  end
end
