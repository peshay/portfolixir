defmodule PortfolixirWeb.Router do
  use PortfolixirWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", PortfolixirWeb do
    pipe_through(:api)

    get("/health", HealthController, :show)
  end
end
