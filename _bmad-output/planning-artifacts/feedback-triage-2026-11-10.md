# Agent Report Triage — 2026-11-10 (the news layer's first fill)

Source: a findings report the operator's agent wrote for the PM on
2026-11-10. The agent had registered the operator's feeds and sources and
run the first fetch. This document is the PM triage per ADR-0038 and the
sprint workflow's "Issues and the registry" (a third party's report is
triaged into a triage document). Every claim was checked against the code
on `main` at `7d53be4`; the two parser claims were reproduced with
synthetic bodies. Nothing here is a decision record: the owner answers
Part 3 before any of it becomes a plan.

**Privacy note.** The report named the operator's securities, gave counts
from the instance (feeds, rated sources, refused items) and named feed and
story ids. None of that is reproduced here. Only the product shape of each
point is kept.

Status: **answered.** On 2026-11-10 the owner accepted every
recommendation of Part 3 ("ja"). Every item now has a record (Part 4);
P1 and P2 are built on the PR that carries this document.

---

## Part 0 — What governs the rest

1. **The `regulatory` class is dead for every SEC filer, and the parser
   says so on purpose.** EDGAR's Atom feeds declare
   `encoding="ISO-8859-1"`; the reader (`saxy`) accepts UTF-8 only and the
   parser maps its `invalid_encoding` error to
   `parse_refused:unsupported_encoding` (`news/parser.ex`, `read/1`). The
   refusal is honest, but the feeds ADR-0056 §2 names as the regulator's own
   word cannot be read at all. This is the report's one blocker, and the
   only item that should not wait for a sprint (OQ-1).
2. **One premise does not hold.** The report says the design (§1) planned
   to resolve aggregator redirects at ingest. ADR-0056 §2 says the
   opposite: "no redirect is followed", deferred as "news follow", because
   it would make the app request a host it did not choose, once per item;
   §13 and D9 keep the ask deferred. The 255-character refusal is real
   (C1 below), but its fix is not the deferred flip.
3. **One finding is stronger than the report states.** The report treats
   the frozen tier (C2) as cosmetic, because the pilot's items age out. The
   other direction matters more: a domain rated **down or blocked** after
   its items were stored keeps those items at their old tier, and
   promotion turns that tier into the entry's `source_quality`. D6 refuses
   a `source_quality` sent by the caller, and the research log is never
   rewritten (ADR-0044). So an entry can claim a better source than the
   operator's current table allows, permanently.

---

## Part 1 — Item by item

Severity follows the sprint workflow's closing-act scale (S1 to S3).

| # | Claim | Verified | Class | Recommendation |
|---|---|---|---|---|
| P1 | Every EDGAR Atom feed answers `parse_refused:unsupported_encoding`; the body is ASCII under an ISO-8859-1 declaration | **Yes**, reproduced: an Atom body behind `encoding="ISO-8859-1"` and one behind `encoding="US-ASCII"` are both refused; so is a Latin-1 body with a byte above 0x7F | **S2** (a flow that cannot be completed: a whole feed class), parser = hostile-input surface, so risk-tier attention | Before the reader: read the declared encoding from the prolog (the same linear prolog scan the DTD guard already does); for ISO-8859-1, Latin-1 and US-ASCII (any letter case), transcode the body Latin-1 → UTF-8 (`:unicode.characters_to_binary/3`) and replace the declaration's encoding. **Check `max_bytes/0` again after transcoding** (a Latin-1 body can double). Every other encoding stays refused (no windows-1252 guessing). A fixture of each, written first and seen failing; A1's attack fixtures re-run behind the transcoding |
| P2 | A UTF-8 byte-order mark before `<?xml` is refused as `malformed` | **Yes**, reproduced, with and without a declaration. The parser is inconsistent with itself: `declares_dtd?/1` already skips a BOM, the reader then fails on it | **S2** (same class of failure; worked around on the instance through another host) | Strip one leading UTF-8 BOM before the reader, in the same prolog step as P1. One fixture. Same issue as P1: one story, one function |
| C1 | `notes.append` with `cluster_id` answers 422 when no member's link fits 255 characters; aggregator redirect links are often 250–400 | **Yes.** `promotion.ex` `@source_url_max 255`; `security_notes.source_url` and `security_events.source_url` are `varchar(255)`; the parser accepts links up to 2,048 bytes. So the layer stores links the log cannot hold | **S2** (a flow that cannot be completed, for most aggregator stories) | **Widen, do not follow** (OQ-2): `source_url` on `security_notes` and `security_events` to 2,048 characters, the parser's own cap, in the changeset, the migration and D6's two 422s. "News follow" stays deferred: its reason (the app requesting a host it did not choose) is unchanged, and **[unverified]** current Google News article links no longer resolve by a plain HTTP redirect at all, so the flip may not even work. Where a screen prints the link in full, it gets a board first |
| C2 | A source rated after ingest does not change its stored items' tier; promotion then writes the old tier | **Yes.** `Sources.put_source/4` writes the table only; promotion reads `%Item{tier: …}` (`promotion.ex` `source_quality/1`) | **S2**, bordering S1 in the downgrade direction (Part 0.3) | **Re-tier on a hand write** (OQ-3): `sources_put` re-rates, in the same transaction, the stored unpromoted items the row now covers (longest-suffix rule, B5's caps unchanged), and recomputes the representative of each touched story; a newly `blocked` domain's unpromoted items are removed, as they would not have been stored. Promoted items keep their tier: the entry they name is already written. Needs an ADR-0056 §3 amendment. Reading the tier at query time instead was weighed and not recommended: it moves the digest's tier filter and the representative into every read |
| R1 | A redirect to another host answers `url_not_allowed:host_not_allowed` without naming the target | **Yes** (`net/http.ex` `follow/3`; the fetcher records only the reason) | **S3** (the agent fixed it by reading the feed by hand) | A line on "Polish: API and MCP" (#1356): the feed's `last_error` names the refused hop's **host** (normalized, never the full Location, which is the remote server's text) |

---

## Part 2 — Outside the app

The report's "next step" (the labeller in four weeks of shadow, then the
radar and the watcher on `news_digest`) runs on the operator's side and
needs nothing built here. Three things the PM adds:

- **Start the shadow after P1 lands, not before.** The labeller's recall
  target is measured against the stories the agent logs. With no SEC
  filing reaching the layer, four weeks of shadow would be measured on a
  layer without its most material class, and the baseline would not carry
  over.
- **One prompt version at a time** during the shadow, or every read names
  `prompt_version`: ADR-0056 D10 is still open, and two prompt versions
  side by side make the digest's order flip between calls.
- **The labeller's token is a named token** (ADR-0054, §7). Creating it
  and adding the companion with the `label` profile is the owner's step on
  the instance; there is no scope to request.

---

## Part 3 — The owner's questions (all answered 2026-11-10 with the recommendation)

- **OQ-1 — P1/P2 now, or in Sprint 29?** Recommended: **now**, as one
  small single-concern PR (squash), outside the sprint: one function in
  the parser, test-first, its own risk-tier verification pass. Waiting for
  Sprint 29 keeps the regulatory class dead and delays the labeller's
  shadow (Part 2).
- **OQ-2 — C1: widen `source_url` to 2,048, keep "news follow" deferred?**
  Recommended: yes. A migration on two research tables, no row rewritten;
  a Sprint 29 candidate.
- **OQ-3 — C2: re-tier stored items on a hand `sources_put`?** Recommended:
  yes, as an ADR-0056 amendment on the Sprint 29 planning PR, built in
  that sprint.

---

## Part 4 — Where each item went (2026-11-10)

| Item | Record | Label |
|---|---|---|
| P1 + P2, the parser's prolog (encoding, BOM) | #1442 (under #416), built on this PR | `agentic` |
| C1, `source_url` 2,048 | #1443 (under #416) | `agentic` |
| C2, re-tier on `sources_put` | #1444 (under #416), the ADR-0056 §3 amendment on the Sprint 29 planning PR first | `agentic` |
| R1, the redirect target in `last_error` | a line on #1356 ("Polish: API and MCP") | — |

The next planning session takes #1443 and #1444 as candidates. ADR-0056
A1 states no encoding, so #1442 changes no decision record; the parser's
moduledoc states the rule.
