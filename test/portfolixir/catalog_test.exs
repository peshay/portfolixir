defmodule Portfolixir.CatalogTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Taxonomies

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

  test "assigns a category to a security" do
    {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    assert {:ok, security} =
             Catalog.create_security(%{name: "Test ETF", symbol: "TETF", currency_code: "USD"})

    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Allocation", description: "Portfolio structure"})

    assert {:ok, category} =
             Taxonomies.create_category(%{
               taxonomy_id: taxonomy.id,
               name: "Core ETF",
               description: "Core ETF holdings with broad market exposure"
             })

    assert {:ok, assignment} = Catalog.assign_category_to_security(security.id, category.id)
    assert assignment.security_id == security.id
    assert assignment.category_id == category.id
    assert assignment.weight == Decimal.new("1.0")
  end

  test "duplicate security/category assignment is rejected" do
    {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    assert {:ok, security} =
             Catalog.create_security(%{name: "Test ETF", symbol: "TETF", currency_code: "USD"})

    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Allocation", description: "Portfolio structure"})

    assert {:ok, category} =
             Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Core ETF"})

    assert {:ok, _} = Catalog.assign_category_to_security(security.id, category.id)

    assert {:error, changeset} = Catalog.assign_category_to_security(security.id, category.id)
    assert %{security_id: ["has already been taken"]} = errors_on(changeset)
  end

  test "list_security_categories returns assigned categories with description" do
    {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    assert {:ok, security} =
             Catalog.create_security(%{name: "Test ETF", symbol: "TETF", currency_code: "USD"})

    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Allocation", description: "Portfolio structure"})

    {:ok, category} =
      Taxonomies.create_category(%{
        taxonomy_id: taxonomy.id,
        name: "Core ETF",
        description: "Core ETF holdings with broad market exposure"
      })

    assert {:ok, _} = Catalog.assign_category_to_security(security.id, category.id)

    assert [listed_category] = Catalog.list_security_categories(security.id)
    assert listed_category.id == category.id
    assert listed_category.name == "Core ETF"
    assert listed_category.description == "Core ETF holdings with broad market exposure"
  end

  test "remove_category_assignment/2 removes a category assignment from security" do
    {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    assert {:ok, security} =
             Catalog.create_security(%{name: "Test ETF", symbol: "TETF", currency_code: "USD"})

    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Allocation", description: "Portfolio structure"})

    {:ok, category} = Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Core ETF"})

    assert {:ok, _} = Catalog.assign_category_to_security(security.id, category.id)
    assert {:ok, _} = Catalog.remove_category_assignment(security.id, category.id)
    assert Catalog.list_security_categories(security.id) == []
  end

  test "remove_category_assignment/2 is no-op and returns clear error when missing" do
    {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    assert {:ok, security} =
             Catalog.create_security(%{name: "Test ETF", symbol: "TETF", currency_code: "USD"})

    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Allocation", description: "Portfolio structure"})

    {:ok, category} = Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Core ETF"})

    assert {:error, :not_found} = Catalog.remove_category_assignment(security.id, category.id)
  end

  test "assigning category to unknown security fails" do
    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Allocation", description: "Portfolio structure"})

    assert {:ok, category} =
             Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Core ETF"})

    assert {:error, changeset} = Catalog.assign_category_to_security(999_999, category.id)
    assert %{security: ["does not exist"]} = errors_on(changeset)
  end

  test "assigning unknown category to security fails" do
    {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    assert {:ok, security} =
             Catalog.create_security(%{name: "Test ETF", symbol: "TETF", currency_code: "USD"})

    assert {:error, changeset} = Catalog.assign_category_to_security(security.id, 999_999)
    assert %{category: ["does not exist"]} = errors_on(changeset)
  end
end
