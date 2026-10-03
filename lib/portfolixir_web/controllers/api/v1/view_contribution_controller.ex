defmodule PortfolixirWeb.Api.V1.ViewContributionController do
  @moduledoc """
  JSON API for the contribution analysis of a bucket view across all
  portfolios (FR-41, ADR-0051 §6): the deduplicated account scope the view
  valuation and the view performance cover, in EUR, so the view's total, its
  return and its contribution table speak about the same accounts.
  `?period=`/`?year=`/`?from=`/`?to=` behave like the portfolio contribution
  read.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.View
  alias Portfolixir.Portfolios.Performance.Contribution
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.PeriodParam
  alias PortfolixirWeb.Api.V1.ViewParam

  def show(conn, %{"view_id" => view_id} = params) do
    with {:ok, vid} <- IdParam.parse(view_id),
         %View{} = view <- Buckets.get_view(vid) do
      with {:ok, period} <- PeriodParam.resolve(params),
           {:ok, result} <- Contribution.for_view(view.id, period: period) do
        data = result |> JSON.contribution() |> ViewParam.put_active(view)
        json(conn, %{data: data})
      else
        # An unknown period string, a malformed year, or a backwards range
        # share the 422 contract.
        {:error, :invalid_period} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: %{period: ["is invalid"]}})

        # The view vanished between the lookup and the walk (TOCTOU): a plain
        # 404, never a 500.
        {:error, :view_not_found} ->
          not_found(conn)
      end
    else
      _ -> not_found(conn)
    end
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end
end
