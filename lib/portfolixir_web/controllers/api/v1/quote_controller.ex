defmodule PortfolixirWeb.Api.V1.QuoteController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.QuoteSync
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, %{"security_id" => security_id} = params) do
    with {:ok, id} <- parse_id(security_id),
         security when not is_nil(security) <- Catalog.get_security(id),
         {:ok, from} <- parse_date(Map.get(params, "from"), ~D[0001-01-01], :from),
         {:ok, to} <- parse_date(Map.get(params, "to"), ~D[9999-12-31], :to) do
      quotes =
        id
        |> Quotes.range(from, to)
        |> Enum.map(&JSON.quote/1)

      json(conn, %{data: quotes})
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
      {:invalid_param, field} -> validation_error(conn, field)
    end
  end

  def upsert(conn, %{"security_id" => security_id} = params) do
    rows = Map.get(params, "quotes", [])

    with {:ok, id} <- parse_id(security_id),
         security when not is_nil(security) <- Catalog.get_security(id),
         true <- is_list(rows),
         {:ok, count} <- Quotes.upsert_many(id, rows) do
      json(conn, %{data: %{upserted: count}})
    else
      false ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{quotes: ["must be a list"]}})

      :error ->
        not_found(conn)

      nil ->
        not_found(conn)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: JSON.errors(changeset)})
    end
  end

  def sync(conn, %{"security_id" => security_id}) do
    with {:ok, id} <- parse_id(security_id),
         security when not is_nil(security) <- Catalog.get_security(id) do
      result = QuoteSync.sync_security(security)
      json(conn, %{data: sync_result(result)})
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
    end
  end

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_date(nil, default, _field), do: {:ok, default}

  defp parse_date(value, _default, field) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:invalid_param, field}
    end
  end

  defp parse_date(_value, _default, field), do: {:invalid_param, field}

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end

  defp validation_error(conn, field) when field in [:from, :to] do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{field => ["is invalid"]}})
  end

  defp sync_result(%{status: status, reason: nil}) do
    %{status: Atom.to_string(status)}
  end

  defp sync_result(%{status: status, reason: reason}) do
    %{status: Atom.to_string(status), reason: reason_to_string(reason)}
  end

  defp reason_to_string(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_to_string(reason), do: inspect(reason)
end
