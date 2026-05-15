defmodule Portfolixir.Catalog.Security do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.AssetClasses
  alias Portfolixir.Catalog.Currencies
  alias Portfolixir.Catalog.Feeds

  @providers ~w(portfolio_performance coingecko manual)

  schema "securities" do
    field(:name, :string)
    field(:ticker_symbol, :string)
    field(:isin, :string)
    field(:wkn, :string)
    field(:currency_code, :string)
    field(:exchange_code, :string)
    field(:asset_class, :string)
    field(:note, :string)
    field(:feed, :string)
    field(:feed_url, :string)
    field(:latest_feed, :string)
    field(:latest_feed_url, :string)
    field(:is_retired, :boolean, default: false)
    field(:online_id, :string)
    field(:provider, :string)
    field(:attributes, :map, default: %{})

    timestamps()
  end

  @castable ~w(
    name ticker_symbol isin wkn currency_code exchange_code asset_class
    note feed feed_url latest_feed latest_feed_url is_retired
    online_id provider attributes
  )a

  def changeset(security, attrs) do
    security
    |> cast(attrs, @castable)
    |> normalize_text(:ticker_symbol, &String.upcase/1)
    |> normalize_text(:currency_code, &String.upcase/1)
    |> normalize_text(:exchange_code, &String.upcase/1)
    |> normalize_text(:wkn, &String.upcase/1)
    |> normalize_text(:isin, &String.upcase/1)
    |> empty_to_nil([
      :ticker_symbol,
      :isin,
      :wkn,
      :exchange_code,
      :asset_class,
      :note,
      :feed,
      :feed_url,
      :latest_feed,
      :latest_feed_url,
      :online_id,
      :provider
    ])
    |> default_attributes()
    |> validate_required([:name, :currency_code])
    |> validate_length(:currency_code, is: 3)
    |> validate_inclusion(:currency_code, Currencies.codes(), message: "is invalid")
    |> validate_inclusion(:asset_class, AssetClasses.codes(), message: "is invalid")
    |> validate_inclusion(:provider, @providers, message: "is invalid")
    |> validate_feed(:feed)
    |> validate_feed(:latest_feed)
    |> unique_constraint([:provider, :online_id],
      name: :securities_provider_online_id_unique_index
    )
    |> unique_constraint(:isin, name: :securities_isin_unique_index)
  end

  def delete_changeset(security) do
    security
    |> change()
    |> foreign_key_constraint(:id,
      name: :transactions_security_id_fkey,
      message: "is referenced by existing records"
    )
    |> foreign_key_constraint(:id,
      name: :security_quotes_security_id_fkey,
      message: "is referenced by existing records"
    )
  end

  def asset_classes, do: AssetClasses.codes()
  def providers, do: @providers

  defp validate_feed(changeset, field) do
    case get_field(changeset, field) do
      nil ->
        changeset

      "" ->
        changeset

      value ->
        if Feeds.supported?(value), do: changeset, else: add_error(changeset, field, "is invalid")
    end
  end

  defp default_attributes(changeset) do
    update_change(changeset, :attributes, fn
      nil -> %{}
      value when is_map(value) -> value
      _ -> %{}
    end)
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
