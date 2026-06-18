---
description: Verified, Portfolixir-specific review of the current diff — surfaces only confirmed findings
---

You are running the Portfolixir quality gate: a **verified** semantic review of a
change set, tuned to this project's load-bearing invariants. The maintainer does
not read code in detail, so your job is to catch wrong details that CI cannot —
and to surface **only confirmed, decision-worthy** findings, never raw suspicions.

Read and apply the rubric at `docs/development/pr-review-checklist.md` in full.

## What to review

- If an argument is given (a PR number or a base ref), review that. Otherwise
  review the diff of the current branch against `origin/main`
  (`git diff origin/main...HEAD`).
- Also read the PR body / commit messages if available, and check the PR Quality
  Checklist claims against what the diff actually shows.

## Protocol (do not skip the verification step)

1. **Review** the diff against every section (A–F) of the rubric.
2. **Verify** each candidate finding against the actual code, tests, and the
   relevant ADR under `docs/decisions/` before reporting it. Drop anything that
   turns out to be intentional or documented. Spawn parallel sub-agents for
   independent verification when the diff is large.
3. **Report** only what survives, grouped as **Blocker / Should-fix / Note**.
   Each item: `file:line` — rule broken — one-line recommended decision.
4. If nothing survives verification, say "No confirmed findings" and stop. That
   is a valid, valuable result — do not invent work.

## Output

Lead with a one-line verdict (`✅ clean` / `⚠️ N should-fix` / `🔴 N blockers`).
Keep it tight: conclusions and `file:line`, not code dumps. The maintainer should
be able to decide each item in seconds.

Do **not** modify code as part of this review unless explicitly asked to fix.
