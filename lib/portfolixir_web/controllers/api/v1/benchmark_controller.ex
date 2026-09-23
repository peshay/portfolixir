defmodule PortfolixirWeb.Api.V1.BenchmarkController do
  @moduledoc """
  JSON API for the benchmark comparison of one portfolio (ADR-0046 §4,
  issue #572): the portfolio's own flows replayed into a benchmark, both
  comparisons in one read. `?benchmark=` is required (`rate:<decimal>` or
  `security:<id>`); `?period=`, `?year=`, `?from=`/`?to=`, `?view=` and
  `?series=` behave like the performance read. Financial decimals are
  serialized as strings.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance.Benchmark
  alias PortfolixirWeb.Api.V1.BenchmarkParam
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.PeriodParam
  alias PortfolixirWeb.Api.V1.ViewParam

  def index(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, id} <- IdParam.parse(portfolio_id),
         portfolio when not is_nil(portfolio) <- Portfolios.get_portfolio(id),
         {:ok, view} <- ViewParam.resolve(params),
         {:ok, period} <- PeriodParam.resolve(params),
         {:ok, benchmark} <- BenchmarkParam.resolve(params) do
      include_series? = Map.get(params, "series") in ["true", "1"]
      opts = Keyword.put(ViewParam.opts(view), :period, period)

      case Benchmark.for_portfolio(id, benchmark, opts) do
        {:ok, result} ->
          data =
            result
            |> JSON.benchmark_comparison(include_series?)
            |> ViewParam.put_active(view)

          json(conn, %{data: data})

        {:error, :invalid_period} ->
          unprocessable(conn, %{period: ["is invalid"]})

        {:error, :invalid_benchmark} ->
          unprocessable(conn, %{benchmark: ["is invalid"]})

        # The view vanished between resolve and read (TOCTOU): a plain 404.
        {:error, :view_not_found} ->
          not_found(conn)
      end
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
      {:error, :view} -> unprocessable(conn, %{view: ["is invalid"]})
      {:error, :invalid_period} -> unprocessable(conn, %{period: ["is invalid"]})
      {:error, {:benchmark, message}} -> unprocessable(conn, %{benchmark: [message]})
      :view_not_found -> not_found(conn)
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
