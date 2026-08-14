# Sprint 6 Retrospective — four lanes in one batch (2026-08-14)

**Status: written at PR time (#688 ready for review).** The close-out
section at the end is filled in after the owner's squash-merge, following
the Sprint 5 precedent.

## What shipped

One batch on one branch, one PR (#688), 46 commits, per the adopted plan
(sprint-plan-2026-08-12-sprint6.md, amended 2026-08-14 with Lane D):

- **Z — release/instrumentation:** #682 local test-run capture with seed
  (`scripts/capture-test-run.sh`). The v0.5.0 tag push stayed blocked from
  the session (git proxy allows only the designated branch) and is an owner
  action with a prepared command.
- **B + D — agent surface:** #664 verified (no regression; preservation of
  notes/attributes now test-pinned), FR-37 sparse fieldsets and roll-ups
  with a durably-tested ≥70 % volume cut (#665), FR-38 `?since=` delta
  reads, pull-only with the B3.7 boundary pinned (#666), activity-aware tax
  staleness with its computation basis in every payload (#667), and
  `tax_refund` discoverability on every agent surface (#686 D1–D4).
- **C — durable derived values (ADR-0039 C1–C5, risk-tier):** one
  mechanism with a lifetime per analytic, §5 invariants as blocking tests
  before activation, the daily performance walk activated `:durable`,
  freshness in every payload, and `mix portfolixir.derived.rebuild` with a
  measured runtime.
- **A — UI design-language debt, all twelve issues:** #651 #561 #668 #669
  #670 #671 #673 #412 #491 #564 #565 #566.
- **M — maintenance:** postgrex 0.22.4 and phoenix_live_view 1.2.9 (CVE
  fixes), phoenix 1.8.11, sobelow 0.15.0, gettext 1.0.2, mcp-server dev
  deps; BMAD 6.8→6.11 pinned (#674); Dependabot config and the version
  report with the deliberately-held-back list (#676).

Gates at PR time: 1855 tests / 0 failures, Dialyzer zero, Credo strict
clean, coverage 90.5 %, pre-commit green, MCP 67 tests + build green.

## Agentic review closing act — what it caught

Six roles ran (correctness/Decimal + risk-tier verification, journal/scope,
API-MCP parity, TDD/docs, design critic, edge-case hunter + UAT persona).
Every confirmed finding was fixed on the branch before promotion:

1. **The delta-read contract lost rows two ways.** `as_of` was stamped at
   render time (a row committed between query and stamp vanished forever
   under the strictly-after cut), and second-precision `updated_at` made a
   row committed inside the stamp's own second equal to `as_of` — same
   loss. Both found by different roles; fixed with a parse-time stamp
   backdated one second: overlap over loss, test-pinned.
2. **A claimed invariant was unpinned.** ADR-0039's
   version-captured-before-compute race safety existed in the moduledoc and
   nowhere else; a refactor reading the version after compute would have
   passed the whole suite. Now a blocking test that bumps the version from
   inside the compute closure.
3. **The URL-as-source-of-truth work had one unguarded param.** `?q[]=foo`
   crashed the securities view on every remount of a shared link — the
   crash was permanent for that URL, which is exactly what #651 made
   shareable. Guarded like every other param.
4. **An "alignment" commit aligned onto the deviating build.** #669 moved
   the period controls onto `.segmented-control__option`, whose active
   state contradicted the spec's own anatomy (no accent fill, weight change
   without width reserve). The spec named that class as a call site the
   canonical component must absorb — not the other way round. Fixed in the
   class, stylesheet-test-pinned.
5. **Docs drift inside the same batch.** The product documentation still
   described pre-#667 staleness semantics in both languages while the same
   PR shipped the new behavior.

## Process lessons

1. **Worktree-committed state is the recovery unit.** A session restart
   killed all four lane subagents mid-flight; every completed commit in
   their worktrees survived and the batch was reassembled by cherry-pick.
   Losing the agents cost orchestration time, not work. Corollary: lane
   agents committing early and often is what made the recovery cheap.
2. **Capacity limits are a scheduling fact, not an anomaly.** The Lane A
   finisher died on the session usage limit and completed cleanly after the
   reset window. Plan lane sizing so a lane can be resumed, not restarted.
3. **Exit codes must be read raw.** Two avoidable red CI rounds came from
   piping gate output through `tail`/`grep`, which masks the exit code —
   a 43-failure run initially read as green locally. All later gate runs
   captured real exit codes; the habit belongs in every orchestration
   prompt.
4. **Dialyzer belongs in the local gate list.** It runs in CI's quality job
   but is absent from the AGENTS.md local-check list, so a
   `pattern_match_cov` finding was discovered by CI instead of locally.
   Follow-up: add `mix dialyzer` to the required local checks.
5. **gettext catalogs do not union-merge.** The `merge=union` driver used
   to survive repeated cherry-pick conflicts corrupted the catalog once
   (dropped `msgstr`, glued references) and silently lost translations
   twice; `mix gettext.extract --merge` plus a translation pass after every
   lane merge was the reliable sequence.
6. **The UAT live-server walkthrough is fragile in this environment.** It
   stalled and produced no screenshots; the LiveViewTest-level fallback
   still surfaced a real user-visible defect (the `?q[]=` crash). The
   briefing states the screenshot gap explicitly rather than hiding it.
7. **One flaky-burst observation, no seed.** A 43-failure burst did not
   reproduce on re-run; it predates the #682 instrumentation being active
   locally, so no seed was captured — the instrumentation shipped in this
   very sprint exists for the next occurrence.

## Recorded follow-ups (not fixed in this batch)

Sprint 7 UI close: inline-result placement for detail-pane actions, styled
select indicator, needs-attention basis-line typography, reduced-motion
gate on the disclosure chevron, spacing tokens in `.inline-result`, wealth
data-quality rows and the tax staleness badge as data-notes. Backlog: MCP
logo tools (four `/logo*` routes uncovered, pre-existing), #670 cash as-of
date not in the API payload, invalidation-rollback atomicity pinned by AST
check only, tax staleness counting future-dated bookings (conservative),
FR-37/38 human view due by the next batch per the two-way rule.

## Close-out (filled in after the merge)

Merged 2026-08-14 as the **first rebase-merge under the ADR-0026
merge-method amendment** — an owner decision taken on this very PR, so the
sprint that argued for per-issue revertability also delivered it: 41
per-issue commits on `main` (agent-cleaned from 47; mechanical fix-ups
folded into their sources, review-round commits kept, tree byte-identical,
verified by empty diff before the force-push).

- **Merge CI:** Commit-authorship green across all 41 rebased commits; the
  CI workflow on `main` at `f0beb8c` confirmed green in this pass; the new
  Dependabot config ran its first scans on the same push.
- **Issues:** all twenty closing-keyword targets closed by the merge
  (spot-verified via the API — closing keywords work identically under
  rebase-merge).
- **Bookkeeping:** sprint-status.yaml close-out entry written; epics.md FR
  Coverage Map reconciled — FR-37/38 shipped (agent-only, human view due
  next batch per the two-way rule), FR-39/40 issue-ready now that the
  ADR-0039 mechanism landed; UX-DR row shows #414 and #560 as the Sprint 7
  remainder.
- **Tags (owner action, both blocked from agent sessions):**
  `git tag -a v0.5.0 73affc5 -m "Sprint 5: design-language alignment batch" && git push origin v0.5.0`
  and
  `git tag -a v0.6.0 f0beb8c -m "Sprint 6: agent surface, durable derived values, UI alignment" && git push origin v0.6.0`.
  The v0.6.0 push is the first real exercise of the #659 release workflow
  on a sprint boundary.

**Retro addendum from the merge itself:** the rebase-merge decision came
out of the owner reading the PR — the squash default had survived two
sprints unquestioned because nobody owned the question. Lesson: merge
method is a reviewable decision per PR shape, not repo tradition; it is now
written where the workflow lives (ADR-0026, AGENTS.md step 4).
