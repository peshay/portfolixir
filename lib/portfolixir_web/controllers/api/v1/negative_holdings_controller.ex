defmodule PortfolixirWeb.Api.V1.NegativeHoldingsController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Ledger
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, _params) do
    json(conn, %{data: JSON.negative_holdings(Ledger.negative_holdings_report())})
  end
end
