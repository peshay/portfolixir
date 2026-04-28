defmodule Portfolixir.PortfoliosTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.DepositAccount

  setup do
    {:ok, _currency} = Catalog.create_currency(%{code: "EUR", name: "Euro", minor_units: 2})
    :ok
  end

  defp create_portfolio(name) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{
        name: name,
        description: "Synthetic portfolio",
        base_currency_code: "EUR"
      })

    portfolio
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
             Portfolios.create_portfolio(%{
               description: "Missing name",
               base_currency_code: "EUR"
             })

    assert %{name: ["can't be blank"]} = errors_on(changeset)
  end

  test "create portfolio with unknown currency fails" do
    assert {:error, changeset} =
             Portfolios.create_portfolio(%{name: "No Currency", base_currency_code: "XYZ"})

    assert %{base_currency: ["does not exist"]} = errors_on(changeset)
  end

  test "create deposit account with valid attributes" do
    portfolio = create_portfolio("Primary portfolio")

    assert {:ok, account} =
             Portfolios.create_deposit_account(%{
               portfolio_id: portfolio.id,
               name: "Primary Cash",
               currency_code: "EUR"
             })

    assert account.portfolio_id == portfolio.id
    assert account.name == "Primary Cash"
    assert account.currency_code == "EUR"
    assert account.active == true
    assert account.notes == nil
  end

  test "create deposit account defaults active to true" do
    portfolio = create_portfolio("Default active")

    assert {:ok, account} =
             Portfolios.create_deposit_account(%{
               portfolio_id: portfolio.id,
               name: "Checking",
               currency_code: "EUR"
             })

    assert account.active == true
  end

  test "create deposit account without required fields fails" do
    assert {:error, changeset} = Portfolios.create_deposit_account(%{})

    assert %{
             portfolio_id: ["can't be blank"],
             name: ["can't be blank"],
             currency_code: ["can't be blank"]
           } =
             errors_on(changeset)
  end

  test "create deposit account with unknown portfolio fails" do
    assert {:error, changeset} =
             Portfolios.create_deposit_account(%{
               portfolio_id: 9_999_999,
               name: "Unknown Portfolio",
               currency_code: "EUR"
             })

    assert %{portfolio: ["does not exist"]} = errors_on(changeset)
  end

  test "create deposit account with unknown currency fails" do
    portfolio = create_portfolio("Bad currency")

    assert {:error, changeset} =
             Portfolios.create_deposit_account(%{
               portfolio_id: portfolio.id,
               name: "Wrong currency",
               currency_code: "ZZZ"
             })

    assert %{currency: ["does not exist"]} = errors_on(changeset)
  end

  test "list deposit accounts for a portfolio only returns that portfolio's accounts" do
    first_portfolio = create_portfolio("Portfolio A")
    second_portfolio = create_portfolio("Portfolio B")

    assert {:ok, _account} =
             Portfolios.create_deposit_account(%{
               portfolio_id: first_portfolio.id,
               name: "Zeta",
               currency_code: "EUR"
             })

    assert {:ok, account_for_ordering} =
             Portfolios.create_deposit_account(%{
               portfolio_id: first_portfolio.id,
               name: "Alpha",
               currency_code: "EUR"
             })

    assert {:ok, _other_account} =
             Portfolios.create_deposit_account(%{
               portfolio_id: second_portfolio.id,
               name: "Beta",
               currency_code: "EUR"
             })

    assert [alpha, zeta] = Portfolios.list_deposit_accounts_for_portfolio(first_portfolio.id)

    assert alpha.id == account_for_ordering.id
    assert zeta.name == "Zeta"
  end

  test "update deposit account name, notes, and active" do
    portfolio = create_portfolio("Update portfolio")

    {:ok, account} =
      Portfolios.create_deposit_account(%{
        portfolio_id: portfolio.id,
        name: "Cash",
        currency_code: "EUR",
        notes: "start"
      })

    assert {:ok, updated_account} =
             Portfolios.update_deposit_account(account, %{
               name: "High Yield",
               notes: "updated",
               active: false
             })

    assert updated_account.name == "High Yield"
    assert updated_account.notes == "updated"
    assert updated_account.active == false
  end

  test "delete deposit account works" do
    portfolio = create_portfolio("Delete portfolio")

    {:ok, account} =
      Portfolios.create_deposit_account(%{
        portfolio_id: portfolio.id,
        name: "Closed",
        currency_code: "EUR"
      })

    assert {:ok, %DepositAccount{}} = Portfolios.delete_deposit_account(account)
    assert_raise Ecto.NoResultsError, fn -> Portfolios.get_deposit_account!(account.id) end
  end
end
