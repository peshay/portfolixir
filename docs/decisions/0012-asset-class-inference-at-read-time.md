---
layout: docs
title: "ADR-0012: Asset class inference at read time"
description: Heuristic asset class classification runs at read time on name/ISIN/ticker so improvements apply retroactively without migrations.
---

# ADR-0012: Asset class inference at read time

- **Status:** Accepted; its summary of the pipeline is corrected to the code
  by the note of 2026-10-03 below (#929), and the note of 2026-10-08 adds
  the bond step (#1127), the decision unchanged
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

> **Note 2026-10-03 (#929, the summary reconciled with the code):** the
> decision stands — a stored class wins, and only a security without one is
> classified by heuristics when it is read — but the summary above, and two
> of the consequences below, say more than `Security.effective_asset_class/1`
> does. The code is what runs, and this note changes none of it:
>
> - **The ISIN is not a heuristic signal.** `infer_asset_class_code/3`
>   ignores it (`_isin`) and reads the name and, for crypto, the ticker,
>   because the structure of an ISIN alone is not a reliable asset-class
>   signal (#408). The ISIN is read only by the logo fallback below.
> - **There is no `derivative` class.** That step is `derivative_class/1`,
>   which returns a leaf class: `knock_out`, `discount_certificate`,
>   `warrant`, `factor_certificate`, `reverse_convertible`,
>   `bonus_certificate` or `express_certificate`, a bare Call or Put being a
>   `warrant`.
> - **A logo fallback follows `fund_or_nil`** (#408, `inferred_from_logo/1`):
>   a security the name rules leave unresolved that has an ISIN and a stored
>   company logo (`logo_path`) is `equity`. The pipeline as the code runs it:
>
>   ```
>   stored class → government_bond → etf → crypto → commodity →
>     derivative leaf class → equity_or_nil → fund_or_nil →
>     logo fallback (equity) → nil
>   ```
>
>   `fund_or_nil` also knows the issuer prefix AIS-AM beside Amundi.
> - **Not every improvement reaches every security.** `changeset/2` stores
>   the class the name rules give whenever a write leaves the class empty,
>   and the security form saves the class it shows, so a security created or
>   saved through the catalog usually carries a stored class that then
>   short-circuits the inference like the user's own choice. "Zero-migration
>   and retroactive" holds only for the securities that store no class: those
>   no name rule matched at their last write, and those reset to automatic on
>   the asset-class tree, which clears the stored class without inferring
>   one. Whether an inferred class should be stored at write time at all is
>   a question for triage that this note does not decide.
> - **The `is_nil` filter is keyed on the stored class** (#700): it lists
>   every security with no stored class, including those whose class is
>   inferred (shown as derived), not only those no heuristic resolves.

> **Note 2026-10-08 (#1127, the Sprint 20 plan's D-4):** the pipeline gains
> a **bond** step between the derivative leaf class and `equity_or_nil`, so
> a bond named with its issuer's legal form is no longer read as a share. A
> name is `bond` when it carries Anleihe, Schuldverschreibung or Pfandbrief,
> also as the last part of a compound (Unternehmensanleihe,
> Inhaberschuldverschreibung, Hypothekenpfandbrief), or the word Notes,
> Obligation or Obligationen, and no structured-product word (a certificate
> is legally a Schuldverschreibung too). Not "Bond", which company names
> use, and not a bare coupon-and-year pattern ("4,10% 2028/2033"), which
> shares and funds carry too. The steps before it still decide first:
> "Aktienanleihe" stays `reverse_convertible`, "Bundesanleihe"
> `government_bond`, an ETF token `etf`. It reaches new securities only, as
> Sprint 19's D-5 keeps the stored class: a class stored before — such a
> bond was stored as `equity` — is not rewritten, and the step reaches a
> stored row only by the paths the note of 2026-10-03 names. The decision
> is unchanged. The pipeline as the code runs it:
>
> ```
> stored class → government_bond → etf → crypto → commodity →
>   derivative leaf class → bond → equity_or_nil → fund_or_nil →
>   logo fallback (equity) → nil
> ```

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
