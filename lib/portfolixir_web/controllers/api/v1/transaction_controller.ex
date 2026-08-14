defmodule PortfolixirWeb.Api.V1.TransactionController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias PortfolixirWeb.Api.V1.FieldSelection
  alias PortfolixirWeb.Api.V1.JSON

  # FR-37 (#665): sparse fieldsets over the serializer's own field list.
  @fields_whitelist FieldSelection.whitelist(JSON.transaction_fields())

  def index(conn, params) do
    with {:ok, opts} <- list_opts(params),
         {:ok, fields} <- FieldSelection.parse(params, @fields_whitelist) do
      rows =
        Ledger.list_transactions(opts)
        |> Enum.map(fn transaction ->
          transaction |> JSON.transaction() |> FieldSelection.take(fields)
        end)

      json(conn, %{data: rows})
    else
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

  # A `split` (ADR-0028) must be booked through the dedicated per-portfolio
  # fan-out flow (§1) — never as a single generic transaction row — and its
  # quote/price-basis adjustment engine (§2, issue #590) is not in yet, so a
  # split booked through the generic endpoint would produce a phantom
  # valuation/TTWROR spike. Reject it at this public boundary, before any
  # write. The domain `Ledger.create_transaction/2` stays permissive so the
  # fan-out shell (later slice) and the fold tests can create splits through it.
  @split_rejection %{
    type: [
      "split transactions are booked via the dedicated split flow, not the generic transaction endpoint"
    ]
  }

  def create(conn, params) do
    attrs = Map.get(params, "transaction", %{})

    if split?(attrs) do
      unprocessable(conn, @split_rejection)
    else
      case Ledger.create_transaction(conn.assigns.actor, attrs) do
        {:ok, transaction} ->
          conn
          |> put_status(:created)
          |> json(%{data: JSON.transaction(transaction)})

        {:error, changeset} ->
          unprocessable(conn, JSON.errors(changeset))
      end
    end
  end

  def update(conn, %{"id" => id} = params) do
    attrs = Map.get(params, "transaction", %{})

    if split?(attrs) do
      unprocessable(conn, @split_rejection)
    else
      with {:ok, tid} <- parse_id(id),
           %Transaction{} = transaction <- Ledger.get_transaction(tid),
           {:ok, updated} <- Ledger.update_transaction(conn.assigns.actor, transaction, attrs) do
        json(conn, %{data: JSON.transaction(updated)})
      else
        nil -> not_found(conn)
        :error -> not_found(conn)
        {:error, changeset} -> unprocessable(conn, JSON.errors(changeset))
      end
    end
  end

  defp split?(attrs) when is_map(attrs) do
    Map.get(attrs, "type") == "split" or Map.get(attrs, :type) == "split"
  end

  defp split?(_attrs), do: false

  def delete(conn, %{"id" => id}) do
    with {:ok, tid} <- parse_id(id),
         %Transaction{} = transaction <- Ledger.get_transaction(tid),
         {:ok, _} <- Ledger.delete_transaction(conn.assigns.actor, transaction) do
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
