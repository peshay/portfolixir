defmodule PortfolixirWeb.Api.V1.Contract do
  @moduledoc """
  The **contract-version read** (ADR-0044 §8, issue #752): what the API and
  MCP surface offers and when it last changed, pollable the way `?since=` is
  pollable for rows.

  A code-maintained manifest: dated entries, each naming the endpoints and
  tools the change touched (and the parameters it added to existing ones).
  The newest entry's `version` and `date` are the contract's. A meta-test
  (`test/portfolixir_web/controllers/api_v1_contract_meta_test.exs`) ties the
  router's `/api/v1` inventory and the MCP companion's tool inventory to the
  union of these entries in **both directions**, so a route or tool added,
  renamed or removed without a manifest entry fails the build — the surface
  cannot change without saying so.

  Not a changelog document and not a description rewrite: an entry is one
  dated statement of *which parts of the surface moved*, for a consumer that
  cached its tool descriptions at connect time.

  Maintaining it: append a new entry at the **head** of `@entries` with the
  next integer `version`, today's date, a one-sentence `summary`, the
  `endpoints` ("VERB /api/v1/path") and `tools` it adds, and `parameters`
  (free text, one per changed read) for a parameter added to an existing
  surface. Removals are listed under `removed_endpoints` / `removed_tools`
  so the union stays exact.
  """

  @type entry :: %{
          version: pos_integer(),
          date: Date.t(),
          summary: String.t(),
          endpoints: [String.t()],
          tools: [String.t()],
          parameters: [String.t()],
          removed_endpoints: [String.t()],
          removed_tools: [String.t()]
        }

  # Newest first.
  @entries [
    %{
      version: 3,
      date: ~D[2026-09-05],
      summary:
        "Sprint 10 (ADR-0045, E21 security hardening): provenance fields are system-set — " <>
          "notes.append no longer takes author or machine_generated and transactions refuse " <>
          "import_hash (#766); every list read takes a bounded limit and the quote upsert a row " <>
          "cap (#771); the logo endpoint validates its URL and answers fixed messages (#762); " <>
          "repeated wrong bearer tokens are answered 429 with Retry-After (#771).",
      endpoints: [],
      tools: [],
      parameters: [
        "POST /api/v1/securities/:security_id/notes and portfolixir.notes.append: author is derived from the credential and machine_generated is reserved; both are ignored in the body (#766)",
        "POST and PATCH /api/v1/transactions and the MCP transaction writes refuse import_hash with 422 (#766)",
        "PATCH /api/v1/securities/:id and portfolixir.securities.update: attributes merge into the stored map, a null removes a key, logo_* keys are dropped (#766)",
        "GET /api/v1/transactions, /securities, /exchange_rates and /securities/:id/quotes and their MCP twins take limit= (defaults 10000 / 5000 / 50000 / 20000, maxima 50000 / 20000 / 200000 / 50000); a malformed limit is 422 (#771)",
        "PUT /api/v1/securities/:id/quotes and portfolixir.quotes.upsert refuse more than 10000 rows per request (#771)",
        "PUT /api/v1/securities/:id/logo: the URL must be https to a public address; refusals and download failures carry fixed messages (#762)",
        "Every /api/v1 route answers 429 with Retry-After after repeated wrong bearer tokens from one source (#771)"
      ],
      removed_endpoints: [],
      removed_tools: []
    },
    %{
      version: 2,
      date: ~D[2026-09-03],
      summary:
        "Sprint 9 (ADR-0044, E20): the security research log — append and the four reads — " <>
          "with the thesis state in the security read; include_positions reaches the view valuation " <>
          "and min_drift the position-target listing (#740); the exchange-rate sync gains the " <>
          "historical backfill scope (#737); this contract read (#752).",
      endpoints: [
        "GET /api/v1/securities/:security_id/notes",
        "POST /api/v1/securities/:security_id/notes",
        "GET /api/v1/notes/unreviewed",
        "GET /api/v1/notes/uncorroborated",
        "GET /api/v1/notes/expiring",
        "GET /api/v1/contract"
      ],
      tools: [
        "portfolixir.notes.list",
        "portfolixir.notes.append",
        "portfolixir.notes.unreviewed",
        "portfolixir.notes.uncorroborated",
        "portfolixir.notes.expiring",
        "portfolixir.contract.get"
      ],
      parameters: [
        "GET /api/v1/securities/:id and portfolixir.securities.get carry thesis_state (ADR-0044 §1); fields= can select it",
        "GET /api/v1/views/:view_id/valuation and portfolixir.views.valuation take include_positions=false (#740)",
        "GET /api/v1/portfolios/:portfolio_id/position_targets and portfolixir.targets.list_positions take min_drift= and answer position_targets_total, drift_basis and drift_weight on kept rows (#740)",
        "POST /api/v1/exchange_rates/sync and portfolixir.exchange_rates.sync take scope=latest|history and answer scope (#737)"
      ],
      removed_endpoints: [],
      removed_tools: []
    },
    %{
      version: 1,
      date: ~D[2026-09-03],
      summary:
        "Baseline: the surface as released in 0.8.0 (Sprint 8, 2026-08-22), recorded when the " <>
          "contract read was introduced so its first entry can name this batch's own additions.",
      endpoints: [
        "DELETE /api/v1/buckets/:id",
        "DELETE /api/v1/cash_accounts/:id",
        "DELETE /api/v1/classifications/:classification_id/assignments/:security_id",
        "DELETE /api/v1/classifications/:classification_id/categories/:id",
        "DELETE /api/v1/classifications/:id",
        "DELETE /api/v1/plans/:id",
        "DELETE /api/v1/portfolios/:portfolio_id/position_targets/:category_id/:security_id",
        "DELETE /api/v1/portfolios/:portfolio_id/targets/:category_id",
        "DELETE /api/v1/securities/:id",
        "DELETE /api/v1/securities/:security_id/identifier_aliases/:id",
        "DELETE /api/v1/securities/:security_id/logo",
        "DELETE /api/v1/securities_accounts/:id",
        "DELETE /api/v1/securities_accounts/:id/positions/:security_id/buckets",
        "DELETE /api/v1/snapshots/:id",
        "DELETE /api/v1/tax/allowance_orders/:id",
        "DELETE /api/v1/tax/profiles/:id",
        "DELETE /api/v1/tax/statement_snapshots/:id",
        "DELETE /api/v1/transactions/:id",
        "DELETE /api/v1/views/:id",
        "GET /api/v1/buckets",
        "GET /api/v1/buckets/:id",
        "GET /api/v1/cash_accounts",
        "GET /api/v1/cash_accounts/:id",
        "GET /api/v1/classifications",
        "GET /api/v1/costs",
        "GET /api/v1/exchange_rates",
        "GET /api/v1/external_flows",
        "GET /api/v1/holdings/by_security",
        "GET /api/v1/holdings/negative",
        "GET /api/v1/journal",
        "GET /api/v1/portfolios",
        "GET /api/v1/portfolios/:portfolio_id/allocation",
        "GET /api/v1/portfolios/:portfolio_id/cash_target",
        "GET /api/v1/portfolios/:portfolio_id/category-results",
        "GET /api/v1/portfolios/:portfolio_id/holdings",
        "GET /api/v1/portfolios/:portfolio_id/income",
        "GET /api/v1/portfolios/:portfolio_id/performance",
        "GET /api/v1/portfolios/:portfolio_id/plans",
        "GET /api/v1/portfolios/:portfolio_id/position_targets",
        "GET /api/v1/portfolios/:portfolio_id/risk",
        "GET /api/v1/portfolios/:portfolio_id/snapshots/:id/comparison",
        "GET /api/v1/portfolios/:portfolio_id/targets",
        "GET /api/v1/portfolios/:portfolio_id/valuation",
        "GET /api/v1/realized_gains",
        "GET /api/v1/securities",
        "GET /api/v1/securities/:id",
        "GET /api/v1/securities/:security_id/logo",
        "GET /api/v1/securities/:security_id/quotes",
        "GET /api/v1/securities/:security_id/trades",
        "GET /api/v1/securities/search",
        "GET /api/v1/securities_accounts",
        "GET /api/v1/securities_accounts/:id",
        "GET /api/v1/settings/default_view",
        "GET /api/v1/snapshots",
        "GET /api/v1/tax/allowance_orders",
        "GET /api/v1/tax/parameters",
        "GET /api/v1/tax/profiles",
        "GET /api/v1/tax/statement_snapshots",
        "GET /api/v1/tax/statement_snapshots/:id",
        "GET /api/v1/tax/trim_budget",
        "GET /api/v1/transactions",
        "GET /api/v1/transactions/:id",
        "GET /api/v1/views",
        "GET /api/v1/views/:id",
        "GET /api/v1/views/:view_id/performance",
        "GET /api/v1/views/:view_id/valuation",
        "PATCH /api/v1/buckets/:id",
        "PATCH /api/v1/cash_accounts/:id",
        "PATCH /api/v1/classifications/:classification_id/categories/:id",
        "PATCH /api/v1/classifications/:id",
        "PATCH /api/v1/plans/:id",
        "PATCH /api/v1/portfolios/:portfolio_id",
        "PATCH /api/v1/securities/:id",
        "PATCH /api/v1/securities_accounts/:id",
        "PATCH /api/v1/tax/profiles/:id",
        "PATCH /api/v1/tax/statement_snapshots/:id",
        "PATCH /api/v1/transactions/:id",
        "PATCH /api/v1/views/:id",
        "POST /api/v1/buckets",
        "POST /api/v1/cash_accounts",
        "POST /api/v1/cash_accounts/:id/balance",
        "POST /api/v1/classifications",
        "POST /api/v1/classifications/:classification_id/categories",
        "POST /api/v1/exchange_rates/sync",
        "POST /api/v1/holdings/reconcile",
        "POST /api/v1/plans/:id/activate",
        "POST /api/v1/plans/:id/duplicate",
        "POST /api/v1/portfolios",
        "POST /api/v1/securities",
        "POST /api/v1/securities/:security_id/isin-change",
        "POST /api/v1/securities/:security_id/logo/discover",
        "POST /api/v1/securities/:security_id/sync_quotes",
        "POST /api/v1/securities_accounts",
        "POST /api/v1/snapshots",
        "POST /api/v1/splits",
        "POST /api/v1/splits/preview",
        "POST /api/v1/tax/profiles",
        "POST /api/v1/tax/statement_snapshots",
        "POST /api/v1/transactions",
        "POST /api/v1/views",
        "PUT /api/v1/cash_accounts/:id/buckets",
        "PUT /api/v1/classifications/:classification_id/assignments",
        "PUT /api/v1/classifications/:classification_id/assignments/bulk",
        "PUT /api/v1/portfolios/:portfolio_id/cash_target",
        "PUT /api/v1/portfolios/:portfolio_id/targets",
        "PUT /api/v1/securities/:security_id/logo",
        "PUT /api/v1/securities/:security_id/quotes",
        "PUT /api/v1/securities_accounts/:id/buckets",
        "PUT /api/v1/securities_accounts/:id/positions/:security_id/buckets",
        "PUT /api/v1/settings/default_view",
        "PUT /api/v1/tax/allowance_orders",
        "PUT /api/v1/tax/parameters",
        "PUT /api/v1/views/:id/buckets"
      ],
      tools: [
        "portfolixir.securities.list",
        "portfolixir.securities.get",
        "portfolixir.securities.create",
        "portfolixir.securities.update",
        "portfolixir.securities.delete",
        "portfolixir.securities.isin_change",
        "portfolixir.securities.delete_isin_alias",
        "portfolixir.securities.search_online",
        "portfolixir.quotes.sync",
        "portfolixir.quotes.list",
        "portfolixir.quotes.upsert",
        "portfolixir.portfolios.list",
        "portfolixir.portfolios.create",
        "portfolixir.cash_accounts.list",
        "portfolixir.cash_accounts.create",
        "portfolixir.cash_accounts.update",
        "portfolixir.cash_accounts.delete",
        "portfolixir.securities_accounts.list",
        "portfolixir.securities_accounts.create",
        "portfolixir.securities_accounts.update",
        "portfolixir.securities_accounts.delete",
        "portfolixir.transactions.list",
        "portfolixir.transactions.create",
        "portfolixir.transactions.update",
        "portfolixir.transactions.delete",
        "portfolixir.splits.preview",
        "portfolixir.splits.create",
        "portfolixir.holdings.list",
        "portfolixir.cashflow.realized_gains",
        "portfolixir.cashflow.external_flows",
        "portfolixir.cashflow.costs",
        "portfolixir.holdings.by_security",
        "portfolixir.holdings.negative",
        "portfolixir.holdings.reconcile",
        "portfolixir.portfolios.valuation",
        "portfolixir.exchange_rates.list",
        "portfolixir.exchange_rates.sync",
        "portfolixir.classifications.list",
        "portfolixir.classifications.create",
        "portfolixir.classifications.categories.create",
        "portfolixir.classifications.update",
        "portfolixir.classifications.delete",
        "portfolixir.classifications.categories.update",
        "portfolixir.classifications.categories.delete",
        "portfolixir.classifications.assign",
        "portfolixir.classifications.assign_bulk",
        "portfolixir.classifications.unassign",
        "portfolixir.trades.list",
        "portfolixir.targets.list",
        "portfolixir.targets.set",
        "portfolixir.targets.delete",
        "portfolixir.targets.list_positions",
        "portfolixir.targets.delete_position",
        "portfolixir.portfolios.allocation",
        "portfolixir.portfolios.category_results",
        "portfolixir.portfolios.risk",
        "portfolixir.portfolios.cash_target",
        "portfolixir.portfolios.set_cash_target",
        "portfolixir.cash_accounts.set_balance",
        "portfolixir.portfolios.income",
        "portfolixir.portfolios.performance",
        "portfolixir.journal.list",
        "portfolixir.buckets.list",
        "portfolixir.buckets.get",
        "portfolixir.buckets.create",
        "portfolixir.buckets.update",
        "portfolixir.buckets.delete",
        "portfolixir.views.list",
        "portfolixir.views.get",
        "portfolixir.views.create",
        "portfolixir.views.update",
        "portfolixir.views.delete",
        "portfolixir.views.set_buckets",
        "portfolixir.views.valuation",
        "portfolixir.views.performance",
        "portfolixir.securities_accounts.set_buckets",
        "portfolixir.cash_accounts.set_buckets",
        "portfolixir.securities_accounts.set_position_buckets",
        "portfolixir.securities_accounts.clear_position_buckets",
        "portfolixir.settings.get_default_view",
        "portfolixir.settings.set_default_view",
        "portfolixir.plans.list",
        "portfolixir.plans.duplicate",
        "portfolixir.plans.activate",
        "portfolixir.plans.rename",
        "portfolixir.plans.delete",
        "portfolixir.snapshots.list",
        "portfolixir.snapshots.create",
        "portfolixir.snapshots.delete",
        "portfolixir.snapshots.comparison",
        "portfolixir.tax_parameters.list",
        "portfolixir.tax_parameters.upsert",
        "portfolixir.tax_profiles.list",
        "portfolixir.tax_profiles.create",
        "portfolixir.tax_profiles.update",
        "portfolixir.tax_profiles.delete",
        "portfolixir.allowance_orders.list",
        "portfolixir.allowance_orders.put",
        "portfolixir.allowance_orders.delete",
        "portfolixir.tax_snapshots.list",
        "portfolixir.tax_snapshots.get",
        "portfolixir.tax_snapshots.create",
        "portfolixir.tax_snapshots.update",
        "portfolixir.tax_snapshots.delete",
        "portfolixir.tax_snapshots.trim_budget"
      ],
      parameters: [],
      removed_endpoints: [],
      removed_tools: []
    }
  ]

  @doc "The manifest, newest entry first."
  @spec entries() :: [entry()]
  def entries, do: @entries

  @doc "The current contract version — the newest entry's `version`."
  @spec version() :: pos_integer()
  def version, do: hd(@entries).version

  @doc "When the surface last changed — the newest entry's `date`."
  @spec last_changed_at() :: Date.t()
  def last_changed_at, do: hd(@entries).date

  @doc """
  The entries dated **strictly after** `since` (a `Date`), newest first — the
  `?since=` idea applied to the contract: an agent that stored
  `last_changed_at` asks for what moved since then.
  """
  @spec entries_since(Date.t()) :: [entry()]
  def entries_since(%Date{} = since),
    do: Enum.filter(@entries, &(Date.compare(&1.date, since) == :gt))

  @doc "Every endpoint the surface offers today: the union of the entries, removals applied."
  @spec endpoints() :: MapSet.t(String.t())
  def endpoints, do: current(:endpoints, :removed_endpoints)

  @doc "Every MCP tool the surface offers today: the union of the entries, removals applied."
  @spec tools() :: MapSet.t(String.t())
  def tools, do: current(:tools, :removed_tools)

  # Oldest first: an entry may only remove what an earlier entry added.
  defp current(add_key, remove_key) do
    @entries
    |> Enum.reverse()
    |> Enum.reduce(MapSet.new(), fn entry, acc ->
      acc
      |> MapSet.union(MapSet.new(Map.get(entry, add_key, [])))
      |> MapSet.difference(MapSet.new(Map.get(entry, remove_key, [])))
    end)
  end
end
