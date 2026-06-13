# Adversarial Review — Portfolixir PRD (2026-06-12)

Reviewer stance: cynical. Target: `prd.md` + `addendum.md` in this folder,
cross-checked against `AGENTS.md`, `_bmad-output/project-context.md`,
GitHub issues #310–#350, `docs/decisions/`, the MCP tool surface
(`mcp-server/src/tools.ts`), and the router (`lib/portfolixir_web/router.ex`).

Verdict: **the PRD is well-written and honest in places (OQ-2/3/5 flag real
unknowns), but it is not launch-grade as a contract.** It understates an
already-shipped destructive LLM write surface, has no audit-trail or
backup/export requirement while explicitly retiring the operator's only
redundant source of truth, sells "read-only sync" as a security property when
it is only a client-side promise, and contains counter-metrics that are
violated by the repo's baseline on day zero. Two FRs (PP XML import,
rebalancing guidance) are currently forbidden by AGENTS.md but carry no gate
annotation, unlike Phase 3.

Severity counts: **2 critical, 7 high, 8 medium, 4 low** (21 findings).

---

## Critical

### C-1. No audit trail for an LLM that edits financial records

**Location:** FR-14, NFR-2; verified against `mcp-server/src/tools.ts`.

FR-14 makes an external LLM a first-class *writer* of financial records.
NFR-2 then quietly redefines auditability as "reproducible from immutable
inputs; editing is allowed" — but the inputs (transactions) are themselves
mutable, and the MCP surface **already ships** `transactions.update`,
`transactions.delete`, `securities.delete`, `cash_accounts.delete`,
`cash_accounts.set_balance`. There is no change log anywhere (no
versions/audit code exists in `lib/portfolixir/ledger/`). A hallucinated
agent edit of a historical transaction is **undetectable after the fact** —
which is precisely the "silent financial corruption" NFR-1 names as the
defining failure class. The PRD's flagship risk and its flagship feature are
the same thing, and no requirement connects them.

**Fix:** Add an FR: append-only change log on every write path (actor —
agent token vs. human UI —, timestamp, before/after values), covering
create/update/delete on ledger, accounts, and securities. Add
destructive-operation semantics (confirmation step, or recoverable window).
This is a Phase-1/2 requirement, not Phase-4 polish — the write surface is
live today.

### C-2. No backup, restore, or data-export requirement — while retiring the redundant source of truth

**Location:** Success Metric 1, NFR-5; absent from all FRs/NFRs.

Success Metric 1 celebrates retiring the manual spreadsheet and PP
reconciliation — i.e. deleting the operator's only independent copy of his
financial history. In exchange the PRD offers: a single PostgreSQL instance
on commodity home hardware, with **zero** requirements for backup, restore
verification, or data egress. FR-5 promises lossless import *from* PP;
nothing promises a way *out* (back to PP, CSV, or anything). For a product
whose vision sentence is "wealth data backbone", losing the box means losing
the wealth record. This is a month-one operational reality, not an edge case.

**Fix:** Add an NFR for backup/restore (documented procedure in
docker-compose context, periodic restore test as a release-blocking check)
and an FR for full structured export (at minimum PP-compatible or
CSV/JSON round-trip). Gate Success Metric 1 on the export FR shipping first.

---

## High

### H-1. "Read-only sync" is a behavioral promise, not a security property

**Location:** Phase 3, FR-17/18/21, NFR-4, OQ-1.

FR-21 says "all sync is read-only, credential storage is local and
encrypted." Three problems the PRD does not acknowledge:

1. **The stored credentials are write-capable.** A comdirect API session can
   place orders; bunq API keys are full-access by default. "Read-only" is
   enforced only by Portfolixir choosing not to call write endpoints.
   Whoever exfiltrates the credential from the self-hosted box gets trading
   and payment capability. The AGENTS.md boundary "no real bank, broker …
   payment, order, trading action" is therefore protected by nothing but the
   app's good manners once Phase 3 lands.
2. **"Encrypted" with what?** On a single self-hosted box the encryption key
   sits next to the ciphertext. No threat model, no key-management
   requirement, no statement of what attacker this encryption defeats.
3. **comdirect requires interactive PhotoTAN session activation.** UJ-2's
   "later: read-only sync pulls it" implies unattended sync; that is likely
   impossible with comdirect's session-TAN model. The PRD never mentions the
   human-in-the-loop constraint.

**Fix:** Extend OQ-1 into a real threat-model deliverable before any sync
story: per-provider credential scoping (does bunq permit permission-limited
keys?), key-management decision, and an explicit statement that comdirect
sync is operator-initiated per session, not background.

### H-2. The Phase 3 gate is self-amended paper, with no mechanical backstop

**Location:** Phase 3 "Gate:", NFR-3, OQ-1.

The gate is: the owner writes an ADR and edits AGENTS.md. The same solo
owner — who by the PRD's own admission does not read code — is author,
approver, and enforcer. Nothing fails CI if an agent lands a bank-API client
before the ADR exists. This matters because the PRD itself declares
mechanical guards "load-bearing product requirements, not process garnish"
(Section 1) — and then specifies its most consequential scope boundary as
pure process. The project-context gate roadmap already builds invariant
meta-tests for *less* dangerous invariants (no DB deps in mcp-server, no
reducer catch-all) but has none for sync.

**Fix:** Pair the gate with a meta-test in the #347 suite: dependency
allowlist (no OAuth/bank-API libraries), no credential-bearing schema/table,
no HTTP client config pointing at bank domains — removed only in the same PR
as the ADR + AGENTS.md amendment. Make NFR-3 reference it explicitly.

### H-3. PP XML import and rebalancing guidance are forbidden by AGENTS.md today — and carry no gate note

**Location:** FR-5 (XML, #333, scheduled Phase 1 "now"), FR-12; vs.
AGENTS.md Hard Rules.

AGENTS.md: "Do not implement document intake (binary `.portfolio`, **PP
XML**, broker PDFs), broker sync, bank sync, trading, payment, order,
**rebalance**, or LLM behavior unless a reviewed story explicitly changes
scope." The PRD is scrupulous about gating Phase 3 sync but presents FR-5's
XML import as Phase-1-now and FR-12's rebalancing guidance as gateless core,
both of which sit on the same forbidden list. Issue #333 even subtitles
itself "scope extension of goal #9" — the PRD dropped that caveat. An agent
following AGENTS.md must refuse both FRs; an agent following the PRD
violates AGENTS.md. For a project whose whole methodology is "agents obey
written contracts", contradictory contracts are a live defect.

**Fix:** Annotate FR-5 (XML portion) and FR-12 with the same "requires
AGENTS.md scope amendment" gate as Phase 3, or amend AGENTS.md (goal list +
hard-rule exception) in the PR that accepts this PRD. For FR-12, the
amendment should restate the guidance-vs-action line ("ranked suggestions,
never order placement") inside AGENTS.md itself.

### H-4. Counter-metric "no threshold raises, no ignore files" is violated by the repo's baseline on day zero

**Location:** Section 7 counter-metrics; vs. project-context.md Quality
sections.

The repo today: Credo thresholds grandfathered at `max_complexity: 15` /
`max_nesting: 4` (defaults 9/2); Sobelow runs with
`--ignore Config.CSP,Config.HTTPS` plus documented `# sobelow_skip`
annotations; the dependency-update policy explicitly says "fix **or
baseline** new findings in the same update PR." So "no ignore files" is
already false, and the counter-metric bans a practice project-context.md
explicitly permits. A counter-metric that is unmeetable at baseline gets
ignored, which trains everyone to ignore counter-metrics.

**Fix:** Reword: "gates only ratchet downward — no *new* baselines or skips
without a written reason in the PR, no raising of grandfathered thresholds
(#314 tracks lowering them); Sobelow skips require documented justification
per project-context.md."

### H-5. Success Metric 1 dismantles the detection mechanism for Counter-metric 1

**Location:** Section 7, Metric 1 vs. Counter-metric 1.

Counter-metric 1 targets zero "financial-correctness incidents (wrong number
reaching a view/API)." Wrong numbers are only ever *discovered* by
reconciliation against an independent source — exactly the manual
cross-checking that Metric 1 defines success as eliminating. Once Numbers
and PP reconciliation are retired, the incident count is zero by
construction: not because numbers are right, but because nothing can prove
them wrong. The counter-metric becomes unfalsifiable the moment the headline
metric is achieved.

**Fix:** Add an automated reconciliation requirement as a precondition for
declaring Metric 1: e.g. a periodic PP-export diff report, or (post-Phase 3)
a sync-vs-ledger reconciliation view whose drift count is the measured
counter-metric. "Reconciliation drift … surfaced" (counter-metric 2)
currently has no FR producing that surface for the pre-sync era.

### H-6. FR-14 understates the live write surface and specifies no failure modes

**Location:** FR-14, FR-6; verified against `mcp-server/src/tools.ts`.

FR-14 says MCP tools "cover data maintenance (create/update records)." The
shipped surface already includes **delete** on transactions, securities, and
cash accounts. Beyond the understatement, the FR is silent on the failure
modes that define an LLM writer:

- **No write idempotency.** FR-6's content-hash idempotency covers file
  imports only. An LLM that times out and retries `transactions.create`
  silently duplicates a financial record — the most predictable agent
  failure there is.
- **No preview/dry-run.** Imports get preview-before-apply (FR-6); agent
  writes, performed by a probabilistic actor, get nothing.
- **No runaway protection.** Nothing bounds a retry loop or mass
  delete-and-recreate sequence.

**Fix:** Extend FR-14: (a) idempotency keys on all MCP/API write endpoints;
(b) explicit destructive-op contract (and list delete as in scope, since it
is); (c) error responses designed for agent recovery (machine-readable
validation failures); (d) optional dry-run mode mirroring import preview.
Ties into C-1's audit log.

### H-7. German pension modeling is sold as a moat without acknowledging it is a moving legal target

**Location:** Section 1 Positioning, FR-24, FR-25, UJ-4.

"German retirement modeling (no open-source coverage at all)" is framed as a
differentiator. The reason there is no coverage: Rentenwert changes every
July; early retirement carries 0.3%/month Abschläge; payouts are subject to
nachgelagerte Besteuerung with a year-of-retirement-dependent taxable share;
KVdR health-insurance contributions reduce net payout. "What does one more
point buy me?" (FR-24) has no meaningful answer without these, and FR-24/25
acknowledge none of them — nor is there any requirement for maintaining the
legal parameter tables or their annual update cadence. As written, FR-24/25
smuggle in either a permanently-wrong calculator or an open-ended
legal-modeling project.

**Fix:** Add an explicit assumption block: v1 = gross, current-law,
parameter-table-driven projection with parameters as operator-maintained
data (with as-of dates surfaced per FR-13); taxes and KVdR out of scope v1
and stated as such in every response. Add an OQ for parameter-update
ownership, parallel to OQ-5's honest treatment of tax-aware rebalancing.

---

## Medium

### M-1. FR-19 is committed while OQ-4 says it must not be

**Location:** FR-19 vs. OQ-4. OQ-4: bitcoin.de needs "a technical spike
before FR-19 is committed" — yet FR-19 stands as an unconditional
requirement. **Fix:** Mark FR-19 `[CONDITIONAL on OQ-4]`.

### M-2. The "FRs map to #316–#350" traceability claim is overstated

**Location:** PRD framing / Section 4–5 issue references. FR-9
(benchmark), FR-17–21 (all of Phase 3), FR-24/25 (pensions), FR-26
(retirement projection) have **no** issues; #341/#342/#345 do not exist
(gap in the range); #340 is a parking lot, not a pension issue. Roughly a
third of the FRs are untracked. **Fix:** Add a per-FR → issue table;
create issues or mark "no issue yet" honestly.

### M-3. FR-9's comparison method cannot answer the founding question as specified

**Location:** FR-9, Section 1 founding question. Comparing a TTWROR series
to a flat 2% line is apples-to-oranges: TTWROR deliberately removes
cash-flow timing, but "would I be richer in Tagesgeld?" depends exactly on
when the cash flowed. The honest comparison replays the investor's actual
cash flows into the alternative (money-weighted / end-wealth comparison) —
and German tax treats interest and equity gains differently. Risk: the
product's headline analytic serves a confidently misleading number to an
LLM that will repeat it verbatim. **Fix:** Specify the method in the FR
(cash-flow-replay baseline producing comparable end-wealth/IRR), or scope
v1 explicitly as rate-vs-TTWROR with the caveat embedded in the
self-describing response (FR-13).

### M-4. What-if/benchmark features have an unstated quote-history dependency

**Location:** FR-27 (#332), FR-9, OQ-3. Blind-follow backtests need
historical quotes from each tip date for securities **never held** —
acquiring, storing, and licensing that history is a real dependency with no
requirement behind it. OQ-3 covers only index series for benchmarks.
**Fix:** Add an FR or OQ for historical-quote acquisition for non-held
securities (source, depth, ADR-0005 fit).

### M-5. Watch-only xpub tracking has an unaddressed privacy/ops trade-off

**Location:** FR-20. Deriving balances from an xpub requires a chain data
source: a third-party explorer (leaks the entire wallet structure of a
self-described long-term BTC holder to an external service — ironic for a
self-hosting product) or a local node (significant ops weight). The FR
mentions neither. **Fix:** Add an OQ: chain-data source and privacy stance
for FR-20.

### M-6. The web UI has no authentication at all, and no NFR requires any

**Location:** NFR-4, NFR-5; verified in `lib/portfolixir_web/router.ex`
(browser pipeline: session, CSRF, locale — no auth plug). Only the JSON API
has bearer auth. Acceptable for a LAN box today, but the PRD claims "a
quality grade that lets others adopt it" and Phase 3 plans to park bank
credentials behind this UI. **Fix:** Add an NFR: either UI auth, or an
explicit documented stance ("network-level/reverse-proxy auth is the
operator's responsibility") — silence is the only wrong option.

### M-7. No data-freshness requirement — stale quotes become confident wrong answers

**Location:** FR-13, NFR-8, UJ-1. FR-13's as-of date helps only if the
agent checks it; nothing requires a staleness flag, a last-sync indicator,
or degraded-confidence signaling when quotes or FX rates are days old. The
morning-briefing journey (UJ-1) will happily report a valuation built on
last week's prices. **Fix:** Require staleness metadata (age of newest
quote/FX rate per response) and a defined threshold beyond which responses
self-mark as stale.

### M-8. FR-4 "portfolios partition the wealth space" overstates the model

**Location:** FR-4, UJ-6. Securities, quotes, FX rates, and classification
trees are global (Catalog); only accounts/depots and their transactions are
portfolio-scoped. "Every view and every analytic can be scoped" is broader
than what is specified or shipped (target weights per portfolio?
classification trees per portfolio?). **Fix:** State precisely which
entities are portfolio-scoped vs. instance-global, and whether targets/
classifications are shared across the family boundary in UJ-6.

---

## Low

### L-1. Success metrics are one-shot demos, not 12-month metrics

**Location:** Section 7. Metric 2 is satisfied by a single successful demo;
Metric 3 by the existence of one projection run (says nothing about
correctness); "CI green-rate stays high" has no baseline, number, or window
and is gameable by pushing less. **Fix:** Attach numbers and measurement
method (e.g. "≥ N agent sessions/week answered via MCP with zero file
handoffs, sustained over a month"; "CI green-rate ≥ X% over rolling 30
days").

### L-2. "Phases are sequential priorities, not strict gates" — except Phase 3, which is a strict gate

**Location:** Section 4 intro vs. Phase 3. Minor internal wording tension.
**Fix:** "…not strict gates, with the exception of Phase 3 (hard scope
gate)."

### L-3. No release/upgrade requirement for self-hosters

**Location:** NFR-5. Migration-roundtrip lives in the CI roadmap, but the
PRD says nothing about versioned releases, changelogs, or upgrade paths for
the "future self-hosters" persona. **Fix:** One NFR line: tagged releases,
changelog, documented upgrade procedure — or explicitly defer until the
persona activates.

### L-4. Concurrent agent + human edits are unspecified

**Location:** FR-14, UJ-2. Agent writes via MCP while the operator edits in
LiveView: last-write-wins on financial records, no conflict detection
required anywhere. Low likelihood for a solo operator, nonzero for an
always-on agent. **Fix:** Note as accepted risk or add optimistic-locking
note to FR-14.

---

## What the PRD gets right (so the praise is calibrated, not absent)

- OQ-5 honestly defuses the tax-guidance trap that UJ-3 opens.
- The "Portfolixir never calls an LLM" cornerstone is consistent with
  AGENTS.md and architecturally enforced (ADR-0002).
- [ASSUMPTION] tags (UJ-4, FR-9, OQ-2/3) are the right discipline; the fix
  for several findings above is simply to apply that same discipline to
  FR-5/12/19/24/25.
- The aggregator-avoidance rationale (Phase 3) is current and correct.
