# Portfolixir Story Template

Use this shape for small, test-first implementation stories. Keep stories aligned with the
current MVP path unless a card explicitly parks or defers work: securities, portfolio/depot
and cash-account setup, manual buy/sell entry, then quote/chart read surfaces.

## Story ID

PFX-XXX

## Title

Short, implementation-focused title.

## User-visible problem

Describe what a user, contributor, or maintainer experiences today.

## Expected behavior

Describe what should be true after the story is done.

## Affected route or surface

Examples: `/securities`, `/accounts`, `README.md`, a background job, or an API read endpoint.

## Severity

blocking | annoying | papercut | parked

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Non-goals

- Do not implement adjacent feature ...
- Do not weaken safety boundary ...

## Suggested implementation scope

- Files likely touched:
  - `...`
- Tests:
  - `...`

## Required evidence

- [ ] `mix format`
- [ ] `mix test`
- [ ] `pre-commit run --all-files` or the documented replacement public-artifact guard
- [ ] Docker smoke checks if route/UI/runtime behavior changes

## PR requirements

PR body must include:

- Summary
- Tests run
- Docker smoke checks if applicable
- Follow-up tasks

## Sample story

## Story ID

PFX-MVP-001

## Title

Reset first-run dashboard around the MVP path

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
