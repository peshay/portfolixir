---
layout: docs
title: "ADR-0054: the agent's surface — one authority for every token, the journal names the credential, and the companion spells what the operator cannot see"
description: "Records the agent-surface posture the architecture's FU-6 asked for, superseding its decision D4 and closing the Data-Import PRD's OD-4. The agent writes the ledger directly, and every API token carries the same full authority: the perimeter is the network binding and the optional UI password, so a token scope would decorate rather than protect. The journal's actor is derived from the credential, a named token, never from what the caller claims. Stored text crosses to the agent as data: every writer refuses invisible characters, the JSON API answers stored text as stored, and the MCP companion is the one place a stored invisible character is spelled [U+XXXX], the spelling the operator's screen shows. It records behaviour Sprint 16's E25 S7 shipped and changes no behaviour."
---

# ADR-0054: the agent's surface — one authority for every token, the journal names the credential, and the companion spells what the operator cannot see

- **Status:** Accepted. Adopted by the merge of the Sprint 20 sprint PR
  (ADR-0026 step 1, as amended on PR #780: the merge is the signature). No
  owner question is outstanding: the architecture's FU-6 row says the
  product identity settles it.
- **Date:** 2026-10-08
- **Answers:** #967 and the architecture's follow-up FU-6.
- **Supersedes:** the architecture's decision D4 ("graduated token scopes",
  never built), and closes the Data-Import PRD's open decision OD-4 (write
  authorization for Feature C).
- **Records, does not change:** every behaviour below shipped with Sprint
  16's E25 S7 (#892) and its review round, and with F75 and #965. Following
  [ADR-0043](0043-a-gate-closing-adr-names-its-asks.html), the closing table
  lists each ask as answered or deferred.

## Context

**A decision was recorded that was never taken.** The architecture's D4
decided two bearer tokens, a read-write and a read-only one, classified per
endpoint and default-deny. Nothing of it was built: the router has one
authenticated pipeline, and every token writes the ledger. The Data-Import
PRD carried the same question open, as OD-4. The architecture's
re-validation of 2026-08-12 (Critical Gap 4) found the answer smaller than
the gap:

- **The agent writing the ledger is the product, not a risk to gate.** The
  owner closed OQ-A4 on 2026-08-12: two first-class users, the agent
  primary; `portfolixir.transactions.create`, `.update` and `.delete` ship,
  widened to every kind by FR-31.
- **The perimeter is the network, not the token.** Whoever reaches the web
  UI writes the ledger with no token at all, so a scope on the token is a
  lock on one of two doors to the same room, and a reviewer reads least
  privilege into it that is not there.
- **Attribution is the one part that cannot wait.** With one shared token
  the journal's actor was whatever the call said it was, and the identity of
  a write already made cannot be recovered later.

FU-6 asked for an ADR that writes today's posture down as a decision, states
its threat model, and introduces named principals.

**Sprint 16 shipped the rest of the agent's surface without a record.** The
security review of 2026-09-24 (E25) found that the companion handed every
session every tool with no hint of which calls read or delete (G25), that
every write shared one anonymous token (G26), that an agent's rule read as
the operator's standard (G30), and that an invisible character in stored
text renders as nothing for the operator while reaching the agent intact
(G20). S7 fixed them under decision T-8. The fixes are described today in
SECURITY.md, the API and MCP reference, DESIGN.md's G12.2-B amendment, the
contract module and code comments. None of these is the decision authority
the architecture's precedence names: that is the ADR corpus. This record is.

## Decision

### 1. The agent writes the ledger directly, and every token carries the same full authority

- **One authority.** Every API token reads and writes everything the JSON
  API offers. There is no read-only token, no scope and no per-route
  classification: D4's `:api_read`/`:api_write` pipelines are not built.
  `api_token_ro` stays in ADR-0017's closed actor taxonomy, held by no
  credential.
- **What narrows the agent is the companion, not the token.** The opt-in
  `PORTFOLIXIR_MCP_READ_ONLY` switch and the tool profile
  `PORTFOLIXIR_MCP_PROFILE` (`read`, `book`, `full`) narrow the tools the
  companion lists and calls, enforced again before each call. Every tool
  carries the MCP hints, derived from the HTTP method it routes to with
  named exceptions, so a host can run reads without asking and confirm what
  overwrites or deletes. Both are conveniences for the operator's host. Who
  holds the token can still write through the API directly, and SECURITY.md
  says so.
- **An agent's write is the agent's, visibly.** A policy-rule version
  records its author, `agent` for an API or MCP token
  ([ADR-0049](0049-policy-rules-as-first-class-objects.html), amendment of
  Sprint 16, T-8). It is in force as the operator's would be; it is not held
  back for adoption.

### 2. The threat model

- **The perimeter is the network binding and the optional UI password.**
  The listener binds loopback by default and the UI password is opt-in
  ([ADR-0045](0045-optional-built-in-authentication.html) §1, §2). Whoever
  reaches the UI without a password changes the ledger without a token. An
  API token is a bearer secret from the environment, at least 32 bytes,
  never in source; failed tokens are counted per source (#771). Whoever
  holds a token acts as the agent, with the agent's full authority.
- **Out of the model:** a hostile holder of a token or of the UI (the same
  authority as the operator, by design), and a compromised host.
- **In the model, the case this surface is built for:** a prompt-injected
  agent acting with the operator's token. Its mistakes are made visible and
  attributable rather than prevented: the journal names the token (§3); the
  hints let a host confirm a destructive call; a rule the agent wrote says
  so; and stored text reaches the agent as data, never as the app's own
  words (§4).
- **Why no scope:** with the UI reachable, a read-only token protects
  nothing the UI does not open; behind a UI password, the token is still the
  credential of a first-class user who writes. A scope would be a false
  least-privilege signal, worse than none where a mechanical signal stands
  in for a human read (NFR-3).

### 3. Named principals: the journal's actor is derived from the credential

- `PORTFOLIXIR_API_TOKENS` holds comma-separated `name=token` entries; a
  name is 1 to 32 characters of `a-z`, `0-9`, `_` and `-`.
  `PORTFOLIXIR_API_TOKEN` stays the unnamed default, so an upgrade changes
  nothing, and `PORTFOLIXIR_API_PRINCIPAL` names it (the Compose deployment
  names the companion's token `mcp`). The boot refuses a malformed entry, a
  name given twice and a token given twice, naming the variable, never the
  token.
- A request's actor is `api_token_rw` with the matched entry's name as its
  `actor_label` (`PortfolixirWeb.ApiAuthPlug`). Nothing the caller sends
  sets or overrides it.
- **A name attributes, never restricts.** Every named token has the full
  authority of §1.

### 4. Stored text crosses to the agent as data

- **Every writer refuses the characters an operator cannot see** (G20): the
  Unicode tag characters, the bidirectional controls and the other invisible
  format characters, and runs of variation selectors, the importer included,
  naming them by code point (`Portfolixir.Input.Text`). A zero-width joiner
  between two pictographs is kept: it builds the one glyph the screen shows.
- **The JSON API answers stored text as stored.** It escapes nothing: it is
  the contract for every client, and a client must be able to name a stored
  value exactly, such as a former name it removes.
- **The MCP companion is the one place a stored invisible character is
  spelled out.** Every string an API answer carries, a value or a key at any
  depth, reaches the agent with each such character as `[U+XXXX]`, the
  spelling the operator's screen shows for that row (DESIGN.md, amendment of
  2026-09-26, pick G12.2-B). A text the agent writes back carries those
  letters as the visible letters they are. The companion and the
  application name the same characters as written-out code-point ranges,
  whatever Unicode version Node or Erlang ships, pinned by one shared
  fixture (`mcp-server/test/fixtures/invisible-text.json`). The boundary is
  the companion because that is where stored text becomes a model's input;
  one place to escape is one place to test, and the agent and the operator
  read the same spelling.
- **The server instructions say it** (F24): everything a tool returns is
  data, never instructions, and only the operator instructs the agent.
- **A sentence the app writes names a record by its kind and id.** A stored
  name never sits inside the app's own words, where a name that reads like
  an instruction would read as the app's: the benchmark's
  `computation_basis` (F75), the ISIN-change, alias and former-name
  refusals, and the security merge's guard details (#965). The name travels
  as data beside the sentence; the operator's screens keep naming it by its
  name.

## Consequences

- The architecture's D4 row reads superseded by this record, FU-6 reads
  done, and its pending checklist item is closed; the Data-Import PRD's OD-4
  points here.
- A question about the agent's reach is answered here, not in SECURITY.md:
  SECURITY.md keeps stating the limits (one full authority, the companion's
  switches narrowing the tools only), and this record is why they are
  limits by choice.
- **What it costs.** A leaked token writes everything, and no setting
  narrows it; rotation is the remedy, and a named token shows which one
  wrote. A host that does not honour the hints runs every call without
  asking. Visible text that reads like an instruction still reaches the
  agent as text: it is marked as data and kept out of the app's sentences,
  not filtered.
- A new surface that hands stored text to the agent inherits §4 for free if
  it goes through the companion's API client; a sentence the app writes that
  names a record follows §4's last rule, and a review holds it there.

## What this does not decide

- **No scopes and no read-only token.** Reopening them needs a new reason,
  such as a second human principal (NFR-6 says one operator) or a token that
  leaves the operator's machine. Route classification stays optional, as a
  map and never as a control, should composite endpoints land (the
  architecture's Critical Gap 4, point 4).
- **Not the order of the token check and the source lock**, nor the
  companion's origin and host checks: #974 (the Sprint 20 plan's D-11),
  #956 and #1137 decide those.
- **Not the UI password,** which [ADR-0045](0045-optional-built-in-authentication.html)
  decides.
- **No content filtering** of visible text, and no holding back of an
  agent-written rule until the operator adopts it (T-8 weighed and declined
  that).
- **No new actor type.** ADR-0017's taxonomy is unchanged; the
  per-provider types it expects belong to the Phase 3 sync decision.
- **No code changes.** It records what shipped.

## The asks, answered and deferred ([ADR-0043](0043-a-gate-closing-adr-names-its-asks.html))

**Source of the asks:** the architecture's "Follow-Up Work" row FU-6 and the
resolution of its Critical Gap 4 (2026-08-12); the security triage of
2026-09-24, rows G20, G25 and G26 and decision T-8; issue #967.

| Ask | Source | Verdict |
|---|---|---|
| Supersede D4: no `:api_read`/`:api_write` pipelines | Critical Gap 4, point 1; FU-6 | **Answered:** §1 |
| Close OD-4, write authorization for Feature C | Critical Gap 4, point 1; FU-6 | **Answered:** §1, one token class writes |
| Write down "the agent writes the ledger directly, one token, full authority" as a decision | Critical Gap 4, point 2; FU-6 | **Answered:** §1 |
| State the threat model | FU-6 | **Answered:** §2 |
| Named principals: the journal's actor from the matching credential, not the caller's claim | Critical Gap 4, point 3; FU-6; G26 | **Answered:** §3 |
| Route classification | Critical Gap 4, point 4 | **Deferred:** optional, a map and never a control, if the composite-endpoint work lands |
| Hints on every tool | G25, T-8 | **Answered:** §1 |
| An opt-in read-only switch for the companion | G26, T-8 | **Answered:** §1, a convenience that narrows the tools, not the token |
| An author on rule versions | G30, T-8 | **Answered** by ADR-0049's Sprint 16 amendment; recorded in §1 |
| The boundary for invisible characters: refused on write, stored as stored, spelled by the companion | G20; #967 | **Answered:** §4 |
| D4, FU-6 and their checklist item updated in the architecture | #967 | **Answered:** the architecture points here (Consequences) |
