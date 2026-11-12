---
layout: docs
title: "ADR-0056: the news layer — feeds fetched, matched and deduplicated by rule inside the app, labelled by a model outside it"
description: "Decision for gate B3.3, narrowed to news (idea F12, idea I21; extends I13). Portfolixir fetches registered news feeds, binds each item to a security by construction or by a deterministic alias matcher, clusters duplicates into stories, rates each source by a hand-kept tier and serves compact story lists over API and MCP. No model runs in the app: an outside labeller writes machine-generated labels through one schema-closed write, and everything works without them. Excerpts of at most 600 characters and a 90-day retention keep it from becoming a news archive; a feed that has not answered for 24 hours reads as stale. Issuer and regulatory stories are never hidden by a label. No token scope is introduced (ADR-0054 stands)."
---

# ADR-0056: the news layer — feeds fetched, matched and deduplicated by rule inside the app, labelled by a model outside it

- **Status:** Accepted. Signed by the merge of #1399 on 2026-11-05
  (ADR-0026 step 1, as amended on 2026-10-08: the merge is the signature),
  and confirmed with its amendment of 2026-11-06 by the merge of the
  Sprint 26 planning PR, after the owner's doubts and his answer the same
  day (see "Amendment of 2026-11-06"), and amended on 2026-11-07 by the
  merge of the Sprint 27 planning PR (see "Amendment of 2026-11-07"), and
  amended on 2026-11-08 by the Sprint 27 closing act, adopted by the merge
  of the sprint PR (see "Amendment of 2026-11-08"), and amended on
  2026-11-09 by the Sprint 28 build and its closing act, adopted by the
  merge of that sprint PR (see "Amendment of 2026-11-09"), and amended on
  2026-11-12 by the merge of the Sprint 29 planning PR (see "Amendment of
  2026-11-12" at the end). The merge opens gate B3.3
  **for news feeds only**; every other kind of acquisition (bank, broker
  and wallet sync, F13; CPI and other series) stays behind it.
- **Date:** 2026-11-05
- **Answers:** gate B3.3 for news (the addendum's "Parked, with reasons");
  idea F12 (data collectors and their health), narrowed to news; idea I21
  (the agent's feature request of 2026-11-05 and its review round).
- **Extends:** idea I13 and the Sprint 25 convention N1 (plan D-5): an
  outside aggregator records a news item as a research note. This record
  adds what comes before that note — fetching, matching, deduplicating —
  and keeps the note as the place a story becomes knowledge (§8).
- **Builds on:** ADR-0002 (MCP calls the API only), ADR-0003 (decimals as
  strings), ADR-0044 (the research log, `source_quality`, `as_of`, the
  `invalidation_condition` of a thesis entry), ADR-0048 (security events),
  ADR-0054 (one authority per token, named principals, stored text as
  data), the bounded HTTP client and URL policy (#762, #763), and the
  delta cursor (FR-38, `Portfolixir.DeltaCursor`).
- **Ladder:** none. Nothing here is a metric; a label's `tone` is a stored
  statement, not a computed figure, and nothing scores it here.
- Following [ADR-0043](0043-a-gate-closing-adr-names-its-asks.html), §13
  lists each ask as answered or deferred.

## Context

**The agent spends its context on raw text the app could have sorted.**
The operator's agent watches the held and watched securities for news
each morning. Measured over a week of its scheduled runs, a run takes
several hundred thousand context tokens and more than ten minutes, and
the prompt is about one percent of that: the rest is feed and web-search
output read in full. Most of it is duplicates, items about another
company with a similar name, and items from sources the agent then
discounts.

**I13 put the judgment outside and the result in the research log.** The
owner decided on 2026-11-05 that the aggregation runs through an agent
outside the app, and Sprint 25's N1 writes the convention down: an item
becomes an `evidence` note with `as_of` its publication date, a source
link and a `source_quality`. That stays. What it leaves outside too is the
part that needs no judgment at all — fetching a feed, deciding which
security an item is about when the feed belongs to the issuer, noticing
that eleven items are one story, and knowing that a feed has been dead
since Tuesday. Done outside, every run repeats it, and nobody sees a dead
collector: a quiet morning and a broken feed look the same.

**Why this is B3.3 and not a convention.** The I13 triage said it: if the
app fetched news itself, it would be B3.3. The addendum parked B3.3 until
a decision covers sources, failure behavior, retention ("condensed dated
signals with source links, never a full-text archive") and collector
health ("a dead collector is visibly dead within a day instead of
producing false calm"). §3 to §6 are those four.

**What stays fixed.** No LLM in the app and no external LLM call from it
(permanent non-goal); no raw news archive (permanent non-goal);
machine-extracted data is a proposal until confirmed (NFR-10); every token
carries the same authority (ADR-0054 §1).

## Decision

### 1. What the app does, and what it does not

The app fetches feeds the operator or the agent registered, assigns each
item to a security or a category by rule, clusters duplicates into
stories, rates sources by a hand-kept tier, and serves the stories. It
calls no model, stores no article text beyond a capped excerpt, ranks
nothing by sentiment, delivers nothing to anyone, and guesses no
assignment. Any judgment of a story — what kind of event it is, how much
it matters — comes from outside, through §7's one write.

### 2. Feed classes and identity

A feed has one of four classes, and the class decides how its items find
their security:

| Class | Example | Bound to | Identity |
|---|---|---|---|
| `issuer` | the issuer's own newsroom feed | a `security_id` | by construction: the feed belongs to the security |
| `regulatory` | a filing feed per identifier (SEC EDGAR per CIK, an ad-hoc feed per ISIN, an exchange announcement feed per code) | a `security_id`, through the identifier stored on it | by construction |
| `aggregator` | a news search feed | nothing | by the alias matcher below, or not at all |
| `thematic` | a sector or theme feed | a `category_id` of a classification, never a security | by construction, to the category |

**`news_identity` on the security.** A new block on the security, written
through `securities.update`: `cik`, and `aliases`, a list of
`{token, context, case}`. `token` is a name or a symbol; `context` is an
optional list of words of which one must appear in the same sentence;
`case` is `sensitive` or `insensitive`. A word boundary around `token` is
implied. **No regular expression is accepted from input.** *Why:* a
pattern from data runs against foreign text, and a backtracking pattern is
a denial of service and unreadable in review; the grammar expresses every
case the request named (a ticker that is also an English word, matched
only next to "stock", "shares" or the company's name) and is matched by
tokenizing the sentence and looking words up, with no backtracking at all.
ISIN and WKN are the security's existing fields.

**The matcher.** An `aggregator` item is matched against the universe
(below): exactly one hit assigns it; none leaves it `unassigned`; more
than one leaves it `ambiguous`, with the candidates listed. Never a model,
never a default. A change to a security's aliases re-matches the
`unassigned` and `ambiguous` items of the last 7 days.

**The universe** is every security that a view holds, that carries a
target weight above zero, or that carries the new `news_watch` flag. *Why
the flag:* a candidate with no holding and no target must be watchable,
and the catalogue has no watch list today.

**Exchange-traded funds** get no `aggregator` feed; an `issuer` feed only
where the fund's provider publishes one. *Why:* a fund's name matches
index and market news that is not about the fund.

**Aggregator links.** Some news search feeds wrap each link in a redirect.
The publisher's domain is taken from the item's `<source>` element; an
item without one is dropped and counted (`dropped_no_source`), and no
redirect is followed. *Why:* without the real domain, dedupe and tier are
blind; following the redirect would make the app request a host it did
not choose, once per item. **To flip:** "news follow", which follows the
redirect through §5's client for items without a source element.

### 3. Sources and their tier

`news_sources` maps a domain to a tier: `primary`, `secondary`,
`awareness` or `blocked`. Items from a `blocked` domain are dropped at
ingest and counted. The operator or the agent edits the table; **a
correction by hand is never overwritten by a later import or seed** — the
invariant ADR-0044 §2 already binds for `source_quality`. An unknown
domain is `awareness` until someone rates it.

When a story becomes a research note (§8), its tier becomes the note's
`source_quality` by one rule: a `primary` member gives `primary`; members
from two or more distinct `secondary` domains give `secondary_multi`; one
`secondary` domain gives `unverified`; `awareness` gives `awareness`.

### 4. Data model

- **`news_feeds`:** class, URL, `security_id` or `category_id`, enabled,
  interval in minutes, language, `last_ok_at`, `last_error`, and the
  rolling counts `items_24h` and `err_24h`.
- **`news_items`:** cluster, `security_id` or `category_id` (or neither,
  while unassigned), feed, class, `published_at` as the feed states it,
  `first_seen_at` by the server's clock, title (plain text, at most 160
  characters), canonical URL, domain, tier, language, excerpt (HTML
  removed, at most 600 characters), content hash, `assignment`
  (`assigned`, `unassigned`, `ambiguous` with its candidates), `status`
  (`new`, `promoted`, `muted`), and the ids of the notes it was promoted
  to.
- **`news_clusters`:** one story about one security. An item joins a
  cluster of the same security when, within 72 hours, its normalized title
  hash is equal or its title tokens have a Jaccard similarity of at least
  0.8. The representative is the earliest item of the best tier present;
  the cluster counts its duplicates. Deterministic: the same items give
  the same clusters.
- **`news_labels`:** §7.
- **Languages.** Each `issuer` and `regulatory` feed is registered in one
  language. Clustering across languages is not a goal, and the duplicate
  rate is measured per language. *Why:* the same release in two languages
  shares no title tokens, and catching it would need translation or
  embeddings, both of which §1 keeps out.

The 72 hours and the 0.8 are starting values, set by a setting and
reviewed against a sample after two weeks of use.

### 5. Fetching and failure

- **A scheduler like the quote sync:** a supervised process, opt-in in
  production, off in every other environment, with an on-demand run for
  the UI and the agent. The suite registers a fake provider and never
  touches the network.
- **Default interval per class:** `regulatory` 10 minutes, `issuer` 15,
  `aggregator` 60, `thematic` 180; per feed overridable.
- **Every request goes through the bounded client** (`Net.Http`: byte
  cap, deadline, redirects only through the URL policy) with the feed's
  own host as its allow-list. *Why:* a feed URL is caller-supplied, so a
  feed is a request-forgery surface; the URL policy refuses private and
  special-purpose addresses, and a redirect to another host is refused.
- **A feed that fails never stops another:** each feed runs on its own,
  backs off exponentially on 429 and 5xx, and records its error.
- **Per-host limits:** at most 10 requests per second to `sec.gov`,
  as its fair-access policy asks; IPv4 is tried first, because IPv6 to
  that host was seen to hang.
- **The user agent** is set by the operator in `PORTFOLIXIR_NEWS_USER_AGENT`.
  The SEC asks for a contact address in it; the repository carries none,
  so a `regulatory` feed on `sec.gov` stays disabled with the error
  `user_agent_missing` until the variable is set.

### 6. Health: a dead collector is visibly dead within a day

Each feed reports `last_ok_at`, `items_24h`, `err_24h` and `stale`.
**`stale` is true when a feed has had no successful fetch for 24 hours.**
The health read adds the day's `unassigned`, `ambiguous`, dropped and
blocked counts, the number of unlabelled stories and the time of the last
label. The dossier's news block (§9) shows the age of the newest primary
story, so a quiet security and a dead feed read differently.

### 7. Labels: written from outside, never required, never hiding a primary story

**The row.** `news_labels`: `cluster_id`, `model`, `prompt_version`,
`event_type` (`earnings`, `guidance`, `capital_measure`, `legal`,
`m_and_a`, `product`, `regulatory`, `macro`, `noise`), `materiality` 0 to
3 (0 noise, 1 worth a note, 2 worth checking the thesis, 3 touches an
invalidation condition), `tone` −1, 0 or +1, optional `thesis_note_id`
and `clause_idx`, `confidence` (a decimal from 0 to 1, a string in the
API and MCP), optional `suggested_security_id`, `machine_generated`
(always true), `created_at`. The active label of a cluster is the newest
one per `prompt_version`. Labels are kept without limit.

**The one write.** `news.label_put` takes exactly those fields. The schema
is closed: an unknown field is refused with 422 naming it, so
`security_id`, tier, status, notes, events and feeds cannot be written
through it. It is idempotent per `(cluster_id, model, prompt_version)`
and journaled like every write.

**The one read for the labeller.** `news.unlabeled(prompt_version, limit)`
returns stories without a label of that version: id, security, title,
excerpt, domain, tier, publication time; once per answer the universe
(id, short name, ISIN); and per assigned security the active thesis's
`invalidation_condition` split into numbered clauses at line breaks and
semicolons, with the note id.

**A label is a proposal (NFR-10), so it may sort but not hide what is
certain.** Stories from `issuer` and `regulatory` feeds appear in the
digest whatever their label; a label orders them. `min_materiality` and
`include_unlabeled` act on `aggregator` and `thematic` stories only. A
label never assigns a security: `suggested_security_id` shows beside an
`unassigned` or `ambiguous` item, and only `news.assign` (§9) moves it.
`tone` is never a filter or a sort key.

**Fail-open.** Without any label, every read works unchanged; only
`n_unlabeled` grows. Nothing waits for the labeller.

**No token scope.** The labeller writes with its own named token
(ADR-0054 §3), so every label and any other write it makes is attributed
in the journal. Its token carries the same authority as every other one.
*Why no scope:* ADR-0054 decided against scopes and named what would
reopen them — a second human principal or a token that leaves the
operator's machine. Neither applies: the labeller runs on the operator's
machine, and its model never holds the token — it returns JSON to a
script, and the script calls `news.label_put` and nothing else. The
schema is the hard limit on what a label can change. **To flip:** a new
reason in the sense of ADR-0054, in its own record.

**A companion profile `label`** lists only `news.unlabeled` and
`news.label_put`, and the agent's profiles do not list them. As ADR-0054
§1 says of every profile, it narrows the tools, not the token.

**Not B3.8.** The model runs outside the app and writes through the API
like any agent; the app runs no model, so the local-model gate is not
touched.

### 8. From story to knowledge

`notes.append` accepts a `cluster_id`. The server fills in what the N1
convention asks the agent to supply: `kind` `evidence`, `as_of` the
story's publication date, `source_url` from the best-tier member,
`source_quality` by §3's rule; the agent writes the body. The story
becomes `promoted` and links the note. `events.create` accepts a
`news_id` as its source. A story becomes knowledge only by such a write:
nothing in the news layer writes a note, an event or a prediction by
itself.

### 9. The agent's surface

Answers are compact by rule: enums as short codes, no URLs or excerpts in
lists, null fields left out, short names of at most 20 characters, stable
integer ids for follow-up calls, and a `truncated` flag with a cursor
instead of a large page. Eight tools, because every schema costs context
in every session:

| Tool | What it answers | Budget |
|---|---|---|
| `news.digest(view_id, consumer or since, ack_cursor?, min_materiality=2, tier_min=secondary, include_unlabeled=false, max_rows=40)` | one row per security with something new: id, short name, count, highest materiality, event types, the top story (id, title, tier, time); quiet securities only as a count; totals for unlabelled and unassigned | ≤ 800 tokens for a 40-security fixture over 24 hours; ≤ 100 with nothing new |
| `news.list(security_id or category_id or cluster_id, since?, min_materiality=0, event_types?, tier_min?, assignment?, limit=20 up to 100, fields=slim or std)` | story rows; `std` adds URL and note ids; `assignment=unassigned` or `ambiguous` lists the remainder with candidates and the suggested security | ≤ 60 tokens a row |
| `news.get(cluster_id or news_id)` | one story: title, URL, domain, tier, times, excerpt, labels, up to five members, note ids, the security | ≤ 400 tokens; the only place with excerpt and URL |
| `news.health()` | §6 | — |
| `news.feeds_put`, `news.feeds_delete` | register and remove feeds | — |
| `news.sources_put(domain, tier)` | rate a source | — |
| `news.assign(news_id, security_id or null)` | assign by hand, or undo | — |

**The digest's cursor is at-least-once.** With `consumer`, every answer
carries a `cursor`; the consumer confirms it with `ack_cursor` on its next
call, and the server keeps the confirmed position per consumer. A call
without a confirmation reads again from the last confirmed position, so a
run that broke off loses nothing. Confirming a cursor older than the
stored position is a no-op; a cursor the server did not issue to that
consumer is refused with 422. `since` without `consumer` keeps no state.
The cursor follows `Portfolixir.DeltaCursor`'s rule: overlap, never loss.
*Why not move the position on read:* a run that fails after the read
would never see those stories again.

**Extensions:** `securities.dossier` gains a news block (count over 7
days, primary count, highest materiality, the newest primary story; about
50 tokens); `securities.update` takes `news_identity` and `news_watch`.

**Stored text is data.** Titles and excerpts are foreign text: HTML and
control characters are removed at ingest and lengths capped; invisible
characters are kept as received and spelled `[U+XXXX]` by the companion
and the screen, as ADR-0054 §4 sets for every stored text. The tools
return data, never instructions.

### 10. The human view

The operator sees what the agent sees, with no logic of its own: feeds
and their health, the stories of a security on its page, and the
unassigned and ambiguous queue with an assign action. Mocked on a board
before it is built. It ships in the sprint after the agent's surface at
the latest, as the coverage rule allows.

### 11. Two sprints

- **First:** fetching, identity and the matcher, sources, items and
  clusters, retention, health, `news.list`, `news.get`, `news.health`,
  and a **digest without labels and without a cursor** (`since` only,
  issuer and regulatory stories, aggregator stories with
  `include_unlabeled`). *Why the digest already:* without it, an agent
  reads each security with `news.list`, and the first sprint saves no
  context at all.
- **Second:** labels and the labeller's read and write, the consumer
  cursor, the upkeep tools (feeds, sources, assign), the extensions of
  §8 and §9, and the human view of §10, boarded in that sprint's planning
  PR.

### 12. Retention

Items are kept 90 days, unless promoted or linked to a note. Clusters
follow their items. Labels are kept without limit (they are small and are
the labeller's record). Feeds and sources are master data and journaled.
Excerpts are capped at 600 characters at ingest, so nothing stored is an
article.

### 13. The asks, answered and deferred (ADR-0043)

**Source of the asks:** the addendum's B3.3 entry; idea F12; the agent's
feature request of 2026-11-05 and its answer to the review the same day.

| Ask | Source | Verdict |
|---|---|---|
| Sources | B3.3 | **Answered** — §2 (four classes, registered feeds only), §3 (tiers) |
| Failure behavior | B3.3 | **Answered** — §5 |
| Retention, never a full-text archive | B3.3 | **Answered** — §12 |
| Collector health, dead visibly within a day | B3.3, F12 | **Answered** — §6, `stale` after 24 hours |
| Identity by construction, matcher never guessing | request §1 | **Answered** — §2 |
| Dedupe into stories | request §2 | **Answered** — §4, per language |
| Compact agent reads with budgets | request §3 | **Answered** — §9 |
| Delta without loss | request §3, review | **Answered** — §9, at-least-once |
| Labels from an outside model, fail-open | request §4, §5 | **Answered** — §7 |
| A token only the labeller holds, reaching only its two tools | request §4, §6 item 6 | **Answered differently** — a named token and a closed schema; no scope, ADR-0054 stands (§7) |
| Agents without `label_put` | request §6 item 6 | **Answered as a convenience** — the profiles (§7), not a boundary |
| Promote a story to a note, an event as its source | request §3 | **Answered** — §8 |
| The human view | request §0, coverage rule | **Answered** — §10, the second sprint |
| Following redirects of aggregator links | request §1, §7 item 1 | **Deferred** — §2, flip "news follow" |
| Clustering across languages | review | **Deferred** — not a goal (§4) |
| End-to-end saving of the agent's runs | request §6 | **Outside the app** — measured by the operator's agent on the real instance after the merge |

### 14. Acceptance

**In the sprint, on synthetic fixtures only** (no network, no instance
data):

1. **Identity:** `issuer` and `regulatory` fixture items land on their
   security with no exception; an `aggregator` fixture with one, none and
   several matching aliases gives `assigned`, `unassigned`, `ambiguous`;
   an alias change re-matches the last 7 days.
2. **Size:** on a 40-security fixture with 24 hours of items, the digest
   is at most 800 tokens (characters / 4), with nothing new at most 100;
   20 `news.list` rows at most 1,500; `news.get` at most 400.
3. **Dedupe:** constructed duplicates (same release from several domains,
   reworded titles) collapse to one story per language.
4. **Freshness:** with a fixture clock, an item that appears in a feed at
   time t is visible by t + the feed's interval + 5 minutes.
5. **Health:** a feed with no successful fetch for 24 hours reads `stale`.
6. **Labels:** `news.label_put` refuses any field outside its schema with
   422 naming the field; every stored label carries `model`,
   `prompt_version` and `machine_generated` true; the journal names the
   token that wrote it.
7. **Visibility:** an `issuer` story labelled materiality 0 still appears
   in the digest; an `aggregator` story labelled 1 does not at the
   default.
8. **Fail-open:** with no labels at all, digest, list and get answer
   normally.
9. **No archive:** no stored excerpt exceeds 600 characters; an item
   older than 90 days and not promoted is gone after the retention run.

**After the merge, on the real instance, by the operator's agent** — not
sprint acceptance: misassignment rate in a sample, duplicate rate per
language, the digest's median size over ten trading days, and the change
in the agent's context tokens and run time.

## Consequences

- An agent reads the morning's news per view in one call of a few hundred
  tokens and fetches the full story only for what it acts on.
- The operator sees a dead feed within a day, and an unassigned item has
  a queue instead of vanishing.
- The app makes outbound requests to hosts the operator registers. They
  pass the URL policy and the bounded client, and a feed is a new place a
  misconfiguration shows: in `news.health`.
- A label can be wrong. It can sort a primary story low but never hide
  it; it can hide an aggregator story, which `include_unlabeled` and
  `min_materiality=0` bring back.
- The catalogue gains `news_identity` and `news_watch`; the companion
  gains eight tools for the agent and two for the labeller.
- Nothing here scores a source or a label. Scoring a source by how right
  its stories turned out is F1's deferred per-source calibration.

## Choices and how to flip them

| Choice | Default | To flip |
|---|---|---|
| Aggregator redirects | `<source>` only, drop without | "news follow" |
| Intervals | 10 / 15 / 60 / 180 minutes | per feed, or a new default by comment |
| Cluster window and threshold | 72 hours, 0.8 | a setting; review after two weeks |
| Retention | 90 days | a comment on this record |
| Digest default | materiality ≥ 2, tier ≥ secondary | per call |
| Token scope for the labeller | none (ADR-0054) | a new reason, in its own record |

## Amendment of 2026-11-06: the owner's shape

**Adopted by the merge of the Sprint 26 planning PR.** The merge of #1399
on 2026-11-05 signed this record; the owner then said, on 2026-11-06,
that he was not yet sure of it, and settled it the same day: the stream is
acceptable as a **staging area**, so long as only what is really relevant
becomes lasting knowledge. In his words, stated generically: feeds are
fetched and kept 90 days, a cheaper model pre-sorts and tags them on a
schedule, and an agent picks what matters, assigns it to its security,
rates it and marks the rest as read or irrelevant, so nothing is read
twice; what lasts should explain afterwards why a price moved, and give an
outlook where it can (quarterly results, profit warnings, regulatory
items). That is §7 to §9 as signed. Four things are added, each because
the record as signed did not answer it.

### A1. The feed parser is hardened against hostile XML

§5 bounds the request and says nothing about what is done with the
answer. A feed is XML from a host the operator registered and does not
control, so the parser is a hostile-input surface in its own right, as
ADR-0021 says of a PDF. **The parser:**

- never turns an element or attribute name into an atom (Erlang's
  `xmerl` does by default, which `AGENTS.md`'s rule on atoms from external
  input forbids);
- processes no document type declaration: no external entity is ever
  resolved (no file, no URL), no internal entity is ever expanded; only
  the five predefined XML entities and numeric character references are
  decoded;
- parses at most the bounded client's byte cap, refuses nesting deeper
  than 64 and more than 5,000 items in one answer;
- reads RSS 2.0 and Atom 1.0 only.

A refusal is the feed's `last_error` (`parse_refused` with its reason) and
counts in `err_24h`; it never stops another feed. **Acceptance, beside
§14:** fixtures for an entity expansion bomb, an external entity naming a
local file and a URL, a document 10,000 levels deep and one over the byte
cap are each refused without the parser reading past the refusal, and the
atom count of the VM is unchanged by parsing 1,000 distinct element names.
The parser is a new dependency or a small parser of the app's own; the
story that builds it chooses, and a new dependency goes through the
maintenance lane's audit and is pinned.

### A2. What lasts is a research note with a headline, an event type and a tone

§8's promotion stays the only way a story becomes knowledge. The note it
writes carries a `headline`, an `event_type` and a `tone`, by
[ADR-0044's amendment of 2026-11-06](0044-security-knowledge-as-an-append-only-log.html#amendment-of-2026-11-06-a-headline-an-event-type-and-a-tone-on-an-entry),
pre-filled from the story and its active label and confirmed by the
agent's write. **The security chart draws research notes with a headline
as markers at their `as_of`, never a raw item or a story:** what the
operator sees on the chart is what someone judged worth keeping. The
markers' board comes with the second sprint's planning PR, with §10's
view.

### A3. A feed's yield is visible, and a flooding feed is capped

*Why:* the owner's worry is that an agent fills the app with feeds nobody
reads. The retention of §12 bounds how long an item stays, not how many
arrive. **Added to §6:** each feed reports `items_30d`, `promoted_30d` and
`yield_30d` (promoted stories over items, a decimal string); a feed with
at least 50 items and none promoted in 30 days carries `low_yield: true`
in `news.health` and on §10's screen. Nothing disables a feed by itself:
the operator decides. **Added to §5:** a feed stores at most 200 items in
24 hours; the rest are dropped and counted as `dropped_cap`. **To flip:**
a number by comment.

### A4. When it is built

Not in Sprint 26, which owes three screens and the privacy mode. §11's
first sprint is Sprint 27, its second, with §10's view and A2's markers,
Sprint 28. **To flip:** "News in 26".

## Amendment of 2026-11-07: what the first sprint needs, and nothing decided by order

**Adopted by the merge of the Sprint 27 planning PR.** The planning pass
for Sprint 27 read this record against the code on `main` (`d6df259`) and
ran Sprint 26's carry-forward 1 on it: for a rule that reads several
records, ask whether an id, an insertion order or a tie-break decides the
outcome, and whether a party can change it with a true record. Seven
answers were missing or would have been settled by whoever built them. None
of them books or corrects a stored money figure, so each is decided here
with its reason and flips by a comment naming its flip.

### B1. The first sprint can register what it fetches

§11 put `news.feeds_put`, `news.feeds_delete`, `news.sources_put` and the
`news_identity` and `news_watch` keys of `securities.update` in the second
sprint. Without them the first sprint ships a fetcher with no way to give it
a feed, an alias or a tier through the API, so its agent-first surface
could not be used or checked on an instance until Sprint 28. **They move
into the first sprint.** `news.assign` stays in the second, beside the
label's `suggested_security_id` it acts on. The tool count of §9 is
unchanged; four of its tools arrive one sprint earlier. **To flip:**
"news upkeep in 28".

### B2. A feed's URL is checked with name resolution, every time

`Portfolixir.Net.Http` checks a client's first request without resolving
the name, because every caller so far compiled its endpoint in. A feed's
URL is data, so **the fetcher checks it through `UrlPolicy` with name
resolution when the feed is registered and again before every fetch**:
https only, no userinfo, public addresses only; the request's allow-list is
the feed's own host, so a redirect to another host is refused (§5). The
policy's stated limit stays stated: the check and the connection resolve
the name separately, so a rebinding name with a very short lifetime can
pass between them. **To flip:** none offered; a weaker check would be a
request-forgery surface.

### B3. The same items give the same stories, in any order

§4 promises determinism and names no rule. Taken literally ("an item joins
a cluster"), the result would depend on the order items are fetched: with
A like B and B like C but A unlike C, the first-fetched decides. **The
rule:** within one security (or category) and one language, two items are
the same story when their `published_at` lie within 72 hours of each other
and their normalized titles are equal or their title tokens reach a Jaccard
similarity of 0.8; **a story is a connected component of that relation**.
An item that links two stories merges them; the surviving story is the one
whose earliest member is earliest by (`first_seen_at`, canonical URL),
**never by id**. The representative is the member of the best tier, then
the earliest clamped `published_at` (B4), then the smallest canonical URL.
A test books the same fixture items in shuffled orders and compares the
stories. **The one order that still decides** is the daily cap of A3: a
feed past 200 items in 24 hours keeps its first 200 in the feed's own
order. That order belongs to the one feed that floods, and touches no other
feed's items. **To flip:** "news first match" (an item joins the first
story it matches, with the order stated).

### B4. The server's clock decides what is new and what expires

`published_at` is what the feed claims. **A claim later than
`first_seen_at` is clamped to it**, so a future date cannot make an item
the newest. **`since` (the digest and `news.list`) and the retention of
§12 read `first_seen_at`**, the server's clock, never the claim: an item
published at 09:00 and fetched at 10:00 is not lost to a `since=09:30`
call, by `Portfolixir.DeltaCursor`'s rule (overlap, never loss). **An item
whose claim is older than the retention window is not stored**
(`dropped_old`, counted), so a feed that keeps listing old items does not
refill what retention removed. **To flip:** none offered; the claim is the
feed's, the clock is the operator's.

### B5. An aggregator's item is never primary

An `aggregator` item takes its domain from its own `<source>` element (§2),
which is a claim inside the item: a sloppy or hostile aggregator could name
a primary domain and make its item the story's representative, and later a
note's `primary` `source_quality` (§3). **An `aggregator` item's tier is at
most `secondary`**, whatever its domain's tier; `primary` comes only by
construction, from an `issuer` or `regulatory` feed. A `blocked` domain is
still dropped. **To flip:** "news trusts source".

### B6. Where the scheduler runs

§5 says "opt-in in production". **The scheduler runs where the quote sync
runs** (production; development with `PORTFOLIXIR_BACKGROUND_FETCH`; never
in tests), and **an enabled feed is the opt-in**: with no feed registered
it makes no request. *Why:* a second switch beside the feed's own `enabled`
is one more setting to forget, and a feed nobody registered reaches no
host. **To flip:** "news switch" (its own environment variable, off by
default).

### B7. What the journal records

Feeds, sources, a security's `news_identity` and `news_watch` are master
data and journaled, as §12 says, with the token that wrote them. **Items
and stories are not journaled**: they are a staging area that retention
empties, written by a registered system job, at up to 200 per feed and day.
The fetcher and the retention run are registered as system jobs and
self-scheduling processes in the backstop that lists them
(`scope_b5_system_writers_and_schedulers_test.exs`).

### B8. The gate's sentence and its backstops

`AGENTS.md` lists "data acquisition beyond quotes and FX (B3.3)" as gated,
and the gate registry pins that sentence. This record opened B3.3 for news
feeds only. **The sentence becomes "data acquisition beyond quotes, FX and
ADR-0056's news feeds (B3.3)"**, changed in the sprint PR in the same commit
as the registry, never ahead of the code. **The outbound backstop
(`scope_b2_outbound_chokepoint_test.exs`) registers the fetcher** with its
purpose and, since its hosts come from stored feeds and not from the
source, an `any:` reason naming this record and B2; the environment
variable `PORTFOLIXIR_NEWS_USER_AGENT` is listed with its reason. These
are registrations a reviewer reads, not a weakened gate: every other caller
keeps its literal allow-list.

## Amendment of 2026-11-08: what the closing act found

**Adopted by the merge of the Sprint 27 sprint PR**, as the closing act of
Sprint 26 amended ADR-0057 inside its own sprint PR. The closing act's five
lenses (correctness, edge cases, a hostile feed host, order, the agent)
read the built layer against this record and found six places where the
record, built as written, lets a true item or an honest gap mislead. None
books or corrects a stored money figure, so each is decided here with its
reason and flips by a comment naming its flip.

### C1. A primary story is anchored: lower-tier items cannot chain two primary stories together

**Found by the order lens:** with B3 as written, ten true items from one
aggregator, each one word away from the last, link an issuer's quarterly
results (published at 0 h) and its chief executive's resignation (24 h)
into one story whose representative is the older one. The newer primary
headline disappears from the digest and the list, and the story id the
agent held for it answers "not found". §7 already says a label never hides
an issuer or regulatory story; a chain of lower-tier items must not either.
**The rule:** within a scope and language, the B3 relation first builds the
components of the `primary` items alone, and the lower-tier items form
components among themselves by B3. A lower-tier component that the
relation links to one or more primary components joins exactly one of
them, whole: the one whose survivor key (C2) is smallest; the other
lower-tier components are stories of their own. (So a secondary item
linked to a primary one and an awareness item linked only to that
secondary one stay one story, as §4's fixture expects; a chain linked to
two primary stories joins one of them.) The result is still a function of
the set of items, so no order decides it.
**To flip:** "news primary chains" (B3 as written).

### C2. A story's survivor is chosen by tier first

**Found by the order lens:** within one scheduler tick every item shares
`first_seen_at`, so B3's survivor key fell to the canonical URL, which an
attacker chooses: a story of the attacker's items at `https://a.example/…`
survived a merge with a primary story, and the id the agent held for the
primary story was deleted. **The survivor key becomes (best tier present,
earliest `first_seen_at`, smallest canonical URL)**, never an id. The
representative's rule (B3) is unchanged. **To flip:** "news survivor by
time".

### C3. `since` reads the moment an item entered its scope

**Found by the correctness lens:** an aggregator item that the 7-day
re-match (§2) assigns after its first sight kept its old `first_seen_at`,
so every `since` read after that sight skipped it, against B4's "overlap,
never loss". **Each item carries `scope_at`, the server's time it entered
its security's or category's scope** (its first sight for an item bound by
construction or matched at ingest; the time of the assignment for one
matched later, re-matched, merged or left the only candidate). `since` (the
digest and `news.list`) reads `scope_at`; retention keeps reading
`first_seen_at` (B4), and the 90 days do not restart. **To flip:** none
offered; the alternative loses items.

### C4. Yield is not answered before promotion exists

**Found by the agent's lens:** A3's `yield_30d` and `low_yield` count
promoted stories, and promotion (§8) arrives with the second sprint. Until
then every feed with 50 items reads `low_yield: true` on its first day, in
A3's words "a feed nobody reads", beside a delete tool. **Until §8 is
built, `news.health` leaves `yield_30d` and `low_yield` out and says why
in one field** (`yield: "not_measured_until_promotion"`); `items_30d` and
`promoted_30d` stay. The second sprint answers them as A3 says. **To
flip:** "news yield now".

### C5. The digest says what it left out, and its default fits its budget

**Found by the agent's lens:** with news only from an aggregator feed, the
default digest answered every security as quiet, the false calm §6 exists
to prevent; and at the default `max_rows=40` the 800-token budget holds
only while about 13 securities have news. **The digest carries `hidden`,
the count of aggregator and thematic stories it left out by
`include_unlabeled`, and a security with only hidden stories is not counted
quiet. Its `max_rows` defaults to 12**, with `truncated` beyond, so the
budget of §9 holds at the default; a caller may still ask for up to 40.
The budgets of §9 and §14 are measured on the text the companion returns,
with invisible characters spelled as ADR-0054 §4 spells them, and the
server clips titles and excerpts in lists and the digest by that spelled
width. **To flip:** a number by comment.

### C6. The operator's contact goes to the SEC only

**Found by the security lens:** §5 sets the user agent from
`PORTFOLIXIR_NEWS_USER_AGENT` because the SEC asks for a contact address in
it; sent to every feed host, it tells each aggregator and newsroom the
operator registers who the operator is. **The variable is sent to
`sec.gov` and its subdomains only; every other host receives the app's own
user agent.** A host name with a trailing dot is read without it, so
`www.sec.gov.` cannot skip the requirement or the pace. **To flip:** "news
agent everywhere".

### C7. What `err_24h` counts

**Found by the correctness lens:** errors are counted per feed and server
day, so `err_24h` sums today's and yesterday's rows and can include up to
48 hours. It stays so, and the health read and its tool description say
"errors of the server's current and previous day". Counting per hour would
add rows for a figure that only needs to read "not zero". **To flip:**
"news errors hourly".

## Amendment of 2026-11-09: what the second sprint decided

**Adopted by the merge of the Sprint 28 sprint PR**, as the amendment of
2026-11-08 was adopted by Sprint 27's. The second sprint (§11) built §7 to
§10, A2, A3's yield and the end of C4, and its closing act attacked them.
Where this record left an answer open, the story that met it decided and
its commit and module documentation say why; this amendment collects
those answers, so the record and the code say the same thing. None books
or corrects a stored money figure, so each is decided here with its
reason and flips by a comment naming its flip; where none is offered, the
alternative loses a story or opens a hole.

### D1. A label: replaced in place, checked without a foreign key, closed to the last character

- **The same `(cluster_id, model, prompt_version)` replaces the label in
  place**, a full replacement (an optional field the put leaves out is
  cleared), journaled as an update whose before-image is the old label; a
  put equal to the stored label writes and journals nothing. *Why:* a
  labeller that corrects itself without a new prompt version is believed,
  and the journal keeps what it withdrew; ignoring the second put would
  keep a label its own author took back. **To flip:** "news labels
  append".
- **No foreign key on `cluster_id` or `suggested_security_id`.** Labels
  are kept without limit (§12) while stories age out and merge away, and a
  suggestion must never block a security's merge or delete. The write
  checks that both exist and holds their rows `FOR KEY SHARE` until it
  commits. A label can outlive its story; it then names nothing a read
  shows. **To flip:** none offered.
- **`confidence` is a decimal string** from 0 to 1 with at most four
  places, checked against its own truncation, never rounded; a JSON number
  answers "must be a decimal string", as every decimal the API takes
  (ADR-0003). **`model` and `prompt_version` are identifiers:** 1 to 64
  letters, digits or `. _ : / @ + -`, starting with a letter or a digit,
  no invisible character (ADR-0054 §4). A digest consumer's name has the
  same shape (D3).
- **`thesis_note_id` names only the thesis the labeller's read offers**
  (closing act, AT2): the story's security's current thesis while it is
  intact, and `clause_idx` counts that thesis's clauses. §7 offers "the
  active thesis"; a label that names a superseded or withdrawn one ties a
  story to a condition nobody holds any more.
- **The wrapper sent in the query is refused** (AT3): `label` (and
  Sprint 27's `feed` and `source`) in the query string beside a JSON body
  answers 422 naming it. The query's fields had been dropped in silence
  while the put answered 201; a closed schema that drops is not closed.
- **The labeller's read** answers 10 stories by default and 25 at most,
  six clauses per thesis with `more` counting the rest, and holds 6,000
  tokens at the default on the companion's text with a 40-security
  universe. **The universe is not bounded:** it is the news universe and
  the rows' securities, so an instance that watches far more pays more
  per call. Recorded, not capped. **To flip:** "news universe paged".
- A label write moves no derived figure (`BlastRadius`): it sorts reads
  and is read nowhere else.

### D2. The reads take one prompt version, and one active label of it

- **`prompt_version` is a parameter of `news.list`, `news.get` (a story)
  and `news.digest`; without it, the version of the label created last.**
  *Why one version per read:* materialities from two prompts are not on
  one scale, so one answer never compares them; a story the new prompt has
  not labelled reads as unlabelled and comes back in `news.unlabeled`.
  *Why creation, not update:* a correction to an old version's label does
  not move the reads back to that version. **To flip:** "news label per
  story newest".
- **The active label** (§7's "newest one per prompt_version") is the one
  written last, by `updated_at`, then the smallest model name, never an
  id.
- **To hold §9's budgets with the widest label** (a 64-character prompt
  version, materiality 3, the longest event types), the digest names **at
  most two event types** per row, the most material first, and cuts its
  top story's title at **50** characters (C5 cut at 100): 754 of 800
  tokens measured; the list 1,452 of 1,500; `news.get` 362 of 400.
  **`news.get`'s label leaves out `model` and `prompt_version`** (the
  version is the read's, and both are in the journal), and the excerpt,
  cut last, gives way to it. **To flip:** a number by comment.
- **Measured with every id, count and tier at its widest** (closing act,
  AG1: the figures above held with id 1 and a primary tier, and the widest
  answer read 908 of 800), **the digest defaults to `max_rows=10`** (C5's
  12) **and cuts its top title at 45, a list row's title is cut at 80 on
  the API** (the screens keep 160) **and a story's members' domains at
  28**: the digest 747 of 800, its consumer's first page 765, a list row
  56 of §9's 60 and 20 rows 1,197 of 1,500, `news.get` 388 of 400; an
  ambiguous item row adds its candidates' ids, about five tokens each, and
  is not held to the 60. **`fields=std` cuts a row's link at 300** as
  `news.get` does (AG2: it answered each whole, 12,067 tokens for 20 rows
  of 2,048-character links), so a std row holds 150 tokens and 20 rows
  3,045, and an item row's domain is cut at 40 as a story row's.
  **To flip:** a number by comment.
- **The count is named `unlabeled`**, where §7 wrote `n_unlabeled`: §9's
  compact rule names fields by what they count.
- `min_materiality` on `news.list` defaults to 0; above 0 it also leaves
  out the unlabelled aggregator and thematic stories, and with
  `cluster_id` or `assignment` it answers 422 (it reads stories). No read
  takes `tone` (§7).
- **`tier_min` is not a digest parameter.** §9's signature lists
  `tier_min=secondary`; the digest built in Sprint 27 never took it, and
  it answers 422 naming it, while `news.list` takes it. That is recorded
  here as the state: what the digest counts is decided by the feed's class
  and the label (§7), and its `hidden` count says what that rule left out
  (C5); a tier floor beside it would leave out stories `hidden` does not
  count, the false calm C5 removed. A primary story comes only from an
  issuer or regulatory feed (B5) and always counts. **To flip:** "news
  digest tier_min" (the floor, its omissions counted in `hidden`).

### D3. The consumer cursor (§9)

- **A consumer is a row of `news_digest_consumers`, not journaled.**
  `Portfolixir.Journal.Allowlist`'s non-journaled tables grow by this one
  table, beside B7's staging area, and the allowlist's test says growing
  that list takes an amendment of a record: this is it. *Why:* the
  position is a reader's bookmark that every confirmed read moves, and it
  changes nothing any other reader is answered; journaling it would write
  an entry per agent run and record no decision.
- **A cursor is `<unix seconds>~<tag>`**, the tag an HMAC-SHA-256 over the
  consumer's row id, its name and the position, cut to 16 bytes, under a
  **key derived from `SECRET_KEY_BASE`** for this one purpose. Nothing
  secret is stored: a stored key would be a credential-shaped column, the
  thing the stored-credentials backstop (B1) refuses. A changed
  `SECRET_KEY_BASE` refuses every earlier cursor; the consumer reads once
  without `ack_cursor`, from its confirmed position, and loses nothing.
- **The position is the answer's moment** (the digest's `as_of`, a little
  early, so a story may repeat and never be skipped). **A new consumer
  starts 24 hours back**, the stateless default window, and its start
  counts as confirmed. **A confirmation is one `GREATEST` update**: an
  older cursor changes nothing, and of two racing confirmations the newer
  stays, whichever commits last.
- **Refusals** (422, naming the parameter): `since` beside `consumer`;
  `ack_cursor` or `page` without `consumer`; `page` beside `ack_cursor`; a
  name that is not an identifier; a cursor not issued to that consumer
  (forged, altered, another consumer's, or one issued before the consumer
  was deleted and named again); a new consumer beyond the cap.
- **A consumer is not bound to a token.** Every token carries the same
  authority (ADR-0054 §1), and a name is a run's bookmark, not a
  principal. `news.digest` stays read-only in every profile: the position
  it moves is the consumer's own. **To flip:** "news consumer per token".
- **At most 32 consumers**, created one at a time under an advisory lock
  so the cap holds. **The daily retention deletes a consumer not
  confirmed for 90 days** (its `updated_at`: its last confirmation or,
  never confirmed, its creation); named again it starts anew, 24 hours
  back. *Why a cap:* an agent that names a fresh consumer each run would
  grow the table without bound and read the stateless 24 hours in
  disguise. **The residual:** a careless agent can fill the cap and hold
  it for 90 days, and no API path removes a consumer; stored consumers keep
  reading, a new name is refused, and the stateless `since` digest still
  answers. **To flip:** "news consumers delete tool".
- **A consumer's truncated digest is paged** (closing act, AT5): with
  `consumer`, an answer cut by `max_rows` carries `next_page`, a page
  token, and no cursor; sent back as `page` it answers the next rows, and
  only the last page carries the cursor, at the first page's moment, so a
  confirmation never passes a row an answer left out and what arrived
  while the consumer paged reads after it. A page token names the
  consumer's position, that moment and the place of the last row
  answered, signed under a key of its own purpose, so neither passes for
  the other; paging moves nothing; a page of a position the consumer has
  confirmed past answers the first page from the new one with
  `restarted: true`. Rows tie, after their materiality and their top
  story's tier and publication, by security id: a link would not fit a
  page token. `since` keeps `truncated` and `more`.
- **A label written after the position makes a story new** (closing act,
  AT6): for a consumer a story is new when it entered its scope after the
  position, or when its active label of the read's prompt version was
  written or replaced after it. An aggregator story hidden as unlabelled
  when the consumer confirmed is otherwise lost once a label shows it.
  The price is a story read again when its label is replaced. The
  stateless `since` reads `scope_at` alone: its caller chooses the window.

### D4. `news.assign`

- **The route is `PUT /api/v1/news/items/:id/assignment`** with
  `{"assignment": {"security_id": id or null}}`, `security_id` required.
  The tool is a replace-shaped write (the previous security sent back
  restores it): in `book` and `full`, not in `read` or `label`.
- **Aggregator items only.** An issuer or regulatory item is its feed's
  security's, a thematic item its feed's category's, by construction
  (§2); assigning one answers 422 naming `news_id`.
- **`null` is the matcher's answer now**: one security named assigns it,
  none leaves it `unassigned`, several `ambiguous` with them. *Why not
  "the assignment before the hand's":* nothing stores who assigned an
  item, the matcher's answer is a function of the title and the aliases,
  and the journal keeps every before-image. An assignment the item already
  has writes and journals nothing; any other is one `news_item` update,
  journaled under the actor: B7's exception for a hand write.
- **The scopes follow in its transaction:** the scope the item left and
  the one it entered are reclustered in full, as a merge does, and the
  item enters its new scope at the assignment (`scope_at`, C3).
- **Securities are locked first** (closing act, AT4): `FOR KEY SHARE`, in
  id order, on every security the write may touch (the item's own, its
  candidates, the target or the matcher's names), before the matcher's
  advisory lock, the scope's and the item's. A security merge holds both
  securities `FOR UPDATE` before it writes their news items, so the old
  order deadlocked in both directions. An item that moved between the
  read and the lock is attempted again, at most three times
  (`Portfolixir.LockTable`, row 21).
- **`scope_at` is stamped after the locks** (AT8): an assignment that
  waited enters its scope after what it waited for, so a consumer that
  confirmed meanwhile still reads it. An ambiguous item whose set of
  candidates changes enters its remainder anew, in the one rule the
  matcher's re-match and `news.assign` share.
- **A label after a split: the limit, recorded.** A label belongs to a
  story id. When an item leaves a story (an assignment, a re-match,
  retention) and the story splits, the label stays with the part that
  keeps the id, the part holding the survivor key's member (C2), which
  need not hold the representative whose title the labeller read; the
  other parts are new stories without a label and return in
  `news.unlabeled`. A misplaced label can sort an aggregator story; it can
  hide no issuer or regulatory story (§7). **To flip:** "news relabel on
  split" (a split drops the label of the part that keeps the id).

### D5. An open question: no suggestion reaches the queue

§7 says `suggested_security_id` "shows beside an `unassigned` or
`ambiguous` item". **It cannot as built:** a label is a story's, and an
unassigned or ambiguous item sits in no story (§4 clusters within a
security's or a category's scope), so no label reaches it. The queue's
rows and `news.list`'s remainder carry no suggestion, and the page draws
none (the board did). Until this is decided, an assignment is the agent's
or the operator's judgment from the title and the candidates. **Two
options, for the owner:**

- **(a) the labeller labels remainder items**: `news.unlabeled` offers
  them and `news.label_put` takes a `news_id` in place of a `cluster_id`;
  a second key on the label and a wider closed schema, attacked again.
  "news suggest by item" picks it.
- **(b) the remainder forms stories of its own**, in an "unassigned"
  scope, so a label reaches them as any story; it changes §4's scopes and
  what the digest counts as `unassigned`. "news remainder stories" picks
  it.

### D6. From story to knowledge (§8, A2)

- **What the server fills** for `notes.append` with `cluster_id`:
  `kind` `evidence` (`event_result` may be sent; another kind answers 422,
  a story is a finding or an outcome, not a thesis); `as_of` the
  representative's publication day (clamped, B4) on the instance's
  calendar; `source_url` the representative's link, or, when it is longer
  than an entry's 255 characters, the first member's that fits in
  `news.get`'s member order; `source_quality` by §3's rule over every
  member (a `primary` member gives `primary`, two or more distinct
  `secondary` domains `secondary_multi`, one `unverified`, else
  `awareness`); `headline` the representative's title cut at 80
  characters on a word boundary as the companion spells them; `event_type`
  and `tone` from the story's active label of the newest prompt version (a
  `noise` label gives no event type), the entry keeping that label's id as
  `news_label_id` only when it took one of them.
- **What the caller may override:** `kind`, `headline`, `event_type` and
  `tone`, a `null` leaving one out; the write is the confirmation NFR-10
  asks for. **What belongs to the story:** `as_of`, `source_url` and
  `source_quality`, each refused with 422 beside `cluster_id`: they state
  the provenance by rule, and a write may not claim a better source than
  the story has. A title holding an invisible character is refused as a
  headline (ADR-0054 §4), naming `headline`; the caller sends its own.
- **Every member is promoted** and names the entry, so the story's
  sources outlive retention (§12). **A second promotion appends another
  entry**, and the story names both: the log is append-only, and a story
  may carry a finding and later its outcome. The write runs under the
  story's scope lock with its members locked.
- **`events.create` takes an item's `news_id`**, not a story's: an event
  names one source. The item's link becomes `source_url` and its tier
  `source_quality` (`secondary` as `unverified`); `source_url` or
  `source_quality` beside it, an item of another security and a link over
  255 characters answer 422. The item is not promoted: an event is a
  mutable calendar fact (ADR-0048), and what lasts from news is an entry
  (A2).
- **The entry's columns:** four nullable columns on `security_notes`,
  `headline` (1 to 80 code points), `event_type` (§7's set without
  `noise`), `tone` and `news_label_id`, each with a CHECK, the first
  three on `evidence` and `event_result` entries only. `news_label_id`
  has no foreign key: it is provenance, and the label it names can be
  replaced in place (D1); the journal keeps every version.
  [ADR-0044's amendment of 2026-11-06](0044-security-knowledge-as-an-append-only-log.html#amendment-of-2026-11-06-a-headline-an-event-type-and-a-tone-on-an-entry)
  is built with them.

### D7. Yield, the dossier and the registry

- **A3 is answered and C4 retired.** `news.health` answers `yield_30d`,
  `promoted_30d` over `items_30d` as an exact decimal rounded half-up to 4
  places and left out for a feed without items, and `low_yield` at 50
  items or more in 30 days with none of its stories promoted
  (`promoted_30d` counts each promoted story its items are in once). C4's
  placeholder `yield` is gone. Nothing disables a feed by itself.
- **The dossier's news block** (§9): `count_7d`, the stories with a member
  that entered their scope in the last 7 days (as `news.list`'s `since`
  reads them), `primary_7d`, `max_materiality` of their active labels of
  the newest prompt version, and `newest_primary`, the newest primary
  story **at any age** with its title cut at 50, so a quiet security and a
  dead feed read apart (§6). About 50 tokens on the companion's text,
  which answers the dossier as compact JSON.
- **`news.registry`, a ninth tool for the agent** (§9 counted eight), by
  the coverage rule: the page's Feeds and Quellen tabs showed stored feed
  URLs, bindings and rated sources that no read listed, a capability for
  the human only. `GET /api/v1/news/registry` lists them, each row what
  `news.feeds_put` and `news.sources_put` answer without the interval, in
  pages of 40 (at most 100) of at most 4,500 tokens, and the page reads
  through the same function. In `read`, `book` and `full`, not in
  `label`. `news.list`'s `std` row adds its representative's domain, cut
  at 40, the source the security's tab shows.

### D8. The human view (§10, A2)

- **The page „Nachrichten“** in the main navigation after Wertpapiere
  (ADR-0022 names News a top-level area), with three tabs, each an
  address: Meldungen (the health line, the queue with „Zuordnen“, the
  digest per security), Feeds and Quellen. **No logic of its own:** each
  region reads through the function the API's read answers from, with
  its defaults. The digest is read **without a consumer**, so opening the
  page moves no agent's position, and over **the news universe**, not a
  view; the queue shows the first page of each kind (20). „Zuordnen“ is
  the view's one write, the function `news.assign` calls, journaled under
  the operator. **Feeds and sources are shown, not edited** (Sprint 28
  plan D-3): they stay with the API and the companion. **To flip:** "Feeds
  am Bildschirm pflegen".
- **The security's tab „Nachrichten“** after Research: its stories as
  `news.list` reads them, a label marked „maschinell“; „Ins Research-Log“
  opens the entry form pre-filled with the very proposal D6 writes, and
  only its save writes (NFR-10). A field left as proposed is not sent, so
  the server fills it as for the agent. A kept story reads „übernommen“;
  a second promotion is the API's.
- **The pins** (A2): a research entry with a headline that no later entry
  supersedes is drawn at its `as_of` as a pin at the chart's top edge, its
  colour and glyph the tone; never a story or an item. **One pin per day**,
  with a count and a mixed tone when several notes share it: two heads on
  one x would hide each other. A superseded entry is not drawn, since a
  pin cannot say it was replaced. „Notizen anzeigen“ beside „Transaktionen
  anzeigen“ toggles them, and the Übersicht's small chart has one toggle
  under it. The privacy mode keeps them: they name no amount.

### D9. The asks after the second sprint (ADR-0043)

§13's table stands; the second sprint changes these rows.

| Ask | Source | Verdict |
|---|---|---|
| Labels from an outside model, fail-open | request §4, §5 | **Answered and built** — §7, D1, D2 |
| A token only the labeller holds, reaching only its two tools | request §4, §6 item 6 | **Answered differently, built** — a named token, the `label` profile and a closed schema (§7, D1) |
| Agents without `label_put` | request §6 item 6 | **Built as a convenience** — `read`, `book` and `full` do not list it |
| Delta without loss | request §3, review | **Answered and built** — the consumer cursor, paged when cut (D3) |
| Promote a story to a note, an event as its source | request §3 | **Answered and built** — D6 |
| The human view | request §0, coverage rule | **Answered and built** — D8; feeds and sources stay agent-side (D8) |
| A label's suggested security beside the queue | §7 | **Deferred** — an open question with two options (D5) |
| Following redirects of aggregator links | request §1, §7 item 1 | **Deferred**, unchanged — "news follow" |
| Clustering across languages | review | **Deferred**, unchanged — not a goal (§4) |
| End-to-end saving of the agent's runs | request §6 | **Outside the app**, unchanged — measured on the real instance |

### D10. An open question: which prompt version the reads follow

D2's default reads the version of the label **created last**. With one
labeller that is the version it moved to. **With two labellers on
different prompt versions** (two models compared, or an old script left
running beside a new one), whichever created a label last decides, so
every read without `prompt_version` flips between their materialities
from one call to the next, and the digest's rows and `hidden` count move
with it. Found by the Sprint 28 closing act's lenses. Until it is
decided, run one labeller's prompt version at a time, or name
`prompt_version` on every read. **Two options, for the owner:**

- **(a) a configured active prompt version**: a setting names the version
  the reads use by default, changed by the operator or the agent, and a
  version nobody named is read only when a call names it. "news active
  prompt version" picks it.
- **(b) per read only**: a read without `prompt_version` reads no label
  (as with none stored, §7's fail-open), and a caller that wants labels
  names its version. "news prompt per read" picks it.

§13's table gains no row: this is a question about D2's default, not an
ask.

## Amendment of 2026-11-12: what the first fill found

**Adopted by the merge of the Sprint 29 planning PR** (ADR-0026 step 1, as
amended on 2026-10-08), **built in Sprint 29** (#1443, #1444). The
operator's agent registered the first feeds and sources and ran the first
fetch on 2026-11-10; its report was triaged the same day
(`_bmad-output/planning-artifacts/feedback-triage-2026-11-10.md`), and the
owner adopted every recommendation of its Part 3. The parser's half (P1,
P2) was built at once (#1442, merged as #1445) and changes no decision
(A1 states no encoding). Two items change this record: E1 (C2 of the
triage) and E2 (C1). Neither books or corrects a stored money figure.

### E1. A rating by hand re-rates the stored items it covers (§3, B5, D6)

§3 rates a domain, and ingest stores each item with the tier its domain
had at that moment (`Ingest.tier_and_block/2`). Until now a later rating
changed nothing stored: an item kept the tier it arrived with, and
promotion turns stored tiers into an entry's `source_quality` (§3's rule,
D6), which the caller may not override. So a domain rated **down or
blocked** after its items were stored still promoted at its old tier, and
the append-only research log (ADR-0044) kept an entry claiming a better
source than the operator's table now allows, permanently. The other
direction (rated up) understated.

**The rule.** A write to `news_sources` that changes a row's stored tier
re-rates, **in the same transaction**, every stored item that is **not
promoted** and whose domain the row now decides:

1. **Which items:** an item's domain equals the row's domain or is a
   subdomain of it, and no longer row decides it (§3's longest-suffix
   rule, `Sources.lookup/1`). A more specific row elsewhere keeps its
   items.
2. **Their new tier:** `Sources.tier(class, rated)` exactly as ingest
   computes it, B5's cap included: an `aggregator` item is at most
   `secondary`; an `issuer` or `regulatory` item stays `primary` unless
   the domain is `blocked`.
3. **A newly `blocked` domain's unpromoted items are removed**, as ingest
   would not have stored them (§3), and counted in the journal entry
   (below). A later fetch that lists them again drops them at ingest and
   counts them `dropped_blocked`, as for any blocked item; no tombstone is
   needed.
4. **Each touched story's representative is chosen again** by C2's rule
   (best tier, then `first_seen_at`, then URL), so a story whose best
   member lost its tier is represented by the member that now ranks
   first. Removed items leave their stories through
   `Stories.remove/5`, as retention's do (§12): a story left without a
   member is deleted, one that a removed item held together splits. C1's
   anchoring is read again for each touched story, since an item that
   was `primary` may no longer be. Labels are kept, as §12 keeps them.
5. **Promoted items keep their tier.** The entry they name is written, and
   the log is never rewritten (ADR-0044). The item's stored tier is the
   provenance of that entry; changing it would make the item and the
   entry disagree about the same moment.
6. **The journal entry** of the write (B7) names, beside the row's prior
   and new tier, the count of items re-rated, the count removed, and the
   count left untouched because promoted.

**Which writes.** Every write that changes a row's stored tier: a hand
write (the operator or the agent), and a seed write onto a domain with no
hand row. **A seed write onto a hand row stays a no-op** (§3: a correction
by hand is never overwritten), so it changes no tier and re-rates
nothing. *Why seed writes too:* a seed that changes a default after items
are stored would otherwise leave the same frozen tier this amendment
removes; the owner's answer named the hand write, the case that occurs,
and this is the same rule applied to the other writer. **To flip:** "news
retier hand only".

**Order** (the Sprint 26 retrospective's first carry-forward):

- *A fetch storing items while a rating is written:* the rating's
  transaction and ingest's tier read serialize, so an item is either
  stored before the re-rating (and re-rated by it) or after it (and reads
  the new tier). The build picks the mechanism (a lock both paths take in
  a registered order) and pins it with an order test that interleaves
  the two; what must not happen is an item stored with the old tier after
  the re-rating committed.
- *A promotion while a rating is written:* promotion runs under the
  story's scope lock with its members locked (D6); the re-rating takes the
  touched stories' locks in the order registered for `news.assign` (D4).
  Whichever commits first wins: a member promoted first keeps its tier; a
  member re-rated first is promoted at its new tier.
- *Two ratings of overlapping domains* (`example.com` and
  `markets.example.com`): each re-rates only the items its own row
  decides after its write, so the result depends on the rows, not on
  which write came first.

*Why at write and not at read:* reading the tier at query time was
weighed and not chosen. It moves the digest's tier filter, each story's
representative and C1's anchoring into every read, and a story's
representative would change between two reads without a write the
journal names. **To flip:** "news tier at read".

### E2. An entry's link holds what the parser accepts (D6)

The parser accepts links of up to 2,048 bytes; `security_notes.source_url`
and `security_events.source_url` held 255 characters, so D6 fell back to
the first member whose link fits and answered 422 when none did.
Aggregator redirect links are often 250 to 400 characters, so most
aggregator stories could not become an entry: a flow that cannot be
completed (S2).

**`source_url` on both tables is widened to 2,048 characters**, the
parser's own cap: one migration, no row rewritten, the two changesets'
length validation and the companion's descriptions with it. D6's two
references to 255 characters read 2,048: the representative's link is
used when it fits, else the first member's that fits in `news.get`'s
member order, else 422 naming `source_url`. **"News follow" stays
deferred** (§2, §13, D9): following the redirect would make the app
request a host it did not choose, once per item, and that reason is
unchanged. Where a screen prints an entry's link in full, it is boarded
before it is built; the Research tab's entry (the Sprint 29 plan) shows
the link's domain and opens the link, and prints no link in full.

### E3. The asks of the first fill (ADR-0043)

| Ask | Source | Verdict |
|---|---|---|
| Read ISO-8859-1, US-ASCII and a UTF-8 BOM | triage P1, P2 | **Answered and built** — #1442 (merged as #1445), no change to this record |
| An entry for a story whose links are all long | triage C1 | **Answered** — E2 |
| A rating after ingest reaches the stored items | triage C2 | **Answered** — E1 |
| Name the refused redirect's host in `last_error` | triage R1 | **Recorded** — a line on "Polish: API and MCP" (#1356), S3 |
| Resolve aggregator redirects at ingest | the report's premise | **Deferred**, unchanged — "news follow" (§2, D9) |

D5 and D10 stay open questions, unchanged by this amendment.
