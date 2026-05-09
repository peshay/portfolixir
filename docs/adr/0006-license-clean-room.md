# ADR 0006: Clean-room Implementation

## Status

Accepted for MVP.

## Decision

Portfolixir may import data exported by Portfolio Performance, but it must not copy or translate
Portfolio Performance source code unless a deliberate license review is completed.

## Rules

- Do not paste Java code from Portfolio Performance into this repository.
- Do not ask an AI agent to translate Portfolio Performance source code into Elixir.
- Use public documentation, observed file formats, synthetic fixtures and black-box comparison
  tests.
- Keep attribution clear when discussing compatibility.
- Do not name the project in a way that suggests affiliation with Portfolio Performance.

## Rationale

Portfolixir should remain an independent implementation with its own architecture and license
posture.
