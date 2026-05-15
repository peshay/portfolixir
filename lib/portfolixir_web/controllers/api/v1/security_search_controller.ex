defmodule PortfolixirWeb.Api.V1.SecuritySearchController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Catalog.SecuritySearch
  alias PortfolixirWeb.Api.V1.JSON

  @allowed_types ["security", "crypto"]

  def index(conn, params) do
    query = Map.get(params, "query", "")
    type = Map.get(params, "type", "security")

    if type in @allowed_types do
      {:ok, results} = SecuritySearch.search(query, type: type)
      json(conn, %{data: Enum.map(results, &JSON.search_result/1)})
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{errors: %{type: ["is invalid"]}})
    end
  end
end
