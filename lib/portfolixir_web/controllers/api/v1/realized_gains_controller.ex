defmodule PortfolixirWeb.Api.V1.RealizedGainsController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios.RealizedGains
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ListLimit

  # #776: the bound of a roll-up is a number of years of its annual matrix,
  # newest first; the payload's computation_basis names a cut when one
  # happened. Sized above any real ledger so a routine read never sees it.
  @default_limit 100
  @max_limit 1_000

  # Issue #724: the realized-gains roll-up, cross-security and
  # cross-portfolio (FIFO trades match per security across portfolios), so
  # the route is global like /holdings/by_security. The FX basis (D-1)
  # travels in the payload.
  def index(conn, params) do
    case ListLimit.parse(params, @default_limit, @max_limit) do
      {:ok, limit} ->
        json(conn, %{data: JSON.realized_gains(RealizedGains.report(limit: limit))})

      {:error, :limit} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{limit: ["is invalid"]}})
    end
  end
end
