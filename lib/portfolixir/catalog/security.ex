defmodule Portfolixir.Catalog.Security do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.SecurityCategoryAssignment
  alias Portfolixir.Catalog.FundAllocation
  alias Portfolixir.Catalog.FundDocument
  alias Portfolixir.Catalog.Currency

  schema "securities" do
    field(:name, :string)
    field(:symbol, :string)
    field(:active, :boolean, default: true)
    field(:exchange_code, :string)
    field(:provider_symbol, :string)
    field(:isin, :string)
    field(:wkn, :string)
    field(:notes, :string)

    belongs_to(:currency, Currency,
      foreign_key: :currency_code,
      references: :code,
      type: :string,
      define_field: true
    )

    has_many(:security_category_assignments, SecurityCategoryAssignment)
    has_many(:fund_allocations, FundAllocation)
    has_many(:categories, through: [:security_category_assignments, :category])
    has_many(:fund_documents, FundDocument)

    timestamps()
  end

  @doc false
  def changeset(security, attrs) do
    security
    |> cast(attrs, [
      :name,
      :symbol,
      :active,
      :exchange_code,
      :provider_symbol,
      :isin,
      :wkn,
      :currency_code,
      :notes
    ])
    |> validate_required([:name, :symbol, :currency_code])
    |> assoc_constraint(:currency)
    |> unique_constraint(:provider_symbol,
      name: :securities_provider_symbol_exchange_code_unique_index
    )
  end
end
