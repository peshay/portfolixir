defmodule PortfolixirWeb.Api.V1.CostsController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios.Costs
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ListLimit

  # #776: the bound of a roll-up is a number of years of its annual matrix,
  # newest first; the payload's computation_basis names a cut when one
  # happened. Sized above any real ledger so a routine read never sees it.
  @default_limit 100
  @max_limit 1_000

  # Issue #726: the fees-and-taxes roll-up at overview level, global like
  # the sibling cash-flow reads. The legs-not-gross series rule travels in
  # the payload's computation basis.
  def index(conn, params) do
    case ListLimit.parse(params, @default_limit, @max_limit) do
      {:ok, limit} ->
        json(conn, %{data: JSON.costs(Costs.report(limit: limit))})

      {:error, :limit} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{limit: ["is invalid"]}})
    end
  end
end
