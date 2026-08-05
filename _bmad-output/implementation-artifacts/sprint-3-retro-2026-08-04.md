# Sprint 3 Retrospective — 2026-08-04

Part of the ADR-0026 step 5 close-out for PR #631 (merge `1903913`).
Scope: `#569`, `#620`, `#577`, `#563`, `#606`, `#619`, ADR-0034 through
ADR-0037, plus the dependency and CI work that attached itself along the way.

## What shipped against what was planned

`sprint-plan-2026-08-01.md` committed to Lane A (`#606`) plus `#569` and
`#620`, with `#577` "next in the review queue if capacity allows" and `#568`'s
design session as a no-review-cost extra. Everything on that list shipped, and
so did `#563`, `#619`, a framework upgrade and two dependency sweeps that were
not in the plan at all.

The plan's central assumption — that review capacity is the constraint and
three risk-tier PRs cannot pass one reviewer in parallel — turned out to be
correct in a way the plan did not anticipate: the answer was not to serialize
the queue but to stop generating it (ADR-0036).

## What worked

- **The agentic review earned its place.** Six independent verifying reviewers
  across two rounds produced one real **Blocker** (an empty blast radius never
  bumped the `:global` view-cache scope, so an FX write could leave a stale
  cross-portfolio series being served as current) and several confirmed
  should-fixes. None of these would have surfaced in a behaviour walkthrough.
  This is the evidence ADR-0036 leans on when it makes the mechanical controls
  the substitute for a human read.
- **Verification, not inspection.** The risk-tier pass on ADR-0035 did not
  read for plausibility: it probed FX equivalence line by line against a live
  database, compared batched and per-row split-adjusted quotes for securities
  with one split, two splits and none, and re-measured the pricing context's
  query count by telemetry (34, against 35 claimed). That is why "no
  correctness defect found" is worth something here.
- **Decisions before code held.** ADR-0033 was accepted before `#569` was
  written and ADR-0035 before `#619`; both implementations landed without a
  design argument mid-flight. The one place a decision was written *after* the
  investigation (ADR-0037) was a security upgrade with no design freedom.
- **The measurement was A/B on one machine, not a comparison to an old
  report.** It also states plainly where the win is small (the cold mount
  improves 9 %). A report that only contains good news is not a measurement.

## What went wrong, and what it costs

- **The Phoenix migration was overestimated by roughly everything.** It was
  described to the owner as "a framework migration across every LiveView, its
  own project with its own gate", and then changed **zero** lines of
  application code. Five minutes of grepping for the LiveView 1.x breaking
  patterns would have produced the right answer before the estimate. The cost
  was not wasted work but a wrong decision input: the owner was told a HIGH
  advisory would be expensive to close when it was nearly free, and could
  reasonably have deferred it on that basis.
- **A gate was assumed to exist because CI was green.** `mix hex.audit` runs
  pinned to Hex 2.4.1 (deliberately — 2.5's advisory gating has no ignore
  mechanism) and `mix deps.audit`'s database did not carry the EEF advisories,
  so **15 advisories including 5 HIGH sat on `main` behind two green audit
  steps**. Separately, AGENTS.md had required `npm test` / `npm run build` for
  the MCP companion since the beginning; CI never ran either. Both were found
  by accident, not by a control. **Green is evidence that a gate passed, not
  evidence that it exists.**
- **Closing that hole opened another one.** The `npm ci` step added to run the
  MCP gates omitted `--ignore-scripts`, which SonarCloud correctly flagged as
  arbitrary code execution at install time. The step added to make the build
  safer made it less safe for two commits.
- **Two speculative CI fixes were pushed before the finding was known.**
  SonarCloud is unreachable from the build container (network policy, 403),
  and rather than saying so immediately, a hypothesis was pushed, disproved,
  and a second one prepared. The owner then read the dashboard in seconds. The
  rule for next time: when the diagnostic is behind a wall the agent cannot
  cross, ask on the first failure, not the second.
- **A subagent's scratch file was swept into a commit.** A read-only reviewer
  wrote a probe test into the shared working tree while a `git add -A` ran,
  and it landed in an unrelated commit. It was caught and, being genuinely
  good coverage, promoted deliberately — but `git add -A` while background
  agents share the tree is a loaded gun.

## Actions

1. **Close the advisory-gate gap** (ADR-0036 names it as the first follow-up
   it owes). Blocked only by tooling now: `hex.audit` sees advisories but
   cannot ignore, `deps.audit` can ignore but does not see them. A visible
   non-blocking step is available today; a blocking one needs one of the two
   to grow the missing half. **Owner decision.**
2. **Harden `mcp-server/Dockerfile:10`** — it runs the same bare `npm ci` that
   was just fixed in CI.
3. **Make the browser smoke check a gate.** ADR-0037's Chromium session is
   currently a manual acceptance step; as a CI job it would also close the
   never-booted-server blind spot a reviewer flagged for the cowboy upgrade.
4. **Never `git add -A` while background agents write to the tree.** Stage
   explicit paths.
5. **Apply or reject the structural proposal** from the 2026-07-31
   reconciliation. 17 issues were attached to trackers this sprint, but the
   two-structures decision itself is untouched and is now the oldest open
   standing finding.

## Standing findings — status

1. *Planning artifacts drift silently.* The same-pass close-out has now held
   across a full multi-PR sprint, which was the stated test. **Countermeasure
   holds**; keep it in the closing act.
2. *An issue's state lags its PR.* No instance; the six issues were closed in
   the same pass as this document.
3. *Two parallel epic structures.* Partly reduced (17 attachments), decision
   still open. **Carried.**
4. **New:** *A quality gate can be documented, green, and absent at the same
   time.* Two instances this sprint. Carried until an inventory confirms every
   gate AGENTS.md claims actually runs.
