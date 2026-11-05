defmodule PortfolixirWeb.Api.V1.SaleHindsightController do
  @moduledoc """
  `GET /api/v1/sales/hindsight` (I18 modes 1 and 2; the Sprint 25 plan's
  D-3): what each sale missed, one row per sale booking over four spans
  after the sale, computed by `Portfolixir.Portfolios.Performance.SaleHindsight`.

  Optional filters: `portfolio_id`, `security_id`, `from` and `to` (the sale
  date, inclusive, the bounded dates every read takes), `limit` (default
  100, at most 500) and `benchmark=` (ADR-0046's `rate:<decimal>` or
  `security:<id>`, read by `PortfolixirWeb.Api.V1.BenchmarkParam`
  unchanged, so a security must be flagged `is_benchmark`). Absent or blank,
  `benchmark` compares nothing. A malformed value answers 422 naming it; `to`
  before `from` answers 422 on `to`. Read-only; financial decimals are
  strings.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios.Performance.SaleHindsight
  alias PortfolixirWeb.Api.V1.BenchmarkParam
  alias PortfolixirWeb.Api.V1.DateParam
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ListLimit

  # #771: a bound, not a page. Each row measures up to nine windows from
  # stored closes, so the cap sits below the cheaper roll-ups' 1,000.
  @default_limit 100
  @max_limit 500

  def index(conn, params) do
    with {:ok, portfolio_id} <- id_filter(params, "portfolio_id", :portfolio_id),
         {:ok, security_id} <- id_filter(params, "security_id", :security_id),
         {:ok, from} <- date_param(params, "from", :from),
         {:ok, to} <- date_param(params, "to", :to),
         :ok <- ordered(from, to),
         {:ok, limit} <- ListLimit.parse(params, @default_limit, @max_limit),
         {:ok, benchmark} <- benchmark(params) do
      report =
        SaleHindsight.report(
          benchmark: benchmark,
          portfolio_id: portfolio_id,
          security_id: security_id,
          from: from,
          to: to,
          limit: limit
        )

      json(conn, %{data: JSON.sale_hindsight(report)})
    else
      # A refused benchmark= carries its own errors object (#959).
      {:error, {:benchmark, errors}} -> unprocessable(conn, errors)
      {:error, :invalid_range} -> unprocessable(conn, %{to: ["must be on or after from"]})
      {:error, field} -> unprocessable(conn, %{field => ["is invalid"]})
    end
  end

  # The comparison is optional here (D-3): absent or blank compares nothing;
  # any other value is BenchmarkParam's, refusals included.
  defp benchmark(params) do
    case Map.get(params, "benchmark") do
      value when value in [nil, ""] -> {:ok, nil}
      _value -> BenchmarkParam.resolve(params)
    end
  end

  defp ordered(%Date{} = from, %Date{} = to) do
    if Date.compare(to, from) == :lt, do: {:error, :invalid_range}, else: :ok
  end

  defp ordered(_from, _to), do: :ok

  # The bounded date every writer meets (DateParam, F70 review round).
  defp date_param(params, key, field) do
    case DateParam.parse(params, key) do
      {:ok, date} -> {:ok, date}
      :error -> {:error, field}
    end
  end

  defp id_filter(params, key, field) do
    case Map.get(params, key) do
      value when value in [nil, ""] ->
        {:ok, nil}

      value ->
        case IdParam.parse(value) do
          {:ok, id} -> {:ok, id}
          :error -> {:error, field}
        end
    end
  end

  defp unprocessable(conn, errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end
end
