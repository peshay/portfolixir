defmodule PortfolixirWeb.Api.V1.ExchangeRateController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Fx
  alias Portfolixir.Fx.RateSync
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, _params) do
    json(conn, %{data: Enum.map(Fx.list_rates(), &JSON.exchange_rate/1)})
  end

  # `scope` (issue #737, Sprint 9 D-1): `latest` (default) runs the daily
  # sync; `history` runs the one-shot backfill of the provider's historical
  # series through the same upsert path, so past booking dates gain their
  # rate. Anything else is a 422.
  def sync(conn, params) do
    case Map.get(params, "scope", "latest") do
      value when value in ["latest", ""] -> respond(conn, RateSync.sync())
      "history" -> respond(conn, RateSync.backfill())
      _other -> unprocessable(conn, %{scope: ["is invalid"]})
    end
  end

  defp respond(conn, {:ok, result}), do: json(conn, %{data: JSON.fx_sync_result(result)})

  defp respond(conn, {:error, :history_unsupported}),
    do: unprocessable(conn, %{scope: ["the configured provider publishes no history"]})

  defp respond(conn, {:error, reason}) do
    conn
    |> put_status(:bad_gateway)
    |> json(%{errors: %{detail: inspect(reason)}})
  end

  defp unprocessable(conn, errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end
end
