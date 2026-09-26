defmodule PortfolixirWeb.Api.V1.QuoteController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.QuoteSync
  alias PortfolixirWeb.Api.V1.DateParam
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ListLimit
  alias PortfolixirWeb.Api.V1.MergedAway

  def index(conn, %{"security_id" => security_id} = params) do
    with {:ok, id} <- IdParam.parse(security_id),
         security when not is_nil(security) <- Catalog.get_security(id),
         {:ok, from} <- parse_date(params, "from", ~D[0001-01-01], :from),
         {:ok, to} <- parse_date(params, "to", ~D[9999-12-31], :to),
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
      :error -> MergedAway.not_found(conn, :security, security_id)
      nil -> MergedAway.not_found(conn, :security, security_id)
      {:invalid_param, field} -> validation_error(conn, field)
    end
  end

  # An authored write (E25 S6, T-9): every row is stored as manual whatever
  # source it names (F20), journaled under the token with the rows it
  # replaced, and the answer names the dates it replaced (G27).
  def upsert(conn, %{"security_id" => security_id} = params) do
    rows = Map.get(params, "quotes", [])

    with {:ok, id} <- IdParam.parse(security_id),
         security when not is_nil(security) <- Catalog.get_security(id),
         true <- is_list(rows),
         :ok <- within_upsert_cap(rows),
         {:ok, %{upserted: count, replaced: replaced}} <-
           Catalog.upsert_quotes(conn.assigns.actor, id, rows) do
      json(conn, %{data: %{upserted: count, replaced: Enum.map(replaced, &Date.to_iso8601/1)}})
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
        MergedAway.not_found(conn, :security, security_id)

      nil ->
        MergedAway.not_found(conn, :security, security_id)

      {:error, :not_found} ->
        MergedAway.not_found(conn, :security, security_id)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: JSON.errors(changeset)})
    end
  end

  @doc """
  Releases the security's manual rows dated `from` through `to` (both
  required, inclusive) back to provider data (E25 S6, T-9): the rows are
  removed, journaled with their closes as the before-image, so the next quote
  sync stores the provider's close for those dates. Provider rows stay.
  Agent-first: the security page's control lands no later than Sprint 17.
  """
  def release(conn, %{"security_id" => security_id} = params) do
    with {:ok, id} <- IdParam.parse(security_id),
         security when not is_nil(security) <- Catalog.get_security(id),
         {:ok, from} <- required_date(params, "from", :from),
         {:ok, to} <- required_date(params, "to", :to),
         {:ok, %{released: released}} <-
           Catalog.release_manual_quotes(conn.assigns.actor, id, from, to) do
      json(conn, %{
        data: %{
          security_id: id,
          from: Date.to_iso8601(from),
          to: Date.to_iso8601(to),
          released: Enum.map(released, &Date.to_iso8601/1)
        }
      })
    else
      :error -> MergedAway.not_found(conn, :security, security_id)
      nil -> MergedAway.not_found(conn, :security, security_id)
      {:error, :not_found} -> MergedAway.not_found(conn, :security, security_id)
      {:invalid_param, field} -> validation_error(conn, field)
      {:missing_param, field} -> field_error(conn, field, "can't be blank")
      {:error, :invalid_range} -> field_error(conn, :to, "must be on or after from")
    end
  end

  defp required_date(params, key, field) do
    case DateParam.parse(params, key) do
      {:ok, %Date{} = date} -> {:ok, date}
      {:ok, nil} -> {:missing_param, field}
      :error -> {:invalid_param, field}
    end
  end

  defp field_error(conn, field, message) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{field => [message]}})
  end

  def sync(conn, %{"security_id" => security_id}) do
    with {:ok, id} <- IdParam.parse(security_id),
         security when not is_nil(security) <- Catalog.get_security(id) do
      case QuoteSync.sync_security(security) do
        # Single-flight (E25, G04): one sync of a security at a time.
        %{reason: :sync_in_progress} ->
          conn
          |> put_status(:conflict)
          |> json(%{errors: %{detail: "a quote sync for this security is already running"}})

        result ->
          json(conn, %{data: sync_result(result)})
      end
    else
      :error -> MergedAway.not_found(conn, :security, security_id)
      nil -> MergedAway.not_found(conn, :security, security_id)
    end
  end

  # The bounded date every writer meets (DateParam, F70 review round); an
  # absent bound reads the whole stored history.
  defp parse_date(params, key, default, field) do
    case DateParam.parse(params, key) do
      {:ok, nil} -> {:ok, default}
      {:ok, date} -> {:ok, date}
      :error -> {:invalid_param, field}
    end
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
