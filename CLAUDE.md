# CLAUDE.md

Guidance for Claude Code (and any agent that reads this file) when working in
this repository.

The canonical, tool-agnostic rules live in @AGENTS.md — read and follow them as
the single source of truth. This file only restates the rules that must never
be worked around.

## Non-negotiable: no personal or private data in the repo

This repository is public. Never commit the maintainer's (or anyone's) real
financial data (balances, net worth, positions, performance figures, credit
lines), names of household members or pets, personal banking/broker details,
local machine paths or usernames, or personal agent state
(`_bmad/config.user.toml`, `_bmad/memory/**`). Agent-generated artifacts
(BMAD sessions, decision logs, design notes) must be scrubbed before they are
committed. See "Privacy And Disclosure" in AGENTS.md for the full rule.

## Non-negotiable: commit authorship

Every commit is authored by an accountable human under their own GitHub identity,
even when the change was produced with an LLM or coding agent. The agent is a
tool; a person owns the result.

- Commit under the human's own `user.name` / `user.email` (a GitHub-verified
  address, e.g. `name@users.noreply.github.com`).
- Never commit under a bot/agent identity (e.g. `Claude`, `Codex`, `OpenClaw`).
- Never add a `Co-authored-by:` line that credits an AI agent, and never add
  `Model:`, `Thinking level:`, `Claude-Session:`, or `claude.ai/code/session`
  footers. Put model/reasoning notes in the PR description instead.

This is enforced by a `commit-msg` hook (`scripts/check-commit-authorship.sh`)
and the "Commit authorship" CI workflow, checked against
`.github/commit-authorship-allowlist.txt`. See "Commit Authorship And
Accountability" in AGENTS.md for the full policy.

## Non-negotiable: a pull request you opened is yours until it is merged

AGENTS.md ("Branch Naming For Agent Work") states the duty; this is how to
discharge it in Claude Code, and it is not conditional on being asked.

- **Subscribe as soon as the PR exists.** Call `subscribe_pr_activity` with the
  owner, repo and PR number right after opening it. Do not offer to watch and
  wait for a yes — the offer is the failure mode, because a declined-by-silence
  offer leaves the PR unwatched.
- **Then end the turn.** Events arrive as `<github-webhook-activity>` messages
  that wake the session. Never poll with `sleep`, a timer, or repeated status
  checks.
- **On a CI-failure event, produce a visible outcome every time:** a pushed fix,
  or a reply saying exactly what is failing and why it is not being fixed. There
  is no third option, and one round is not the task — keep going until the
  checks are green, then say so once.
- **Skip silently only two things:** an event echoing your own comment, and an
  event duplicating one you already handled.
- **Promote the draft yourself** once the four conditions in AGENTS.md hold
  (reviews clean, CI green on the head commit, owner questions answered, branch
  current and judged mergeable): `update_pull_request` with `draft: false`, plus
  one short comment saying what changed since the draft was opened. Do not wait
  to be asked, and do not ask permission — the conditions *are* the permission.
  Recorded open questions in the deliverable (an `OQ-n`, a named follow-up) do
  not block promotion; a question you put to the owner and have not had answered
  does.
- **Unsubscribe** when the PR is merged or closed, or the moment the owner asks
  you to stop.

The limits in AGENTS.md bind here without exception: never weaken a gate to get
green, never fix outside the PR's scope, never merge. Losing an approval by
pushing a fix is an accepted cost, not a reason to hold one back.
