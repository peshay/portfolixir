# Sprint 9 — closing-act walkthrough (2026-09-03)

Design-critic and UAT persona pass of the agentic review closing act
(ADR-0026 step 3), run under section G's conditions of
`docs/development/pr-review-checklist.md`, on the synthetic demo dataset
(`priv/demo/`, no real data).

## Conditions the walkthrough ran under (stated so the claim is checkable)

- **DE locale**: every touched screen was rendered in DE (`accept-language:
  de-DE`); the EN desktop shots are the comparison, not the pass.
- **390 px**: one full pass of the Research tab and the Cash-flow realized
  facet at 390 × 844 (`research-de-390.png`, `cashflow-realized-de-390.png`).
- **Seed data that fires the alarm surfaces**: an unclassified security
  (`Thames Utilities plc`, not in the Strategies tree), a security with no
  quote (the same), a plan that does not sum to 100 % (the Strategies plan
  sums to 1.65), a research log with a **superseded** entry (#1 replaced by
  #2), a **retracted** entry (#3 retracted by #4), a `decision` expiring
  within 7 days (#6, valid until 2026-09-08), and a GBP sale whose close
  date has no stored rate (the Sprint 8 D-1 fixture), so the realized
  facet's exclusion note renders with the new backfill control.
- The security with no entry for 90 days condition holds for every demo
  security except the one seeded (Allianz), so `notes/unreviewed?days=90`
  lists the other six.

## What was looked at

| Shot | Screen | What it shows |
| --- | --- | --- |
| `research-de-390.png` | `/securities/3?tab=research`, DE, 390 px | thesis state (Intakt), the append form, the timeline newest first; superseded (#1, #3) dashed and marked "Ersetzt durch"; the retraction (#4) marked "Widerruft #3"; the decision's "Gültig bis" |
| `research-en-desktop.png` | same, EN, 1440 px | the second-level tab row with Research as the eighth tab; the thesis fact grid in one row |
| `research-en-desktop-full.png` | same, full page | the complete timeline |
| `cashflow-realized-de-390.png` | `/cashflow?tab=realized`, DE, 390 px | the exclusion note naming the GBP sale with the live control "Historische Kurse nachladen" and the stated remaining limit |
| `cashflow-realized-en-desktop.png` | same, EN, 1440 px | the same note at desktop width |

## Findings and what was done

1. **Fixed on the branch (design critic, 390 px, DE):** the fact grids under
   a thesis and under an entry ran two columns of uppercase labels at 390 px,
   and the long German label "Invalidierungsbedingung" overran the neighbour
   column ("INVALIDIERUNGSBEDINGUNGZEITSTOPP" in the first take). The grids
   now stack below 480 px and labels wrap (`overflow-wrap: anywhere`); the
   retaken shot is the one in this directory. Folded into the #751 commit.
2. **Accepted as is:** a source URL wraps mid-word inside its column
   (`overflow-wrap: anywhere` on the value) — preferable to a horizontal
   scroll on a phone; the full URL stays legible and the link target is
   intact.
3. **Not exercised live:** the backfill button's click on the demo instance
   would fetch the real ECB series over the network; the end-to-end path
   (click → background run → note disappears → exact converted total) is
   pinned by `test/portfolixir_web/live/cashflow_backfill_test.exs` with the
   fake provider instead.
4. **Noted for the UX spec, not changed:** the pane's second-level tab row
   at 390 px scrolls horizontally with Research as the last tab (the row
   already did before this batch; EXPERIENCE.md's second-level tab rule
   covers it). No new tab idiom was introduced.
