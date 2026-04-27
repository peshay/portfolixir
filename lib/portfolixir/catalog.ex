defmodule Portfolixir.Catalog do
  @moduledoc "Currency catalogue context."

  import Ecto.Query
  alias Portfolixir.Catalog.Currency
  alias Portfolixir.Repo

  @mvp_currencies [
    %{code: "EUR", name: "Euro", minor_units: 2},
    %{code: "USD", name: "US Dollar", minor_units: 2},
    %{code: "CHF", name: "Swiss Franc", minor_units: 2},
    %{code: "GBP", name: "British Pound", minor_units: 2},
    %{code: "SEK", name: "Swedish Krona", minor_units: 2},
    %{code: "NOK", name: "Norwegian Krone", minor_units: 2},
    %{code: "DKK", name: "Danish Krone", minor_units: 2},
    %{code: "JPY", name: "Japanese Yen", minor_units: 0}
  ]

  def list_currencies do
    from(c in Currency, order_by: [asc: c.code])
    |> Repo.all()
  end

  def get_currency!(code) when is_binary(code) do
    Repo.get_by!(Currency, code: code)
  end

  def get_currency_by_code(code) when is_binary(code) do
    Repo.get_by(Currency, code: code)
  end

  def create_currency(attrs) when is_map(attrs) do
    %Currency{}
    |> Currency.changeset(attrs)
    |> Repo.insert()
  end

  def seed_mvp_currencies! do
    Enum.each(@mvp_currencies, fn attrs ->
      case get_currency_by_code(attrs.code) do
        nil ->
          create_currency(attrs)

        _currency ->
          {:ok, :already_exists}
      end
    end)
  end
end
