## Story

Closes PFX-...

## What changed

-
-
-

## Tests

Story comment evidence:

-

Test-first evidence:

-

Gates run:

```bash
mix format
mix test
mix coveralls
pre-commit run --all-files
```

## Documentation

Docs review/update note:

-

## Checklist

- [ ] User story is written as a comment in the relevant test file.
- [ ] Functional test sits directly below the user story comment.
- [ ] Tests were written first.
- [ ] New or changed test failed for the expected reason before implementation.
- [ ] User documentation was reviewed for consistency.
- [ ] User documentation was updated, or this PR explains why no user docs changed.
- [ ] English-first visible copy has German gettext translations where applicable.
- [ ] `mix coveralls` was run.
- [ ] No real financial data was added.
- [ ] No live network calls are used in tests.
- [ ] Financial values use Decimal where relevant.
- [ ] No external input is converted with `String.to_atom/1`.
- [ ] Story scope was not exceeded.
- [ ] No import, sync, trading, payment, order, rebalance, MCP, or LLM behavior was added.
