defmodule PortfolixirWeb.Api.V1.ExternalFlowsController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios.ExternalFlows
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ListLimit

  # #776: the bound of a roll-up is a number of years of its annual matrix,
  # newest first; the payload's computation_basis names a cut when one
  # happened. Sized above any real ledger so a routine read never sees it.
  @default_limit 100
  @max_limit 1_000

  # Issue #725: the deposits-and-withdrawals roll-up, global like the
  # sibling realized-gains read. Basis (and the stated invested-capital
  # difference) travels in the payload.
  def index(conn, params) do
    case ListLimit.parse(params, @default_limit, @max_limit) do
      {:ok, limit} ->
        json(conn, %{data: JSON.external_flows(ExternalFlows.report(limit: limit))})

      {:error, :limit} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{limit: ["is invalid"]}})
    end
  end
end
