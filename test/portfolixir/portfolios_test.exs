defmodule Portfolixir.PortfoliosTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Portfolios

  setup do
    {:ok, _currency} = Catalog.create_currency(%{code: "EUR", name: "Euro", minor_units: 2})
    :ok
  end

  test "create portfolio with base currency EUR" do
    assert {:ok, portfolio} =
             Portfolios.create_portfolio(%{
               name: "Long Term",
               description: "Synthetic portfolio",
               base_currency_code: "EUR"
             })

    assert portfolio.name == "Long Term"
    assert portfolio.base_currency_code == "EUR"
  end

  test "create portfolio without name fails" do
    assert {:error, changeset} =
             Portfolios.create_portfolio(%{description: "Missing name", base_currency_code: "EUR"})

    assert %{name: ["can't be blank"]} = errors_on(changeset)
  end

  test "create portfolio with unknown currency fails" do
    assert {:error, changeset} =
             Portfolios.create_portfolio(%{name: "No Currency", base_currency_code: "XYZ"})

    assert %{base_currency: ["does not exist"]} = errors_on(changeset)
  end
end
