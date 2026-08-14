defmodule PortfolixirWeb.Api.V1.HoldingController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.Api.V1.FieldSelection
  alias PortfolixirWeb.Api.V1.JSON

  # FR-37 (#665): sparse fieldsets over the serializer's own field list.
  @fields_whitelist FieldSelection.whitelist(JSON.holding_fields())

  def index(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, id} <- parse_id(portfolio_id),
         portfolio when not is_nil(portfolio) <- Portfolios.get_portfolio(id),
         {:ok, fields} <- FieldSelection.parse(params, @fields_whitelist) do
      holdings =
        id
        |> Ledger.holdings_for_portfolio()
        |> filter_holdings(params)

      response =
        JSON.holdings(holdings, id)
        |> Map.update!(:data, fn rows ->
          Enum.map(rows, &FieldSelection.take(&1, fields))
        end)

      json(conn, response)
    else
      :error ->
        not_found(conn)

      nil ->
        not_found(conn)

      {:error, :fields} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{fields: ["is invalid"]}})
    end
  end

  # Optional in-memory filters on the enriched holdings.
  defp filter_holdings(holdings, params) do
    security_id = optional_id(params["security_id"])
    account_id = optional_id(params["securities_account_id"])

    holdings
    |> filter_by(& &1.security_id, security_id)
    |> filter_by(& &1.securities_account_id, account_id)
  end

  defp filter_by(holdings, _selector, nil), do: holdings

  defp filter_by(holdings, selector, value),
    do: Enum.filter(holdings, fn holding -> selector.(holding) == value end)

  defp optional_id(value) do
    case parse_id(value) do
      {:ok, id} -> id
      _ -> nil
    end
  end

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_id(_value), do: :error

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end
end
