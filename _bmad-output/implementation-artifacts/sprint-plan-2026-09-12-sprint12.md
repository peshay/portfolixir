# Sprint 12 — the surface, brought level with its spec

**Status: ADOPTED by the merge of PR #783 (2026-09-12).** The merge is the
signature (ADR-0026 step 1 as amended on PR #780): it adopts the lane cut AND
signs **D-1** to **D-5** below. The variant picks the review leaves to the
owner (issues #797–#801, #803–#806) are made by one comment on the issue or
on PR #783; **silence is the recommended variant** (D-2). Verification basis:
`main` at 1e78853 (the Sprint 11 planning merged 2026-09-07; no Sprint 11
batch branch or PR exists yet), the open-issue list before the review filed
anything (27 open) and after (52), the open pull requests (three Dependabot
PRs — #775, #781, #782 — and #783 itself), the review document
`planning-artifacts/ux-review-2026-09-12.md` and its twenty-five issues
#784–#808.

## State of play, in four lines

1. **Sprint 11 is adopted and unstarted.** Its plan merged five days ago; its
   batch branch has not opened. This plan does not displace it — D-1 says in
   which order the two batches run, and why it is not "both at once".
2. **The spec has been ahead of the build on four surfaces for four sprints.**
   Tax, Snapshots, Views and the Wealth data-quality list have their target
   shape in `EXPERIENCE.md` → Component Patterns since 2026-08-05; the
   alignment stories were "cut from the spec" and never cut. The review's
   Part 0.1 names it; Lane S closes it.
3. **Eleven defects survived four closing acts because no closing act ran
   under the conditions that show them.** The clipped umlaut is on every
   docs screenshot since the top bar was built; the raw `balance_adjustment`
   slug is in every balance row; the stale quote renders as live. The #706
   conditions (DE, 390 px, seed data that fires the alarm surfaces) were
   adopted on 2026-08-15 and this review is the first pass that ran them on
   every route. D-4 makes them the closing act's conditions for good.
4. **Twenty-five issues are two batches, not one.** Eight defects (agentic,
   small), nine alignment stories (rule exists, no pick), eight compositions
   (owner picks a variant, `needs-uat`). Sprints 7 and 8 closed eight UX issues
   each; this plan takes twenty-two and states the shrink order that turns
   it back into one batch if the closing act says so.

## Why this cut

- **Defects and alignment lead because they need nothing from anyone.** Lane F
  and Lane N are mechanical against a verified code location each; Lane S
  builds a shape the spine already fixed. None waits on a pick, none needs a
  gate, and together they are what ADR-0038 calls "visual drift becomes a
  review finding instead of an owner discovery months later" — here the
  months are four, and the discovery is this review.
- **The composition lanes ride on picks the owner makes in one comment each.**
  The review lists the recommended variant first and D-2 makes silence the
  pick, so the lanes do not block on a session; the picked variant is written
  into `DESIGN.md` by the story that builds it, which is how the spine stays
  the authority (ADR-0038 §3).
- **The phone work is one lane** (K's phone half, P) because it shares one
  new rule (UX-DR27) and one mechanism (the D6 strip: overflow, snap, fade).
  Splitting it would have two stories invent the strip twice.
- **Transactions is one lane** because #470's earlier stories landed on the
  pre-language screen and the 2026-08-15 triage ruled the UI dimension must
  land with the design engagement, not before it. #786 (numbers, amount
  column) rides Lane F so the table is right whichever form home wins.
- **What waits, and why:** #807 is `needs-decision` (the Trades reconciliation
  the 2026-08-15 triage deferred — the owner signs it by comment, Sprint 13
  builds it); #798-B changes UX-DR2 and is built only if picked; #806 and
  #808 are low-traffic administration surfaces and are the first thing a
  closing act should not spend its day on.

## Lanes

### Lane F — the defect sweep (#784, #785, #786, #788, #790, #791; first)

Six issues, one commit group each, every one against a verified location in
the review's Part 1. The two meta-tests land here and stay: every element of
`Transaction.kinds/0` has a gettext label clause (the `to_string` fallback is
removed, #785), and the second-person grep over the DE catalog returns zero
outside quoted legal terms (#791). The docs screenshots that carry the clipped
title are re-taken with #784. F runs first because #785's labels and #786's
table are what Lanes N and T build on.

### Lane N — data notes and freshness (#792, #789, #787)

The UX-DR17 remainder and the freshness rule: the Wealth data-quality list as
six `{components.data-note}` rows at the inventory's severities with the
remedy inside the note (#792); the stale-quote marker at its three call sites
with the `:clock` glyph joining the icon set (#789); one basis line and one ⓘ
per Cash-flow facet, a subtitle per facet (#787). No pick, no gate. #789's
optional `stale` boolean, if added, lands on API and MCP in the same commit
or the PR says why not (two-way coverage).

### Lane S — the four specified surfaces and the two chart gaps (#795, #796, #802, #793, #794)

Tax to the budget-meter-plus-check-list shape, Snapshots with the comparison
first, Views as read-first rows — each builds the paragraph `EXPERIENCE.md` →
Component Patterns already carries, with the review's target mockup as the
picture of it. The sunburst gains its disclosure, basis line and centre
(#793); the income chart gains legend, continuous years, quiet zeros, both
disclosures and the accumulated-per-month series if it has not shipped
(#794). Tax and Snapshots are `needs-uat`: the owner walks them at the
closing act with the seed script's statement and snapshot. **Risk-tier
attention label on none** — nothing computed changes; #794's accumulated
series is a running sum of numbers already on the page and states its basis
in the chart's `aria-label`.

### Lane K — the Wealth KPI band and the Overview (#797, #798; picks)

Recommended A and A. The band re-composes into two tiers with no value
wrapping and does not repeat on the Allocation tab; the Overview gains the
90-day trend in the value card and drift bars in the rows. **The design
critic verifies the value-slot states after the re-composition** — pending,
settling, the count-up hook, width reservation (UX-DR18/20) — because a
re-composed card is where those regress silently. If B is picked for #798,
UX-DR2 is amended in the same PR.

### Lane P — the phone (#799, #800; picks)

Recommended A and A: two-line rows under 560 px for Securities and
Transactions (UX-DR27), one swipeable chip strip with the D6 fade for the
filter chrome. #788 (the drift table's scroller) rides Lane F but its
verification is here, at 390 px, with the rest of the phone pass.

### Lane T — Transactions (#803; pick)

Recommended A: the form as a disclosure panel above the history, the
holdings section gone from the route, the amount column from #786. The lane
touches the oldest LiveView in the app; its closing-act condition is the
booking walkthrough (one transaction of each of buy, dividend, deposit) on
desktop and phone.

### Lane D — the detail pane, the tree rows, the custom range (#804, #805, #801; picks)

Recommended A, A, A: the securities detail's first tab reads, the
classification tree rows get a column head, the custom range opens in a
popover on its trigger. Last in order because each is a contained surface
and the first to go under the shrink order.

### Lane M — maintenance (always present)

- **Dependabot #781 (dialyxir 1.4.7 → 1.4.8):** apply as its own commit;
  the quality gate is the evidence.
- **Dependabot #782 (Node 26.8 image):** close with the reason Sprint 11 gave
  #774 — Node 26 is Current until October 2026; the trigger is the LTS
  promotion, and the runtime is pinned in four places by an invariant test.
- **Dependabot #775 (Elixir 1.20.3-otp-29):** owned by Sprint 11's Lane M;
  not re-decided here.
- `version-report-2026-09-XX.md` written at lane time, before the closing
  act starts.

### Lane Z — registry (small)

No new epic: this sprint is **E11's second alignment pass**, tracker #356
(twenty-five sub-issues attached on 2026-09-12). When the branch opens: the
FR Coverage Map's UX-DR row gains #784–#808 and UX-DR27; the Tracker Index's
E11 line gains the 2026-09-12 review as its second reference; this file's
planning entry is already in `sprint-status.yaml`; the close-out reconciles
against the existing rows.

## Decisions

### D-1 — Sprint 11's batch runs first; Sprint 12 opens after its merge (recommended)

Sprint 11 carries risk-tier correctness (#779, #610), the security remainder
(#382, #772) and the benchmark's UI step on the Wealth chart. Sprint 12
touches every LiveView and `app.css` throughout. Two epic branches rewriting
the same files for a week is the conflict ADR-0026's "rebased onto `main` at
least daily" exists to avoid, and the benchmark overlay (Sprint 11 Lane B
step 4) lands on the chart Lane K re-composes around. So: Sprint 11's batch
opens next, Sprint 12's branch `agent/claude/ux-alignment-2` opens on the
commit that merges it. The one exception the owner may take by comment:
**Lane F alone** is small, file-local and conflict-free, and may open as its
own small PR ahead of Sprint 11 if the owner wants the docs screenshots and
the raw slug fixed now.

### D-2 — the recommended variant is the default pick (recommended)

Each pick issue lists its variants with the recommended one first, and the
review's Part 3 states the reason in one sentence. A comment naming another
letter on the issue or on PR #783 changes the pick; no comment by the time the
lane opens means the recommended variant ships. The story writes the pick
into `DESIGN.md` → Components, so the spine — not the issue — carries the
decision afterwards. This is "the merge is the signature" applied one level
down: the owner reads and comments to change, and nothing has to be edited
between silence and the build.

### D-3 — two batches, declared (recommended)

Sprint 12 takes Lanes F, N, S, K, P, T and D — twenty-two issues — with the
shrink order below. #806, #807, #808 and #798-B are named as Sprint 13
candidates now, so their absence from the closing act is a plan, not a
surprise, and the gate #807 needs (the owner's comment on Q2) can be taken
in the meantime.

### D-4 — the closing act's conditions are the review's conditions (recommended)

The design-critic and UAT walkthroughs of this and every later batch with
user-visible surface run in DE, at 390 px for one full pass, in light and
dark, on seed data that fires every alarm surface — the #706 conditions,
now with a script. **The review's seed script moves into `priv/demo/` as
`finding_surfaces_seed.exs` in this batch** so it is exercised on every
walkthrough and does not rot the way the Sprint 5 retro found the other two
seeds rotting; `review-rubric.md` names it. Screenshots go in a PR comment,
not the PR body (Sprint 10's finding).

### D-5 — the tag (standing)

`0.12.0`; the annotated tag command in the close-out for the owner to run
(ADR-0026 step 5 as amended by D-4 of Sprint 11).

## Sequencing

```
Sprint 11 batch ──▶ merge ──▶ agent/claude/ux-alignment-2 opens (D-1)
   (or Lane F alone as a small PR ahead, by owner comment)
Lane F ── first: #785 labels and #786 table are what N and T build on
Lane N ── after F (#789 adds the glyph; #787 independent)
Lane S ── independent of every pick; Tax + Snapshots UAT at the closing act
Lanes K ▶ P ▶ T ▶ D ── after the picks (D-2: silence = recommended), in that order
Lane M ── #781 at lane time; #782 closed with reason; report before the closing act
Lane Z ── registry rows when the branch opens; close-out reconciles
```

## Shrink order (cut from the bottom, name the cut in the briefing)

1. **Lane D** (#801, #804, #805) → Sprint 13.
2. **Lane T** (#803) → Sprint 13; #786 stays in F regardless.
3. **Lane K** (#797, #798) → Sprint 13.
4. **Lane P** (#799, #800) → Sprint 13; C1's phone half goes with it.

**Lanes F, N and S do not shrink.** A defect visible on the docs screenshots
and a rule four sprints old with no build behind it are the sprint not being
done; a batch that ships only F, N and S (fourteen issues) is still a
complete E11 pass.

## What is deliberately not in this sprint

- **#807 (C10 — realized gains as the Trades view):** `needs-decision`; the
  owner signs Q2 of the review by comment, Sprint 13 builds it.
- **#798-B (a KPI strip on the Overview):** a UX-DR2 change; built only if
  picked, in Lane K, with the rule amended in the same PR.
- **#806 (C9, the bucket cell) and #808 (C11, the classifications index):**
  low-traffic administration; Sprint 13 candidates.
- **Anything computed.** Every rule the review adds is about naming, control
  vocabulary, layout and state rendering; no metric, basis or predicate
  changes, and no lane carries the risk-tier attention label. The one
  optional field (#789's `stale`) is API + MCP together or not at all.
- **#608, #328, #333, #332, #330, #354, #573, #567, #314, #395:** unchanged
  from Sprint 11's list.

## What "done" means for this sprint

1. Every Lane F issue is closed by the merge; the enum-label meta-test and
   the second-person grep guard exist and are green; the docs screenshots no
   longer show "Ubersicht".
2. The Wealth data-quality list renders its findings as data notes with the
   remedy inside; a five-week-old quote is marked at all three call sites;
   every Cash-flow facet has its own subtitle and one basis line.
3. Tax, Snapshots and Views render their Component-Patterns shape; the
   sunburst and both income charts carry "Daten als Tabelle"; the income
   years are continuous and the matrix zeros are quiet.
4. The picked variants of K, P, T and D are built, and `DESIGN.md` names
   each pick — or the briefing names the lane as the shrink.
5. The closing act ran under D-4's conditions on the committed seed script,
   the walkthrough is in a PR comment with its shots, and `priv/demo/`
   carries `finding_surfaces_seed.exs`.
6. Lane M's report exists; #781 is applied as its own commit; #782 is closed
   with the LTS reason.
7. The `0.12.0` command is in the close-out for the owner to run.
