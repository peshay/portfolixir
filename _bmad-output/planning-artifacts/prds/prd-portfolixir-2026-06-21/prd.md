---
title: "PRD — Data Import & Sync"
project: portfolixir
status: draft
created: 2026-06-21
updated: 2026-06-21
owner: Andi
mode: fast-path
---

# PRD — Data Import & Sync

> Short, focused PRD for the intake domain. Capabilities only; mechanism/tech
> notes live in `addendum.md`. `[ASSUMPTION]` marks inferred items to confirm.

## 1. Problem & Goal

Portfolixir's value is an auditable local record of holdings derived from
transaction history. Today the only practical way to load real history is via
**Portfolio Performance (PP)** CSV/JSON v1 — Portfolixir rides on PP's export.
That makes PP a hard dependency.

**Goal:** make Portfolixir self-sufficient for getting transaction-grade data in
and back out, so a user can adopt it without PP and eventually migrate off PP
entirely — while staying a local, auditable, decimal-correct tool.

## 2. Strategic context

- **PP is a migration bridge, not the destination.** Long-term we replace it.
- **The hard truth about source data (German banks, e.g. comdirect):** the only
  structured CSV export is an **IST/holdings snapshot** (positions + current
  value). Transaction-grade data — purchase price, shares & date, fees, taxes on
  sale, dividends — is **locked in PDFs** (Wertpapierabrechnung, Steuerreport).
  A generic CSV mapper therefore cannot replace PP for such banks; it only helps
  brokers that export structured trades (IBKR Flex, Trade Republic, Scalable).
- **Owner decision:** the AGENTS "no PDF intake" policy is **under review** —
  in-app PDF parsing is now a candidate capability (see FR-D / §6).

## 3. Users & context

- **Primary:** a single self-hosting investor (Andi) migrating an existing PP
  history, then maintaining it ongoing. `[ASSUMPTION]` solo/local, no multi-user.
- **Secondary:** an **LLM/automation agent** acting on the user's behalf via the
  JSON API / MCP — a first-class intake actor, in line with the LLM-first
  direction.

## 4. Scope

**In scope:** transaction intake (file + API/MCP + manual), holdings-snapshot
intake, own export/backup, market-data sync (quotes + FX, already built),
PP-import hardening as the interim bridge, and an evaluation of in-app PDF intake.

**Out of scope (unchanged policy unless noted):** live broker/bank sync, trading
/orders/payments, external LLM calls *from the app*. `[ASSUMPTION]` multi-user
and non-PP non-PDF document formats remain out for now.

## 5. Capabilities & Requirements

### Feature A — Generic mappable CSV import (structured brokers)
Let a user import an arbitrary broker transaction CSV by mapping its columns to
Portfolixir fields, without per-broker code.

- **FR-1** User uploads any delimited file; the app previews detected
  columns/rows and lets the user map each Portfolixir field (date, type, ISIN/
  WKN/name, shares, price, amount, fees, taxes, currency, account) to a source
  column.
- **FR-2** Mappings are reusable/savable per source so re-imports need no
  re-mapping. `[ASSUMPTION]`
- **FR-3** Preview shows the records that would be created and flags rows that
  fail validation **before** any atomic apply (ties to #482).
- **FR-4** Apply is atomic with content-hash idempotency (re-import = no dupes).

### Feature B — Holdings snapshot import (IST only)
Seed/reconcile current positions from a bank's snapshot CSV, explicitly without
history.

- **FR-5** Import a positions snapshot (security + quantity, optional current
  value) into a portfolio/depot.
- **FR-6** The UI clearly labels snapshot-sourced positions as **no cost basis /
  no P&L** and never silently fabricates transactions.
- **FR-7** Snapshot can be used to **reconcile** against derived holdings and
  surface drift (expected vs. snapshot). `[ASSUMPTION]`

### Feature C — API / MCP write-parity (the push path)
Enable an LLM or script to push transaction-grade data programmatically, so a
PDF can be parsed *outside* the app and the result posted in.

- **FR-8** Every transaction kind creatable in the UI is creatable via the JSON
  API. (relates to #355 / FR-14)
- **FR-9** Equivalent MCP write-tools expose the same operations with decimals as
  strings; idempotency keys supported to make pushes safe to retry.
- **FR-10** Bulk/batch create endpoint so a parsed PDF's many rows post in one
  auditable call. `[ASSUMPTION]`

### Feature D — In-app broker-PDF intake (DECIDED — ADR-0021)
Parse broker PDFs (Wertpapierabrechnung, Steuerreport) into transactions inside
the app. **Decided** in ADR-0021 (Option A): an in-app importer, sandboxed and
text-extraction-only, per-broker, that supersedes the AGENTS "no broker PDF
intake" rule. Feature C (API/MCP push) remains a valid complementary path.

- **FR-11** Parse a comdirect Wertpapierabrechnung PDF into one or more proposed
  transactions (buy/sell with price, fees, taxes, date, shares), shown in the
  same validated preview as other imports before apply (never written silently).
- **FR-12** `[ASSUMPTION]` Parse a dividend/tax statement into dividend + tax
  records.
- **FR-12a** Parsing is sandboxed and text-only: no script/JS execution, no
  embedded-object evaluation, no content-triggered network; size/page/time
  limits; malformed/oversized input rejected safely.
- **FR-12b** Each broker layout is an explicit, tested parser (synthetic
  fixtures only, never real statements); scope grows one broker at a time.
- **Dependency note:** a pure PDF text-extraction library is a reviewed
  dependency decision (no rendering/scripting). See ADR-0021.

### Feature E — Own export + backup/restore (leave-PP)
Make the local data self-contained and portable.

- **FR-13** Full backup/restore of all financial data (relates to #354).
- **FR-14** PP-compatible export so data can round-trip out (relates to #354),
  plus a native Portfolixir export format. `[ASSUMPTION]`

### Feature F — PP import hardening (interim bridge)
Keep the migration path reliable while it's still in use.

- **FR-15** A single invalid record (e.g. zero-amount tax/delivery) never aborts
  the whole atomic import; invalid rows are surfaced in preview with reasons and
  can be skipped (#482).
- **FR-16** `[ASSUMPTION]` Evaluate PP XML full import (#333) for richer master
  data / classifications / quote history.

### Feature G — Market-data sync (existing)
- **FR-17** Quote sync (prices) and FX-rate sync run automatically; this PRD only
  notes robustness follow-ups (rate-limit/backoff, provider coverage), not new
  scope.

## 6. Open decisions

- **OD-1 — RESOLVED (2026-06-21, ADR-0021):** in-app broker-PDF intake is
  adopted (Option A), sandboxed/text-only/per-broker, superseding the AGENTS
  rule. Feature D is now decided, not a candidate.
- **OD-2:** Verify empirically what comdirect actually exports as CSV (snapshot
  vs. any transaction substance) using a real, anonymized file — informs whether
  Feature A alone suffices for any German-bank history. `[ASSUMPTION]`
- **OD-3:** Is reusable saved mapping (FR-2) MVP or later?

## 7. Success metrics & counter-metrics

- **SM-1** A new user can load a full transaction history and reach correct
  holdings **without** Portfolio Performance for at least one real broker.
- **SM-2** Time-to-first-correct-portfolio for a new user (lower is better).
- **Counter-metric CM-1** Imports that silently produce wrong/incomplete data
  (e.g. snapshot mistaken for history, fees/taxes dropped) → must trend to zero;
  better to refuse/flag than to import wrong numbers.

## 8. Related issues

#482 (import hardening — Feature F), #333 (PP XML — FR-16), #354 (backup/restore
+ export — Feature E), #355 / FR-14 (MCP write tools — Feature C), #416 (data
epic), #419 (LLM/MCP epic).

## 9. Phasing sketch (smallest validating first)

1. **Harden PP bridge** (#482) — keep migration reliable.
2. **Verify comdirect export reality** (OD-2) — cheap, decides A's reach.
3. **API/MCP write-parity** (Feature C) — unlocks the LLM push path; on-strategy.
4. **Resolve OD-1**, then either Feature D (in-app PDF) or double down on C.
5. **Generic CSV import** (Feature A) for structured brokers.
6. **Own export + backup/restore** (Feature E) — the true "leave PP" milestone.
7. **Snapshot import** (Feature B) as a small, clearly-scoped add.
