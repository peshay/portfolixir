---
layout: docs
title: Sprint Workflow
description: How a Portfolixir sprint runs — a planning PR, one sprint PR, the closing act and the close-out — with the reason for each rule.
---

# Sprint Workflow

This page holds the procedures behind `AGENTS.md` at the repository root,
which stays short because it loads into every agent session. Read the part
that applies when you reach it. Every rule names its reason (*Why*) and where
the reason is recorded. When a reason no longer holds, propose changing the
rule instead of following it blindly. Plans, retrospectives and the
close-out log (`sprint-status.yaml`) are in the repository's
`_bmad-output/implementation-artifacts/`.

**The shape, in one line:** a planning session writes the planning PR, the
owner merges it, a fresh implementation session builds the whole sprint as
one sprint PR, and the owner merges that. *Why:* two owner touchpoints per
sprint instead of five, and a fresh session tests whether the plan is
complete ([ADR-0026, amendment of 2026-10-08](../decisions/0026-epic-batch-workflow.html)).

## 1. Planning: the planning session and the planning PR

- **A decision gate comes before the build.** An ADR or spec with
  acceptance criteria is signed before the sprint that builds it.
  *Why:* blockers are cheap to resolve in a document and expensive as rework
  in code
  ([ADR-0026](../decisions/0026-epic-batch-workflow.html) step 1;
  E17–E19 retrospective §5).
- **A gate-closing ADR names its asks**, each answered or deferred with a
  reason, and a deferred ask is filed as an issue in the same pass.
  *Why:* one gate's half fell out between the gate and its ADR and survived
  the batch, the closing act and the close-out
  ([ADR-0043](../decisions/0043-a-gate-closing-adr-names-its-asks.html)).
- **The merge is the signature.** A planning PR is written as adopted, its
  status naming the PR whose merge adopts it, and opens ready for review.
  The owner merges to adopt or comments to change; a rejected decision is
  removed on the PR before the merge, never merged as "proposed".
  *Why:* a "draft, then edit the status, then merge" round trip was paperwork
  around a decision already made
  ([ADR-0026, amendment of 2026-09-07](../decisions/0026-epic-batch-workflow.html)).
- **The plan opens with "What you need to do"**: the asks only the owner can
  answer, which may be nothing but the merge. Every other choice is made in
  the plan with its reason and flips by a comment.
  *Why:* the owner's attention is the scarcest resource; a decision listed as
  a question costs a read even when silence adopts it
  ([ADR-0038](../decisions/0038-continuous-feedback-and-design-authority.html);
  ADR-0026, amendment of 2026-10-08).
- **The plan estimates the sprint PR's commit count.** Above 90, it cuts the
  sprint into a stack of PRs and says why.
  *Why:* GitHub refuses "Rebase and merge" beyond 100 commits, and `main`
  requires a linear history (ADR-0026, amendment of 2026-10-08).
- **A surface a decision places is mocked on the planning PR** (see
  [UI changes are mocked first](#ui-changes-are-mocked-first)).
- **After the merge, the planning session does the plan's registry
  bookkeeping** (closures by hand, relabels, filings) **and ends.**
  *Why:* the implementation runs in a fresh session; see below.

## 2. Implementation: one fresh session, one sprint PR

- **A fresh session executes the plan.** It reads the plan and the documents
  the plan names, and nothing from the planning session.
  *Why:* "once the spec is complete, start a fresh session to execute it" —
  a filling context degrades the work, and a gap the planning session carries
  in memory only shows in a session that does not
  ([Claude Code best practices](https://code.claude.com/docs/en/best-practices);
  ADR-0026, amendment of 2026-10-08).
- **One branch, one PR.** `agent/<provider>/sprint-<N>`, opened as a draft
  with its first commit. The plan's lanes are commit groups in the plan's
  order; one commit or a small commit group per issue; every commit passes
  the local gates.
  *Why:* a branch without a PR is invisible to the owner and CI does not run
  on it; per-issue commits keep `git bisect` and `git revert` at the issue
  ([ADR-0026](../decisions/0026-epic-batch-workflow.html) step 2 and the
  merge-method amendment).
- **The session orchestrates.** Each story goes to a subagent with a fresh
  context and a brief that names its base commit; the session reviews and
  commits the result. Its state lives in the plan and the PR's checklist.
  *Why:* the files survive a compaction and the conversation does not; agent
  worktrees start from `main`, not from the branch, and four Sprint 18 agents
  opened on the wrong base (Sprint 18 retrospective).
- **Read a gate's exit status directly**, never through a pipe.
  *Why:* three Sprint 19 commits carried stale gettext references because a
  failing check was piped into `tail` (Sprint 19 retrospective).
- **Rebase onto `main` before each closing act and before promotion.**
  *Why:* GitHub sends no event when `main` moves under an open PR (ADR-0026,
  amendment of 2026-10-08).
- **The Story Workflow applies to every story**: the nine test-first steps in
  [Story Workflow](story-workflow.html).

## 3. The closing act

- **Each risk class gets its closing act when its commit group is done**:
  at minimum a correctness hunter, an edge-case hunter and, for user-visible
  work, a design critic against the board and the living spec; a UAT persona
  walks the result on seeded synthetic data at the end.
  *Why:* PR #557 merged cleaner after a multi-role review than stacked small
  PRs did, and visual drift passed every review until a role looked for it
  ([ADR-0026](../decisions/0026-epic-batch-workflow.html) step 3;
  [ADR-0038](../decisions/0038-continuous-feedback-and-design-authority.html)).
- **A finding on a surface the PR already changes, small and with its answer
  in the spec, is fixed on the branch.** One off the PR's surface, or one
  that needs a choice, is filed. Nothing is withheld to make a count.
  *Why:* "confirmed findings fixed on the branch" is the closing act's
  point, and filing what the PR could fix grew the backlog by 51 in Sprint 18
  (Sprint 19 plan D-14).
- **The reviewer briefing** says what is new, what changed, where to look and
  which trade-offs are deliberate, with screenshots for UI work.
  *Why:* the owner reviews behavior against the briefing, not lines
  (ADR-0026 steps 3–4).

## 4. Promotion and merge

- **Promote the PR yourself once all four hold** — do not ask:
  1. the closing act has run and every confirmed finding is fixed;
  2. CI is green on the head commit, required checks included;
  3. every question put to the owner is answered;
  4. the branch is current with `main`, conflict-free, and you judge it
     mergeable.

  Leave one short comment saying what changed since the draft opened.
  *Why:* the four conditions are the owner's permission, so asking adds a
  round trip on a decision already made; a red required check once sat on
  `main` for a week unnoticed (E17–E19 retrospective §3). The comment's
  reason is inferred, not recorded: it saves the owner a diff read.
- **A question the work records** (an `OQ-n`, a named follow-up) **does not
  block promotion; a question put to the owner and unanswered does.**
  *Why:* blocking on recorded questions would mean never shipping a document
  honest about what it does not know.
- **Do not flip the status back and forth.** A red check after promotion is
  fixed on the branch; return to draft only when the work needs an owner
  decision, and say why on the PR. Ready for review is not a merge request.
  *Why (inferred, not recorded):* the status is the signal the owner reads;
  flapping turns it into noise.
- **History cleanup before promotion:** mechanical fix-ups fold into the
  commits that caused them; substantive review-round commits stay; the final
  tree is byte-identical to a backup ref; force-push only with
  `--force-with-lease`. A history rebuild proves every commit's invariants,
  not only the tip's.
  *Why:* `main` gets meaningful per-issue commits with unchanged content
  ([ADR-0026, merge-method amendment](../decisions/0026-epic-batch-workflow.html);
  Sprint 18 retrospective).
- **The owner merges** — a sprint PR by rebase-merge, a small single-concern
  PR by squash. **Agents never merge.**
  *Why:* the merge is the owner's acceptance (ADR-0026 step 4); squashing a
  sprint would make `git bisect` land on "the sprint" and break risk-tier
  revertability (merge-method amendment).

## 5. The close-out and the retrospective (inside the sprint PR)

The close-out records are the sprint PR's **last commits before
promotion**, written by the session that did the work. *Why:* everything
after the merge belonged to nobody — trackers outlived their children, the
status file went stale, retrospectives were skipped (E17–E19 retrospective
§3); the session that built the sprint remembers what went wrong (ADR-0026,
amendment of 2026-10-08).

- **Records:** `sprint-status.yaml` (the close-out entry and the
  retrospective), `epics.md`'s FR Coverage Map, Tracker Index and a dated
  reconciliation (never a story row), and any readiness summary the plan
  asks for. *Why:* the registry and the work ledger stopped competing under
  [ADR-0042](../decisions/0042-one-planning-structure.html).
- **Issues:** the ones the merge's keywords will close are named in the PR
  body; the ones a keyword cannot reach (invalidated work, trackers) are
  closed by hand with their reason.
- **Two-way coverage check:** an agent-only capability from an earlier
  sprint whose human view has not landed by the end of the next sprint is a
  finding recorded here. *Why:* it gives the coverage deadline in
  `AGENTS.md` a place to be enforced instead of a place to be intended
  (brief addendum, "API and MCP Coverage becomes symmetric").
- **Surface check:** when a read-ergonomics parameter lands
  (`include_positions`, `min_drift`, `fields=`, `since=`, or a successor),
  name every endpoint of its family and which of them carry it. *Why:* FR-37
  shipped on the portfolio scope and skipped the view scope the operator
  uses (#740; feedback triage of 2026-08-27, §0.3).
- **Maintenance lane.** Every sprint reviews available updates for Hex, npm,
  Elixir/OTP, PostgreSQL, BMAD and the external BMAD modules, applies what
  passes the gates as commits of their own, and reports what it deliberately
  did not update, with the reason (a `version-report-*` file). *Why:* BMAD
  went two months without an update because nobody owned the question, and a
  habit depends on someone remembering (feedback triage of 2026-08-12, Q1;
  [ADR-0036](../decisions/0036-risk-tier-rides-the-batch.html) item 1 for
  the separate commits).
- **After the merge:** the merge wakes the session; it confirms the merge's
  CI run on `main` and the calendar release the Release workflow made, and
  tells the owner in one line. The next planning PR records both in its
  verification basis. Every push to `main` that touches shipped code gets a
  `YYYY.M.N` release (annotated tag plus GitHub Release, one job; Sprint 17
  plan D-11); docs-only, test-only and planning pushes make none. If that
  job fails, the owner's fallback is an annotated tag the owner creates by
  hand, which still triggers the Release workflow's tag job. A release is a
  rollback point and a changelog, never an installable artifact.
  *Why:* `0.<sprint>.0` depended on a tag push the agent's credential cannot
  make
  ([ADR-0026, calendar-version amendment](../decisions/0026-epic-batch-workflow.html)).

## Owning a PR

A PR you open is yours until it is merged or closed.

- **Watch it from the moment it exists**, with the event subscription your
  tool provides (Claude Code: `subscribe_pr_activity`); never offer to watch
  and wait for a yes, and never poll with `sleep` or a timer. Unsubscribe
  when the PR is merged or closed, or when the owner says stop.
  *Why:* a session's own timer check-in disabled itself and the watch lapsed
  silently (Sprint 10 retrospective); an offer declined by silence leaves the
  PR unwatched.
- **Every CI failure gets a visible outcome**: a pushed fix, or one comment
  saying exactly what fails and why it is not fixed here. Keep going until
  the checks are green, then say so once. Skip silently only an event that
  echoes your own comment or duplicates one you handled.
  *Why (inferred, not recorded):* a silent event looks exactly like an
  unwatched PR.
- **Resolve conflicts and stale bases** by rebasing or merging `main` and
  re-running the gates; ask only when both sides changed the same logic and
  either choice loses behavior. *Why:* `main` requires a linear, current
  branch, and GitHub does not announce that `main` moved.
- **A failure that reproduces on the base branch is not silently yours:** say
  so once, port a fix that exists, and act when the base recovers. *Why:* an
  advisory published since the last push turns an audit gate red with nobody
  pushing, and a gate that is always red trains everyone to ignore red
  (Sprint 13 retrospective).
- **Never weaken a quality gate** — no lowered threshold, added ignore,
  skipped test or baselined finding. *Why:* the gates are the compensating
  controls that replaced the human read
  ([ADR-0026](../decisions/0026-epic-batch-workflow.html), "Compensating
  controls"; ADR-0036).
- **Never fix outside the PR's scope**; say so on the PR and file it.
  *Why:* every change stays reviewable against its decision (ADR-0022,
  Context).
- **Losing an approval by pushing a fix is an accepted cost.** *Why
  (inferred, not recorded):* a held fix keeps the PR red; an approval is
  given again in one click.

## UI changes are mocked first

Any story whose diff changes rendered output — a new surface, a layout, a
control, a state, a colour, a label's placement — gets a **mockup board
before the code**, including a one-rule CSS repair. *Why:* `DESIGN.md`
described the `.num` defect in words for two sprints and it shipped twice
anyway, because words about alignment do not show a reader two columns of
proportional digits (Sprint 14 plan D-10, D-11).

1. **Options, or a before/after.** A genuine choice shows at least two
   argued variants with one recommended; a conformance repair shows before
   and after.
2. **Before the code**: a surface a decision record places goes on the
   planning PR; one discovered mid-sprint is boarded before its story.
3. **The recommendation is the default**; a comment naming another option
   changes it; silence adopts it. The story that builds it writes the
   anatomy into `DESIGN.md`, so spec and screen do not drift apart.
4. **A board** is an HTML artboard under
   `_bmad-output/planning-artifacts/design-language/mockups/<pass>/` that
   links the real `priv/static/app.css`, rendered to PNG, with synthetic data
   only. *Why:* it shows the shipped tokens, not an approximation; PNG is what
   a PR comment renders (inferred).
5. **The exception:** a change with no rendered difference — an ARIA
   attribute that was absent and is now correct, a test-only change. "Too
   small to draw" is not the exception; "identical picture" is.

The design critic reviews the built surface against its board; a UI change
that landed without one is a close-out finding.

## Risk-tier attention

Ledger and money math, import idempotency, projection semantics,
security-relevant changes and dependency updates ride the sprint like
everything else, and get:

1. their own commit or commit group, independently readable and revertable;
2. a dedicated verification pass on the invariant at stake;
3. an explicit callout in the briefing: what changed, which invariant
   protects it, which test pins it;
4. the decision gate unchanged: semantics-changing risk-tier work needs its
   ADR signed before the sprint.

*Why:* with one reviewer, separate risk-tier PRs became a queue of unread
micro-PRs, and a silent money or idempotency error is invisible in a
walkthrough
([ADR-0036](../decisions/0036-risk-tier-rides-the-batch.html)). TDD with
exact `Decimal` expectations and every gate green are blocking, not
aspirational.

## Issues and the registry

- **Issues are thin pointers**: a title, a one-paragraph scope, links to the
  authoritative ADR or `epics.md` section, and dependencies. Acceptance
  criteria are never copied in. *Why:* copies drift
  ([ADR-0042](../decisions/0042-one-planning-structure.html)).
- **What owns what:** `epics.md` is the requirement registry (inventory, FR
  Coverage Map, Tracker Index, dated reconciliations); the GitHub tracker set
  is the work ledger; `sprint-status.yaml` is the close-out and
  retrospective log; the sprint plan is the execution artifact. *Why:* two
  structures claiming the same job drifted apart (ADR-0042).
- **Filing an issue is bookkeeping, not communication.** What the owner needs
  to know goes in an ADR, a triage document, the plan or the briefing. A
  third party's report is triaged into the next triage document or plan.
  *Why:* the owner does not read the tracker, and a channel that ends in an
  unread place is a defect (ADR-0042, "Who reads what").
- **One topic = one issue.** The issue plus the artifacts it points at are
  the complete specification; a session must not need context from earlier
  sessions. New ideas found while working are filed immediately, with their
  area tracker as parent (#416–#420), after searching the open titles. *Why:*
  a session's memory ends with it; an issue does not (#321's working
  agreement; Sprint 19 retrospective for the parent and the title search).
- **A `needs-decision` issue carries its recommended answer** and what would
  reopen it if closed. *Why:* the next decision pass is then a table, not
  research (Sprint 20 plan D-4).
- **Name the issues the diff closes with a GitHub closing keyword** and a real
  number — `Closes #675` — so the merge closes them. If the diff closes
  nothing, say so in one clause and why. An issue the diff invalidates rather
  than implements is closed by hand with the evidence; a keyword is only for
  issues this diff finishes. Before opening, ask whether the diff finishes
  something already on the backlog (an ADR or a docs change often does).
  *Why:* issues and trackers stayed open after their PRs merged, and a
  keyword on invalidated work would record "done" for work that never
  existed (E17–E19 retrospective §3).
- **Labels:** `agentic` = implementable autonomously, merged by the owner;
  `needs-uat` = needs the owner's check on real data; `needs-decision` =
  waits for an answer; `tracking` = a tracker with no PR of its own.

## Tool notes

- **Claude Code** reads `AGENTS.md` directly from v2.1.277 on, and only
  while no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` exists in
  the working directory or above it; a personal `~/.claude/CLAUDE.md` does
  not count. An interactive session confirms it with "no CLAUDE.md found;
  AGENTS.md loaded", and `/context` lists the file. An older version reads
  nothing from the repository: update it. Its PR tools:
  `subscribe_pr_activity` and `unsubscribe_pr_activity` for the watch;
  `update_pull_request` with `draft: false` to promote.
- **Codex** reads `AGENTS.md` directly and stops at 32 KiB. *Why this
  matters:* `AGENTS.md` once grew past that, and Codex never saw its
  security and authorship sections; keep it short.
