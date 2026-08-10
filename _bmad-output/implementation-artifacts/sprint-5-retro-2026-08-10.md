# Sprint 5 Retrospective — design-debt batch, lanes A–F (2026-08-10)

**Status: batch retrospective, written at PR time.** The ADR-0026 step-5
close-out items (issue/tracker closure, merge-CI confirmation, the `v0.5.0`
tag and first automated release) run after the owner's squash-merge and are
appended then.

## What shipped

One batch on one branch, one PR, per the owner's 2026-08-10 decisions
(sprint-plan-2026-08-10-sprint5.md). All six lanes landed:

- **A — tokens/contrast** (#642 #643 #644 #648 #650 + spec cleanups): every
  designer-decided value adopted verbatim; theme-block token parity, the
  no-undefined-token rule and the decided values are pinned by a new
  invariant test.
- **B — colour independence** (#637 #645): signed metrics carry sign +
  gain/loss colour at every level; buy/sell markers are ▲/▼ paths.
- **C — loading/motion** (#638 #647 + owner picks): recomputing cue,
  value-slot pending fallback, CountUp settling hook (ninth inline hook),
  progressive sunburst, opt-in reduced-motion form pinned by a motion-gate
  invariant test.
- **D — UX-DR11**: performance and income methodology prose out of the
  sightline (one definition, one place).
- **E — defect sweep** (#634 #635 #636 #639 #640 #641 #646 #649): one
  commit each; native `<dialog>` modals and ISO date entry are the two
  behaviour-visible ones.
- **F — CI/release** (#653 #654 #659): release-on-tag workflow, recoverable
  test-failure artifact, fatal missing-form-id warnings.

Gates at PR time: 1754 tests / 0 failures, coverage 89.8% total, Credo
strict clean, Sobelow clean, Dialyzer zero, MCP 62 tests + build green,
pre-commit green, `--warnings-as-errors` clean.

## Agentic review closing act — what it caught

Four roles ran (correctness hunter, edge-case hunter, design critic, UAT
persona with a live server + screenshots on synthetic seed data,
`uat-sprint5-2026-08-10/`). The round earned its cost:

1. **The worst bug of the sprint was invisible to every DOM-level test.**
   morphdom strips the client-set `open` attribute from native dialogs on
   the first server patch — every converted modal would have died on its
   first keystroke. Caught independently by the correctness and edge-case
   hunters via client-source tracing, fixed with an `updated()` re-assert.
2. **Computed-style regressions are a test blind spot.** Two cascade fights
   (`.stat span` swallowing the count-up digits; sign classes losing to
   label/dd rules) shipped green through 1700+ tests and were caught only
   by the design critic reading the cascade and the UAT persona reading
   computed styles off a real render.
3. **The spec's decided outcomes beat plausible implementations.** Lane D
   had recreated the TTWROR-duplicate the rule exists to delete; the
   dashboard section skeletons had been demoted against an explicit keep.
   Both reverted to the spec's letter.

## Lessons carried forward

- **A screenshot/computed-style pass belongs in every user-visible batch**
  — the UAT persona ran the real server with Playwright and found cascade
  bugs no LiveViewTest can see. Standing instruction added to the dev-agent
  override; consider a small CI screenshot smoke as a future gate story.
- **Client-behaviour hooks need client-behaviour review.** Two of the three
  serious findings were JS/morphdom lifecycle issues. Until a JS test
  harness exists (deliberately out of scope), hook changes get a dedicated
  trace against the pinned LiveView client source in review.
- **Pipeline codified.** The owner's "never tell me this again" instruction
  is now `_bmad/custom/bmad-agent-dev.toml`: a plain "work sprint N" runs
  lanes → gates → four-role review → PR → watch/fix → close-out + tag.

## Follow-ups (filed as notes, not fixed — scope lock)

- Classification category rows render two always-identical count badges
  (`cat-count` and `cat-positions` both show `total_count/1`) — needs its
  own issue.
- Cash-flow transaction history rows show no amount (only month headers
  do), and trailing zeros are trimmed on prices — pre-existing; issue-worthy.
- The Cash KPI card's composite value wraps to three lines on narrow
  panels — pre-existing composite-typography debt.
- Securities detail custom range: a pattern-shaped but invalid date (e.g.
  2026-13-40) fails silently; the portfolio surface has `range_error`
  parity to copy.
- P2 "last known value dimmed" is implemented where a prior value exists
  today (the stale-TTWROR card); the general stored-previous-value slot and
  `.stale-marker` machinery for all KPI slots remain design debt.
- The three `role="status"` section-level pending regions predate the
  batch and still conflict with the one-region-per-surface announcement
  rule (EXPERIENCE.md State Patterns item 4).

## Close-out (appended after merge)

- [ ] Squash-merge landed; merge CI green (required checks included).
- [ ] Issues #634–#650, #653, #654, #659 closed; #651 stays queued.
- [ ] sprint-status.yaml close-out block written.
- [ ] Annotated `v0.5.0` tag pushed; Release workflow produced the first
      automated GitHub release.
