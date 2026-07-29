---
layout: docs
title: Architecture Decisions
description: Lightweight ADR log for Portfolixir architecture decisions.
---

# Architecture Decisions

This is the Architecture Decision Record (ADR) log for Portfolixir. Each ADR
captures one decision, the context that forced it, and its consequences.
[`AGENTS.md`](https://github.com/peshay/portfolixir/blob/main/AGENTS.md)
requires that architecture decisions not change silently: when a decision
changes, add a new ADR and mark the old one as superseded rather than editing
history.

The records below were written after the fact to document decisions that were
already in force in the codebase.

## How to add an ADR

1. Copy [the template](0000-adr-template.html) to
   `docs/decisions/NNNN-short-title.md` with the next number.
2. Fill in context, decision, and consequences. Keep it short.
3. Set the status to `Accepted` and add it to the list below.
4. To reverse a decision, add a new ADR and set the old one's status to
   `Superseded by ADR-NNNN`.

## Records

| ADR | Title | Status |
| --- | --- | --- |
| [0001](0001-modular-phoenix-monolith.html) | Modular Phoenix monolith with bounded contexts | Accepted |
| [0002](0002-thin-mcp-over-json-api.html) | Thin MCP companion over the JSON API only | Accepted |
| [0003](0003-decimal-for-money.html) | Decimal for all financial values | Accepted |
| [0004](0004-holdings-derived-from-transactions.html) | Holdings and trades derived from transaction history | Accepted |
| [0005](0005-quote-provider-split.html) | Split quote providers: search vs. history | Accepted |
| [0006](0006-classifications-with-target-weights.html) | Classifications (taxonomies) with built-in derived trees | Accepted |
| [0007](0007-currency-conversion-with-exchange-rates.html) | Currency conversion with exchange rates | Accepted |
| [0008](0008-target-weights-and-allocation.html) | Target weights and target/actual allocation | Accepted |
| [0009](0009-cash-as-balance-snapshots.html) | Cash as balance snapshots, not a mirrored ledger | Accepted |
| [0010](0010-ttwror-performance-series.html) | Daily valuation series and TTWROR | Accepted |
| [0011](0011-unified-ledger-projection.html) | Unified ledger projection (single per-kind reducer) | Accepted |
| [0012](0012-asset-class-inference-at-read-time.html) | Asset class inference at read time | Accepted |
| [0013](0013-exclude-securities-from-allocation-targets.html) | Exclude flagged securities from the allocation steering basis | Superseded by [0018](0018-buckets-tag-based-wealth-scoping.html) |
| [0014](0014-bilingual-docs-site.html) | Bilingual docs site (EN baseline, DE alongside) without a custom Pages build | Accepted |
| [0015](0015-cross-currency-settlement-fx-rate.html) | Cross-currency transaction settlement with a stored FX rate | Accepted |
| [0016](0016-rounding-policy.html) | Rounding policy — full precision in compute, round only at the human display | Accepted |
| [0017](0017-append-only-audit-journal.html) | Append-only audit journal for financial writes | Accepted |
| [0018](0018-buckets-tag-based-wealth-scoping.html) | Buckets — tag-based wealth scoping with view filters | Accepted |
| [0019](0019-view-scoped-performance-boundary-flows.html) | View-scoped performance treats boundary transfers as external flows | Accepted |
| [0020](0020-view-bound-soll-plans.html) | target plans belong to a view | Accepted |
| [0021](0021-pdf-transaction-intake.html) | In-app broker-PDF transaction intake (sandboxed, text-only) | Accepted |
| [0022](0022-task-oriented-information-architecture.html) | Task-oriented UI information architecture | Accepted |
| [0023](0023-drift-sign-and-display-only-rebalancing-hints.html) | Drift sign convention and display-only rebalancing hints | Accepted |
| [0024](0024-buckets-and-views-replace-portfolios-in-the-ui.html) | Buckets and views replace portfolios as the user-facing grouping | Accepted |
| [0025](0025-automation-recipes-boundary.html) | Automation recipes — docs in the repo, broker scripts outside | Accepted |
| [0026](0026-epic-batch-workflow.html) | Epic-batch workflow — humans review decisions and behavior | Accepted |
| [0027](0027-plan-versions-and-depot-snapshots.html) | Named plan versions and ledger-marker depot snapshots | Accepted |
| [0028](0028-corporate-actions-as-ledger-events.html) | Corporate actions as ledger events — splits as a first-class kind | Accepted |
| [0029](0029-stable-identities-and-reimport-survival.html) | Stable identities and re-import survival — identity ladder with ISIN-change aliases | Accepted |
| [0030](0030-position-level-soll-targets.html) | Position-level SOLL targets — positions as source of truth, categories as derived roll-up | Accepted |
| [0031](0031-recorded-tax-statement-snapshots.html) | Recorded tax-statement snapshots — capture the broker's tax pots, never derive them | Accepted |
