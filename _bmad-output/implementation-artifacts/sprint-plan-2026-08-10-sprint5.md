# Sprint Plan — Sprint 5 (ADOPTED, 2026-08-10)

**Status: adopted.** This plan supersedes
`sprint-plan-2026-08-10-sprint5-draft.md` and answers its three open
questions with the owner's decisions of 2026-08-10. The decision gate was
already passed (the owner's merge of #652 confirmed the design-language
spec, close-out #655); this document fixes the sequencing, the lane→issue
mapping, and the batch topology.

Ground truth at adoption: `main` at `cf68260` (Sprint 4 complete — Lane A
#652, Lane B #560/PR #656, Lane C #568/PR #657 merged, close-out #658).
Verified against the open-PR list (empty) and the open-issue list, not
against tracking files alone.

## Owner decisions (2026-08-10)

1. **All lanes run in ONE batch** on one epic branch
   (`agent/claude/sprint-5-design-debt`), per the ADR-0026 default.
2. **One PR per sprint.** A lane is split into its own PR only if it turns
   out big during the batch (the Sprint-4 retro item 1 rule, now decided
   up front: default combined, split on size — the batch agent flags the
   split in the PR briefing rather than asking mid-sprint).
3. **#572 (benchmark comparison) stays out of Sprint 5.** It is E5
   money-domain analytics work, not design-lane work; it remains the
   unblocked front-runner for Sprint 6.
4. **Release automation joins the sprint as Lane F** (#659): version tag +
   GitHub release with generated notes per sprint merge, wired through CI
   and the ADR-0026 step-5 bookkeeping rules, so releases happen
   automatically from then on.

## Sources

- `design-language/DESIGN.md` — "Violations in the built UI" (the
  corrections list, including two designer-decided token values dated
  2026-08-05).
- `design-language/review-accessibility-2026-08-05.md` and
  `review-design-critic.md` — filed findings.
- `sprint-plan-2026-08-10-sprint5-draft.md` — the sequencing draft this
  plan adopts.
- Filed implementation issues #634–#654 (from the Sprint 4 Lane A
  close-out) plus #659 (release automation, filed at adoption).

## Lanes (one batch, smallest-risk first)

### Lane A — Token and contrast corrections (mechanical, decided in the spec)

Every item has its correction written in DESIGN.md; several values are
explicitly designer-decided 2026-08-05. One commit group per token family.

- #643 `--color-warning-soft` dark values (`rgb(251 191 36 / 0.16)` in
  both dark blocks — decided).
- #650 `--shadow-sm` dark value (`0 1px 3px rgb(0 0 0 / 0.5)` — decided).
- #648 `--color-danger` re-key to `#b91c1c` in `:root` +
  `[data-theme="light"]` (closes the `.alert-error` 4.02:1 violation —
  decided via the danger-tint gate).
- #642 segmented-control active-option contrast in dark mode (all
  accents).
- #644 `--color-selected` re-keyed per `[data-accent]`, plus accent
  hard-coded to violet in six rules → `var(--color-accent)`.
- Undefined-token cleanup (no issue — spec corrections list):
  `--color-border-subtle` → {colors.border}, `--color-surface-hover` →
  {colors.hover}, `--color-surface` alias → {colors.bg} directly;
  `white` / `--color-on-accent` literals → theme-dependent
  {colors.on-accent}.

### Lane B — Colour independence and semantic sign (UX-DR7)

- #637 signed values on stat/KPI cards take {colors.positive}/
  {colors.danger} plus a sign — at every level, not only totals; unsigned
  values keep the accent.
- #645 buy/sell chart markers become ▲/▼ paths instead of hue-only
  circles (the `<title>` fallback is unreachable under `role="img"`, so
  shape is the only channel).

### Lane C — Loading affordances and motion (owner decision 2026-08-05)

- Skeleton states; the count-up pattern (cosmetic count-up to the final
  value with a visible "still counting" state); progressive sunburst
  fill; replacement of "Lädt …" text and bare-dot placeholders.
- #638 `.section-skeleton` gains its reduced-motion gate.
- #647 reduced motion flips to opt-in form for all four gated animations
  (inseparable from the motion work above; UX-DR spec).

### Lane D — Hint prose → ⓘ tooltips (UX-DR11)

- Performance-chart footnotes and the income EUR-hub note move into
  on-demand tooltips; "chart as table" kept but de-emphasized as the
  accessibility fallback (UX-DR10 stays mandatory). Spec-driven, no
  filed issue.

### Lane E — Markup, i18n and navigation defect sweep

Small independent defects from the same filing batch, each with its own
commit:

- #634 allocation table: two of four column headers render as floating
  boxes.
- #635 classifications form: checkbox stack renders broken.
- #636 count-bearing strings use `gettext` with `%{count}` instead of
  `ngettext` (8 sites).
- #639 `nav_current?/2` omits `/snapshots`.
- #640 SecurityChart empty state hard-coded English, bypassing gettext.
- #641 date inputs render MM/DD/YYYY in a product whose display dates are
  ISO.
- #646 modals become native `<dialog>` with real focus containment
  (spec: native `<dialog>` was recorded as shipped and is not).
- #649 filtered no-match shows a no-results state instead of the
  empty-surface message.

### Lane F — CI and release engineering (#659, owner decision 2026-08-10)

- #659 release automation: the ADR-0026 step-5 bookkeeping close-out
  gains "create and push an annotated `vX.Y.Z` tag"; a CI workflow on
  tag push (`v*`) creates the GitHub Release with generated notes
  (squash-merged PR titles/briefings as source material). First tag
  `v0.5.0` at the Sprint 5 merge, minor bump per sprint, patch reserved
  for hotfixes. AGENTS.md "Epic-Batch Workflow" step 5 is amended in the
  same lane. No installable artifacts — the release is a rollback point
  for self-hosted instances plus a communicable changelog.
- #653 LiveView "missing form id" warnings make CI test failures
  undiagnosable.
- #654 CI uploads no test-failure artifact.
- All three touch `.github/workflows` — the CI meta-tests (`ci_test.exs`,
  `workflow_docs_test.exs`) are updated together with each change, never
  skipped. (Adoption call: #653/#654 ride here because they are the same
  CI surface and pay off during this sprint's own runs — strike them from
  the lane if unwanted.)

## Queued behind the lanes (unchanged from the draft)

- #651 URL-addressable securities filters (enabler for the Overview
  data-quality link — its own cut story; the 2026-07-12 decision is
  currently impossible without it).
- Assets-view tabs, period selector and date picker rework.
- Contra-account value-setting UI; snapshots view makeover.
- Income view set (#415 umbrella).
- Tax view as an MCP-first review/overview surface.
- Overview "needs attention" card: naming its view + plan context.
- #572 benchmark comparison — Sprint 6 front-runner (owner decision
  above).

## Explicitly not Sprint 5

- The "from data to information" insights direction (needs a product
  brief and a decision gate; Hard Rule "no advanced reports" stands).
- PP XML import (#333) — gated on its own ADR + AGENTS.md amendment.
- Active-plan-per-allocation semantics — E16/ADR-0027 decision gate.
- Anything from the parking lot (#340).

## Process notes for the batch

- Epic branch `agent/claude/sprint-5-design-debt`, rebased onto `main` at
  least daily; one PR for the sprint (split rule above). Owner merges;
  agents never merge.
- No money-domain math in Lanes A–E → no risk-tier labels expected; the
  css invariant meta-tests and the design-critic review role (ADR-0038)
  are the verification pass for the token lanes. Lane F is process/CI,
  not money-domain, but changes review-relevant enforcement — call it out
  in the reviewer briefing.
- Every lane lands with its pinning tests (css assertions per repo
  precedent, LiveView assertions for markup) and a gettext pass where
  user-facing strings move.
- CSS comments spell `issue 560`, never `#560` (Sprint-4 retro item 2 —
  the css-token-discipline invariant reads `#NNN` as a hex colour).
- Agentic-review closing act per ADR-0026 step 3: correctness hunter,
  edge-case hunter, UAT persona walkthrough on seeded synthetic data, and
  the design critic against the living design-language spec.
- Bookkeeping close-out per ADR-0026 step 5 — for the first time
  including the `v0.5.0` tag + release once Lane F has landed the
  automation.
