defmodule PortfolixirWeb.Api.V1.ViewBenchmarkController do
  @moduledoc """
  JSON API for the benchmark comparison of a bucket view across all
  portfolios (ADR-0046 §3–4): the same deduplicated account scope the view
  valuation and the view performance cover, so the view's total, its
  return and its benchmark speak about the same accounts. `?benchmark=`,
  `?period=`/`?year=`/`?from=`/`?to=` and `?series=` behave like the
  portfolio benchmark read.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.View
  alias Portfolixir.Portfolios.Performance.Benchmark
  alias PortfolixirWeb.Api.V1.BenchmarkParam
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.PeriodParam
  alias PortfolixirWeb.Api.V1.ViewParam

  def show(conn, %{"view_id" => view_id} = params) do
    with {:ok, vid} <- parse_id(view_id),
         %View{} = view <- Buckets.get_view(vid) do
      include_series? = Map.get(params, "series") in ["true", "1"]

      with {:ok, period} <- PeriodParam.resolve(params),
           {:ok, benchmark} <- BenchmarkParam.resolve(params),
           {:ok, result} <- Benchmark.for_view(view.id, benchmark, period: period) do
        data =
          result
          |> JSON.view_benchmark_comparison(include_series?)
          |> ViewParam.put_active(view)

        json(conn, %{data: data})
      else
        {:error, :invalid_period} -> unprocessable(conn, %{period: ["is invalid"]})
        {:error, :invalid_benchmark} -> unprocessable(conn, %{benchmark: ["is invalid"]})
        {:error, {:benchmark, message}} -> unprocessable(conn, %{benchmark: [message]})
        {:error, :view_not_found} -> not_found(conn)
      end
    else
      _ -> not_found(conn)
    end
  end

  defp unprocessable(conn, errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end

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
end
