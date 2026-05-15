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

Run the required gates before review:

```bash
mix format
mix test
mix coveralls
pre-commit run --all-files
npm test --prefix mcp-server
npm run build --prefix mcp-server
```

Review user-facing documentation for every story. Update docs when the story
changes routes, screens, labels, setup, API/MCP usage, or visible behavior. For
background-only work, record that user documentation was reviewed and no update
was needed.
