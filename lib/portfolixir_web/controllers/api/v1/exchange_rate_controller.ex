defmodule PortfolixirWeb.Api.V1.ExchangeRateController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Fx
  alias Portfolixir.Fx.RateSync
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, _params) do
    json(conn, %{data: Enum.map(Fx.list_rates(), &JSON.exchange_rate/1)})
  end

  def sync(conn, _params) do
    case RateSync.sync() do
      {:ok, result} ->
        json(conn, %{data: JSON.fx_sync_result(result)})

      {:error, reason} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{errors: %{detail: inspect(reason)}})
    end
  end
end
