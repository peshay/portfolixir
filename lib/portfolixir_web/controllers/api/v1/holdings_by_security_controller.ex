defmodule PortfolixirWeb.Api.V1.HoldingsBySecurityController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios.Valuation
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, _params) do
    json(conn, %{data: JSON.holdings_by_security(Valuation.holdings_by_security_report())})
  end
end
