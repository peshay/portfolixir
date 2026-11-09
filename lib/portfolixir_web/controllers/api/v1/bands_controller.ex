defmodule PortfolixirWeb.Api.V1.BandsController do
  @moduledoc """
  JSON API for the stacked value chart's bands of one portfolio (I23,
  FR-53): the performance read's value series split into bands by `level`
  (`total`, `category`, `security`), each band's daily values summing
  exactly to the series. `?period=`, `?year=`, `?from=`/`?to=` and `?view=`
  behave like the performance read; `level`, `sort`, `classification_id`
  and `category_id` are read strictly (`BandsParam`), a wrong one a 422
  naming it. `category_id` (an id or `unclassified`) filters every level to
  one category's subtree (FR-56); without `level` the read answers
  `category`, as it always has. Financial decimals are serialized as
  strings.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance.Bands
  alias PortfolixirWeb.Api.V1.BandsParam
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.PeriodParam
  alias PortfolixirWeb.Api.V1.ViewParam

  def index(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, id} <- IdParam.parse(portfolio_id),
         portfolio when not is_nil(portfolio) <- Portfolios.get_portfolio(id),
         {:ok, view} <- ViewParam.resolve(params),
         {:ok, period} <- PeriodParam.resolve(params),
         {:ok, bands_opts} <- BandsParam.resolve(params) do
      opts = ViewParam.opts(view) ++ [period: period] ++ bands_opts

      case Bands.for_portfolio(id, opts) do
        {:ok, result} ->
          data = result |> JSON.bands() |> ViewParam.put_active(view)
          json(conn, %{data: data})

        # The view vanished between resolve and read (TOCTOU): a plain 404.
        {:error, :view_not_found} ->
          not_found(conn)

        {:error, reason} ->
          unprocessable(conn, BandsParam.errors(reason))
      end
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
      {:error, :view} -> unprocessable(conn, %{view: ["is invalid"]})
      {:error, :invalid_period} -> unprocessable(conn, %{period: ["is invalid"]})
      {:error, %{} = errors} -> unprocessable(conn, errors)
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
