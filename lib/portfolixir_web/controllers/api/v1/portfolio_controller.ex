defmodule PortfolixirWeb.Api.V1.PortfolioController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, _params) do
    json(conn, %{data: Enum.map(Portfolios.list_portfolios(), &JSON.portfolio/1)})
  end

  def create(conn, params) do
    attrs = Map.get(params, "portfolio", %{})

    case Portfolios.create_portfolio(attrs) do
      {:ok, portfolio} ->
        conn
        |> put_status(:created)
        |> json(%{data: JSON.portfolio(portfolio)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: JSON.errors(changeset)})
    end
  end
end
