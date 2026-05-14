defmodule Portfolixir.Catalog.SecurityQuote do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.Security

  schema "security_quotes" do
    field(:date, :date)
    field(:source, :string, default: "manual")
    field(:currency_code, :string)
    field(:open, :decimal)
    field(:high, :decimal)
    field(:low, :decimal)
    field(:close, :decimal)
    field(:volume, :decimal)

    belongs_to(:security, Security)

    timestamps()
  end

  def changeset(security_quote, attrs) do
    security_quote
    |> cast(attrs, [
      :security_id,
      :date,
      :source,
      :currency_code,
      :open,
      :high,
      :low,
      :close,
      :volume
    ])
    |> normalize_currency_code()
    |> default_source()
    |> validate_required([:security_id, :date, :source, :currency_code, :close])
    |> validate_number(:open, greater_than_or_equal_to: 0)
    |> validate_number(:high, greater_than_or_equal_to: 0)
    |> validate_number(:low, greater_than_or_equal_to: 0)
    |> validate_number(:close, greater_than_or_equal_to: 0)
    |> validate_number(:volume, greater_than_or_equal_to: 0)
    |> assoc_constraint(:security)
    |> unique_constraint([:security_id, :source, :date])
  end

  defp normalize_currency_code(changeset) do
    update_change(changeset, :currency_code, fn
      value when is_binary(value) -> value |> String.trim() |> String.upcase()
      value -> value
    end)
  end

  defp default_source(changeset) do
    case get_field(changeset, :source) do
      nil -> put_change(changeset, :source, "manual")
      "" -> put_change(changeset, :source, "manual")
      _source -> changeset
    end
  end
end
