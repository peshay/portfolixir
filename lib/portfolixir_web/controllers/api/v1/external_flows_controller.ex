defmodule PortfolixirWeb.Api.V1.ExternalFlowsController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios.ExternalFlows
  alias PortfolixirWeb.Api.V1.JSON

  # Issue #725: the deposits-and-withdrawals roll-up, global like the
  # sibling realized-gains read. Basis (and the stated invested-capital
  # difference) travels in the payload.
  def index(conn, _params) do
    json(conn, %{data: JSON.external_flows(ExternalFlows.report())})
  end
end
