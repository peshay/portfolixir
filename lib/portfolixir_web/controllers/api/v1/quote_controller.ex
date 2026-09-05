defmodule PortfolixirWeb.Api.V1.QuoteController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.QuoteSync
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ListLimit

  def index(conn, %{"security_id" => security_id} = params) do
    with {:ok, id} <- parse_id(security_id),
         security when not is_nil(security) <- Catalog.get_security(id),
         {:ok, from} <- parse_date(Map.get(params, "from"), ~D[0001-01-01], :from),
         {:ok, to} <- parse_date(Map.get(params, "to"), ~D[9999-12-31], :to),
         {:ok, limit} <- limit_param(params) do
      # Stored rows plus their display-basis adjustment (ADR-0028 §2),
      # derived from ONE fetch: computing the adjusted view from the same
      # loaded list keeps the zip aligned even when a concurrent upsert
      # lands between reads (E17 review, finding 6).
      stored = Quotes.range(id, from, to, limit: limit)
      adjusted = Quotes.adjust_rows(stored, security)
      quotes = Enum.zip_with(stored, adjusted, &JSON.quote/2)

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
         :ok <- within_upsert_cap(rows),
         {:ok, count} <- Quotes.upsert_many(id, rows) do
      json(conn, %{data: %{upserted: count}})
    else
      false ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{quotes: ["must be a list"]}})

      {:too_many_rows, max} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{quotes: ["at most #{max} rows per request"]}})

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

  # #771: sized above a security's whole daily history, a bound rather than a page.
  @default_limit 20_000
  @max_limit 50_000

  defp limit_param(params) do
    case ListLimit.parse(params, @default_limit, @max_limit) do
      {:ok, limit} -> {:ok, limit}
      {:error, :limit} -> {:invalid_param, :limit}
    end
  end

  defp within_upsert_cap(rows) do
    max = ListLimit.quote_upsert_max_rows()
    if length(rows) > max, do: {:too_many_rows, max}, else: :ok
  end

  defp validation_error(conn, field) when field in [:from, :to, :limit] do
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
  # A fixed word (#770): the adapter's error term is not echoed to the caller.
  defp reason_to_string(_reason), do: "provider_error"
end
