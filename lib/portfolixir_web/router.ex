defmodule PortfolixirWeb.Router do
  use PortfolixirWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:put_root_layout, html: {PortfolixirWeb.LayoutView, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", PortfolixirWeb do
    pipe_through(:browser)
    live("/", SecurityManagementLive)
    live("/accounts", AccountManagementLive)
    live("/transactions", TransactionManagementLive)
    live("/taxonomies", CategoryManagementLive)
    live("/securities", SecurityManagementLive)
  end

  scope "/", PortfolixirWeb do
    pipe_through(:api)

    get("/health", HealthController, :show)
  end
end
