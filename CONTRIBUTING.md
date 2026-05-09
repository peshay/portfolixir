# Contributing to Portfolixir

Portfolixir is built story-by-story with tests first. Keep each change small, repo-facing,
and aligned with the current MVP path: securities, portfolio/depot and cash-account setup,
manual buy/sell entry, then quote and chart read surfaces.

## Local setup

### Docker workflow

The simplest local workflow uses Docker Compose:

```bash
docker compose up --build
```

The app container runs `mix phx.server`, connects to the Compose PostgreSQL service,
and exposes Phoenix on the configured local port. Stop the stack and remove local volumes with:

```bash
docker compose down -v
```

### Host Phoenix workflow

If you run Phoenix directly on the host, install Elixir/Erlang and PostgreSQL, then run:

```bash
mix deps.get
mix ecto.setup
mix phx.server
```

Use the Docker workflow when you want the repository defaults for database host, user, and password.

## Development workflow

1. Pick one user story.
2. Confirm the user-visible problem, expected behavior, affected route or surface, severity,
   acceptance criteria, and non-goals.
3. Write acceptance tests first.
4. Implement the smallest possible change.
5. Run the required local checks.
6. Run public artifact guard checks.
7. Open a PR with a short story summary and commands run.

## Required local checks

Run these before opening a PR:

```bash
mix format
mix test
pre-commit run --all-files
```

If pre-commit is not installed, install it once:

```bash
pre-commit install --install-hooks
```

The CI test job runs the same formatting and test expectations with `mix format --check-formatted`,
database setup, `MIX_ENV=test mix test`, and a coverage-floor check.

## Optional heavy checks

Run these when the touched area is risky or a reviewer asks for them:

```bash
mix coveralls
mix credo --strict
mix dialyzer
mix sobelow
mix deps.audit
```

These are not mandatory for every local contribution unless the story or review explicitly
requires them.
Do not add or configure a missing heavy tool as drive-by work.

## Public artifact guard

This repository enforces a local and CI guard for GitHub-visible text artifacts.

```bash
pre-commit run --all-files
```

Replacement command if pre-commit is unavailable:

```bash
python3 scripts/public_artifact_guard.py $(git ls-files)
```

If the guard fails:

1. Remove internal paths/metadata, leaked prompt/process text, or obvious secrets from the flagged
   files.
2. Replace literal escaped backslash-n sequences with real line breaks in public-facing text,
   templates, or scripts.
3. Rerun the guard until it passes.

## Public commit and merge metadata

GitHub-visible commit and merge metadata must stay repo-facing. Before opening or merging a PR:

- Use public-safe author and co-author identities. Do not use local-only email domains.
- Keep commit bodies and merge messages to the story summary, constraints respected, tests run,
  and follow-up tasks.
- Do not include private agent identity, model/runtime identifiers, hostnames, workspace paths,
  prompt/process text, or board-only metadata in commit messages, merge messages, PR bodies,
  or release notes.
- If GitHub suggests a merge message containing private metadata, rewrite it before merge.
  If an already-published commit needs history rewriting or branch deletion to hide metadata,
  stop and get explicit maintainer approval first.

The CI public artifact guard scans PR commit metadata as well as repository files. It allows only
`Worker-Model` and `Worker-Thinking` worker traceability footers, and fails unsafe author/co-author
metadata before merge.

## Story template

Use this shape for new implementation stories:

```markdown
## Story ID

PFX-XXX

## User-visible problem

What a user, contributor, or maintainer experiences today.

## Expected behavior

What should be true after the story is done.

## Affected route or surface

Examples: `/securities`, `/accounts`, `README.md`, background job, API read endpoint.

## Severity

blocking | annoying | papercut | parked

## Acceptance criteria

- [ ] Observable result 1
- [ ] Observable result 2

## Non-goals

- Do not implement adjacent feature X.
- Do not weaken safety boundary Y.

## Required evidence

- [ ] Tests, checks, screenshot, or manual smoke note required for this story.
```

Sample:

```markdown
## Story ID

PFX-MVP-001

## User-visible problem

The empty dashboard points users at import/document flows before the manual portfolio path works.

## Expected behavior

A first-time user is guided toward portfolio setup, securities, manual transactions, and then
read-only reports or charts.

## Affected route or surface

`/` dashboard and primary navigation.

## Severity

blocking

## Acceptance criteria

- [ ] Empty-state calls to action list portfolio/account setup before import/document actions.
- [ ] Securities remain a primary navigation target.

## Non-goals

- No broker connection, bank payment, order placement, or import parser rewrite.

## Required evidence

- [ ] LiveView tests for the empty-state call-to-action order.
- [ ] `mix format`
- [ ] `mix test`
```

## Branch naming

```text
story/PFX-004-category-descriptions
fix/PFX-007-symbol-search-provider
chore/quality-gate
```

## PR checklist

- [ ] Tests were written before implementation.
- [ ] No real financial data was added.
- [ ] No external network calls are used in tests.
- [ ] Financial values use `Decimal` where relevant.
- [ ] No external input is converted with `String.to_atom/1`.
- [ ] Story scope was not exceeded.
- [ ] Commands run are listed in the PR.
- [ ] Commit, co-author, and merge-message text are public-safe.

## Commit style

Use concise conventional commits:

```text
feat(taxonomies): add category descriptions
feat(ledger): record buy transactions
fix(market-data): avoid atom creation from symbols
chore(ci): add coverage threshold
```
