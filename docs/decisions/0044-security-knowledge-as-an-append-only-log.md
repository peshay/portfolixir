---
layout: docs
title: "ADR-0044: security knowledge as an append-only log, with the thesis state as its projection"
description: What an agent knows about a security is recorded as entries that are never overwritten and never deleted, and the current thesis state is derived from them rather than maintained beside them - the pattern the ledger already uses, applied to knowledge. A retracted finding stays visible and carries its reason, because a log that drops disproved findings reproduces the error it exists to prevent. Machine-extracted entries are proposals carrying their source until confirmed. Closes gate B4.1 together with the agent's P0-6; full-text search and automatic population stay out.
---

# ADR-0044: security knowledge as an append-only log, with the thesis state as its projection

- **Status:** Proposed — owner sign-off pending (decision gate per
  [ADR-0026](0026-epic-batch-workflow.html) step 1)
- **Date:** 2026-08-27
- **Closes gate:** B4.1 (theses and conviction as structured fields), together
  with the agent's P0-6 (an append-only research log). The two were opened
  separately and are decided together here, for the reason in "Why one
  decision".

## Context

A security in this system carries exactly one free-text field. `note` is a
single `:string` column on `securities`, and every write replaces what was
there. The owner's agent presses a thesis, invalidation criteria, quarterly
results, buying blocks, counterparty warnings and withdrawn false alarms into
that one field, and each of those overwrites the last.

The structured alternative it built for itself outside the system has decayed
exactly as the 2026-08-12 triage (`_bmad-output/planning-artifacts/feedback-triage-2026-08-12.md`)
predicted a copy would: keyed on ticker symbols instead of stable identifiers,
built against a classification taxonomy that has been dead since July, last
touched in May, no longer mappable onto the portfolio at all.

The 2026-08-27 round supplies the failure that makes the shape of the fix
obvious rather than a matter of taste. The agent reports the same premise being
raised in successive weekly runs and refuted each time on inspection of the
primary source — with nowhere for "checked on this date, premise refuted,
forecast withdrawn" to live next to the position. On the fourth pass it starts
from nothing again. **The expensive thing is not the missing note. It is the
missing record of having been wrong.**

The identity gate (B3.1, accepted 2026-08-12) already settled the principle:
Portfolixir has two first-class users, one of them an agent, and FR-45/FR-46 sit
in the requirements inventory as decided in principle. What was missing is the
object, its guarantees and its boundaries — which is what a plain tracker has no
business inventing on the fly, and what this gate exists to fix.

## Why one decision

B4.1 asks for the *state*: thesis text and status, conviction tier,
invalidation condition, time stop, last reviewed and by whom. P0-6 asks for the
*evidence*: dated entries with source and quality, superseding each other, some
of them retractions.

Building the state alone reproduces the orphaned file: a status field that
cannot say why it flipped is a value nobody trusts six weeks later, and the
agent's own dead artifact is the demonstration. Building the log alone leaves
every consumer to reduce a list of entries to "is this thesis intact?" on its
own, differently each time.

They are one object family and they are decided once.

## Decision

### 1. The log is the truth; the state is a projection of it

`security_notes` rows are **append-only**: never updated, never deleted. The
current thesis state is **derived** from them.

This is not a new architectural idea in this codebase — it is the one the system
already runs on. Holdings, balances and performance are projections of an
append-only ledger ([ADR-0011](0011-unified-ledger-projection.html),
FR-1 in `_bmad-output/planning-artifacts/epics.md`); corporate actions are
ledger events rather than mutated history
([ADR-0028](0028-corporate-actions-as-ledger-events.html)); quote-history
continuity is append-only adjustment factors. Knowledge gets the same treatment,
for the same reason: the audit value is in what was believed *at the time*, and
a mutable field destroys precisely that.

Where the projection is materialized rather than computed per read, it follows
[ADR-0039](0039-durable-derived-values.html) — a lifetime per analytic,
rebuildable from the log alone, never authoritative for a write.

### 2. The entry

Per entry: `security_id`, `created_at`, `author`, `kind`, `body`, `source_url`,
`source_quality`, `as_of`, `supersedes`, `valid_until`.

- `kind` ∈ `thesis` · `evidence` · `invalidation_check` · `event_result` ·
  `risk` · `retraction` · `decision`. A fixed set, mapped from input with
  `String.to_existing_atom/1` — never `String.to_atom/1`.
- `source_quality` ∈ `primary` · `secondary_multi` · `awareness` ·
  `unverified`. **It is set, not guessed.** Where a future collector derives it,
  the derivation is traceable and overridable, and a manual correction is never
  overwritten by a later run. That invariant was reported twice by the agent
  against its own tooling; it binds here so we do not rebuild the same defect.
- `as_of` is the statement's cut-off date, distinct from `created_at`. An entry
  written today about last quarter is not fresh information, and only this
  separation makes the review-hygiene queries mean anything.
- `supersedes` references an earlier entry. The superseded entry **stays
  visible**.
- `valid_until` carries dated blocks (a lockup, a self-imposed buying block)
  and is what the expiry query reads.

### 3. Retraction is a kind, not a deletion

A refuted finding is withdrawn by **adding** a `retraction` entry that
supersedes it and carries the reason. Both remain readable, and the retraction
is what the next run sees first.

This is the load-bearing clause. A log from which disproved findings disappear
recreates the exact failure it was built to prevent — the fourth investigation
of a premise that was settled three times. Anything that lets an entry vanish
(a delete endpoint, a cleanup task, a "tidy up superseded entries" convenience)
is a change to this ADR, not an implementation detail.

### 4. Authorship, and machine-extracted entries

`author` distinguishes the operator, the agent, and any local model. An entry
produced by extraction rather than judgment carries `machine_generated` and its
source link, and is a **proposal until confirmed** — the standing rule (NFR-10)
that the Portfolio Performance import already implements as preview-then-apply.
Nothing here opens the local-model question; [ADR-0021](0021-pdf-transaction-intake.html)
remains the only sanctioned path.

### 5. Writes are journaled

The log is written primarily by an agent, which is exactly the case the audit
journal exists for. `security_notes` is armed in the journal
([ADR-0017](0017-append-only-audit-journal.html)) in the same migration that creates it.

**This is the dependency that makes the gate honest rather than optimistic.**
The journal rollout is incomplete — Catalog, FX, targets and tax are armed;
Portfolios/Classifications, Ledger and Imports are not — and it has been
recorded as an unscheduled prerequisite for agent writes since 2026-08-12
without being scheduled. This ADR does not require the whole rollout to
finish. It requires that this table is armed at creation, so the new surface
does not add to the debt.

### 6. Both audiences, in the same batch

Under the two-way coverage rule the log needs its human view. It is a
**research timeline on the security detail pane**: entries newest first, kind
and source quality visible, superseded entries shown as superseded rather than
hidden, retractions legible as such.

It lands in the same batch, not the next one. Two entries in the human-view-debt
ledger are enough to know how "the same or the next batch" is actually
experienced.

### 7. The queries are the acceptance criteria

Four reads, over API and MCP, with the same parameters on both:

1. all entries for a security, newest first — the starting point of any research
   run;
2. positions with no entry for N days — review hygiene;
3. entries whose `source_quality` is not `primary` — what still needs
   corroboration;
4. `valid_until` falling inside the next N days — expiring blocks.

### 8. The surface says what it is, so a consumer can notice it changed

The API and MCP expose a **contract-version read**: what the surface offers and
when it last changed, pollable the way `?since=` is pollable for rows.

This rides here rather than standing alone because it is the same lesson as the
rest of this ADR. Three capabilities shipped in Sprint 6 were invisible to the
agent they were built for, and the second edition of its requirements document
asked for two of them again. A tool description is read once at connect time; a
system whose first user is an agent needs its release notes to be readable the
way its data is.

## Scope

**In:** the entry, the derived state, the four queries, the timeline view, the
journal arming, the contract-version read.

**Out of v1, deliberately:**

- **Full-text search across all entries.** A different capability with different
  costs; deferred rather than allowed to ride in unpriced. Named here so the
  deferral is visible.
- **Automatic population** from filings, feeds or IR pages. That is gate B3.3,
  untouched.
- **Predictions and the calibration report.** Gate B4.2, adjacent and
  deliberately separate.
- **Anything that reads a note to make a decision.** Entries inform the
  operator and the agent. No booking, import decision or consistency finding
  reads one.

## Consequences

The agent's starting point becomes one call instead of a re-read of old
conversations, and a refuted premise dies the first time rather than the fourth.
`securities.note` stops being a dumping ground; the migration path is that new
knowledge goes to the log and the existing note stays as it is, since three of
the notes in the live instance are known to be stale and rewriting them
automatically would fabricate `as_of` dates nobody can vouch for.

The cost is a table that grows monotonically, by design, and a projection that
must stay rebuildable from it. Both are the same trade the ledger already makes.

## Alternatives rejected

**Widen `note` into a text field, or a list of strings.** It fails on the
queries — "unreviewed for 90 days", "not corroborated", "expiring" are not
questions you can ask free text — and it fails on retraction, because there is
nothing to supersede.

**Use the audit journal as the log.** The journal records *that a write
happened*, by whom and with what payload. It is a different question from *what
is believed and on what evidence*, and overloading it would make both harder to
read. They stay separate and the log is journaled, per §5.

**Store the state only, and treat the evidence as prose inside it.** This is the
design that already failed outside the system. The state is the part that goes
stale; the evidence is the part that lets you tell.

## Asks this gate was opened on

Source: the agent requirements document of 2026-08-27 (P0-6, P1-1 and its
appendix B), triaged in
`_bmad-output/planning-artifacts/feedback-triage-2026-08-27.md`,
and gate B4.1 as recorded in the 2026-08-12 triage.

| Ask | Verdict |
|---|---|
| An append-only log per security, with the listed fields | **Answered** — §2 |
| `retraction` as a first-class, non-vanishing kind | **Answered** — §3 |
| Thesis, status, conviction tier, invalidation, time stop, last reviewed (B4.1) | **Answered** — §1, as the projection; the conviction tier is a field of the `thesis` kind |
| History, so a flip is visible after the fact | **Answered** — §1; it is the log itself |
| The four list queries | **Answered** — §7 |
| Full-text search over all entries | **Deferred** — a search capability with its own cost; v1 ships the four structured reads. Filed at implementation time, not carried in someone's head |
| "Does the log survive a PP re-import?" | **Answered** — it does, by the guarantee #664 pinned; documented by #741 so the answer stops being invisible |
| "May a local model write structured fields?" | **Answered** — §4, propose only; no local-model gate is opened |
| Automatic population of entries from sources | **Deferred** — gate B3.3, unchanged and untouched here |
| Predictions with a calibration report (P1-2 / B4.2) | **Deferred** — adjacent gate, specified separately; this ADR neither blocks nor presumes it |
| Multi-tenancy for household members | **Deferred** — answered outside this gate: buckets and views are the mechanism, true multi-user is parked (#340) |

## Notes for the signature

Three things are worth a deliberate yes rather than a skim, because each is a
place where a later objection would be expensive:

1. **§3** — that entries are never removed, including by a future convenience.
2. **§5** — that this table is journaled from its first migration.
3. **§6** — that the human timeline is in the same batch, not promised for the
   next one.
