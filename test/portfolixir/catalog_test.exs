defmodule Portfolixir.CatalogTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog

  test "creating EUR succeeds" do
    assert {:ok, currency} =
             Catalog.create_currency(%{code: "EUR", name: "Euro", minor_units: 2})

    assert currency.code == "EUR"
    assert currency.name == "Euro"
    assert currency.minor_units == 2
  end

  test "creating duplicate EUR fails" do
    assert {:ok, _} = Catalog.create_currency(%{code: "EUR", name: "Euro", minor_units: 2})

    assert {:error, changeset} =
             Catalog.create_currency(%{code: "EUR", name: "Euro duplicate", minor_units: 2})

    assert %{code: ["has already been taken"]} = errors_on(changeset)
  end

  test "lowercase currency code is rejected" do
    assert {:error, changeset} =
             Catalog.create_currency(%{code: "eur", name: "Euro", minor_units: 2})

    assert %{code: [error_message]} = errors_on(changeset)
    assert error_message in ["has invalid format", "is invalid"]
  end

  test "invalid code length fails" do
    assert {:error, changeset} =
             Catalog.create_currency(%{code: "EURO", name: "Euro", minor_units: 2})

    assert %{code: ["has invalid format", "should be 3 character(s)"]} = errors_on(changeset)
  end
end
