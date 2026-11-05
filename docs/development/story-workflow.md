---
layout: docs
title: Story Workflow
description: Test-first story workflow for Portfolixir contributors.
---

# Story Workflow

Portfolixir changes are developed as small, reviewed stories. Keep story scope
narrow so code, tests, translations, API contracts, MCP tools, and user
documentation stay consistent.

For every user-visible story, use this order:

1. User Story documented.
2. Functional test written directly below the User Story comment.
3. Test failure confirmed for the expected reason.
4. Smallest implementation code written.
5. API coverage reviewed and updated, or explicitly marked not applicable.
6. MCP coverage reviewed and updated, or explicitly marked not applicable.
7. User documentation reviewed and updated when visible behavior changed.
8. Security audit performed.
9. Required gates run.

Every user-visible change updates user documentation when behavior changes.
Visible copy stays English-first in code and must include German gettext
translations.

The story comment belongs in the relevant test file immediately above the
functional test:

```elixir
# User story:
# As a local portfolio maintainer,
# I want to record a manual buy transaction,
# so that my holdings are derived from auditable local data.
#
# Acceptance criteria:
# - The transaction is stored with Decimal values.
# - The holdings view includes the bought quantity.
test "records a manual buy transaction and updates holdings" do
  ...
end
```

The first run of the new or changed test must fail for the expected reason. The
implementation should then make the smallest change that fulfills the story and
acceptance criteria.

API and MCP coverage is part of the story contract. When a visible function is
added or changed, update `/api/v1` and `mcp-server/` tests and behavior in the
same story, or document why that surface is not applicable.

## What a story's own tests do not cover

Four rules for the story's own run, before the orchestrating session
integrates it. Each comes from a defect that reached integration or the
closing act in Sprint 24 although every story test was green (Sprint 24
retrospective, carry-forwards 1 to 4).

- **Run `test/invariants` beside the story's own tests.** *Why:* the
  invariants are app-wide rules no single story's tests restate; a story
  that built a native date input passed its own tests and turned the suite
  red at integration on two invariants (J3).
- **A story that changes what a writer stores searches the whole suite for
  the shape it changes**, `test/portfolixir/seeded_upgrade/` included, and
  runs every test it finds. *Why:* a test far from the writer still
  expected the old shape, and only the orchestrator's full run found it
  (J1).
- **A screen story's test drives the field as the operator does**: a half
  value, Enter, a resize across a breakpoint, a link handed over. A figure
  on the screen is compared with the API answer for the same request, its
  period stated. *Why:* tests that pinned what was rendered passed while
  the screen failed under use; one compared the screen with an API call
  over a different period and passed only because the fixture's figures
  were recent (B2, J3).
- **A gate a story adds gets an attack case in its self-test**: an input
  the gate must refuse, seen refused. *Why:* a schema-budget rule added in
  Sprint 24 measured only the last row and never asked whether a named tool
  was new; it checked less than it said until the closing act gave it an
  attack case (D1).

Run the required gates before review: the full list in `AGENTS.md` at the
repository root ("Required Local Checks"). It is CI's `pre-commit`, `test`,
`quality`, `advisories` and `browser` jobs, so a branch that passes it passes CI. The six-command copy
this page carried omitted eight of CI's checks, and a batch that skipped two
of them cost a round (Sprint 13 retrospective).

Review user-facing documentation for every story. Update docs when the story
changes routes, screens, labels, setup, API/MCP usage, or visible behavior. For
background-only work, record that user documentation was reviewed and no update
was needed.
