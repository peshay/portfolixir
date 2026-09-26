defmodule PortfolixirWeb.Router do
  use PortfolixirWeb, :router

  # The static half of the browser Content-Security-Policy (#382): the text
  # Sobelow reads, and the fail-closed header a page would carry if the
  # nonce plug below were ever dropped — its inline boot scripts blocked,
  # never a foreign script admitted. PortfolixirWeb.ContentSecurityPolicy
  # replaces it per request with the same text plus the nonce and the
  # socket origin.
  @secure_headers %{
    "content-security-policy" => PortfolixirWeb.ContentSecurityPolicy.static_policy()
  }

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_cookies)
    plug(PortfolixirWeb.Locale)
    plug(PortfolixirWeb.ViewScope)
    plug(PortfolixirWeb.BenchmarkScope)
    plug(:put_root_layout, html: {PortfolixirWeb.LayoutView, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers, @secure_headers)
    plug(PortfolixirWeb.ContentSecurityPolicy)
    # Optional UI login (ADR-0045 §1, #764): a no-op until a password is set.
    plug(PortfolixirWeb.RequireUiAuth)
  end

  # The login and logout routes: the browser pipeline without the login gate.
  pipeline :browser_open do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_cookies)
    plug(PortfolixirWeb.Locale)
    plug(:put_root_layout, html: {PortfolixirWeb.LayoutView, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers, @secure_headers)
    plug(PortfolixirWeb.ContentSecurityPolicy)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :api_auth do
    plug(:accepts, ["json"])
    plug(PortfolixirWeb.ApiAuthPlug)
    # #840: an id past the bigint range is refused here, for every route.
    plug(PortfolixirWeb.Api.V1.IdRangeGuard)
  end

  scope "/", PortfolixirWeb do
    pipe_through(:browser)

    live_session :browser,
      on_mount: [
        PortfolixirWeb.HeapCap,
        PortfolixirWeb.LiveUiAuth,
        PortfolixirWeb.LiveIdRange,
        PortfolixirWeb.LiveEventGuard,
        PortfolixirWeb.LiveLocale,
        PortfolixirWeb.LiveViewScope,
        PortfolixirWeb.LiveBenchmarkScope
      ] do
      live("/", DashboardLive)
      live("/portfolio", PortfolioLive)
      live("/securities", SecuritiesLive)
      live("/securities/:id", SecuritiesLive)
      live("/portfolios", PortfolioAccountsLive)
      live("/transactions", TransactionManagementLive)
      live("/cashflow", IncomeLive)
      live("/snapshots", SnapshotsLive)
      live("/tax", TaxLive)
      live("/risk", RiskLive)
      live("/imports", ImportsLive)
      live("/buckets", BucketsLive)
      live("/classifications", ClassificationsLive, :index)
      live("/classifications/new", ClassificationsLive, :new)
      live("/classifications/:id", ClassificationsLive, :show)
    end
  end

  scope "/", PortfolixirWeb do
    pipe_through(:browser)

    # UX-DR4, #672: Income was promoted to the Cash-flow area. The old route
    # keeps working so existing links and bookmarks survive the rename.
    get("/income", RedirectController, :cashflow)

    # Stored logos, behind the UI login like the pages that show them (#764).
    get("/security_logos/:file", LogoFileController, :show)
  end

  scope "/", PortfolixirWeb do
    pipe_through(:browser_open)

    get("/login", SessionController, :new)
    post("/login", SessionController, :create)
    get("/logout", SessionController, :confirm_logout)
    post("/logout", SessionController, :delete)
  end

  scope "/", PortfolixirWeb do
    pipe_through(:api)

    get("/health", HealthController, :show)
  end

  scope "/api/v1", PortfolixirWeb.Api.V1 do
    pipe_through(:api_auth)

    get("/journal", JournalController, :index)

    # The contract-version read (ADR-0044 §8): what this surface offers and
    # when it last changed, pollable with ?since=.
    get("/contract", ContractController, :show)

    get("/securities/search", SecuritySearchController, :index)
    get("/securities", SecurityController, :index)
    post("/securities", SecurityController, :create)
    get("/securities/:id", SecurityController, :show)
    patch("/securities/:id", SecurityController, :update)
    delete("/securities/:id", SecurityController, :delete)

    # ISIN-change aliases (ADR-0029 §3): record a corporate-action ISIN change
    # and correct recorded aliases; imports keep matching via former ISINs.
    post("/securities/:security_id/isin-change", IsinChangeController, :create)

    delete(
      "/securities/:security_id/identifier_aliases/:id",
      IsinChangeController,
      :delete_alias
    )

    get("/securities/:security_id/logo", LogoController, :show)
    put("/securities/:security_id/logo", LogoController, :update)
    delete("/securities/:security_id/logo", LogoController, :delete)
    post("/securities/:security_id/logo/discover", LogoController, :discover)

    get("/securities/:security_id/quotes", QuoteController, :index)
    put("/securities/:security_id/quotes", QuoteController, :upsert)
    # E25 S6, T-9: a journaled release of manual rows back to provider data.
    post("/securities/:security_id/quotes/release", QuoteController, :release)
    post("/securities/:security_id/sync_quotes", QuoteController, :sync)

    get("/securities/:security_id/trades", TradeController, :index)

    # The per-security derived metrics (FR-39, ADR-0047 §9): level (a) of the
    # scope ladder — moving averages, volatility, drawdown, momentum and the
    # distance to the 52-week extremes over the security's own close series.
    get("/securities/:security_id/metrics", SecurityMetricsController, :show)

    # The security research log (ADR-0044): append, and the four reads of §7.
    # Deliberately no PATCH and no DELETE — entries never vanish (§3); a
    # retraction is appended.
    get("/securities/:security_id/notes", NoteController, :index)
    post("/securities/:security_id/notes", NoteController, :create)
    get("/notes/unreviewed", NoteController, :unreviewed)
    get("/notes/uncorroborated", NoteController, :uncorroborated)
    get("/notes/expiring", NoteController, :expiring)

    # Security events (FR-44, ADR-0048 §5): a dated calendar fact that books
    # nothing, tracked for the WHOLE CATALOG rather than the holdings. The
    # four reads are the acceptance criteria; held_only= narrows and is never
    # the default.
    get("/securities/:security_id/events", SecurityEventController, :index)
    post("/securities/:security_id/events", SecurityEventController, :create)
    patch("/security_events/:id", SecurityEventController, :update)
    delete("/security_events/:id", SecurityEventController, :delete)
    get("/events/upcoming", SecurityEventController, :upcoming)
    get("/events/unconfirmed", SecurityEventController, :unconfirmed)
    get("/events/stale", SecurityEventController, :stale)

    get("/holdings/by_security", HoldingsBySecurityController, :index)
    get("/realized_gains", RealizedGainsController, :index)
    get("/external_flows", ExternalFlowsController, :index)
    get("/costs", CostsController, :index)
    get("/holdings/negative", NegativeHoldingsController, :index)

    # Read-only reconcile of a user-supplied external position list against
    # the ledger (ADR-0029 §6, FR-35): body-only input, nothing persisted.
    post("/holdings/reconcile", HoldingsReconcileController, :create)

    get("/portfolios", PortfolioController, :index)
    post("/portfolios", PortfolioController, :create)
    patch("/portfolios/:portfolio_id", PortfolioController, :update)
    get("/portfolios/:portfolio_id/holdings", HoldingController, :index)
    get("/portfolios/:portfolio_id/valuation", ValuationController, :index)
    get("/portfolios/:portfolio_id/performance", PerformanceController, :index)
    get("/portfolios/:portfolio_id/performance/benchmark", BenchmarkController, :index)
    get("/portfolios/:portfolio_id/income", IncomeController, :index)
    get("/portfolios/:portfolio_id/allocation", AllocationController, :index)

    get(
      "/portfolios/:portfolio_id/category-results",
      CategoryResultController,
      :index
    )

    get("/portfolios/:portfolio_id/risk", RiskController, :index)

    # Policy rules (FR-43, ADR-0049 §8, §9): the operator's caps, floors and
    # bands as versioned objects. An edit is a new version; a version that has
    # been in force is never changed or deleted.
    get("/portfolios/:portfolio_id/policy_rules", PolicyRuleController, :index)
    post("/portfolios/:portfolio_id/policy_rules", PolicyRuleController, :create)
    get("/policy_rules/:id", PolicyRuleController, :show)
    # The rename (#872, D-6): the name is a label outside the versioning.
    patch("/policy_rules/:id", PolicyRuleController, :rename)
    post("/policy_rules/:id/versions", PolicyRuleController, :add_version)
    post("/policy_rules/:id/retire", PolicyRuleController, :retire)
    delete("/policy_rules/:id", PolicyRuleController, :delete)

    # The findings read (ADR-0049 §5): the rules in force today, evaluated at
    # read over the figures the product already serves. status=breached is
    # the retrievable alarm list — a pull; nothing is pushed (B3.7).
    get("/portfolios/:portfolio_id/policy_findings", PolicyFindingController, :index)
    get("/portfolios/:portfolio_id/targets", TargetController, :index)
    put("/portfolios/:portfolio_id/targets", TargetController, :set)
    delete("/portfolios/:portfolio_id/targets/:category_id", TargetController, :delete)

    get("/portfolios/:portfolio_id/position_targets", TargetController, :index_positions)

    delete(
      "/portfolios/:portfolio_id/position_targets/:category_id/:security_id",
      TargetController,
      :delete_position
    )

    get("/portfolios/:portfolio_id/cash_target", TargetController, :show_cash_target)
    put("/portfolios/:portfolio_id/cash_target", TargetController, :set_cash_target)

    # Plan versions (ADR-0027): named SOLL plan versions per scope.
    get("/portfolios/:portfolio_id/plans", PlanController, :index)
    post("/plans/:id/duplicate", PlanController, :duplicate)
    post("/plans/:id/activate", PlanController, :activate)
    patch("/plans/:id", PlanController, :rename)
    delete("/plans/:id", PlanController, :delete)

    # Depot snapshots + counterfactual comparison (ADR-0027).
    get("/snapshots", SnapshotController, :index)
    post("/snapshots", SnapshotController, :create)
    delete("/snapshots/:id", SnapshotController, :delete)

    get(
      "/portfolios/:portfolio_id/snapshots/:id/comparison",
      SnapshotController,
      :comparison
    )

    # Recorded tax-statement snapshots and their configuration (ADR-0031).
    # The pots are transcribed, never derived — see TaxSnapshotController.
    get("/tax/parameters", TaxConfigurationController, :index_parameters)
    put("/tax/parameters", TaxConfigurationController, :upsert_parameters)
    get("/tax/profiles", TaxConfigurationController, :index_profiles)
    post("/tax/profiles", TaxConfigurationController, :create_profile)
    patch("/tax/profiles/:id", TaxConfigurationController, :update_profile)
    delete("/tax/profiles/:id", TaxConfigurationController, :delete_profile)
    get("/tax/allowance_orders", TaxConfigurationController, :index_allowance_orders)
    put("/tax/allowance_orders", TaxConfigurationController, :put_allowance_order)
    delete("/tax/allowance_orders/:id", TaxConfigurationController, :delete_allowance_order)
    get("/tax/statement_snapshots", TaxSnapshotController, :index)
    post("/tax/statement_snapshots", TaxSnapshotController, :create)
    get("/tax/trim_budget", TaxSnapshotController, :trim_budget)
    get("/tax/statement_snapshots/:id", TaxSnapshotController, :show)
    patch("/tax/statement_snapshots/:id", TaxSnapshotController, :update)
    delete("/tax/statement_snapshots/:id", TaxSnapshotController, :delete)

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
    delete("/cash_accounts/:id/former_names", CashAccountController, :remove_former_name)
    # ADR-0050 §7, §10: the merge of a cash account into another — a read
    # that previews it, and the apply under the preview's digest.
    get("/cash_accounts/:id/merge_preview", MergeController, :cash_account_preview)
    post("/cash_accounts/:id/merge", MergeController, :cash_account_merge)

    get("/securities_accounts", SecuritiesAccountController, :index)
    post("/securities_accounts", SecuritiesAccountController, :create)
    get("/securities_accounts/:id", SecuritiesAccountController, :show)
    patch("/securities_accounts/:id", SecuritiesAccountController, :update)
    delete("/securities_accounts/:id", SecuritiesAccountController, :delete)

    delete(
      "/securities_accounts/:id/former_names",
      SecuritiesAccountController,
      :remove_former_name
    )

    # ADR-0050 §7, §10: the merge of a depot into another — a read that
    # previews it, and the apply under the preview's digest.
    get("/securities_accounts/:id/merge_preview", MergeController, :securities_account_preview)
    post("/securities_accounts/:id/merge", MergeController, :securities_account_merge)

    get("/buckets", BucketController, :index)
    post("/buckets", BucketController, :create)
    get("/buckets/:id", BucketController, :show)
    patch("/buckets/:id", BucketController, :update)
    delete("/buckets/:id", BucketController, :delete)

    get("/views", ViewController, :index)
    post("/views", ViewController, :create)
    get("/views/:id", ViewController, :show)
    patch("/views/:id", ViewController, :update)
    delete("/views/:id", ViewController, :delete)
    put("/views/:id/buckets", ViewController, :set_buckets)
    get("/views/:view_id/valuation", ViewValuationController, :show)
    get("/views/:view_id/performance", ViewPerformanceController, :show)
    get("/views/:view_id/performance/benchmark", ViewBenchmarkController, :show)

    get("/settings/default_view", SettingsController, :show_default_view)
    put("/settings/default_view", SettingsController, :set_default_view)

    put("/securities_accounts/:id/buckets", BucketAssignmentController, :set_depot_buckets)
    put("/cash_accounts/:id/buckets", BucketAssignmentController, :set_cash_account_buckets)

    put(
      "/securities_accounts/:id/positions/:security_id/buckets",
      BucketAssignmentController,
      :set_position_override
    )

    delete(
      "/securities_accounts/:id/positions/:security_id/buckets",
      BucketAssignmentController,
      :clear_position_override
    )

    # Dedicated split booking flow (ADR-0028 §1): the generic transaction
    # endpoint rejects the `split` kind; these two routes preview and book
    # the per-portfolio fan-out.
    post("/splits/preview", SplitController, :preview)
    post("/splits", SplitController, :create)

    get("/transactions", TransactionController, :index)
    post("/transactions", TransactionController, :create)
    get("/transactions/:id", TransactionController, :show)
    patch("/transactions/:id", TransactionController, :update)
    delete("/transactions/:id", TransactionController, :delete)
  end
end
