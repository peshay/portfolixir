defmodule PortfolixirWeb.Api.V1.TransactionController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, params) do
    case list_opts(params) do
      {:ok, opts} ->
        json(conn, %{data: Enum.map(Ledger.list_transactions(opts), &JSON.transaction/1)})

      {:error, field} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{field => ["is invalid"]}})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, tid} <- parse_id(id),
         %Transaction{} = transaction <- Ledger.get_transaction(tid) do
      json(conn, %{data: JSON.transaction(transaction)})
    else
      _ -> not_found(conn)
    end
  end

  def create(conn, params) do
    attrs = Map.get(params, "transaction", %{})

    case Ledger.create_transaction(attrs) do
      {:ok, transaction} ->
        conn
        |> put_status(:created)
        |> json(%{data: JSON.transaction(transaction)})

      {:error, changeset} ->
        unprocessable(conn, JSON.errors(changeset))
    end
  end

  def update(conn, %{"id" => id} = params) do
    attrs = Map.get(params, "transaction", %{})

    with {:ok, tid} <- parse_id(id),
         %Transaction{} = transaction <- Ledger.get_transaction(tid),
         {:ok, updated} <- Ledger.update_transaction(transaction, attrs) do
      json(conn, %{data: JSON.transaction(updated)})
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
      {:error, changeset} -> unprocessable(conn, JSON.errors(changeset))
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, tid} <- parse_id(id),
         %Transaction{} = transaction <- Ledger.get_transaction(tid),
         {:ok, _} <- Ledger.delete_transaction(transaction) do
      send_resp(conn, :no_content, "")
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
      {:error, _changeset} -> conflict(conn)
    end
  end

  defp list_opts(params) do
    with {:ok, from} <- date_param(params, "from", :from),
         {:ok, to} <- date_param(params, "to", :to),
         {:ok, portfolio_id} <- int_param(params, "portfolio_id", :portfolio_id),
         {:ok, security_id} <- int_param(params, "security_id", :security_id),
         {:ok, securities_account_id} <-
           int_param(params, "securities_account_id", :securities_account_id) do
      opts =
        []
        |> put_present(:from, from)
        |> put_present(:to, to)
        |> put_present(:portfolio_id, portfolio_id)
        |> put_present(:security_id, security_id)
        |> put_present(:securities_account_id, securities_account_id)

      {:ok, opts}
    end
  end

  defp date_param(params, key, field) do
    case Map.get(params, key) do
      value when value in [nil, ""] ->
        {:ok, nil}

      value when is_binary(value) ->
        case Date.from_iso8601(value) do
          {:ok, date} -> {:ok, date}
          _ -> {:error, field}
        end

      _ ->
        {:error, field}
    end
  end

  defp int_param(params, key, field) do
    case Map.get(params, key) do
      value when value in [nil, ""] ->
        {:ok, nil}

      value when is_integer(value) and value > 0 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} when int > 0 -> {:ok, int}
          _ -> {:error, field}
        end

      _ ->
        {:error, field}
    end
  end

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.put(opts, key, value)

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
    |> json(%{errors: %{detail: "transaction is referenced by existing records"}})
  end
end
