---
layout: docs
title: "ADR-0006: Classifications (taxonomies) with built-in derived trees"
description: Decision to add hierarchical classification trees, including auto-managed built-in classifications derived from security data, with target weights deferred to a later decision.
---

# ADR-0006: Classifications (taxonomies) with built-in derived trees

- **Status:** Accepted
- **Date:** 2026-06-06

## Context

Portfolixir describes a security's nature only with a single flat `asset_class`
enum (`Portfolixir.Catalog.AssetClasses`). That labels a row but cannot express
how a maintainer organises a portfolio. Portfolio Performance solves this with
**Klassifizierungen** (taxonomies): user-defined hierarchies into which
securities are sorted like folders, with colours and multiple parallel views.

The near-term goal is to bring this organising structure to Portfolixir — and to
expose it (and later, via MCP, to an LLM) — so strategies and groupings are
first-class. Two needs shape the design:

- Some groupings Portfolixir can already derive itself (asset class from
  `asset_class`, currency from `currency_code`). Those should be **built-in** and
  set automatically, yet appear alongside user trees like any other
  classification. If a maintainer disagrees with a derived grouping, they build
  their own classification in parallel rather than fighting the built-in one.
- The structure (trees, categories, colours, assignments) is the feature now;
  **target/actual weights are explicitly deferred** to a later ADR so this stays
  a tractable first step.

Constraints that apply:

- Auditable, derived state stays reproducible, not stored as mutable running
  totals ([ADR-0004](0004-holdings-derived-from-transactions.html)). Built-in
  assignments are derived from security data and kept in sync.
- The MCP companion stays a thin wrapper over `/api/v1`
  ([ADR-0002](0002-thin-mcp-over-json-api.html)).
- The supported `asset_class` and currency code lists are curated, not user
  free-text.
- Scope stays small: this records and reports structure; it does not place
  orders or rebalance.

## Decision

Introduce a bounded context `Portfolixir.Classifications` that models editable
taxonomy trees plus auto-managed built-in trees.

**Stored, editable definitions:**

- **Classification** — a named tree (e.g. "My Strategy"). Has a `name`, a
  `position`, an optional `description`, a nullable `key`, and a `built_in`
  flag. A `key` (`"asset_class"`, `"currency"`) identifies a built-in tree.
- **Category** — a node within one classification, forming a tree via a nullable
  `parent_id`. Carries a `name`, an optional `color`, a `position`, and a
  nullable `key` (the derived code, e.g. an asset-class or currency code, used to
  keep built-in trees in sync).
- **Assignment** — places one security in one category of a classification.
  Uniqueness is `(security_id, classification_id)`: a security sits in at most
  one category per classification (splitting a security across categories is a
  weights concern, deferred).

**Built-in classifications (auto-managed, structure locked):**

- Portfolixir seeds and maintains built-in trees for **asset class** (from
  `Security.effective_asset_class/1`) and **currency** (from `currency_code`).
  Their categories mirror the curated code lists; their assignments are derived
  from each security and re-synced whenever a security is created or changed.
- They are fully visible like any classification, but their structure and
  assignments are not hand-editable through the API/UI — a maintainer who wants
  a different cut creates a custom classification instead.

**Surfaces:**

- A JSON API under `/api/v1/classifications` (list trees with categories and
  assignments; create/update custom classifications, categories, and
  assignments), mirrored by MCP tools.
- A simple LiveView page that lists classifications as coloured trees and lets a
  maintainer build custom trees and drag securities into categories.

## Consequences

- Maintainers get Portfolio-Performance-style hierarchies with colours and
  drag-and-drop, plus built-in asset-class and currency trees that are always
  present and current without manual upkeep.
- Built-in assignments stay reproducible from security data, consistent with
  [ADR-0004](0004-holdings-derived-from-transactions.html); only custom trees are
  free-form configuration.
- New schema arrives: `classifications`, `classification_categories`, and
  `security_category_assignments`. The flat `asset_class` field stays as the
  source for the built-in asset-class tree and is not removed.
- **Target and actual weights (SOLL/IST) are out of scope here** and will be
  added in a follow-up ADR on top of this structure, so categories carry no
  weight yet.
- Region/industry built-ins (e.g. from the ISIN country prefix) are deliberately
  left for a later batch; only asset class and currency ship as built-ins first.
- More surface to keep consistent across context, API, MCP, LiveView, tests,
  translations, and docs; the work is split into small TDD stories.
