---
layout: docs
title: "ADR-0059: The chain source — block heights and block times read from the chain, for halvings and nothing else"
description: "Decision for gate B3.3, narrowed to one chain source (idea I12, FR-58). Portfolixir reads the Bitcoin block chain's tip height and the timestamps of single blocks over the public Esplora REST API (mempool.space, blockstream.info as an independent fallback, or one base URL the operator sets for an own instance), GET only, no credentials, nothing that can act. A security is bound to a registered chain by the operator or an agent; past halvings at k times the chain's interval become confirmed events of a new kind halving with source quality primary, and the next one is an unconfirmed window between the recent block time and the protocol's target, refreshed daily. A source that has not answered for 24 hours reads as stale. The halving interval is a registered protocol constant, never detected. No transaction, fee, mempool, address or price data is read."
---

# ADR-0059: The chain source — block heights and block times read from the chain, for halvings and nothing else

- **Status:** Accepted. Adopted by the merge of the Sprint 29 planning PR
  (ADR-0026 step 1, as amended on 2026-10-08: the merge is the signature).
  **Built in Sprint 30**, not 29 (the Sprint 29 plan, D-2). The merge opens gate
  B3.3 **for this one chain source only**; every other kind of acquisition
  (bank, broker and wallet sync, F13; CPI and other series; any other chain
  data) stays behind it, as ADR-0056 left it for everything but news feeds.
- **Date:** 2026-11-12
- **Answers:** gate B3.3 for halvings (the addendum's "Parked, with
  reasons"); FR-58 (`epics.md`, the halving half); idea I12
  (`_bmad-output/planning-artifacts/ideas.md`), the owner's wish of
  2026-11-10 for "a connection to the block chain itself as the source of
  halvings, the most genuine source there is", and its triage the same day,
  which named this record "the chain source that opens gate B3.3 for it".
- **Builds on:** [ADR-0056](0056-news-layer-fetched-matched-stored-labelled-outside.html),
  the first record that opened B3.3, and its amendment of 2026-11-07 (B2's
  URL check, B6's scheduler placement, B7's journal, B8's gate sentence and
  backstop registrations); `Portfolixir.Net.Http` and
  `Portfolixir.Net.UrlPolicy` (#762, #763); [ADR-0048](0048-security-events-as-first-class-objects.html)
  and its [amendment of 2026-11-12](0048-security-events-as-first-class-objects.html#amendment-of-2026-11-12-a-halving-is-an-event-and-the-chain-writes-it),
  which this record adopts together with it (a new event kind `halving`, a
  `chain_height` field, the one system writer); ADR-0044's `source_quality`
  vocabulary; [ADR-0005](0005-quote-provider-split.html) (quotes and search
  stay where they are: nothing here is a price).
- **Ladder:** none. A halving date is a recorded fact and an estimate of a
  calendar date, not a metric. What is computed from the halvings is
  [ADR-0060](0060-halving-cycles-tops-and-lows-by-drawdown-projected-as-a-band.html)'s.
- Following [ADR-0043](0043-a-gate-closing-adr-names-its-asks.html), §14
  lists each ask as answered or deferred. §13 is the adversarial pass the
  Sprint 26 retrospective asks of a rule that reads several records.

## Context

I12 wants Bitcoin's price chart aligned on its halvings: the four past ones
fixed, the next one estimated. A halving is a protocol fact. The block
subsidy halves every 210,000 blocks, so the halvings are blocks 210,000,
420,000, 630,000 and 840,000 (2012-11-28, 2016-07-09, 2020-05-11,
2024-04-20, in UTC), and the next is block 1,050,000. Its date depends on
how fast the coming blocks arrive. At the protocol's target of ten minutes
a block it would fall near 2028-04-17, but blocks have nearly always come
faster than that: the three past intervals ran 1,319, 1,402 and 1,440 days
against the target's 1,458.

The first triage on 2026-11-10 kept the app off the network: the next
halving as an estimate from the target rate, stored as an unconfirmed
event, and an agent refining it from a block explorer through the API.
The owner then asked for the chain itself as the source, because websites
"change or vanish and need chasing". The triage answered that B3.3 is a
checklist with a recorded reason, not a ban. The addendum parks
acquisition beyond quotes and FX until a decision covers **sources,
failure behaviour, retention** and **collector health**, "so that a dead
collector is visibly dead within a day instead of producing false calm".
ADR-0056 opened B3.3 for news feeds by answering those four, and a chain
source opens it the same way: with its own record, not as an exception.

The block chain is a good fit for those four questions. Every node and
every block explorer holds the same headers, so a source that vanishes can
be replaced by another one that answers with the same data. A block's
height and timestamp do not change once the block is buried. And the two
figures I12 needs, the tip height and a block's timestamp, are the
smallest thing a block-explorer API serves.

**What stays fixed.** Nothing that can act (permanent non-goal: no
connection that can place an order or move money); no credentials in
source or storage (B1); every outbound request through the one GET-only
client (B2); no data from an unstructured source lands unconfirmed
(NFR-10); every token carries the same authority (ADR-0054 §1).

## Decision

### 1. What the app reads, and what it does not

**Read:** the chain's **tip height**, and, for single heights, the **block
hash** at that height (a lookup key only) and the block's **height and
timestamp**. Nothing else in a block is stored or used.

**Not read, and not opened by this record:** transactions, fees, the
mempool, addresses, balances, difficulty, hash rate, prices or any figure a
block explorer derives, and anything that needs a key, an account or a
wallet. *Why the narrow list:* B3.3's reason is that every new kind of
acquisition brings its own sources, failures and retention. These two
figures need nothing that the record cannot answer here, while a fee or
mempool read would be a monitoring feature that nobody asked for. A price
read from the chain is not a price. **Reopened by:** a new record for each
further figure. No flip by comment.

### 2. Chains are registered protocol constants, never detected

A closed set `Portfolixir.Chains.Registry` names each chain the app knows,
with constants taken from the chain's consensus rules:

| Chain | `halving_interval` (blocks) | `target_spacing` (seconds) | Source in this record |
|---|---|---|---|
| `bitcoin` | 210,000 | 600 | §3; genesis hash `000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f` |
| `bitcoin_cash` | 210,000 | 600 | none |
| `litecoin` | 840,000 | 150 | none |

These are **protocol constants**: the subsidy halving interval and the
target block spacing as each chain's reference client states them in its
consensus parameters (Bitcoin Core's `nSubsidyHalvingInterval` of 210,000
and its ten-minute spacing; Bitcoin Cash inherited both at the fork of
2017 and shares Bitcoin's headers up to it; Litecoin's 840,000 blocks at
two and a half minutes). Halving *k* is the block at height
*k* × `halving_interval`. **No API states a chain's emission schedule in a
form the app can read**, and the quote and search providers (ADR-0005)
carry none, so the app never detects one (the triage's point 7). *Why
constants in code and not rows:* they are the same on every instance, they
are facts of the protocol rather than settings, and a row would let one
mistyped digit produce a wrong cycle that nothing could notice. A chain is
added by an amendment of this record that names its constants and their
source. **To flip:** "Ketten als Daten" (operator-registered rows, with a
check against the registry for a known chain).

**Not registered:** Zcash, whose halving interval changed at a network
upgrade and whose first halving was offset by its slow start, so one
constant does not describe it; Ethereum and most other coins, which have no
halvings at all (the triage's point 6).

**Only Bitcoin has a source in this record.** For `bitcoin_cash` and
`litecoin` the constants are registered so that a security can be bound to
them and the interval is checked (§4); their halving events are written by
hand or by an agent through the API, as ADR-0048 always allowed, and the
app fetches nothing for them. *Why:* §3's two public sources serve Bitcoin
only, and a source for another chain is a new host with its own failure
behaviour, which deserves its own amendment rather than a guess at a
compatible endpoint.

### 3. The source: the Esplora REST API, two public hosts, or one of the operator's

The adapter, `Portfolixir.Chains.Esplora`, speaks the read-only Esplora
REST API that mempool.space and blockstream.info both serve:

| Request | Answer read |
|---|---|
| `GET {base}/blocks/tip/height` | the tip height, as text |
| `GET {base}/block-height/{height}` | the block hash at that height, as text |
| `GET {base}/block/{hash}` | the block's `id`, `height` and `timestamp`, as JSON |

- **Default:** `https://mempool.space/api`, with
  **`https://blockstream.info/api`** as an **independent fallback** of the
  same API shape, run by another operator on its own infrastructure.
- **The operator's own instance:** `PORTFOLIXIR_BITCOIN_ESPLORA_URL`, when
  set, **replaces both** (the operator's own mempool or Esplora instance in
  front of a node). It is read at boot, never written by the app or its UI
  (`AGENTS.md`: no `.env` writing from the web UI). It passes the same URL
  policy as every other source: https, no userinfo, a host that resolves to
  public addresses only. It is checked with name resolution at boot and
  before every run, as ADR-0056 B2 checks a feed. **An instance on a
  loopback or private address is therefore refused**, with the error
  `url_not_allowed` and its reason on the health read (§8). *Why not
  waive the policy for one variable the operator set:* the policy is the
  one request-forgery guard every outbound caller shares (#762), and an
  exception for private addresses is a change to that guard, not to this
  adapter. §14 defers it with that reason.
- **Order:** the primary first, the fallback only when the primary fails
  (§7). The fallback is never asked to confirm what the primary said. *Why:*
  both serve the same headers, so a second read of every figure doubles the
  requests and finds nothing. §13 item 3 names what that leaves open.
  **To flip:** "Halving von zwei Quellen bestätigen" (a halving is confirmed
  only when both default sources give the same hash at its height).
- **Requests per run:** the tip height (1), then hash and block at the tip
  and at tip − 2,016 (4); once a day per source, the genesis check of §7
  (1); and, only until each past halving is confirmed, its hash and block
  (2 each). Six requests on an ordinary run, at most fourteen on the first.

### 4. A security is bound to a chain by the operator or an agent, never by a guess

A new nullable field on the security, **`halving_chain`**, an `Ecto.Enum`
over the registry's chains. It is written through `securities.update` (API,
MCP and the security's edit form) with the caller's token, journaled
(ADR-0054 §3), and returned by every security read. **Nothing sets it by
itself.** A security whose CoinGecko id or ticker looks like Bitcoin is not
bound by that, because a Bitcoin exchange-traded product, a wrapped token
and a coin with "bit" in its name all look like it too. *Why the binding is
a plain write and not a proposal:* NFR-10's preview-then-confirm is for
data extracted from an unstructured source. A caller choosing "this
security is Bitcoin" is a statement, and the write is its confirmation,
just as ADR-0058's manual window is. **To flip:** "Kette vorschlagen" (the
security read carries a `halving_chain_suggestion` from the CoinGecko id,
which only a write turns into a binding).

- **Any security may be bound**, held or not, flagged or not: the coin's
  own listing in USD or EUR, or a product that tracks it. Several securities
  may be bound to one chain, and each gets its own halving events (ADR-0048
  keys an event on one security and nothing else).
- **Binding** to a chain with a source makes the next run (§10) write the
  security's halving events. **Unbinding or rebinding** deletes the
  security's `halving` events in the same write, journaled and counted in
  the answer. The screen asks first when there are any. *Why:* a halving
  event is a fact about the security *as bound to that chain*, so without
  the binding it is a wrong fact. The journal keeps every deleted row.
- A merged-away security cannot be bound (422 naming `merged_into`).

### 5. Past halvings: read from the chain, confirmed, `primary`

For each bound security and each *k* with
*k* × `halving_interval` ≤ tip − 5, the reader makes sure an event exists:
`kind: halving`, `chain_height` *k* × 210,000, `date` the **UTC date of the
block's timestamp**, `timing: exact`, `confirmed: true`,
**`source_quality: primary`**, `source_url` `{base}/block/{hash}` of the
source that answered, `checked_at` the day it was read, and
`machine_generated: false`. *Why `primary`:* ADR-0044's scale puts the
issuer's own statement at the top, and for a halving the chain is the
issuer. *Why not `machine_generated`:* ADR-0048 §6 reserves the marker for
an extraction from an unstructured source. This is a read of two
structured fields, and the journal names the system writer (§10).

- **Six confirmations** (tip ≥ height + 5) before a halving counts as
  confirmed. Until then the event keeps `confirmed: false`, takes the block's
  date with `timing: exact`, and keeps `source_quality: unverified`. *Why:*
  a block at the tip can still be replaced by a short reorganisation, and
  six blocks is the depth that block explorers and exchanges conventionally
  treat as final.
- **A confirmed halving is never re-read.** Its block is buried, and a
  later answer that disagrees with it is the source's error, not the
  chain's (§7). ADR-0048's staleness read leaves confirmed `halving` events
  out (the amendment), so a 2012 fact does not show up as stale.
- **The date is the UTC date.** A block's timestamp is set by its miner
  and may be off by up to about two hours, so a halving close to UTC
  midnight can fall on the neighbouring day in another time zone. The
  block of 2024 is an example: it was mined at 00:09 UTC on 20 April, which
  was still 19 April in the Americas. The basis says UTC, and no time zone
  conversion is ever applied.

### 6. The next halving: a window between the recent block time and the target, refreshed daily

For each bound security, one **unconfirmed** event for the next halving
height *H* (the first *k* × 210,000 above the tip), with
`source_quality: unverified`, `timing: window`, and its two ends:

- **at the recent rate:** the tip's timestamp + (*H* − tip) × the **mean
  block time of the last 2,016 blocks**, which is
  (timestamp(tip) − timestamp(tip − 2,016)) / 2,016;
- **at the target:** the tip's timestamp + (*H* − tip) × `target_spacing`.

`date` and `date_end` are the earlier and the later of the two UTC dates.
The basis, carried in the event's `note` (at most one line) and in full by
ADR-0060's read, names the tip height, its timestamp, the timestamp at
tip − 2,016, the mean in seconds and both ends. All of it is integer
arithmetic and `Decimal` division, with no float. *Why 2,016 blocks:* it is
the length of one difficulty period, the span over which the protocol
itself measures block time, so the mean is the rate the next retarget will
correct. *Why a window and not the mean alone:* the retarget pulls the
block time back toward the target every 2,016 blocks. Over the remaining
blocks, the time therefore lies between "as fast as lately" and "at
target", unless the hash rate itself changes sharply. The window states
that range without any fitted model. Board 02 asked for exactly this
uncertainty ("the top band's time inherits the halving estimate's") and
drew an invented ±10 days for it; this rule replaces that guess. **To
flip:** "Halving als Einzeldatum" (`timing: estimated` at the recent rate
alone, and the top band's time from that one day).

- **Refreshed on every successful run**, and **written at most once a
  day**: the row changes when a date changes or when `checked_at` moves to a
  new day. Each write is journaled, about one entry a day for each bound
  security. *Why daily:* the estimate moves by about a day a week, so a
  daily refresh keeps it current. A fresh `checked_at` lets a dead collector
  show twice: in §8's health and in ADR-0048's staleness read, where the
  estimate turns stale when nobody has refreshed it.
- When the tip reaches *H*, the same row becomes §5's unconfirmed block
  date and then the confirmed fact, and the reader creates the estimate for
  *H* + 210,000. A bound security therefore always has exactly one
  unconfirmed `halving` event.
- **Why the estimate is stored, though ADR-0004 stores nothing derived:**
  its inputs are acquired data that nothing else in the app keeps, so it
  cannot be recomputed from the ledger or the stored series at read. It
  is also exactly what ADR-0048 built an unconfirmed event for: a calendar
  date that is expected, together with how well it is known. The inputs are
  kept with it (§9), so the stored date can be checked.

### 7. Failure behaviour

- **The client:** every request goes through `Portfolixir.Net.Http`, GET
  only, with the source's host as its allow-list, redirects only within it,
  a byte cap of 64 KiB and a deadline of 10 seconds. Bodies are decoded with
  string keys, and no atom is ever made from an answer.
- **Validation, before anything is written:** the tip is a decimal integer
  of at most 12 digits and **not more than 6 below the last stored tip**
  (otherwise `tip_behind`: a lagging source, or a source on another chain).
  A hash has exactly 64 hex characters. A block's `id` and `height` echo
  the hash and height asked for. A timestamp is an integer between the
  genesis block's time and the server's clock + 2 hours. **Once a day per
  source, the hash at height 0 must equal the registered genesis hash**
  (otherwise `wrong_chain`). *Why the genesis check:* an operator's own
  instance pointed at testnet or signet answers every other check
  plausibly, with heights and timestamps of the wrong chain. A refused
  answer writes nothing.
- **Fallback:** a primary that times out, answers 429 or 5xx, or fails
  validation is followed in the same run by the fallback. When both fail,
  or the operator's own URL fails (it has no fallback), the run records
  `last_error` with its reason and **changes nothing stored**. The last
  estimate stands, with its `checked_at`.
- **Retry:** the next scheduled run, every 6 hours (§10). There is no tight
  retry loop and no backoff state beyond that. *Why:* a daily fact does not
  need more, and four runs a day mean that one bad hour cannot make the
  source stale.
- **A failing chain never stops anything else.** The reader is its own
  supervised process, apart from the quote sync and the news fetcher.

### 8. Health: a dead collector is visibly dead within a day

One state row per chain with a source, `chain_reads`, holds `source_host`
(the host that last answered), `last_tried_at`, `last_ok_at`,
`last_error` (a short code and its reason) and the inputs of §6
(`tip_height`, `tip_at`, `tip_2016_at`). **`stale` is true when the chain
has had no successful run for 24 hours** (ADR-0056 §6's threshold, the
addendum's "within a day"). It is reported:

- by `GET /api/v1/chains` and `portfolixir.chains.list` (§11), per chain;
- in ADR-0060's cycles read, as `chain_source` beside the halvings;
- on the screen, in the cycle bar of the security chart: the host and the
  age of the last read, and with `stale` the line "Kettenquelle seit
  ‹n› Std. ohne Antwort", so a quiet chain and a dead source look different.

### 9. Retention

- **Halving events are kept** for as long as the security stays bound.
  They are calendar facts, a few rows per security, and ADR-0048 already
  keeps events without limit.
- **`chain_reads` is one row per chain, overwritten** by each run: state,
  not history. It is not journaled. *Why:* it is operational state that a
  system job writes four times a day, like a feed's health counters
  (ADR-0056 B7). The journal records the facts it produced (the events),
  not the polling.
- **No answer body is stored**, and no block beyond the three timestamps of
  §6 and the halving blocks of §5. Nothing here can become an archive,
  because nothing larger than a timestamp is kept.

### 10. Where it runs, and its registrations

- **The scheduler runs where the quote sync runs** (production;
  development with `PORTFOLIXIR_BACKGROUND_FETCH`; never in tests), every
  6 hours, with an on-demand run (§11). **A bound security is the opt-in**:
  when no security is bound to a chain with a source, the scheduler makes no
  request at all. *Why:* the same reason as ADR-0056 B6. A second switch
  would be one more setting to forget, and a chain nobody bound reaches no
  host.
- **B2, the outbound backstop**, registers `Portfolixir.Chains.Esplora` with
  its purpose and its hosts `mempool.space` and `blockstream.info`. Its
  allow-list is computed from the application config (`hosts_from:
  :config`), and the operator's base URL from
  `PORTFOLIXIR_BITCOIN_ESPLORA_URL` gets its own reason naming this record.
  The variable is listed in B2's environment registry as `:config`. These
  are registrations a reviewer reads, not a weakened gate.
- **B5** registers the reader as a self-scheduling process and its writes
  as the system job `chain_read`, the only writer of `halving` events on a
  security bound to a chain with a source (ADR-0048's amendment).
- **B3:** no new dependency. Req, Jason and the chokepoint are already
  there.
- **B4:** the names avoid the vocabulary B4 refuses: the context is
  `Portfolixir.Chains`, the process `Chains.Reader`, the table
  `chain_reads`. Nothing is named `sync` or `wallet`.
- **The suite** registers a fake source and never touches the network
  (`AGENTS.md`). The fixtures are synthetic heights and timestamps, plus the
  real, public genesis hash.

### 11. Surfaces

- **API:** `GET /api/v1/chains` (the registry's chains with their
  constants, and for a chain with a source its health of §8 and the inputs
  of §6); `POST /api/v1/chains/:chain/refresh`, an on-demand run that
  answers with the health. It is throttled to once per 10 minutes per chain:
  sooner answers 429 with `retry_after`, and a chain without a source
  answers 422 `no_source`. `securities.update` takes `halving_chain` (a
  registry chain or `null`); an unknown value is refused with 422 naming the
  field. Events of kind `halving` are read through ADR-0048's four reads.
- **MCP:** `portfolixir.chains.list` and `portfolixir.chains.refresh`. Each
  says that it returns data, never instructions. `portfolixir.securities.update`
  gains the field. The contract-version read reports the new surface
  (ADR-0044 §8).
- **Screen:** a "Halving-Kette" choice (none, Bitcoin, Bitcoin Cash,
  Litecoin) in the security's edit form, with the confirmation of §4 when
  halving events exist; the health line in the cycle bar (§8). The
  Sprint 30 planning PR draws its planning board, from the I12 idea boards,
  with the states this record adds: not bound, bound without a source,
  stale, and a refused own URL.

### 12. The gate's sentence and the PRD

`AGENTS.md` lists "data acquisition beyond quotes, FX and ADR-0056's news
feeds (B3.3)" as gated, and the gate registry
(`scope_b7_gate_registry_test.exs`) pins that sentence. **It becomes "data
acquisition beyond quotes, FX, ADR-0056's news feeds and ADR-0059's chain
source (B3.3)"**, and the *Why* that follows it, "which ADR-0056 gave news
feeds alone (ADR-0056 B8)", becomes "which ADR-0056 gave news feeds and
ADR-0059 one chain source". The change goes into the Sprint 30 sprint PR, in
the same commit as the registry entry and **never ahead of the code**, as
ADR-0056 B8 did.

PRD §4 still reads "data acquisition beyond quotes and FX" in two places,
its gate table and its "Gated, not in" sentence, and so missed ADR-0056 as
well. The same commit brings both in line with the new `AGENTS.md`
sentence.

### 13. The adversarial pass: sources, order and what a true record can change

1. *Can a source that vanishes leave the chart silently wrong?* No. The
   confirmed past is never re-read (§5). The estimate keeps its last
   value and its `checked_at`, and both §8's `stale` and ADR-0048's
   staleness read show the gap within a day.
2. *Can the order of answers change a halving's date?* No. A halving's
   date is a function of one block, read once at six confirmations. The
   estimate is a function of three numbers from one run, and a run takes
   all three from one source, never a mix.
3. *Can a lying source write a false halving?* A compromised public source
   could serve a false timestamp that passes §7's bounds. The fallback is
   not asked to confirm (§3), so that one answer would land. The threat is
   the same as a provider that serves false quotes (ADR-0005), and the
   remedy is the same: an own instance, or the flip "Halving von zwei
   Quellen bestätigen". A false *height* cannot land, because the height is
   the constant and the block must echo it.
4. *Can a source on the wrong chain write anything?* No. The genesis check
   refuses it (§7).
5. *Can a reorganisation move a confirmed halving?* Only one deeper than six
   blocks, which is outside what this record defends. Before six blocks the
   event stays unconfirmed (§5).
6. *Can a tie or an id decide anything?* There is nothing to break a tie
   over. Per security and height there is exactly one row, enforced by a
   unique index (ADR-0048's amendment).
7. *Can a security merge duplicate a halving?* It would, because ADR-0050 §9
   moves every event of the source security
   (`lib/portfolixir/lifecycle/security_merge.ex:1720`). ADR-0048's
   amendment keeps the target's row and drops the source's for a height the
   target holds, and drops all of the source's when the target is bound to
   another chain or to none. Each dropped row is journaled and listed in the
   merge preview.
8. *Can the operator's base URL reach the local network?* No, the URL
   policy refuses it (§3). That is the limit §14 defers.
9. *Can a timestamp near midnight move a cycle?* By a day, in the zone of
   whoever reads it. The stored date is UTC and says so (§5).
   ADR-0060 assigns that day's close to the new window, and the basis states
   it.

### 14. The asks, answered and deferred (ADR-0043)

**Source of the asks:** the addendum's B3.3 entry; idea I12's row
(2026-11-01 to 2026-11-10) and its triage points 1, 2, 6 and 7; the
owner's wish of 2026-11-10 for the chain as the source.

| Ask | Source | Verdict |
|---|---|---|
| Sources | B3.3 | **Answered**: §3, two public Esplora hosts or the operator's own, Bitcoin only |
| Failure behaviour | B3.3 | **Answered**: §7 |
| Retention, never an archive | B3.3 | **Answered**: §9 |
| Collector health, dead visibly within a day | B3.3 | **Answered**: §8, `stale` after 24 hours, and the estimate's `checked_at` |
| The chain itself as the source of halvings | owner, 2026-11-10 | **Answered**: §1, §5 |
| A source that does not vanish or need chasing | owner, 2026-11-10 | **Answered**: two independent hosts of one API, replaceable by the operator's own (§3) |
| Past halvings as confirmed events | triage 1 | **Answered**: §5, `primary`, six confirmations; the new kind is ADR-0048's amendment |
| The next halving estimated, refreshed daily, its basis stated | triage 2, owner | **Answered**: §6, a window between the recent rate and the target |
| An agent refining the estimate from a block explorer | triage 2 | **Answered differently**: the app reads it itself (§6); for a chain without a source an agent still writes the event by hand |
| The halving interval per chain as a registered constant, not detected | triage 7 | **Answered**: §2, three chains |
| Whether adding a coin with halvings builds the chart on its own | I12 row | **Answered differently**: one binding per security (§4), then the reader writes the events and ADR-0060's view appears by itself; detecting a schedule stays impossible (§2) |
| Other crypto assets | triage 6 | **Answered in part**: Bitcoin Cash and Litecoin are registered without a source (§2); Zcash is not |
| No credentials, nothing that can act | owner's triage | **Answered**: §1, §7, GET only through the chokepoint |
| An own node or instance on a private or loopback address, or Bitcoin Core's own REST interface | owner, "own instance or node" | **Deferred**: the URL policy refuses private addresses for every caller (§3), and an exception is a decision about the request-forgery guard; Bitcoin Core's REST interface is another API shape. Reopened by a record that amends the URL policy for operator-set sources |
| Chain sources for Bitcoin Cash and Litecoin | triage 6 | **Deferred**: no source of the same API shape was checked for this record (§2). Reopened by an amendment naming a host and its failure behaviour |
| Aligning a security on another chain's halvings | triage 6 | **Deferred**: ADR-0060 §14 |

## Consequences

- The app now talks to two more public hosts, a few requests every 6 hours,
  and only while a security is bound to Bitcoin. Each request is a GET for
  a number or a 1 KB header.
- Bitcoin's halvings land as confirmed, primary-quality events without any
  typing, and the next one stays current within a day. A security bound to
  Litecoin or Bitcoin Cash is checked against its constant, while its
  events are written by hand.
- A dead source shows on the chart's cycle bar, in the chains read and in
  ADR-0048's staleness read. A quiet cycle and a broken collector look
  different.
- The operator's own instance has to be reachable over https at a public
  address. That is a real limit for a node on the home network, and §14
  names it.
- The security gains one field, and ADR-0048 one kind, one field and one
  system writer. The companion gains two tools.
- B3.3 is open for exactly two things now (news feeds, this chain source).
  Each has its own record, so the next request starts from this checklist
  and not from a precedent.

## Choices and how to flip them

| Choice | Default | Flip by comment |
|---|---|---|
| Chains as constants in code | three chains, Bitcoin with a source | "Ketten als Daten" |
| Primary and fallback | mempool.space, then blockstream.info | "Blockstream zuerst" |
| One source confirms a halving | the source that answered | "Halving von zwei Quellen bestätigen" |
| The binding | a write by the operator or an agent, no suggestion | "Kette vorschlagen" |
| Confirmations before a halving is confirmed | six | a number by comment |
| The next halving | a window from the recent 2,016-block rate to the target | "Halving als Einzeldatum" |
| Run interval and staleness | every 6 hours; stale after 24 hours | numbers by comment |
| The operator's own URL | https, public address, replaces both defaults | none here; a private address needs the URL-policy record of §14 |
| Further chain data (fees, mempool, prices) | not read | none: a new record |
