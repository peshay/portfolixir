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
