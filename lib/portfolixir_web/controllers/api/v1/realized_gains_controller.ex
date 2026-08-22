defmodule PortfolixirWeb.Api.V1.RealizedGainsController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios.RealizedGains
  alias PortfolixirWeb.Api.V1.JSON

  # Issue #724: the realized-gains roll-up, cross-security and
  # cross-portfolio (FIFO trades match per security across portfolios), so
  # the route is global like /holdings/by_security. The FX basis (D-1)
  # travels in the payload.
  def index(conn, _params) do
    json(conn, %{data: JSON.realized_gains(RealizedGains.report())})
  end
end
