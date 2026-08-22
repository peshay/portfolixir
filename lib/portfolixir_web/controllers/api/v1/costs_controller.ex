defmodule PortfolixirWeb.Api.V1.CostsController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios.Costs
  alias PortfolixirWeb.Api.V1.JSON

  # Issue #726: the fees-and-taxes roll-up at overview level, global like
  # the sibling cash-flow reads. The legs-not-gross series rule travels in
  # the payload's computation basis.
  def index(conn, _params) do
    json(conn, %{data: JSON.costs(Costs.report())})
  end
end
