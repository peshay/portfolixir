# Design Session Prep — Product Review Follow-ups (2026-07-12)

Prepared by: John (PM) · Source: product review 2026-07-12 (Andi) on the
reconsolidation branch (PR #557) · Status: prep, no decisions taken here.

Five discussion topics came out of the review triage. Each section below frames
the topic, collects the evidence, spans the option space, and names the BMad
method to run it with — so any session can start cold and end with a recorded
decision. Elicitation convention per Andi: when a skill proposes elicitation
methods, run **all** of them, no pick-menu.

Suggested order: **A → C → B → D → E.** A blocks the Konten-&-Depots redesign
(#491) and shapes #559; C is a 15-minute decision that unblocks #561; B gates
#568 and interacts with #545; D gates #567; E is a data walkthrough, not a
product decision.

---

## A. Structural simplification: Portfolios vs. Depots/Konten vs. Buckets/Views

**The question.** Portfolio Performance forced depot/account granularity to be
the *filtering* mechanism, so the user managed pseudo-buckets through depots.
Portfolixir now has real buckets (overlapping tags) and views (filters over
buckets) per ADR-0018. Do we still need portfolios as a *scoping* level, or do
they collapse into something simpler?

**Evidence.**
- Five sidebar concepts today: Depots, Verrechnungskonten, Portfolios,
  Buckets, Views. The user's instinct: Buckets/Views are "das was man braucht".
- #491 (Steve): master-data creation has two design languages; the
  portfolio/account/depot forms are the unloved half. Redesigning that UI
  before deciding the structure would build a nice room in a wing we may tear
  down.
- ADR-0018 already names the tension: buckets replace "three conflicting
  mechanisms — portfolios-as-scope, the global exclude flag (ADR-0013), and
  classifications-as-filter".
- #327 (move depots/accounts between portfolios) and #328 (merge/rename/delete
  accounts & depots) are open and become much simpler — or moot — depending on
  the outcome.
- Hard constraints: depots/cash accounts remain *bookkeeping* entities
  (transactions attach to them; PP import round-trip needs them, goal #4/#9).
  The question is only about the *grouping/scoping* layer above them.

**Option space (to be challenged in session).**
1. **Status quo+**: keep portfolios, polish the UI (#491 as-is).
2. **Portfolio = the wealth container, singular in practice**: keep the entity
   for API/import compatibility, demote it in the UI (no portfolio-scoped
   pages; buckets/views are the only user-facing grouping). Rename UI surface
   accordingly.
3. **Merge portfolios into views**: a portfolio becomes a system view over the
   depots/accounts bound to it; migration turns existing portfolios into
   buckets+views; the portfolios table stays as a thin compatibility shim or
   is removed in a follow-up major.
4. **Full collapse**: depots/accounts carry buckets directly (already true);
   portfolios deleted as a concept. Highest migration and API/MCP breakage.

**Decision criteria.** PP import/export round-trip intact · API/MCP breakage
budget · migration path for existing data · does the sidebar drop to ≤ 4
concepts · does #327/#328 get simpler or disappear · SOLL-plan binding
(ADR-0020 binds plans to views — good sign for option 2/3).

**BMad method.** `bmad-party-mode` with Winston (architect), Sally (UX), Mary
(analyst) moderated by John — the topic is equal parts entity model, IA, and
user-mental-model. Follow with `bmad-advanced-elicitation` on the drafted
direction: run all proposed methods (expect at minimum First Principles, Red
Team, Pre-mortem). Output: **ADR draft** (supersedes/extends ADR-0018 scope
notes) + re-scoped #491/#559/#327/#328.

**Prework done.** Evidence collected above; entity inventory verified in code
2026-07-12 (memberships: `buckets_live.ex`, binding: `portfolio_accounts_live.ex`).

---

## B. The metrics story: TTWROR alone tells the wrong story

**The question.** Which return/wealth KPIs does Portfolixir show, where, and
how are they explained — so the owner never again reads a cashflow-neutral
max-period TTWROR as "my money times X"?

**Evidence.**
- Owner's own analysis (2026-07-10, external LLM session): the max-period
  TTWROR reads absurdly high next to the honest pair — net invested capital
  vs. current value — and the money-weighted IRR (concrete figures are
  personal data and stay out of this repo).
- #545: long-period TTWROR is additionally inflated by trade-price re-pricing
  of unquoted holdings — the headline multiple is not even a clean TTWROR.
  Sequencing with the metric work is mandatory (don't explain a number, then
  change it).
- PP parity: Portfolio Performance shows TTWROR and IRR side by side.
- Candidate KPI set: cumulative + annualized TTWROR (exists) · **net invested
  capital** · **wealth multiple** · **IRR/XIRR p.a.** · absolute gain split
  realized/unrealized (an earlier FIFO analysis shows the appetite).

**Design questions for the session** (mirrored in #568):
external-flow definition per transaction kind (deposits/removals yes;
transfers/deliveries between own accounts no; dividends/interest are internal
returns) · XIRR algorithm under Decimal (bisection vs. Newton, precision
policy, pathological flows) · surface placement (Wealth header KPIs, per
period; per-view scoping later) · one-line explanations per KPI ("what
question does this number answer") · API/MCP exposure.

**BMad method.** `bmad-domain-research` first (short: XIRR under Decimal,
flow-definition conventions in PP/beancount/ghostfolio), then a focused PM+dev
session shaping #568 into stories; `bmad-advanced-elicitation` (all methods)
on the metric definitions before implementation. Output: design note or
mini-ADR + story breakdown for #568, sequenced against #545.

---

## C. Where does data quality live?

**The question.** ADR-0022 made the dashboard the attention surface; data
quality landed there as three count cards. The owner's instinct: counts on
page one feel like settings noise — the dashboard should *alert*, a dedicated
surface should *fix*.

**Evidence.** Dashboard cards link to `/securities` without filters (not URL-
addressable yet); missing-quote/logo aren't filterable; retriggers exist but
are buried (verified 2026-07-12; all in #561).

**Options.**
1. Dashboard keeps compact "N issues → fix" one-liner linking to the filtered
   securities list (#561 does the heavy lifting). No new page.
2. Dedicated "Data health" page under the securities area; dashboard links to it.
3. Move data quality entirely out of the dashboard (settings-adjacent).

**Recommendation to challenge:** option 1 — smallest, consistent with
ADR-0022's "attention, then act elsewhere", and #561 is needed anyway.

**BMad method.** No session needed beyond a 15-minute decision with Sally's
hat on (`bmad-agent-ux-designer` consult, not a workshop). Record the outcome
as a comment on #561 (+ ADR-0022 addendum only if option 2/3 wins).

---

## D. Automation recipes in the repo: where is the boundary?

**The question.** External read-only broker sync (e.g. a private,
out-of-repo comdirect script: OAuth+photoTAN pull of depot/positions/postbox, settlement-PDF
parsing) feeding Portfolixir via MCP is exactly the LLM-first direction (#419)
— but AGENTS.md forbids broker sync *in the app*. What may live in the repo?

**Evidence.** The comdirect example (reviewed 2026-07-12): strictly read-only,
never writes to Portfolixir directly, hand-off via MCP reconcile-and-book; the
credential reality is ugly (comdirect grants all scopes incl. BROKERAGE_RW —
no read-only grant exists), mitigated by per-session TAN, short token TTL, and
never wrapping order endpoints. Full details in #567.

**Options.** Docs-only recipes (prompts + walkthrough, scripts linked
externally) · `contrib/` directory with example scripts (unsupported, no CI,
big disclaimer) · nothing executable, prose only.

**Decision criteria.** Repo must not *appear* to ship broker sync · no
credentials/PII, synthetic examples only (public-repo rule) · maintenance
burden of unsupported scripts · discoverability for users who want this.

**BMad method.** Small ADR, drafted by Winston (`bmad-agent-architect`) with a
security-boundary review pass; `bmad-review-adversarial-general` on the draft
(the "does this look like we ship broker sync?" test). Output: ADR + unblocked
#567.

---

## E. Owner-data walkthrough (not a product decision)

Personal data-modeling questions from the review, to be walked through
together against the live instance — no repo changes expected (account
names and amounts live on the instance, not in this document):

1. **Lombard/credit line**: model the broker credit line as a cash account
   with liquidity role `credit_line`; the call-money account as `reserve`
   (roles exist in `portfolio_accounts_live.ex`). Then the cash line stops
   being cosmetic.
2. **Negative holdings**: identify via the future #570
   report; until then, repair the transaction history manually — these are
   import debris, not classification candidates.
3. **Phantom FX P&L positions**: list the USD-quoted/EUR-booked positions so
   the per-position P&L distortion (#569) is known-and-ignored until fixed.

**BMad method.** None — this is a guided session with John + the MCP tools on
the live instance, after #557 merges.

---

## Bookkeeping

- In-branch UAT round 2 (PR #557): signed drift sort + category sort,
  expandable Unassigned, row-click expand, tooltip edge fix, single
  expand-toggle near the table, aligned rebalance hints, attention-card
  explanation, 1y default period, toast-free FX sync.
- Issues filed 2026-07-12: #558 (portfolio rename), #559 (cash-account
  memberships), #560 (income mobile bug), #561 (actionable data quality),
  #562 (performance-series cache), #563 (period picker), #564 (chart data
  table), #565 (classification columns), #566 (toast removal), #567
  (automation recipes), #568 (money-weighted metrics), #569 (phantom FX P&L),
  #570 (negative holdings flag). Stacked PRs #551–556 closed in favor of #557.
