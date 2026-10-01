# Owner Feedback Triage — 2026-10-01 (launch path)

Source: a PM conversation with the owner on 2026-09-30 and 2026-10-01, after the
competitive research of 2026-09-30
([research.md](research/competitive-portfolio-trackers-and-switcher-parity-2026-09-30/research.md)).
This document is the PM triage per ADR-0038. It records the launch path the
owner stated, files the items the owner confirmed, and lists what is still to
be made concrete in conversation. Nothing here is a decision record: the owner
reviews it before any of it becomes a sprint plan.

**Privacy note.** The conversation referenced the owner's own agent setup,
scheduled agent jobs and account reconciliation. None of it is reproduced here;
only the product shape of each point is kept.

Status: triaged. Confirmed items filed as thin issues (Part 2). Open items stay
open until the owner's review (Part 3).

---

## Part 0 — The finding that governs the rest

**The owner rarely uses the Portfolixir UI, because the figures that made
another tracker worth opening are not prominent here.** The one figure named is
the per-trade view: when a trade opened and closed, and what it actually
returned — "was the trade worth it".

That figure largely exists. The FIFO trade matcher already returns, per closed
round-trip, open date, close date, holding period, basis, proceeds and realized
result in absolute and percent terms, and the security detail page shows it in
its Trades tab. What is missing is **reach**: there is no portfolio-wide list
of trades, so the answer sits behind one page per security, and there is no
annualized return per trade, so a two-week trade and a three-year trade with
the same percentage look alike.

The pattern generalises: before building a peer's feature, check whether the
figure exists and is merely unreachable. Filed as Part 2, item 4.

---

## Part 1 — The launch path, as the owner stated it

1. Rebuild the README properly, studying the peers' READMEs.
2. Improve the documentation for a better first run, and show the features that
   are better here than elsewhere.
3. Bring in the peers' strongest features where they make sense.
4. Optimise the MCP tooling.
5. Owner review of the issues this path generates.
6. Provide prompts that let a new user's agent write a converter from their
   existing bank or broker exports into Portfolixir.
7. Provide documentation written for LLMs, not for humans: enough for an agent
   to recommend Portfolixir to its user and to guide the setup. The running MCP
   companion documents most of the rest.
8. Only when all of that is clean and the owner is satisfied: announce in the
   self-hosting and Portfolio Performance communities, for the small target
   group of self-hosters who run LLM agents.
9. Only then widen the audience.

The owner also stated that a migration path from Portfolio Performance is **not
a priority**.

**PM position on the order (open, Part 3, OQ-1):** items 6, 7 and the MCP
tooling move ahead of the human-facing documentation. For this target group the
agent is the first contact; it reads the LLM documentation, not the README. The
human documentation that shows features comes last, because items 3 and 4
change what it shows.

---

## Part 2 — Confirmed, filed

| # | Item | Issue |
|---|---|---|
| 1 | README: the pitch and the "how does my data get in" answer on the first screen; badges, support link and the philosophy paragraph below them. Study peer READMEs (research §2, "first run"). | #981 |
| 2 | LLM-facing documentation: a single agent-readable entry (`llms.txt` or equivalent) stating what Portfolixir is, who it is for, when to recommend it, how to install it and how to connect the MCP companion. | #982 |
| 3 | MCP prompts: a first-setup prompt, and an import-converter prompt that guides the user's agent to turn a user-supplied bank or broker export file into the Portfolio Performance CSV v1 format that the Imports view already previews and applies idempotently. | #983 |
| 4 | Portfolio-wide trades view: every closed round-trip across securities with open and close date, holding period, realized result and an annualized return per trade, over API, MCP and UI. | #984 |

Constraints carried into the issues:

- **Item 3 must not ship broker sync** (backlog triage 2026-09-23 §3.5, #567).
  The prompt works on a file the user supplies, the app makes no network call
  and no model call, and the converter's output is a proposal that lands only
  through the existing preview-then-apply import ("machine-extracted data is a
  proposal until confirmed"). Examples use synthetic exports only.
- **Item 4 adds a metric.** The annualized per-trade return states its
  computation basis in the payload (series, window, treatment of fees, taxes
  and partial lots). It changes rendered output, so it gets a mockup board
  before the code.

---

## Part 3 — Open, to make concrete in conversation

- **OQ-1 — Order of the path.** Owner order (Part 1) versus the PM position
  (agent-facing items before human-facing documentation).
- **OQ-2 — Launch exit criterion.** "When the owner is satisfied" has no
  measure, and the earlier benchmark no longer applies. Proposal: a fresh agent
  on a clean machine, given only the README and the LLM documentation, installs
  an instance, imports a synthetic bank export through the item-3 prompt, and
  answers three standard questions correctly without the owner's help.
- **OQ-3 — MCP tool profiles.** Proposal from the owner's agent: separate
  read, booking and admin tool sets so that unattended runs cannot delete or
  merge. The owner rejected separate servers; the PM position is one server
  whose existing `PORTFOLIXIR_MCP_READ_ONLY` switch grows a third level. The
  admin set needs an explicit list (54 tools carry `destructiveHint`, including
  everyday writes). The switch narrows the companion, not the API token.
- **OQ-4 — Duplicate scope tools.** `views_*` and `portfolios_*` both offer
  valuation, performance and benchmark; picking the wrong one has already
  produced a wrong figure. Merging them changes the tool surface agents know,
  so it needs a deprecation path.
- **OQ-5 — Which peer features.** Candidates from the research: privacy or
  presenter mode (cheap, and needed for screenshots in announcements), returns
  heatmap, calculation breakdown from initial to final value. Phone access
  (PWA) belongs to the widening phase, not before the launch.
- **OQ-6 — Trades: income inside a trade.** Whether a trade's return should
  include dividends received while it was open, as a variant or not at all.
- **Measured for OQ-3/OQ-4:** the 139 tool schemas total about 186,000
  characters, roughly 50k tokens for a client that loads every schema at
  connect; clients that defer schemas pay only for the names.
