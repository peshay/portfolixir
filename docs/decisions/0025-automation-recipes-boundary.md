---
layout: docs
title: "ADR-0025: Automation recipes — docs in the repo, broker scripts outside"
description: The docs site documents the external-sync interchange contract and MCP reconcile flow; executable broker clients live in a separate repository, never in this one.
---

# ADR-0025: Automation recipes — docs in the repo, broker scripts outside

- **Status:** Accepted
- **Date:** 2026-07-12

## Context

Users automate transaction intake with external tooling: a read-only broker
sync (e.g. comdirect REST: OAuth session with per-run photoTAN consent,
pulling depot state and settlement documents into local JSON/JSONL), whose
output an LLM agent reconciles against Portfolixir via MCP and books through
the JSON API. This is the LLM-first direction of epic #419 — but AGENTS.md
forbids broker sync *in the app*, and the question was what may live in this
repository (#567).

An adversarial review (2026-07-12, planning artifacts) rejected the initial
draft of an in-repo `contrib/recipes/` directory with three findings that
stand on their own:

1. The mitigations do not contain the credential. Brokers like comdirect
   issue only all-scope tokens (including order rights); per-session TAN
   consent gates token *issuance*, not token *use*, and the same machine
   runs an LLM agent by design.
2. CI-exempt credential-handling code would be the least-reviewed, most
   dangerous code in the repo and a supply-chain target — un-reviewable and
   un-testable under this project's own rules.
3. The app/contrib distinction is invisible to scanners, journalists, and
   broker compliance teams: the repo would "ship bank-login scripts with
   order rights" regardless of disclaimers.

## Decision

1. **No executable broker-integration code in this repository — ever under
   this ADR.** Example scripts and per-broker clients live in a separate
   satellite repository (or the operator's own repos), with their own issue
   tracker, linked once from the docs site. The support boundary is
   structural, not a README plea.
2. **The docs site gains a "Recipes" section whose centerpiece is the
   interchange contract, not the bank client:** the local JSON/JSONL schema
   an external sync should emit, the MCP reconcile-and-book flow, and a
   broker-agnostic safety checklist. Broker-specific auth mechanics are
   described at concept level (what to authenticate, what to pull, what to
   parse) — no turnkey copy-paste of credential flows.
3. **Mandatory guardrails in every published reconcile prompt/template:**
   preview/dry-run before booking, idempotent booking (re-runs must not
   duplicate), no deletes, bounded batch sizes.
4. **Risk banner on every recipe page, EN and DE, above the fold:** the
   broker credential may carry order rights regardless of the tooling's
   intent; sharing credentials with third-party tooling can shift fraud
   liability to the user (gross-negligence doctrine); the broker's terms may
   forbid third-party clients. Prompt templates additionally warn that real
   financial data leaves the machine when a hosted LLM is used, and name the
   local-LLM alternative.
5. **Normative token hygiene in the documented flow:** refresh tokens are
   never persisted; tokens are never written where the booking agent can
   read them; sync tooling and booking agent stay isolated; sessions are
   revoked on exit; no unattended scheduling that bypasses per-run consent.
6. **Preconditions before the first per-broker recipe is published:** a
   dated review of that broker's API terms recorded in the recipe page, a
   removal plan for the linked material (cease-and-desist case), and a named
   risk owner (the maintainer).

Changing boundary 1 requires a new ADR that explicitly supersedes this
section — scope exceptions happen through review (see ADR-0021), not through
drift.

## Consequences

- #567 is re-scoped to: docs recipes section (interchange schema, MCP
  reconcile flow with guardrails, safety checklist, risk banners) plus one
  linked external comdirect example maintained outside this repo.
- The repo keeps exactly two toolchains (Elixir, MCP TypeScript); no new
  language runtimes, no CI carve-outs, no test-exempt directories.
- SECURITY.md and the recipes section stay consistent: this repository
  neither ships nor executes broker-facing code.
