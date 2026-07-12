---
layout: docs
title: "ADR-0024: Buckets and views replace portfolios as the user-facing grouping"
description: Demote the portfolio entity to an internal compatibility record, make buckets and views the only user-facing grouping, and gate the change on additivity of view totals.
---

# ADR-0024: Buckets and views replace portfolios as the user-facing grouping

- **Status:** Accepted
- **Date:** 2026-07-12

## Context

The sidebar exposes five grouping-adjacent concepts: depots, cash accounts,
portfolios, buckets, and views. Depots and cash accounts are bookkeeping
entities — transactions attach to them and the Portfolio Performance
round-trip needs them. Above them sit three answers to the same question
("how do I group my holdings?"): portfolios (exclusive containers),
buckets (overlapping tags on depots/cash accounts, ADR-0018), and views
(named filters over buckets, carrying SOLL plans per ADR-0020).

The owner's product review (2026-07-12) named the problem: buckets and views
are "what one actually needs"; the portfolio layer is inherited shape. A
four-voice design session plus a full elicitation pass (planning artifacts
2026-07-12) established the evidence:

- The PP import/export round-trip references depots and cash accounts per
  transaction; it does not carry a portfolio concept. The importer has to
  *invent* the "PP Import" portfolio (#558) because the source has none.
- The one property portfolios uniquely provide is **exclusivity**: a disjoint
  partition of depots, so scoped sums always add up to the total. Buckets
  are overlapping by design — a depot in two buckets double-counts in naive
  view sums.
- ADR-0020 already binds SOLL plans to views, while ADR-0022's Wealth page
  and dashboard cards scope to portfolios — two answers to "what do I
  aggregate over" in one product.
- An issue cluster (#327, #328, #558) exists purely as maintenance cost of
  the container concept, and #491's master-data redesign is blocked on this
  decision.

## Decision

**Demote now, merge later.** The portfolio entity remains in the schema, the
JSON API, and the import path as a compatibility record; it disappears from
the UI as a user-facing grouping. Buckets and views become the only grouping.

Binding modifications (from the elicitation pass — these are part of the
decision, not implementation detail):

1. **API story is decided now, not deferred.** Portfolio write endpoints are
   deprecated (documented, deprecation signal in the response); every
   portfolio that exists is visible in a minimal administration list. An
   LLM-first product must not carry an invisible writable resource — MCP
   agents would otherwise accumulate ghost portfolios no human ever sees.
2. **Exclusivity is preserved, not dropped.** The migration seeds one
   designated *exclusive* bucket dimension (each depot/cash account in
   exactly one bucket of that dimension); additional buckets are free
   overlapping tags. View totals ALWAYS deduplicate at the account level
   (union of accounts, never sum of buckets); views whose buckets overlap
   show a visible badge.
3. **The validation spike must include an overlap fixture** — a shared depot
   in two buckets with a Decimal-exact assertion that the "everything" total
   equals the deduplicated union. A 1:1 migration fixture alone proves only
   the tautological case.
4. **Retroactive series semantics, reproducibility preserved.** Current
   bucket membership applies retroactively to historical series (like PP
   filters) — no temporal membership model. The UI labels view series
   "composition as of today", and bucket-membership changes are recorded in
   the audit journal so "what did this view contain on date X" stays
   answerable.
5. **Merge exit criterion.** The demoted entity is phase 1 with a defined
   end: after two releases without external portfolio writes, a follow-up
   story merges portfolios into buckets+views and supersedes this section.
   Without the criterion the zombie entity becomes permanent.
6. **One management surface, migration with preview and revert.** Buckets
   get NO sidebar entry — they appear as chips on depot/cash-account rows
   and in the view editor ("Manage…" from the view picker). Replacing one
   managed concept with two would simplify nothing. The one-time migration
   (one bucket + one view per existing portfolio, fully editable, audit-
   journaled) runs with a preview, and the revert path is documented while
   the entity still exists.

User-facing consequences: the Wealth page and dashboard scope to a view with
"Everything" as the built-in default and a **user-settable default view**
(household case: "mine" vs. "whole household" without a hard wall). The PP
import preview replaces the auto-created portfolio with an editable bucket
tag ("these accounts get tagged X — rename or skip").

**Information-architecture rule** (root cause of the five-concept sidebar):
navigation reflects user tasks, not the storage model — *sidebar = tasks,
entities = attributes*. New entities do not get sidebar entries by default.

**Kill criterion:** if account-level deduplication of view totals cannot be
implemented cleanly and cheaply (the overlap spike is the gate), this ADR is
rejected rather than weakened — the additivity of the total wealth number is
the one number an audit tool must never contradict.

## Consequences

- #327 (move depots between portfolios) is superseded: moving becomes a tag
  edit. #328 shrinks to merge/rename/delete of the bookkeeping entities
  themselves. #558 dissolves via the import-preview tagging. #491 is
  unblocked and re-scoped smaller (one creation flow less, one design
  language). #559 (bucket chips on account rows) becomes core grouping UI.
- The user documentation gains a **use-case guide** for buckets and views
  (household split, strategy views, migrating a PP depot-as-category habit),
  since the grouping model is now the product's central mental model.
- API/MCP: no breaking change in phase 1; deprecation notes on portfolio
  writes; view-scoped aggregation endpoints follow ADR-0019/0020.
- Supersedes the "portfolios-as-scope" remnants tolerated by ADR-0018 and
  the portfolio-scoped surface decisions of ADR-0022 where they conflict.
