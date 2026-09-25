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
      version: 8,
      # Sprint 16's one entry: the first surface change of the batch opened it,
      # every later change of the batch extends it.
      date: ~D[2026-09-25],
      summary:
        "Sprint 16: the second security pass (E25) — errors the server answers " <>
          "itself carry the documented errors envelope with their own status — and the " <>
          "lifecycle's hardened deletes (ADR-0050 §11): a referenced cash account, depot or " <>
          "security answers 409 naming what references it, counted, and the remedy; its " <>
          "identity fields freeze once referenced, answering 422 — and the re-import contract's " <>
          "former names (ADR-0050 §4): a cash account and a depot list the names a Portfolio " <>
          "Performance import still books onto them, a rename keeps the previous name, a name " <>
          "another account answers to is refused, and a former name is removable — and a " <>
          "policy rule's rename (ADR-0049 §4 as amended, #872): the name is a label outside the " <>
          "versioning, so a rename creates no version and changes none — and every authored " <>
          "quote write journaled, with a journaled release of manual quotes back to provider " <>
          "data (T-9).",
      endpoints: [
        "DELETE /api/v1/cash_accounts/:id/former_names",
        "DELETE /api/v1/securities_accounts/:id/former_names",
        "PATCH /api/v1/policy_rules/:id",
        "POST /api/v1/securities/:security_id/quotes/release"
      ],
      tools: [
        "portfolixir.cash_accounts.remove_former_name",
        "portfolixir.securities_accounts.remove_former_name",
        "portfolixir.policy_rules.rename",
        "portfolixir.quotes.release"
      ],
      parameters: [
        "Every /api/v1 error the server answers itself rather than an endpoint (an unreadable body 400, a body over the size bound 413, an unknown route 404, an internal error 500) answers {\"errors\": {\"detail\": <reason phrase>}} with its own status (E25 S2, F68); it used to be {\"status\", \"error\"} for 404 and 500 and a bodyless 500 for every other status",
        "The MCP companion's HTTP transport checks the origin and the bearer token before it reads a request body, and answers the errors it raises itself, an unknown path's 404 among them, {\"errors\": {\"detail\": <reason phrase>}} with no stack trace; the MCP protocol's own refusals on /mcp keep their JSON-RPC error shape (E25 S2, F19)",
        "DELETE /api/v1/cash_accounts/:id, /securities_accounts/:id and /securities/:id (portfolixir.cash_accounts.delete, portfolixir.securities_accounts.delete, portfolixir.securities.delete) answer a referenced row 409 with errors.referenced_by (the referencing tables, counted; a transaction once whichever leg references the account), errors.remedy (merge, or retire for a security research notes or policy-rule versions reference) and errors.remedy_route (GET /api/v1/<kind>/:id/merge_preview?target_id=, or PATCH /api/v1/securities/:id); it used to be a bare detail. A delete of a row that has gone answers 404, and an unreferenced row's bucket links, position overrides, category assignments, position targets and ISIN aliases are removed first, each journaled (ADR-0050 §11, L1)",
        "PATCH /api/v1/cash_accounts/:id (portfolixir.cash_accounts.update) answers a currency_code change 422 once a transaction references the account through either leg or a securities account links to it, and PATCH /api/v1/securities/:id (portfolixir.securities.update) once the security has a transaction or a quote, with errors.currency_code [\"is frozen once referenced (<the references, counted>)\"] and nothing written; it used to re-denominate the booked history silently. Resending the stored currency is no change, and the other fields stay editable (ADR-0050 §11, L1)",
        "Every cash-account and securities-account payload (GET /api/v1/cash_accounts, /cash_accounts/:id, /securities_accounts, /securities_accounts/:id and the create, update and removal answers; portfolixir.cash_accounts.* and portfolixir.securities_accounts.*) carries former_names, a list of strings: the names a Portfolio Performance import still resolves to that account after its live name (ADR-0050 §4, L2)",
        "PATCH /api/v1/cash_accounts/:id and /securities_accounts/:id (portfolixir.cash_accounts.update, portfolixir.securities_accounts.update): a rename appends the previous name to former_names, and a rename back to a former name consumes it; while another account of the kind in the portfolio still carries the previous name as its live name, it is not kept. POST and PATCH answer 422 with errors.name when the name is another account's live or former name of the kind in the portfolio; it used to allow duplicate names (ADR-0050 §4, L2)",
        "DELETE /api/v1/cash_accounts/:id/former_names?name= and /securities_accounts/:id/former_names?name= (portfolixir.cash_accounts.remove_former_name, portfolixir.securities_accounts.remove_former_name) remove one former name, journaled, and answer the account; a name the account does not carry answers 404, a missing name 422. An import that still names it then creates a new account (ADR-0050 §4, L2)",
        "POST /api/v1/securities and PATCH /api/v1/securities/:id (portfolixir.securities.create, .update) answer 422 with errors.ticker_symbol for a ticker made only of dots, and with errors.online_id for a provider id made only of dots, carrying whitespace or URL syntax, or longer than 128 characters: both travel in provider request paths as one segment (E25 S3, F31)",
        "PUT /api/v1/securities/:security_id/quotes (portfolixir.quotes.upsert) answers 422 with errors.date for a date later than tomorrow (the instance's calendar day plus one day of zone slack) and errors.close for a close that is not positive once rounded half up to its 6 decimal places or that has more than 14 digits before the decimal point, and writes nothing (a finer close is stored rounded, never as 0); POST /api/v1/securities/:security_id/sync_quotes and POST /api/v1/exchange_rates/sync drop a provider point or rate outside the same bound (a rate judged at its 15 decimal places) instead of failing the run; the latest-quote and latest-rate reads (the valuation price, latest_price on the securities reads, the stale_quote set, the rates a conversion uses) never serve a stored row dated past it (E25 S3, F26)",
        "GET /api/v1/portfolios/:portfolio_id/risk (portfolixir.portfolios.risk) and GET /api/v1/securities/:security_id/metrics (portfolixir.securities.metrics) answer a volatility, a risk_adjusted_return or a correlation pair whose square root lies outside the double range, a magnitude only implausible stored prices or rates reach, as null without insufficient_data, and computation_basis.gaps says so; the read used to fail with a 500 (E25 S3, F73)",
        "POST /api/v1/securities/:security_id/sync_quotes (portfolixir.quotes.sync) stores a history of any length (written in chunks inside one transaction) and answers status error with reason persist_failed when the fetched quotes cannot be stored; the scheduled sync keeps going past such a security. POST /api/v1/exchange_rates/sync (portfolixir.exchange_rates.sync) stores the full history in one call and answers 502 with nothing stored when the rates cannot be stored; it used to answer 500 (E25 S3, F28)",
        "GET /api/v1/securities/search (portfolixir.securities.search_online) type-checks and size-bounds every provider field of a hit: a field of the wrong type or over its bound is absent, a hit without a usable name is dropped, markets keep bounded fields and scalar properties, and raw carries only type and market_cap_rank instead of the provider's whole entry; the attributes a hit writes pass the same scalar-and-length rule. POST /api/v1/securities and PATCH /api/v1/securities/:id (portfolixir.securities.create, .update) answer 422 on a name, feed_url or latest_feed_url over 255 characters, which used to fail in the database (E25 S3, F29)",
        "POST /api/v1/securities/:security_id/sync_quotes (portfolixir.quotes.sync) answers 409 with a fixed detail while a sync of the same security runs on any path, the background backfill a newly created security starts included, and calls no provider; POST /api/v1/exchange_rates/sync with scope=history (portfolixir.exchange_rates.sync) answers 409 while another backfill runs. A created security's quote backfill, over the API, the page or an import, runs on one serial queue, one security at a time (E25 S3, G04)",
        "Every write that stores a date (the transactions, set_balance, splits, policy-rule versions and retirements, depot and tax statement snapshots, tax profiles, research-log entries, security events, ISIN changes and quotes, over the API and their MCP tools) answers 422 naming the field for a date outside 1900-01-01 to 2999-12-31 or sent in any form other than YYYY-MM-DD (an object of parts, a date-time), and stores nothing; it used to accept any year the cast could build. A provider quote or rate dated before the range is dropped like any implausible point, and a Portfolio Performance import names a row dated after it as a row error (E25 S4, F70)",
        "GET /api/v1/portfolios/:portfolio_id/allocation and /position_targets (portfolixir.portfolios.allocation, portfolixir.targets.list_positions) answer min_drift=NaN, Infinity or -Infinity with 422 naming min_drift; it used to answer 500. The risk read's thresholds and risk_free_rate and the benchmark's rate: selector share the same finite-decimal parser (E25 S4, G15)",
        "POST /api/v1/transactions, PATCH /api/v1/transactions/:id and POST /api/v1/cash_accounts/:id/balance (portfolixir.transactions.create, .update, portfolixir.cash_accounts.set_balance) round a money field or price to 6 decimal places and a quantity to 12, half up, before the checks, so the stored, answered and journaled value is the rounded one and a positive amount that rounds to 0 answers 422; a value with more than 14 digits before the decimal point (a quantity more than 18) answers 422 naming the field; both used to reach the database, which rounded after validation or failed with a 500 (E25 S4, G16, G17)",
        "PUT /api/v1/tax/parameters, POST and PATCH /api/v1/tax/profiles, PUT /api/v1/tax/allowance_orders and POST and PATCH /api/v1/tax/statement_snapshots (portfolixir.tax_parameters.upsert, portfolixir.tax_profiles.create, .update, portfolixir.allowance_orders.put, portfolixir.tax_snapshots.create, .update) round every money field to 6 decimal places and every rate to 4, half up, before the checks, so the stored and answered value is the rounded one; a money value with more than 14 digits before the decimal point answers 422 naming the field; it used to fail in the database with a 500 (E25 S4, G16, G17)",
        "Every write that stores a name, an identifier or free text (portfolios, cash and securities accounts, securities, classifications and categories, buckets, views, plans, snapshots, policy rules and their versions, research-log entries, security events, tax profiles, statement snapshots and allowance orders, ISIN aliases, transactions' notes; over the API and their MCP tools) answers 422 naming the field for one-line text longer than its column in Unicode code points or carrying a control character or line break, and for free text carrying a control character other than tab and line break; it used to fail in the database with a 500. POST /api/v1/securities/:security_id/isin-change (portfolixir.securities.isin_change) answers 422 on new_isin unless it is twelve characters of the ISIN shape, and on an alias note over 255 characters (E25 S4, G17, G24)",
        "POST /api/v1/securities and PATCH /api/v1/securities/:id (portfolixir.securities.create, .update) answer 422 on attributes when a key, at any depth, is longer than 255 characters or carries a control character or line break, or a text value carries a control character other than tab and line break; it used to fail in the database with a 500. GET /api/v1/securities/search (portfolixir.securities.search_online) drops a provider property that breaks the same rule (E25 S4, G24)",
        "GET /api/v1/transactions and /securities/:security_id/quotes and /trades (from, to), /securities/:security_id/metrics and /portfolios/:portfolio_id/policy_rules (as_of) (portfolixir.transactions.list, portfolixir.quotes.list, portfolixir.trades.list, portfolixir.securities.metrics, portfolixir.policy_rules.list) answer a date outside 1900-01-01 to 2999-12-31, or not YYYY-MM-DD, with 422 naming the parameter; GET /api/v1/securities (query), /journal (resource_type, resource_id), /tax/parameters (jurisdiction), /tax/profiles, /tax/allowance_orders, /tax/statement_snapshots and /tax/trim_budget (holder, institution) answer a text filter longer than 255 characters, carrying a control character or not a string with 422 naming it; both used to reach the database and fail with a 500 (E25 S4, F70, G24)",
        "PUT /api/v1/securities/:security_id/quotes (portfolixir.quotes.upsert) answers a batch that names one date twice with 422 on date naming that date, and a row that is not an object with 422 on quotes, and writes nothing; both used to answer 500 (E25 S4, F13)",
        "PUT /api/v1/views/:id/buckets (portfolixir.views.set_buckets) counts a bucket named twice in include or exclude once; it used to answer 500 (E25 S4, F12)",
        "PUT /api/v1/portfolios/:portfolio_id/targets (portfolixir.targets.set) answers a batch that names one category row twice with 422 (errors.detail names the category), and a batch longer than one row per category and one per security assigned in the classification, or than 10000 rows, with 422 on targets, and writes nothing; the MCP schema carries maxItems 10000 (E25 S4, G11)",
        "PUT /api/v1/portfolios/:portfolio_id/targets, PUT .../cash_target and POST/PATCH /api/v1/portfolios with cash_target_weight (portfolixir.targets.set, the cash-target tool, portfolixir.portfolios.create) answer 422 on the weight for more than 6 decimal places, and the database refuses such a weight on every writer (on an instance that already held a finer weight when upgraded, the changesets alone refuse it, and a duplicate or a SOLL save rounds the stored weight half up to 6 places). GET /api/v1/portfolios/:portfolio_id/allocation (portfolixir.portfolios.allocation) answers drift_value and rebalance_quantity null for a position valued at 0 without its own target (it used to answer a signed zero) and, with the position rows, carries computation_basis (the drift share's basis and the gaps where it is null) (E25 S4, G14)",
        "POST /api/v1/classifications/:classification_id/categories and PATCH .../categories/:id (portfolixir.classifications.categories.create, .update) answer 422 on parent_id for a parent from another classification, and PATCH for the category itself or one of its descendants as its parent, and write nothing; both used to store a tree that loops (E25 S4, F11)",
        "GET /api/v1/portfolios/:portfolio_id/risk (portfolixir.portfolios.risk) caps top_n at 1000 and echoes the applied top_n (10 when absent); the MCP schema carries maximum 1000. metrics.correlations covers at most the 20 leading names of the Top-N list and carries leading_names, how many it ran over, and metrics.computation_basis.input_series states the bound; both used to grow with an unbounded top_n (E25 S4, F72)",
        "POST /api/v1/splits/preview and POST /api/v1/splits (portfolixir.splits.preview, .create) answer 422 on ratio when the security's splits, each counted by its own magnitude, would multiply past 10^12 with the new one included, and write nothing. The performance reads' irr (and mwr) are null when an amount lies outside the range the solver's one float step carries, and computation_basis.gaps names why irr can be null; such a read used to fail with a 500 (E25 S4, G12)",
        "POST /api/v1/securities/:security_id/isin-change (portfolixir.securities.isin_change) answers 422 on new_isin when its check digit does not agree, as well as for the shape. PATCH /api/v1/securities/:id (portfolixir.securities.update) answers 422 naming the field for an isin, wkn or ticker_symbol it changes that fails the catalog's rules: an ISIN of the shape with a check digit that agrees, a WKN of six letters or digits, a ticker of printable ASCII; resending the stored value is no change, and POST /api/v1/securities keeps what a new security is created with. POST and PATCH store a security's name without Unicode format characters (E25 S5, G23)",
        "PUT /api/v1/securities/:security_id/quotes (portfolixir.quotes.upsert) stores every row as manual whatever source it names, and the MCP schema offers source manual only and lets it be omitted; the write is journaled under the token (resource_type security_quotes, filed under the security's id, operation upsert) with the stored rows it replaced as the before-image, and the answer carries replaced, the ISO dates whose stored row the write changed, beside upserted; a call that changes nothing writes no journal entry. It used to store the named source and replace a provider close with no trace (E25 S6, F20, G27, T-9)",
        "POST /api/v1/securities/:security_id/quotes/release (portfolixir.quotes.release) takes from and to (both required, inclusive) and removes the security's manual quotes in the range, journaled (operation delete) with the released rows as the before-image, answering {security_id, from, to, released}; provider rows stay, and the next quote sync stores the provider's close for a released date. A missing or invalid date answers 422 naming it, to before from 422 on to, an unknown security 404. Agent-first: its control on the security page lands no later than Sprint 17 (E25 S6, T-9)",
        "POST /api/v1/securities/:security_id/notes (portfolixir.notes.append) answers 422 on as_of for a date after the instance's calendar day and appends nothing; valid_until and time_stop may still lie in the future. GET /api/v1/notes/unreviewed (portfolixir.notes.unreviewed) and the thesis_state's last_reviewed_at count an entry as a review no later than the day after it was written, so a stored future as_of cannot keep a position off the review read (E25 S6, F44)",
        "POST /api/v1/securities/:security_id/events and PATCH /api/v1/security_events/:id (portfolixir.events.create, .update) answer 422 on checked_at for a date later than tomorrow (the instance's calendar day plus one day of zone slack) and write nothing; GET /api/v1/events/stale (portfolixir.events.stale) lists an event whose stored checked_at lies after tomorrow, with a negative days_since_checked (E25 S6, G09)",
        "POST /api/v1/securities/:security_id/notes (portfolixir.notes.append) answers 422 on body past 20000 characters and on invalidation_condition past 10000; POST .../events and PATCH /api/v1/security_events/:id (portfolixir.events.create, .update) on note past 10000; POST /api/v1/portfolios/:portfolio_id/policy_rules and POST /api/v1/policy_rules/:id/versions (portfolixir.policy_rules.create, .add_version) on the version's note past 10000 — characters counted as Unicode code points, a database CHECK of the same cap behind each, and the MCP schemas carry the caps as maxLength. The thesis_state of the security and notes reads loads the current thesis's text only (E25 S6, G01)",
        "Every write of a free-text note or description (portfolios, cash and securities accounts, transactions, securities, classifications, tax profiles, allowance orders and statement snapshots, over the API and their MCP tools) answers 422 naming the field past 10000 characters (a category's description 2000), counted as Unicode code points, with a database CHECK of the same bound behind it; POST /api/v1/securities and PATCH /api/v1/securities/:id (portfolixir.securities.create, .update) answer 422 on attributes when the map as stored, merged with the stored attributes, is past 65536 bytes as compact JSON, and store nothing. A Portfolio Performance import names a row whose note is past the bound. An update that changes nothing writes no row and no journal entry (E25 S6, G02)",
        "POST and PATCH /api/v1/tax/statement_snapshots (portfolixir.tax_snapshots.create, .update) never take source from the body: a recorded statement's source is manual, and the MCP schemas no longer offer it; it used to store a caller's pdf_import (E25 S6, F20)",
        "PATCH /api/v1/policy_rules/:id (portfolixir.policy_rules.rename) takes {\"name\"} only and answers the rule with its versions, none added or changed; journaled under the token with the previous name; allowed on a retired rule; names need not be unique. A blank, missing or non-text name answers 422 on name; a predicate field, a version, the version keys of the rule's read shape (version_in_force, next_version, versions) or the context (view_id, portfolio_id) in the same body answers 422 naming each such field, and nothing is written; any other key is ignored, as on PATCH /api/v1/plans/:id; a rule deleted since it was read answers 404 (ADR-0049 §4 and §8 as amended by the Sprint 16 plan D-6, #872)"
      ],
      removed_endpoints: [],
      removed_tools: []
    },
    %{
      version: 7,
      # The date the batch lands on main; an entry sharing its predecessor's
      # date would be invisible to a poller that read that one (since= is
      # strictly after), so it is never backdated onto Sprint 14's.
      date: ~D[2026-09-24],
      summary:
        "Sprint 15: policy rules as first-class objects (ADR-0049, FR-43, gate B3.6) — the " <>
          "operator's caps, floors and bands over a weight, a drift, the HHI or a portfolio " <>
          "metric, stored as versioned, effective-dated objects: an edit is a new version, a " <>
          "version that has been in force is never changed or deleted, and the standard in " <>
          "force on any date is a read — and the findings read, which evaluates the rules in " <>
          "force today over the figures the product already serves into ok, breached or " <>
          "undetermined (never a pass), with no action on any finding.",
      endpoints: [
        "GET /api/v1/portfolios/:portfolio_id/policy_rules",
        "POST /api/v1/portfolios/:portfolio_id/policy_rules",
        "GET /api/v1/policy_rules/:id",
        "POST /api/v1/policy_rules/:id/versions",
        "POST /api/v1/policy_rules/:id/retire",
        "DELETE /api/v1/policy_rules/:id",
        "GET /api/v1/portfolios/:portfolio_id/policy_findings"
      ],
      tools: [
        "portfolixir.policy_rules.list",
        "portfolixir.policy_rules.get",
        "portfolixir.policy_rules.create",
        "portfolixir.policy_rules.add_version",
        "portfolixir.policy_rules.retire",
        "portfolixir.policy_rules.delete",
        "portfolixir.portfolios.policy_findings"
      ],
      parameters: [
        "GET /api/v1/portfolios/:portfolio_id/policy_rules and portfolixir.policy_rules.list take as_of= (the standard in force on a date), include_retired=, view= (one evaluation context; absent is every context), since= (a rule counts as changed when its row or any version did) and limit=",
        "GET /api/v1/portfolios/:portfolio_id/policy_findings and portfolixir.portfolios.policy_findings take view= (the evaluation context) and status= (a comma-separated set of breached, undetermined, ok; status=breached is the pull-only alarm list); since= deliberately does not apply — findings are a derived projection (#849). An undetermined finding's reason includes unvalued (a subject held but not valued); a drift finding's computation_basis carries drift_basis (full_plan or allocated_portion)",
        "DELETE /api/v1/securities/:id, /classifications/:id, /classifications/:classification_id/categories/:id and /views/:id answer 409 with errors.policy_rules (id, name, status) when a policy rule reads the object (ADR-0049 §8); a view counts as read both as a rule's context and as its subject",
        "The policy-rule reads (portfolixir.policy_rules.list, .get, portfolixir.portfolios.policy_findings) state in their descriptions that a Portfolio Performance re-import does not destroy the policy rules (ADR-0049 §8, #831's lesson)",
        "POST /api/v1/transactions and PATCH /api/v1/transactions/:id (portfolixir.transactions.create, .update) answer 422 on gross_amount when a cross-currency buy's cash differs from settlement_amount + fees + taxes, or a sell's from settlement_amount - fees - taxes, by more than 0.01 (#395); a PATCH that changes none of gross_amount, settlement_amount, fees, taxes and type is not re-checked"
      ],
      removed_endpoints: [],
      removed_tools: []
    },
    %{
      version: 6,
      date: ~D[2026-09-23],
      summary:
        "Sprint 14: the portfolio and view derived metrics (ADR-0047, FR-40) on the one " <>
          "risk read — volatility, maximum drawdown and risk-adjusted return over the " <>
          "TTWROR chain's flow-adjusted factors, and the Top-N correlation matrix converted " <>
          "to the base currency; `required` on every metric of both metric payloads (#838); " <>
          "since= on the row collections a scheduled run polls (#830), deliberately not on " <>
          "the derived projections or the time-derived queues; the re-import guarantee in " <>
          "the descriptions of the reads it protects (#831).",
      endpoints: [],
      tools: [],
      parameters: [
        "GET /api/v1/portfolios/:portfolio_id/risk and portfolixir.portfolios.risk carry metrics (ADR-0047 §3, FR-40): volatility, max_drawdown (peak/trough/recovery dates) and risk_adjusted_return over 30d/90d/365d from the TTWROR chain's flow-adjusted daily return factors, annualized by √365, and correlations — the Top-N names' Pearson matrix converted to the base currency first, each pair with its overlap count, a currency with no rate path listed in excluded; metrics.computation_basis states the basis once. The risk family keeps exactly one endpoint; the view arrives as view=",
        "GET /api/v1/portfolios/:portfolio_id/risk and portfolixir.portfolios.risk take risk_free_rate= (a Decimal fraction, default 0, ADR-0046's fixed-rate bound and daily compounding); a malformed or out-of-bound rate is a 422 naming the field",
        "GET /api/v1/securities/:security_id/metrics and the risk read's metrics carry required on every metric in both states (ADR-0047 §6 as amended, #838): n for sma_n, 20 for volatility and risk_adjusted_return, 2 for max_drawdown and momentum, 1 for distance_to_extremes, 60 per correlation pair; a refused sma_n keeps window null",
        "GET /api/v1/securities/:security_id/notes and portfolixir.notes.list take since= (FR-38, #830): entries appended strictly after it, by inserted_at; thesis_state still derives from the whole log",
        "GET /api/v1/securities/:security_id/events and portfolixir.events.list take since= (#830): rows created or updated strictly after it",
        "GET /api/v1/portfolios/:portfolio_id/targets and /position_targets and portfolixir.targets.list / list_positions take since= (#830): a row counts as changed when it or its plan changed; effective_targets stays whole-plan",
        "The six time-derived queues (/notes/unreviewed, /notes/expiring, /notes/uncorroborated, /events/upcoming, /events/stale, /events/unconfirmed) deliberately ignore since= (D-5): their membership changes because time passes, with no row changing",
        "The eight research-log and security-events tools state the re-import guarantee in their descriptions (#831)"
      ],
      removed_endpoints: [],
      removed_tools: []
    },
    %{
      version: 5,
      date: ~D[2026-09-19],
      summary:
        "Sprint 13: the per-security derived metrics (ADR-0047, FR-39) — moving averages, " <>
          "realized volatility, maximum drawdown, momentum and the distance to the 52-week " <>
          "extremes over the security's own split-adjusted close series, every metric " <>
          "carrying its window and observation count and the payload its computation basis; " <>
          "level (a) reports and carries no signal, rating or action. Security events " <>
          "(ADR-0048, FR-44) — a dated calendar fact that books nothing, tracked for the " <>
          "WHOLE CATALOG rather than the holdings, with the four reads of §5 and the three " <>
          "writes that keep them current.",
      endpoints: [
        "GET /api/v1/securities/:security_id/metrics",
        "GET /api/v1/securities/:security_id/events",
        "POST /api/v1/securities/:security_id/events",
        "PATCH /api/v1/security_events/:id",
        "DELETE /api/v1/security_events/:id",
        "GET /api/v1/events/upcoming",
        "GET /api/v1/events/unconfirmed",
        "GET /api/v1/events/stale"
      ],
      tools: [
        "portfolixir.securities.metrics",
        "portfolixir.events.list",
        "portfolixir.events.create",
        "portfolixir.events.update",
        "portfolixir.events.delete",
        "portfolixir.events.upcoming",
        "portfolixir.events.unconfirmed",
        "portfolixir.events.stale"
      ],
      parameters: [
        "GET /api/v1/realized_gains and portfolixir.cashflow.realized_gains carry trades (the closed round-trips themselves, newest close first) and summary (realized_total, hit_rate, average_holding_period_days, trade_count) beside the annual matrix; the three figures are derived from the same converted set, and computation_basis.summary states their rules — limit= still cuts only the matrix's years (#807)",
        "GET /api/v1/journal and portfolixir.journal.list take limit= through the family's shared parser (#811): absent is the default 100, an oversized value is capped at 1000 and echoed in meta.filters.limit, and zero, a negative or a non-number is a 422 naming the field — the read carried its own identical copy of that parser until now"
      ],
      removed_endpoints: [],
      removed_tools: []
    },
    %{
      version: 4,
      date: ~D[2026-09-15],
      summary:
        "Sprint 11: the limit surface finished (#776) — the four research-log reads, the " <>
          "snapshot list and the three cash-flow roll-ups take a bounded limit on the API and " <>
          "their MCP twins, the trades read records from/to as its bound, every bounded payload " <>
          "of the family echoes the limit it applied; the valuations carry price_date per " <>
          "position and stale_priced_count (#779, #610); the benchmark comparison — the " <>
          "portfolio's own flows replayed into a fixed rate or a flagged security — on both " <>
          "performance scopes (#572, ADR-0046).",
      endpoints: [
        "GET /api/v1/portfolios/:portfolio_id/performance/benchmark",
        "GET /api/v1/views/:view_id/performance/benchmark"
      ],
      tools: [
        "portfolixir.portfolios.benchmark",
        "portfolixir.views.benchmark"
      ],
      parameters: [
        "GET /api/v1/securities/:security_id/notes and portfolixir.notes.list take limit= (default 1000, maximum 10000): the newest entries; thesis_state still derives from the whole log (#776)",
        "GET /api/v1/notes/unreviewed, /notes/uncorroborated and /notes/expiring and their MCP twins take limit= (default 1000, maximum 10000): the most overdue positions, the newest entries, the soonest-expiring entries (#776)",
        "GET /api/v1/snapshots and portfolixir.snapshots.list take limit= (default 1000, maximum 10000): the newest snapshots (#776)",
        "GET /api/v1/realized_gains, /external_flows and /costs and the portfolixir.cashflow.* twins take limit= as a number of years (default 100, maximum 1000): the newest years of the annual matrix, computation_basis.window naming a cut (#776)",
        "GET /api/v1/securities/:security_id/trades and portfolixir.trades.list take no limit: from/to is the bound, stated in the payload's basis (#776)",
        "The eight bounded reads answer the limit they applied as limit in the data envelope; a malformed limit is 422 (#776)",
        "GET /api/v1/portfolios/:portfolio_id/valuation, /views/:view_id/valuation and /holdings/by_security and their MCP twins: every position carries price_date, and the two valuations carry stale_priced_count — quoted positions whose quote is older than the data-quality threshold, retired holdings left out (#779, #610)",
        "GET /api/v1/securities and portfolixir.securities.list take is_benchmark=true|false; the securities read, create and update carry the is_benchmark field (ADR-0046 §1, #572)"
      ],
      removed_endpoints: [],
      removed_tools: []
    },
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
