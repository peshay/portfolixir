# Sprint Plan — Sprint 5 (DRAFT, 2026-08-10)

**Status: draft sequencing, not a decision.** The decision gate is already
passed: the owner's merge of #652 confirmed the design-language spec
(Sprint 4 Lane A close-out, #655), and the implementation work is filed as
issues **#634–#654**. What this draft adds is the *sequencing* — which
issues form which Sprint 5 lanes, in what order — for the owner to confirm
or reshuffle with one read. Companion to `sprint-status.yaml`; supersedes
nothing. Mapping the lanes below to the concrete issue numbers in
#634–#654 is the first step of the sprint-planning session that adopts
this draft.

Ground truth: `main` at `5167f27` — Sprint 4 complete (Lane A #652,
Lane B #560/PR #656, Lane C #568/PR #657 all merged).

## Sources

- `design-language/DESIGN.md` — "Violations in the built UI" (the corrections
  list, including two designer-decided token values dated 2026-08-05).
- `design-language/review-accessibility-2026-08-05.md` and
  `review-design-critic.md` — filed findings.
- `sprint-plan-2026-08-05.md` Lane A scope list — the owner-scoped design
  session topics whose stories become Sprint 5+.

## Proposed lanes (smallest-risk first)

### Lane A — Token and contrast corrections (mechanical, already decided in the spec)

Everything here has its correction written in DESIGN.md; several values are
explicitly designer-decided 2026-08-05. One commit group per token family.

- `--color-warning-soft` dark values (`rgb(251 191 36 / 0.16)` in both dark
  blocks — decided).
- `--shadow-sm` dark value (`0 1px 3px rgb(0 0 0 / 0.5)` — decided).
- `--color-danger` re-key to `#b91c1c` in `:root` + `[data-theme="light"]`
  (closes the `.alert-error` 4.02:1 violation — decided via the danger-tint
  gate).
- Undefined-token cleanup: `--color-border-subtle` → {colors.border},
  `--color-surface-hover` → {colors.hover} (one value), `--color-surface`
  alias → reference {colors.bg} directly.
- Accent hard-coded to violet in six rules → `var(--color-accent)`, plus
  the token-level case: `--color-selected` re-keyed per `[data-accent]`
  (issue #644).
- `white` / `--color-on-accent` literals → theme-dependent {colors.on-accent}.

### Lane B — Colour independence and semantic sign (UX-DR7)

- Signed values on stat/KPI cards take {colors.positive}/{colors.danger}
  plus a sign — at every level, not only totals; unsigned values keep the
  accent.
- Buy/sell chart markers become ▲/▼ paths instead of hue-only circles
  (issue #645; the `<title>` fallback is unreachable under `role="img"`,
  so shape is the only channel).

### Lane C — Loading affordances (owner decision 2026-08-05)

- Skeleton states; the count-up pattern (cosmetic count-up to the final
  value with a visible "still counting" state); progressive sunburst fill;
  replacement of "Lädt …" text and bare-dot placeholders.

### Lane D — Hint prose → ⓘ tooltips (UX-DR11)

- Performance-chart footnotes and the income EUR-hub note move into
  on-demand tooltips; "chart as table" kept but de-emphasized as the
  accessibility fallback (UX-DR10 stays mandatory).

## Queued behind the lanes (need their own cut stories / decisions)

- Assets-view tabs (visual language shared with the icon menu), period
  selector and date picker rework.
- Contra-account value-setting UI; snapshots view makeover.
- Income view set (#415 umbrella): bars per month/quarter/year,
  accumulated-per-month chart, closed trades, deposits/withdrawals view,
  explicit labeling of what "income" aggregates; per-instrument breakdown
  stays an open design question.
- Tax view as an MCP-first review/overview surface (owner decision
  2026-08-05, no document intake).
- Overview "needs attention" card: naming its view + plan context.
- #572 benchmark comparison — unblocks once #568 is on `main` (reuses the
  projection's flow markers); E5 scope, not design-lane work.

## Explicitly not Sprint 5

- The "from data to information" insights direction (needs a product brief
  and a decision gate; Hard Rule "no advanced reports" stands).
- PP XML import (#333) — gated on its own ADR + AGENTS.md amendment.
- Active-plan-per-allocation semantics — E16/ADR-0027 decision gate.
- Anything from the parking lot (#340).

## Process notes for the batch

- Epic-batch workflow per ADR-0026 unchanged; if the owner prefers the
  Sprint-4 mode (one PR per lane), fix that topology in this plan before
  the batch starts — decided up front this time (Sprint 4 retro item 1).
- No money-domain math in Lanes A–D → no risk-tier labels expected; the
  css invariant meta-tests and the design-critic review role are the
  verification pass for the token lanes.
- Every lane lands with its pinning tests (css assertions per repo
  precedent, LiveView assertions for markup) and a gettext pass where
  user-facing strings move.

## Open questions for the owner

1. Lane order/capacity: A+B are small and mechanical; C and D carry the
   visible product change. All four in one batch, or A+B first?
2. Per-lane PRs (Sprint-4 mode) or one epic branch (ADR-0026 default)?
3. Whether #572 (benchmark comparison, now unblocked by #568) rides
   Sprint 5 as its own lane or waits — it is E5 analytics work, not
   design-lane work.
