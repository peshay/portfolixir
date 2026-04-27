defmodule PortfolixirWeb.HealthController do
  use PortfolixirWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
