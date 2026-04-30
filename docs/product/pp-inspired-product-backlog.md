# Portfolixir Product Backlog

Status: draft for story-driven implementation  
Scope: Portfolio-management product planning inspired by established portfolio-tracking workflows, adapted for Portfolixir.

## Purpose

This backlog maps common portfolio-management capabilities into Portfolixir epics and implementation stories.

The goal is not to clone Portfolio Performance 1:1 and not to copy its UI or documentation. The goal is to use proven portfolio-management concepts as a functional reference point, then shape them into a modern, self-hosted Portfolixir product.

Portfolixir should become a self-hosted portfolio analytics and wealth graph platform with transparent calculations, import/export-friendly data handling, and a future path toward API and MCP-based AI-assisted analysis.

## Product principles

- **Self-hosted first:** Portfolixir should work well as a local or private self-hosted web app.
- **Data ownership:** User data should remain exportable and understandable.
- **Transparent calculations:** Positions, cash balances, valuation and later performance metrics should be traceable back to transactions and prices.
- **Ledger-like core:** Portfolio state should be derived from master data, accounts, transactions, prices and FX rates, not manually mutated reports.
- **Import/export friendly and automation-first:** Import and sync flows are primary; manual forms are fallback maintenance.
- **AI/MCP-ready early:** The domain model and API boundaries support read-only AI access safely before late-stage polishing.
- **Modern web UI:** The product should feel like a clean, usable web app, not a desktop clone.
- **No broker execution:** Portfolixir must not place trades or trigger real-money actions.
- **No fake data in production flows:** Demo data may exist only behind explicit dev/test mechanisms.
- **Portfolio boundaries:** A `Portfolio` is a tenant-like workspace, comparable to one Portfolio Performance `.portfolio` file.
- **Portfolio scoping:** Accounts, transactions, and reports are portfolio-scoped.
- **Shared market model:** quotes, FX rates, and market metadata are shared across portfolios where possible.

## Automation-first direction

- Portfolixir is a self-hosted portfolio data hub with import/sync-first ingestion and a strict ledger source of truth.
- Core workflows start with automated intake (connector, document inbox, PP XML preview/confirm), while manual forms remain fallback paths.
- Read-only API/MCP analysis access is part of early architecture and remains non-mutating.

## Current foundation

Current model notes:

- Portfolio records already exist.
- Deposit accounts and securities accounts include `portfolio_id` and are currently listable per portfolio.
- Catalog securities are currently global.
- The account workspace currently defaults to the first portfolio in the database (implicit current context).

### PFX-015D: Add explicit current portfolio selection

As a user with multiple portfolios, I want to explicitly choose the current portfolio, so account and future ledger workflows do not accidentally use a hidden fallback.

- Add explicit current-portfolio selection state in the UI/application context.
- Make account pages use the selected portfolio consistently.
- Keep single-portfolio startup behavior stable.
- Keep shared market/currency/security references reusable across portfolios.

## Near-term strategy

The repository currently has early support for:

- Phoenix/LiveView application shell
- root route `/`
- securities page
- taxonomies/categories page
- currencies
- securities
- taxonomies/categories
- security/category assignments
- Docker Compose development workflow
- health endpoint
- official Portfolixir branding assets

This backlog starts the next implementation sequence at `PFX-009`.

---

# Feature map

## A. App shell and navigation

Capabilities:
- Product shell with stable root route
- Left sidebar navigation
- Light/dark theme
- Branded app shell
- Future i18n
- Page-level headers and consistent content sections
- Usable default route

Near-term stories:
- Improve All Securities UX
- Move heavy inline CSS out of the component later
- Prepare navigation for Accounts, Transactions, Reports and Imports

Non-goals for now:
- Complex dashboard
- Highly polished design system
- i18n implementation beyond simple naming readiness

## B. Master data

Capabilities:
- Securities
- Currencies
- Exchanges
- Security identifiers: symbol, ISIN, WKN, provider symbol, exchange code
- Security notes/descriptions
- Active/inactive status
- Data quality validation

Near-term stories:
- Better All Securities table
- Edit securities
- Archive/delete securities
- Active/inactive state
- CSV export/import for securities

## C. Accounts

Capabilities:
- Securities accounts / depots
- Deposit/cash accounts
- Account currency
- Reference account relationship
- Account balances derived from transactions
- Optional account notes
- Active/inactive state

Near-term stories:
- Create deposit accounts
- Create securities accounts
- Link securities account to reference deposit account
- List accounts
- Edit/archive accounts

## D. Taxonomies and classifications

Capabilities:
- Taxonomies
- Categories
- Category hierarchy
- Security-category assignments
- Optional assignment weights
- Target allocation
- Allocation report
- Deviation from target allocation

Near-term stories:
- Show categories assigned to a security
- Assign/unassign categories from security detail
- Allocation report after holdings are available
- Target weights after transaction-based holdings exist

## E. Transactions

Capabilities:
- Buy
- Sell
- Dividend
- Deposit
- Withdrawal
- Fees
- Taxes
- Inbound delivery
- Outbound delivery
- Transfers between cash accounts
- Transfers between securities accounts
- All transactions list
- Transaction correction model

Design principle:
Transactions are immutable or ledger-like. Editing a transaction should be implemented carefully, with auditability in mind. Reports derive from transactions; reports must not mutate state.

## F. Positions and valuation

Capabilities:
- Holdings calculated from transaction history
- Cash balances calculated from transaction history
- Latest quote per security
- Manual quote entry
- Historical prices later
- Portfolio value in base currency
- FX conversion
- Position cost basis
- Realized and unrealized gains later

## G. Imports and exports

Capabilities:
- CSV export
- CSV import preview
- Import mapping (including connector and document source metadata)
- Import hub and raw payload queue
- Local document inbox
- Raw import storage
- Broker statement intake via connector candidates
- Portfolio Performance XML import
- Repeatable import jobs with deduplication

## H. Reports and analytics

Capabilities:
- Statement of assets / holdings table
- Allocation by taxonomy
- Performance overview
- Performance by security
- Payments/dividends
- Realized gains/losses
- Cash flow report
- IRR/TTWROR later
- Charting later

## I. Operations and quality

Capabilities:
- Docker Compose development workflow
- Health endpoint
- Tests for each story
- Seed/dev data only for dev
- Auditability
- Backup/export guidance
- CI later
- Domain documentation
- Import contract documentation

---

# MVP release plan

## Phase 0: Foundation already done

Already available:
- Phoenix/LiveView foundation
- Docker Compose development setup
- health endpoint
- currencies
- taxonomies/categories
- securities
- security/category assignments
- branded product shell
- `/` route to securities view
- `/securities`
- `/taxonomies`

## Phase 1: Make securities usable

Goal: Securities become real master data, not a raw prototype form.

Stories:
- PFX-009 Clean up All Securities page and table
- PFX-010 Edit existing security
- PFX-011 Delete or archive security
- PFX-012 Add active/inactive status to securities
- PFX-013 CSV export for securities
- PFX-014 CSV import preview for securities

Exit criteria:
- A user can add, view, edit and archive securities.
- The table is useful enough for daily work.
- Securities can be exported.
- CSV import has a safe preview path.

## Phase 2: Accounts and transactions

Goal: Start building the ledger model with import-first ingestion.

Stories:
- PFX-AUTO-001 Import Domain Foundation
- PFX-CONN-001 Connector Behaviour
- PFX-AUTO-003 Local Document Inbox
- PFX-PP-001 Portfolio Performance XML Preview
- PFX-PP-002 Portfolio Performance XML Import Confirmation
- PFX-015 Create deposit accounts
- PFX-016 Create securities accounts
- PFX-017 Link securities account to reference deposit account
- PFX-018 Record buy transaction
- PFX-019 Record sell transaction
- PFX-020 All transactions list
- PFX-021 Record deposit and withdrawal
- PFX-022 Record dividend
- PFX-023 Record fees and taxes

Exit criteria:
- Users can begin with import/sync workflows before manual transaction entry.
- A user can model a depot and reference cash account.
- A user can record basic buy/sell/dividend/cash movements.
- Transactions are listed and traceable.

## Phase 3: Holdings and portfolio value

Goal: Derive current portfolio state from transactions.

Stories:
- PFX-024 Calculate security positions from transactions
- PFX-025 Calculate cash balances from transactions
- PFX-026 Manual latest quote entry
- PFX-AUTO-002 Read-only Portfolio API
- PFX-027 Holdings report
- PFX-028 Portfolio valuation snapshot

Exit criteria:
- Holdings are not manually entered; they are calculated.
- Cash balances are derived.
- Portfolio value can be calculated from latest quotes.

## Phase 4: Classification and allocation

Goal: Make the portfolio understandable by strategy/category.

Stories:
- PFX-ETF-001 Fund Allocation Model
- PFX-029 Show assigned categories on securities
- PFX-030 Manage security-category assignments in UI
- PFX-031 Add target weights to category assignments
- PFX-032 Allocation report by taxonomy
- PFX-033 Allocation deviation report

Exit criteria:
- Securities can be classified.
- Current allocation is visible.
- Target deviation can be reviewed.

## Phase 5: Imports and automation

Goal: Reduce manual work.

Stories:
- PFX-034 Transaction CSV import preview
- PFX-035 Transaction CSV import confirmation
- PFX-036 Quote provider behaviour and manual provider
- PFX-037 External quote provider integration
- PFX-038 API/MCP readiness notes and read-only endpoints

Exit criteria:
- Imports have preview/confirm workflow.
- Quote fetching is abstracted.
- Read-only API path has hardening notes and auditability.

---

# Implementation stories

## PFX-AUTO-001: Import Domain Foundation

### User story
As a system, I want standardized import domain records (source, batch, staging, mapping state), so imports are auditable and replayable before they mutate the ledger.

### Acceptance criteria
- Import domain entities (source, batch, staged payload, preview result) are represented in domain documentation.
- Manual and automated ingestion share a single raw-to-staging path.
- Reprocessing the same input can be detected and handled without duplicate writes.
- Import previews never persist financial rows directly.
- Tests include one valid and one malformed fixture path.

### Notes / non-goals
- Not an end-user UI rewrite.
- No connector execution or payment actions in this foundation story.
- No broker order placement.

## PFX-AUTO-002: Read-only Portfolio API

### User story
As a user, I want read-only access surfaces for portfolio data so AI tools can analyze safely without the ability to place actions.

### Acceptance criteria
- API/MCP contract prioritizes read-only endpoints for portfolio, positions, and valuation snapshots.
- Endpoints include explicit non-mutating guarantees.
- Auth assumptions and trust boundaries are documented.
- Tests include read-path shape checks and explicit write-path rejection/guard coverage.

### Notes / non-goals
- No write-capable LLM/MCP actions.
- No broker/banking/trading execution controls.

## PFX-AUTO-003: Local Document Inbox

### User story
As a user, I want local document uploads to land in a queue with processing state, so imports start from structured evidence.

### Acceptance criteria
- Users can store local documents into a local inbox.
- Stored document records include source, parser hint, status and timestamps.
- Import queue can be previewed before processing.
- Tests cover document ingestion and queue state transitions.

### Notes / non-goals
- No external write callbacks.
- No automatic funds movement.

## PFX-PP-001: Portfolio Performance XML Preview

### User story
As a user, I want PP XML parsed into a reviewable preview, so I can validate what will be imported.

### Acceptance criteria
- PP XML parsing can produce a preview report from a sample PP file.
- Preview includes row-level or section-level validation warnings.
- No ledger writes happen in preview mode.
- Deterministic fixture-based tests verify recognized and rejected XML patterns.

### Notes / non-goals
- No provider credentials or broker authentication required.
- No write actions in preview mode.

## PFX-PP-002: Portfolio Performance XML Import Confirmation

### User story
As a user, I want a confirm step for PP XML parsed data, so imported rows are only written after approval.

### Acceptance criteria
- Confirm converts validated PP XML staging rows into transactions or normalized import artifacts.
- Replays/double-submit are safe and idempotent.
- Import summary shows inserted, skipped and invalid counts.
- Tests cover confirmed and blocked import confirmation flows.

### Notes / non-goals
- No auto-posting to external systems.
- No real-money effects.

## PFX-CONN-001: Connector Behaviour

### User story
As a developer, I want a connector behaviour contract, so additional sync sources can be added without rewriting the import core.

### Acceptance criteria
- A clear connector contract defines pull/normalize/progress behavior.
- Connector errors and partial failures are represented in import status.
- Tests use test doubles and avoid live network calls.
- Documentation includes required metadata for new connectors.

### Notes / non-goals
- Not a broker-execution integration layer.
- No direct write APIs in connector scope for MVP.

## PFX-ETF-001: Fund Allocation Model

### User story
As a user with ETF-heavy holdings, I want allocation model support for fund/ETF categories, so classification remains meaningful.

### Acceptance criteria
- ETF/fund classification rules are representable in the taxonomy model.
- Allocation report can reflect ETF-level grouping and edge cases.
- Tests define deterministic mappings and coverage for missing mapping rules.

### Notes / non-goals
- No rebalance execution.
- No automatic trading recommendations.

## PFX-009: Clean up All Securities page and table

### User story
As a user, I want the All Securities page to show my securities in a clear table with a focused add flow, so that the page feels like a usable product screen instead of a raw prototype form.

### Acceptance criteria
- `/` and `/securities` render a page titled `All Securities`.
- The securities list/table is the primary content.
- The empty state is visible when no securities exist:
  - Title: `No securities yet`
  - Text: `Add your first security to start building your portfolio.`
- The add-security form is visually secondary or collapsible.
- Existing create security functionality still works.
- No fake sample securities are added.
- Tests cover empty state and at least one created security row.

### Notes / non-goals
- Do not implement search yet.
- Do not implement edit/delete in this story.
- Avoid spending too much time on high-end design polish.

### Suggested implementation scope
- Refactor `SecurityManagementLive.render/1`.
- Add simple table structure and empty state.
- Keep form event handling as-is where possible.
- Add or update LiveView tests.

## PFX-010: Edit existing security

### User story
As a user, I want to edit a security, so that I can correct names, identifiers, exchange code or notes after creation.

### Acceptance criteria
- Each security row has an edit action.
- Editing allows changing name, symbol, ISIN, WKN, exchange code, provider symbol and notes.
- Validation errors are shown.
- Existing unique constraints remain enforced.
- Tests cover successful edit and validation failure.

### Notes / non-goals
- Do not implement audit history yet.
- Do not implement bulk edit.
- If changing currency would conflict with transactions later, document future restriction but allow it for now if no transactions exist.

### Suggested implementation scope
- Add LiveView edit state.
- Reuse `Catalog.update_security/2`.
- Add tests in `security_management_live_test.exs`.

## PFX-011: Delete or archive security

### User story
As a user, I want to remove or archive securities that I no longer use, so that my list stays clean.

### Acceptance criteria
- A security can be archived or deleted depending on current schema capability.
- The preferred MVP behavior is archive if transactions exist later, delete only if safe.
- For now, if no transactions exist, deleting a security is allowed.
- User gets a clear confirmation or safe action flow.
- Tests cover removal from list.

### Notes / non-goals
- Do not implement complex dependency analysis yet.
- Do not hard-delete data once transactions depend on it in future stories.

## PFX-012: Add active/inactive status to securities

### User story
As a user, I want to mark a security as inactive, so that old holdings do not clutter active workflows while history remains intact.

### Acceptance criteria
- Securities have an `active` boolean defaulting to true.
- All Securities page shows active securities by default.
- There is a way to include inactive securities.
- Inactive securities are visually distinguishable.
- Tests cover default active behavior and inactive filtering.

### Notes / non-goals
- Do not delete transaction history.
- Do not implement complex lifecycle statuses.

## PFX-013: CSV export for securities

### User story
As a user, I want to export securities as CSV, so that I can back up or inspect my master data outside Portfolixir.

### Acceptance criteria
- A CSV export endpoint/action exists for securities.
- Export contains name, symbol, currency_code, isin, wkn, exchange_code, provider_symbol, notes and active if available.
- CSV has a header row.
- Tests cover response status, content type and sample content.

### Notes / non-goals
- Do not export transactions in this story.
- Do not implement custom column selection yet.

## PFX-014: CSV import preview for securities

### User story
As a user, I want to upload or paste a securities CSV and preview parsed rows before import, so that I can avoid bad imports.

### Acceptance criteria
- User can provide CSV input for securities.
- Parsed rows are shown in preview.
- Validation errors are shown per row.
- No database write happens during preview.
- Tests cover valid preview and invalid row preview.

### Notes / non-goals
- Do not confirm/import in this story unless very small.
- Do not implement broker-specific import formats.

## PFX-015: Create deposit accounts

### User story
As a user, I want to create cash/deposit accounts, so that cash movements and dividends have a place in the model.

### Acceptance criteria
- A `deposit_accounts` or generic `accounts` model supports cash accounts.
- Fields include name, currency_code, active and notes.
- Accounts page lists accounts.
- Tests cover create/list validation.

### Notes / non-goals
- No transaction balance calculation yet.
- No bank connection.

## PFX-016: Create securities accounts

### User story
As a user, I want to create securities accounts/depots, so that buy/sell transactions can be assigned to a depot.

### Acceptance criteria
- A securities account can be created.
- Fields include name, currency_code or base currency behavior, active and notes.
- Securities accounts are listed in Accounts UI.
- Tests cover create/list validation.

### Notes / non-goals
- No positions yet.
- No broker integration.

## PFX-017: Link securities account to reference deposit account

### User story
As a user, I want a securities account to reference a cash account, so that buys, sells and dividends can affect the correct cash balance later.

### Acceptance criteria
- A securities account can have a reference deposit account.
- Reference account must exist.
- UI shows the relationship.
- Tests cover valid and invalid references.

### Notes / non-goals
- Do not automatically move cash yet.
- Do not implement transfers yet.

## PFX-018: Record buy transaction

### User story
As a user, I want to record a buy transaction, so that Portfolixir can later calculate holdings and cash impact.

### Acceptance criteria
- A buy transaction can be recorded with date, securities account, security, quantity, price, fees, taxes and currency.
- Transaction is persisted.
- Validation prevents missing required fields and non-positive quantity.
- Tests cover successful buy and validation failure.

### Notes / non-goals
- Do not calculate holdings report yet unless trivial.
- Do not support multi-currency settlement complexity in this story.

## PFX-019: Record sell transaction

### User story
As a user, I want to record a sell transaction, so that reductions in holdings and proceeds can be modeled.

### Acceptance criteria
- A sell transaction can be recorded with similar fields as buy.
- Validation prevents non-positive quantity.
- Optional validation warns or prevents selling more than held if positions are already implemented; otherwise document future behavior.
- Tests cover successful sell and validation failure.

### Notes / non-goals
- No realized gain/loss calculation yet.
- No FIFO/LIFO/tax lot logic yet.

## PFX-020: All transactions list

### User story
As a user, I want to see all transactions in one list, so that I can audit what has been recorded.

### Acceptance criteria
- `/transactions` route exists.
- Transactions are listed newest-first.
- List shows date, type, account, security where applicable, quantity, amount and currency.
- Empty state exists.
- Tests cover route, empty state and one listed transaction.

### Notes / non-goals
- No advanced filtering yet.
- No edit/delete yet.

## PFX-021: Record deposit and withdrawal

### User story
As a user, I want to record deposits and withdrawals on cash accounts, so that cash balances can be derived.

### Acceptance criteria
- Deposit transaction can be recorded.
- Withdrawal transaction can be recorded.
- Fields include date, deposit account, amount, currency and note.
- Tests cover both transaction types.

### Notes / non-goals
- No bank sync.
- No recurring payments yet.

## PFX-022: Record dividend

### User story
As a user, I want to record dividends for a security, so that investment income is tracked.

### Acceptance criteria
- Dividend transaction can be recorded.
- Fields include date, security, account, gross amount, taxes, currency and optional notes.
- Transaction is listed in All Transactions.
- Tests cover successful dividend.

### Notes / non-goals
- No dividend analytics yet.
- No withholding-tax optimization logic.

## PFX-023: Record fees and taxes

### User story
As a user, I want to record standalone fees and taxes, so that portfolio cash movements are complete.

### Acceptance criteria
- Fee transaction can be recorded.
- Tax transaction can be recorded.
- Transactions are assigned to cash account and optionally security.
- Tests cover both types.

### Notes / non-goals
- No tax reporting.
- No country-specific tax calculation.

## PFX-024: Calculate security positions from transactions

### User story
As a user, I want Portfolixir to calculate my holdings from buy and sell transactions, so that positions are transparent and reproducible.

### Acceptance criteria
- A position calculation module exists.
- Positions are grouped by securities account and security.
- Buy increases quantity.
- Sell decreases quantity.
- Tests cover simple buy, buy+sell and multiple securities.

### Notes / non-goals
- No cost basis method yet.
- No short selling unless explicitly supported later.

## PFX-025: Calculate cash balances from transactions

### User story
As a user, I want cash balances to be calculated from cash-related transactions, so that account balances are not manually maintained.

### Acceptance criteria
- Cash balance calculation module exists.
- Deposits increase cash.
- Withdrawals decrease cash.
- Buy decreases cash if cash impact is represented.
- Sell/dividend increase cash if represented.
- Tests cover simple cash flows.

### Notes / non-goals
- No multi-currency FX conversion yet.
- No bank account sync.

## PFX-026: Manual latest quote entry

### User story
As a user, I want to enter a latest quote manually, so that portfolio valuation can work before automated market data exists.

### Acceptance criteria
- A quote can be stored for a security.
- Fields include security, price, currency, date/time and source = manual.
- Latest quote per security can be retrieved.
- Tests cover create and latest lookup.

### Notes / non-goals
- No external provider yet.
- No historical price import yet.

## PFX-027: Holdings report

### User story
As a user, I want a holdings report, so that I can see current quantities and latest valuation per security.

### Acceptance criteria
- `/reports/holdings` route exists or holdings are shown on a reports page.
- Report includes security, quantity, latest price if available, value if available and currency.
- Empty state exists.
- Tests cover report from simple transactions.

### Notes / non-goals
- No performance metrics yet.
- No charts yet.

## PFX-028: Portfolio valuation snapshot

### User story
As a user, I want to see the latest total portfolio value, so that I know the current approximate value of my holdings and cash.

### Acceptance criteria
- Portfolio value combines holdings and cash balances.
- Securities without latest quote are clearly marked as missing valuation.
- Tests cover total value calculation with one security and one cash account.

### Notes / non-goals
- No historical valuation curve yet.
- No FX conversion unless required by already implemented fields.

## PFX-029: Show assigned categories on securities

### User story
As a user, I want to see categories assigned to each security, so that I understand portfolio classification at a glance.

### Acceptance criteria
- All Securities table shows assigned categories or a compact indicator.
- Security detail/edit area shows assigned categories.
- Tests cover displayed assigned category.

### Notes / non-goals
- No allocation report yet.
- No target weights in this story.

## PFX-030: Manage security-category assignments in UI

### User story
As a user, I want to assign and unassign categories from securities, so that classifications can be maintained without direct database work.

### Acceptance criteria
- User can assign category to a security.
- Duplicate assignment is rejected or disabled.
- User can remove assignment.
- Tests cover assign/remove and duplicate behavior.

### Notes / non-goals
- No target weights yet unless already present.
- No bulk assignment.

## PFX-031: Add target weights to category assignments

### User story
As a user, I want to assign target weights to classifications, so that later allocation reports can compare current versus desired allocation.

### Acceptance criteria
- Assignment weight can be set.
- Weight defaults to `1.0`.
- Validation prevents negative weight.
- Tests cover default and custom weight.

### Notes / non-goals
- No automatic rebalancing actions.
- No trading recommendations.

## PFX-032: Allocation report by taxonomy

### User story
As a user, I want to see current portfolio allocation by taxonomy/category, so that I understand how my portfolio is distributed.

### Acceptance criteria
- User can select taxonomy.
- Report groups portfolio value by category.
- Unclassified securities are shown as unclassified.
- Tests cover simple allocation calculation.

### Notes / non-goals
- No charts required.
- No target deviation yet.

## PFX-033: Allocation deviation report

### User story
As a user, I want to compare current allocation with target allocation, so that I can identify drift.

### Acceptance criteria
- Report shows current percentage, target percentage and deviation.
- Missing targets are clearly handled.
- Tests cover over/under target categories.

### Notes / non-goals
- No automatic rebalance proposal.
- No broker actions.

## PFX-034: Transaction CSV import preview

### User story
As a user, I want to preview transaction CSV imports, so that I can validate data before writing to the ledger.

### Acceptance criteria
- User can paste or upload CSV transaction data.
- Preview shows parsed rows.
- Validation errors are row-level.
- No writes happen during preview.
- Tests cover valid and invalid input.

### Notes / non-goals
- No broker-specific mappings yet.
- No automatic duplicate detection yet.

## PFX-035: Transaction CSV import confirmation

### User story
As a user, I want to confirm a validated transaction import, so that rows are written only after review.

### Acceptance criteria
- Valid preview can be confirmed.
- Transactions are created in a single controlled operation.
- Invalid preview cannot be confirmed.
- Import result summary is shown.
- Tests cover successful confirm and blocked invalid confirm.

### Notes / non-goals
- No background jobs yet.
- No broker PDF import.

## PFX-036: Quote provider behaviour and manual provider

### User story
As a developer, I want market data behind a provider behaviour, so that external quote providers can be added without coupling tests to external APIs.

### Acceptance criteria
- Provider behaviour is defined.
- Manual/local provider exists for tests.
- Tests do not call external APIs.
- Documentation explains provider contract.

### Notes / non-goals
- No real external provider in this story.
- No API keys.

## PFX-037: External quote provider integration

### User story
As a user, I want Portfolixir to fetch quotes from an external provider, so that manual quote entry is not required forever.

### Acceptance criteria
- Provider can fetch current quote for configured symbols.
- Errors are handled and visible.
- Tests mock external calls.
- No tests depend on live external services.

### Notes / non-goals
- Provider choice is an architecture decision before implementation.
- Avoid paid-only providers for MVP if possible.

## PFX-038: API/MCP readiness notes and read-only endpoints

### User story
As a user, I want Portfolixir to expose clean read-only data endpoints later, so that AI agents can analyze my portfolio safely.

### Acceptance criteria
- Document API/MCP design principles.
- Add first read-only JSON endpoints if product data model is stable enough.
- Endpoints do not mutate state.
- Tests cover auth assumptions or explicitly document no-auth dev-only state.

### Notes / non-goals
- No write-enabled AI agent tools.
- No real-money actions.

---

# Architecture notes

## Securities are master data

Securities represent instruments such as stocks, ETFs, funds, bonds or crypto-like instruments if supported later. They should be stable records referenced by transactions and prices.

## Accounts hold cash or securities

The account model should support cash/deposit accounts, securities accounts/depots and a reference cash account relationship. Avoid embedding balances directly as primary state. Balances should be derived from transactions.

## Transactions are ledger-like records

Transactions should be treated as the primary history of portfolio activity.

Design rules:
- Prefer immutability or auditable updates.
- Preserve enough information to recalculate derived state.
- Use Decimal for money and quantities.
- Reports derive from transactions.

## Reports do not mutate state

Reports should read master data, transactions, prices and FX rates. They should not change portfolio data.

## Imports use preview/confirm

Imports should follow:
1. load raw input
2. parse
3. validate
4. preview
5. confirm
6. persist
7. summarize

This prevents accidental database pollution.

## External quote providers are abstracted

Market data should be behind behaviours/adapters so tests can run without live network calls and providers can be replaced later.

---

# Non-goals

- No broker order execution.
- No real-money trading.
- No direct banking write actions.
- No write-capable LLM/MCP tools.
- No direct payment execution or wallet-like action flows.
- No automatic rebalance execution.
- No complex IRR/TTWROR calculations before the transaction model is solid.
- No Portfolio Performance XML import in early MVP unless explicitly reprioritized.
- No UI clone of Portfolio Performance.
- No broker PDF parsing in early MVP.
- No external market-data calls inside tests.
- No fake/demo data in production flows.
