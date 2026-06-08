defmodule PortfolixirWeb.Api.V1.SecuritiesAccountController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, _params) do
    json(conn, %{
      data: Enum.map(Portfolios.list_securities_accounts(), &JSON.securities_account/1)
    })
  end

  def show(conn, %{"id" => id}) do
    with {:ok, sid} <- parse_id(id),
         %SecuritiesAccount{} = account <- Portfolios.get_securities_account(sid) do
      json(conn, %{data: JSON.securities_account(account)})
    else
      _ -> not_found(conn)
    end
  end

  def create(conn, params) do
    attrs = Map.get(params, "securities_account", %{})

    case Portfolios.create_securities_account(attrs) do
      {:ok, account} ->
        conn
        |> put_status(:created)
        |> json(%{data: JSON.securities_account(account)})

      {:error, changeset} ->
        unprocessable(conn, JSON.errors(changeset))
    end
  end

  def update(conn, %{"id" => id} = params) do
    # Never let an update move an account into a different portfolio.
    attrs = params |> Map.get("securities_account", %{}) |> Map.drop(["portfolio_id"])

    with {:ok, sid} <- parse_id(id),
         %SecuritiesAccount{} = account <- Portfolios.get_securities_account(sid),
         {:ok, updated} <- Portfolios.update_securities_account(account, attrs) do
      json(conn, %{data: JSON.securities_account(updated)})
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
      {:error, changeset} -> unprocessable(conn, JSON.errors(changeset))
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, sid} <- parse_id(id),
         %SecuritiesAccount{} = account <- Portfolios.get_securities_account(sid) do
      case Portfolios.delete_securities_account(account) do
        {:ok, _} -> send_resp(conn, :no_content, "")
        {:error, :referenced} -> conflict(conn)
        {:error, changeset} -> unprocessable(conn, JSON.errors(changeset))
      end
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
    end
  end

  defp parse_id(value) when is_integer(value), do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_id(_value), do: :error

  defp unprocessable(conn, errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end

  defp conflict(conn) do
    conn
    |> put_status(:conflict)
    |> json(%{errors: %{detail: "securities account is referenced by existing records"}})
  end
end
