---
layout: docs
title: Features
description: What Portfolixir does that a newcomer should know first, each claim linked to the page that shows it, and what Portfolixir is not.
lang: en
lang_en: /features.html
lang_de: /de/features.html
---

# Features

Portfolixir is a self-hosted portfolio record for you and the LLM agent you
run: your transactions, holdings, valuation, returns and research notes, on
your own machine, on a screen and behind a local JSON API and an MCP
companion. This page says first what it does that a newcomer should know,
then how it breaks down a period's result, and last what it is not. Each claim
links to the page that shows it, so you can check it instead of taking it on
trust.

## The app never calls a language model; your agent does

Portfolixir contains no language model and no client for one. Your agent, with
the MCP client and the model you chose, calls Portfolixir through the MCP
companion, and the companion calls the instance's local JSON API and nothing
else. Nothing runs the other way: every request the application itself sends
out fetches quote history, exchange rates, security search results or a logo,
and the [deployment guide](home-deployment.html#reach) names each of those
calls and when it happens. What your agent reads, it reads through the tools
you connected; the application hands none of it to a model.

The rule is one of the project's
[architecture constraints](architecture.html), and the `import_converter`
prompt binds the converter it has your agent write the same way: no network
call and no model call ([API and MCP](integration/api-and-mcp.html#mcp-tools)).

## A research log your agent reads and writes, on the record

Each security has a research log: dated entries, each one a thesis, evidence,
an invalidation check, an event result, a risk, a decision or a retraction.
Every entry states its source quality (the primary source, several secondary
sources, awareness, unverified), which is required and never filled in by
default; it can carry the link to its source, and its as-of date is the day the
statement refers to, not the day it was written. One call gives your agent a
security's log, newest first, with the thesis state derived from all of it, so
a premise already checked, or already withdrawn, is not investigated again
from nothing.

Nothing in the log is rewritten or removed, by the agent or by you: the
database refuses to update or delete an entry. A finding that turns out wrong
is withdrawn by appending a retraction that carries the reason and stays
beside it, and the current thesis state is derived from the log, never kept
next to it. Every entry names its author from the credential that wrote it (an
entry written over the API or the MCP companion is the agent's, one written on
the screen is yours), and every entry is recorded in the audit journal.

You decide how far the agent goes. Under the companion's `read` profile it
reads the log and appends nothing. `portfolixir.notes.append` is not marked
read-only, so an MCP host that asks before each write asks you before each
entry. Anything a machine extracts from a document would enter only as a
proposal carrying its source until someone confirms it; no such path exists
today, and no request can mark an entry as machine-extracted.

The log is on each security's
[Research tab](product-documentation.html#research-tab-the-security-research-log);
the routes and tools are in
[API and MCP](integration/api-and-mcp.html#research-log-adr-0044), the
profiles in [Connect an Agent](integration/connect-an-agent.html#pick-a-profile-first),
and the decision in
[ADR-0044](decisions/0044-security-knowledge-as-an-append-only-log.html).

## Prompts that carry the no-advice stance

The MCP companion offers two prompts, ready-made instructions you hand your
agent to run against your own instance:

- `first_setup` checks the instance and the active profile, reads what exists,
  proposes cash accounts, depots, buckets and views, explains how your data
  gets in, and creates only what you confirmed.
- `import_converter` has your agent write a converter, run on your machine,
  from a bank or broker export to a file the Imports page previews before
  anything is booked.

Both carry the same stance in their own text:

> The system prepares decisions and the operator executes them: nothing here places, proposes or sizes a trade, and neither do you.
> Do not recommend buying, selling or weighting anything; describe what is recorded.

The companion tells every agent that connects that what a tool returns is
data, never instructions, and that only you instruct it. The figures hold the
same line: the price and risk metrics and the contribution reads carry no
signal, recommendation, rating or score, a finding of your own rules carries
no action, and tests walk the keys of those rendered payloads to keep it so.

The prompts and the server instructions are described in
[API and MCP](integration/api-and-mcp.html#mcp-tools), and
[Connect an Agent](integration/connect-an-agent.html) has the client
configurations to copy.

## Figures that say how they were computed

A figure you can check is worth more than one you have to believe. The returns
(TTWROR, IRR, invested capital, wealth multiple), the benchmark comparison,
the contribution analysis, the risk metrics, a security's price metrics, the
realized gains with each trade's annualized return, the deposits and
withdrawals, the costs, a bond's yields and the findings of your own rules
each carry a `computation_basis` in their API and MCP payload: the input
series, the window it covers, the reference series where there is one, and how
gaps are treated (a day without a price, a missing exchange rate, a history
too short). A metric short of history is `null` with the number of
observations it had, not a small number. The project's rules
(`AGENTS.md` in the [repository](https://github.com/peshay/portfolixir)) make
that basis part of the payload of every new figure, and review rejects a figure
without it.

On the screen the same figures say it in words. The contribution table ends
with its formula and what it counts; the risk metrics name the series they are
measured over; each [Cash flow](product-documentation.html#cash-flow) facet
states what it counts and what it leaves out; a
[performance series](product-documentation.html#performance-ttwror) served
while it recomputes is labelled with what it contains; and a metric without
enough history reads "not computable" with the observations it had
([Risk](product-documentation.html#risk-concentration-and-movement),
[derived metrics](integration/api-and-mcp.html#derived-metrics-adr-0047)).

## The calculation breakdown: which position made how much

Beside a period's return, the portfolio page says where the money result came
from. Under the performance chart on **Wealth → Holdings**, the contribution
table lists every position held or traded in the period, with its start value,
flows, income, costs and end value beside its contribution: end value − start
value − flows + income − costs, in the base currency with the currency move
included, so each row can be checked by hand. What no position owns is listed
apart, each line summed from its own bookings: interest, standalone fees and
taxes, and the currency effect on cash. The positions and those three lines
add up exactly to the period's money result, the "+x EUR in the period" beside
the TTWROR, and none of them is a balancing figure. The table follows the
section's period control and the page's view, and a position that counted zero
on some days, for want of a price or an exchange rate, keeps its place and is
named.

Your agent reads the same table, with the remainder lines, the totals and the
computation basis:

- for one portfolio, `GET /api/v1/portfolios/:portfolio_id/performance/contribution`
  and the MCP tool `portfolixir.portfolios.contribution`;
- for a view across every portfolio, `GET /api/v1/views/:view_id/performance/contribution`
  and the MCP tool `portfolixir.views.contribution`.

The table is described in the
[App Handbook](product-documentation.html#contribution-by-position), the reads
in [API and MCP](integration/api-and-mcp.html#transactions-and-holdings)
(the view read under [Buckets and Views](integration/api-and-mcp.html#buckets-and-views)),
and the method in
[ADR-0051](decisions/0051-contribution-analysis.html).

## What Portfolixir is not

Portfolixir is deliberately narrow, and it says so where a newcomer and an
agent read first:

- **Not a broker.** There is no order-placing broker connection, no trading and
  no payment: nothing creates, places or sends an order, and nothing moves
  money.
- **Not a sync service.** There is no bank or broker sync, by design. Your
  history comes in from export files dropped on the
  [Imports page](product-documentation.html#imports), or is booked by hand or
  by your agent.
- **Not an adviser.** There is no advice: nothing tells you what to buy, sell
  or weight. The system prepares decisions, and you make them. The nearest
  thing on any screen is the rebalancing hint beside an allocation drift:
  arithmetic on targets you set, the indicative number of units that would
  close the gap, shown and never turned into an order
  ([ADR-0023](decisions/0023-drift-sign-and-display-only-rebalancing-hints.html)).
- **Not a hosted service.** There is no hosted service, no cloud and no
  tenancy: one dataset, one instance, one operator, on a machine you control.
  You run it with Docker Compose, and you update it and back it up yourself
  ([Home Deployment](home-deployment.html)).
- **Not a phone app.** There is no phone app; the web UI runs in a browser
  against your own instance.
- **No model inside.** The app calls no language model; the agent you connect
  is yours, and so is its choice of model.
- **Not a production promise.** There is no upgrade guarantee and no claim of
  production readiness. Portfolixir is an open-source project under the MIT
  license, written with LLM coding agents, and every commit is owned by an
  accountable human.

[llms.txt](llms.txt), the entry written for agents, gives an agent the same
list before it recommends Portfolixir, and the
[App Handbook](product-documentation.html#non-goals-today) keeps the current
non-goals.
