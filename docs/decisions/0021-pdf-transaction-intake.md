---
layout: docs
title: "ADR-0021: In-app broker-PDF transaction intake (sandboxed, text-only)"
description: How transaction-grade data locked in broker PDFs gets into Portfolixir, and the document-intake policy change that allows it.
---

# ADR-0021: In-app broker-PDF transaction intake (sandboxed, text-only)

- **Status:** Accepted
- **Date:** 2026-06-21

## Context

Portfolixir derives holdings from transaction history (ADR-0004). The only
practical way to load real history today is Portfolio Performance (PP) CSV/JSON
v1 (AGENTS goal #9). The long-term goal is to replace PP, which forces the
question: where does transaction-grade data actually come from?

For many German banks (e.g. comdirect), the only structured export is an
**IST/holdings snapshot** (positions + current value). The data that matters —
purchase price, shares and date, fees, taxes on sale, dividends — is **locked in
PDFs** (Wertpapierabrechnung, Steuerreport). A generic CSV importer cannot
recover it; it helps only brokers with structured trade exports (IBKR Flex,
Trade Republic, Scalable).

This collides with a standing rule: AGENTS forbids "document intake (binary
`.portfolio`, PP XML, broker PDFs)" unless a reviewed story changes scope. The
owner reviewed this and decided to change scope.

Two options were considered:

- **A — In-app PDF parser (chosen).** Portfolixir parses broker PDFs directly
  into transactions. Maximum convenience; one self-contained tool, no external
  scripting required to migrate a German-bank history off PP.
- **B — Out-of-app extraction + structured push (alternative).** Portfolixir
  never parses PDFs; an external agent (LLM or script) extracts and posts
  structured transactions via the JSON API / MCP. Smaller, safer core, but it
  requires the user to run an external tool and moves extraction quality outside
  the app.

## Decision

Adopt **Option A**: Portfolixir gains an **in-app broker-PDF transaction
importer**, as a reviewed scope change that **supersedes the AGENTS "no broker
PDF intake" rule** for broker transaction/tax PDFs specifically. Binary
`.portfolio` workspace intake remains out of scope; PP XML stays tracked
separately (#333).

The capability is constrained:

- **Sandboxed, text-extraction-only.** No script/JS execution, no embedded-object
  evaluation, no network fetches triggered by PDF content. Enforce size/page
  limits and time-bound parsing; reject malformed/oversized input safely.
- **Per-broker, opt-in parsers.** Start with one broker (comdirect
  Wertpapierabrechnung + Steuerreport); each broker layout is an explicit,
  tested parser, not a generic guess.
- **Same downstream path as every import.** Parsed records go through the
  existing validated **preview** (show what would be created, flag invalid rows)
  before an **atomic, content-hash-idempotent** apply, recorded in the audit
  journal (ADR-0017). PDF parsing produces *proposed* transactions a human
  confirms; it never writes silently.
- **No external LLM calls from the app** (unchanged) — parsing is deterministic
  local extraction, not an LLM call.

Option B remains a valid complementary path (the API/MCP push, #355) and is not
precluded; this ADR simply also allows the in-app parser.

## Consequences

Easier:

- A user can migrate a German-bank history (cost basis, fees, taxes, dividends)
  **without** routing through Portfolio Performance — the core "replace PP" goal.
- Self-contained: no external script/agent needed for the common case.

Harder / accepted trade-offs (explicitly owned):

- **Larger attack surface.** PDFs are hostile input; the sandboxed,
  text-only, size/time-bounded design is mandatory mitigation, and security
  review must cover the parser (Sobelow/manual) on every change.
- **Per-broker maintenance burden.** Broker layouts drift; each parser needs
  tests against synthetic fixtures (never real statements) and will need upkeep.
  Scope grows one broker at a time, not "all PDFs".
- **New dependency.** A PDF text-extraction library is a reviewed dependency
  decision (per the dependency policy); prefer a well-maintained,
  pure-extraction library with no rendering/scripting.
- AGENTS.md is updated to record this exception and point here.

Related: ADR-0004 (holdings from transactions), ADR-0017 (audit journal),
ADR-0002 (thin MCP over JSON API); issues #333 (PP XML), #354 (backup/restore +
export), #355 (MCP write tools), #482 (import hardening).
