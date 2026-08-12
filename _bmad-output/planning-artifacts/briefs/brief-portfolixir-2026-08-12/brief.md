---
title: "Product Brief: Portfolixir"
status: draft
created: 2026-08-12
updated: 2026-08-12
---

# Product Brief: Portfolixir

## Executive Summary

Portfolixir is a self-hosted portfolio system with **two first-class users: the
operator, and the LLM agent the operator runs.** Everything it knows is
reachable through a local JSON API and an MCP companion, and everything it
knows is also visible on a screen. There is one dataset, one instance, one
operator — no cloud, no tenancy, no broker.

It exists because portfolio facts that live *next to* a system rot. The
operator's agent kept dates, theses, target weights and tax state in local files
and in the text of scheduled prompts, and within a single two-day window five of
those facts had drifted from reality — target weights that existed in three
places with two of them stale, a thesis file keyed to a taxonomy that had been
dead for a month, position notes that contradicted the holdings they described.
Each failure had the same shape: the fact had no home with an identity. At the
same time, the agent's most expensive recurring run took roughly 25 calls and
seven minutes, most of it fetching raw data and recomputing figures the system
could have handed over finished.

The answer is not another report screen. It is to make **derived values a
durable, continuously maintained layer that always states its own freshness**,
and to expose every capability to the agent first, with the human view following
close behind. One computation, two audiences: the agent stops burning tokens
recomputing what the system already knows, and the operator stops waiting on a
skeleton to find out where they stand.

## The Problem

**For the agent.** It reads raw data and does arithmetic that belongs on the
server. A full allocation read returns thousands of characters to yield five or
six meaningful drift rows; a securities listing returns the whole catalog to
yield three fields. Everything it cannot get, it keeps itself — in files with no
identities, no provenance and no freshness — and those copies drift silently.
Worse, the drift is invisible: a stale fact and a current one look identical,
and only a contradiction downstream reveals which was which.

**For the operator.** Numbers are computed when a page is opened and forgotten
when it closes, so the wait is paid again on the next visit. There is no
measurement of this; there is a felt symptom, and it arrives through the chat —
the agent shows a stale figure, or works visibly through tool calls to answer
something the system should already know. And the evaluative depth that made
Portfolio Performance worth using — how a position actually performed, how well
something was sold, whether the strategy is working — is thinner here than it
should be.

**Structurally.** The rule that made the app trustworthy — nothing derived is
ever stored, everything is recomputed from the ledger — was read as *nothing
derived may ever be kept*. That is a stricter rule than auditability requires,
and it is the direct cause of both symptoms above.

## The Solution

1. **One auditable ledger, unchanged.** Holdings and every other derived figure
   remain reproducible from transactions. That property is the reason the
   numbers can be trusted and it is not up for negotiation.
2. **A durable derived layer on top of it.** Continuously maintained,
   invalidated by the writes that affect it, rebuildable from scratch at any
   time, never authoritative for a write — and never silent about its own age.
   Every derived value carries its as-of and says so when it is behind its
   inputs, on screen and in the API payload alike.
3. **Answers, not raw material.** Read endpoints return what the caller asked
   for: field selection, roll-up-only aggregates, server-side thresholds,
   and "what changed since" instead of the full state every time.
4. **A home with an identity for every fact.** Rules, theses, events and
   predictions become objects with provenance and history, so they can stop
   living in prompt text and local files.
5. **The operator sees what the agent sees.** Not a parallel truth built from a
   second pipeline — the same values, presented for a human.

## What Makes This Different

Honest version, no fabricated moat:

- **Portfolio Performance** is better at visualization today and will stay ahead
  for a while. It is a desktop application whose data lives in a file; it was
  never built to be an agent's working surface. Portfolixir's advantage is not
  charts — it is being addressable.
- **Cloud trackers** have the polish and the API. The data is theirs.
- **Spreadsheets and local scripts** are infinitely flexible and have no
  identity model, which is exactly the failure this project was started to fix.

The real advantage is structural: **agent-native from the data model up**,
combined with **self-hosted single-operator simplicity**. One instance, one
dataset, no cluster to keep coherent and no tenants to isolate — which is
precisely why it can afford to compute continuously in the background instead of
making someone wait for a page. Larger systems cannot spend compute that
casually. This one can.

## Who This Serves

**The operator's LLM agent — primary consumer.** It needs decision-ready
answers, stable identifiers, provenance and freshness on every fact, cheap
deltas, and metrics computed once on the server rather than reconstructed from
raw series in a context window. Success for the agent is a short, current answer
per question and no private copy of anything.

**The operator — the one who decides.** They need to keep the overview, see what
is happening in the depot, understand what the agent based a recommendation on,
and trust a figure without checking it elsewhere. Every action stays theirs to
take: the system prepares, the human executes.

**Everyone else who self-hosts it.** Portfolixir is open source; anyone can run
their own instance with their own data and their own model. That is the
deployment model, not a growth target — and it is the reason the README has to
make the value legible in fifteen seconds rather than after a feature list.

## Success Criteria

**Agent side — measurable, adopted from the agent's own requirements:**

- The weekly rebalancing run costs **≤ 5 calls** (from ~25) with no external
  price fetch.
- **−70 % response volume** on the four heaviest reads at unchanged decision
  quality.
- **No date, thesis or target weight** exists in a local file or in prompt text
  any more. _(A migration criterion — it can only be met once the objects
  exist.)_
- A **purchase candidate with no holdings** is monitored for upcoming dates
  exactly like a held position.
- The **calibration report** is available without manual work after ten resolved
  predictions.

**Operator side — qualitative, deliberately.** There is no measurement here and
inventing one would be dishonest. The felt signal today is negative and arrives
through the chat: stale figures, visible tool-grinding, tokens spent on
retrieval. So the agent-side criteria above *are* substantially the operator's
criteria, because that is where the operator experiences the system. Two cheap
observable proxies, if a signal is ever wanted: no view waits on an empty
skeleton, and Portfolio Performance stops being opened for questions Portfolixir
should answer. `[ASSUMPTION]` Both are proposed here, not requested.

**Quality bar, both sides:** every metric ships with its computation basis
documented — which series, which window, which reference. A metric without a
definition is an opinion with decimal places.

## Scope

**In, and newly so.** The former blanket rule "no advanced reports" is replaced
by a bounded ladder:

- **(a) derived metrics** per security and per portfolio — moving averages,
  volatility, drawdown, momentum, distance to extremes;
- **(b) comparison and decomposition** — benchmark, contribution analysis,
  factor/sector/region exposure;
- **(c) evaluation of decisions** — prediction calibration, rule evaluation,
  signal quality.

**Gated, not in:** (d) backtesting rules against stored price history; data
acquisition beyond quotes and FX; push delivery to external endpoints; a local
model beyond the narrow, already-gated PDF-intake path.

**Permanently out — identity, not backlog:** no broker connection, no order
creation or transmission, no automated trading or payment, no advice, no raw
news archive, no external LLM calls from the app. The system prepares
decisions; the operator executes them.

**Two working rules follow from the identity and belong in the process
documents:** a capability may ship for the agent alone with the PR stating why,
and the human view then follows in the same or the next batch — enforced as a
close-out finding, so that "the view follows" stays a commitment rather than an
intention.

## Vision

In two to three years Portfolixir is the single home for every fact about one
operator's holdings: the records, the rules that govern them, the theses behind
them, the dates that affect them, and the predictions made about them — each
with an identity, a source and an age. The agent works inside it instead of
around it. The operator opens it to see where they stand and what changed, and
finds the same numbers the agent quoted an hour earlier, because there is only
one set.

It does not become a wealth platform, a broker, or an advisor. It becomes the
place where a person and their agent look at the same truth and disagree about
what to do next — which is the only interesting kind of disagreement.
