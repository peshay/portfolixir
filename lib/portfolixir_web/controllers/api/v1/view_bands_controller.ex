defmodule PortfolixirWeb.Api.V1.ViewBandsController do
  @moduledoc """
  JSON API for the stacked value chart's bands of a bucket view across all
  portfolios (I23, FR-53): the deduplicated account scope the view
  performance walks, so the bands add up to that read's series.
  `?period=`/`?year=`/`?from=`/`?to=` and the bands parameters behave like
  the portfolio bands read. `?base_currency=` (a supported code, default
  EUR) is the currency the walk converts into through the EUR hub, so an
  agent reads the figures the screen shows in its own base currency (the
  closing act's money lens, M1).

  `total/2` serves the same read with no view: `GET
  /api/v1/performance/bands`, every account of every portfolio, with
  `portfolio_id` and `view_id` null and no view echo (as #1056 serves the
  rest of the family).
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.View
  alias Portfolixir.Portfolios.Performance.Bands
  alias PortfolixirWeb.Api.V1.BandsParam
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

  # `view` nil is the Everything scope.
  defp read(conn, view, params) do
    with {:ok, period} <- PeriodParam.resolve(params),
         {:ok, bands_opts} <- BandsParam.resolve(params),
         {:ok, base} <- BandsParam.base_currency(params),
         {:ok, result} <-
           Bands.for_view(
             ViewParam.id(view),
             [period: period, base_currency: base] ++ bands_opts
           ) do
      data = result |> JSON.bands() |> ViewParam.put_active(view)
      json(conn, %{data: data})
    else
      # The view vanished between the lookup and the walk (TOCTOU): a plain
      # 404, never a 500.
      {:error, :view_not_found} ->
        not_found(conn)

      {:error, %{} = errors} ->
        unprocessable(conn, errors)

      {:error, reason} ->
        unprocessable(conn, BandsParam.errors(reason))
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
