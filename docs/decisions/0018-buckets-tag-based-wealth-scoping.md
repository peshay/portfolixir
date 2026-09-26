---
layout: docs
title: "ADR-0018: Buckets — tag-based wealth scoping with view filters"
description: Decision to introduce buckets as overlapping tags on holdings (depot default plus per-position override) and named views that scope analytics by including or excluding buckets, generalizing the per-security allocation exclude flag (ADR-0013).
---

# ADR-0018: Buckets — tag-based wealth scoping with view filters

- **Status:** Accepted. **Amended in Sprint 16** (the security review's
  decision T-10 and finding F45, adopted by the merge of the Sprint 16
  planning PR): resolved parameter 5 now journals view definitions, and a
  bucket delete journals its cascade — see "Amendment" below.
- **Date:** 2026-06-18

## Context

Three distinct needs around "what counts toward wealth" collide in the current
model:

1. **Total wealth** — everything held must count somewhere, exactly once.
2. **Scoped views** — only a *subset* should feed a given analysis. The
   motivating case: a highly volatile asset stays in total net worth but is
   left out of the investment *strategy* and rebalancing because its
   volatility would distort the steered mix.
3. **Separating parts by purpose or person** — e.g. holdings that belong to a
   second person but sit in the operator's depot should be viewable
   separately, while holdings that are not the operator's wealth at all
   should be able to leave the instance entirely.

Today three mechanisms each address part of this and conflict:

- **Portfolios** ([ADR-0001](0001-modular-phoenix-monolith.html)) partition the
  wealth space but give no unified total *across* portfolios, and conflate
  "container" with "strategy scope".
- The per-security **`excluded_from_allocation_targets`** flag
  ([ADR-0013](0013-exclude-securities-from-allocation-targets.html)) is
  allocation-only and global per security — it cannot vary by view or purpose.
- **Classifications** ([ADR-0006](0006-classifications-with-target-weights.html))
  organize securities into trees but do **not** filter: an unassigned security
  still counts in every analysis.
- **Purpose / ownership is not modeled at all.**

The maintainer wants a single general primitive rather than an owner-specific
concept: *put parts of your wealth into named buckets, then look at your wealth
through a chosen set of buckets.*

## Decision

Introduce two concepts: **Buckets** and **Views**.

### Buckets

- A **Bucket** is a user-defined named label (e.g. `Core`, `Krypto`, `Family`).
- **Overlapping tags, not a partition.** A holding may carry zero or more
  buckets (many-to-many). The totals rule below follows directly from this.
- **Assignment is depot-default plus position-override.** A securities account
  (depot) and a cash account carry a **default bucket set** applied to
  everything they hold. An individual **position** (a security held in a
  specific depot) may carry its **own explicit bucket set that replaces the
  depot default for that position**. With no explicit set, a position inherits
  its depot's default. "Explicit-empty" (deliberately no bucket) must be
  representable and distinct from "inherit".

### Views (Sichten)

- A **View** is a named, saved scope defined as a **filter over buckets** — an
  include set and/or an exclude set (e.g. `Strategie = exclude {Krypto, Family}`).
- A view selects the **subset of holdings** whose bucket tags satisfy the
  filter. Valuation, allocation, performance, risk, and the future (gated)
  rebalancing run against the view's holding set.
- The implicit default view is **"everything" = total wealth**.

### Wealth math under overlapping tags

- **Every total — overall or per-view — is computed over the holding universe,
  counting each holding exactly once** (a membership boolean: is this holding in
  the view?). A total is **never** the sum of per-bucket valuations.
- **Per-bucket breakdowns may overlap** (a holding tagged both `Krypto` and
  `Spekulativ` appears under both) and must be presented as overlapping facets,
  **never summed as if they partitioned wealth**. A meta-test/contract guards
  that the documented total equals the single-count universe under the active
  view.

### Relationship to existing decisions

- ADR-0013's `excluded_from_allocation_targets` becomes a **special case** of
  "not in the `Strategie` view". The flag is **not auto-migrated**: at cutover it
  is removed and the operator re-creates the equivalent setup by hand (assign the
  affected securities to a bucket and exclude that bucket from the `Strategie`
  view). ADR-0013 stays in force until then and will be marked *Superseded by
  ADR-0018* once the flag is removed.
- Buckets are the **primary soft-scoping** mechanism within the existing
  portfolio model. Multiple portfolios remain available for hard separation, but
  buckets + views deliver "household total with sub-views" without splitting the
  total. Views select holdings **across** portfolios so a unified household
  total stays possible.
- Bucket and view writes are actor-first and journaled per
  [ADR-0017](0017-append-only-audit-journal.html) (subject to that rollout) so a
  changed scope is attributable.
- API/MCP parity ([ADR-0002](0002-thin-mcp-over-json-api.html)): bucket/view
  CRUD and a `view` scope parameter on analytics endpoints each get an API
  endpoint **and** an MCP tool; financial decimals serialize as strings.

### Explicitly out of scope of this ADR

- **Removing holdings** (the "remove a non-owner entirely" case) is **not** a bucket
  operation. Buckets scope and hide; removing wealth that is not yours is depot
  / holding deletion with transaction handling (FR-4 / #328), tracked
  separately. Conflating the two is rejected.
- **Rebalancing** stays gated (FR-12) behind its own scope ADR; buckets merely
  give it a natural scope input (a view).

## Consequences

- One concept (buckets + views) covers person/purpose separation, strategy
  scoping, and volatility carve-outs that today need three conflicting
  mechanisms.
- Tags give real flexibility (a holding can be `Krypto` *and* `Spekulativ`), and
  views are reusable and named.
- **Trade-off (accepted): there is no "sum of buckets".** Because buckets
  overlap, totals must be computed over the single-count holding universe;
  per-bucket breakdowns can exceed the total, and the UI/API must label them as
  overlapping facets. A double-count guard (meta-test) is required.
- **Trade-off:** depot-default + position-override needs a clear inheritance
  model (inherit vs. explicit-empty vs. override) that must be tested; it is more
  schema than a single global boolean.
- Larger surface: new tables (buckets, depot/account default-bucket links,
  position-level overrides, views), engine changes to accept a view scope,
  API/MCP coverage, and UI assignment affordances + a view switcher. Migrations
  are additive.
- ADR-0013 becomes a special case and will be superseded on migration; both run
  during the interim.
- Net worth stays honest: everything counts once toward the total, regardless of
  bucketing.

## Resolved parameters

These were decided with the maintainer and are part of this Accepted decision:

1. **View filter grammar & precedence.** A view is
   `{include: [buckets] | :all, exclude: [buckets]}`; when both are present,
   **exclude wins**.
2. **View scope.** Views are **global** (across all portfolios) so a unified
   household total is possible; per-portfolio scoping remains an orthogonal
   filter.
3. **Cash buckets.** Cash accounts are bucketable from **v1** — a cash account
   carries a default bucket so a person's cash follows their holdings.
4. **ADR-0013 migration.** **Manual re-setup**, not auto-migration. Existing
   `excluded_from_allocation_targets` flags are removed at cutover; the operator
   re-creates the equivalent buckets/views by hand.
5. **Journaling granularity.** **Bucket *assignment* changes are journaled**
   (they change reported attribution); pure view-*definition* edits (create /
   rename / delete a view) are operational config and are **not** journaled
   (cf. idempotency keys, AR-5). *Amended in Sprint 16 — see below: a view's
   definition is journaled, because a policy rule in force reads it.*

## Amendment: view definitions and bucket deletes are journaled (Sprint 16, T-10, F45)

The security review of Sprint 16 (E25, findings F45, G19 and G29, decisions
of its triage adopted with the Sprint 16 planning PR) found that parameter 5
no longer held once policy rules existed. A rule in force
([ADR-0049](0049-policy-rules-as-first-class-objects.html)) is evaluated
under a view, or over a view as its subject, so a view's definition is part
of what a finding means; a definition that changed with no entry left a
shifted finding with no audit trace. Two paths changed it silently: the view
writers, and the database cascade of a bucket delete, which also turned a
position override that lost its last bucket into inheritance.

- **A view's definition is journaled.** Editing a view (name,
  `include_all`), replacing its bucket sets and deleting it each leave one
  entry of `resource_type` `view`, filed under the view, whose before- and
  after-image is the whole definition — the row and both bucket sets —
  read under the view row's lock in the writing transaction. Resending the
  stored definition leaves none. Creating a view stays unjournaled: no rule
  can read a view before it exists, and its first edit's before-image is the
  view as created.
- **A bucket delete journals its cascade (T-10).** Before the row goes,
  every view and assignment that names the bucket is rewritten through its
  journaled writer, so each affected owner gets its own entry, and the
  bucket's own entry carries every membership it had as its before-image.
  **An override that loses its last bucket stays explicit-empty**: the
  position keeps "no buckets" and does not start inheriting its depot's set.
  The delete confirm and the tool description say so. No new refusal is
  added: a bucket stays deletable, and its delete stays visible. The foreign
  keys still cascade, as a backstop that finds nothing left to remove.
- **The tables stay unarmed scope tables.** The journaling rests on the
  `Portfolixir.Buckets` writers, as the assignment writers' already did.
