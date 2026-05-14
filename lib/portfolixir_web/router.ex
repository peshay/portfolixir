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

    live_session :browser do
      live("/", DashboardLive)
      live("/securities", SecurityManagementLive)
      live("/securities/:id", SecurityDetailLive)
      live("/portfolios", PortfolioAccountsLive)
      live("/transactions", TransactionManagementLive)
    end
  end

  scope "/", PortfolixirWeb do
    pipe_through(:api)

    get("/health", HealthController, :show)
  end
end
