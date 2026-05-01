defmodule PortfolixirWeb.Router do
  use PortfolixirWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(PortfolixirWeb.Locale)
    plug(:put_root_layout, html: {PortfolixirWeb.LayoutView, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :browser_csv do
    plug(:accepts, ["html", "csv"])
    plug(:fetch_session)
    plug(PortfolixirWeb.Locale)
    plug(:put_root_layout, html: {PortfolixirWeb.LayoutView, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", PortfolixirWeb do
    pipe_through(:browser_csv)

    get("/securities/export.csv", SecurityController, :export)
  end

  scope "/", PortfolixirWeb do
    pipe_through(:browser)

    live_session :localized,
      session: {PortfolixirWeb.Locale, :live_session, []},
      on_mount: {PortfolixirWeb.Locale, :default} do
      live("/", SecurityManagementLive)
      live("/accounts", AccountManagementLive)
      live("/transactions", TransactionManagementLive)
      live("/taxonomies", CategoryManagementLive)
      live("/securities", SecurityManagementLive)
      live("/securities/:id", SecurityDetailLive)
    end
  end

  scope "/", PortfolixirWeb do
    pipe_through(:api)

    get("/health", HealthController, :show)
  end

  scope "/api/read", PortfolixirWeb do
    pipe_through(:api)

    get("/portfolio_snapshot", ReadAPIController, :portfolio_snapshot)
    get("/positions", ReadAPIController, :positions)
    get("/transactions", ReadAPIController, :transactions)
    get("/cash_balances", ReadAPIController, :cash_balances)
  end
end
