defmodule Portfolixir.Portfolios.Portfolio do
  use Ecto.Schema
  import Ecto.Changeset

  schema "portfolios" do
    field(:name, :string)
    field(:base_currency_code, :string)
    field(:notes, :string)

    timestamps()
  end

  def changeset(portfolio, attrs) do
    portfolio
    |> cast(attrs, [:name, :base_currency_code, :notes])
    |> normalize_currency_code()
    |> validate_required([:name, :base_currency_code])
    |> validate_length(:base_currency_code, is: 3)
  end

  defp normalize_currency_code(changeset) do
    update_change(changeset, :base_currency_code, fn
      value when is_binary(value) -> value |> String.trim() |> String.upcase()
      value -> value
    end)
  end
end
