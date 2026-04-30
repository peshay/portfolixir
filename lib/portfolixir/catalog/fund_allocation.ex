defmodule Portfolixir.Catalog.FundAllocation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.FundAllocationItem
  alias Portfolixir.Catalog.Security

  @allocation_types ["region", "country", "sector", "asset_class"]

  schema "fund_allocations" do
    field(:source, :string)
    field(:allocation_type, :string)
    field(:as_of_date, :date)
    field(:status, :string, default: "active")
    field(:metadata, :map, default: %{})

    belongs_to(:security, Security)
    has_many(:fund_allocation_items, FundAllocationItem)

    timestamps()
  end

  @doc false
  def changeset(fund_allocation, attrs) do
    fund_allocation
    |> cast(attrs, [
      :security_id,
      :source,
      :allocation_type,
      :as_of_date,
      :status,
      :metadata
    ])
    |> validate_required([:security_id, :source, :allocation_type])
    |> validate_inclusion(:allocation_type, @allocation_types)
    |> assoc_constraint(:security)
    |> unique_constraint(:security_id,
      name: :fund_allocation_uniq_not_null
    )
    |> unique_constraint(:security_id,
      name: :fund_allocation_uniq_null
    )
  end
end
