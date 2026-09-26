defmodule PortfolixirWeb.Api.V1.IsinChangeController do
  @moduledoc """
  Records corporate-action ISIN changes and manages the resulting identifier
  aliases (ADR-0029 §3, AR-11 parity with the MCP companion).

  `POST /api/v1/securities/:security_id/isin-change` moves the current ISIN
  into a journaled alias and writes the new ISIN; the §3 guards (A->A,
  live-ISIN collision, foreign-alias collision, B->A alias consumption) run
  inside the journaled transaction and surface as 422 errors naming the
  conflicting security.

  A security id a merge took away answers 404 with `errors.merged_into`
  naming the survivor (ADR-0050 §12, `PortfolixirWeb.Api.V1.MergedAway`), on
  both routes.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Catalog
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.MergedAway

  def create(conn, %{"security_id" => id} = params) do
    attrs = Map.get(params, "isin_change", %{})

    case Catalog.get_security(id) do
      nil -> MergedAway.not_found(conn, :security, id)
      security -> record_change(conn, security, attrs)
    end
  end

  defp record_change(conn, security, attrs) when is_map(attrs) do
    opts = [changed_on: Map.get(attrs, "changed_on"), note: Map.get(attrs, "note")]

    case Catalog.record_isin_change(conn.assigns.actor, security, attrs["new_isin"], opts) do
      {:ok, %{security: updated}} ->
        json(conn, %{data: JSON.security(Catalog.with_identifier_aliases(updated))})

      {:error, :not_found} ->
        MergedAway.not_found(conn, :security, security.id)

      {:error, changeset} ->
        validation_error(conn, changeset)
    end
  end

  defp record_change(conn, _security, _attrs) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{isin_change: ["is invalid"]}})
  end

  # An alias of a live security that is not found answers the plain 404; one
  # under a merged-away security names its survivor (the merge moved the
  # security's aliases there).
  def delete_alias(conn, %{"security_id" => raw_security_id, "id" => id}) do
    with {:ok, security_id} <- IdParam.parse(raw_security_id),
         {:ok, alias_id} <- IdParam.parse(id),
         alias_row when not is_nil(alias_row) <-
           Catalog.get_identifier_alias(security_id, alias_id),
         {:ok, _deleted} <- Catalog.delete_identifier_alias(conn.assigns.actor, alias_row) do
      send_resp(conn, :no_content, "")
    else
      nil -> MergedAway.not_found(conn, :security, raw_security_id)
      :error -> MergedAway.not_found(conn, :security, raw_security_id)
      {:error, :not_found} -> MergedAway.not_found(conn, :security, raw_security_id)
      {:error, changeset} -> validation_error(conn, changeset)
    end
  end

  defp validation_error(conn, changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: JSON.errors(changeset)})
  end
end
