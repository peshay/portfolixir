# Prompt for ChatGPT 5.3 Codex Spark — One Story

You are working on Portfolixir.

Read first:

- AGENTS.md
- CONTRIBUTING.md
- docs/process/tdd-policy.md
- docs/process/definition-of-done.md
- docs/product/initial-user-stories.md

Work on exactly one story:

```text
[PASTE STORY ID AND TEXT HERE]
```

Rules:

- Follow TDD strictly.
- Write failing tests first.
- Run the tests and show the failure.
- Implement the smallest possible change.
- Run tests again and show success.
- Do not implement adjacent stories.
- Do not refactor unrelated code.
- Do not make live network calls.
- Do not add real financial data.
- Do not use floats for financial values.
- Do not use `String.to_atom/1` on external input.

Quality gate:

```bash
mix format
mix test
```

If additional tools are configured, also run:

```bash
mix coveralls
mix credo --strict
```

Final response:

- Story completed
- Acceptance criteria covered
- Tests added
- Commands run
- Files changed
- Follow-up story suggestions, if any
