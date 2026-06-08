defmodule PortfolixirWeb.Api.V1.TradeController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, %{"security_id" => security_id} = params) do
    with {:ok, from} <- date_param(params, "from", :from),
         {:ok, to} <- date_param(params, "to", :to),
         {:ok, id} <- parse_id(security_id),
         security when not is_nil(security) <- Catalog.get_security(id) do
      trades =
        security.id
        |> Ledger.list_trades_for_security()
        |> filter_trades(from, to)

      json(conn, %{data: JSON.trades(trades)})
    else
      {:error, field} -> unprocessable(conn, field)
      :error -> not_found(conn)
      nil -> not_found(conn)
    end
  end

  # Optional date-range filter, applied to each leg by its own date: open lots by
  # open date, closed round-trips by close date, orphan sells by sell date.
  defp filter_trades(trades, nil, nil), do: trades

  defp filter_trades(trades, from, to) do
    %{
      trades
      | open_lots: Enum.filter(trades.open_lots, &in_range?(&1.open_date, from, to)),
        closed_trades: Enum.filter(trades.closed_trades, &in_range?(&1.close_date, from, to)),
        orphan_sells: Enum.filter(trades.orphan_sells, &in_range?(&1.date, from, to))
    }
  end

  defp in_range?(%Date{} = date, from, to) do
    (is_nil(from) or Date.compare(date, from) != :lt) and
      (is_nil(to) or Date.compare(date, to) != :gt)
  end

  defp in_range?(_date, _from, _to), do: true

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

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_id(value) when is_integer(value), do: {:ok, value}
  defp parse_id(_), do: :error

  defp unprocessable(conn, field) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{field => ["is invalid"]}})
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end
end
