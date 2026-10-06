defmodule PortfolixirWeb.Api.V1.ViewBenchmarkController do
  @moduledoc """
  JSON API for the benchmark comparison of a bucket view across all
  portfolios (ADR-0046 §3–4): the same deduplicated account scope the view
  valuation and the view performance cover, so the view's total, its
  return and its benchmark speak about the same accounts. `?benchmark=`,
  `?period=`/`?year=`/`?from=`/`?to=` and `?series=` behave like the
  portfolio benchmark read.

  `total/2` serves the same read with no view (#1056, Sprint 19 plan D-7):
  `GET /api/v1/performance/benchmark`, the comparison over the Everything
  walk, every account in EUR, with `view_id` null and no view echo.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.View
  alias Portfolixir.Portfolios.Performance.Benchmark
  alias PortfolixirWeb.Api.V1.BenchmarkParam
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.PeriodParam
  alias PortfolixirWeb.Api.V1.ViewParam

  def show(conn, %{"view_id" => view_id} = params) do
    with {:ok, vid} <- IdParam.parse(view_id),
         %View{} = view <- Buckets.get_view(vid) do
      read(conn, view, params)
    else
      _ -> not_found(conn)
    end
  end

  def total(conn, params), do: read(conn, nil, params)

  # `view` nil is the Everything scope (#1056).
  defp read(conn, view, params) do
    include_series? = Map.get(params, "series") in ["true", "1"]

    with {:ok, period} <- PeriodParam.resolve(params),
         {:ok, benchmark} <- BenchmarkParam.resolve(params),
         {:ok, result} <- Benchmark.for_view(ViewParam.id(view), benchmark, period: period) do
      data =
        result
        |> JSON.view_benchmark_comparison(include_series?)
        |> ViewParam.put_active(view)

      json(conn, %{data: data})
    else
      {:error, :invalid_period} -> unprocessable(conn, %{period: ["is invalid"]})
      {:error, :invalid_benchmark} -> unprocessable(conn, %{benchmark: ["is invalid"]})
      # A refused benchmark= carries its own errors object (#959).
      {:error, {:benchmark, errors}} -> unprocessable(conn, errors)
      {:error, :view_not_found} -> not_found(conn)
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
