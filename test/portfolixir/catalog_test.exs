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

  test "creating Apple security with USD" do
    {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    assert {:ok, security} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL",
               currency_code: "USD"
             })

    assert security.name == "Apple Inc."
    assert security.symbol == "AAPL"
    assert security.currency_code == "USD"
  end

  test "creating Apple Frankfurt security with EUR" do
    {:ok, _} = Catalog.create_currency(%{code: "EUR", name: "Euro", minor_units: 2})

    assert {:ok, security} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL.F",
               exchange_code: "Frankfurt",
               provider_symbol: "AAPL.F",
               currency_code: "EUR"
             })

    assert security.name == "Apple Inc."
    assert security.symbol == "AAPL.F"
    assert security.exchange_code == "Frankfurt"
    assert security.provider_symbol == "AAPL.F"
    assert security.currency_code == "EUR"
  end

  test "creating a security without currency fails" do
    {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    assert {:error, changeset} =
             Catalog.create_security(%{name: "Apple Inc.", symbol: "AAPL"})

    assert %{currency_code: ["can't be blank"]} = errors_on(changeset)
  end

  test "creating a security with unknown currency fails" do
    assert {:error, changeset} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL",
               currency_code: "UNKNOWN"
             })

    assert %{currency: ["does not exist"]} = errors_on(changeset)
  end

  test "creating a security without name fails" do
    {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    assert {:error, changeset} =
             Catalog.create_security(%{symbol: "AAPL", currency_code: "USD"})

    assert %{name: ["can't be blank"]} = errors_on(changeset)
  end

  test "creating a security without symbol fails" do
    {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    assert {:error, changeset} =
             Catalog.create_security(%{name: "Apple Inc.", currency_code: "USD"})

    assert %{symbol: ["can't be blank"]} = errors_on(changeset)
  end

  test "duplicate provider symbol and exchange combination is rejected when both are present" do
    {:ok, _} = Catalog.create_currency(%{code: "EUR", name: "Euro", minor_units: 2})

    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL.F",
               exchange_code: "Frankfurt",
               provider_symbol: "AAPL.F",
               currency_code: "EUR"
             })

    assert {:error, changeset} =
             Catalog.create_security(%{
               name: "Apple Holding",
               symbol: "AAPL.H",
               exchange_code: "Frankfurt",
               provider_symbol: "AAPL.F",
               currency_code: "EUR"
             })

    assert %{provider_symbol: ["has already been taken"]} = errors_on(changeset)
  end

  test "same provider symbol is allowed when exchange_code is nil" do
    {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Apple US",
               symbol: "AAPL",
               provider_symbol: "AAPL",
               currency_code: "USD"
             })

    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Apple US Class C",
               symbol: "AAPL.CL",
               provider_symbol: "AAPL",
               currency_code: "USD"
             })
  end

  test "same exchange code is allowed when provider_symbol is nil" do
    {:ok, _} = Catalog.create_currency(%{code: "EUR", name: "Euro", minor_units: 2})

    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Apple DE",
               symbol: "AAPL.DE",
               exchange_code: "Frankfurt",
               currency_code: "EUR"
             })

    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Apple Alternate",
               symbol: "AAPL.H",
               exchange_code: "Frankfurt",
               currency_code: "EUR"
             })
  end

  test "creating a security with WKN persists" do
    {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    assert {:ok, security} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL",
               currency_code: "USD",
               isin: "US0378331005",
               wkn: "865985"
             })

    assert security.isin == "US0378331005"
    assert security.wkn == "865985"
  end

  test "list_securities returns securities in deterministic order" do
    {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Zebra Holdings",
               symbol: "ZB",
               currency_code: "USD"
             })

    assert {:ok, _} =
             Catalog.create_security(%{name: "Apple Inc.", symbol: "AAPL", currency_code: "USD"})

    assert {:ok, _} =
             Catalog.create_security(%{name: "Apex Fund", symbol: "AXP", currency_code: "USD"})

    securities = Catalog.list_securities()
    assert Enum.map(securities, & &1.name) == ["Apex Fund", "Apple Inc.", "Zebra Holdings"]
  end

  test "update_security/2 can update notes or name" do
    {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    assert {:ok, security} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL",
               currency_code: "USD",
               notes: "original note"
             })

    assert {:ok, updated_security} =
             Catalog.update_security(security, %{
               name: "Apple Corporation",
               notes: "updated note"
             })

    assert updated_security.name == "Apple Corporation"
    assert updated_security.notes == "updated note"
  end

  test "delete_security/1 removes the security" do
    {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    assert {:ok, security} =
             Catalog.create_security(%{name: "Apple Inc.", symbol: "AAPL", currency_code: "USD"})

    assert {:ok, _deleted_security} = Catalog.delete_security(security)
    assert_raise Ecto.NoResultsError, fn -> Catalog.get_security!(security.id) end
  end
end
