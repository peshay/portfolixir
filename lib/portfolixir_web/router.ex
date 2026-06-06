defmodule PortfolixirWeb.Router do
  use PortfolixirWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_cookies)
    plug(PortfolixirWeb.Locale)
    plug(:put_root_layout, html: {PortfolixirWeb.LayoutView, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :api_auth do
    plug(:accepts, ["json"])
    plug(PortfolixirWeb.ApiAuthPlug)
  end

  scope "/", PortfolixirWeb do
    pipe_through(:browser)

    live_session :browser, on_mount: PortfolixirWeb.LiveLocale do
      live("/", DashboardLive)
      live("/securities", SecuritiesLive)
      live("/securities/:id", SecuritiesLive)
      live("/portfolios", PortfolioAccountsLive)
      live("/transactions", TransactionManagementLive)
      live("/imports", ImportsLive)
    end
  end

  scope "/", PortfolixirWeb do
    pipe_through(:api)

    get("/health", HealthController, :show)
  end

  scope "/api/v1", PortfolixirWeb.Api.V1 do
    pipe_through(:api_auth)

    get("/securities/search", SecuritySearchController, :index)
    get("/securities", SecurityController, :index)
    post("/securities", SecurityController, :create)
    get("/securities/:id", SecurityController, :show)
    patch("/securities/:id", SecurityController, :update)
    delete("/securities/:id", SecurityController, :delete)

    get("/securities/:security_id/quotes", QuoteController, :index)
    put("/securities/:security_id/quotes", QuoteController, :upsert)
    post("/securities/:security_id/sync_quotes", QuoteController, :sync)

    get("/securities/:security_id/trades", TradeController, :index)

    get("/portfolios", PortfolioController, :index)
    post("/portfolios", PortfolioController, :create)
    get("/portfolios/:portfolio_id/holdings", HoldingController, :index)
    get("/portfolios/:portfolio_id/valuation", ValuationController, :index)

    get("/exchange_rates", ExchangeRateController, :index)
    post("/exchange_rates/sync", ExchangeRateController, :sync)

    get("/classifications", ClassificationController, :index)
    post("/classifications", ClassificationController, :create)
    put("/classifications/:classification_id/assignments", ClassificationController, :assign)

    post(
      "/classifications/:classification_id/categories",
      ClassificationController,
      :create_category
    )

    delete(
      "/classifications/:classification_id/assignments/:security_id",
      ClassificationController,
      :unassign
    )

    get("/cash_accounts", CashAccountController, :index)
    post("/cash_accounts", CashAccountController, :create)

    get("/securities_accounts", SecuritiesAccountController, :index)
    post("/securities_accounts", SecuritiesAccountController, :create)

    get("/transactions", TransactionController, :index)
    post("/transactions", TransactionController, :create)
  end
end
