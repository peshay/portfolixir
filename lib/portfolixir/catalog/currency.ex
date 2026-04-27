defmodule Portfolixir.Catalog.Currency do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Phoenix.Param, key: :code}
  @primary_key {:code, :string, autogenerate: false}
  schema "currencies" do
    field :name, :string
    field :minor_units, :integer

    timestamps()
  end

  @doc false
  def changeset(currency, attrs) do
    currency
    |> cast(attrs, [:code, :name, :minor_units])
    |> validate_required([:code, :name, :minor_units])
    |> validate_length(:code, is: 3)
    |> validate_format(:code, ~r/^[A-Z]{3}$/)
    |> validate_number(:minor_units, greater_than_or_equal_to: 0, less_than_or_equal_to: 9)
    |> unique_constraint(:code, name: :currencies_pkey)
  end
end
