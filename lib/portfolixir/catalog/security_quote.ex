defmodule Portfolixir.Catalog.SecurityQuote do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.Currency
  alias Portfolixir.Catalog.Security

  schema "security_quotes" do
    field(:date, :date)
    field(:source, :string)
    field(:open, :decimal)
    field(:high, :decimal)
    field(:low, :decimal)
    field(:close, :decimal)
    field(:volume, :decimal)
    field(:metadata, :map, default: %{})

    belongs_to(:security, Security)

    belongs_to(:currency, Currency,
      foreign_key: :currency_code,
      references: :code,
      type: :string,
      define_field: true
    )

    timestamps()
  end

  @doc false
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
      :volume,
      :metadata
    ])
    |> validate_required([:security_id, :date, :source, :currency_code, :close])
    |> validate_number(:open, greater_than_or_equal_to: 0)
    |> validate_number(:high, greater_than_or_equal_to: 0)
    |> validate_number(:low, greater_than_or_equal_to: 0)
    |> validate_number(:close, greater_than_or_equal_to: 0)
    |> validate_number(:volume, greater_than_or_equal_to: 0)
    |> validate_metadata_map()
    |> assoc_constraint(:security)
    |> assoc_constraint(:currency)
    |> unique_constraint(:security_id,
      name: :security_quotes_security_id_source_date_unique_index
    )
  end

  defp validate_metadata_map(changeset) do
    validate_change(changeset, :metadata, fn :metadata, metadata ->
      case metadata do
        %{} = _map -> []
        _ -> [metadata: "is invalid"]
      end
    end)
  end
end
