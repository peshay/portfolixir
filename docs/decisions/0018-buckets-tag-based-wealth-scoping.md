---
layout: docs
title: "ADR-0018: Buckets — tag-based wealth scoping with view filters"
description: Decision to introduce buckets as overlapping tags on holdings (depot default plus per-position override) and named views that scope analytics by including or excluding buckets, generalizing the per-security allocation exclude flag (ADR-0013).
---

# ADR-0018: Buckets — tag-based wealth scoping with view filters

- **Status:** Accepted
- **Date:** 2026-06-18

## Context

Three distinct needs around "what counts toward wealth" collide in the current
model:

1. **Total wealth** — everything held must count somewhere, exactly once.
2. **Scoped views** — only a *subset* should feed a given analysis. The
   motivating case: Bitcoin stays in total net worth but is left out of the
   investment *strategy* and rebalancing because its volatility would distort
   the steered mix.
3. **Separating parts by purpose or person** — e.g. a child's ("Leo") holdings
   currently mixed into the operator's real depot should be viewable
   separately, while another person's ("Julia") holdings are not the operator's
   wealth at all and should leave the instance entirely.

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

- A **Bucket** is a user-defined named label (e.g. `Core`, `Krypto`, `Leo`).
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
  include set and/or an exclude set (e.g. `Strategie = exclude {Krypto, Leo}`).
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

- **Removing holdings** (the "remove Julia entirely" case) is **not** a bucket
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
   (cf. idempotency keys, AR-5).
