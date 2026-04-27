# Prompt for ChatGPT 5.3 Codex Spark — Review

You are reviewing Portfolixir after recent story implementations.

Read:

- AGENTS.md
- docs/process/tdd-policy.md
- docs/product/initial-user-stories.md

Task:
Review the latest changes for:

- scope creep
- missing tests
- financial values accidentally using floats
- external input being converted to atoms
- live network calls in tests
- real financial data in fixtures
- architecture drift from the selected contexts

Do not add features.

If you make fixes:

- write or update tests first
- run tests
- summarize every change

Commands:

```bash
mix format
mix test
```

Final response:

- risks found
- fixes made
- commands run
- follow-up issues
