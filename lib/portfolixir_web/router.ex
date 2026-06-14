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
      live("/portfolio", PortfolioLive)
      live("/securities", SecuritiesLive)
      live("/securities/:id", SecuritiesLive)
      live("/portfolios", PortfolioAccountsLive)
      live("/transactions", TransactionManagementLive)
      live("/income", IncomeLive)
      live("/imports", ImportsLive)
      live("/classifications", ClassificationsLive, :index)
      live("/classifications/new", ClassificationsLive, :new)
      live("/classifications/:id", ClassificationsLive, :show)
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

    get("/securities/:security_id/logo", LogoController, :show)
    put("/securities/:security_id/logo", LogoController, :update)
    delete("/securities/:security_id/logo", LogoController, :delete)
    post("/securities/:security_id/logo/discover", LogoController, :discover)

    get("/securities/:security_id/quotes", QuoteController, :index)
    put("/securities/:security_id/quotes", QuoteController, :upsert)
    post("/securities/:security_id/sync_quotes", QuoteController, :sync)

    get("/securities/:security_id/trades", TradeController, :index)

    get("/holdings/by_security", HoldingsBySecurityController, :index)

    get("/portfolios", PortfolioController, :index)
    post("/portfolios", PortfolioController, :create)
    patch("/portfolios/:portfolio_id", PortfolioController, :update)
    get("/portfolios/:portfolio_id/holdings", HoldingController, :index)
    get("/portfolios/:portfolio_id/valuation", ValuationController, :index)
    get("/portfolios/:portfolio_id/performance", PerformanceController, :index)
    get("/portfolios/:portfolio_id/income", IncomeController, :index)
    get("/portfolios/:portfolio_id/allocation", AllocationController, :index)
    get("/portfolios/:portfolio_id/targets", TargetController, :index)
    put("/portfolios/:portfolio_id/targets", TargetController, :set)
    delete("/portfolios/:portfolio_id/targets/:category_id", TargetController, :delete)

    get("/exchange_rates", ExchangeRateController, :index)
    post("/exchange_rates/sync", ExchangeRateController, :sync)

    get("/classifications", ClassificationController, :index)
    post("/classifications", ClassificationController, :create)
    patch("/classifications/:id", ClassificationController, :update)
    delete("/classifications/:id", ClassificationController, :delete)
    put("/classifications/:classification_id/assignments", ClassificationController, :assign)

    put(
      "/classifications/:classification_id/assignments/bulk",
      ClassificationController,
      :assign_bulk
    )

    post(
      "/classifications/:classification_id/categories",
      ClassificationController,
      :create_category
    )

    patch(
      "/classifications/:classification_id/categories/:id",
      ClassificationController,
      :update_category
    )

    delete(
      "/classifications/:classification_id/categories/:id",
      ClassificationController,
      :delete_category
    )

    delete(
      "/classifications/:classification_id/assignments/:security_id",
      ClassificationController,
      :unassign
    )

    get("/cash_accounts", CashAccountController, :index)
    post("/cash_accounts", CashAccountController, :create)
    get("/cash_accounts/:id", CashAccountController, :show)
    patch("/cash_accounts/:id", CashAccountController, :update)
    post("/cash_accounts/:id/balance", CashAccountController, :set_balance)
    delete("/cash_accounts/:id", CashAccountController, :delete)

    get("/securities_accounts", SecuritiesAccountController, :index)
    post("/securities_accounts", SecuritiesAccountController, :create)
    get("/securities_accounts/:id", SecuritiesAccountController, :show)
    patch("/securities_accounts/:id", SecuritiesAccountController, :update)
    delete("/securities_accounts/:id", SecuritiesAccountController, :delete)

    get("/transactions", TransactionController, :index)
    post("/transactions", TransactionController, :create)
    get("/transactions/:id", TransactionController, :show)
    patch("/transactions/:id", TransactionController, :update)
    delete("/transactions/:id", TransactionController, :delete)
  end
end
