defmodule Portfolixir.Fx.ExchangeRate do
  @moduledoc """
  A single dated exchange rate `1 base_currency = rate quote_currency`.

  Rates are an append/upsert log keyed by `(base_currency, quote_currency,
  date)`. Portfolixir stores rates against a single hub currency (EUR), matching
  the ECB reference rates; any other pair is derived by triangulation in
  `Portfolixir.Fx`. Decimals are used everywhere — never floats — so conversions
  round-trip losslessly (see ADR-0007).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.Currencies

  @sources ~w(auto manual ecb)

  schema "exchange_rates" do
    field(:base_currency, :string)
    field(:quote_currency, :string)
    field(:date, :date)
    field(:rate, :decimal)
    field(:source, :string)

    timestamps()
  end

  def sources, do: @sources

  def changeset(rate, attrs) do
    rate
    |> cast(attrs, [:base_currency, :quote_currency, :date, :rate, :source])
    |> validate_required([:base_currency, :quote_currency, :date, :rate, :source])
    |> update_change(:base_currency, &normalize_code/1)
    |> update_change(:quote_currency, &normalize_code/1)
    |> validate_currency(:base_currency)
    |> validate_currency(:quote_currency)
    |> validate_number(:rate, greater_than: 0)
    |> validate_inclusion(:source, @sources, message: "is invalid")
    |> unique_constraint([:base_currency, :quote_currency, :date],
      name: :exchange_rates_base_currency_quote_currency_date_index
    )
  end

  defp normalize_code(code) when is_binary(code), do: code |> String.trim() |> String.upcase()
  defp normalize_code(code), do: code

  defp validate_currency(changeset, field) do
    validate_change(changeset, field, fn ^field, code ->
      if Currencies.supported?(code), do: [], else: [{field, "is not a supported currency"}]
    end)
  end
end
