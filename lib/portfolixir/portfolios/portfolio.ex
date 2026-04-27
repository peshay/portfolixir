defmodule Portfolixir.Portfolios.Portfolio do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.Currency

  schema "portfolios" do
    field(:name, :string)
    field(:description, :string)

    belongs_to(:base_currency, Currency,
      foreign_key: :base_currency_code,
      references: :code,
      type: :string,
      define_field: true
    )

    timestamps()
  end

  @doc false
  def changeset(portfolio, attrs) do
    portfolio
    |> cast(attrs, [:name, :description, :base_currency_code])
    |> validate_required([:name, :base_currency_code])
    |> assoc_constraint(:base_currency)
  end
end
