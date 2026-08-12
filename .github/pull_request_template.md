## Story

- Closes #<issue> — a real GitHub number and a closing keyword, so the merge
  closes it. Repeat the line per issue. If this diff closes nothing, say so and
  why. An issue this diff *invalidates* rather than implements is closed by hand
  with the reason, never by a keyword (see AGENTS.md).
- Agent branch (if applicable): `agent/<provider>/<topic-slug>` or `codex/<topic-slug>` (legacy).

## Summary

- [What changed in one short bullet list]

## User Story Evidence

### Story text and acceptance criteria

- ...

### User story test evidence

- Test file:
- Test name:
- [ ] New test added before implementation
- [ ] Test failed for the expected reason first

### Security audit evidence

- Security surface touched:
- Threats identified and mitigations:

### API and MCP evidence

- API coverage added or reviewed:
- MCP coverage added or reviewed:
- Why API/MCP coverage is not applicable (if true):

## Implementation

- Main approach:
- Files changed:
- Validation of constraints (scope and rule checks):

## Tests and Gates

- `mix format`:
- `mix test`:
- `mix coveralls` (if applicable):
- `pre-commit run --all-files`:
- `npm test --prefix mcp-server` (if applicable):
- `npm run build --prefix mcp-server` (if applicable):

```bash
mix format
mix test
mix coveralls
pre-commit run --all-files
npm test --prefix mcp-server
npm run build --prefix mcp-server
```

## Documentation

- Docs reviewed:
- Docs changed:
- Why no doc change is acceptable (if true):

## PR Quality Checklist

- [ ] User story is written as a comment in the relevant test file.
- [ ] Functional test sits directly below the user story comment.
- [ ] Tests were written first and validated as failing-first.
- [ ] API coverage was reviewed and updated, or marked not applicable.
- [ ] MCP coverage was reviewed and updated, or marked not applicable.
- [ ] Security audit was run before finalizing changes.
- [ ] Required gates were run and passed.
- [ ] User documentation reviewed for consistency.
- [ ] User documentation was updated, or this PR explains why no user docs changed.
- [ ] No real financial data was added.
- [ ] No live network calls are used in tests.
- [ ] Financial values use Decimal where relevant.
- [ ] No external input is converted with `String.to_atom/1`.
- [ ] No import, trading, payment, order, rebalance, or LLM behavior was added.
- [ ] Story scope stayed inside the request.
