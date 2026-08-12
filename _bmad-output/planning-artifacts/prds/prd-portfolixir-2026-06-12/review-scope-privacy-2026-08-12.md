# Scope and privacy review — identity gate B3.1 branch (2026-08-12)

**Branch:** `agent/claude/identity-gate` — 4 commits, diffed against `origin/main`.
**Reviewer role:** scope-and-privacy auditor (AGENTS.md → Hard Rules, Privacy And
Disclosure, Security Boundaries, Scope Lock).

**Files in the diff:**
`AGENTS.md`, `README.md`, `docs/index.md`,
`_bmad-output/planning-artifacts/epics.md`,
`_bmad-output/planning-artifacts/prds/prd-portfolixir-2026-06-12/prd.md`,
`.../addendum.md`, and `.../.decision-log.md` (the last was not in the audit
brief handed over — reviewed anyway, see L4).

**Authorities the change was held against:**
`_bmad-output/planning-artifacts/briefs/brief-portfolixir-2026-08-12/brief.md`
and its `addendum.md`, `feedback-triage-2026-08-12.md` Round 3, and the recorded
privacy scope decision of 2026-07-25 in the PRD addendum.

## Verdict

**Not yet safe to publish — two fixes needed, both in the public-facing copy.**

Privacy is clean and commit hygiene is clean; neither dimension produced a
finding. The scope amendment did what the brief authorized and removed nothing
it was not told to remove — the permanent non-goals survived intact. What blocks
publication is section 3: the rewritten `README.md` and `docs/index.md` describe
unbuilt capability in the present tense and drop every maturity caveat, which is
the "Do not claim production readiness" rule. The scope gaps (H3, M1) are
contract holes rather than publication blockers, but they are cheap to close on
the same branch and the batch is the right place for them.

---

## Critical

None.

---

## High

### H1 — README and docs/index.md state unbuilt capability in the present tense

`AGENTS.md` → Hard Rules: *"Do not claim production readiness."* The new opening
copy makes four assertions of fact that this branch's own documents contradict.

1. **"Portfolixir gives every such fact a home with an identity, a source, and an
   age."** (`README.md`) — the "such facts" the preceding sentence names are a
   thesis note keyed to a taxonomy and a date living in a scheduled prompt. Those
   are the knowledge objects FR-45 and FR-44, registered as *unbuilt* in
   `epics.md` in this very commit, with no issue and blocked by #677. Target
   weights, the third example, do exist. Two of the three illustrations describe
   a product that does not exist yet.

2. **"the same figures the agent read over MCP, each stating the age of its
   inputs"** (`README.md`) — `addendum.md`, added in the same batch, says the
   opposite in plain words: *"The Sprint 5 value-slot vocabulary … is the UI half
   of FR-1's freshness property and already exists; the payload half does not."*
   The README advertises the half that does not exist.

3. **"Everything it knows is reachable through a local JSON API and an MCP
   companion"** (`README.md` and `docs/index.md`) — `epics.md` (unchanged,
   same branch) records that MCP data-maintenance writes are *deliberately*
   blocked behind the incomplete audit-journal rollout, and that the
   "every write is auditable" guarantee is **"not yet actually met"**. That block
   is a good decision; stating unqualified reachability over it is not.

4. **"everything it knows is also visible on a screen"** (both files) — directly
   contradicted by the rule this same batch adds to `AGENTS.md`: an agent-visible
   capability *may ship over API and MCP alone, with no human view*, for up to
   one epic batch. The batch simultaneously promises the property in public and
   licenses its temporary absence in the contract.

**Why this is High rather than Medium.** These are the first paragraphs a
stranger reads on `portfolixir.app`. The prior copy was descriptive and modest —
"an application for local portfolio tracking … it helps you keep securities,
portfolios, depots …". The replacement is a product promise. A promise made
before the thing exists is the production-readiness claim the rule forbids,
whether or not the words "production ready" appear.

**Recommended fix (cheap).** Keep the identity sentence — it is the accepted
decision and it is good. Move the aspirational half into the future tense the
brief itself uses, or scope it to what ships: *"Everything it knows today is
reachable through a local JSON API and an MCP companion (reads; agent writes
land with the audit journal), and is also visible on a screen."* For the third
bullet, drop "each stating the age of its inputs" until the payload half of FR-1
lands, then add it back. The `## What works today` section directly below is
accurate and does the honest work — the opening should not outrun it.

### H2 — Every maturity and security caveat was dropped from the public entry points

Neither `README.md` nor `docs/index.md` now carries any statement of maturity,
security posture, or upgrade guarantee. A grep for "not production", "early",
"alpha", "beta", "experimental", "no warranty", "trusted network" and
"unauthenticated" across both files returns nothing.

This matters *because of what changed in the same batch.* The PRD's Users section
was rewritten to promote third-party self-hosters from "Future self-hosters
(quality bar, not a commitment)" to a first-class audience — **and it states the
honest caveat while doing so**:

> the web UI is **unauthenticated by design** (NFR-4, OQ-8) and there is **no
> upgrade guarantee** (OQ-10), so what a stranger adopts today is a tool for a
> trusted network.

The README, addressing that same newly-promoted stranger in the second person
("your holdings, your agent, your machine"), carries none of it. The internal
document is honest and the public one is not — which is exactly the wrong way
round. The invitation got louder and the warning disappeared in the same commit.

**Recommended fix.** One sentence in `README.md` and one in `docs/index.md`,
lifted from the PRD's own wording: the web UI is unauthenticated by design and
there is no upgrade guarantee, so run it on a trusted network. This is not a
scope change and needs no gate — the PRD already says it.

### H3 — The binding contract records one of four gated boundaries

The brief's Scope section and the PRD's section 4 both gate **four** things:

| Gated item | Gate | In PRD §4 | In `AGENTS.md` |
|---|---|---|---|
| (d) backtesting against stored price history | B3.6 | yes | **yes** |
| data acquisition beyond quotes and FX | B3.3 | yes | **no** |
| push delivery to external endpoints | B3.7 | yes | **no** |
| a local model beyond ADR-0021 PDF intake | B3.8 | yes | **no** (incidental) |

`AGENTS.md` is the file agents read and are held against; the PRD explicitly is
*not* the live registry. The amendment named only level (d). Of the three
omissions, B3.8 is incidentally covered by the surviving hard rule forbidding
"LLM behavior" unless a reviewed story changes scope. **B3.3 and B3.7 are covered
by nothing.** The blanket analytics rule that was retired in this commit was the
nearest thing to a catch-all, and it is gone.

Push delivery is the sharper of the two: the brief's own addendum parks it as a
**security** decision — *"request-forgery surface, stored secrets and retry
semantics"* — and `AGENTS.md` → Security Boundaries says nothing about outbound
delivery to configured endpoints. `epics.md` does carry the constraint, but only
as a per-requirement note under FR-38 ("the push half stays gated at B3.7 and
must not ride the same story"), which an agent working on an unrelated story will
never see.

This is an incomplete transfer rather than a deliberate widening — nothing in the
brief was contradicted, and the decision log shows the author guarding carefully
against widening elsewhere (see the explicit "advanced *classifications* stay out
of scope" entry). But the effect on the contract is the same.

**Recommended fix.** Extend the ladder bullet in `AGENTS.md` with the sentence
the PRD already carries: *"Gated, not in: ladder level (d); data acquisition
beyond quotes and FX (gate B3.3); push delivery to external endpoints (gate
B3.7); a local model beyond the already-gated ADR-0021 PDF-intake path (gate
B3.8)."* One sentence, copied verbatim from the accepted PRD.

---

## Medium

### M1 — NFR-9's revised guarded set describes meta-tests that do not exist

Both `prd.md` and `epics.md` now assert, in the present tense, that the hard
gates *"are backed by meta-tests in the invariant suite"* and that since the
identity gate the guarded set is *"Phase 3 sync, FR-5 XML intake, **the permanent
non-goals and the level-(d) backtesting gate**, in place of the retired blanket
analytics gate."*

Verified against the tree:

- `test/invariants/` contains thirteen files; a grep across all of them for
  `backtest`, `advanced`, `analytics`, `non-goal`, `order`, `trading`, `payment`
  returns **zero** matches. The suite guards Decimal persistence, projection
  catch-alls, CSS tokens, the MCP dependency allowlist and the web/repo boundary.
- `test/portfolixir/docs_test.exs` is the only relevant guard, and it is a
  literal-string refute list (`"trading exists"`, `"order placement exists"`,
  `"rebalancing exists"`) applied to **documentation text only**, not to code.
- `epics.md`'s own Requirements Inventory lists NFR-9 with **no issue**.

So the batch retired a textual gate and pointed at a mechanical gate that has not
been built. NFR-9's own closing sentence names the risk precisely — *"a gate that
lifts partially is exactly the kind a reader mistakes for lifted entirely"* — and
the batch then created that condition.

**Recommended fix.** Mark the revised guarded set as *owed* rather than *in
place* (the wording NFR-8 already uses for itself: "Still **aspirational**: no
instrument measures it"), and open an issue for the meta-test. Do not leave a
present-tense claim of mechanical enforcement standing over an absent test — in a
project whose PRD says the owner does not read code, this is the one class of
claim that must not be aspirational.

### M2 — `AGENTS.md` now contradicts itself on dependency updates, two paragraphs apart

The new maintenance lane closes with:

> The Dependency Update Policy in `project-context.md` still governs *how* an
> update lands — dedicated dependency-update PRs, never inside feature stories.

Verified: `_bmad-output/project-context.md` says exactly that, so the quotation
is accurate. But the very next block in the same section is the ADR-0036
paragraph:

> Ledger/money-domain math and invariants, security-relevant changes,
> **dependency updates**, and anything touching import idempotency or projection
> semantics ship **inside the epic batch like everything else** — the former
> "dedicated small PR with real human review" exception is withdrawn …

One paragraph withdraws the dedicated-PR exception for dependency updates; the
next reinstates it by reference. The contradiction pre-existed between the two
documents, but this commit is what moved both claims into the same section of the
same file, where an agent must now pick one.

**Recommended fix.** Reconcile in favour of ADR-0036 (the later, signed-off
decision): the maintenance lane's updates ride the batch as their own commit
group, and `project-context.md`'s policy is what needs the amendment note.

### M3 — The README's lead example is the closest the public copy has come to the advice line

The first of the three "questions the tool answers" is *"Which categories drifted
away from their targets, and **what would it take to correct them?**"* — with the
indicative corrective quantity as the answer.

This is in scope: ADR-0023 authorizes display-only rebalancing hints, and
`epics.md` confirms FR-12 partially landed with exactly that. The finding is one
of framing, not scope. "No advice" is a **permanent non-goal**, restated as
identity in this same batch, and the README now promotes corrective quantities to
the product's first advertised job. The mitigating sentence — "It is not a
broker, bank, trading, payment, order, or rebalance platform" — sits three
paragraphs below, where a skimming reader will not reach it.

**Recommended fix.** Add one qualifier inline: "an **indicative, display-only**
corrective quantity". Six words, and the boundary travels with the claim instead
of trailing it.

### M4 — The docs guard is string-based and did not catch H1

`test/portfolixir/docs_test.exs` states its acceptance criterion as *"Public docs
avoid deployment process and deferred capability claims"* and *"the documentation
describes the current local self-hosted scope"* — the right intent. Its mechanism
is `refute docs_text =~ claim` over a fixed phrase list. The new copy in H1
asserts capability the project does not have while containing none of those
phrases, so the suite passed.

Not a defect in this change, but worth recording while the batch is open: the
guard that is supposed to keep the public docs modest cannot see the modesty
failures this batch introduced. If H1 is fixed by prose edit alone, nothing stops
the next rewrite from reintroducing it.

---

## Low

### L1 — Ladder level (a) wording drifted in the binding file only

`AGENTS.md` reads *"per security and per view"*. The brief's Scope and Round 3 of
the triage both say *"per security and per portfolio"*; the brief addendum and the
PRD say *"per portfolio or view"*. The one document that dropped "portfolio" is
the contract. Harmless in substance — views are the broader concept — but align
it with the PRD's "per portfolio or view" while the file is open.

### L2 — Observation: the operator's investment strategy is carried forward in PRD §2

The bullet reads: *"Self-hosts the app; invests with a deliberate **maximum risk
performance** strategy (stocks and Bitcoin) over a long horizon and plans
retirement under German pension rules."*

**Not a finding.** It is pre-existing text on `main`, it sits inside the recorded
owner decision of 2026-07-25 (operator named openly; what stays out is *concrete
financial values* and *anything about family or household*), and it carries no
amounts, positions or performance figures. This commit in fact **improved** the
privacy posture of that bullet by removing the operator's personal first name
from the persona label.

Recorded only because the bullet's opening line was rewritten here, so the clause
was in the author's hands and could have been genericized at zero cost
("a long-horizon, high-risk-tolerance strategy"). Asset-class disclosure attached
to a named real person is the weakest link left in the PRD. Owner's call — the
decision is recorded and this reviewer is not reopening it.

### L3 — The brief's frontmatter still says `status: proposed`

The brief's own acceptance rule is its merge, and it merged as #663. The decision
log correctly flags the frontmatter as stale. Fix belongs on the brief, not on
this branch.

### L4 — `.decision-log.md` was in the diff but not in the audit scope; reviewed, clean

107 added lines, committed (not gitignored). Agent decision logs are the
highest-risk artifact class under the Privacy rule — they are written mid-session
with real context in the window. This one is clean: no figures, no names, no
local paths, no household references. It records the FR-1 rewording rationale,
the uneven section-C gate resolution, the nine-step Story Workflow decision, and
the README tone tension. Flagging only that it reached the diff without being
listed for review; a scrub pass should be explicit for this file class, not
incidental.

---

## Dimensions that produced no findings

### Privacy — clean

Every added line in the diff was scanned for: currency symbols and amounts
(`€`, `$n`, `EUR n`, `USD`), IBAN/BIC/xpub, named banks and brokers, absolute
local paths (`/home/`, `/Users/`, `C:\`), private IP ranges, hostnames, personal
email addresses, and the maintainer's name and handles. **Zero hits.**

Every number introduced by the batch is operational, not financial: `≤ 5 calls`,
`~25 calls`, `−70 % response volume`, `1,105 ms → 265 ms`, `2,614 → 115
queries`, `1755 tests`, `p95 < 2 s`, `90+ days`, `ten resolved predictions`. None
of them says anything about anyone's holdings.

The material imported from the brief and the feedback triage — the flagged risk —
was **genericized on the way in**, and correctly. The brief's Problem section
attributes the drift cases to the operator's own agent and quantifies them
("within a single two-day window five of those facts had drifted … target weights
that existed in three places with two of them stale"). The PRD's version is an
unattributed shape statement: *"Dates, theses, target weights and tax state kept
in local files and in the text of scheduled prompts drift from reality."* No
count, no window, no owner. The README goes further still and drops to three
anonymous illustrations. This is the scrub the brief's addendum promised, and it
was performed.

No household, family or pet references anywhere in the diff. No banking
relationship newly attached to the operator's accounts.

### Scope discipline — the amendment did not widen beyond its authority

Every line removed from `AGENTS.md`, `README.md` and `docs/index.md` was checked
against the brief's addendum. The complete removal set is:

- the old Project Goal opening sentence (authorized: addendum, "Project Goal —
  two edits");
- `- Do not add advanced reports or advanced classifications.` (authorized: the
  ladder replaces it);
- the one-way API/MCP coverage sentence (authorized: "API and MCP Coverage
  becomes symmetric" — and it is preserved verbatim as the first bullet of the
  replacement, not dropped);
- three README/docs definition sentences (authorized: "For the README rewrite").

**The permanent non-goals survived intact and were not softened.** All six —
no broker connection, no order creation or transmission, no automated trading or
payment, no advice, no raw news archive, no external LLM calls from the app —
appear in the new `AGENTS.md` hard rule, in the PRD's section 4, and match the
triage's Round 3 wording exactly. They were additionally *strengthened* in two
ways this reviewer credits: restated as identity ("no capacity argument reopens
them") rather than as a backlog boundary, and the README's negative claim gained
a clause ("and it never calls an LLM itself: agents call Portfolixir, not the
other way round").

The pre-existing catch-all hard rule — document intake, broker sync, bank sync,
trading, payment, order, rebalance, LLM behavior — is untouched, as is the entire
Security Boundaries section. `ADR-0023`'s display-only carve-out is unchanged.
Advanced *classifications* were explicitly held out of scope in the replacement
text, matching the addendum's instruction and the Round 3 confirmation; the
decision log shows this was a conscious guard against exactly the widening this
audit looked for.

The additions beyond the addendum's literal list — the `workflow_docs_test.exs`
note under Story Workflow, and the `project-context.md` pointer in the
maintenance lane — are descriptive rather than normative. The first is accurate
and useful. The second is the M2 contradiction.

### Commit hygiene — clean

| Commit | Author | Committer |
|---|---|---|
| `f636e1c` | Andreas Hubert \<peshay@me.com\> | same |
| `283217a` | Andreas Hubert \<peshay@me.com\> | same |
| `1fa44e0` | Andreas Hubert \<peshay@me.com\> | same |
| `90ccbd8` | Andreas Hubert \<peshay@me.com\> | same |

`peshay@me.com` is on `.github/commit-authorship-allowlist.txt`. Author and
committer match on all four commits.

A scan of all four commit bodies for `Co-authored-by`, `Model:`,
`Thinking level:`, `Claude-Session:`, `claude.ai/code`, `Generated with` and
`noreply@anthropic` returns **nothing**. The decision log records that the
environment had defaulted to a bot identity and that authorship was corrected
before the first commit — the hook would have caught it, and the author did not
wait for the hook.

Commit bodies are substantive, in English, and explain rationale rather than
restating the diff. The risk-tier FR-1 rewording was given its own commit with an
explicit callout, per ADR-0036.

---

## Fix list, in order

1. **H1** — remove or future-tense the four unbuilt-capability claims in
   `README.md` and `docs/index.md`. *Blocking.*
2. **H2** — add the unauthenticated-UI / no-upgrade-guarantee caveat to both
   public entry points, using the PRD's own wording. *Blocking.*
3. **H3** — copy the PRD's four-item "Gated, not in" sentence into the
   `AGENTS.md` ladder bullet.
4. **M1** — restate NFR-9's revised guarded set as owed, and open the meta-test
   issue.
5. **M2** — reconcile the dependency-update contradiction in favour of ADR-0036.
6. **M3** — add "indicative, display-only" to the README's first example.
7. **M4, L1, L3** — opportunistic, same branch.
