---
layout: docs
title: "ADR-0002: Thin MCP companion over the JSON API"
description: Decision that the MCP companion wraps the public JSON API only.
---

# ADR-0002: Thin MCP companion over the JSON API only

- **Status:** Accepted
- **Date:** 2026-05-23

## Context

Portfolixir exposes its supported actions to MCP clients through a companion
server in `mcp-server/`. The companion could either reach into the application
directly (shared database or Elixir contexts) or call the public JSON API like
any other client.

## Decision

The MCP companion is a thin TypeScript wrapper that calls the public `/api/v1`
JSON API only. It must not access the database or Elixir contexts directly. The
companion stays installable and runnable separately from Docker Compose.

## Consequences

- The JSON API is the single supported integration contract; MCP and other
  clients exercise the same code paths, validation, and authorisation.
- No second data path to keep in sync with the domain, and no way for MCP to
  bypass API-level rules.
- The companion needs its own local auth: `PORTFOLIXIR_API_TOKEN` to call the
  API, and `PORTFOLIXIR_MCP_TOKEN` for its HTTP transport.
- Any capability MCP needs must first exist as a JSON API endpoint.
</content>
