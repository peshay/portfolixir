defmodule PortfolixirWeb.Api.V1.ContributionController do
  @moduledoc """
  JSON API for the contribution analysis of one portfolio (FR-41, ADR-0051
  §6 and §11): which position made how much of a period's money result,
  with the three remainder lines and the totals, summing exactly to the
  performance read's `end_value − start_value − net_external_flows`.
  `?period=`, `?year=`, `?from=`/`?to=` and `?view=` behave like the
  performance read, and the errors are its errors. Financial decimals are
  serialized as strings.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance.Contribution
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.PeriodParam
  alias PortfolixirWeb.Api.V1.ViewParam

  def index(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, id} <- IdParam.parse(portfolio_id),
         portfolio when not is_nil(portfolio) <- Portfolios.get_portfolio(id),
         {:ok, view} <- ViewParam.resolve(params),
         {:ok, period} <- PeriodParam.resolve(params) do
      opts = Keyword.put(ViewParam.opts(view), :period, period)

      case Contribution.for_portfolio(id, opts) do
        {:ok, result} ->
          data = result |> JSON.contribution() |> ViewParam.put_active(view)
          json(conn, %{data: data})

        {:error, :invalid_period} ->
          unprocessable(conn, %{period: ["is invalid"]})

        # The view vanished between resolve and read (TOCTOU): a plain 404.
        {:error, :view_not_found} ->
          not_found(conn)
      end
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
      {:error, :view} -> unprocessable(conn, %{view: ["is invalid"]})
      {:error, :invalid_period} -> unprocessable(conn, %{period: ["is invalid"]})
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
