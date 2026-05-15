defmodule PortfolixirWeb.Api.V1.TransactionController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Ledger
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, _params) do
    json(conn, %{data: Enum.map(Ledger.list_transactions(), &JSON.transaction/1)})
  end

  def create(conn, params) do
    attrs = Map.get(params, "transaction", %{})

    case Ledger.create_transaction(attrs) do
      {:ok, transaction} ->
        conn
        |> put_status(:created)
        |> json(%{data: JSON.transaction(transaction)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: JSON.errors(changeset)})
    end
  end
end
