defmodule PortfolixirWeb.Api.V1.SecurityMetricsController do
  @moduledoc """
  The per-security derived metrics read (FR-39, ADR-0047 §9).

  One security's moving averages, realized volatility, maximum drawdown,
  momentum and distance to the 52-week extremes, over its own split-adjusted
  close series. Mirrored by the `portfolixir.securities.metrics` MCP tool
  (API/MCP parity, FR-16/AR-11).

  Level (a) of the scope ladder **reports**; it does not evaluate. The payload
  carries no signal, recommendation, rating, score or action, and that boundary
  is mechanical rather than remembered — `test/invariants/metrics_carry_no_verdict_test.exs`
  walks the rendered keys (ADR-0047 §7, identity I6).
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Catalog.SecurityMetrics
  alias PortfolixirWeb.Api.V1.JSON

  def show(conn, %{"security_id" => security_id} = params) do
    with {:ok, as_of} <- as_of_param(params),
         {:ok, payload} <- SecurityMetrics.for_security(security_id, as_of_opts(as_of)) do
      json(conn, %{data: JSON.security_metrics(payload)})
    else
      {:error, :not_found} -> not_found(conn)
      {:error, field} -> unprocessable(conn, %{field => ["is invalid"]})
    end
  end

  # Absent means "today" — resolved inside the context through
  # `Portfolixir.Clock.today/0`, because "how has this priced lately" is a
  # local calendar question and the domain must not read the host clock (#609).
  defp as_of_opts(nil), do: []
  defp as_of_opts(%Date{} = as_of), do: [as_of: as_of]

  defp as_of_param(params) do
    case Map.get(params, "as_of") do
      value when value in [nil, ""] ->
        {:ok, nil}

      value when is_binary(value) ->
        case Date.from_iso8601(value) do
          {:ok, date} -> {:ok, date}
          _ -> {:error, :as_of}
        end

      _ ->
        {:error, :as_of}
    end
  end

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
end
