defmodule PortfolixirWeb.Api.V1.SecuritiesAccountController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, _params) do
    json(conn, %{
      data: Enum.map(Portfolios.list_securities_accounts(), &JSON.securities_account/1)
    })
  end

  def create(conn, params) do
    attrs = Map.get(params, "securities_account", %{})

    case Portfolios.create_securities_account(attrs) do
      {:ok, account} ->
        conn
        |> put_status(:created)
        |> json(%{data: JSON.securities_account(account)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: JSON.errors(changeset)})
    end
  end
end
