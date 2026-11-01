# I1: explanatory texts and data notes out of the way — inventory and prototype

Idea I1 of the [idea list](../../../ideas.md). The owner asked on
2026-11-01 for every current hint in the UI, and for the screens as they
are today and as they would look after the change.

This is a **discussion prototype, not a board**: the variants are applied
over the running app by `proposal.js`, so the "Heute" frames are the shipped
screens and the variant frames are the same screens with the proposal
injected. The PNGs are not committed (they are regenerated in a minute, and
the repository should not grow by megabytes per discussion; see I10). The
board that a planning PR needs is drawn once a variant is chosen.

## Decision (owner, 2026-11-01)

The recommendation is adopted, as variant **R** in `proposal.js`, tracked by
**#1351**:

- **Explanations:** a section's method sentences move into one ⓘ beside the
  section heading; the short basis clauses (view · period · currency ·
  as-of) stay visible.
- **Data notes:** two lines, three on a phone, "mehr" only where the text is
  cut; problems always visible; two or more attention/note items in one
  block fold into one line with their counts.
- UX-DR11 and UX-DR25 stand. The count of excluded rows stays visible; their
  names are one tap away.

`out/final-*.png` show today beside R. The prototype decides by clause length
which basis clauses stay; the real change classifies each text by the
inventory.

## How to regenerate

On the review seed (`priv/demo/finding_surfaces_seed.exs`, synthetic data
only; its header gives the database and port), with the server on port 4003:

```bash
node render.js          # 1280 px: every page, today and variants A, B, C, R
W=390 node render.js    # the phone frames
node compose.js         # side-by-side comparisons into out/ (MODE=final: today and R only)
```

## Inventory, in numbers

Every explanatory paragraph, basis line, hint, ⓘ and data note the web UI
renders, read from the code (`lib/portfolixir_web/`) on 2026-11-01.

| Mechanism | What it is | Roughly how many |
|---|---|---|
| Data note (note / attention / problem) | a fact about the current data, conditional | ~60 call sites; up to 8 stacked on Wealth's data-quality block |
| ⓘ (`details.metric-tooltip`) | a definition, behind a tap | ~27 call sites (`DESIGN.md` still says eight) |
| Basis line (`.summary-basis` and kin) | where a number comes from: view, period, currency, method | ~35 |
| `.hint` / `.muted` / `small.hint` | **both** explanations and data facts | ~70 |
| Form and dialog help | how a control behaves | ~15 |
| `title=` only | meaning only on mouse hover | 6 that carry meaning |

Per page, the always-shown explanations (excluding the page subtitle):

| Page | Always-shown explanation lines | Typical conditional data notes on the review seed |
|---|---|---|
| Overview `/` | 4 (KPI basis, closed-trades basis, drift threshold line, "Due" paragraph) | 3 |
| Wealth `/portfolio` | 6 + 7 ⓘ | 9 (8 in the data-quality block) |
| Snapshots | 4 + 1 always-on note that is an explanation | 2 |
| Tax | 3 + 2 ⓘ | 2 |
| Cash flow (4 facets) | 2 per facet + 1 ⓘ per facet | 1 per facet |
| Risk | 3, two of them styled as empty states | 1 |
| Securities, detail tabs | 1 per tab (basis or purpose) | 0 to 3 |
| Imports, Views, Classifications, Accounts | 2 to 4 each | conditional |

## Where today's UI already breaks its own rules

Found by the inventory; each is a conformance finding, not part of I1's
decision.

- The view switcher's ⓘ opens as a plain paragraph, not a popover: **#1350**.
- `.hint`, `.muted`, `.alert-*` and `badge-warning` still carry data facts,
  although `DESIGN.md` (line 1086) says the data note replaces them.
- An always-on explanation is shown as a data note: Snapshots, "the
  comparison is gross and price development only".
- Meaning that lives only in `title=`: Wealth's overlapping-buckets sentence,
  the rebalance hint's quote date, three column titles on Classifications
  (with EUR hard-coded).
- The same explanation twice on one screen: Views, the buckets ⓘ and the
  basis line under it.
- Two always-on explanations on Risk are styled as empty states.

## The variants

- **A — ⓘ at the heading, notes one line.** Every explanation line of a
  section moves into one ⓘ beside the section heading; every data note is
  clamped to one line with "mehr".
- **B — ⓘ, notes collected.** As A for explanations; problems stay visible
  (clamped), attention and note fold into one line per block with their
  counts ("4 Achtung · 1 Hinweis — anzeigen").
- **C — an "Erklärungen" switch.** One switch in the top bar hides or shows
  every explanation line at once; notes clamped as in A.

Not prototyped, named in the discussion: explanations shown until
dismissed once; a per-page help panel; footnote markers with the text at
the page foot; data notes moved onto the figure they affect.

## What the variants run into

- **"Every number states its basis"** (UX-DR11, `EXPERIENCE.md`): a basis
  line hidden behind ⓘ breaks it. The prototype hides basis lines and
  explanations alike, because both use the same classes; a real change has
  to split them, so a short basis (view · period · currency) stays visible
  and only the method sentences move.
- **An excluded row is named beside its total** (UX-DR25): a one-line clamp
  hides the names. On a 390 px phone one line keeps only the first words.
- **`.hint` carries data facts too**, so a mechanical move also hides facts
  (on Snapshots: "Wieder eingespielt? Ja"). The inventory's per-line
  classification is the input a real change needs.
