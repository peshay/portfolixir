# Design Session Results — 2026-07-12

Companion to `design-session-prep-2026-07-12.md`. Sessions executed autonomously
with independent subagents (party mode for A; domain research for B; UX consult
folded into A's panel for C; adversarial review for D). Facilitator: John (PM).
These are **decision drafts for the owner** — nothing below is decided until
Andi signs off.

---

## Session A — Structural simplification (party mode + full elicitation pass)

**Panel:** Winston (architect), Sally (UX), Mary (analyst), Steve (user
persona), independently briefed. Then an elicitation pass over the synthesis
(First Principles, Socratic, Red Team, Pre-mortem, Five Whys).

**Convergence:** 3× Option 2 (demote), 1× Option 3 (merge, Sally); nobody
defended Option 1 (status quo+) or Option 4 (removal).

**Key findings the decision rests on:**
- **The PP round-trip does not need portfolios** (Mary): PP CSV/JSON references
  depot + cash account per transaction; the import *invents* the "PP Import"
  portfolio because the source has none. Portfolio is a schema artifact, not a
  round-trip requirement. (Verify once against the exporter code.)
- **The one thing portfolios uniquely provide is exclusivity/additivity** —
  disjoint partition of depots, so scoped sums always add up to the total.
  Buckets are overlapping by design (ADR-0018). This is the central technical
  risk: a shared depot in two buckets double-counts in naive view sums.
- **User's hard condition (Steve):** a settable default view (household case:
  per-person defaults without a hard wall). Explicitly NOT needed:
  multi-tenant, separate logins.
- **UX rule (Sally):** buckets get NO sidebar entry — they live as chips on
  depot/account rows and in the view editor. Replacing one word (portfolio)
  with two managed concepts (bucket + view) would simplify nothing. Sidebar
  target: Übersicht · Vermögen (view picker, default "Gesamt") · Wertpapiere ·
  Transaktionen · Administration (Konten & Depots, Views).
- **Import UX (Sally):** the import preview replaces the auto-portfolio with an
  editable bucket tag ("these accounts get tagged X — rename or skip"). #558
  dissolves instead of being fixed.
- **LLM-first paradox (elicitation):** demoting only hides portfolios in the
  shrinking channel (UI) while the growing channel (API/MCP — our own planned
  depot-sync agent) can keep creating invisible ones. Ghost-portfolio
  accumulation is failure mode #1.
- **Retroactive series semantics (Winston):** current bucket membership applies
  retroactively to historical series, like PP filters — documented and labeled;
  no temporal membership model. Elicitation adds: membership history must stay
  answerable via the audit journal ("what did this view show on date X").

**Draft decision (for owner sign-off):** *Option 2 now, Option 3 as an
explicit later phase*, subject to six binding modifications from the
elicitation pass:
1. **API story decided now, not in phase 2:** portfolio writes via API/MCP are
   deprecated (or aliased to buckets), and every write is visible in a minimal
   admin list. No invisible writable resource in an LLM-first product.
2. **Exclusivity is preserved, not dropped:** migration seeds one designated
   *exclusive* bucket dimension (each depot in exactly one); further buckets
   are free tags. View totals ALWAYS deduplicate at account level (union, never
   bucket-sum); overlap gets a visible badge.
3. **The validation spike must include an overlap fixture** (shared depot in
   two buckets; Decimal-exact assertion Everything = deduplicated union). The
   1:1 migration fixture alone proves only the tautological case.
4. Retroactivity accepted, reproducibility ensured (UI label "composition as of
   today"; membership history queryable).
5. **Merge exit criterion named** (e.g. two releases without external portfolio
   writes → merge story), so the demoted entity cannot become a permanent zombie.
6. One management surface for views/buckets ("Manage…" from the view picker, no
   sidebar entries) and migration with preview + documented revert.

**Kill criterion:** if account-level deduplication in view totals cannot be
done cleanly and cheaply, reject the restructure — the additivity of the total
wealth number is the one number an audit tool must never contradict.

**Root cause (Five Whys):** navigation is chained to the storage model; the
missing piece is an explicit IA rule "sidebar = tasks, entities = attributes".
The ADR should state this rule so the confusion doesn't return in new vocabulary.

**Issue consequences:** #327 moot (tag edit replaces container move) · #328
shrinks to rename · #558 dissolves via import-preview tagging · #491 re-scoped
smaller (one creation flow less, one design language) and unblocked once the
ADR lands · #559 becomes core (bucket chips ARE the grouping UI).

**Next step:** owner reviews this draft → ADR (supersedes/extends ADR-0018
scope notes; states the IA rule) → overlap fixture spike → re-scope #491.

---

## Session B — Money-weighted metrics (domain research)

Full memo with sources attached to #568. Highlights:

- **Flow definition (PP-compatible, portfolio scope):** exactly four external
  flow kinds — `deposit`, `removal`, `inbound_delivery`, `outbound_delivery`
  (deliveries at full transaction value). Buys/sells/dividends/interest/fees/
  taxes/transfers are internal. `balance_adjustment`: recommend external
  (signed) — it fabricates value with no internal counterpart. The classifier
  must take *scope* as a parameter: at per-security scope buy/sell/dividend
  invert and taxes drop out (PP semantics) — build it parameterized, defer the
  per-security IRR.
- **XIRR:** hand-rolled (~100 lines; existing Elixir libs are float-based and
  abandoned). Newton from guess 0.1 with analytic derivative + bracketed
  bisection fallback in (−0.999999, +10]; Act/365; tolerance 1e-7; cap ~200
  iterations; all-same-sign flows → "n/a". Windows < 1 year: show the
  non-annualized period MWR (annualized IRR explodes — known PP complaint).
- **Precision policy (needs an ADR-style note):** Decimal end-to-end for
  flows, net invested, multiple; **float64 only inside the XIRR solver**,
  result returned as rounded Decimal, never persisted. Matching Excel/PP
  (both float64) is the correctness criterion; a pure-Decimal exp/ln is
  complexity for sub-display-precision benefit.
- **Pitfalls:** net invested ≤ 0 → multiple/"% on invested" render "n/a",
  never a negative multiple. Multi-currency: convert each flow at flow-date
  FX through the EUR hub (the result is the EUR-investor IRR incl. FX —
  document that). Period-scoped invested capital: show "opening value" and
  "net period flows" as two labeled numbers (PP's combined widget confuses
  its own forum).
- **Display copy:** "TTWROR: how well your investments performed, as if
  deposits/withdrawals never happened. IRR: how well your money actually
  grew, including when you added or removed it."
- **Sequencing:** decide metric set + fix #545 consciously together — don't
  explain a number, then change it.

**Next step:** owner confirms the three design decisions (flow scope /
solver-precision exception / denominator semantics) → story breakdown on #568.

---

## Session C — Where data quality lives (Sally + Steve, unanimous)

**Decision draft: C1.** One compact line on the dashboard — "N data issues →
fix" — rendered ONLY when N > 0 (no green "all OK" badge), linking to the
pre-filtered securities list (#561 provides the filters). No dedicated data-
health page (C2 = over-engineering for three counters; revisit if issue types
grow). Not removed entirely (C3): stale quotes silently falsify the drift
numbers the dashboard itself shows — that warning belongs exactly there, just
quiet. Steve's ranking: stale quotes are the one item that actually breaks the
check-in; logos are cosmetics.

**Next step:** record on #561; fold the one-line treatment into its acceptance
criteria.

---

## Session D — Automation recipes boundary (adversarial review)

**Verdict on the draft (docs + `contrib/recipes/` in-repo): Tier 2 REJECTED.**
Three HIGH findings: (1) mitigations don't contain the all-scope credential —
BROKERAGE_RW is token-wide for its TTL, and our own architecture puts an LLM
agent on the same machine; per-session TAN gates issuance, not use. (2)
CI-exempt credential-handling code = least-reviewed, most dangerous code in
the repo and a supply-chain target; un-reviewable under the project's own
rules. (3) Headline test fails: the app/contrib distinction is invisible to
scanners, journalists, and brokers' compliance teams.

**Accepted direction: satellite repo + hardened docs.**
- Executable recipes live in a separate repo (e.g. `portfolixir-recipes`) or
  owner gists — own issue tracker (support boundary is structural), no CI
  carve-outs, contains the headline. Linked once from the docs site.
- The main repo's docs "Recipes" section centers on the **interchange
  contract**, not the bank client: the local JSON/JSONL schema, the MCP
  reconcile-and-book flow with mandatory guardrails (preview/dry-run first,
  idempotency, no deletes, bounded batches), and a broker-agnostic safety
  checklist. Broker auth mechanics at concept level only — no turnkey ROPC
  copy-paste.
- Every walkthrough leads with a risk banner (all-scope credential incl. order
  rights; liability shift / grobe-Fahrlässigkeit warning; "your bank's ToS may
  forbid this"), EN + DE.
- LLM prompt templates carry a data-privacy warning (real financial data
  leaves the machine with hosted LLMs; note the local-LLM option).
- ADR replaces "forbidden forever" with "requires a new ADR explicitly
  superseding this section" (ADR-0021 proves scope exceptions happen — name
  the process, don't pretend immutability), and records a dated ToS review of
  the comdirect API terms + a removal plan (C&D case) + who accepts the risk.
- Token-hygiene rules become normative recipe text: refresh token never
  persisted, token never shared with the LLM agent's environment, sync tool
  and booking agent isolated, revoke-on-exit verified.

**Next step:** owner sign-off → ADR draft along these lines → re-scope #567.

---

## Session E — Owner-data walkthrough

Not executed (requires the live instance and the owner); scheduled after #557
merges. Agenda unchanged from the prep doc: credit_line/reserve roles for the
relevant cash accounts; repair negative holdings (#570 will surface them);
list phantom-FX positions (#569) as known-and-ignored until fixed.

---

## Consolidated ask to the owner

1. **A:** approve "demote now, merge later + 6 modifications" → I draft the ADR.
2. **B:** confirm the three design decisions → story breakdown on #568.
3. **C:** approve C1 → acceptance criteria on #561.
4. **D:** approve "satellite repo + hardened docs" → ADR draft, re-scope #567.
5. **E:** schedule after the #557 merge.
