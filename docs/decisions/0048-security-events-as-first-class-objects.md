---
layout: docs
title: "ADR-0048: security events as first-class objects — calendar facts about the whole catalog, entered by hand or by an agent, fetched by nobody"
description: Decision for gate B3.4 (FR-44). An event is a dated calendar fact about a security that books nothing - distinct from ADR-0028 corporate actions, which change a position - and it is tracked for every security in the catalog, not only the held ones, because a purchase candidate with zero holdings is exactly the security whose dates matter. Events are mutable and journaled rather than append-only like the research log, a date is qualified by how well it is known, four reads are the acceptance criteria, and nothing fetches a calendar — entry is manual or agent, and automatic population stays gated at B3.3.
---

# ADR-0048: security events as first-class objects

- **Status:** Accepted (decision gate **B3.4** per
  [ADR-0026](0026-epic-batch-workflow.html)) — owner sign-off is the merge of
  the Sprint 13 planning PR (step 1 as amended on PR #780: the merge is the
  signature).
- **Date:** 2026-09-19
- **Answers:** FR-44. The asks it answers and defers are in §9, per
  [ADR-0043](0043-a-gate-closing-adr-names-its-asks.html).
- **Opens nothing else.** B3.3 (acquisition beyond quotes and FX), B3.6
  (policy rules) and B3.7 (push delivery) are untouched, and §8 says in what
  way.

## Context

The owner's portfolio agent submitted the **third edition** of its
requirements document on 2026-09-19 (triage:
`feedback-triage-2026-09-19.md`). Most of the list is answered, gated or
already in flight; one item is neither, and the agent ranks it above
everything else it asks for.

Earnings, dividend and lockup dates live in local JSON files that the agent
builds **out of the holdings**. A security it does not yet own therefore has
nowhere to keep a date, and the agent reports that a purchase candidate's
reporting date came close to being missed for exactly that reason.

That is worth reading twice, because it contains the actual requirement. The
agent did not merely lack a table; it derived the calendar from the position
list, and a calendar derived from the position list cannot hold a date for
something not yet owned. The failure is structural, and it points at the one
case where a date matters most — the decision to buy. (The instrument is not
named here: the triage's privacy note applies, and the *shape* of the
near-miss is the whole content.) The agent's own
ranking is that this is the only gap that hides **risk** rather than costing
**tokens**, and the distinction is correct: everything else on its list is a
number it can recompute, this is a date it can miss.

FR-44 has said the same since the requirements inventory, in almost the same
words, including both structural boundaries. What was missing is the gate.

There is a second reason to take it now. The 2026-08-15 triage recorded a
finding this record is a test of: *generalising a request before satisfying it
manufactures its own difficulties.* A "security events" table invites a
calendar sync, an alerting engine and a rules layer. None of those is asked
for, and each has its own gate. This record builds the table and the four
reads, and says no to the rest in §8.

## Decision

### 1. An event is a calendar fact, and it books nothing

A **security event** is a dated statement that something will happen, or has
happened, to a security: an earnings report, an ex-dividend or payment date, a
lockup expiry, an index review, a shareholder meeting, a regulatory decision,
a guidance update.

It is **not** a corporate action. [ADR-0028](0028-corporate-actions-as-ledger-events.html)
made corporate actions **ledger events** because a split *changes a position*;
an earnings date changes nothing until a price moves, and a price move is
already a quote. FR-44 calls sharing one table "a shortcut that costs later"
and this record agrees: `security_events` is its own table, and
`Ledger.Projection.effects/1` never sees one.

When a calendar fact becomes a booking — the dividend is actually paid — **the
event is not converted into a transaction and the transaction does not consume
the event.** The booking is recorded through the ledger as it always was, and
the event is marked `confirmed`. Correlating the two automatically is a
reconciliation feature nobody asked for; it is named in §9 as deferred, with
its reason.

### 2. The catalog, not the holdings — the boundary that is the whole point

`security_events` keys on `security_id` and **nothing else**. No portfolio, no
depot, no view. The reads of §5 cover **every security in the catalog by
default**, and `held_only=true` is an opt-in filter, never the default.

This is stated as a decision rather than left to a query, because the default
is the requirement: the agent's local calendar defaulted to the holdings and
that is precisely how a date for an unheld candidate became invisible. A
default that has to be remembered is the defect rebuilt inside the product.

### 3. A date is qualified by how well it is known

"Earnings expected late February" is not a date, and storing it as one makes
a guess indistinguishable from a filing. Every event therefore carries a
**timing qualifier** beside its date:

| `timing` | Meaning |
|---|---|
| `exact` | the date is confirmed by a source that sets it |
| `estimated` | a date is expected, from an estimate rather than an announcement |
| `window` | it falls between `date` and `date_end`, inclusive |
| `month` | the month of `date` is known, the day is not |

A read that answers "what is due in the next N days" treats a `window` or
`month` event as due when **any** day it could fall on is inside the horizon —
the conservative direction, because the failure this record exists to prevent
is a missed date, not an early warning.

### 4. Mutable and journaled — deliberately not append-only

[ADR-0044](0044-security-knowledge-as-an-append-only-log.html) made the
research log append-only, and the obvious move would be to copy it. This
record does not, and the difference is not convenience:

- **A research entry is an argument.** Its history *is* its meaning — what was
  believed, when, on what evidence, and a retraction that erases the mistake
  erases the reason the thesis changed.
- **An event is a fact about the world.** A rescheduled earnings call does not
  make the old date a second fact; it makes it wrong. Two rows for one
  reporting date is a calendar an operator cannot read, and "which of these
  three is current?" is exactly the question the object exists to answer.

So an event is **one mutable row per fact**, and its change history lives where
change histories already live: the **append-only audit journal**
([ADR-0017](0017-append-only-audit-journal.html), FR-28). The table is
**journaled from its first migration** — the ADR-0044 precedent, and
non-negotiable here because an agent writes these rows. Nothing is lost;
nothing is duplicated; NFR-2 holds through the mechanism built for it.

### 5. Four reads are the acceptance criteria

As in ADR-0044 §7, the reads are the specification:

1. **One security's events** — all of them, past and future, newest relevant
   first.
2. **Upcoming across the catalog within N days** — the read the agent is
   missing. Default scope is the whole catalog; `held_only=true` narrows it;
   `kind` filters it.
3. **Unconfirmed events whose date has passed** — the "did it actually
   happen?" queue, which is what keeps the calendar from quietly rotting.
4. **Events whose `checked_at` is older than N days** — staleness of the
   calendar itself, distinct from (3): a confirmed future date nobody has
   re-read in three months is a different risk from a past date nobody
   resolved.

### 6. Fields, and the two vocabularies that are reused rather than reinvented

`security_id`, `kind`, `date`, `date_end`, `timing`, `confirmed`, `source_url`,
`source_quality`, `checked_at`, `note`, plus the timestamps.

- **`kind` is a fixed `Ecto.Enum`.** Never `String.to_atom/1` at the boundary —
  the hard rule, and the enum-label meta-test Sprint 12 added for transaction
  kinds applies here from the first commit: every member has a gettext label
  clause and there is no `to_string` fallback.
- **`source_quality` reuses ADR-0044's vocabulary** exactly —
  `primary | secondary_multi | awareness | unverified`. One scale for "how well
  do we know this" across the two knowledge families; a second scale would
  make the two incomparable for no gain.
- **`machine_generated` is reserved, not used** (NFR-10), the same way
  ADR-0044 reserves it: an event extracted from an unstructured source by a
  local model would be a proposal until confirmed, and no such path exists.
- Financial decimals: none. An event carries no money. Where a future version
  wants an expected dividend amount, it is a new decision — §9.

### 7. It survives a re-import, and that is pinned before anyone asks

A calendar that vanishes at the next Portfolio Performance import is worth
nothing, and the agent's document raises exactly this worry about the research
log — where it is already false and documented (the triage refutes it for the
third time with the evidence).

The same guarantee is **extended to events in the same batch that creates
them**: `test/portfolixir/imports/reimport_preservation_test.exs` gains the
assertions, and the integration documentation's re-import section gains the
sentence. The guarantee is cheap to hold — the applier never deletes a
security — and expensive to discover missing.

### 8. What this record does not open

- **Nothing fetches a calendar.** Entry is manual or through the agent's own
  write. Automatic population is **B3.3** and stays shut; no provider, no
  scrape, no feed.
- **No alerting and no push.** The due-date list of §5.2 is a **pull** read. Any
  outbound delivery is **B3.7** and stays shut.
- **No rules over events.** "Warn me when a lockup is within 14 days" is a
  policy rule, which is **FR-43** at **B3.6**. This record gives that gate a
  better object to work on and does not pre-empt it.
- **No evaluation.** Whether events predicted anything is ladder level (c) and
  needs FR-46 predictions first; replaying a rule over a history that did not
  have it is level (d) and is out.
- **No auto-reconciliation with the ledger** (§1).

### 9. The asks, answered and deferred (ADR-0043)

**Source of the asks:** FR-44 as written in the requirements inventory, and
the 2026-09-19 agent round's P0-4 with its near-missed candidate date.

| Ask | Source | Verdict |
|---|---|---|
| Events as an object with security, type, date, confirmed, source, source quality, checked-at, note | FR-44 | **Answered** — §6 |
| Timing qualifier | FR-44 | **Answered** — §3, four values, and the due-read resolves a range conservatively |
| Tracked for the whole catalog, not only holdings | FR-44, P0-4 (the near-missed candidate) | **Answered** — §2, and it is the default rather than a filter |
| Distinct from corporate actions | FR-44 | **Answered** — §1, its own table, never a ledger effect |
| Manual and agent entry only | FR-44 | **Answered** — §8; B3.3 stays shut |
| A due-date read an agent can poll instead of rebuilding state | P0-4 | **Answered** — §5.2 |
| Append-only, like the research log | this record | **Answered: no**, with the argument — §4. A fact's history is an audit trail, and the journal is the audit trail. |
| Survives a re-import | the agent's appendix-B question, generalized | **Answered** — §7, pinned in the same batch |
| Expected dividend amount / an event that carries money | this record | **Deferred** — it turns a calendar into a forecast and needs the tax and FX treatment argued; no consumer asked for it |
| Automatic linking of a confirmed event to the transaction that settled it | this record | **Deferred** — reconciliation, and the matching rule (a dividend paid three days late, in another currency) is its own problem |
| Alerts, thresholds, rules over events | P0-3, P1-3 | **Out of scope, gated** — B3.6 and B3.7; §8 |
| A calendar feed or scrape | P1-3 | **Out of scope, gated** — B3.3; §8 |

## Consequences

- **Not risk-tier.** No money math, no projection semantics, no import
  idempotency — an event carries no `Decimal` at all (§6). The journaling and
  the enum boundary are the two places to read carefully, and both follow
  patterns already built.
- **Agent-visible first, by design and with a deadline.** The four reads ship
  on the API and MCP; the per-security list lands on the securities detail
  pane in the same batch, and the catalog-wide upcoming surface is the half
  that may slip — in which case the close-out records the deadline the
  two-way coverage rule gives it, rather than letting it inherit one quietly.
- **The contract-version read reports the new surface** (ADR-0044 §8), which
  is how an agent notices the object exists without being told. Worth naming
  here: the 2026-09-19 triage found the agent reading the contract version
  while missing the integration documentation, so a new surface must be
  announced where it already looks.
- FR-44's row in the FR Coverage Map moves from **gated** to the issue numbers
  the Sprint 13 batch files, and the Tracker Index gains the epic.
- The B3.4 gate is **closed by this record and by nothing else**: a later
  decision that wants acquisition, alerting or rules over these events opens
  its own gate and cites its own ADR.
