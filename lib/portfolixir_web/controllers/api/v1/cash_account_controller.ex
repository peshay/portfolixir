defmodule PortfolixirWeb.Api.V1.CashAccountController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, _params) do
    json(conn, %{data: Enum.map(Portfolios.list_cash_accounts(), &JSON.cash_account/1)})
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
