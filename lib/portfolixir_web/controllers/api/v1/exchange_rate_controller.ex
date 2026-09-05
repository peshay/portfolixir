defmodule PortfolixirWeb.Api.V1.ExchangeRateController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Fx
  alias Portfolixir.Fx.RateSync
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ListLimit

  require Logger

  # #771: sized above a realistic rate table, a bound rather than a page.
  @default_limit 50_000
  @max_limit 200_000

  def index(conn, params) do
    case ListLimit.parse(params, @default_limit, @max_limit) do
      {:ok, limit} ->
        json(conn, %{data: Enum.map(Fx.list_rates(limit: limit), &JSON.exchange_rate/1)})

      {:error, :limit} ->
        unprocessable(conn, %{limit: ["is invalid"]})
    end
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

  # A fixed message (#770): the provider's error term is logged, not echoed.
  defp respond(conn, {:error, reason}) do
    Logger.warning("exchange-rate sync failed: #{inspect(reason)}")

    conn
    |> put_status(:bad_gateway)
    |> json(%{errors: %{detail: "the rate provider could not be reached"}})
  end

  defp unprocessable(conn, errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end
end
