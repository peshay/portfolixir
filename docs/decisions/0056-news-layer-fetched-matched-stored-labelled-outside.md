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
  merge of the Sprint 27 planning PR (see "Amendment of 2026-11-07" at the
  end). The merge opens gate B3.3
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
