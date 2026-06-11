---
layout: docs
title: "ADR-0012: Asset class inference at read time"
description: Heuristic asset class classification runs at read time on name/ISIN/ticker so improvements apply retroactively without migrations.
---

# ADR-0012: Asset class inference at read time

- **Status:** Accepted
- **Date:** 2026-06-11

## Context

Portfolio Performance exports do not always carry an asset class. Even when
they do, the local security record may have been created before classification
was introduced. A migration-based approach (set a default, fill nulls once)
creates a snapshot that drifts as heuristics improve: any rule fix would need
another migration and another pass over all rows.

The database column stores an explicit override (the user's authoritative
choice); the inference only fires when that override is nil.

## Decision

`Security.effective_asset_class/1` infers the class at read time by inspecting
the stored name, ISIN, and ticker. The priority pipeline is:

```
government_bond → etf → crypto → commodity → derivative →
  equity_or_nil → fund_or_nil → nil
```

`equity_or_nil` returns `"equity"` only when `equity_name?` is true **and**
`structured_product_name?` is false — preventing Turbo/Knockout names with
legal-form suffixes from over-classifying as equity. `fund_or_nil` fires as
the last fallback when a known fund-issuer prefix (iShares, Vanguard, Lyxor,
Amundi, Xtrackers, SPDR, Invesco, WisdomTree, VanEck, Fidelity, Deka) is
present but no stronger signal matched.

Because the function runs on the in-memory struct, every improvement to a
heuristic takes effect immediately for all securities on the next read, with no
schema change.

The user can pin a class by setting it explicitly via the quick-assign dropdown
or the security detail form. A stored non-nil value short-circuits the
inference entirely.

## Consequences

- Heuristic improvements are zero-migration and apply retroactively.
- The stored field remains the authoritative override; a user correction is
  never silently overwritten.
- The `is_nil` filter operator on the asset-class column surfaces securities
  for which neither a stored class nor any heuristic fires, giving a focused
  "unclassified" work list.
- Letter-spaced PP export names (e.g. `I b e r d r o l a S . A . A c c i o n e s`)
  are collapsed by the JSON parser before the security is stored, so
  legal-form suffixes are reliably detected.
- Read-time inference adds a small computation per row; for the expected
  catalogue sizes (hundreds to low thousands of securities) this is negligible.
