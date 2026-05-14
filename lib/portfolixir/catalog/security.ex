defmodule Portfolixir.Catalog.Security do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.SecurityQuote

  schema "securities" do
    field(:name, :string)
    field(:symbol, :string)
    field(:currency_code, :string)
    field(:isin, :string)
    field(:exchange_code, :string)
    field(:notes, :string)

    has_many(:security_quotes, SecurityQuote)

    timestamps()
  end

  def changeset(security, attrs) do
    security
    |> cast(attrs, [:name, :symbol, :currency_code, :isin, :exchange_code, :notes])
    |> normalize_text(:symbol, &String.upcase/1)
    |> normalize_text(:currency_code, &String.upcase/1)
    |> empty_to_nil([:isin, :exchange_code, :notes])
    |> validate_required([:name, :symbol, :currency_code])
    |> validate_length(:currency_code, is: 3)
    |> unique_constraint([:symbol, :currency_code])
  end

  defp normalize_text(changeset, field, fun) do
    update_change(changeset, field, fn
      value when is_binary(value) -> value |> String.trim() |> fun.()
      value -> value
    end)
  end

  defp empty_to_nil(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, acc ->
      update_change(acc, field, fn
        value when is_binary(value) ->
          value = String.trim(value)
          if value == "", do: nil, else: value

        value ->
          value
      end)
    end)
  end
end
