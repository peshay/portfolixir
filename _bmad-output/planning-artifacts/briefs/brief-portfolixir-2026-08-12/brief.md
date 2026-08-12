---
title: "Product Brief: Portfolixir"
status: draft
created: 2026-08-12
updated: 2026-08-12
---

# Product Brief: Portfolixir

**What this decides:** the product's identity — who Portfolixir is for, and how
far its scope now reaches. **What changes if it is accepted:** the PRD, the
`AGENTS.md` Project Goal and Hard Rules, the ADR for a durable derived-value
layer, and the README's opening definition.

## Executive Summary

Portfolixir is a self-hosted portfolio system with **two first-class users: the
operator, and the LLM agent the operator runs.** Everything it knows is
reachable through a local JSON API and an MCP companion, and everything it
knows is also visible on a screen. One dataset, one instance, one operator — no
cloud, no tenancy, no broker.

It exists because portfolio facts that live *next to* a system rot. The
operator's agent kept dates, theses, target weights and tax state in local files
and in the text of scheduled prompts, and within a single two-day window five of
those facts had drifted from reality — among them target weights that existed in
three places with two of them stale, and a thesis file keyed to a taxonomy that
had been dead for a month. Meanwhile the agent's most expensive recurring run
took roughly 25 calls and seven minutes, most of it fetching raw data and
recomputing figures the system could have handed over finished.

The answer is not another report screen: make **derived values a durable,
continuously maintained layer that always states its own age**, and expose every
capability to the agent first, with the human view following close behind.

## The Problem

**For the agent.** It reads raw data and does arithmetic that belongs on the
server — a full allocation read returns roughly 15,000 characters to yield five
or six meaningful drift rows. Everything it cannot get, it keeps itself, in
files with no identity, no provenance and no as-of date. A stale fact and a
current one look identical there, and only a contradiction downstream reveals
which was which. Each of the five failures had the same shape: **the fact had no
home with an identity.**

**For the operator.** Numbers are computed when a page is opened and forgotten
when it closes, so the wait is paid again on the next visit. There is no
measurement of this; there is a felt symptom, and it arrives through the chat —
the agent shows a stale figure, or works visibly through tool calls to answer
something the system should already know. And the evaluative depth that made
Portfolio Performance worth using — how a position actually performed, how well
something was sold, whether the strategy is working — exists here mostly as data
without a surface to read it on.

**Structurally.** The rule that made the app trustworthy — nothing derived is
ever stored, everything is recomputed from the ledger — was implemented as
*nothing derived may ever be kept*. That is stricter than auditability requires,
and it is the shared cause of both symptoms above.

## The Solution

1. **One auditable ledger, unchanged.** Holdings and every other derived figure
   remain reproducible from transactions. That property is why the numbers can
   be trusted, and it is not up for negotiation.
2. **A durable derived layer on top of it.** Continuously maintained,
   invalidated by the writes that affect it, rebuildable from scratch at any
   time, never authoritative for a write — and carrying its as-of everywhere,
   saying so when it is behind its inputs.
3. **Answers, not raw material.** Read endpoints return what the caller asked
   for: field selection, roll-up-only aggregates, server-side thresholds, and
   "what changed since" instead of the full state every time.
4. **A home with an identity for every fact.** Rules, theses, events and
   predictions become objects with provenance and history, so they can stop
   living in prompt text and local files.
5. **The operator sees what the agent sees** — the same values, presented for a
   human, not a parallel truth from a second pipeline.

## Scope

**Newly in scope.** The former blanket rule "no advanced reports" is replaced by
a bounded ladder:

- **(a) derived metrics** per security and per portfolio — moving averages,
  volatility, drawdown, momentum, distance to extremes;
- **(b) comparison and decomposition** — benchmark, contribution analysis,
  factor/sector/region exposure;
- **(c) evaluation of decisions** — prediction calibration, rule evaluation,
  signal quality.

**Gated, not in:** (d) backtesting rules against stored price history; data
acquisition beyond quotes and FX; push delivery to external endpoints; a local
model beyond the already-gated PDF-intake path.

**Permanently out — identity, not backlog:** no broker connection, no order
creation or transmission, no automated trading or payment, no advice, no raw
news archive, no external LLM calls from the app. The system prepares decisions;
the operator executes them.

**Two working rules follow, and belong in the process documents:** (1) a
capability may ship for the agent alone, with the PR stating why; (2) the human
view follows in the same or the next batch, enforced as a close-out finding.

## Who This Serves

**The operator's LLM agent — primary consumer.** It needs decision-ready
answers, stable identifiers, provenance and freshness on every fact, cheap
deltas, and metrics computed once on the server rather than reconstructed from
raw series in a context window.

**The operator — the one who decides.** They need to keep the overview, see what
is happening in the depot, understand what the agent based a recommendation on,
and trust a figure without checking it elsewhere. Every action stays theirs to
take.

**Everyone else who self-hosts it.** Portfolixir is open source; anyone can run
their own instance with their own data and their own model. That is the
deployment model, not a growth target.

## What Makes This Different

Measured against the tools this actually competes with: **Portfolio Performance**
is better at visualization today, and that gap will not close quickly — it is a
desktop application whose data lives in a file, and it was never built to be an
agent's working surface. **Cloud trackers** have the polish and the API. The data
is theirs. **Spreadsheets and local scripts** are infinitely flexible and have no
identity model, which is exactly the failure this project was started to fix.

The real advantage is structural: **agent-native from the data model up**,
combined with **self-hosted single-operator simplicity**. One instance, one
dataset, no cluster to keep coherent and no tenants to isolate — which is
precisely why it can afford to compute continuously in the background instead of
making someone wait for a page. Larger systems cannot spend compute that
casually. This one can.

## Success Criteria

**Agent side — measurable, adopted from the agent's own requirements** (sources
and baselines in `feedback-triage-2026-08-12.md`):

- The weekly rebalancing run costs **≤ 5 calls** (from ~25) with no external
  price fetch.
- **−70 % response volume** on the four heaviest reads, with no field the
  agent's decisions depend on removed.
- **No date, thesis or target weight** exists in a local file or in prompt text
  any more. _(A migration criterion: it gates on the objects shipping first.)_
- A **purchase candidate with no holdings** is monitored for upcoming dates
  exactly like a held position.
- The **calibration report** is available without manual work after ten resolved
  predictions.

**Operator side — qualitative, deliberately.** The only signal is the felt one
described above, and inventing a metric for it would be dishonest. So the
agent-side criteria *are* the operator's criteria — that is where the operator
experiences the system. Two cheap proxies if one is ever wanted: no view opens
on a placeholder that has to fill itself in, and Portfolio Performance stops
being opened for questions Portfolixir should answer. `[ASSUMPTION]`

**Quality bar, both sides:** every metric ships with its computation basis
documented — which series, which window, which reference. A metric without a
definition is an opinion with decimal places.

## Vision

In two to three years Portfolixir is the single home for every fact about one
operator's holdings — the records, the rules that govern them, the theses behind
them, the dates that affect them, the predictions made about them — each with an
identity, a source and an age.

It does not become a wealth platform, a broker, or an advisor. It becomes the
place where a person and their agent look at the same truth and disagree about
what to do next, which is the only interesting kind of disagreement.
