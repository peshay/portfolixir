defmodule PortfolixirWeb.Api.V1.CashAccountController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, _params) do
    balances = Ledger.cash_balances()

    data =
      Portfolios.list_cash_accounts()
      |> Enum.map(fn account ->
        balance = Map.get(balances, account.id, Decimal.new("0"))

        account
        |> JSON.cash_account()
        |> Map.put(:balance, JSON.decimal(balance))
      end)

    json(conn, %{data: data})
  end

  def create(conn, params) do
    attrs = Map.get(params, "cash_account", %{})

    case Portfolios.create_cash_account(attrs) do
      {:ok, account} ->
        conn
        |> put_status(:created)
        |> json(%{data: JSON.cash_account(account)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: JSON.errors(changeset)})
    end
  end
end
