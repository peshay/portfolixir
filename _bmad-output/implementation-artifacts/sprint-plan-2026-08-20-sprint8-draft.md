# Sprint 8 — the design-language execution, and the debt with a deadline (DRAFT)

**Status: draft, awaiting owner adoption.** Written 2026-08-20 at the Sprint 7
close-out (0.7.0 released). One open decision gates one lane (D-1 below); the
rest is schedulable as filed. Verification basis: the post-0.7.0 open-issue
list (39 open), the FR Coverage Map as reconciled 2026-08-19, and the
design-language spec as amended by the #707 engagement.

## Why this cut

Three forces pick the sprint, and none of them is new work invented here:

1. **The two-way coverage rule's deadline.** FR-37/38 shipped agent-only in
   Sprint 6; Sprint 7 refiled the surviving human-view debt as #731 and #732
   with the explicit deadline "end of the next batch". This batch IS the next
   batch, so these two are the one non-negotiable lane — their absence at
   this close-out is a finding by the rule's own terms.
2. **The #707 engagement produced a spec that is now sitting unexecuted.**
   D1–D6 are decided and written into `EXPERIENCE.md`/`DESIGN.md` (ADR-0038
   makes the living spec the authority — no further gate needed); #717–#721
   and #723 are their issues. A design decision that waits two batches
   becomes a re-litigation.
3. **The Cash-flow area is a parent with one child.** #672 shipped the
   `/cashflow` route and the Income facet; #724–#726 are the three facets it
   deliberately cut. A tab family of one answers no question for long.

## Lanes

### Lane A — two-way-rule debt (mandatory, first after Lane Z)

- **#731 — the `?since=` human view.** A changed-since surface over
  transactions and securities, with the one property that makes a delta read
  honest stated ON the surface: deletions are not represented. Pull-only;
  B3.7 stays gated.
- **#732 — the `fields=` column picker** for the transactions and holdings
  lists, following the pattern the securities picker already set — and
  closing the asymmetry that the one list WITH a picker is the one list
  without `fields=`.

### Lane B — design-language execution (#707's output)

The spec is written; this lane builds it. Order by user impact:

1. **#717** — filter chips become the primary securities filter (D2), the
   builder demoted behind the counted disclosure — the same pattern #414
   shipped on Transactions, so the two histories converge on one interaction.
2. **#718** — the drift card is named for what it contains (D1).
3. **#720** — view switcher drops the "View:" prefix, names the manage
   control (D4).
4. **#721** — custom date range as a real from/to pair that validates and
   shows itself (D5).
5. **#723** — the "computing" cue on 100–400 ms figures is a rendering
   decision, per the measured figures ADR-0039 recorded.
6. **#719** — retire the Σ-Konflikt pill: findings are data notes, the
   remainder is a row (rides on ADR-0040's shipped remainder).
7. **#729** — built-in classification trees speak the locale (the Sprint 7
   walkthrough finding; same class as #701, and the same fix shape: localize
   at render keyed on the stored `key`, keep the seed idempotent).
8. **#730** — the just-requested column (Saldo, Drift) must not be the last
   one in its scroller on a phone. Includes the small DESIGN.md rule it
   needs ("a surface's subject column sorts before its context columns
   under narrow width"), so the fix is a rule, not two one-offs.

### Lane C — Cash-flow facets (#672's cut children)

- **#724 — Realized gains facet. Risk-tier, and gated on D-1 below.** Needs a
  cross-security closed-trades read (the matcher is per-security today) and a
  **stated FX basis** before it can draw one bar. The computation basis goes
  in the API/MCP payload per the AGENTS.md metric rule — review-blocking.
- **#725 — Deposits & withdrawals ("Ersparnis").**
- **#726 — Costs facet, overview level only.**

Facets are independent; this lane degrades gracefully (shrink order below).

### Lane D — toolchain (risk-tier attention label, own commit groups)

- **#728 — pin the Node runtime** (CI `setup-node` + `engines`), which is
  what makes the parked `@types/node` major decidable. After it lands, bump
  `@types/node` deliberately in the same commit group; Dependabot PR #692 was
  closed with an ignore for the major, so the bump is ours to make, not a
  reopened bot PR.
- **#727 — Elixir/OTP move** (1.18.3/OTP 27 → current). CI `elixir-version`/
  `otp-version`, the Dockerfile and the PLT cache key move TOGETHER; full
  gate run on the new toolchain before anything else stacks on it.

### Lane M — maintenance (always present)

Point-in-time from `version-report-2026-08-19.md`; regenerate at lane time.
Known review candidates: BMAD `tea` (four minors behind, sha-pinned, needs
its changelog read), `cis`/`bmb` (compare against their repos' tags, not npm
dist-tags — the report records why), cowlib (re-check for a fixed release;
three advisories, none fixable today). **The lane's report is written WHEN
THE LANE RUNS, not at close-out** — Sprint 7's one process miss, and the
done-list below makes it checkable.

### Lane Z — structural (small this time)

- **Release-tag hygiene, closed structurally.** 0.5.0, 0.6.0 and 0.7.0 are
  all lightweight against ADR-0026 step 5's "annotated", and the failure
  mode is now identified: the release-UI's "create new tag" cannot produce
  an annotated tag, and the agent's proxy cannot push tags at all. The fix
  is a guard, not a fourth reminder: the Release workflow warns (or fails
  soft with a note in the release body) when the pushed tag is lightweight,
  and the close-out checklist points at the prepared-command path.

## D-1 — the one open decision (gates #724 only)

**FX basis for the realized-gains roll-up.** Two candidates recorded in
#724; the recommendation is **option 1 — convert each sale at its booking
date through the EUR hub**, as `Portfolios.Income` already does for
dividends, because the realized figure is a historical fact tied to its date
and the sibling facet already speaks that basis. Rate-availability behavior,
spelled out rather than left to the implementation: a sale whose
booking-date rate is not stored is **excluded from the converted total and
named on the surface** (count + securities), never converted at a
neighboring date's rate and never silently dropped — the same
excluded-and-named shape ADR-0041 uses. If the owner prefers option 2
(per-currency totals, unconverted), the facet ships without the period chart
and says why.

A one-page ADR or a signed line on this draft both satisfy the gate
(ADR-0026 step 1); the invariant either way is pinned by exact `Decimal`
expectations before activation.

## Sequencing

```
Lane Z (tag guard) ──▶ independent
Lane A: #731, #732 ── first, the deadline lane
Lane B: #717 ──▶ (#718, #720, #721, #723, #719, #729, #730 independent)
Lane C: D-1 signed ──▶ #724; #725, #726 independent
Lane D: #728 ──▶ @types/node bump; #727 as its own group
Lane M: independent throughout, report written at lane time
```

## Shrink order (cut from the bottom, name the cut in the briefing)

1. #726 (costs facet) — smallest reader value of the three facets.
2. #721 (custom date range) — the range presets still work.
3. #730 — the rule can land in DESIGN.md with the fix following.
4. #727 — the toolchain holds another sprint if the batch runs long; #728
   does NOT shrink, because #692's decision hangs on it.

Lane A never shrinks — it is the deadline.

## What "done" means for this sprint

1. #731 and #732 are merged, or this close-out records the two-way-rule
   finding the deadline prescribes — there is no quiet third option.
2. Every #707 decision issue in Lane B is closed or its remainder is named
   in the briefing with the user-visible consequence stated.
3. #724's FX basis is stated in the API and MCP payload (series, basis,
   gap treatment) — review-blocking per the AGENTS.md metric rule.
4. The toolchain commits are independently revertable, each with green
   gates, and the `@types/node` decision is recorded either way.
5. Lane M's report exists BEFORE the closing act starts.
6. The closing act runs under section G's conditions (DE, ≤390 px,
   finding-triggering seed) — including at least one pass over the NEW
   facet surfaces with data that fires their empty/excluded states.
7. Close-out per ADR-0026 step 5, with an annotated `0.8.0` via the
   prepared-command path (the Lane Z guard makes a lightweight tag loud).
