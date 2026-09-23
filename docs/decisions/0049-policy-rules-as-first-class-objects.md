---
layout: docs
title: "ADR-0049: policy rules as first-class objects — a rule is a standard in force over a period, evaluated at read into findings that carry no action"
description: "Decision for gate B3.6 (FR-43). A policy rule is a stored predicate (cap, floor or band) over one named measure that an existing read already produces: a weight, a drift, the HHI, or a portfolio metric of ADR-0047. Rules are versioned and effective-dated, so the question which standard was in force on a given date is answered by a read rather than by journal forensics; a version that has been in force is never edited. Evaluation happens at read time into findings with three states (ok, breached, undetermined), and undetermined never counts as passing. A finding names the rule and the measured value and carries no action, no quantity and no advice. The protected and budget rule types, rules over events, push delivery and the rebalancing digest stay out, each with its reason."
---

# ADR-0049: policy rules as first-class objects

- **Status:** Accepted (decision gate **B3.6** per
  [ADR-0026](0026-epic-batch-workflow.html)). The owner signs it by merging
  the Sprint 15 planning PR (step 1 as amended on PR #780: the merge is the
  signature).
- **Date:** 2026-09-23
- **Answers:** FR-43. §11 lists the asks it answers and the ones it defers, per
  [ADR-0043](0043-a-gate-closing-adr-names-its-asks.html).
- **Opens nothing else.** B3.5 (the rebalancing digest), B3.7 (push delivery)
  and ladder level (d) (rule backtesting) stay shut; §10 says how each one is
  kept out.

## Context

FR-43 has been in the requirements inventory since the identity gate of
2026-08-12, and its own text names the defect: caps and floors live **as prose
inside scheduled prompts**, "which is exactly where the observed drift came
from". The owner's portfolio agent has since reported the same drift a second
time, independently (2026-09-19 round, P0-3, recorded in
`feedback-triage-2026-09-19.md` §3.3 as the strongest argument yet for opening
this gate).

The shape of today's workaround matters, because it is what this record
replaces. The concentration lens (`Portfolixir.Portfolios.Risk`, FR-8/FR-9/FR-10)
already evaluates thresholds, but only ones **passed per request**:
`asset_class_caps`, `stock_thresholds` and `etf_thresholds` are query
parameters with shipped defaults. So every caller restates the operator's
policy on every read. The agent does that from its prompt, and the prompt is
where the policy drifts. The human operator cannot do it at all: the Risk tab
states that caps "are set per request over the API".

Sprint 14's plan (D-6) held this gate shut for one sprint, for a reason about
order rather than merit: a rules engine reads the metrics ADR-0047's portfolio
half ships, so the record should name real fields, real refusal states and
real `required` thresholds, not anticipated ones. That payload shipped on
2026-09-23 (PR #846). D-6 named this planning PR as the trigger and recorded
the two questions the record must answer: **what a rule is**, and **what
happens to a rule's history when it is edited**. §1 and §4 answer them.

This record follows ADR-0048's discipline: build the object and its reads,
and say no to everything the object invites — alerting, a digest, advice,
replay. None of those is asked for here, and each has its own gate.

## Decision

### 1. A rule is a predicate over one named measure, stored as an object

A **policy rule** says that one measure, for one subject, in one evaluation
context, must stay under a cap, above a floor or inside a band. It is stored
as a row, not as prose, and it is read by the same API and MCP surface as
everything else. Parts:

| Part | Values | Meaning |
|---|---|---|
| **context** | `portfolio_id`, `view_id` (nullable) | where the rule is evaluated. `view_id NULL` is the portfolio-wide scope, the same convention target plans use ([ADR-0020](0020-view-bound-soll-plans.html)). The measure is read on that context's steerable basis. |
| **subject** | `basis` · `security` · `category` · `view` · `cash` | what the measure is taken of. `security` carries `security_id`; `category` carries `classification_id` + `category_id`; `view` carries the subject view's id (see §2). |
| **measure** | a closed `Ecto.Enum` (§2) | which figure the rule reads. |
| **kind** | `cap` · `floor` · `band` | `cap`: breached when the value is strictly above `threshold`. `floor`: breached when strictly below. `band`: breached when outside `[lower, upper]`. |
| **thresholds** | `threshold`, or `lower` + `upper` (Decimal) | on the measure's own scale and sign, as the source payload states it. |
| **window** | `30d` · `90d` · `365d`, only for the metric measures | the ADR-0047 window the rule reads. |
| **severity** | `warn` · `hard` | the lens's existing vocabulary, reused rather than reinvented. |
| **name**, **note** | text | the operator's words, never parsed. |
| **validity** | `valid_from`, `valid_until` (nullable) | the period the version is in force (§4). |

"Strictly" is deliberate and inherited: the lens's `severity` is `ok` until a
weight is strictly above `warn` (counter-metric CM3: a breach is a real
crossing, never noise). A rule that disagreed with the lens about where a line
is would be a second truth about the same number.

The enums are `Ecto.Enum`s and never `String.to_atom/1` at the boundary (the
hard rule). Every member gets a gettext label clause with no `to_string`
fallback, under the enum-label meta-test Sprint 12 added.

### 2. The measures: v1 reads figures that already exist, and computes nothing new

A rules engine that computes its own figures becomes a second analytics
engine, with its own rounding and its own gaps. So every v1 measure is **read
off a payload the product already serves**, and the finding names that read as
its computation basis:

| Measure | Subjects | Scale | Source read |
|---|---|---|---|
| `weight` | `security` · `category` · `cash` · `view` | percent of the context's steerable basis, 0–100 | the risk lens's merged single-name weight (security); the allocation breakdown's actual weight (category, cash); for `view`, the subject view's steerable basis over the context's, both from `Valuation` |
| `drift` | `category` · `security` | percentage points, actual − target | the allocation drift of the context's **active** plan, the same figure ADR-0023's hints sit beside |
| `hhi` | `basis` | 0–10000 | the risk lens |
| `volatility` | `basis` | percent, annualized | ADR-0047's portfolio metrics, at the rule's window |
| `max_drawdown` | `basis` | percent, in the metric's own sign | ADR-0047's portfolio metrics, at the rule's window |

`view` as a subject is how FR-43's **bucket** scope is answered. Buckets are
tags, and a view is the saved filter over them
([ADR-0018](0018-buckets-tag-based-wealth-scoping.html)). "The speculative bucket stays
under 5 % of everything" is therefore a `weight` cap on the view that selects
that bucket, evaluated in the portfolio-wide context. Adding a second
bucket-weight computation beside the view model would give the product two
answers to one question.

**Deliberately not measures in v1:**

- `correlations` is a matrix, not a scalar per subject.
- `risk_adjusted_return`: a floor on it is a performance target rather than an
  exposure limit, and nothing in FR-43's list asks for one.
- The per-security metrics of ADR-0047 §3 (a rule over one security's
  momentum is a signal in all but name).
- Anything over security events.

§11 records each of these as deferred with its reason.

### 3. Three states, and undetermined never passes

Evaluating a rule produces a **finding** in exactly one state:

- `ok`: the measure was read and is on the right side of the line;
- `breached`: the measure was read and is strictly beyond it;
- `undetermined`: the measure could not be read. This covers a metric that
  refused (ADR-0047 §5), a `drift` rule whose context has no active plan or
  no target for the subject, a `weight` rule on a security that is not held
  (weight is `0`, which *is* a reading, so a floor on it can breach; a
  **removed** subject is undetermined), and a view subject that no longer
  exists.

**An undetermined finding is never counted as `ok`, is never filtered out by
default, and carries the reason.** When the reason is a metric refusal, it
also carries the metric's `required` and `observations` (ADR-0047 §6 as
amended 2026-09-19). This is the invariant the record exists for, next to
"a deposit is not a return" in ADR-0047. A rule set that reads green because
half its inputs were missing is worse than no rule set: it is the prose drift
again, with a check mark on it.

### 4. History: a rule is a standard in force over a period, so it is versioned and effective-dated

D-6 recorded the question: when a rule is edited, what happens to its history?
The two records this project already has answer it in opposite ways, and
neither answer fits.

- **[ADR-0044](0044-security-knowledge-as-an-append-only-log.html) (append-only
  log):** a research entry is an *argument*, and its history *is* its meaning.
  A rule is not an argument. Nobody reads the old cap to learn why the new
  one was set.
- **[ADR-0048](0048-security-events-as-first-class-objects.html) (mutable row,
  history in the journal):** an event is a *fact*, and an outdated fact is
  simply wrong, so its history is an audit trail. A rule's old threshold is
  not wrong. It **was the standard** for a period, and that period is exactly
  what later questions will ask about.

A rule is a **standard in force over a period**. The question its history
must answer is *"what was the standard on date D?"*, and a read must answer
it, not a reconstruction from the audit journal. That is the question
FR-48 (level (c): did the rules produce findings that mattered?) cannot be
answered without. The in-repo precedent is the target plan: named, versioned,
at most one active version per scope ([ADR-0027](0027-plan-versions-and-depot-snapshots.html)).

So a rule has a stable identity (`policy_rules`: name, context) and one or
more **versions** (`policy_rule_versions`: the predicate of §1 plus
`valid_from` and `valid_until`):

- **Editing a rule creates a new version.** The new version gets `valid_from`
  (today by default, or a later date). The previous version's `valid_until`
  is set to the day before. Versions of one rule never overlap. That is a
  database constraint, not only a changeset check.
- **A version that has been in force is immutable.** It is never updated and
  never deleted. A version whose `valid_from` is still in the future may be
  edited or deleted, because nothing has ever been measured against it.
- **Retiring a rule** sets `valid_until` on its current version. The rule and
  all its versions stay readable.
- **Both tables are journaled from their first migration**
  ([ADR-0017](0017-append-only-audit-journal.html)). The journal records *who*
  changed the standard; the versions record *what* the standard was. An agent
  writes these rows, which is why the journal is non-negotiable, as it was for
  ADR-0044 and ADR-0048.

Versioning also carries the level (c)/(d) boundary. Evaluating a version over
dates inside its validity scores a rule against a period in which it was
recorded, which is level (c). Evaluating it over dates **before its
`valid_from`** replays a rule over a history that did not have it, which is
level (d) and forbidden. The boundary is therefore a column, not a code-review
habit. §10 pins it.

### 5. Evaluation happens at read, and findings are never stored

Findings are **derived**. They are computed when read, over the current state,
and never persisted as rows:

- **One read**: `GET /api/v1/portfolios/:portfolio_id/policy_findings`, with
  `view=` as every scoped read has it and `status=` to filter
  (`status=breached` is the **retrievable alarm list**, the pull half of
  B3.7 that FR-43 names). MCP twin: `portfolixir.portfolios.policy_findings`.
- **One finding per rule in force** for that context. Each finding carries:
  the rule id and version, name, kind, severity, thresholds, measured value,
  `state`, the signed distance to the nearest threshold (arithmetic, on the
  measure's scale), and a **`computation_basis`**. The basis names the source
  read, its window where there is one, and its `as_of` (the metric-basis rule
  of AGENTS.md applies to findings exactly as it applies to metrics).
- **Registered with [ADR-0039](0039-durable-derived-values.html)** as
  `policy_findings` at computation version 1, default lifetime `:request`,
  keyed under `DataVersion.portfolio_basis/1` **and** a rules counter that
  every rule write bumps. A finding that outlived an edited cap would be a
  stale answer to the only question the read exists for.
- **Engine and shell.** `Portfolixir.Engines.PolicyEvaluation` is pure: it
  takes rule versions and a measure map and returns findings, with no Repo,
  clock or config. The shell loads the measures from the existing reads of §2
  (architecture AR-2).
- **v1 evaluates today only.** "Which rules were breached on date D" needs
  the valuation walk at D and is FR-48's input. §4 makes it possible and
  §11 defers it.

### 6. A finding carries no action

A finding reports that the operator's own rule, applied to a figure the
product already shows, is on one side of the operator's own line. It does
**not**:

- say what to do: no `action`, `recommendation`, `suggested_*`, `buy`/`sell`,
  no quantity, no order-shaped field;
- rank findings by urgency beyond the rule's own `severity`;
- compute a corrective trade. ADR-0023's display-only hints stay where they
  are, beside the drift figure, and are not copied into findings.

A **key-set meta-test**, the sibling of ADR-0047 §7's
`metrics_carry_no_verdict_test.exs`, walks the findings payload and fails on
any such key. The permanent non-goal "no advice" is the reason. The finding's
`state` is not the system's verdict: it is the rule the operator or the agent
wrote, evaluated. A digest that turns findings into proposed trades is B3.5
and stays shut.

### 7. The lens's request parameters stay, and the two mechanisms do not read each other

The risk lens keeps its per-request `asset_class_caps` and threshold
parameters, and its shipped single-name defaults, unchanged. Stored rules do
not feed the lens's `severity` badges, and the lens does not read stored
rules. Two mechanisms that read each other would give one number two
severities depending on which path computed it.

The shipped defaults are a generic concentration heuristic. Rules are this
operator's policy. The human view (§9) keeps them visually apart. Whether the
lens should one day *default* its caps from stored rules is deferred (§11):
it changes an existing payload's meaning, and no caller has asked.

### 8. Writes, identity and the re-import guarantee

- **Writes on API and MCP**, journaled with the actor (UI session or token,
  AR-1): create a rule with its first version, add a version (the edit), and
  retire. Deleting a rule is allowed only while none of its versions has
  been in force (§4).
- **Validation is per measure.** Weights lie in `[0, 100]`, drift in
  `[−100, 100]`, HHI in `[0, 10000]`, and volatility is `≥ 0`. `lower ≤ upper`
  for a band. The subject must fit the measure (the matrix of §2). The window
  is present exactly for the metric measures. Every financial figure crosses
  the boundary as a Decimal string (ADR-0016).
- **Referenced objects are protected.** Deleting a security, category or view
  that a rule version references answers **409** and names the rules. That is
  the same answer the security-events family gives
  (ADR-0048, Sprint 13 closing act). Retiring the rule first is the remedy,
  and the error says so.
- **A Portfolio Performance re-import preserves rules.** The rows key on
  `security_id`, `category_id` and `view_id`. Securities survive a re-import
  by construction ([ADR-0029](0029-stable-identities-and-reimport-survival.html)),
  and categories and views are Portfolixir-owned. The guarantee is **pinned in
  the same batch** in `reimport_preservation_test.exs`, stated in the
  integration docs' re-import section, and named in the MCP tool
  descriptions. Sprint 14's #831 established that last point: a consumer
  reads the tool description, not the doc page.

### 9. Surfaces, agent and operator in the same batch

- **API and MCP**: the writes of §8 and the reads of §5, plus the rule list
  itself. The list covers rules in force now and, with `as_of=`, rules in force
  on a date. With `include_retired=true` it also returns retired rules. One
  rule's version history completes the reads. `?since=` fits the rule list,
  because it is a row collection with `updated_at`. It does not fit the
  findings read, a derived projection, for the reason #849 records. The
  close-out's surface check says both.
- **The contract-version read reports the new family** (ADR-0044 §8).
- **The human view lands in the same batch.** Its placement is the design
  pass's pick (Sprint 15 plan, pick **F1**). Whichever variant is built, it
  must show findings with **breached and undetermined first**, show the rule's
  words next to the measured value, keep the lens's generic thresholds
  visually distinct from the operator's rules (§7), and let the operator
  create, edit and retire a rule without the API.

### 10. What this record does not open

- **No push.** `status=breached` is a pull read. Any outbound delivery (a
  webhook, a mail, a notification) is **B3.7** and stays shut.
- **No digest and no trades.** Turning findings into a proposed rebalance is
  **B3.5** (P0-2) and stays shut. §6 pins the payload against it.
- **No replay.** Evaluating a rule version before its `valid_from` is ladder
  level **(d)**. The findings read evaluates today only (§5). Any later
  historical read must refuse a date before the version's `valid_from`, and
  the story that builds it pins that with a test.
- **No rule evaluation yet.** Whether rules produced findings that mattered is
  **FR-48**, level (c). It needs a history of findings, and §4 is what makes
  that history computable later. Not built here.
- **No rules over events** ("warn me when a lockup is within 14 days"): §11.
- **No local model, no fetched thresholds.** A rule is written by the operator
  or the agent, and nothing extracts one from a document (NFR-10, B3.8).

### 11. The asks, answered and deferred (ADR-0043)

**Source of the asks:** FR-43 as written in the requirements inventory;
the brief's addendum of 2026-08-12 (the policy-rule object row); the
2026-09-19 agent round's P0-3 and P1-6's trigger half; and Sprint 14's D-6,
which recorded the two questions this gate was to answer.

| Ask | Source | Verdict |
|---|---|---|
| Rules as stored objects, not prose | FR-43, P0-3 | **Answered**: §1 |
| Type **cap / floor / warning band** | FR-43 | **Answered**: §1, `cap`, `floor`, `band` with a severity |
| Type **protected** | FR-43 | **Deferred.** "Do not sell this" is a predicate over *bookings* (a sale in a period), not over *state*, and its main consumer is the rebalancing digest, which is gated at B3.5. Filed in the same pass as the Lane Z issue for flow rules. |
| Type **budget** | FR-43 | **Deferred**, same reason: a budget ("at most X of new money into Y per year") sums flows over a period. That is risk-tier ledger arithmetic with its own period semantics, and it gets its own story. Same issue as `protected`. |
| Scope **category, bucket, security** | FR-43 | **Answered**: §1 and §2. The bucket scope is answered through the `view` subject, with the argument. |
| Threshold, severity | FR-43 | **Answered**: §1, lens vocabulary reused |
| Validity period | FR-43 | **Answered**: §4, `valid_from` / `valid_until` per version |
| History, so a changed rule is visible afterwards | FR-43, D-6 question 2 | **Answered**: §4, versioned and effective-dated, argued against both precedents |
| What a rule is | D-6 question 1 | **Answered**: §1 and §2, a predicate over a named measure that an existing read produces |
| Evaluated server-side into structured findings | FR-43 | **Answered**: §5 |
| A retrievable alarm list (pull half of B3.7) | FR-43, P1-6 | **Answered**: §5, `status=breached` |
| Push delivery of an alarm | P1-6 | **Out of scope, gated**: B3.7, §10 |
| Rules over portfolio metrics (volatility, drawdown) | D-6 ("a rules engine reads the metrics A1 ships") | **Answered**: §2, with the refusal carried as `undetermined` (§3) |
| Rules over `risk_adjusted_return`, correlations, per-security metrics | this record | **Deferred**: §2. A return floor is a performance target, a matrix is not a scalar, and a rule over one security's momentum is a signal. Each needs its own argument, and no consumer has asked. |
| Rules over security events | ADR-0048 §8 | **Deferred.** A time-derived predicate ("within N days") is a different evaluation, whose membership changes with no row changing (the #830 lesson). It comes after v1 has been used. |
| Historical findings ("breached on date D") | FR-48's input | **Deferred** to FR-48. §4 makes it computable, and §10 fixes the (c)/(d) boundary it must respect. |
| The lens defaulting its caps from stored rules | this record | **Deferred**: §7. It changes an existing payload's meaning, and no caller asked. |
| The rebalancing digest | P0-2 | **Out of scope, gated**: B3.5, §10 |

## Consequences

- **E24 opens**, with its tracker and story issues filed at branch opening
  after the signature (the 2026-08-15 precedent: no issue carries a title with
  no spec behind it). FR-43's row in the FR Coverage Map moves from **gated**
  to this record and those numbers.
- **Not risk-tier by ADR-0036's list.** No new money math, no projection
  semantics, no import idempotency: the measures are read, not computed. Two
  invariants still get a dedicated verification pass in the closing act, each
  mutation-verified: **undetermined never passes** (§3) and **a version in
  force is immutable, and versions of one rule never overlap** (§4).
- **The contract takes one bump** for the new family. The MCP companion gains
  five tools: list, show with history, create, add a version, retire. It also
  gains the findings read. All of them wrap the JSON API (ADR-0002).
- **Agent-visible first is not an option here.** §9 puts the operator's view in
  the same batch, because the operator is the one person the prose never
  reached. If the view slips, the close-out records the two-way deadline, which
  falls in Sprint 16.
- **FR-48 becomes reachable** without a findings store. That is a reason for
  §4's design, not a commitment to build FR-48.
- Gate **B3.6 is closed by this record and by nothing else.** A later decision
  that wants flow rules, rules over events or evaluation over history cites
  this record and argues its own extension.
