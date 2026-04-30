defmodule Portfolixir.Catalog.FundAllocationItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.FundAllocation

  schema "fund_allocation_items" do
    field(:label, :string)
    field(:weight, :decimal)
    field(:confidence, :decimal)
    field(:metadata, :map, default: %{})

    belongs_to(:fund_allocation, FundAllocation)

    timestamps()
  end

  @doc false
  def changeset(fund_allocation_item, attrs) do
    fund_allocation_item
    |> cast(attrs, [:fund_allocation_id, :label, :weight, :confidence, :metadata])
    |> validate_required([:fund_allocation_id, :label, :weight])
    |> validate_number(:weight, greater_than_or_equal_to: 0)
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> unique_constraint(:label,
      name: :fund_allocation_items_fund_allocation_id_label_unique_index
    )
    |> assoc_constraint(:fund_allocation)
  end
end
