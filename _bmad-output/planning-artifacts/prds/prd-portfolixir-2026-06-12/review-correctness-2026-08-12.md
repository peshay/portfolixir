# Correctness review — 2026-08-12 identity-gate documentation change

**Reviewer role:** correctness hunter (factual errors only; style and prose are
out of scope).
**Scope:** the last four commits on the current branch, diffed against
`origin/main`:

- `f636e1c docs(prd): carry the 2026-08-12 identity gate into the PRD`
- `283217a docs(epics): register FR-37..FR-48 from the identity gate`
- `1fa44e0 docs: amend AGENTS.md and the public identity for gate B3.1`
- `90ccbd8 docs(prd): reconcile the PRD against the brief and record the run`

Files: `prd.md`, `addendum.md`, `.decision-log.md`, `epics.md`, `AGENTS.md`,
`README.md`, `docs/index.md`.

**Verdict: yes, there are factual errors.** One is blocking (F-1): a claim about
the state of the codebase that is contradicted by the code, by `ADR-0017`'s own
rollout-complete section, and by a meta-test — and it has been turned into a
binding sequencing dependency on six requirements. Three further findings are
moderate, four are minor.

---

## F-1 (blocking) — the audit-journal rollout is complete, not incomplete; MCP write tools are not blocked

**Where**

- `_bmad-output/planning-artifacts/epics.md:108`
- `_bmad-output/planning-artifacts/prds/prd-portfolixir-2026-06-12/prd.md:622-628`
- consequentially: `epics.md:224`, `:225`, `:226` (three FR Coverage Map rows
  reading "Blocked by #677")

**Claim as written** (epics.md:108, near-identical in prd.md:622):

> the audit-journal rollout (FR-28) is incomplete — Catalog and FX are armed;
> Portfolios, Classifications, Ledger and Imports still write unjournaled — and
> MCP *write* tools are deliberately blocked behind it so no agent can edit
> financial data without an audit trail. … **completing the rollout (#677) is a
> prerequisite, not a parallel nicety.**

**What I verified**

1. **The named contexts all journal.** `Journal.record/3` is called throughout
   `lib/portfolixir/portfolios.ex` (lines 116, 129, 211, 226, 248, 293, 317,
   343…), `lib/portfolixir/ledger.ex` (1058, 1104, 1121),
   `lib/portfolixir/classifications.ex` (177, 192, 208, 235, 245, 260, 280, 323,
   336, 527, 584) and `lib/portfolixir/imports/applier.ex` (1159, under
   `Actor.import_session()`). `lib/portfolixir/tax.ex` and
   `lib/portfolixir/buckets.ex` journal as well.
2. **Their tables are guard-armed by migration:**
   `priv/repo/migrations/20260622130000_arm_portfolios_journal.exs`,
   `…20260622140000_arm_accounts_journal.exs`,
   `…20260622150000_arm_transactions_journal.exs`,
   `…20260623120000_arm_classifications_journal.exs`,
   `…20260623130000_arm_assignments_journal.exs`,
   `…20260716130000_arm_targets_journal.exs`,
   `…20260725130000_arm_tax_journal.exs`,
   `…20260726130000_arm_tax_snapshots_journal.exs`.
3. **`ADR-0017` says so itself.** `docs/decisions/0017-append-only-audit-journal.md`
   documents slices 0–6 as *landed* and carries a section headed **"Rollout
   complete"**: *"Every context that writes financial data — Catalog/Fx,
   Portfolios, Ledger, Classifications — is converted… The grandfather list is
   empty."*
4. **A meta-test pins it.** `test/write_actor_test.exs:59` holds
   `@grandfathered MapSet.new([])`, with a test asserting the list only shrinks
   and a test asserting `armed_tables_in_db() == @armed_tables`.
5. **MCP write tools are shipped, not blocked.** `mcp-server/src/tools.ts`
   dispatches `portfolixir.securities.create/update/delete`,
   `portfolixir.transactions.create/update/delete`,
   `portfolixir.cash_accounts.*`, `portfolixir.securities_accounts.*`,
   `portfolixir.classifications.*`, `portfolixir.splits.create`,
   `portfolixir.quotes.upsert` (lines 2315–2451+). `epics.md:313` — untouched by
   this change — already records this: *"MCP data-maintenance writes
   (FR-14/#355) are broadly shipped … **unblocked by the journal rollout
   above**."*
6. **"FX is armed" is wrong in the opposite direction.**
   `lib/portfolixir/fx.ex` contains no `Journal` reference at all, and
   `lib/portfolixir/journal/allowlist.ex` puts `exchange_rates` on the closed
   list of tables that are **deliberately never armed** (market-data ingestion
   is exempt by design). ADR-0017 slice 1 says the same: *"`Fx`'s only write …
   stays allowlisted."*

**Provenance, so the fix lands in the right places.** The wording originates in
the `epics.md` reconciliation of **2026-06-18** (`epics.md:263-270`), which was
correct at that date. The **2026-07-16** reconciliation immediately below it
(`epics.md:308-313`) already superseded it. The stale text was then copied
forward into `feedback-triage-2026-08-12.md:507-515`, into PR #663's body, and
into issue **#677** — whose own scope paragraph repeats it verbatim. This change
is the fourth copy, and the first one to promote it into the requirement
registry.

**Correction**

- Delete the sequencing paragraph from `epics.md:108` and `prd.md:622-628`, or
  replace it with the true state: *the ADR-0017 rollout is complete (slices 0–6
  landed, grandfather list empty, `exchange_rates` deliberately allowlisted);
  MCP write tools are already armed and journaled. Agent-written knowledge
  objects therefore need journal coverage of their own new tables as an
  acceptance criterion, not a prerequisite epic.*
- Drop "Blocked by #677" from `epics.md:224`, `:225`, `:226`.
- Out of scope for this branch but worth a follow-up note: issue #677 and
  `feedback-triage-2026-08-12.md:507` carry the same error and should be
  corrected or closed, otherwise the next reader re-imports it.

---

## F-2 (moderate) — `AGENTS.md` misstates what `workflow_docs_test.exs` enforces

**Where** `AGENTS.md:277-279`

**Claim as written**

> The nine steps above are the canonical order and are asserted verbatim by
> `workflow_docs_test.exs` across this file, `README.md`, `CONTRIBUTING.md` and
> `docs/development/story-workflow.md` — change them in all four or in none.

**What I verified** `test/portfolixir/workflow_docs_test.exs:22-40` reads all
four documents and **joins them into one string** before asserting each of the
nine step lines appears in that concatenation. A step present in exactly one of
the four files satisfies the test. And `README.md` does not carry the nine steps
at all (`grep` for `1. User Story documented.`: CONTRIBUTING.md ✓, AGENTS.md ✓,
docs/development/story-workflow.md ✓, README.md ✗). The suite passes on this
branch (21 tests, 0 failures across `workflow_docs_test.exs`, `docs_test.exs`,
`ci_test.exs`), so nothing is broken — the sentence just describes a stronger
mechanism than exists.

**Correction** "…are asserted by `workflow_docs_test.exs`, which reads
`AGENTS.md`, `CONTRIBUTING.md`, `README.md` and
`docs/development/story-workflow.md` as one text — so the steps must stay
verbatim, but the test does not require each file to carry them. They currently
live in `AGENTS.md`, `CONTRIBUTING.md` and `docs/development/story-workflow.md`;
keep those three in sync."

---

## F-3 (moderate) — NFR-9 was added on 2026-07-25, not "present in the PRD since 2026-06-12"

**Where** `_bmad-output/planning-artifacts/epics.md:122`

**Claim as written**

> *(Present in the PRD since 2026-06-12 and missing from this inventory until
> 2026-08-12; recorded here to close the drift.)*

**What I verified** NFR-9 entered `prd.md` in commit `1bc1693`
("docs(planning): validate both PRDs adversarially and resolve all findings
(#615)", **2026-07-25**), as an added line. The PRD as of the previous commit
(`c61a261`) contains zero occurrences of `NFR-9`. The decision log confirms the
origin — `.decision-log.md:140`: *"new NFR-9 mechanical scope backstop"* — and
the adversarial review that produced it records the predecessor finding as
`H-2 … **Not fixed.** No meta-test requirement was added`
(`review-adversarial-general.md:619`). The PRD's *title* date is 2026-06-12; its
content is explicitly "corrected for decisions taken since", so the title date is
not evidence of the requirement's age.

**Correction** "Present in the PRD since 2026-07-25 (added by the adversarial
validation run, #615) and missing from this inventory until 2026-08-12."

---

## F-4 (moderate) — the H5 gate table assigns B3.1 to thesis and prediction; the triage assigns B4.1 and B4.2

**Where** `prd.md:608-609` (the H5 knowledge-object table, `Gate` column)

**Claim as written**

| Thesis / conviction | … | **B3.1** |
| Prediction | … | **B3.1** |

**What I verified** `feedback-triage-2026-08-12.md` defines these as **Bucket 4**
items with their own IDs: `B4.1 — Theses and conviction as structured fields`
(line 453) and `B4.2 — Predictions with a calibration report` (line 463). B3.1 is
the *identity* gate; the triage says Bucket 4 items are "sequenced **behind**
B3.1" (line 451) and lists them separately in the "not filed, deliberately"
section as "the knowledge objects (B4.1/B4.2)" (line 733). The two IDs `B4.1` and
`B4.2` appear **nowhere** in any file this change touches — verified by grep
across `AGENTS.md`, `README.md`, `docs/index.md`, `epics.md`, `prd.md`,
`addendum.md`.

Note the same table gets the other two rows right (Policy rule → B3.6, Security
event → B3.4), so the column is genuinely meant to hold gate IDs, which makes the
B3.1 entries read as a gate assignment rather than as "unlocked by".

**Correction** Set the two rows to `B4.1` and `B4.2` respectively (adding
"sequenced behind B3.1" if the dependency matters), and mirror it at
`epics.md:226`, which currently says only "Decided in principle by the identity
gate".

---

## F-5 (moderate) — NFR-9's coverage-map row asserts a backstop that does not exist, with no status marker

**Where** `_bmad-output/planning-artifacts/epics.md:228`

**Claim as written**

> | NFR-9 | — | mechanical scope backstop — meta-tests in the invariant suite;
> guarded set revised 2026-08-12 |

**What I verified** The FR Coverage Map is a *status* table — every other row
carries a status word (`shipped`, `future`, `partially landed`, `not
implemented`). This row carries none, and reads as describing something that
exists. It does not. `test/invariants/` contains thirteen files; the only
allowlist meta-test is `mcp_dependency_allowlist_test.exs`, whose stated purpose
is ADR-0002 (keeping the MCP companion thin — no DB drivers), not the NFR-9
scope gates. There is **no** "no credential-bearing schema" test and **no**
"no bank-domain HTTP configuration" test anywhere in `test/`. The PRD's own NFR-9
text is prescriptive ("Without this, the project's most consequential
boundary is enforced by one person editing Markdown…"), i.e. the backstop is
requested, not built.

The claim in the epics prose entry (`epics.md:122`) is fine as a *requirement*.
The problem is the coverage-map row presenting an unbuilt requirement as
inventory.

**Correction** Add a status to the row, e.g.
`| NFR-9 | — | mechanical scope backstop — **not implemented**: the invariant
suite has no dependency/schema/hostname gate for the scope boundary today;
guarded set revised 2026-08-12 |`.

---

## F-6 (minor) — "Blind-follow backtesting is *literally* ladder level (d)" over-reads FR-27

**Where** `prd.md:438-442`

**What I verified** Ladder level (d) is defined at `prd.md:245` as *"Backtesting
**rules** against stored price history"*. FR-27 (`prd.md:566-571`) is broader:
*"virtual trade scenarios as overlay timelines against real quote history —
including 'blind-follow' series … and an aggregate per-source verdict"*. Only the
blind-follow half is backtesting-shaped, and it backtests a *tip source*, not a
*rule*. The triage agrees, treating #332 as a **neighbour** of the backtesting
request rather than the same thing: *"Backtesting a rule against own price
history (P2-2) | Nothing exists; nearest neighbours are the what-if simulator
(#332, gated) and the parking lot"* (`feedback-triage-2026-08-12.md:486`).

This matters because under the ladder as written, the non-backtesting half of
FR-27 (virtual trade overlays) is no longer forbidden by anything, so the stated
gate under-describes what is actually blocked.

**Correction** Drop "literally", and say what the gate covers: *"FR-27's
blind-follow half is ladder level (d) and stays out for now; the rest of the
simulator has no ladder home and stays gated with it until level (d) reopens
(gate B3.6). OQ-11 remains an independent blocker."* Mirror at `epics.md:203`.

---

## F-7 (minor) — the alarm list is described as "the pull half of B3.7"; the triage rides it on B3.6

**Where** `epics.md:101` (FR-43)

**Claim as written** "a violated rule is the retrievable alarm list, which is the
pull half of B3.7"

**What I verified** `feedback-triage-2026-08-12.md:413-419` (B3.7): *"A
retrievable alarm list is ordinary scoped work and **can ride B3.6** … outbound
HTTP to a user-configured endpoint is a separate security decision …
Recommendation: build pull, defer push to its own gate."* B3.7 *is* the push
gate; the alarm list is explicitly the thing that does **not** need it. Calling
the alarm list "the pull half of B3.7" invites a reader to think the alarm list
sits behind gate B3.7.

**Correction** "…is the retrievable alarm list, which rides B3.6; only push
delivery is gated at B3.7."

---

## F-8 (minor) — the measured A/B figures are attributed to ADR-0035, which does not contain them

**Where** `addendum.md:99-103`

**Claim as written** "**ADR-0035**, the adjacent precedent that deliberately
*removed* redundant computation instead of caching it, with a measured result
(1,105 ms → 265 ms, 2,614 → 115 queries, output identical)."

**What I verified** The numbers are correct — they come from
`_bmad-output/implementation-artifacts/619-pricing-pass-measurement-2026-08-03.md:103,138,150`
(whole async block 1,104.6 ms → 264.7 ms; 2,614 → 115 queries) and are quoted the
same way at `epics.md:211`. But `docs/decisions/0035-one-pricing-pass-per-read.md`
does **not** carry them: it was accepted 2026-08-03, before the change shipped
(2026-08-04), and its only measurement table is the ~388 ms *pre-change* warm
steady state. Its References section points at the earlier
`619-dashboard-mount-measurement-2026-07-31.md`, not at the A/B report. An ADR
author sent to ADR-0035 for the measured result will not find it.

The substantive characterisation of ADR-0035 is accurate: *"Rather than
memoizing that redundancy (the ADR-0032 extension), the redundancy is removed"*
and *"Caching valuation stays deferred"* (Consequences).

**Correction** Cite the measurement artifact alongside the ADR, e.g. "…instead of
caching it (`ADR-0035`; measured A/B in
`_bmad-output/implementation-artifacts/619-pricing-pass-measurement-2026-08-03.md`:
1,105 ms → 265 ms, 2,614 → 115 queries, output identical)."

---

## F-9 (minor) — the reworded epics FR-1 still omits the `split` kind

**Where** `epics.md:36`

**Claim as written** "All financial state derives from the transaction ledger
(13 PP kinds + balance adjustments)…"

**What I verified** PRD FR-1 (`prd.md:358-359`) says "13 PP kinds + balance
adjustment **+ split**". Split is a shipped first-class ledger kind: ADR-0028
(Accepted 2026-07-19, E17 stories #588–#591 shipped, #338 closed 2026-07-31),
`split_ratio_numerator` / `split_ratio_denominator` on
`lib/portfolixir/ledger/transaction.ex:68-69`, `portfolixir.splits.create` MCP
tool. Since the registry rule says `epics.md` wins on conflict, the stale side is
the authoritative one. The line was rewritten in this change, so the omission is
now a fresh miss rather than an inherited one.

**Correction** "(13 PP kinds + balance adjustment + split)".

---

## Verified correct — no action needed

Recorded so a later reader does not re-check them.

**ADR references.** Every ADR cited in an added line exists in
`docs/decisions/` and supports the claim made:

| ADR | Cited for | Verdict |
|---|---|---|
| ADR-0004 | "the guarantee ADR-0004 protects is *reproducibility*, not *absence*" | ✓ — its Consequences say holdings "are always reproducible", and it explicitly defers "caching or materialised views … a future decision (new ADR)" |
| ADR-0021 | accepted, sandboxed/text-only/per-broker/preview-then-confirm PDF intake; "already-gated" narrow path | ✓ — title and Status: Accepted 2026-06-21 |
| ADR-0023 | display-only rebalancing hints; limit-price suggestion would need an amendment | ✓ — Accepted 2026-07-03 |
| ADR-0024 | portfolios demoted to internal compatibility record | ✓ — Accepted 2026-07-12 |
| ADR-0028 | corporate actions as ledger events, **shipped**, distinct from calendar-style security events | ✓ |
| ADR-0031 | covers *recorded* snapshots; forward projection deferred behind its own gate | ✓ — stated in the ADR description; story 19.7 deferred |
| ADR-0032 | "today's memo is deliberately volatile"; the data-version counter and as-of labelling are inherited, not invented | ✓ — "never survives a restart and never becomes a source of truth"; global data-version counter and as-of label both in the ADR |
| ADR-0035 | removed redundancy rather than caching it; must be argued against | ✓ (numbers: see F-8) |
| ADR-0036 | risk-tier rides the batch | ✓ |
| ADR-0017, ADR-0026, ADR-0038 | referenced in surrounding unchanged text | ✓ exist |

**Issue numbers.** All check out against GitHub and the triage index
(`feedback-triage-2026-08-12.md:700-731`):

- **#665** — "Sparse fieldsets, roll-up-only aggregates and server-side filters
  on read endpoints (API + MCP)", B1.1. Matches FR-37 exactly, including the
  whitelist constraint and the −70 % acceptance measure.
- **#666** — "Delta reads: `?since=` on the relevant read endpoints", B1.2, with
  push explicitly excluded. Matches FR-38.
- **#675** — "Maintenance lane in every epic batch (AGENTS.md amendment)".
  Matches the `AGENTS.md` insertion, including the list Hex/npm/Elixir-OTP/
  Postgres/BMAD/external BMAD modules and the attachment to ADR-0026 step 5.
  *(Note: the issue says "The `AGENTS.md` and `workflow_docs_test.exs` changes
  ship together"; this change touches `AGENTS.md` only. Not a factual error in
  the document — flagged only so the issue is not closed prematurely.)*
- **#677** — "Complete the audit-journal rollout". The number is attached to the
  right issue; the *claim* the issue and the documents share is wrong (F-1).
- **#663** — a **merged PR** ("owner feedback triage 2026-08-12 and the product
  brief for the identity gate", closed 2026-08-12). "accepted as #663" /
  "accepted by the merge of #663" is accurate, and matches the brief's own
  "the merge is the acceptance" (ADR-0026 step 4).
- **#340** — used for "the wealth-vision parking-lot issue". Consistent with
  `feedback-triage-2026-08-05.md:208` ("parking lot: wealth-management vision")
  and `feedback-triage-2026-08-12.md:485,500`. *(Pre-existing ambiguity, not
  introduced here: `epics.md:201` also maps FR-24/FR-25 to #340 for pension
  modeling. Same issue, two jobs.)*
- **#332** — what-if simulator, matches FR-27. ✓
- #356 and #678 do not appear in any added line.

**FR numbering.** No collisions. `epics.md` on `origin/main` tops out at
**FR-36**; the PRD's highest pre-existing number is also FR-36. The branch adds
exactly FR-37…FR-48 with no gaps and no reuse (full enumeration checked in both
files). NFR-9 and NFR-10 likewise do not collide — `origin/main` had NFR-1…NFR-8
in `epics.md`. The metric-basis cross-cutting rule at `epics.md:93` names
"FR-39 through FR-42, FR-47 and FR-48", which is exactly the ladder (a)–(c) set.

**Gate IDs B3.1–B3.8.** Every use matches
`feedback-triage-2026-08-12.md:329-441`: B3.1 identity, B3.2 durable derived
values, B3.3 data acquisition beyond quotes, B3.4 security events, B3.6 policy
rules, B3.7 push/webhooks, B3.8 local model. B3.5 (the rebalancing digest) is not
cited in the diff, correctly — its two cut elements are, and they match the
triage's cuts. Only the B4.1/B4.2 omission is a finding (F-4).

**Other codebase claims.**

- *"The existing risk and concentration endpoint"* — real:
  `lib/portfolixir/portfolios/risk.ex`, routed at
  `lib/portfolixir_web/router.ex:100`. It is a fair precedent for the
  metric-basis rule: `JSON.risk/1`
  (`lib/portfolixir_web/controllers/api/v1/json.ex:909-930`) emits `as_of` plus a
  `risk_note` that states the basis ("percentage scale over the steerable basis
  … a security held across depots is merged into one single-name exposure").
- *"The Sprint 5 value-slot vocabulary (pending/settling/final/not-computable) …
  already exists; the payload half does not"* — accurate. The vocabulary is
  specified as UX-DR20 (`design-language/EXPERIENCE.md:589`,
  `DESIGN.md:319,820`) and partly built: `value-slot-pending` /
  `recomputing-cue` markup in `portfolio_live.ex` and `dashboard_live.ex`, and
  `/* Value-slot pending and settling (UX-DR20…) */` at `priv/static/app.css:4597`.
  No API/MCP payload carries the state.
- *"MCP write tools are blocked"* — false, see F-1.
- *FR-33's scope lock* — accurate: `epics.md:82` reads "Scope lock:
  `securities_list` ONLY — explicitly no generic field-selection framework
  across endpoints", which is what FR-37 says it supersedes for this family.
- *README: "moving-average cost basis, unrealized P&L, price chart from local
  quote history"* — accurate (`lib/portfolixir/ledger.ex:13,184,437,518`).
- *README/`docs/index.md`: "it never calls an LLM itself"* — matches the
  `AGENTS.md` Security Boundaries rule "no external LLM calls from the app".
- *Addendum: `project-context.md` says "LiveView 0.20.x — NOT 1.x"* — accurate
  (`_bmad-output/project-context.md:26`); installed version is **1.2.8**
  (`mix.lock:34`, `mix.exs:56` `~> 1.2`). The disagreement is real.
- *Addendum: `epics.md`'s inventory carries a pre-2026-07-25 FR-1..FR-29, e.g.
  FR-4 still says portfolios partition the wealth space* — accurate
  (`epics.md:39` vs. `prd.md:384-387`, ADR-0024).
- *Addendum: the microcopy rule of 2026-07-23* — accurate
  (`_bmad-output/project-context.md:84-85`).
- *`AGENTS.md`: "The Dependency Update Policy in `project-context.md` still
  governs *how* an update lands — dedicated dependency-update PRs, never inside
  feature stories"* — quoted correctly (`project-context.md:44-45`).
- *PRD OQ-14's "existing on-demand ⓘ tooltip pattern (UX-DR11)"* — accurate:
  UX-DR11 is the explanatory-microcopy requirement (issue #356), and ⓘ is in use
  at eight call sites (`DESIGN.md:782`).
- *Success criteria 4–8 and the "quality bar"* — all faithfully carried from
  `briefs/brief-portfolixir-2026-08-12/brief.md:145-165` and its addendum
  (lines 93-100), including the escalation from "documented" to "stated in its
  API and MCP payload", which the brief addendum authorises, and the open UI
  question, which OQ-14 correctly records.
- *"the owner decided against duplicating registry authority"* —
  `.decision-log.md:218-224` records exactly that decision.

**Meta-tests.** `mix test test/portfolixir/workflow_docs_test.exs
test/portfolixir/docs_test.exs test/portfolixir/ci_test.exs` → 21 tests, 0
failures on this branch. Removing the "do not add advanced reports or advanced
classifications" line breaks nothing: no test or source file references that
string.

---

## Summary table

| # | Severity | File:line | Issue |
|---|---|---|---|
| F-1 | **Blocking** | `epics.md:108`, `prd.md:622`, `epics.md:224-226` | Audit-journal rollout is complete and MCP writes are shipped; the stated prerequisite is false |
| F-2 | Moderate | `AGENTS.md:277` | `workflow_docs_test.exs` concatenates the four docs; README carries no steps |
| F-3 | Moderate | `epics.md:122` | NFR-9 dates from 2026-07-25 (#615), not 2026-06-12 |
| F-4 | Moderate | `prd.md:608-609` | Thesis and prediction gates are B4.1/B4.2, not B3.1 |
| F-5 | Moderate | `epics.md:228` | NFR-9 coverage row implies a backstop that is not built |
| F-6 | Minor | `prd.md:438` | FR-27 is broader than ladder level (d); "literally" over-reads it |
| F-7 | Minor | `epics.md:101` | Alarm list rides B3.6; B3.7 is the push gate only |
| F-8 | Minor | `addendum.md:99-103` | A/B figures are in the measurement artifact, not in ADR-0035 |
| F-9 | Minor | `epics.md:36` | Reworded FR-1 omits the shipped `split` kind |
