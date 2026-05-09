## Story

Closes PFX-...

## What changed

-
-
-

## Tests

Commands run:

```bash
mix format
mix test
pre-commit run --all-files
```

## Documentation

User documentation reviewed/updated:

-

## Checklist

- [ ] User story is written as a comment in the relevant test file.
- [ ] Functional test sits directly below the user story comment.
- [ ] Tests were written first.
- [ ] New or changed test failed for the expected reason before implementation.
- [ ] User documentation was reviewed for consistency.
- [ ] User documentation was updated, or this PR explains why no user docs changed.
- [ ] No real financial data was added.
- [ ] No live network calls are used in tests.
- [ ] Financial values use Decimal where relevant.
- [ ] No external input is converted with `String.to_atom/1`.
- [ ] Story scope was not exceeded.
- [ ] No import, sync, trading, payment, order, rebalance, MCP, or LLM behavior was added.
