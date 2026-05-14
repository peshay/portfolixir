# Development documentation

## Purpose

This guide contains the minimum local context needed for contributors. It keeps
the branch changes small and aligned with the project reset scope.

## Local runbook

Start the project with either:

- Docker Compose:

  - `docker compose up --build`
  - `docker compose down -v` to reset local data

- Phoenix from source:

  - `mix deps.get`
  - `mix ecto.setup`
  - `mix phx.server`

## Required local checks

Run before opening a PR:

- `mix format`
- `mix test`
- `pre-commit run --all-files`

If pre-commit is not installed:

- `pre-commit install --install-hooks`

## Scope guardrails

- Use synthetic fixture data only.
- Keep tests free from external network calls.
- Keep financial values in Decimal-backed fields.
- Keep architecture decisions local and explicit to the three domain modules plus web.

## Cross-links

- [Home Deployment](../home-deployment.md)
- [Story Workflow](./story-workflow.md)

