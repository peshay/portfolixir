defmodule PortfolixirWeb.Api.V1.IsinChangeController do
  @moduledoc """
  Records corporate-action ISIN changes and manages the resulting identifier
  aliases (ADR-0029 §3, AR-11 parity with the MCP companion).

  `POST /api/v1/securities/:security_id/isin-change` moves the current ISIN
  into a journaled alias and writes the new ISIN; the §3 guards (A->A,
  live-ISIN collision, foreign-alias collision, B->A alias consumption) run
  inside the journaled transaction and surface as 422 errors naming the
  conflicting security.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Catalog
  alias PortfolixirWeb.Api.V1.JSON

  def create(conn, %{"security_id" => id} = params) do
    attrs = Map.get(params, "isin_change", %{})

    case Catalog.get_security(id) do
      nil -> not_found(conn)
      security -> record_change(conn, security, attrs)
    end
  end

  defp record_change(conn, security, attrs) when is_map(attrs) do
    opts = [changed_on: Map.get(attrs, "changed_on"), note: Map.get(attrs, "note")]

    case Catalog.record_isin_change(conn.assigns.actor, security, attrs["new_isin"], opts) do
      {:ok, %{security: updated}} ->
        json(conn, %{data: JSON.security(Catalog.with_identifier_aliases(updated))})

      {:error, changeset} ->
        validation_error(conn, changeset)
    end
  end

  defp record_change(conn, _security, _attrs) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{isin_change: ["is invalid"]}})
  end

  def delete_alias(conn, %{"security_id" => security_id, "id" => id}) do
    with {:ok, security_id} <- parse_id(security_id),
         {:ok, alias_id} <- parse_id(id),
         alias_row when not is_nil(alias_row) <-
           Catalog.get_identifier_alias(security_id, alias_id),
         {:ok, _deleted} <- Catalog.delete_identifier_alias(conn.assigns.actor, alias_row) do
      send_resp(conn, :no_content, "")
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
      {:error, changeset} -> validation_error(conn, changeset)
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

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end

  defp validation_error(conn, changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: JSON.errors(changeset)})
  end
end
