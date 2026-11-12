---
layout: docs
title: API and MCP
description: Portfolixir JSON API and MCP companion reference.
lang: en
lang_en: /integration/api-and-mcp.html
lang_de: /de/integration/api-and-mcp.html
---

# API and MCP

Portfolixir exposes the supported local workflow through the JSON API under
`/api/v1`. The MCP companion in `mcp-server/` is intentionally thin: MCP tools
call the JSON API only and do not access the database directly.

## Authentication

API requests require a local bearer token:

```text
Authorization: Bearer <PORTFOLIXIR_API_TOKEN>
```

**Named tokens** (E25). `PORTFOLIXIR_API_TOKENS` adds further tokens as
`name=token` entries, comma-separated (`scripts=<token>`; a name is 1 to 32
characters of `a-z`, `0-9`, `_` and `-`, starting with a letter or a digit). A write made with one is journaled
with that name as `actor_label` (`GET /api/v1/journal`), and a merge applied
with one records it on its merge record (`GET /api/v1/merges`), taken from the
entry the presented token matched, never from the request.
`PORTFOLIXIR_API_TOKEN` stays the default, journaled without a label, as before, unless
`PORTFOLIXIR_API_PRINCIPAL` names it; the Compose deployment names it `mcp`
that way, so the companion's writes read `mcp`. Every entry is
checked at boot like the one token, and a name or a token may appear only
once. A name attributes a write; it does not narrow what the token may do:
every token has the same full authority. Why, and the boundary for stored
text below, is decided in
[ADR-0054](/decisions/0054-the-agents-surface-one-authority-named-principals-escaped-text.html).

The MCP companion uses `PORTFOLIXIR_API_TOKEN` to call Portfolixir at
`PORTFOLIXIR_API_BASE_URL`, and it follows no redirect from there: a `3xx`
answer is refused as `ApiRedirectError`, naming the request and the variable,
so a request's body and the token are never resent to wherever the redirect
points. Point `PORTFOLIXIR_API_BASE_URL` at the address the API answers on
without a redirect.
`PORTFOLIXIR_MCP_TOKEN` is required for HTTP transport so local HTTP clients can
authenticate to the companion. It meets the API token's policy: the companion
refuses to start with a token shorter than 32 bytes or equal to a placeholder,
naming the variable. A `PORTFOLIXIR_MCP_PORT` that is not a whole number from
1 to 65535, or a port the listener cannot take (another process holds it),
stops the companion with exit status 1 and one line naming the variable and
its value, or the address and the cause, such as `EADDRINUSE`. An empty or
blank `PORTFOLIXIR_MCP_HOST` binds `127.0.0.1`, as an unset one does, never
every interface (#1137), and so does an empty pair of brackets (`[]`), which
reads as the loopback default as an empty value does; an IPv6 address it binds
is answered in brackets (`[::1]:4001`), the `Host` a client sends for the URL
the companion prints.
Repeated wrong
tokens from one connecting address lock it for a growing interval, during
which every further wrong token from it is answered `429` with `Retry-After`
and extends the lock. The token is compared first: a correct token passes
while its address is locked (#974), so behind the published port, where every
client connects from the Docker bridge, a guesser or a stale client there does
not lock the agent out. The API's own bearer check behaves the same way
while every token it is configured with meets the 32-byte floor; a server run
from source that reads `PORTFOLIXIR_API_TOKEN` alone holds it to none, and
with a shorter token it consults the lock first. The API also counts IPv6
addresses per /64, and past an hourly ceiling on first failures from addresses
it has not seen, a first wrong token from such an address is answered `429`
with `Retry-After` too, instead of `401`. Before anything else, the companion checks the `Host`
header exactly, name and port: a request under a `Host` the listener does not
answer to (the loopback names and its bound address with its port, and the
names in `PORTFOLIXIR_MCP_ALLOWED_HOSTS`) is answered `403` before its origin
or its token is looked at, and counts no failed attempt. The loopback names
are `127.0.0.1`, `localhost` and `[::1]`, each with the listener's port only.
A name in `PORTFOLIXIR_MCP_ALLOWED_HOSTS` is answered with that port and
without one, as a proxy on port 443 passes it; an entry that carries its own
port is answered under that port alone, such as `127.0.0.1:14001` for a Compose
mapping that publishes the companion on another host port than its own.
The names, the bound host's and those in `PORTFOLIXIR_MCP_ALLOWED_HOSTS`, are
compared in lower case, as a browser sends them, so an entry written with
capitals passes both the companion's check and the MCP SDK's.
A browser request's `Origin` is then compared whole, scheme, name and port
(#956): it passes as `http://` on a loopback name or the bound address with
the listener's port, or as `http://` or `https://` on a `Host` value from
`PORTFOLIXIR_MCP_ALLOWED_HOSTS`. Any other origin, a page on another port of
the same machine included, is answered `403` (`origin not allowed`) before its
token is looked at. To admit a browser-based MCP client served from another
origin, name that origin's host and port in `PORTFOLIXIR_MCP_ALLOWED_HOSTS`:
`localhost:6274` admits a client served at `http://localhost:6274`. A client
that is not a browser sends no `Origin` and passes this check. The token is
checked before the request body is read. The
errors the companion answers itself, an unknown path among them, take the
API's shape, `{"errors": {"detail": "Bad Request"}}`, with no stack trace or
local path in it; the refusals of the MCP protocol itself on `/mcp` keep the
protocol's JSON-RPC error shape.

## Data Rules

All responses use JSON envelopes with either `data` or `errors`. Financial
decimals are serialized as strings, including quantities, prices, fees, taxes,
quote closes, and monetary totals. Request payloads send those values as
strings too.

**Decimal strings on writes.** Every write under `/api/v1` (`POST`, `PUT`,
`PATCH`, `DELETE`) refuses a JSON number — a float or an integer alike — in a
money, quantity, price, fee, tax or exchange-rate field with `422` naming the
field, `{"errors": {"price": ["must be a decimal string"]}}`, and stores
nothing (ADR-0003, amendment of 2026-11-01). A JSON number is decoded as a
binary float, so a value past about 17 significant digits would be stored as a
different number than the one sent: `"1234567890.12345678"` sent as a string
is stored exactly, and the same value as a number is refused rather than
rounded to `1234567890.1234567`. The rule reads the body at any depth — inside
a wrapper object such as `transaction`, in every row of a list such as a quote
batch's `quotes`, and in each item of a list of rates such as
`church_tax_rates` — and names each offending field once. The fields:
`amount`, `gross_amount`, `security_amount`, `settlement_amount`,
`face_value`, `amount_granted`, a tax year's allowances, a statement
snapshot's money fields and withheld taxes, `quantity`, `price`, `close`,
`fees`, `taxes`, the tax rates (`capital_gains_tax_rate`,
`solidarity_surcharge_rate`, `church_tax_rate`, `church_tax_rates`),
`settlement_fx_rate` and `coupon_rate`, and any field named with the suffix
`_amount`, `_price`, `_rate`, `_rates` or `_withheld`. A decimal string is
accepted as before and a JSON `null` keeps the answer it had; ids, years,
split ratio terms, target weights and policy thresholds are not covered by
this rule, and reads are unchanged. The MCP companion's tools already send
these fields as strings.

The errors the server answers itself, rather than an endpoint, use the same
envelope with their own status: an unreadable body, or one nesting arrays and
objects more than 100 levels deep, is `400`, a body over the server's size
bound of 2,000,000 bytes `413`, an unknown route `404`, an internal error `500`, each as
`{"errors": {"detail": "Bad Request"}}` with the status's reason phrase.

`DELETE /api/v1/securities/:id` is the success exception: it returns
`204 No Content` with an empty body. Clients should not parse a JSON body for
that successful delete response.

**Ids.** Every id is a positive integer that fits a PostgreSQL `bigint`
(at most `9223372036854775807`). A path id that is malformed, unknown or past
that bound answers `404`; an id past the bound in a query string or a JSON body
(at any depth, as a number or a string) answers `422` naming the key, the same
field error a malformed id gets. No id is ever answered with a `500`. A
security's free-form `attributes` map and the text fields `online_id` and
`resource_id` are not ids and are not checked.

The pages keep the same promise: an id-shaped query parameter past the bound
(`id`, `*_id`, `*_ids`, `view`) is dropped by a redirect to the same page
without it, and a path id past the bound (`/securities/:id`,
`/classifications/:id`) redirects to the index whatever the query string
carries — never a server error. Every other id-valued or integer page
parameter is read by the same id rule and reads as absent when it cannot hold
the value: `/snapshots?snapshot=` opens the newest snapshot, and
`/tax?year=` (a year outside `1`–`9999`) the default year. An event a page
or one of its dialogs receives with a payload that is not an object, an id
past the bound at any depth (the same rule the API answers with `422`), a
field of the wrong shape, or a name it does not know changes nothing: the page
stays as it was.

**Bounded integers.** `offset` on the securities list accepts at most
`1000000`, and `days` on the research log's `unreviewed` and `expiring` reads
at most `3650` (ten years); a value above the bound, or one that is not a
non-negative integer, answers `422` naming the parameter. `limit` keeps its
capped-and-echoed contract, and so does the security events' `days`. A year
outside `1`–`9999` reads as a malformed year.

**A capped list read says when it was cut (#1254).** Every list read that
bounds its rows with `limit` — the five delta reads below, the journal, the
merge records, the exchange rates, a security's quotes and its manual-quote
stretches, the snapshots, the three cash-flow roll-ups (whose `limit` counts
the years of the annual matrix) and the note and event queues (unreviewed,
uncorroborated, expiring, upcoming, unconfirmed, stale) — echoes the `limit`
it applied, the default when none was sent, and `truncated`: `true` when more
rows matched than the answer holds, so a full answer is never taken for the
whole one. Both sit beside `data` when `data` is the list, inside `data` when
it is an object; an older echo (`meta.limit`, `meta.filters.limit`) stays. To
read the rest, raise `limit` up to the read's maximum or narrow the filters;
only the delta reads page with a cursor.

**Dates.** Every date a write stores — a booking's `date`, a rule version's
`valid_from` and a retirement's `valid_until`, a snapshot's `as_of`, a
research-log entry's, an event's, a tax profile's, an ISIN change's, a quote's
and a split's dates — is an ISO 8601 calendar date (`YYYY-MM-DD`) from
`1900-01-01` to `2999-12-31`. A date outside that range, or sent in any other
form (an object of parts, a date-time), answers `422` naming the field and
stores nothing, so the date stored, answered and journaled is the date sent.
A Portfolio Performance import names a row dated outside the range in its
preview instead of booking it. A read's date filter — `from` and `to` on the
transactions, quotes and trades reads, `as_of` on the security metrics and
policy-rule reads — meets the same rule: anything else answers `422` naming
the parameter.

**Ledger amounts.** A booking's money fields and prices (`gross_amount`,
`price`, `fees`, `taxes`, `security_amount`, `settlement_amount`,
`settlement_fx_rate`) keep 6 decimal places and its `quantity` 12
(ADR-0016). A finer value is rounded half up to that scale **before** it is
checked, so the value stored, answered and journaled is the rounded one, and a
positive amount that rounds to `0` answers `422`. A value with more than 14
digits before the decimal point (a quantity more than 18) answers `422` naming
the field instead of failing in the database.

**Other stored amounts.** The same rule holds for every other amount a write
stores: a quote's `close` (6 decimal places), an exchange rate (15), and the
tax writes' money fields (6) and rates (4) — a statement snapshot's pots and
withheld taxes, an allowance order's `amount_granted`, a tax year's
allowances and rates, a profile's `church_tax_rate` — and a bond's
`coupon_rate` and `face_value` (6). A finer value is rounded
half up to its scale before it is checked, so a positive `close` that rounds
to `0` answers `422` and is never stored as zero; a money value with more than
14 digits before the decimal point answers `422` naming the field.

**Text.** A name, an identifier or any other one-line text a write stores is
at most as long as its column — 255 characters unless another limit is
stated (a bucket's or view's name 100, a plan's or snapshot's name 120, a
research entry's or an event's `source_url` 2,048),
counted in Unicode code points, the unit the database counts — and carries no
control character and no line break. Free text (a booking's `notes`, a
research-log entry, an event's or a rule version's `note`, a description)
keeps tabs and line breaks but no other control character, a NUL included,
and is at most 10000 characters long (a research-log entry's `body` 20000, a
category's `description` 2000), counted in code points; the database refuses
a longer value as well. No text, one-line or free, carries an **invisible
character** (E25): any of Unicode's default-ignorable code points — a tag
character and the rest of its block (U+E0000–U+E00FF, U+E01F0–U+E0FFF), a
bidirectional control (U+061C, U+200E, U+200F, U+202A–U+202E,
U+2066–U+2069), another invisible format character (the soft hyphen U+00AD,
the zero-width space and joiners U+200B–U+200D, U+2060–U+2065,
U+206A–U+206F, the byte-order mark U+FEFF, U+FFF9–U+FFFB, U+1BCA0–U+1BCA3,
U+1D173–U+1D17A), the combining grapheme joiner U+034F, a Hangul filler
(U+115F, U+1160, U+3164, U+FFA0), U+17B4–U+17B5, U+180B–U+180F or
U+FFF0–U+FFF8 — or a variation selector with no base it can vary. A
selector of U+FE00–U+FE0F passes after a pictograph (an emoji's
presentation), a keycap's digit, `#` or `*`, a CJK ideograph, a mathematical
operator, a CJK fullwidth punctuation mark (U+3001, U+3002, U+FF01, U+FF0C,
U+FF0E, U+FF1A, U+FF1B, U+FF1F), a curly quotation mark (U+2018, U+2019,
U+201C, U+201D) or a letter of Myanmar, Phags-pa, Manichaean or the Egyptian
hieroglyphs; one of U+E0100–U+E01EF only after a CJK ideograph; a selector
next to another one never.
A zero-width joiner U+200D passes where it joins two pictographs, as in an
emoji built from several (a person at a laptop, a family, the rainbow flag):
the character before it is a pictograph, or a VS16 right after one, and the
character after it is one. The three subdivision flags (England, Scotland,
Wales) are built from tag characters and stay refused, and so does the
zero-width non-joiner U+200C, which some scripts' words (Persian, several
Indic scripts) carry. They render as nothing but reach an agent intact, so the
error names them by code point: `must not contain invisible characters
(U+200B); retype the text without them`. A security's name is the one exception: its default-ignorable
characters, variation selectors included, are dropped as it is stored, as
before for its format characters. Anything else answers `422` naming the field, never a
server error. A Portfolio Performance import names a row whose names or note
break the same rule in its preview. A security's free-form `attributes` map
meets the rule at any depth: every key is one-line text of at most 255
characters, and every text value, in a nested object or list too, is free
text; otherwise the write answers `422` on `attributes`. The map as stored,
merged with the attributes already there, is at most 65536 bytes as compact
JSON; a write that would pass that answers `422` on `attributes` and stores
nothing. `market_cap_rank`, the attribute the securities list sorts as a
number, is a whole number or its text and is stored as a number; anything
else answers `422` on `attributes` ("market_cap_rank must be a whole
number"), and a search provider's value that is no whole number is dropped.
An update that changes nothing writes no row and leaves no journal
entry. A search provider's property that breaks the
rule is dropped before it reaches the attributes. A read's text filter — the
securities `query`, the journal's `resource_type` and `resource_id`, the tax
reads' `holder`, `institution` and `jurisdiction` — is one-line text of at
most 255 characters; anything else, a list included, answers `422` naming the
parameter.

**Wrapped bodies.** A write whose attributes travel under one key —
`{"transaction": {…}}`, `{"view": {…}}`, `{"rule": {…}}` and their siblings —
answers `422` naming that key when its value is not a JSON object (a string, a
number, a list).

**Delta reads (FR-38).** The two recurring-sync reads — `GET
/api/v1/transactions` and `GET /api/v1/securities` — accept
`?since=<ISO8601>` (a datetime with offset, a naive UTC datetime, or a plain
date meaning start of that day, UTC) and then return only the rows created or
updated strictly after that instant, judged by `updated_at`. The response
echoes `since`, carries `as_of` — use it as the next `since` — and a
`delta_note` stating the semantics. `as_of` lies one second before the read
instant, or before the start of the oldest transaction that has written and
is still open, whichever is earlier: a row is stamped when its transaction
writes it, not when that transaction commits, so a cursor at the read instant
would skip a row a long write (an import) commits after the read. The next
read may therefore re-deliver a row, but never skips one.

**A capped delta read is a page (K17).** The delta reads bounded by `limit`
— transactions, securities, a security's notes and events, a portfolio's
policy rules, the audit journal — return their rows oldest change first, and every read of
them, delta or full, echoes `limit` and `truncated` (true when more rows
matched than the answer holds). A delta read, when more rows matched than
the page holds, also carries `has_more: true`, and its `as_of` is then a
cursor at the page's last row,
`<ISO8601 instant>~<id>`: pass it as the next `since` and read again at
once. Rows sharing one stamp (an import writes thousands within a second)
are told apart by the id, so a page boundary among them skips none and
repeats none. A cursor never lies past the bound above: when the page's last
row is newer, `as_of` is the bound, without `~<id>`, and `has_more` stays
true — the rest waits behind a write still in flight, so poll again later,
not at once: until that write ends, a read at once returns the same page.
A page with nothing behind it carries `has_more: false` and the bound, as
before — also when it holds exactly `limit` rows. A cursor belongs to the
read that answered it: it carries that read's row id, so passed to another
read it would skip that read's rows on the cursor's second. With `since`,
page by `as_of`, never by `offset`: on each of the five reads, `offset`
beside a cursor (a `since` ending in `~<id>`) is refused with `422`
`errors.offset` `["is not used with a cursor; page by as_of"]`, because the
offset would skip rows after the cursor (issue #1295); a plain instant
`since` keeps the securities list's `offset`.
A malformed cursor is the same `422` as any invalid `since`.

**Deletions are not
represented** in a delta read; a caller that must detect deletions performs a
full read. An invalid `since` is a `422`. Delta reads are **pull-only**: push
delivery (webhooks to a user-configured endpoint) is a separate, still-gated
decision (B3.7) and deliberately not part of this surface.

**Which reads carry `since` (issue #830, Sprint 14 D-5).** `since` is a
*row-delta* parameter, so it fits reads that answer a collection of rows with a
change stamp, and only those. The family splits three ways:

- **Carries it — the row collections a scheduled run polls:**
  `GET /api/v1/transactions`, `GET /api/v1/securities`,
  `GET /api/v1/securities/:security_id/notes` (by `inserted_at`: the research
  log is append-only, so an entry never changes after it is written; the
  derived `thesis_state` still covers the whole log),
  `GET /api/v1/securities/:security_id/events` (by `updated_at`, so a
  rescheduled date returns as its changed row), and
  `GET /api/v1/portfolios/:portfolio_id/targets` and `/position_targets`
  (a target row counts as changed when **it or its plan** changed after the
  cut — activating another plan version swaps the steering rows without
  editing any of them; the position read's `effective_targets` roll-up always
  covers the whole plan, and `min_drift` applies after the cut), and
  `GET /api/v1/journal` (by `inserted_at`, to the microsecond: the journal is
  append-only; see [Audit Journal](#audit-journal)). Their MCP
  twins take the same `since` string: `portfolixir.transactions.list`,
  `portfolixir.securities.list`, `portfolixir.notes.list`,
  `portfolixir.events.list`, `portfolixir.targets.list`,
  `portfolixir.targets.list_positions` and `portfolixir.journal.list`. The configuration collections
  (portfolios, cash and securities accounts, buckets, views, classifications,
  plans, tax parameters, profiles and allowance orders, snapshots) do not carry
  it: they are small and operator-edited, and several carry per-row figures
  derived from other tables (a cash balance, a statement's staleness) that move
  without the row's `updated_at` moving.
- **Derived projections do not carry it — and need a different mechanism:**
  valuation, allocation, performance, benchmark, income and risk have no rows
  and therefore no `updated_at`. "Has the valuation changed since I last read
  it" is a question about the version of its **basis**, which the instance
  already tracks internally (ADR-0039) but does not expose; answering it is a
  conditional-read mechanism (an ETag or a basis token) that has not been
  built.
- **Time-derived queues must not carry it:** `/notes/unreviewed`,
  `/notes/expiring`, `/notes/uncorroborated`, `/events/upcoming`,
  `/events/stale` and `/events/unconfirmed`. Their membership changes
  **because time passes**, with no row changing — a position becomes
  unreviewed overnight, a date enters the horizon. A cut on `updated_at` would
  silently drop exactly the rows a poller needs, so these reads ignore `since`
  like any parameter they do not define (full answer, no delta envelope), and
  their MCP tools do not accept it.

The **human view** of the same cut (issue #731) lives on
`/transactions?since=` and `/securities?since=` as the *Changed since* chips:
same parameter name, same accepted forms, same strictly-after-`updated_at`
cut, so a link an agent hands over opens exactly the slice it read. The one
divergence is deliberate: where the API rejects an invalid `since` with a
`422`, the pages degrade to the unfiltered list — a stale bookmark must never
silently narrow what the operator sees.

## Securities

The `data_quality` predicates are the **same rule** the dashboard counts and
the securities page links to (issue #705): they are defined once in
`Portfolixir.Catalog.DataQuality`, so a count of N always addresses a list of
N, and an agent asking "which securities have a stale quote" gets exactly the
set a person sees. Combine them with `query`, `holding_status` and the other
narrowings; an unknown value is a `422` naming `data_quality`, never a silent
full list.

- `GET /api/v1/securities` lists securities. Rows default to a slim
  projection — the fixed whitelist `id`, `name`, `ticker_symbol`, `isin`,
  `wkn`, `currency_code`, `asset_class` — so routine listings stay small;
  `projection=full` returns the complete record (notes, feed config, attributes,
  timestamps). An optional `fields=` (issue #732, extending FR-37,
  comma-separated) selects a sparse fieldset resolved against the **full**
  projection's field list; a present `fields=` **supersedes `projection=`**,
  because a sparse fieldset is itself a projection, chosen field by field. An
  unknown name is a `422`, never a silent fallback.
  Optional query params: `query`, `sort`, `direction`,
  holding_status (`all`, `held`, or `not_held`), `logo_status` (`missing` or
  `present` — the bare logo condition; `missing` excludes rows explicitly set
  to no logo and includes a stored logo whose file is gone, whatever its lock,
  issue #933; `present` is a stored logo whose file is not), `data_quality`
  (`stale_quote` — no quote newer than 7 days, **including** securities never
  priced at all; `missing_quote` — no quote at all, the narrower set inside it;
  `missing_logo` — no stored logo and not set to no logo, or a stored logo
  whose file is gone (`file_missing` on the logo read), the set the
  "securities without a logo" overview shows; `missing_fx` — issue #717:
  priced, but with no stored rate from its currency to the EUR hub, so
  storing the rate empties the set. A benchmark and a retired security are in
  none of the first three, which leave them out in the query, before
  `limit`/`offset`: retiring a sold-out or delisted security takes it out of
  all three, and reactivating it puts it back in those it matches.
  `missing_fx` keeps both; `two_scales` — issue #1068: every bond the
  two-scales guard names, in either direction, catalog-wide, the set the
  Overview's data-quality line counts; see `bond.two_scales` below for the
  rule and which securities count as bonds. It keeps a benchmark and a
  retired security too, since their figures are as wrong as before;
  `implausible_quote` — issue #1101: every security, **held or not** (issue
  #1414), for which a buy, a sell or a priced inbound delivery has a
  stored quote, on the booking's date or the latest within 7 days before it, below half or above
  twice the booking's price per unit in the security's currency (a booking
  in another currency at its `security_amount` ÷ `quantity`), read on the
  booking's split basis (ADR-0028 §2), so a recorded split is not named and
  an unrecorded one is; a booking at a price of 0, or with no quote in the
  window, is not compared, and a security `two_scales` names is not counted
  again. A sold security is named too: its series still feeds the snapshot
  comparison, sale hindsight and the TTWROR windows over its holding
  period, so a provider series split-adjusted backwards against bookings in
  the old units is caught. It leaves out a benchmark, and a retired
  security unless it is held; `holding_status=held` or `not_held` narrows
  it as any listing. The Overview's data-quality line counts its held
  members. Under it the envelope adds `findings`,
  one per listed security — `security_id`, `kind` (`buy`, `sell` or
  `inbound_delivery`), `date`, `price`, `currency_code`, `quote_date`,
  `close` (on the booking's split basis), `ratio` (close ÷ price, rounded
  half up at scale 6), `bookings_outside`, the latest booking outside the
  band being the one named, and `held` (`true` or `false`, whether the
  security is held now) — and `computation_basis`, which states
  `input_series`, `reference`, `window`, `gaps`, `threshold` and
  `assumptions`, the last opening with what the set covers; `currency_mismatch` — issue #1415: every security whose
  stored `provider_currency`, the currency its quote provider stated at the
  sync that stored it, is present and differs from its `currency_code`, as
  written (`GBp`, pence, differs from `GBP`). The quote sync stores it on
  every sync that reads one, a refused answer's too (issue #1411), and only
  when it changes, so `provider_currency_at` is the time of the read that
  stored it; a security no sync has read a currency for is not yet known,
  never in the set. Like the first three it leaves out a benchmark, and a
  retired security unless it is held: a held one's value is as wrong as
  before, as `implausible_quote` keeps it. The Overview's data-quality line
  counts it. Under it
  the envelope adds `findings`, one per listed security — `security_id`,
  `currency_code`, `provider_currency` and `provider_currency_at` (ISO 8601,
  UTC) — and `computation_basis` with the same six keys. Nothing is
  converted: the remedy (the ticker, a sync, the stored quotes) is yours),
  `projection` (`slim`/`full`), and
  `limit`/`offset` for pagination (`limit` a positive integer, default 5000,
  max 20000; `offset` non-negative). Use these to
  page large catalogs instead of fetching the whole table at once. A
  `data_quality` set is filtered before `limit`/`offset` page it, so only its
  last page is short (issue #1113). A `sort` on a quote figure
  (`latest_price`, `latest_price_date`, `day_change_abs`, `day_change_pct`,
  `performance_1m`, `performance_1y`) sorts the whole set, with or without a
  `data_quality` set, a security without the figure last in either direction
  and ties in name order, and `limit`/`offset` page after it (issue #1186).
  Every sort breaks its last ties by `id`, ascending in either direction, so
  a `limit`/`offset` walk over rows sharing a sort value (every security
  without a value for an attribute, say) skips none and repeats none (issue
  #1294). The
  **human view** of these narrowings is the one-tap filter-chip row on the
  securities page (issue #717): its chips ride the same URL state
  (`holding=`, `dq=`, `filter[]=asset_class:is_nil`, plus `cur[]=` and
  `class[]=` for the currency and effective-class families), so a
  pre-filtered link and an API read describe the same set.
  `is_benchmark=true` narrows the read to the securities flagged as benchmarks
  (ADR-0046: the reference series of the benchmark comparison),
  `is_benchmark=false` leaves them out; the flag is a field of the full
  projection and of `fields=`, and `POST`/`PATCH` accept it.
  `is_retired=true` narrows the read to the retired securities (issue #1103),
  so a security retired out of the hygiene sets is found again and restored
  with `PATCH` `{"security": {"is_retired": false}}`; `is_retired=false`
  leaves them out. Both flags take `true` or `false` (blank counts as absent,
  anything else is a `422` naming the flag) and narrow together with the
  other parameters: beside a `data_quality` set that leaves such securities
  out, `is_retired=true` or `is_benchmark=true` matches nothing.
  **Held** (`holding_status=held`, and every other held filter: the research
  log's unreviewed positions and the events' `held_only`) means one thing: a
  non-zero net quantity across all depots, moved by `buy`, `sell`,
  `inbound_delivery` and `outbound_delivery` — a depot transferred in is held
  the moment it arrives; a `security_transfer` between own depots nets to zero.
- `POST /api/v1/securities` creates a security with a `security` object.
  `asset_class` is a stable string code: `equity`, `etf`, `fund`,
  `government_bond`, `bond`, `crypto`, `commodity`, `index`, `other`, plus the
  certificate/leverage codes `warrant`, `knock_out`, `factor_certificate`,
  `discount_certificate`, `bonus_certificate`, `express_certificate`,
  `reverse_convertible`. Leave it empty to let the class be inferred from the
  name/ISIN/ticker on read. To keep a position out of the allocation steering
  basis (the 100%) and the drift table while leaving it in the valuation totals
  and performance — e.g. a Bitcoin held as a store of value — tag it with a
  bucket and exclude that bucket from a view, then read allocation under that
  view.
- `GET /api/v1/securities/:id` returns one security, including its
  `identifier_aliases` — the former ISINs recorded via the ISIN-change
  endpoint below (each with `id`, `former_isin`, `changed_on`, `note`) — and
  its `thesis_state`, the current thesis derived from the research log (see
  below). Listings carry `thesis_state` as `null`; only the detail read
  computes it. A security a merge took away answers `404` with
  `errors.merged_into` `{"kind": "security", "id": …}`, the security its
  history lives on now — followed through every later merge to the live one
  — and a detail naming both (ADR-0050 §12); an id no merge names answers
  the plain `404`, and so does one whose chain ends at a row deleted since
  (a survivor may be deleted once it holds nothing), without `merged_into`
  and with a detail naming that row. Every route under
  `/api/v1/securities/:security_id/` answers a merged-away id the same way —
  the quotes, trades, metrics, notes, events and logo reads, their writes,
  the ISIN change and the delete of an identifier alias.
- `PATCH /api/v1/securities/:id` updates a security with a `security` object.
  The boolean `treat_quotes_as_raw` (default `false`) is the ADR-0028 escape
  hatch for providers that never back-adjust their history after a stock
  split: with the flag set, the security's provider-synced quote rows are
  treated as raw (as-traded), so the split-adjustment factors apply to them
  too. The boolean `is_retired` retires a sold-out or delisted security, and
  `false` restores it: a retired security leaves the `stale_quote`,
  `missing_quote` and `missing_logo` sets, and its stale quote stops counting
  as a price measurement in performance, which can restate its TTWROR history
  (#610). Like every security update, it is journaled under the calling
  token. A security's `currency_code` **freezes** once it has a transaction or
  a quote (ADR-0050 §11): a change then answers `422` with
  `errors.currency_code` counting them, for example
  `["is frozen once referenced (120 quotes, 3 transactions)"]`, and nothing
  is written. Resending the stored currency is no change, and the other
  fields stay editable.
  It also takes the news identity (ADR-0056 §2): `news_identity`
  `{"cik": ..., "aliases": [{"token", "context", "case"}]}` and the boolean
  `news_watch`; see [News upkeep](#news-upkeep-adr-0056).
- `DELETE /api/v1/securities/:id` deletes a security when nothing references
  it. A policy rule that reads it answers `409 Conflict` with
  `errors.policy_rules`. Bookings, quote history, research notes, security
  events, policy-rule versions or predictions (about the security or
  scored against it as their benchmark) answer `409 Conflict` with
  `errors.referenced_by` (the referencing tables, counted, for example
  `{"transactions": 3, "security_quotes": 120}`), `errors.remedy` and
  `errors.remedy_route`: `merge` for a duplicate, whose route is the merge
  preview `GET /api/v1/securities/:id/merge_preview?target_id=` completed
  with the id of the security to keep, or `retire` when research notes,
  rule versions or predictions reference it, because a merge cannot carry
  them (the route
  is `PATCH /api/v1/securities/:id` with `is_retired: true`). Before an
  unreferenced security is deleted, its category assignments, position
  targets, position bucket overrides and ISIN aliases are removed, each
  journaled; no database cascade removes them (ADR-0050 §11). A security that
  is already gone answers `404`. A delete that loses a race to a
  concurrent write, with nothing referencing the row afterwards, answers
  `409 Conflict` with `errors.detail` alone and deletes nothing: read the row
  again and retry (#954).
- `GET /api/v1/securities/search` searches configured online security providers.
  Query params: `query`; optional `type` with `security` or `crypto`. Every
  field of a hit comes from the provider and is checked for its type and
  bounded in size: a field of the wrong type or over its bound is absent, a
  hit without a usable name is dropped, a market keeps only bounded fields and
  scalar properties, and `raw` carries only `type` and `market_cap_rank`,
  never the provider's whole entry. The attributes a hit writes to a security
  are bounded the same way, and a name or quote-feed URL longer than 255
  characters is a `422` on any security write.

### ISIN changes (identifier aliases)

When a corporate action gives an existing security a new ISIN, record the
change instead of editing the ISIN in place: the former ISIN becomes a
journaled alias, and the import's ISIN matching consults current ISINs first,
then the aliases — so re-imports of old exports (former ISIN) and new exports
(new ISIN) both keep matching the same security instead of duplicating it
(ADR-0029). A plain rename needs no ISIN change — it is just a name edit.

- `POST /api/v1/securities/:security_id/isin-change` records the change with an
  `isin_change` object: required `new_isin` (normalized to trimmed uppercase),
  optional `changed_on` (ISO date, defaults to today) and `note`. Returns the
  updated security including its `identifier_aliases`. A `new_isin` that is not
  twelve characters of the ISIN shape (two letters, nine letters or digits and
  a check digit) or whose check digit does not agree answers `422` on
  `new_isin`, and a `note` over 255 characters `422` on `note`. Guarded with `422` and a
  named conflict when `new_isin` equals the current ISIN, is live on another
  security, or is recorded as another security's former ISIN; recording a
  change back to one of the same security's own former ISINs consumes that
  alias (a revert). Every security-ISIN write path — create, update, and the
  import's create path — symmetrically rejects an ISIN that exists as an
  alias, naming the aliased security. A conflict names the other security by
  its id (`security #12`), never by its stored name (see "A record named in a
  sentence" below).
- An identifier **changed** on an existing security through
  `PATCH /api/v1/securities/:id` meets the same catalog rules, or answers `422`
  naming the field: an `isin` of the ISIN shape with a check digit that
  agrees, a `wkn` of six letters or digits, a `ticker_symbol` of printable
  ASCII only. A lookalike (a letter from another script, an invisible
  character, a wrong check digit) never replaces the identifier the exports
  carry. Resending the stored value is no change, and a new security keeps
  what it is created with. A security's `name` is stored without Unicode
  format characters (zero-width spaces and joiners, bidirectional controls).
- `DELETE /api/v1/securities/:security_id/identifier_aliases/:id` deletes one
  recorded alias (journaled) when an ISIN change was recorded by mistake;
  returns `204 No Content`, or `404` when the alias does not belong to the
  security.

Example ISIN-change payload:

```json
{
  "isin_change": {
    "new_isin": "IE000XZSV718",
    "changed_on": "2026-07-01",
    "note": "merger rename"
  }
}
```

### Merging a duplicate security (ADR-0050 §9)

A second copy of one instrument — an export carrying a newer ISIN imported
before the change was recorded, a security created by hand that the next
import created again — is repaired by merging the duplicate (the **source**)
into the security you keep (the **target**). The operator's dialog on the
securities page (the row menu's **Merge into…**) reads this preview and
confirms with the same `plan_digest`, so both see the same plan.

- `GET /api/v1/securities/:id/merge_preview?target_id=` previews merging the
  security into `target_id` — a read that writes nothing
  (`portfolixir.securities.merge_preview`). Both must trade in the same
  currency, be both or neither a benchmark, and the target must not be
  retired while the source is live; while the source has quotes, both must
  treat their synced quotes alike (`treat_quotes_as_raw`). A source with
  research notes, named by a prediction (as the security called or the
  benchmark) or read by a policy rule is refused, because a note and a
  prediction can neither move nor vanish and a rule version keeps its
  subject (`research_notes`, `predictions`, `policy_rules` with
  `errors.policy_rules`); where
  merging the other way would pass, the detail says so. Each position the
  source holds in a depot must keep its view membership
  (`position_buckets_mismatch`). A split of the source the target carries in
  the same portfolio on the same day with the same ratio collapses; another
  ratio is refused (`split_ratio_mismatch`), and so is a split one side
  lacks while that side has a booking or a quote before it
  (`split_event_mismatch`) or a split that would rescale bookings it did not
  scale before (`split_linearity`), or a split the merge would move that
  still carries an import hash from a re-type before the import-hash kind
  check (`legacy_hashed_split`, with `errors.splits`; change its kind back
  or delete it — one the merge collapses is deleted with its hash retired).
  A source ISIN that fails its check digit is refused
  (`invalid_source_isin`, the stored value in `errors.source_isin`): the
  merge would write it onto the target, which
  the catalog refuses for a stored security, so correct or clear it on the
  source first. Finally, every identity of both
  securities must still find the target after the merge
  (`identity_unresolvable`, with `errors.unresolvable`): the identity as
  stored, the identity the Portfolio Performance import recorded when it
  created the security (its name, ISIN, WKN, ticker and currency — a file
  resolves on what it carries, not on identifiers added since), each former
  ISIN, and, for every security merged into either of the two before (and
  into those, down the chain), its identity as stored and as imported
  (`merged_stored`, `merged_imported`, under the merged-away security's
  id): a survivor merged away in turn must still lead every earlier import
  to the history. A name-only security that was given a ticker after its import
  and whose name differs from the target's is such a case; so is a name that
  another live security also carries. Each refusal is a `409 Conflict` with
  `errors.code`, `errors.detail` and `errors.guards`; an unknown source
  answers `404`, a source already merged `409` `already_merged` with
  `errors.merged_into`, a missing `target_id` `422`. The `200` carries:
  - `plan_digest`, the digest the merge takes;
  - `source` and `target`, each with its name, currency, `isin`, `wkn`,
    `ticker_symbol`, `feed`, `asset_class`, flags, `transaction_count` and
    `split_events`; `guards`; `reverse`, whether merging the other way would
    pass;
  - `key_equal_pairs` and `choice_required`, as for an account merge, and
    `splits` (`collapsed`, `moved`) with `split_events` before and after;
  - `position_buckets`: per depot the source holds or carries an override
    in, both effective bucket sets, both overrides and the `action`;
  - `quotes`: `source_count`, `moved_count` (the source's quotes on dates the
    target has none, which move keeping their source), `collision_count`
    (dates both have: the target's quote wins, the source's close goes into
    the merge record) and `manual_collisions`, each colliding source quote
    typed by hand, with `date`, `source_close`, `target_close` and
    `target_source`;
  - `configuration`: `category_assignments` (per classification of the
    source, `move` where the target has none in it, otherwise `drop` — the
    target's wins — with both categories) and `position_targets` (every
    position target of the source in an active, draft or archived plan, with
    its plan, `plan_status`, category and `target_weight`, and `move`, or
    `drop` with the `reason` `collides` — the target has a row in that plan —
    or `stale` — the row would no longer sit under the target's category);
  - `events`: the events that move, and `possible_duplicates`, a source and a
    target event of the same kind on the same day (both kept);
  - `identifiers`: `choice_required` (both carry an ISIN), then
    `after_by_identity_choice` with `keep_target_isin` and
    `adopt_source_isin` — or `after` when there is no choice — each the
    target's `isin`, `wkn`, `ticker_symbol`, `feed`, `name`, `asset_class`
    and `former_isins` after the merge; `adopted`, what the target takes from
    the source (a WKN, ticker or feed it lacks, an ISIN only the source
    carries); `differences`, every source value that follows the target
    instead (name, asset class, logo, a WKN, ticker or feed the target has
    already, and a WKN or ticker the catalog's rules refuse on a change,
    which is never adopted and lists the target's `null`; and
    `provider_currency`, the currency the source's quote provider stated,
    wherever it differs from the target's `currency_code` or the target's
    own stored one — carried with its time onto a target whose `target` is
    `null`, the target's kept otherwise);
    `aliases_reassigned`, the source's former ISINs;
  - `outcome_by_collapse_key_equal` with `"false"` and `"true"`: the
    target's `transaction_count` after, `moved_transaction_ids`, `deleted`
    (`collapsed_duplicate` or `collapsed_split`), `positions` (per depot the
    source holds: `source`, `target` and `after`, each `quantity`,
    `cost_basis`, `avg_cost` and `realized_result`), `fifo_realized`,
    `rounding_differences`, `cash_accounts` and `flow_changes`, with
    `positions_basis` and `flow_basis` as for a depot merge (a
    `removed` or `boundary_removed` entry names the source security); `reimport_note` says what the
    merge does to the next import;
  - `fifo_realized`, in each outcome: the FIFO realized gains the merge
    restates (security review 2026-10-12, K11). The realized gains the app
    reads (`GET /api/v1/realized_gains`, a security's trades) are FIFO over
    one queue per security across every depot; the merge pools the two
    queues, so a sale can close the other security's older lot. `years`
    lists per close year and currency the realized result of the source
    and of the target, each over its own queue before (`null` where it
    closes no trade that year), of the target over the merged rows after,
    and the `change`; `open_lots` the open lots' cost likewise;
    `unmatched_sells` the sells no lot covers, per side; `unchanged` is
    true when no realized amount and no open cost moves — which lot a sale
    closes, and with it holding periods and annualized returns, may still
    change. Amounts are in each trade's currency, never
    converted; `fifo_basis` states the rule. `realized_result` in
    `positions` is the depot's moving-average result, not this figure.

  Every quantity, close, weight and decimal is a string. The digest covers
  both securities, every booking of either, their quotes, category
  assignments, position targets, events and former ISINs with their
  `updated_at`, the identities the imports recorded, every figure and the
  guards; the choices are not part of it, so one pair has one digest, and a
  quote the sync stores between the preview and the merge is a changed plan.
- `POST /api/v1/securities/:id/merge` with `{"target_id": …, "plan_digest":
  …, "collapse_key_equal": …, "identity_choice": …, "isin_changed_on": …}`
  merges under the token (`portfolixir.securities.merge`).
  `collapse_key_equal` is required when the preview lists `key_equal_pairs`,
  and `identity_choice` when both securities carry an ISIN — each a `422`
  without it, and never preselected: ask the operator. The `identity_choice`
  refusal names the ISINs by their kind and carries both in `errors.isins`
  (`source_isin`, `target_isin`).
  `keep_target_isin` keeps the target's ISIN and records the source's as a
  former ISIN of the target; `adopt_source_isin` gives the target the
  source's ISIN and records the target's old one as its former ISIN (the
  repair of ADR-0029 §3's wrong-order duplicate, together with
  `collapse_key_equal: true`). `isin_changed_on` (`YYYY-MM-DD`, optional) is
  that former ISIN's `changed_on`; the merge date otherwise. An unknown
  `identity_choice` or an `isin_changed_on` that is no date answers `422`. It
  answers `201 Created` with the merge record (`kind` `security`,
  `portfolio_id` `null`; its `manifest` lists every booking moved or deleted,
  every quote moved and every quote dropped with its close and the target's
  close that won, the assignments, position targets and events moved or
  dropped, the former ISINs reassigned and created, the identifiers adopted
  and the differences, and the choices — `collapse_key_equal` only where
  the preview listed `key_equal_pairs`, `identity_choice` and
  `isin_changed_on` only where the merge made that choice, both securities
  carrying an ISIN, and `null` otherwise, whatever the request sent) and
  `already_applied: false`. In one
  transaction, one audit-journal entry per row: with `true` the source's
  paired bookings are deleted and their content hashes retired; a split the
  target carries on the same day in the same portfolio is deleted; every
  other booking moves onto the target; the quantity of every depot is checked
  on every day against the fold of both securities' bookings
  (`409 identity_check_failed` otherwise); the bucket plan is written; the
  quotes are gap-filled — **not journaled**, the merge record is their
  record — and both securities' derived values are invalidated; the
  assignments, position targets and events move or are dropped as the
  preview listed; the source's former ISINs go to the target, its ISIN is
  written by the choice, its WKN, ticker and feed where the target lacks
  them; the source is deleted; and the identities are checked again on the
  catalog as the merge left it (`409 identity_unresolvable` with
  `errors.unresolvable` rolls it back otherwise). After it, a Portfolio
  Performance import naming the source by any of its identifiers books onto
  the target, and a re-import of an export already applied creates nothing.
  A changed plan answers `409` `plan_changed` with the fresh preview in
  `errors.preview`; a retry of a completed merge of the same pair answers
  `200` with the original record and `already_applied: true`; a source
  merged into another security `409` `already_merged`. There is no unmerge.

### Research log (ADR-0044)

What the operator or the agent knows about a security is recorded as
**append-only** dated entries — the security research log — and the current
thesis state is **derived** from them, never maintained beside them. Entries
are never updated and never deleted: a refuted finding is withdrawn by
appending a `retraction` that supersedes it, and both stay readable, so the
next run sees the retraction first instead of re-investigating a settled
premise. There is deliberately no `PATCH` and no `DELETE` for an entry.

Each entry carries `kind` (`thesis`, `evidence`, `invalidation_check`,
`event_result`, `risk`, `retraction`, `decision`), `body`, `source_url` (an
`http(s)` URL of at most 2,048 characters, the news parser's own cap
(ADR-0056 E2); other schemes, longer links and a link holding a backslash,
which a browser reads as `/` and so would open another host than the one
shown, are a `422`),
`source_quality` (`primary`, `secondary_multi`, `awareness`, `unverified` —
**set, not guessed**), `as_of` (the statement's cut-off date, distinct from
`inserted_at`: an entry written today about last quarter carries last
quarter's date), `author` and `machine_generated` — `author` (`operator` or
`agent`) is derived from the credential that writes the entry, `agent` for
every API token, and `machine_generated` is reserved for a local-model path
that does not exist yet (an extracted entry would be a proposal until
confirmed, carrying its `source_url`); both are ignored in a body, so a body
can claim neither —, `supersedes_id` (the earlier
entry of the same security this one replaces; required for a retraction),
`valid_until` (a dated block such as a lockup or a self-imposed buying block),
— on `thesis` entries only — `conviction` (`low`, `medium`, `high`),
`invalidation_condition` and `time_stop`, and — on `evidence` and
`event_result` entries only (ADR-0044's amendment of 2026-11-06) —
`headline` (plain text of at most 80 characters, one line, no invisible
character), `event_type` (`earnings`, `guidance`, `capital_measure`, `legal`,
`m_and_a`, `product`, `regulatory`, `macro`) and `tone` (`-1`, `0`, `1`, the
writer's reading for the security: it colours a chart marker and is never a
filter, a sort key or a signal); on another kind each answers `422` naming
it. Like every field they are set once: the log is append-only. An entry
without them reads them as `null`, and `news_label_id` names the news label
an entry written from a story took its event type or tone from (the
server's provenance, never taken from a body). Every entry in a response also
carries `superseded_by_ids` and a `superseded` flag, so a superseded entry is
shown as superseded rather than hidden. All closed sets are validated; an
unknown value is a `422` naming the field, and no atom is ever created from
input.

- `GET /api/v1/securities/:security_id/notes` — the log, newest first (by
  `as_of`, then write time), with the derived `thesis_state` and a `log_note`
  stating the append-only contract.
  `limit` keeps the newest entries — in a delta read, the oldest after
  `since` (default 1000, max 10000); `thesis_state` always derives from the
  whole log, and the answer echoes the applied `limit`.
- `POST /api/v1/securities/:security_id/notes` — appends one entry from a
  `note` object (`201`); journaled under the API-token actor. An `as_of`
  after today (the instance's calendar day) answers `422` on `as_of` ("must
  not be in the future"): the log is append-only, so a mistyped future year
  could never be taken back. `valid_until` and `time_stop` may lie in the
  future. `body` holds at most 20000 characters and `invalidation_condition`
  at most 10000 (Unicode code points); a longer value answers `422` naming
  the field, and the database refuses it as well.
- `GET /api/v1/notes/unreviewed?days=N` — held securities (net quantity
  non-zero across all depots) whose newest entry is older than `N` days
  (default 90) or that have none; rows carry `last_entry_as_of` and
  `days_since_last_entry` (`null` when never reviewed). An entry counts as a
  review on its `as_of`, but no later than the day after it was written, so
  an entry stored with a future `as_of` before the refusal existed cannot
  keep its position off this read; the thesis state's `last_reviewed_at`
  follows the same rule, and the entry itself keeps its `as_of`.
  `limit` keeps the most overdue positions (default 1000, max 10000).
- `GET /api/v1/notes/uncorroborated` — entries whose `source_quality` is not
  `primary`, newest first; superseded entries are skipped unless
  `include_superseded=true`; optional `security_id`.
  `limit` keeps the newest entries (default 1000, max 10000).
- `GET /api/v1/notes/expiring?days=N` — entries whose `valid_until` falls
  within the next `N` days (default 30), soonest first, with
  `days_until_expiry`; lifted (superseded) blocks are skipped; optional
  `security_id`.
  `limit` keeps the soonest-expiring entries (default 1000, max 10000).

The **thesis state** (`thesis_state` on the security detail and on the log
read) is the B4.1 projection: `status` (`none`, `intact`, `retracted`), the
current thesis text, `conviction`, `invalidation_condition`, `time_stop`,
`as_of`, `last_reviewed_at` and `last_reviewed_by` (the newest `thesis` or
`invalidation_check` entry), `derived_from_entry_id` (the thesis entry it
reads from) and `retracted_by_entry_id` (the retraction whose body carries
the reason), plus a `basis` sentence stating the derivation. The newest
thesis no other thesis supersedes is the current one; a retraction
superseding it sets `retracted`.

Example append payload:

```json
{
  "note": {
    "kind": "retraction",
    "body": "Checked the 10-Q on 2026-08-02: no supplier dispute disclosed. Withdrawn.",
    "source_url": "https://example.invalid/sec/10-q",
    "source_quality": "primary",
    "as_of": "2026-08-02",
    "supersedes_id": 41
  }
}
```

**A news story becomes an entry only by a confirmed write** (ADR-0056 §8, A2):
`POST /api/v1/securities/:security_id/notes` with
`note.cluster_id` (a story of that security) and a `body` writes an entry
the server pre-fills from the story: `kind` `evidence` (`event_result` may be
sent instead; another kind answers `422` naming `kind`); `as_of` the day the
story was published (its representative's publication, as `news.get`
answers it); `source_url` the link of its best-tier member, the first that
fits 2,048 characters; `source_quality` by ADR-0056 §3's rule (a `primary`
member gives `primary`, two or more distinct `secondary` domains
`secondary_multi`, one `unverified`, else `awareness`), each member at the
tier the source table gives it now, so a second promotion after a re-rating
states the new tier, and a member whose domain is now blocked is left out
(of the quality and of the link; ADR-0056 E1 rule 5); `headline` its title
cut at 80 characters on a word boundary; `event_type` and `tone` from its
active label of the newest prompt version (a `noise` label gives no event
type), the entry keeping that label's id as `news_label_id`. The pre-fill is
a proposal: `kind`, `headline`, `event_type` and `tone` sent beside
`cluster_id` replace it, and `null` leaves one out; `as_of`, `source_url` and
`source_quality` are the story's, and one sent beside `cluster_id` answers
`422` naming it. A title holding an invisible character is refused as a
headline, naming `headline`; send your own. Every member of the story is then
`promoted` and names the entry in `note_ids` (`news.get`, `news.list` with
`fields=std`), so it outlives retention; a second promotion appends another
entry, and the story names both. A story of another security, a category's
story, an id naming none or a story whose every member's domain is now
blocked answers `422` naming `cluster_id`. Nothing in the
news layer writes an entry, an event or a prediction by itself.

**A news item from an outside aggregator** (idea I13; Sprint 25 plan D-5),
which the news layer does not hold, is recorded as an ordinary entry: `kind`
`evidence`; `as_of` the date the item became public, which is the
statement's cut-off date, so it sits beside the close of that day; `source_url`
the article; `source_quality` as the aggregator judged it; `body` a summary and the link, **never the
article** — Portfolixir keeps no news archive. A direction the aggregator
reads from the item (positive, negative) is not written into the note: it is
recorded as a prediction (`POST /api/v1/predictions`,
`portfolixir.predictions.create`) with `note_id` pointing at the note, so the
call is resolved and scored like any other. The aggregation runs outside the
app; Portfolixir fetches no news itself. A news entry is an entry like any
other for `GET /api/v1/notes/unreviewed` (`portfolixir.notes.unreviewed`): it
takes its position off that list. Whether the thesis itself was reviewed is
the thesis state's `last_reviewed_at`, which only `thesis` and
`invalidation_check` entries move.

The human view is the **Research** tab of the security detail pane on
`/securities/:id`: the thesis state on top, the entries newest first with
kind and source quality visible, superseded entries marked as such,
retractions legible, and a form that appends an entry as the operator.

### Predictions (ADR-0055)

A **prediction** is a permanent record of one call on one security: it
`outperform`s or `underperform`s a benchmark by `resolves_on`, with a stated
probability. **It cannot be edited, withdrawn or deleted**, by anyone: there
is deliberately no `PATCH` and no `DELETE`. A mistaken prediction stays and
counts; a correction is a new prediction, and both count. Its status, outcome
and figures are derived at every read from stored closes and never stored, so
a quote corrected later changes the outcome visibly. Ladder (c): it scores
what was recorded before its outcome was known. No field holds an order, a
size or a limit, and nothing proposes one.

- `POST /api/v1/predictions` — records one call from a `prediction` object
  (`201`): `security_id`; `direction` (`outperform`, `underperform`);
  `probability`, a **decimal string** from `"0.50"` to `"0.99"` in steps of
  `0.01` (a JSON number answers `422`; `"0.49"` answers `422` naming the
  other direction, since a call below 50 % is the opposite call above it, and
  `"1.00"` is refused because a call stated as certain cannot be scored);
  `benchmark`, as `benchmark=` spells it — `security:<id>` of any security
  with a stored quote, flagged `is_benchmark` or not (not the security
  itself; one without a quote answers `422`, `has no stored quote`;
  ADR-0046's amendment of 2026-11-07) or `rate:<decimal>`, a
  fixed annual rate as a **fraction** from `-0.999999` to `1` (`rate:0.02` is
  2 % a year; a rate above 1 answers `422` naming the fraction form, because
  `rate:5` meant as 5 % would be 500 % a year on a record that can never be
  corrected), `rate:0` making the call absolute; `resolves_on`, 7 to
  1,830 days after the UTC day it is made; `model`, the model an agent runs
  on (at most 100 characters), **required for an API token**, refused for
  the operator's pages; optional `note_id`, a research-log entry of the same
  security (its thesis, its decision, its news item); optional `rationale`
  (at most 4,000 characters). `made_at` is the server's clock and `author`
  (`agent` for every API token) and `actor` (the token's name) come from the
  credential: a body carrying any of the three answers `422` naming it,
  because a prediction dated in the past is one made with its outcome in
  view. Every refusal is a `422` with all field errors at once; nothing is
  stored. The write is journaled as `prediction` / `create` under the token.
  A prediction also keeps its security and its benchmark security from ever
  being merged away or deleted; retire one instead.
- `GET /api/v1/predictions/:id` — one prediction with its `resolution`, a
  `permanence_note` and the resolution rule's `computation_basis`; `404` for
  an unknown id.
- `GET /api/v1/predictions` — the predictions newest first, each read as
  above, with `as_of`, the `filters` echoed, `limit` (default 100, max 500)
  and `truncated`, the `permanence_note` and the `computation_basis`.
  Optional filters: `security_id`, `status` (`open`, `resolved`,
  `unresolved`, derived at read; `limit` then counts the calls the status
  kept), `author` (`operator`, `agent`), `model` (exactly as named) and
  `due_before`, **the due query**: the open predictions whose `resolves_on`
  is on or before the date, a call past its date that still waits for its
  end close included. A malformed filter answers `422` naming it.
- `GET /api/v1/predictions/calibration` — the calibration report over the
  predictions the filters name, each resolved at read as of today:
  `counts` (`total`, `open`, `resolved`, and `unresolved` by reason);
  `brier` — the Brier score over every resolved prediction (the mean of
  `(probability − outcome)²`, outcome 1 for a hit and 0 for a miss; lower is
  better), its `standard_error` and the `reference` `"0.25"`, the score of
  saying 50 % to everything; `sharpness`, the mean of `probability − 0.50`,
  beside it, since saying 50 % to everything is perfectly calibrated and
  says nothing; `hit_rate` (`rate`, `hits`, `mean_probability` and its
  `standard_error`); five `bands` (`0.50`–`0.59` to `0.90`–`0.99`), each
  with its `count` and `mean_probability`, and a `hit_rate` only from 20
  resolved predictions: below, it is the string `"too_few"`; `groups`, the
  same block per `author` and per `model`; and the whole
  `computation_basis`. With no resolved prediction every figure is `null`,
  and a standard error is `null` with `standard_error_reason`
  `no_resolved` or, with one, `one_resolved`. Open and unresolved
  predictions enter no score and are counted. Optional filters: `author`,
  `model`, and `from` / `to`, a `resolves_on` range, both inclusive; `to`
  before `from` answers `422` on `to`. **Expect `too_few` for a long time**:
  the headline score with its standard error carries meaning from the first
  resolutions.

A prediction read carries `id`, `security_id`, `direction`, `probability`,
`benchmark`, `resolves_on`, `made_at`, `made_on` (its UTC day), `author`,
`actor`, `model`, `note_id`, `rationale` and `resolution`:

- `status` — `open` while the instance's calendar day is on or before
  `resolves_on`, and after it **until its end close is in**: until the
  security, and a benchmark security, each have a stored close dated on or
  after `resolves_on` (the evidence that the day's data is in, never used in
  the measurement), or until 7 days after `resolves_on` have passed. So a
  resolved call never flips when the close of `resolves_on` arrives late.
  Then `resolved`, with `outcome` `hit` or `miss`, or `unresolved`, with
  `reason` `no_start_close`, `no_end_close`, `no_benchmark_close` or
  `no_fx_rate`, never estimated (ADR-0055, amendment of 2026-11-05);
- `start_on` — the UTC day made: the start close is the last close **on or
  before** that day, so a call made after the day's close starts from the
  price it knew, and one made before it from a close that comes after it: no
  call scores a move it had seen; `end_on` — `resolves_on`, the end close the
  last on or before it; a close more than 7 days older than the date it
  stands for is no close;
- `security` — `security_id`, `currency_code`, `start` and `end` (each
  `stands_for`, `date`, `close`, `stored_close`, `source`, `fx_rate` and
  `eur_value`, the close converted to EUR at the stored EUR-hub rate of its
  own date) and `return`, the EUR value at the end over the start minus 1,
  computed as one division of exact products
  (`(end close × start hub rate) / (start close × end hub rate) − 1`), so two
  equal moves in one currency read equal returns to the last digit;
  `null` while open or when that side has no answer;
- `benchmark` — a security benchmark's sides by the same rule, or
  `{kind: "rate", rate, from, to, days, return}`, the rate compounded daily
  over the days between the two dates the security's closes stand for;
- `excess` — the security's return minus the benchmark's: an `outperform`
  call hits when it is above 0, an `underperform` call when it is below 0,
  and 0 is a miss for both. Price returns only: no distribution is counted on
  either side.

Example create payload:

```json
{
  "prediction": {
    "security_id": 12,
    "direction": "outperform",
    "probability": "0.65",
    "benchmark": "security:7",
    "resolves_on": "2027-05-03",
    "model": "example-model-1",
    "note_id": 41,
    "rationale": "The thesis entry's plant ramp-up shows in the next two quarters."
  }
}
```

### Security events (ADR-0048)

A **security event** is a dated statement that something will happen, or has
happened, to a security: an earnings report, an ex-dividend or payment date, a
lockup expiry, an index review, a shareholder meeting, a regulatory decision, a
guidance update.

It is **not** a corporate action. A split *changes a position* and is therefore
a ledger event (ADR-0028); an earnings date changes nothing until a price
moves, and a price move is already a quote. `security_events` is its own table
and the ledger projection never sees one. When the calendar fact becomes a
booking — the dividend is actually paid — the booking goes through the ledger
as it always did and the event is marked `confirmed`: **the event is never
converted into a transaction and the transaction does not consume it.**

**The catalog, not the holdings.** Events key on `security_id` and nothing
else — no portfolio, no depot, no view — and the catalog-wide reads cover
**every security by default**. `held_only=true` narrows them and is never the
default. This is the requirement rather than a query detail: a calendar derived
from the position list cannot hold a date for a security not yet owned, which
is exactly the security whose dates matter most.

**A date is qualified by how well it is known.** `timing` is one of `exact`
(a source that sets it), `estimated` (expected rather than announced), `window`
(between `date` and `date_end`, inclusive — `date_end` is required here and
allowed nowhere else) and `month` (the month of `date` is known, the day is
not). "Earnings expected late February" is not a date, and storing it as one
makes a guess indistinguishable from a filing.

**Mutable and journaled, deliberately not append-only.** A research entry is an
argument whose history is its meaning; an event is a fact about the world, and
a rescheduled call does not make the old date a second fact — it makes it
wrong. So a correction is a `PATCH` on the same row, and the change history
lives in the append-only audit journal.

The reads:

- `GET /api/v1/securities/:security_id/events` — one security's events,
  soonest first, with `limit` (default 1000, max 10000).
- `GET /api/v1/events/upcoming?days=N` — everything due within `N` days
  (default 30) across the whole catalog, soonest first. A `window` or `month`
  event is due when **any** day it could fall on is inside the horizon — the
  conservative direction, because the failure being prevented is a missed date
  rather than an early warning. Optional `kind`, `held_only`, `limit`; the
  answer echoes `days`, `as_of`, `held_only` and its scope. `days` is bounded
  the way `limit` is: a value above ten years is capped and echoed capped.
- `GET /api/v1/events/unconfirmed` — events whose whole span is in the past
  and whose `confirmed` flag is still false: the "did it actually happen?"
  queue, which is what keeps the calendar from quietly rotting. Optional
  `security_id`, `kind`, `held_only`, `limit`; there is deliberately **no**
  `days` here, because an unconfirmed past date belongs in the queue however
  old it is.
- `GET /api/v1/events/stale?days=N` — events whose `checked_at` (the day the
  fact was last re-read against its source) is older than `N` days (default
  90), or that were never checked at all, which are listed with
  `days_since_checked` `null`. Deliberately a different read from the one
  above: a confirmed *future* date nobody has re-read in three months is a
  different risk from a *past* date nobody resolved. An event whose stored
  `checked_at` lies after tomorrow (written before the refusal below
  existed) is listed too, with a negative `days_since_checked`.

The writes:

- `POST /api/v1/securities/:security_id/events` — records one event (`201`).
  `security_id` comes from the path, never the body; `machine_generated` is
  reserved and is ignored in the body. `event.news_id` (ADR-0056 §8) names a
  news item of that security as the event's source: its
  link becomes `source_url` and the tier the source table gives it now
  `source_quality` (`primary`, `secondary` as `unverified`, `awareness`);
  `source_url` or
  `source_quality` sent beside it answers `422` naming it, and an item of
  another security, one that does not exist, one whose domain is now
  blocked or whose link is longer than 2,048 characters answers `422`
  naming `news_id`. The item is not promoted:
  what lasts from news is a research entry.
- `PATCH /api/v1/security_events/:id` — corrects or confirms one in place. The
  security it belongs to cannot be changed.
- On both writes a `checked_at` later than tomorrow (the instance's calendar
  day plus one day of zone slack) answers `422` on `checked_at` and writes
  nothing: it is the day the source was re-read, and a future one would hide
  the event from the stale read. An event's `note` holds at most 10000
  characters (Unicode code points); a longer one answers `422` on `note`.
- `DELETE /api/v1/security_events/:id` — removes one (`204`), journaled with
  the row recorded, for a duplicate or a date that never existed. To record
  that a date passed, mark it `confirmed` instead.

`source_quality` reuses the research log's vocabulary exactly (`primary`,
`secondary_multi`, `awareness`, `unverified`) — one scale for "how well do we
know this" across both knowledge families. An event carries **no money**: there
is no financial decimal on the object at all.

**What this surface is not.** Nothing fetches a calendar — entry is manual or
through the agent's own write. The due-date read is a **pull**: there is no
alerting and no push delivery. No rule reads these rows, and whether events
predicted anything is not evaluated here.

### Derived metrics (ADR-0047)

Scope-ladder **level (a)**: one security's price metrics, derived on read from
the quote history it already holds. Nothing is stored and nothing is fetched.

- `GET /api/v1/securities/:security_id/metrics` — `sma_50` and `sma_200` with
  the latest close's `distance_pct` to each; `volatility` and `max_drawdown`
  over the windows `30d`, `90d` and `365d`; `momentum` over `3m`, `6m` and
  `12m`; `distance_to_extremes`, the 52-week high and low with their dates and
  the distance to each. The drawdown carries `peak_date`, `trough_date` and
  `recovery_date` (`null` while the series is still below the peak; all
  three `null` when the drawdown is exactly `0`: there was no decline, so
  none is dated). Optional `as_of` (ISO date, default today) bounds the series: closes dated
  after it are not read. An unknown security is a `404`; a malformed `as_of` a
  `422`.

Three properties are worth knowing before comparing two securities.

**The series is the security's own.** Metrics read the stored closes in the
**ADR-0028 §2 display basis** (split-adjusted at read time; the stored rows are
never mutated) and in the **security's own currency** — deliberately *not*
converted to the base currency, because a price metric is a statement about the
instrument and a conversion would fold the FX path into it.

**A gap produces no observation, never a zero.** Returns are taken between
consecutive stored closes; a day with no close is not carried forward and then
differenced, because that manufactures a calm 0 % day and drags the standard
deviation toward zero. Every metric therefore carries its `observations` count
and the `window` it was measured over, and the payload carries
`computation_basis` (`input_series`, `window`, `reference`, `gaps`,
`assumptions`) once.

**Below its minimum a metric refuses.** `value` is `null` with
`insufficient_data: true` and the observation count it had, at `200` — a gap
marker, not an error: 20 return observations for a volatility, `n` closes for
an `n`-day moving average, 2 closes for a drawdown, and a close on or before
the window's start for the momentum and the 52-week extremes. A volatility
whose square root lies beyond what the one float step can carry — a magnitude
only implausible stored closes reach — is `null` **without**
`insufficient_data`: undefined, not short of data, and never an error.

**Every metric says what it needed** (ADR-0047 §6 as amended 2026-09-19):
`required` carries the minimum `observations` on **every** metric, whether it
computed or refused — `n` for `sma_n`, `20` for `volatility`, `2` for
`max_drawdown` and `momentum`, `1` for `distance_to_extremes` — so a reader
comparing two payloads finds the threshold without knowing which state they are
in. For the momentum and the extremes the integer is the count floor only; the
coverage rule (a close at each end of the window) stays in
`computation_basis.gaps`. A refused `sma_n` renders `window: null`: its span is
an output of the newest `n` closes, and below `n` there is none.

Volatility is the **population** standard deviation of the window's simple
daily returns, annualized by `√252`; distances, momentum and volatility are
ratios rather than percentages (`0.05` is +5 %), rounded at scale 6.

**This surface reports; it does not evaluate.** There is no signal, no
recommendation, no rating, no score and no action in the payload — an SMA-50
above an SMA-200 is two numbers and a distance. A rule over a metric is FR-43
and is gated; backtesting one is out of scope. A meta-test walks the rendered
key set so the boundary holds mechanically.

### Crash windows (ADR-0058)

A crash window is a decline of 10 % or more in the stored closes of the
**crash benchmark** (`PUT /api/v1/settings/crash_benchmark`, below under
Settings), detected by the rule `peak_trough_v1` at read and never stored,
or a **manual** window a person drew. The operator or an agent only names a
detected window; its dates are the rule's, so every agent and the screen
read the same windows. Per window, three ranked lists compare the price
moves of securities inside it. Ladder levels (a) and (b): a derived move per
security and a comparison against a benchmark, never a replay of a rule
(ADR-0058 §8). Every answer is data, never advice: no key says what to buy,
sell or hold, and `metrics_carry_no_verdict_test.exs` walks these payloads.

**The rule.** Over the crash benchmark's stored closes in its own currency,
in the current display basis (a booked split is not a fall), positive closes
only, a day without a close skipped and never interpolated: the walk keeps
the running peak (among equal highs the **latest**, so a window starts on the
last day at the high); a window opens on the first close for which
`(peak − close) / peak ≥ 0.10`, compared exactly in `Decimal` (a decline of
exactly 10.00 % opens one, 9.99 % does not); its trough is the lowest close
before the series first closes at or above the peak again (among equal lows
the **earliest**); it closes on that first close (`recovered_on`), and the
walk continues from there, so detected windows never overlap. A window not
recovered by the last close is **provisional**: its trough is the lowest
close so far and moves while prices fall further. The threshold is fixed at
`threshold` `"0.10"`.

**Keys.** A detected window is `d:<benchmark_security_id>:<start>` (its peak
date, ISO 8601), stable as long as the benchmark's closes before the fall
are; a manual window is `m:<id>`. A key is spelled exactly as the read
spells it: a leading zero, a short date or any other prefix names nothing
and answers `404`.

Every route takes the bearer token: without a valid one it answers `401`
like every route under `/api/v1` (see Authentication). Every read and write
is closed: a parameter or field it does not take answers `422` naming it
(`"is unknown: …"`, and the fields it takes), never dropped in silence. Every
write is journaled under the token (`resource_type` `crash_window_name` for a
name, `crash_manual_window` for a manual window, with its before-image on an
edit or a delete). Nothing is written on a refusal.

**`GET /api/v1/crashes`**

The windows as every reader reads them. It takes no parameter (any answers
`422` naming it). `data` carries:

- `benchmark` — the crash benchmark: `{id, name, isin, currency_code,
  benchmark_security}` (`benchmark_security` is `flagged`, `held` or
  `unheld`, as the setting's write answers it), or `null`.
- `reason` — `null`, or why nothing is detected: `no_crash_benchmark` (none
  chosen: `detected` is `[]`, manual windows work regardless) or
  `crash_benchmark_unavailable` (the chosen security was merged away since;
  its survivor is never taken by a guess).
- `detected` — oldest start first, each with `key`, `kind` `detected`,
  `name` (`null` while unnamed), `start` (the peak's date), `peak_close`,
  `trough`, `trough_close`, `decline` (the fall from peak to trough as a
  fraction, negative; the closes and the decline as decimal strings in the
  benchmark's own currency), `recovered_on` (`null` while ongoing),
  `provisional` and `max_gap_days`, the longest span in calendar days between
  two consecutive closes from the start to the recovery (or to the last close
  while provisional), so a window drawn over a stale stretch reads as such.
- `manual` — oldest start first, each with `key` `m:<id>`, `kind` `manual`,
  `id`, `name`, `start`, `trough`, `author` (`operator` or `agent`, from the
  creating credential), `actor` (the creating token's name), `created_at` and
  `updated_at`. Listed whether or not a crash benchmark is chosen. Its dates
  were chosen by a person, who may have known the outcome; `kind` says so on
  every read.
- `unmatched_names` — the stored names whose key matches no window the rule
  detects now, oldest start first, each with its stored `key`, `name`,
  `benchmark_security_id`, `benchmark_name` (`null` when that security is
  gone), `start` and `for_current_benchmark`: `true` when it was given for the
  crash benchmark chosen now (the closes changed, and its window moved or
  vanished), `false` when it was given for another one (choosing that one
  again restores it). A name is never re-attached to another window by a
  guess (ADR-0058 §3).
- `computation_basis` — the rule's: `rule` (`peak_trough_v1`), `threshold`
  (`"0.10"`), `comparison`, `peak_ties`, `trough_ties`, `input_series`,
  `currency` (the benchmark's, or `null`), `currency_note`,
  `split_adjustment`, `gaps` and `recovery`.

**`GET /api/v1/crashes/:key/rankings`**

One list of the window `key`, derived at read and never stored. Query
parameters, each optional:

- `list` — `losers` (default), `winners` or `rebounders`;
- `universe` — `catalogue` (default): every security in the catalogue not
  merged away and not flagged `is_benchmark`, minus the crash benchmark
  itself; `held`: of those, the securities held **today** in any depot
  (their quantity summed over every depot is not zero), what the screen's
  „Im Depot“ lists when no view is chosen; or `view:<id>`: of those, the
  securities the view holds **today** (a position in a depot the view covers
  whose quantity summed over those depots is not zero, the rule the news
  digest reads a view's holdings by). Held today, not at the window's dates;
- `limit` — default 8, a positive integer; above 50 it is capped at 50 and
  the answer's `limit` says so;
- `include_unanswered` — `true` adds `unanswered_entries`; `false` or absent
  leaves them out.

**Losers and winners** rank each security's **EUR price return from `start`
to `trough`** by the window-return function sale hindsight and the
prediction resolution share, so a crash return and a sale's hindsight return
over the same dates agree to the last digit: the close standing for a date is
the last positive stored close on or before it, at most 7 calendar days older
(`staleness_days`), in the display basis, each converted to EUR at the stored
EUR-hub rate of its own date, one division. Losers come lowest first,
winners highest first; the winners list keeps negative returns with their
signs when few securities rose. A price return: distributions are not
counted.

**Rebounders** rank each security's rise from its **own low** — its lowest
close on a day from `start` to `trough`, the earliest of equal lows — to the
end of the **recovery span**, `trough` plus three calendar months (a day the
month lacks becomes its last day: 30 November ends on 28 February;
`recovery_span_months` `3`), in EUR by the same function, highest first.
Beside each: `days_back`, the **calendar days** (`days_back_unit`
`calendar_days`, the amendment's F3: trading days differ per venue) from its
own low to its first close at or above its close standing for `start`, `0`
when the low is not below that close, or `null` with `not_yet` `true` when no
close up to today reaches it.

**Ties** within a list: by the figure, then the security's name
case-folded, its ISIN, its ticker, its WKN and its currency (a security
without one after those with one). Entries equal on all of these share a
`rank` and are ordered among themselves by the security's creation time; an
id decides no rank (ADR-0058 §5, amendment of 2026-11-12, part 2).

`data` carries:

- `window` — `{key, kind, name, start, trough, provisional, recovered_on,
  max_gap_days}` (the last two `null` for a manual window);
- `list`, `universe` and `limit`, echoed;
- the dates measured over: `from` and `to` for losers and winners (the
  window's `start` and `trough`); `low_from`, `low_to` (the days an own low is
  read from), `span_end` (the trough plus three months) and `measured_to` for
  rebounders;
- `provisional` — `true` while the window has not recovered (its trough, and
  so every list, moves with it), and for rebounders also while the recovery
  span has not ended: the list is then measured to today (`measured_to`), and
  `completes_on` names the day the span ends (`null` while the window is
  still falling, since that day is not known yet). A rebound is never ranked
  over a shorter span than the one it names without saying so;
- `benchmark` — the crash benchmark `{id, name, isin, currency_code,
  benchmark_security}`, or `null`;
- `reference` — the crash benchmark measured by the same rule and function
  as each entry (over the same dates for losers and winners, from its own low
  for rebounders): `{security_id, return, start, end}`, with `low` for
  rebounders; or `null`, with `reference_reason` saying why:
  `no_crash_benchmark`, `crash_benchmark_unavailable`, `no_benchmark_close`
  or `no_fx_rate`;
- `entries` — at most `limit`, each with `rank` (from 1; entries tied on
  every key share one, and the next takes its position), `security` (`{id,
  name, isin, currency_code}`), `held` (`true` when any depot holds it today,
  so a catalogue list can mark it), `return`, `start` and `end` (each close:
  `stands_for`, `date`, `close`, `stored_close`, `source`, `fx_rate`,
  `eur_value`), `benchmark_return` and `vs_benchmark_pp`, the difference
  `(return − benchmark_return) × 100` in percentage points, unrounded; for
  rebounders also `low` (`{date, close}`), `start_close` (`{stands_for, date,
  close}`), `back_on`, `days_back` and `not_yet`. Every figure is a decimal
  string;
- `answered` — how many securities of the universe have an answer;
- `unanswered` — the others counted by reason, each key always present:
  `no_close_at_start` (no close standing for the start; for a rebounder also
  none from start to trough), `no_close_at_end` (none within 7 days of the
  end, or a security younger than the window) and `no_fx_rate` (a close
  without a stored rate path to EUR). A security without an answer is in no
  list and never ranked as a zero;
- `unanswered_entries` — with `include_unanswered=true` only: each
  `{security, held, reason}`, in the tie order above;
- `computation_basis` — `benchmark`, `reason`, `reference`, `window`,
  `rule` and `threshold` (`null` for a manual window), `dates` (the rule's,
  or chosen by a person), `universe`, `list`, `figure`, `input_series`,
  `currency` (`EUR`), `detection_currency`, `currency_note`, `close_lookup`,
  `staleness_days` (`7`), `split_adjustment`, `fx`, `recovery_span_months`,
  `recovery_span`, `days_back_unit`, `days_back`, `gaps`, `ties`,
  `provisional` and `survivorship`.

**Without a crash benchmark** (the amendment's F2), a manual window's lists
answer without a reference: `benchmark` and `reference` are `null`,
`reference_reason` is `no_crash_benchmark`, every entry's
`benchmark_return` and `vs_benchmark_pp` are `null`, and the basis says
`benchmark: null` with `reason`. The ranking is unchanged: a manual window
is the operator's own span, and ranking the securities inside it needs no
market line.

**Survivorship.** The catalogue holds what is still tracked: a security
that failed and was removed is in no list, so the lists read better than the
market did, and the rebounders most of all. `computation_basis.survivorship`
says so in every answer.

Refusals, each before anything is read: `list` other than the three answers
`422` with `errors.list` `["is invalid: losers, winners or rebounders"]`;
`universe` other than `catalogue`, `held` or `view:<id>` (a leading zero or a sign
included) `errors.universe` `["is invalid: catalogue, held or view:<id>"]`;
`limit` zero, negative or not a number `errors.limit` `["is invalid: a
positive integer, at most 50"]`; `include_unanswered` other than `true` or
`false` `errors.include_unanswered` `["is invalid: true or false"]`; any
other parameter `422` naming it. A key that names no window detected now or
no manual window answers `404`, and so does a `view:<id>` whose view does not
exist.

**`PUT /api/v1/crashes/:key`**

Body `{"window": {...}}`. On a detected key (`d:`) it names the window, or
renames it: the body takes only `name` (at most 80 characters, ADR-0054
§4's text rules, required). The key must name a window the rule detects now
over the current crash benchmark; a name is never given to a window nobody
can read. A name never moves the window's dates. On a manual key (`m:`) it
edits the window: any of `name`, `start` and `trough`, checked on the edited
window under the rules of `POST`; the creating token stays the creator's.
The answer is the written window: for a name `{key, kind: "detected", name,
benchmark_security_id, start}`, for a manual window the shape `manual` reads.

Refusals: a key that is neither `d:` nor `m:`, a detected key that names no
window detected now, or a manual key that names no manual window answers
`404`; a field the key's kind does not take (`start` on a detected key)
answers `422` naming it; a blank or over-long `name` (or none where the window
has no name yet), or a date refused under `POST`'s rules, `422` naming the
field; a `window` that names no field on a named or a manual window (it would
change nothing) `422` naming `name` ("is missing"); a `window` that is not a
JSON object `422` naming `window`.

**`POST /api/v1/crashes`**

Body `{"window": {"name", "start", "trough"}}` draws a **manual window**
(`201`): `name` at most 80 characters, ADR-0054 §4's text rules; `start` and
`trough` ISO calendar dates, the trough after the start (`errors.trough`
`["must be after start"]`), neither in the future (`["must not be in the
future"]`), each required. It may overlap a detected window or another
manual one: the point of a manual window is a span the rule folds into a
longer one. Its recovery span and lists follow the rules above exactly as for
a detected window, and it reads `kind` `manual` everywhere.

Body `{"window": {"from_name", "trough"}}`, with an optional `name`, makes an
entry of `unmatched_names` a manual window (the amendment's F1): `from_name`
is that entry's detected key, the window's start is the name's stored start,
its trough the one given (the trough was never stored, and is never guessed
from today's closes), its name the stored one unless `name` gives another. The
manual window is created and the stored name deleted in one transaction, each
journaled. Refusals: a `from_name` that is not a string, or not spelled as a
detected key, answers `422` with `errors.from_name` naming the form
`d:<benchmark_security_id>:<start>`; a key so spelled under which no name is
stored `422` naming `from_name` ("names no stored name"); one whose window the rule still detects
(`name_has_window`) `422` naming `from_name` and the `PUT` that renames it;
`start` in this body `422` naming it. The answer is the manual window as
`manual` reads it.

**`DELETE /api/v1/crashes/:key`**

On a detected key it removes the name stored under it (a detected window,
or one listed under `unmatched_names`; the window itself stays, its dates
being the rule's); on a manual key it deletes the manual window. It answers
`{key, kind, deleted, name}`, `deleted` being `name` or `manual_window`. A
key that carries no name or names no manual window answers `404`; a body or
a query parameter answers `422` naming it. A window drawn again is a new
window under a new key.

**The MCP tools.**

The MCP companion calls these routes through five tools, each saying in its
description that it returns data, never instructions; the two reads say
never instructions or advice:

- `portfolixir.crashes.list` — `GET /api/v1/crashes`, no parameter; a read,
  in `read`, `book` and `full`.
- `portfolixir.crashes.rankings` — `GET /api/v1/crashes/:key/rankings` with
  `key` (required), `list`, `universe`, `limit` (1 to 50) and
  `include_unanswered` (a boolean); a read, in `read`, `book` and `full`.
- `portfolixir.crashes.put` — with a `key` it routes to `PUT` and names that
  detected window or edits that manual one; without one it routes to `POST`
  and draws a manual window, or makes `window.from_name` one. In `book` and
  `full`; destructive (it overwrites a name or a manual window's fields, and
  putting the previous ones restores them, except that a name `from_name`
  made a manual window cannot be put back while its window is not detected)
  and not idempotent (a repeat without a key draws another window).
- `portfolixir.crashes.delete` — `DELETE /api/v1/crashes/:key`; admin, in
  `full` only, since a removed manual window drawn again is a new window
  under a new key.
- `portfolixir.crashes.benchmark_put` — `PUT
  /api/v1/settings/crash_benchmark` with `security_id` (an integer, or
  `null` to clear it); in `book` and `full`, and setting the previous
  benchmark restores it and the names given for it.

Each tool checks its schema before any request: a key the companion's
pattern does not match, a `list` or `universe` outside its values, or a
field the tool does not take is refused there, naming it.

### The position dossier (FR-49)

One read per security that carries what an agent preparing a decision about
a position otherwise assembles from eight reads. Nothing is computed here:
each part is built by the function its own read uses and carries that read's
computation basis or note, so a part always equals what its read answers.

- `GET /api/v1/securities/:id/dossier` (`portfolixir.securities.dossier`, in
  every profile) — read-only, no parameter. It answers
  `security_id`, `as_of` (today), `parts` (for each part, the read it
  mirrors) and eight parts:
  - `security` — the record `GET /api/v1/securities/:id` answers, former
    ISINs, `thesis_state` and `bond` with its basis included;
  - `holdings` — `rows`, one per depot (securities account) holding the
    security, across portfolios, as
    `GET /api/v1/portfolios/:portfolio_id/holdings?security_id=:id` answers
    them, with that read's `currency_basis`, `currency_basis_note` and
    `computation_basis`; `total`, the security's row of
    `GET /api/v1/holdings/by_security` (EUR, `valued`, `unvalued_reason`),
    `null` when nothing is held, with `total_basis` (`currency`, `note`);
  - `metrics` — `GET /api/v1/securities/:security_id/metrics` at its default
    `as_of`, `computation_basis` included;
  - `research` — the newest 5 entries of the research log, as
    `GET /api/v1/securities/:security_id/notes?limit=5` answers them, with
    `has_more`, the `log_note` and `rest`, the read that pages the rest;
  - `events` — `upcoming`, every event whose last possible day is today or
    later, soonest first, and `past`, the newest 5 others, newest first, both
    from `GET /api/v1/securities/:security_id/events`, with `has_more`, the
    `events_note` and `rest`;
  - `categories` — one row per classification of `GET /api/v1/classifications`
    (`classification_id`, `classification_name`, `classification_key`,
    `built_in`) with `category` (`id`, `name`, `key` and `path`, the
    categories from the root down to it), `null` where the security is not
    filed;
  - `targets` — `rows`, the position target rows of
    `GET /api/v1/portfolios/:portfolio_id/position_targets` naming the
    security, per portfolio, in the active plan of the unscoped view (a
    view's plan is the same read with `view=`; `parts.targets` says so), and
    `drift`, naming the read that states each row's drift: the dossier
    computes none;
  - `news` (ADR-0056 §9) — `count_7d`, the security's
    stories with a member that entered their scope in the last 7 days (as
    `GET /api/v1/news/stories?security_id=:id&since=` 7 days back lists
    them), `primary_7d`, those whose best tier is `primary`,
    `max_materiality`, the highest materiality of their active labels of the
    newest prompt version (`null` without one), and `newest_primary`, the
    security's newest primary story at any age (`id`, `title` cut at 50
    characters, `at`; `null` without one). About 50 tokens; the companion
    answers the dossier as compact JSON, as it answers the news reads.

Left out on purpose: quotes, trades, lots and transactions, each a long series
with its own paged read, and drift, which needs a classification and a
valuation per portfolio. A security with nothing recorded answers every part
empty at `200`. A security merged into another answers `404` with
`errors.merged_into` (`kind`, `id`), as `GET /api/v1/securities/:id` does; an
unknown id answers the plain `404`. The human view is the security page for
every part but `targets`, whose view is the Classifications page.

### Bonds: master data and the bond reading (ADR-0052)

A bond's master data is six nullable fields of the security, settable with
`POST /api/v1/securities` and `PATCH /api/v1/securities/:id` and answered by
every security payload (and selectable with `fields=`):

- `coupon_rate` — the coupon in **percent of face per year**, a Decimal
  string from 0 to 100 (`"2.5"`, not `"0.025"`);
- `coupon_frequency` — `annual` or `semi_annual`;
- `maturity_date` and `issue_date` — ISO dates, the maturity after the issue
  date;
- `face_value` — the denomination, a Decimal string above 0;
- `face_value_currency_code` — the denomination's currency, an ISO 4217 code
  from the set `currency_code` takes.

`coupon_rate` and `face_value` keep 6 decimal places, under the rule every
stored amount follows (**Other stored amounts** above): a finer value is
rounded half up before it is checked, so `"3.1234567"` is stored and
answered as `"3.123457"`. Send them as strings, as every decimal; a JSON
number answers `422` naming the field (**Decimal strings on writes** above).

`null` clears a field, nothing is required, an impossible value is a `422`
naming its field with nothing written, and the fields are kept when the
asset class changes. They are read while the effective asset class is
`bond` or `government_bond`, and — since issue #1068 — while the security
has **no** asset class, stored or inferred (its `asset_class` is `null` and
the name and logo rules infer none), carries a `maturity_date` or a
`coupon_rate`, and has a name the inference does not read as a structured
product's: the name inference recognises government-bond names and, since
issue #1127, the explicit bond words (Anleihe, Schuldverschreibung,
Pfandbrief, Notes, Obligation), so that master data is what marks a
corporate bond named without one and without a class as a bond. A security
with any other class, stored or inferred, is no bond, whatever master data
it carries; a bond whose name carries its issuer's legal form and no bond
word is stored as `equity` on create, as is one with a bond word stored
before issue #1127, and needs its `asset_class` set to `bond`.
The MCP tools `portfolixir.securities.create` and
`portfolixir.securities.update` take them (the update also `null`).

`GET /api/v1/securities/:id` of such a security carries `bond`, computed on
read and never stored (scope-ladder level (a)); it is `null` for any other
security and on listings and write responses:

- `as_of` and `quantity` (the units held across every depot);
- `nominal_held` — `amount`, **quantity × 100**, in `currency_code` (the
  face value's, else the security's): a Portfolio Performance export books a
  percent-quoted bond's quantity as **a hundredth of its face amount**, so a
  quote is both percent of face and the price per unit;
- `remaining_term` — `days` from `as_of` to the maturity, `years` (days ÷
  365, rounded half up at scale 6), `whole_years` and `whole_months`,
  `matured` on and after the maturity date;
- `current_yield` — coupon ÷ price, and `yield_to_maturity` — the **linear
  approximation** (coupon + (100 − price) ÷ remaining years) ÷ price,
  without compounding; each a ratio rounded half up at scale 6 (`0.025707`
  is 2.5707 %), sent without trailing zeros like every decimal (`"0.03685"`,
  `"0"`), with the `price` it used (`value`, `date`, `source`: `quote` for the latest
  stored quote, `trade` for the last own trade price while there is none);
- `two_scales` — `null`, or the finding that the bond is **priced on two
  scales**: its `direction`, its `latest_quote`, the count of
  `unit_scale_bookings` and the `last_unit_scale_booking`, and the `rule`.
  - `direction: "forward"` — a latest quote 20 to 500 times a booked price
    per unit (a buy's or a priced inbound delivery's): quotes near 100
    beside bookings near 1. Every money figure of such a bond is a hundred
    times too high, and the TTWROR does not show it.
  - `direction: "reverse"` (issue #1068) — a latest quote 1/500 to 1/20 of a
    booked price per unit, both ends included, and itself at most 5: quotes
    near 1 beside bookings near 100. The stored quotes are not percent of
    face, and the bond counts a hundred times too low in every total.

  The two booking keys keep their names in both directions and hold the
  bookings inside the band; where a bond has bookings in both bands, the
  forward finding is reported. The `rule` states both bands and which
  securities are read as bonds. Nothing is converted, in either direction.

Every metric carries its own `computation_basis` (`input_series`, `window`,
`reference`, `gaps`, `assumptions`). A figure without its input is `null`
with `insufficient_data: true` and the inputs it lacks in `missing`
(`coupon_rate`, `maturity_date`, `price`); a matured bond's yields are
`null` with `matured: true`. A yield whose price is the last own trade
price at **at most 5** — the two-scales band's mirror, 100 ÷ 20, the price
per unit of a booking that recorded the nominal as the quantity — is `null`
with `price_on_unit_scale: true`, neither `insufficient_data` nor
`matured`: such a price is not percent of face, so coupon ÷ price would be
no yield. A stored quote is a percent price at any level and is always
used; `price_on_unit_scale` is `false` on every other yield. Accrued
interest, fees and taxes are excluded; the reading reports, it does not
evaluate.

### News upkeep (ADR-0056)

The news layer (ADR-0056) fetches registered feeds, binds each item to a
security or a category by rule, groups duplicates into stories and serves
them compactly; an outside model may label the stories. Its surface is
four parts: the upkeep writes here, the [reads](#news-reads-adr-0056), the
[labeller's read and write](#news-labels-adr-0056-7), and the step from a
story to knowledge, which is the [research log](#research-log-adr-0044)'s
`notes.append` with a `cluster_id`, a [security event](#security-events-adr-0048)'s
`news_id` and the [dossier](#the-position-dossier-fr-49)'s news block. The
human view is the News page and each security's News tab
([Product documentation](../product-documentation.html#news)): each region
reads what the read of the same request answers; the page's one write
is the assignment below, the tab's a research entry from a story; feeds
and sources are registered, changed and removed here only, and the page
shows them.

The writes that keep the news layer (§9, B1). Each is journaled under the
calling token and closed: a field it does not take answers `422` naming it.
Answers are compact: short codes, null fields left out.

- `PUT /api/v1/news/feeds` registers or changes a feed from a `feed` object:
  `class` (`issuer`, `regulatory`, `aggregator`, `thematic`), `url`,
  `security_id` (issuer and regulatory) or `category_id` (thematic; an
  aggregator binds to neither), `interval_minutes` (1 to 1,440, else the
  class's default), `language` and `enabled`. With `id` it changes that feed;
  without, the feed registered under `url`, else it creates one (`201`). A
  key not sent keeps its stored value. A URL new to the feed is checked with
  name resolution at once (B2): one that is not https, carries a user name,
  does not resolve or resolves to a private, loopback, link-local or reserved
  address answers `422` on `url` naming its code, e.g.
  `url_not_allowed:private_address`. The class, the binding (`security_id`,
  `category_id`) and the language of a feed with stored items do not
  change: `422` on the field.
- `DELETE /api/v1/news/feeds/:id` removes a feed and its day counters; its
  items stay, detached, until retention. Answers `id` and `items_detached`.
- `PUT /api/v1/news/sources` rates a domain by hand from a `source` object,
  `domain` and `tier` (`primary`, `secondary`, `awareness`, `blocked`); no
  later seed overwrites it. Two puts of a new domain that race both land,
  the later on the earlier's row. A write that changes the domain's tier
  re-rates, in the same transaction, every stored item the domain's row
  decides (the domain and its subdomains, unless a more specific row
  decides them) to the tier a fetch would give it now, an aggregator's at
  most `secondary`, and each story's representative follows the new tiers
  (ADR-0056 E1). An item promoted to a research entry keeps its tier;
  `blocked` removes the others from their stories, and a later fetch that
  lists one again drops it as blocked. The answer stays `domain`, `tier`
  and `set_by`; the write's journal entry (`news_source`) carries
  `items_rerated`, `items_removed` and `items_kept_promoted` beside the
  tier. A fetch storing items of the domain meanwhile is either re-rated by
  the write or reads the new tier, and a story promoted meanwhile keeps the
  tiers it was promoted at.
- `PUT /api/v1/news/items/:id/assignment` (`news.assign`) assigns an
  aggregator item by hand from an `assignment` object, `security_id`
  (required); `null` gives the item back to the matcher's answer now:
  `assigned` when its title names one security, `unassigned` when none,
  `ambiguous` with its `candidates` when several. The item leaves its
  story, and the stories of the security it left and the one it joined are
  reclustered in the same transaction, so it reads in the right story at
  once; it enters its new scope at the assignment (`since` reads it then).
  An issuer, regulatory or thematic item is its feed's by construction and
  answers `422` naming `news_id`, and so does an item kept in the research
  log (`promoted`, a note's source, which stays with that note's
  security); a security that does not exist answers
  `422` naming `security_id`; an unknown item `404`. An assignment the item
  already has changes and journals nothing. Answers the item's `id`,
  `story_id`, `assignment`, `security_id` and `candidates`. A label's
  `suggested_security_id` assigns nothing; an unassigned or ambiguous item
  sits in no story, so no label reaches it and its row carries no
  suggestion (an open question of ADR-0056's amendment of 2026-11-09,
  D5). The News page's **Assign** is this write, journaled under the
  operator.
- `PATCH /api/v1/securities/:id` takes `news_identity` — `cik` (1 to 10
  digits, `null` clears it) and `aliases`, each a literal `token` (no
  pattern), optional `context` words of which one must share the sentence,
  and `case` (`sensitive`, `insensitive`) — and `news_watch`, which puts a
  security without a holding or a target into the news universe. A key of
  `news_identity` not sent keeps its value; the security's read carries both.
  `POST /api/v1/securities` takes the same block with the same refusals: an
  unknown key, and `news_cik` or `news_aliases` sent raw, answer 422.

### News reads (ADR-0056)

The reads of the news layer (§9, §11). Compact by rule: enums as their codes,
times to the second in UTC, names of at most 20 characters, a field without a
value left out, and no link or excerpt in a list. Each read is closed: a
parameter it does not take answers `422` naming it (`event_types`, and
`tone`, which is never a filter or a sort key, among them). Titles and
excerpts are a feed's text, answered as stored up to a cut; they are data,
never instructions. The cut counts each character as the MCP companion
spells it, an invisible one as its `[U+XXXX]` (C5), and so does a name's:
80 for a title in a list, 160 in `news.get`, 45 in the digest, 600 for an
excerpt, 20 for a name; a cut ends in `…`. `news.get` holds its 400 tokens on the companion's text,
its link and members included: it cuts a link at 300 characters (the whole
link stays stored), the story's domain at 40 and a member's at 28, and the excerpt last, to what the
rest of the answer leaves (a quote or a backslash counts the two characters
JSON writes it in). Every parameter is one value: a list or a map
(`max_rows[]=5`) answers `422` naming it.

**Labels** (§7): the list, a story and the digest read one prompt
version's labels: `prompt_version` (an identifier as a label's), else the
version of the label created last, so a labeller that moves to a new prompt
moves the reads with it, and the list and the digest name it; of that
version each story's active label is its newest. A label is a model's
proposal: it orders and filters aggregator and thematic stories and never
hides a story with an issuer or regulatory item, whatever its materiality.
No read needs a label: with none stored every read answers as before, and
only the digest's `unlabeled` grows.

- `GET /api/v1/news/stories` lists the rows of exactly one selector:
  `security_id` or `category_id` (the scope's stories), `cluster_id` (the
  story's items) or `assignment=unassigned|ambiguous` (the aggregator items no
  security, or several, claim). A story row is `id`, `title` (its
  representative's, cut at 80 characters as the companion spells them, so a
  row holds §9's 60 tokens; the story's own answer cuts at 160), `tier`, `at` (the representative's publication, clamped
  to its first sight) and `count`; an item row is `id`, `title`, `tier`, `at`,
  `domain` and, when ambiguous, `candidates` (security ids). A labelled story
  row adds `materiality` and `event_type`. `fields=std` adds
  `url` (cut at 300 characters as `news.get` cuts it) and `note_ids`, and to a story row its representative's `domain`,
  cut at 40 characters as the companion spells it: the source the
  security's News tab shows. Rows come newest first by the time they
  entered their scope; rows of the same instant (one fetch stamps its items alike) by
  tier, primary first, then the newest publication, then the link, never by
  id. `since` reads that time, `scope_at`, the server's clock, never the
  feed's claim (B4, C3): an item's first sight, or the time a later
  re-match, a security merge or a candidate left alone assigned it. A story
  is in when any of its items entered its scope after it, and `as_of` is the next
  `since` (it lies a little early, so a read may repeat a story but never
  skips one). `tier_min` (`primary`, `secondary`, `awareness`) leaves out the
  tiers below it. `min_materiality` (0 to 3, default 0) leaves out the
  aggregator and thematic stories labelled below it, and above 0 the
  unlabeled ones; it reads stories, so with `cluster_id` or `assignment` it
  answers `422`. `limit` is 20 by default and at most 100; when more rows
  matched, `truncated` is `true` and `cursor` continues the page.
- `GET /api/v1/news/stories/:id` answers one story, the only place with its
  link and excerpt: `title`, `url`, `domain`, `excerpt`, `tier`, `language`,
  `published_at`, `first_seen_at`, `count`, at most five `members` (`id`,
  `domain` cut at 28 characters, `tier`, `at`; the representative first), `note_ids`, its
  `security` or `category` (`id`, `name`) and its active `label`
  (`event_type`, `materiality`, `tone`, `confidence` as a string,
  `thesis_note_id` and `clause_idx` when set, `machine_generated` always
  `true`); `prompt_version` chooses the version. The label counts toward
  the 400 tokens, and the excerpt gives way to it.
- `GET /api/v1/news/items/:id` answers one item the same way, with its
  `story_id`, `class`, `assignment`, `status` and, when ambiguous, its
  `candidates`.
- `GET /api/v1/news/health` answers each feed's `id`, `class`, `enabled`,
  `last_ok_at`, `last_error`, `items_24h`, `err_24h`, `stale` (no successful
  fetch for 24 hours; a disabled feed is never stale), `items_30d`,
  `promoted_30d` (the promoted stories its items are in, each once),
  `yield_30d` (`promoted_30d` over `items_30d`, a decimal string rounded to
  4 places, left out for a feed without items) and `low_yield` (`true` for a
  feed with at least 50 items in 30 days and none of its stories promoted;
  A3). Nothing disables a feed by itself: the operator decides. Then the
  day's `unassigned`, `ambiguous`, `dropped` (`cap`, `no_source`, `old`)
  and `blocked` counts.
- `GET /api/v1/news/digest` answers what is new, one row per security: with
  `view_id` the securities that view holds, without it the news universe
  (held, carrying a target weight, or watched). `since` (default 24 hours
  before now) reads `scope_at` as the list does, and `as_of` is the next
  `since`. A row is `id`, `name`, `count` (its new stories), its labelled
  stories' highest `materiality` and `event_types` (at most two, the most
  material first) and `top` (`id`, `title` cut to 45 characters, `tier`,
  `at`): the best tier, then the newest. Rows come by their highest
  materiality, 3 down to 1, then a row of noise (0) or without a label by
  its top story. A story with an issuer or regulatory item always counts; a
  story of aggregator items only, and a thematic story, counts when its
  label's materiality reaches `min_materiality` (0 to 3, default 2) or,
  without a label, with `include_unlabeled=true`, the thematic ones per
  category under `categories`. `hidden` counts the aggregator and thematic
  stories new since then that the two left out (C5), `unlabeled` the new
  stories without a label, and a security whose only news is
  such a story is not counted `quiet`, which counts the securities without a
  row and without one; `unassigned` and `ambiguous` the aggregator items that
  became so since then that no security, or several, claim. With a `view_id`
  the digest is the view's: `categories` and `unassigned` are left out (a view
  holds securities), `hidden` counts only its securities' stories and
  `ambiguous` only the items naming one of them. `max_rows` (default 10, which
  keeps the digest within its budget with every id at its widest; at most 40) caps the rows; `truncated`
  and `more` say how many were left out. `tier_min` is not taken (`422`):
  the class and the label decide what counts, and `hidden` counts what
  they left out, which a tier floor beside them would not. The News page
  reads this digest without `consumer`, so it moves no reader's position.

  **The consumer cursor** (§9, at least once): with `consumer` (an
  identifier as a label's model) the server keeps that reader's confirmed
  position and reads from it, answers it as `since`, and carries a `cursor`
  in place of `as_of`. A new consumer starts 24 hours back. The position
  moves only when the next call confirms the cursor of an answer it handled
  with `ack_cursor`: a call without it reads again from the confirmed
  position, so a run that breaks off after the read loses nothing, and the
  price is a story read twice. For a consumer a story is also new when its
  label of the read's prompt version was written or replaced after the
  position, so a story hidden as unlabelled when the consumer confirmed
  reads once its label shows it. A cursor older than the stored position
  changes nothing; one the server did not issue to that consumer (forged,
  altered or another consumer's) answers `422` naming `ack_cursor`, and
  nothing moves. Two consumers never move each other. `since` beside
  `consumer`, and `ack_cursor` without it, answer `422`. The server keeps at
  most 32 consumers; a new one beyond answers `422` naming the cap. The daily
  retention deletes a consumer whose last confirmation (or, never
  confirmed, its creation) is more than 90 days old, so a name no run uses
  frees its place; named again, it starts as a new one, 24 hours back. A
  cursor is signed with a key derived from `SECRET_KEY_BASE`: after that
  secret changes, a stored cursor answers `422`, and one call without
  `ack_cursor` reads on from the confirmed position. Without `consumer` the
  digest keeps no state.

  **A consumer's truncated answer is paged** (closing act, AT5): it
  carries `next_page`, a page token, and no `cursor`; the consumer sends it
  as `page` (with `consumer`, without `ack_cursor`) and gets the next rows,
  each page within the digest's budget, until the last page, which carries
  the `cursor` to confirm. So a confirmation never passes a row an answer
  left out. The pages read on after the rows already answered, by their
  place in the order, and the last page's cursor is the first page's
  moment, so what arrived while the consumer paged reads after the
  confirmation. Paging moves no position. A page token is signed for that
  consumer and its position with a key of its own: one edited, another
  consumer's, or sent as `ack_cursor` (and a cursor sent as `page`)
  answers `422`. A page token of a position the consumer has confirmed
  past since answers the first page from the new position with
  `restarted: true`. Rows tie, after their materiality and their top
  story's tier and publication, by security id. With `since` a truncated
  answer keeps `truncated` and `more` as before.
- `GET /api/v1/news/registry` (`news.registry`) lists what
  the news page's Feeds and Quellen tabs show, read through the same
  function: every registered feed by id (`id`, `url` cut at 300 characters
  as the companion spells it, `class`, `security_id` or `category_id` (none
  for an aggregator), `language`, `enabled`), then every rated source by
  domain (`domain`, `tier`, `set_by` `hand` or `seed`; a domain without a
  row reads as `awareness`). `limit` (default 40, at most 100) counts feeds
  and sources together; a page with more behind it answers `truncated:
  true` and a `cursor` to pass back. A page at the default limit holds
  about 4,500 tokens at most, however long the links and domains. Each
  feed's health is `news.health`'s. Registering, changing and removing
  stay with [News upkeep](#news-upkeep-adr-0056); an unknown parameter
  answers `422` naming it.

### News labels (ADR-0056 §7)

An outside model labels stories through a script on the operator's machine
that holds its own named token (`PORTFOLIXIR_API_TOKENS`, e.g.
`labeller=<token>`), so every label is journaled under that name. The model
never holds the token: it returns JSON to the script, and the script calls
these two routes and nothing else, directly or through a companion run with
`PORTFOLIXIR_MCP_PROFILE=label`, the profile that alone lists the two tools
([MCP Tools](#mcp-tools)). A label is a proposal (`machine_generated` is
always true): it orders and filters aggregator and thematic stories in the
[reads](#news-reads-adr-0056), never hides an issuer's or a regulator's
story, and moves, assigns or writes nothing else; its
`suggested_security_id` assigns nothing. Without any label every read
answers as before. A labeller that changes its prompt changes
`prompt_version`: the reads follow the version of the label created last,
and the new version's stories come back in `unlabeled` until labelled.
Two labellers on different versions make every read without
`prompt_version` follow whichever created a label last, so run one at a
time or name the version (ADR-0056's amendment of 2026-11-09, D10).

- `PUT /api/v1/news/labels` stores one label from a `label` object:
  `cluster_id` (a story), `model` and `prompt_version` (1 to 64 letters,
  digits or `. _ : / @ + -`, starting with a letter or a digit),
  `event_type` (`earnings`, `guidance`, `capital_measure`, `legal`,
  `m_and_a`, `product`, `regulatory`, `macro`, `noise`), `materiality` 0 to
  3, `tone` -1, 0 or 1, `confidence` a decimal string from 0 to 1 with at
  most four places, and optionally `thesis_note_id` (the story's security's
  current intact thesis, the one the unlabeled read offers; a superseded
  or withdrawn one answers `422`), `clause_idx` (one of its
  clauses, numbered as the unlabeled read numbers them) and
  `suggested_security_id`. A new label answers `201`;
  a put of the same `cluster_id`, `model` and `prompt_version` replaces it
  in place, a full replacement journaled as an update, and answers `200`;
  a put equal to the stored label writes nothing. The schema is closed: a
  field outside it,
  inside `label` or beside it, answers `422` naming it, and so does a wrong
  JSON type, a `confidence` sent as a number (`"must be a decimal
  string"`), and a story, security, thesis or clause that is not there.
- `GET /api/v1/news/unlabeled?prompt_version=` answers the stories without a
  label of that version from any model, newest first, `limit` 10 (at most
  25) with `truncated`: each row's `id`, `security_id` or `category_id`,
  `title`, `excerpt`, `domain`, `tier` and `at`; once per answer the
  `universe` (`id`, a `name` of at most 20 characters, `isin`), the rows'
  `categories`, and per row security with an intact thesis its `note_id`
  and the invalidation condition's `clauses` (`idx`, `text`), split at line
  breaks and semicolons, six listed with `more` counting the rest. Another
  parameter answers `422` naming it. At the default limit the answer holds
  about 6,000 tokens with a 40-security universe; the universe is the
  whole news universe, so a larger one costs more.

### Logos

Each security can carry a logo, resolved automatically (CoinGecko for crypto,
Wikipedia and then companieslogo.com for equities/ETFs/funds, the issuer's
logo for a structured or leverage product) or set manually. A manual logo, or an explicit "no logo", *locks* the security so background
discovery never overwrites the choice.

- `GET /api/v1/securities/:security_id/logo` returns the logo status:
  `{ "data": { "security_id", "path", "source", "has_logo", "locked", "file_missing" } }`.
  `source` is one of `coingecko`, `wikipedia`, `companieslogo`, or `manual`,
  and `null` while there is no logo. `file_missing`
  (issue #933) is `true` when the instance's startup check found no file in
  the logo directory for the stored `path`; `has_logo` is then `false`, while
  `path`, `source` and `locked` read as stored. A discovered logo so marked is
  looked up again; a manual one stays locked and waits to be set again, and
  `logo_status=missing` and `data_quality=missing_logo` list both. Storing or
  removing a logo clears the mark, and so does the next start once the file is
  back.
- `PUT /api/v1/securities/:security_id/logo` sets a manual logo from an image
  URL (`{ "logo": { "url": "https://…" } }` or `{ "url": "https://…" }`). The
  image is downloaded once, validated (png/jpg/jpeg/webp, max 256 KiB) and
  stored locally; the security is locked to the manual choice. A missing URL
  returns `422` with `errors.url`; an image that cannot be fetched or fails
  the check returns `422` with `errors.logo`, a fixed message that names no
  address and no status. The journal entry names the token's principal, and
  its after-image carries `logo_source_host`, the host the URL named.
- `DELETE /api/v1/securities/:security_id/logo` removes the logo and records an
  explicit "no logo" decision (the row falls back to its initials/flag), also
  locking it against discovery. Journaled under the token's principal, like
  the override and the rediscovery; only the background discovery is
  journaled as the system job `logo`.
- `POST /api/v1/securities/:security_id/logo/discover` re-runs automatic
  discovery ("search again"). The response includes a `result` of `updated`,
  `no_source`, or `failed`. Locked securities are left untouched and answer
  `no_source`.

The companion reaches the three writes (Sprint 29 D3, issue #1413):
`portfolixir.securities.logo_put` (`security_id`, `url`; its schema takes an
`https://` URL only, and the API refuses a plain-http or private address as
above), `portfolixir.securities.logo_delete` and
`portfolixir.securities.logo_discover` (`security_id`), each answering the
logo status. The put and the rediscovery make the server fetch, so they
carry `openWorldHint`; both are in the `book` profile. The delete deletes the
stored image, a removal, so it is an admin tool, listed only under `full`.

Example create payload:

```json
{
  "security": {
    "name": "Example ETF",
    "ticker_symbol": "EXM",
    "currency_code": "EUR"
  }
}
```

## Quotes

- `GET /api/v1/securities/:security_id/quotes` lists quote history for one
  security. Optional query params: `from` and `to`, formatted as ISO dates.
  Invalid date filters return `422 Unprocessable Entity` with field errors.
  Each row is self-describing about stock splits (ADR-0028): `close` is the
  **stored** value (never mutated), `adjusted_close` the split-adjusted
  display value, `basis` the row's storage basis (`raw` for as-traded manual
  rows, `provider_mirror` for back-adjusted sync rows) and `adjusted`
  whether a split factor applied. Chart or value with `adjusted_close`;
  audit against `close`. A security whose provider never back-adjusts can be
  flagged with `treat_quotes_as_raw` (see Securities), which forces the raw
  basis for its synced rows.
  `limit` keeps the newest rows of the window, still ascending (default 20000,
  max 50000; zero, negative or non-numeric is a `422`).
- `PUT /api/v1/securities/:security_id/quotes` upserts manual quote rows.
  Every row is stored with source `manual`, whatever `source` it names: a
  close written over the API is a manual close, and the provider sources are
  the quote sync's to state. A manual close wins over provider data, so the
  write replaces a stored row of any source for its dates, and the sync
  leaves a manual row alone until it is released (below). The write is
  journaled under the token (`resource_type=security_quotes`, filed under the
  security's id, operation `upsert`) with the stored rows it replaced — their
  closes and sources — as the before-image. The answer is
  `{"upserted": n, "replaced": [dates]}`: `upserted` counts the rows now
  stored as given, and `replaced` lists the ISO dates whose stored row the
  write changed (a new date is not listed). A write that changes nothing
  leaves no journal entry.
  Every quote row, manual or synced, is bounded: a `close` that is positive
  once rounded to its 6 decimal places, with at most 14 digits before the
  decimal point, on a `date` no later than tomorrow (the instance's calendar day plus one day for
  time zones). A row outside the bound answers `422` naming the field, and a
  sync drops such a provider point instead of failing the run. The
  latest-quote reads (the valuation price, the catalog's latest price and the
  stale-quote check) never use a stored row dated past the bound. One batch
  names each date once and carries only quote objects: a repeated date answers
  `422` with `errors.date` naming it, a row that is not an object `422` on
  `quotes`, and nothing is written.
- `POST /api/v1/securities/:security_id/quotes/release` releases the
  security's **manual** quotes dated `from` through `to` (both required,
  inclusive, in the body or the query) back to provider data: the manual rows
  in the range are removed, journaled under the token (operation `delete`)
  with the released rows as the before-image, and the answer is
  `{"security_id", "from", "to", "released": [dates]}`. Provider rows in the
  range stay, and a range without manual rows changes nothing and writes no
  entry. The next quote sync stores the provider's close for a released date;
  a security without a provider keeps no quote for it. A missing or invalid
  date answers `422` naming it, `to` before `from` `422` on `to`, an unknown
  security `404`. The operator releases from the security's Quotes tab
  (**Release…**, Sprint 17), through the same write.
- `GET /api/v1/securities/:security_id/quotes/manual` reads the security's
  **manual** quotes over its whole stored history — the read a release stands
  on (Sprint 17, `portfolixir.quotes.manual`): `count`, `first` and `last`
  (the first and last manual date, `null` without one), `stored_count` (every
  stored quote, of any source), `stretches` — each a run of manual quotes with
  no quote of another source between them, `{"from", "to", "count"}`,
  ascending, the newest `limit` of them (the list family's: default 100,
  capped at 1000, echoed in `meta.limit`) — `stretch_count` (all of them), and
  `sync_adapter`: whether the quote sync can fetch the security — an adapter
  for its provider that can ask for it (Yahoo needs a ticker) and a `feed`
  other than `MANUAL` or `NONE`, the checks the sync makes before it fetches
  anything. Where it is `false` a released date
  keeps no quote; where it is `true` a fetch can still fail. `from` and/or `to` (inclusive; an absent bound is
  open) add `range` `{"from", "to", "count"}`: the manual quotes a release of
  exactly that range would remove. `to` before `from` answers `422` on `to`,
  an invalid date `422` naming it, an unknown security `404`.
- `POST /api/v1/securities/:security_id/sync_quotes` triggers quote sync for
  one security. The response includes `status` (`ok`, `skipped`, or `error`);
  skipped and error responses may include a `reason` such as
  `missing_ticker` or `no_provider_adapter`, and `persist_failed` when the
  fetched quotes could not be stored. A security whose `feed` is `MANUAL` or
  `NONE` is skipped with `manual_feed` and no provider is asked: that feed
  stops the quote sync on every path, this call, the scheduled sync and the
  page's sync of every security, so `PATCH /api/v1/securities/:id`
  (`portfolixir.securities.update`) setting it is the way to stop provider
  quotes for a security whose quotes you keep by hand. A retired security
  is synced by this call; the scheduled sync and the page's sync of every
  security skip it with `retired` (#1410). Both count as skipped. A
  provider answer that states another currency than the security's
  `currency_code` stores no quote and answers `status` `error` with
  `reason` `currency_mismatch` (#1411): compared as written, so Yahoo's
  `GBp` (pence) is not `GBP`; an answer that states no currency is stored
  as before. A stated value that is not three letters is no currency code:
  it stores no quote and answers `reason` `invalid_currency`, and the
  provider currency kept from an earlier sync stands. A history
  of any length is stored in one sync, and in the scheduled sync one
  security that fails is that security's error while the others are still
  synced. One sync of a security
  runs at a time: while one runs, from any path, a second answers
  `409 Conflict` and calls no provider. A newly created security's quote
  history is fetched in the background on one queue, one security at a time,
  whether it came from the API, the page or an import.

Example quote upsert payload:

```json
{
  "quotes": [
    {
      "date": "2026-05-15",
      "close": "123.45"
    }
  ]
}
```

Example quote upsert response, the first date having replaced a synced row:

```json
{
  "data": {
    "upserted": 2,
    "replaced": ["2026-05-15"]
  }
}
```

Example quote sync response:

```json
{
  "data": {
    "status": "skipped",
    "reason": "missing_ticker"
  }
}
```

## Portfolios and Accounts

> **Portfolio writes are deprecated (ADR-0024) — compatibility only; use
> buckets/views for grouping.** Portfolios were demoted to internal
> compatibility records: the UI groups exclusively through buckets and views,
> and depots/cash accounts no longer need a `portfolio_id` (a deterministic
> internal default is bound automatically). `POST /api/v1/portfolios` and
> `PATCH /api/v1/portfolios/:portfolio_id` keep working but answer with a
> `Deprecation: true` response header. Sunset note: after two releases without
> external portfolio writes, a follow-up story merges the records into
> buckets and views (the ADR's exit criterion) — plan migrations to
> `POST /api/v1/buckets` and `POST /api/v1/views` now. Every record written
> here stays visible in the UI's read-only "Portfolio records (compatibility)"
> admin list, so nothing becomes invisible.

- `GET /api/v1/portfolios` lists portfolios (compatibility records).
- `POST /api/v1/portfolios` creates a portfolio with a `portfolio` object.
  **Deprecated** — answers with `Deprecation: true`; prefer buckets/views.
- `GET /api/v1/cash_accounts` lists cash accounts. Each carries a `balance`
  (decimal string, in the account's own currency) derived on read from the
  ledger: amounts are stored as positive magnitudes and the transaction `type`
  implies the direction (deposits, dividends, interest, tax refunds and sells
  add cash; removals, fees, taxes and buys remove it; a cash transfer debits its
  account and credits the counter account). A `balance_adjustment` snapshot (see
  below) anchors the balance to a stated absolute amount as of its date, after
  which only later bookings adjust it.
- `POST /api/v1/cash_accounts/:id/balance` records an absolute **balance
  snapshot** for one account (ADR-0009): the current balance as of a date,
  instead of mirroring every booking. Body `{"date": "2026-06-01", "amount":
  "4250.00"}` (`notes` optional); `amount` is a decimal string and may be
  negative (an overdraft). It stores a `balance_adjustment` transaction and
  returns it. The balance then anchors to that amount and only bookings dated
  strictly after the snapshot change it, so moving money between own
  accounts needs no transfer entry. Unknown accounts return `404 Not Found`.
- `POST /api/v1/cash_accounts` creates a cash account with a `cash_account`
  object. `portfolio_id` is optional (ADR-0024): when omitted, the account is
  bound to the deterministic internal default portfolio; an explicit id keeps
  winning for compatibility clients. The optional `liquidity_role` (default `free_cash`) classifies the
  account: `free_cash` is genuine deployable cash; `credit_line` is an
  overdraft/Lombard facility whose negative balance is a liability and whose
  unused headroom is never liquidity (it never enters deployable cash, even
  with a positive balance — type beats sign); `reserve` is a visible-but-
  excluded bucket (e.g. a business account). Only `free_cash` accounts with a
  non-negative balance contribute to the valuation's deployable cash and its
  `cash_quote`. An unknown value is rejected with `422 Unprocessable Entity`.
  A `name` another cash account in the portfolio carries as its name or as
  one of its former names answers `422` with `errors.name`, because an import
  naming it already books to that account (ADR-0050 §4).
- Every cash-account and securities-account payload carries **`former_names`**
  (ADR-0050 §4), a list of strings: the names the account was known by. The
  Portfolio Performance import resolves a file's account name by the live name
  first, then by the former names, so a row that names a former name books
  onto this account. Two accounts of one kind in a portfolio never share a
  live or former name; names two accounts already shared before this rule
  resolve to neither, and the import waits for the operator to pick one. A
  name is stored without leading or trailing spaces, as the import reads it,
  so a name that differs from another account's only by them is that name.
- `GET /api/v1/cash_accounts/:id` returns one cash account. An account a
  merge took away answers `404` with `errors.merged_into`
  `{"kind": "cash_account", "id": …}`, the account its history lives on now,
  followed through every later merge (ADR-0050 §12).
- `PATCH /api/v1/cash_accounts/:id` updates a cash account (`name`,
  `currency_code`, `notes`, `liquidity_role`); `portfolio_id` cannot
  be changed. The `currency_code` **freezes** once a transaction references
  the account through either leg or a securities account links to it
  (ADR-0050 §11): a change then answers `422` with `errors.currency_code`
  counting the references, for example
  `["is frozen once referenced (1 securities account, 12 transactions)"]`,
  and nothing is written, so booked history is never re-denominated.
  A rename keeps the previous name in `former_names`, and renaming back to a
  former name consumes it. While another cash account in the portfolio still
  carries the previous name as its live name, the previous name is not kept:
  an import naming it books to that other account (merge or rename that
  account to change this). A new name another cash account carries as its
  live or former name answers `422` with `errors.name`.
- `DELETE /api/v1/cash_accounts/:id/former_names?name=` removes one former
  name, journaled, and answers the account
  (`portfolixir.cash_accounts.remove_former_name`). An import that still names
  '<name>' will then create a new account. A name the account does not carry
  answers `404`, a missing `name` `422`. A name stored before invisible
  characters were refused may be given in the spelling the MCP companion
  lists it in, each such character written `[U+XXXX]`; a stored name of those
  very letters is matched first (E25).
- `DELETE /api/v1/cash_accounts/:id` deletes a cash account that no
  transaction references through either leg and no securities account links
  to. Otherwise it returns `409 Conflict` with `errors.referenced_by` (for
  example `{"transactions": 12, "securities_accounts": 1}`), `errors.remedy`
  `merge` and `errors.remedy_route`, the merge preview
  `GET /api/v1/cash_accounts/:id/merge_preview?target_id=` completed with the
  id of the account to keep: a merge moves the history, a delete never
  discards it. An unreferenced account's bucket links are removed first,
  journaled (ADR-0050 §11). A delete that loses a race to a
  concurrent write, with nothing referencing the row afterwards, answers
  `409 Conflict` with `errors.detail` alone and deletes nothing: read the row
  again and retry (#954).
- `GET /api/v1/cash_accounts/:id/merge_preview?target_id=` previews merging
  the account (the **source**) into `target_id` (the **target**, the account
  that stays) — a read that writes nothing (ADR-0050 §7, §10;
  `portfolixir.cash_accounts.merge_preview`). Both accounts must share the
  portfolio, the currency, the liquidity role and the bucket set; otherwise
  it answers `409 Conflict` with `errors.code` (`same_account`, `not_live`,
  `portfolio_mismatch`, `currency_mismatch`, `liquidity_role_mismatch`,
  `buckets_mismatch`, `legacy_hashed_anchor` for a balance anchor that
  still carries an import hash from before the import-hash kind check and
  would have to be restated or moved, or `unstorable_anchor` for an anchor
  whose restated amount would need more than the amount column's 6 decimal
  places — the other account's balance carries the fraction of a trade
  booked without its amount; record that amount, then preview again),
  `errors.detail` and `errors.guards`; for the last two `errors.anchors`
  names each anchor (`id`, `date`, `cash_account_id`), and for
  `unstorable_anchor` `errors.bookings` names the trades booked without
  their amount.
  An unknown source answers `404`, a source already merged `409`
  `already_merged` with `errors.merged_into`, a missing `target_id` `422`.
  The `200` carries:
  - `plan_digest`, the digest the merge takes;
  - `source` and `target`, each with its `balance` (the fold of every
    booking, as `GET /api/v1/cash_accounts` reports it), `transaction_count`,
    `bucket_ids` and `former_names`; `guards`; `linked_depots` (the source's,
    which move to the target);
  - `internal_transfers`: the transfers between the two, which the merge
    deletes — both legs become one account;
  - `key_equal_pairs`: a source booking whose day, kind and amounts equal a
    target booking's, paired one to one, lowest id first, and
    `choice_required` when there is one;
  - `former_names`: the names the target gains (`appended`), those another
    account already carries (`not_kept`, with `held_by`), and the target's
    list `after`;
  - `outcome_by_collapse_key_equal` with `"false"` (keep both bookings of a
    pair) and `"true"` (delete the source's): the target's `balance` and
    `transaction_count` after, `moved_transaction_ids`, `deleted` (each with
    its `reason`: `internal_transfer`, `collapsed_duplicate` or
    `folded_anchor`), `restated_anchors` (every balance anchor that stands on
    the target afterwards, as `stated` + `other_balance` = `after`: the other
    account's balance at the end of that day, from its bookings before the
    merge; on a day both accounts carry anchors the target's last one holds
    both and the others are deleted), `flow_changes` (the external flows a
    collapse removes — `kind` `removed` — and those it moves into a later
    balance anchor of the account its booking stood on — `kind` `absorbed`,
    the source's own or, for a collapsed transfer, the third account's —,
    each with `cash_account_id`, the anchor's or booking's `transaction_id`,
    `date`, `change` and `collapsed_transaction_id`), `other_accounts` and
    `positions` (what a collapsed transfer or trade changes elsewhere);
  - `balance_basis`, the computation basis of the balances and the restated
    anchors: a balance is the fold of every booking of the account, as
    `GET /api/v1/cash_accounts` reports it; a restated anchor is its stated
    amount plus the other account's balance at the end of that day, from that
    account's bookings before the merge;
  - `reimport_note`, what the merge does to the next Portfolio Performance
    import: the source's names lead there (except one another account still
    carries, `former_names.not_kept`), and a re-import of an export already
    applied creates nothing.

  Every decimal is a string. The digest covers both accounts, every booking
  either references with its `updated_at`, every figure and the guards; the
  choice is not part of it, so one pair has one digest.
- `POST /api/v1/cash_accounts/:id/merge` with `{"target_id": …,
  "plan_digest": …, "collapse_key_equal": …}` merges under the token
  (`portfolixir.cash_accounts.merge`). `collapse_key_equal` is required when
  the preview lists `key_equal_pairs` — `422` without it, naming how many —
  and is never preselected: ask the operator. It answers `201 Created` with
  the **merge record** (`id`, `kind`, `source_id`, `target_id`,
  `portfolio_id`, `source_snapshot`, `manifest` — every booking moved,
  restated or deleted, the depots re-pointed, the bucket links removed, the
  names appended, the choice, `null` where the preview listed no
  `key_equal_pairs` —, `plan_digest`, `actor_type`, `actor_label`,
  `inserted_at`) and `already_applied: false`. In one transaction, one
  audit-journal entry per row: the transfers between the two and, with
  `true`, the source's paired bookings are deleted and their content hashes
  retired; every balance anchor is restated as the preview said; every
  other booking of the source and its linked depots move onto the target;
  the merged balance is checked against the sum of both accounts on every
  day either has a booking and today (`409 identity_check_failed` rolls the
  merge back otherwise — a check for a defect, never an expected answer);
  the source's bucket links are removed and the source is deleted; its name
  and former names become former names of the target, except a name another
  cash account still carries as its live or former name, which is not kept
  (`former_names.not_kept` in the preview) and keeps leading an import to
  that account. A booking, a figure
  or a guard that changed since the preview answers `409` with
  `errors.code` `plan_changed` and the fresh preview in `errors.preview`,
  and writes nothing. A retry of a completed merge of the same pair answers
  `200` with the original record and `already_applied: true`, journaling
  nothing; a source already merged into another account answers `409`
  `already_merged` with `errors.merged_into`. A missing `plan_digest` or
  `target_id`, or a `collapse_key_equal` that is not a boolean, answers
  `422`. There is no unmerge: the record and the journal's before-images
  reconstruct what a merge did. The operator merges from the row menu on
  Accounts & depots (**Merge into…**), which shows this preview and applies
  it with its digest.
- `GET /api/v1/securities_accounts` lists depots/securities accounts.
- `POST /api/v1/securities_accounts` creates a depot/securities account with a
  `securities_account` object. `portfolio_id` is optional (ADR-0024): when
  omitted, the depot is bound to the deterministic internal default portfolio.
  A `name` another depot in the portfolio carries as its name or as one of its
  former names answers `422` with `errors.name` (ADR-0050 §4).
- `GET /api/v1/securities_accounts/:id` returns one securities account. A
  depot a merge took away answers `404` with `errors.merged_into`
  `{"kind": "securities_account", "id": …}`, followed through every later
  merge (ADR-0050 §12).
- `PATCH /api/v1/securities_accounts/:id` updates a securities account
  (`name`, `notes`, `cash_account_id`); `portfolio_id` cannot be changed.
  A rename keeps the previous name in `former_names` under the same rules as
  a cash account's: renaming back consumes it, a previous name another depot
  still carries as its live name is not kept, and a name another depot carries
  as its live or former name answers `422` with `errors.name`.
- `DELETE /api/v1/securities_accounts/:id/former_names?name=` removes one
  former name of a depot, journaled, and answers the depot
  (`portfolixir.securities_accounts.remove_former_name`). An import that still
  names '<name>' will then create a new depot. The name is matched as for a
  cash account, the `[U+XXXX]` spelling included.
- `DELETE /api/v1/securities_accounts/:id` deletes a securities account that
  no transaction references through either leg. Otherwise it returns
  `409 Conflict` with `errors.referenced_by`, `errors.remedy` `merge` and
  `errors.remedy_route`, the merge preview
  `GET /api/v1/securities_accounts/:id/merge_preview?target_id=`. An
  unreferenced depot's default buckets and position overrides are removed
  first, journaled: one entry for the default set, one per position. A delete that loses a race to a
  concurrent write, with nothing referencing the row afterwards, answers
  `409 Conflict` with `errors.detail` alone and deletes nothing: read the row
  again and retry (#954).
- `GET /api/v1/securities_accounts/:id/merge_preview?target_id=` previews
  merging the depot (the **source**) into `target_id` (the **target**, the
  depot that stays) — a read that writes nothing (ADR-0050 §7, §10;
  `portfolixir.securities_accounts.merge_preview`). Both depots must share
  the portfolio and the default bucket set, and every position must keep its
  view membership: for each security the source holds, where the target
  holds it too the two effective bucket sets must be equal; where the target
  does not, the source's set is carried over. Otherwise it answers
  `409 Conflict` with `errors.code` (`same_account`, `not_live`,
  `portfolio_mismatch`, `buckets_mismatch`, or `position_buckets_mismatch`,
  whose `errors.detail` names each position and both bucket sets — or an
  override to carry that holds more than one scope bucket, which the
  target's position cannot take),
  `errors.detail` and `errors.guards`. An unknown source answers `404`, a
  source already merged `409` `already_merged` with `errors.merged_into`, a
  missing `target_id` `422`. The `200` carries:
  - `plan_digest`, the digest the merge takes;
  - `source` and `target`, each with its `cash_account_id`, `bucket_ids` (the
    default set), `former_names` and `transaction_count`; `guards`;
  - `internal_transfers`: the security transfers between the two, which the
    merge deletes — both legs become one depot;
  - `key_equal_pairs`: a source booking whose day, kind, security, cash
    account and amounts equal a target booking's, paired one to one, lowest
    id first, each naming both depot legs (`securities_account_id`,
    `counter_securities_account_id`), and `choice_required` when there is
    one;
  - `position_buckets`: per security the source holds or carries an override
    for, both effective bucket sets, both overrides (`null` for a position
    that inherits its depot's default set, `[]` for a deliberately empty one)
    and the `action`: `carry` (the source's override moves to the target),
    `drop_redundant` (the target already shows the position in the same
    buckets), `drop_unheld` (the source holds no booking of it),
    `clear_target` (the target's override for a security it does not hold is
    cleared, so the moved bookings keep the default set) or `none`;
  - `former_names`: `appended`, `not_kept` and the target's list `after`;
  - `outcome_by_collapse_key_equal` with `"false"` and `"true"`: the target's
    `transaction_count` after, `moved_transaction_ids`, `deleted` (each with
    its `reason`: `internal_transfer` or `collapsed_duplicate`), `positions`
    (every security the source holds, each with `source`, `target` and
    `after`, each `quantity`, `cost_basis`, `avg_cost` and `realized_result`;
    `target` is `null` where the target holds no booking of it),
    `rounding_differences`, `cash_accounts` (each cash account a
    collapsed booking changes, with `balance_before` and `balance_after`)
    and `flow_changes` (each external flow a collapse removes or moves,
    so the change in the time-weighted return is visible; every entry
    carries `kind`, `cash_account_id`, `securities_account_id`,
    `security_id`, `view_id`, `transaction_id`, `date`, `quantity`,
    `change`, `currency_code`, `valued_at` and `collapsed_transaction_id`,
    `null` where a key does not apply: `removed`, a collapsed inbound or
    outbound delivery, its depot and security, `quantity` the change in the
    units that day's flow carries and `change` their value at the
    delivery's booked price in `currency_code` (`valued_at`
    `booked_price`), or `null` where the delivery carries no price and the
    performance walk values the units at the day's price (`valued_at`
    `market`); `boundary_removed`, a collapsed security transfer, buy or
    sell with exactly one leg in the view `view_id`, a flow across that
    view's boundary and none of the portfolio's own, one entry per view it
    straddles: a transfer names the in-view depot and is valued at the
    day's price; a buy or sell names its cash account and depot, and
    `change` is the booked value that view's flow no longer carries, in
    the cash account's `currency_code` (`valued_at` `booked_value`: the
    cash leg negated where the cash account is in the view, the cash leg
    itself where the position is);
    `absorbed`, a collapsed booking's cash leg that a later balance anchor
    of its cash account now absorbs, with the anchor's `transaction_id`,
    `date` and `change`, in the cash account's `currency_code`, as in a
    cash merge's preview) and
    `other_depots` (each third depot a collapsed transfer names, per
    security, with `securities_account_name`, `security_name`,
    `quantity_before` and `quantity_after`: removing a transfer from it
    changes its holding too);
  - `positions_basis`, the computation basis of those figures: the quantity
    is the position fold with each split scaling the position once, rounded
    at volume scale 6 (ADR-0028 §3); `cost_basis` and `avg_cost` are the
    moving-average cost `GET /api/v1/portfolios/:id/holdings` states, in the
    security's currency, fees and taxes not included — after the merge both
    depots' lots combine, so the cost is restated, and a sale the target made
    between two buys now consumes the combined average; `realized_result` is
    the depot's moving-average result, not the app's realized gains: over
    the position's sales, each sale's quantity times its price in the
    security's currency less the cost it removed at the running average, and
    `null` where that price or cost is not derivable. The FIFO realized
    gains (`GET /api/v1/realized_gains`, a security's trades) do not change
    in a depot merge unless equal bookings are removed as duplicates, which
    takes them out of the queue: the FIFO queue belongs to the security, not
    the depot;
    `rounding_differences` lists, per position and split date, each split
    of an affected security where the combined position rounded once
    differs, at the end of the split's day, from the two positions rounded
    apart, with both quantities and their difference — expected and never a
    refusal, and held to no bound per split: where splits compound, a
    difference one split leaves is scaled by the next (ADR-0050, amendment
    of 2026-10-08);
  - `flow_basis`, the computation basis of `flow_changes`: a listed date's
    flow (`GET /api/v1/portfolios/:id/performance`, and
    `GET /api/v1/views/:id/performance` for `boundary_removed`) changes by
    its entries alone; the return of that day and the days after also reads
    the collapsed units no longer held, so the preview lists the flows, not
    a recomputed return; view membership is read as it stands, which the
    merge keeps unchanged;
  - `reimport_note`, what the merge does to the next Portfolio Performance
    import, as for a cash merge.

  Every quantity and decimal is a string. The digest covers both depots,
  every booking either names and the portfolio's splits of their securities
  with their `updated_at`, every figure (the bucket plan among them) and the
  guards; the choice is not part of it, so one pair has one digest.
- `POST /api/v1/securities_accounts/:id/merge` with `{"target_id": …,
  "plan_digest": …, "collapse_key_equal": …}` merges under the token
  (`portfolixir.securities_accounts.merge`). `collapse_key_equal` is required
  when the preview lists `key_equal_pairs` — `422` without it, naming how
  many — and is never preselected: ask the operator. It answers `201
  Created` with the merge record (as for a cash account; its `manifest`
  lists every booking moved or deleted, the overrides `carried`, `dropped`
  and `cleared`, the default buckets removed, the names appended, the
  rounding differences and the choice, `null` where the preview listed no
  `key_equal_pairs`) and `already_applied: false`. In one
  transaction, one audit-journal entry per row: the transfers between the
  two and, with `true`, the source's paired bookings are deleted and their
  content hashes retired; every other booking of the source moves onto the
  target on whichever depot leg names the source, keeping its cash account —
  the target keeps its own linked cash account, the source's stays as an
  account of its own; the target's quantity of every security is checked
  against both depots' bookings on every day either has a booking, every
  split date and today (`409 identity_check_failed` rolls the merge back
  otherwise — a check for a defect, never an expected answer); the bucket
  plan is written, one journal entry per position; the source's default
  buckets are removed and the source is deleted; its name and former names
  become former names of the target, except a name another depot still
  carries (`former_names.not_kept`). A changed plan answers `409`
  `plan_changed` with the fresh preview in `errors.preview`; a retry of a
  completed merge of the same pair answers `200` with the original record
  and `already_applied: true`; a source merged into another depot `409`
  `already_merged`; a missing `plan_digest` or `target_id`, or a
  `collapse_key_equal` that is not a boolean, `422`. There is no unmerge.
  The operator merges from the depot row's menu on Accounts & depots
  (**Merge into…**), through the same preview.
- `GET /api/v1/merges` lists the **merge records**, newest first
  (`inserted_at`, then `id`) — the audit read of a destructive write
  (ADR-0050 §12; `portfolixir.merges.list`). Each record carries `id`,
  `kind` (`cash_account`, `securities_account` or `security`), `source`
  `{id, name}` (the name the merge recorded, since the source no longer
  exists), `target` `{id, name, merged_into}` (`merged_into` is `null` while
  the target lives, otherwise the id a later merge moved it into, followed to
  the live end), `portfolio_id` (`null` for a security), `actor_type`,
  `actor_label` (for an API token, the name of the token entry that applied
  the merge, as the journal's), `inserted_at` and `manifest_summary`: the
  record's `manifest` with every list replaced by its count — bookings moved,
  restated and deleted, names appended, quotes moved and dropped —, beside
  `transactions.deleted` (still every booking the merge removed)
  `transactions.deleted_by_reason`, the same rows counted per reason
  (`internal_transfer`, `collapsed_duplicate`, `folded_anchor`,
  `collapsed_split`; only the reasons present, `{}` when none), and the
  operator's choices as given — `collapse_key_equal` only where the merge
  had key-equal pairs, a security merge's `identity_choice` and
  `isin_changed_on` only where it made that choice (a record written by an
  earlier version may hold them as sent). `meta` carries `order`, `count`
  and `limit`.
  `limit` is the list family's: default 100, capped at 1000, and zero, a
  negative or a non-number answers `422`. The operator reads the same
  records, with the same counts, in **Merges** at the end of Accounts &
  depots (Sprint 17; the survivor's "merged from" date links its entry).

Example account payloads:

```json
{
  "portfolio": {
    "name": "Household Portfolio",
    "base_currency_code": "EUR"
  }
}
```

```json
{
  "cash_account": {
    "portfolio_id": 1,
    "name": "Settlement EUR",
    "currency_code": "EUR"
  }
}
```

```json
{
  "securities_account": {
    "portfolio_id": 1,
    "cash_account_id": 1,
    "name": "Main Depot"
  }
}
```

## Transactions and Holdings

- `GET /api/v1/transactions` lists transactions. Optional filters: `from`/`to`
  (ISO dates, inclusive), `portfolio_id`, `security_id`, `securities_account_id`.
  Invalid filters return `422 Unprocessable Entity` with the offending field.
  An optional `fields=` (FR-37, comma-separated) selects a sparse fieldset:
  each row then carries exactly the requested fields. The names are validated
  against the serializer's own field list — an unknown name is a `422`, never
  a silent fallback. The **human view** of `fields=` (issue #732) is the
  column picker on the transaction history and on the holdings panel: the
  same projections, chosen column by column on the page — and the securities
  list, whose picker predates FR-37, gained the reverse half as its own
  `fields=` (see Securities).
  An optional `running_balance_for=<cash_account_id>` adds a
  `running_balance` to each row — the balance of that cash account after the
  booking, as a Decimal string in the account's own currency — plus a
  top-level `running_balance_basis` naming the account, its currency and the
  fold. Two properties the number depends on: the fold always covers that
  account's **whole** history, so a narrowed read (a `from`, a filter) still
  reports true balances rather than a partial sum; and a row that does not
  move the account carries `null` rather than repeating the previous figure,
  which would read as "nothing happened here". An unknown or non-numeric
  account id is a `422` naming `running_balance_for`. This is the API and MCP
  counterpart of the balance column on the Transactions page.
  `limit` keeps the newest rows (default 10000, max 50000; zero, negative or
  non-numeric is a `422`).
- `POST /api/v1/transactions` creates a transaction of any bookable kind with a
  `transaction` object (per-kind required fields are validated server-side).
  The bookable `type` values are `buy`, `sell`, `dividend`, `interest`,
  `deposit`, `removal`, `fee`, `tax`, `tax_refund`, `cash_transfer`,
  `inbound_delivery`, `outbound_delivery` and `security_transfer`
  (`balance_adjustment` is written through the dedicated balance-snapshot
  endpoint, `split` through the split routes below).
  Booking semantics worth knowing before the first write: a dividend's
  `gross_amount` is the NET cash credited to the account — withheld taxes ride
  in `taxes`, and the income report reconstructs gross as net plus withheld
  tax. An inbound delivery recorded without a
  `price` enters the cost basis at zero — supply the acquisition price when it
  is known; an outbound delivery removes cost at the position's running
  average, so its price is informational only. When reconciling a difference, prefer booking the missing transaction
  of the correct kind — balance snapshots and unpriced inbound deliveries are last
  resorts that make numbers look right while distorting cost basis. Amounts
  are positive magnitudes — the kind implies the direction; only
  `balance_adjustment` may carry a negative (absolute) amount. A **tax
  refund** — for example the tax credited back when a sale realises a loss —
  is therefore never a negative `taxes` value on the sell: book the sell with
  the taxes actually withheld (or `0`), plus a separate `tax_refund`
  transaction whose positive `gross_amount` is the cash credited to the
  account (`cash_account_id` and `gross_amount` are its required fields; the
  changeset rejects a negative `taxes` with exactly this guidance). A security
  settled through a different-currency cash
  account (for example a USD security bought through a EUR account) is booked in
  the security's own currency and carries the cross-currency settlement fields
  `security_amount` (trade amount in the security currency), `settlement_amount`
  (the trade amount in the account currency, before fees and taxes, which are
  recorded in the account currency as well) and `settlement_fx_rate`
  (account-currency units per one unit of the security
  currency). When the rate is omitted but both amounts are supplied it is derived
  as `settlement_amount / security_amount` (the broker's actual rate); a currency
  mismatch with no rate and no amounts to derive one is rejected. Cost basis stays
  in the security currency so per-position P&L is FX-honest. All three are Decimal
  strings and `null` for same-currency bookings. **The cash and the settlement
  must agree** (#395): a cross-currency buy's `gross_amount` (the cash paid,
  fees and taxes included) must equal `settlement_amount + fees + taxes`, a
  sell's (the cash received) `settlement_amount - fees - taxes`, within 0.01
  compared at full precision; otherwise the write answers 422 with a
  `gross_amount` error naming the implied amount. **Without a
  `gross_amount`** the ledger books `quantity × price` (plus fees and taxes on
  a buy, less them on a sale) as the cash, so that is what is compared: a
  trade priced in the security's currency and sent without its cash amount
  answers 422 on `gross_amount` naming both the amount it would book and the
  one the settlement implies — send the cash the broker settled. A trade
  that carries a `settlement_fx_rate` but neither `gross_amount` nor
  `settlement_amount` is refused the same way, 422 on `gross_amount` naming
  the amount it would book: a rate is not the cash the broker settled, and
  nothing is derived from it. The check
  runs on create and on a `PATCH` that changes `gross_amount`,
  `settlement_amount`, `fees`, `taxes`, `type`, `currency_code`,
  `cash_account_id` or `securities_account_id`, or, on a booking without a
  `gross_amount`, its `quantity` or `price` — a `PATCH` of the notes or the
  date of an older booking is never refused by it.
- `GET /api/v1/transactions/:id` returns one transaction.
- `PATCH /api/v1/transactions/:id` updates a transaction (e.g. to fix a
  mis-imported booking); the per-kind validation still applies. An imported
  row keeps its content hash, and a balance anchor or a split never carries
  one (ADR-0050 §1), so changing an imported row's `type` to
  `balance_adjustment` or `split` answers 422 on `errors.type`. A stored
  **split** row changes only its `notes` (E25 S6): a change of its `date`,
  `security_id`, `portfolio_id`, `type` or ratio answers 422 naming the field,
  because a split is booked through `POST /api/v1/splits`, whose checks a
  generic update would pass by. A wrong split is deleted whole
  (`DELETE /api/v1/splits/:transaction_id`, below) and booked again. A buy
  or a sell that stores its cash (`gross_amount`) and no `settlement_amount`
  keeps its cash with its figures (ADR-0053, amendment of 2026-11-02,
  #1371): an update that changes its `quantity`, `price`, `fees` or
  `taxes`, or its `type` between buy and sell, must state `gross_amount` too, or it answers 422 on `errors.gross_amount`
  ("is required when quantity, price, fees, taxes or buy/sell change on a
  booking that stores its cash"); the stated cash must agree with quantity × price
  plus fees and taxes on a buy, less them on a sale, or it answers 422
  "does not match quantity × price, fees and taxes — expected <amount>".
  Agree means: both sides rounded to two places, as ADR-0053 §2 compares an
  imported row, apart by at most 0.01 plus |quantity| × half a unit of the
  price's last digit (read at two to six places), the rounding an imported
  price carries, allowed only while the update leaves the price as stored:
  a price the update sets is exact, so it is checked to the cent (10
  re-priced to 81.00: 0.01; a fee corrected on 10 at a stored 80.00: 0.06).
  A `gross_amount` stated alone, different from the stored one, is checked
  against the stored figures the same way.
  An update of none of these (a note, a date, an account) needs no cash.
  The stored cash is the broker's figure, so it is never re-derived; a
  cross-currency row stored without its legs is checked in the currency it
  is stored in. An update that collides with a concurrent write of the same rows, such as a
  cash-account merge, and loses answers **409** with `errors.detail` only:
  nothing was saved; read the transaction again and retry the update.
- `DELETE /api/v1/transactions/:id` deletes a transaction. Because trades and
  holdings are derived, correcting or removing the transaction fixes them too.
  An imported booking's content hash goes with it, so a re-import of the same
  file books it again (only a merge retires a hash, ADR-0050 §3). On a split
  row it removes that row alone; the split's other rows keep the event.
- `POST /api/v1/splits/preview` previews a stock split booking (ADR-0028)
  without writing anything. The request carries `security_id`, the effective
  `date` (ISO, not in the future) and the ratio as a pair of positive
  integers `ratio_numerator`/`ratio_denominator` (`10:1` forward, `1:10`
  reverse; normalized to lowest terms, so `10:5` previews and books as
  `2:1`). The response shows, per portfolio holding the security, the
  quantity immediately before and after the effective date and the resulting
  current position (all Decimal strings; the ratio parts stay integers),
  plus `warnings`: `effective_date_before_history` means the effective date
  predates the security's earliest recorded transaction — the stored
  quantities may already be post-split (Portfolio Performance's split wizard
  rewrites history destructively), so booking would double-adjust. Check the
  preview before booking. The preview also renders the stored closes around
  the effective date (`quotes_around`) and a `quote_basis_check`
  (misclassification guard, ADR-0028 §2): a visible jump indicates a raw
  series, continuity an already-adjusted one; when that contradicts the
  per-row `source` classification the preview warns with
  `quote_basis_contradiction` (for synced series that never back-adjust, set
  the security's `treat_quotes_as_raw` flag instead of booking blindly), and
  with too few closes on either side it reports
  `insufficient_quotes_to_verify_basis` instead of implying a clean check.
- `POST /api/v1/splits` books the split: **one** call fans the event out
  across all portfolios holding a position in the security at the effective
  date — one journaled `split` row per portfolio, inserted atomically — and
  returns the created transactions (`201`, regular transaction shape). A
  portfolio with zero position at the effective date gets no row. A second
  same-day split for the same security is rejected with `422` on `date`,
  naming the existing event, its transaction and its portfolio by their ids
  (a retried timeout cannot compound the multiplicative event); a future-dated effective date and a security nobody held at the
  effective date are rejected with `422` too. The security's splits, each
  counted by its own magnitude (`2:1` and `1:2` both count 2), may multiply to
  at most `10^12` with the new one included; a ratio past that answers `422`
  on `ratio` from preview and booking alike, and nothing is written (E25 S4).
  The generic
  `POST /api/v1/transactions` endpoint rejects the `split` kind — these two
  routes are the only way a split is booked.
- `DELETE /api/v1/splits/:transaction_id` deletes a split the way it was
  booked, as one fact (Sprint 18 U1, #912): from any of its rows, every
  `split` row sharing that row's security, date and normalized ratio — one
  per portfolio — in one transaction, each row journaled with its
  before-image. It answers `200` with `data.transactions`, the removed rows
  in the regular transaction shape, ordered by portfolio. Afterwards no
  portfolio carries the event: holdings count without it, the quote reads no
  longer adjust for it, and `POST /api/v1/splits` books the corrected ratio
  on the same day. An unknown or already deleted row answers `404`; a
  booking of another kind answers `422` on `transaction_id` naming
  `DELETE /api/v1/transactions/:id`; a failure on any row deletes nothing.
  The security's other splits stay.
- `GET /api/v1/portfolios/:portfolio_id/holdings` lists derived holdings for a
  portfolio, one row per (depot, security). Each row carries `quantity`, a
  moving-average `avg_cost` and `cost_basis` (price-based, so fees and taxes are
  not folded into the unit cost), the `latest_price`, `market_value`, and
  `unrealized_pnl_abs`/`unrealized_pnl_pct` against that price, plus
  `security_name` and `currency_code`. Those figures are in the security's
  **own** currency — enforced by the cost pair the ledger fold carries
  (ADR-0033), no longer an assumption. Since issues #1316 and #1332 a row is
  priced by the rule the valuation's total uses (ADR-0010): the latest quote
  close, else the last own trade price (a buy or sell, across all
  portfolios; a trade booked in another currency is converted into the
  security's at the latest stored rate), so the rows add up to that total.
  Each row names it in `price_source` (`"quote"` or `"trade"`) and
  `price_date`, and `computation_basis.latest_price` states the rule. Only
  a holding with neither a quote nor an own trade returns `null` price,
  market value and P&L, with `price_source` `null`: it is in no total.
  Each row additionally carries
  the ADR-0033 base-currency P&L decomposition: `base_cost` (the
  settlement leg, the cash paid before fees and taxes, with its
  `base_currency`),
  `price_return_abs`/`price_return_pct` (the security's own price move,
  converted at today's rate), `currency_return_abs`/`currency_return_pct`
  (the FX effect on the amount originally invested) and
  `total_return_base_abs`/`total_return_base_pct` — with
  `total = price + currency` holding Decimal-exactly. A row whose
  decomposition is not derivable reports `decomposed: false` with an
  `undecomposed_reason` (`"missing_native_cost"` — no security-currency leg
  in the recorded booking, in which case `cost_basis`/`avg_cost`/P&L are
  `null` too; `"missing_base_cost"` — the settlement leg is not in the base
  currency; `"missing_fx"` — no stored current rate; `"no_price"`), never a
  guessed number. The response is self-describing (FR-13): it carries
  `currency_basis: "security_currency"` plus a `currency_basis_note` naming
  which field is in which currency, and an `as_of` date. Since issue #1142 a
  holding whose `cost_basis` is `"0"` (shares delivered in at no cost, such
  as a spin-off, or bought at a price of 0) keeps its `unrealized_pnl_abs`
  and reads `unrealized_pnl_pct` `null`, never `"0"`: a return on no cost is
  undefined, and `0` would read as flat. The envelope's
  `computation_basis.unrealized_pnl_pct` states the rule. In the same way a
  holding whose `base_cost` is `"0"` reads `price_return_pct`,
  `currency_return_pct` and `total_return_base_pct` `null` beside its three
  amounts, and `computation_basis.decomposition_pct` states the rule.
  Since issue #1212 `computation_basis.fees_and_taxes_in_figures` says what
  the costs count: `cost_basis`, `avg_cost` and `base_cost` are without the
  buys' fees and taxes, and the P&L and its decomposition are measured
  against them, while a closed trade's `basis` on the trades read counts
  them once the shares are sold. The figures did not change: a buy of 10 at
  100 USD settled 790.00 EUR with 6.00 EUR of fees and taxes reads
  `base_cost` `"790"`.
  Holdings are derived
  on read with no stored snapshot, so `as_of` is the read date. Unknown
  portfolios return `404 Not Found`. Optional filters: `security_id`,
  `securities_account_id`. An optional `fields=` (FR-37, comma-separated)
  selects a sparse fieldset per row, validated against the serializer's own
  field list; an unknown name is a `422`.
- `GET /api/v1/realized_gains` (issue #724) returns the Cash-flow
  Realized-gains roll-up: FIFO-matched realized P&L across **all** securities
  and portfolios, grouped by each sale's **close date** into an annual
  `year → month` matrix in the base currency. The FX basis is D-1 (signed
  2026-08-20): each sale converts through the **EUR hub** at the rate stored on
  its own close date; a sale with **no** stored rate for that day is
  **excluded from every converted total and named** in
  `excluded` (`count` + `securities`) — never converted at a neighbouring
  date's rate, never silently dropped. The payload carries
  `computation_basis` (series, window, reference, gaps) and a
  `conversion_note`; the human view is `/cashflow?tab=realized`.
  `limit` bounds the annual matrix to its newest years (default 100, max
  1000); `computation_basis.window` names the cut when years were dropped, and
  the answer echoes the applied `limit`.

  Since issue #807 the payload also carries **`trades`** — the closed
  round-trips themselves, newest close first, each with `security_id`,
  `security_name`, `open_date`, `close_date`, `holding_period_days`,
  `quantity`, `basis`, `proceeds`, `realized_pnl_abs` and `realized_pnl_pct`
  in the trade's own currency and `realized_base` in the base currency — and
  **`summary`**: `realized_total`, `hit_rate` (the share of closed trades
  whose result is strictly positive; a break-even trade counts as a miss) and
  `average_holding_period_days`. The three figures are derived from the
  **same** converted set as the matrix and the list, so an excluded sale is in
  none of the three; with no closed trades `hit_rate` and
  `average_holding_period_days` are `null` rather than `0`, because the
  average of nothing is not zero. `limit` cuts only the matrix's years — the
  figures and the list always read the full history, and
  `computation_basis.summary` states all of this in the payload.

  Since issue #984 every trade also carries **`annualized_return`**: the
  round-trip's money-weighted return per year, as a fraction (`"0.304701"`
  is 30.47 % a year). It is the XIRR solver of ADR-0034 §2 (Act/365) over the
  trade's own flows — each consumed lot's buy on its open date for its
  prorated cost (quantity × buy price plus its buy fees and taxes prorated by
  the quantity taken), and the sell's proceeds on the close date — in the
  trade's own currency, so it annualizes `realized_pnl_pct`, not
  `realized_base`; rounded to 6 places, and a loss stays above −1. It is
  `null` with **`annualized_return_reason`** `no_cost_basis` when the
  trade's `basis` is `"0"` (since issue #1142; this reason comes first,
  because with no cost there is nothing to annualize however long the trade
  was held), `null` with `holding_period_under_365_days` when the trade's
  `holding_period_days` is
  below 365 (ADR-0034 §2 does not annualize a window under a year: 5 % in 14
  days would read as about 257 % a year), and `null` with the solver's
  reason (`no_sign_change`, a total loss among them; `no_root`;
  `amount_out_of_range`) when no rate solves the flows. Dividends and
  interest received while the trade was open are not included.
  `computation_basis.annualized_return` states the rule.

  Since issue #1142 a trade whose `basis` is `"0"` — a buy booked at a price
  of 0 with no fees or taxes, a bonus or free share — reads
  `realized_pnl_pct` `null`, never `"0"`: its `realized_pnl_abs` and
  `realized_base` still state the result, but a return on no cost is
  undefined, and `0` would read as a flat trade.
  `computation_basis.realized_pnl_pct` states the rule.

  Since issue #984 the payload also names the sells the FIFO matcher could
  not pair with a buy, in **`unmatched_sells`**: a `count` and, newest first,
  each sell's `security_id`, `security_name`, `date` and the `quantity` no
  lot covered. Shares that arrived by an inbound delivery open no lot, so
  their sale is no closed trade, and a sell larger than the shares bought
  closes what it can and leaves the rest here. Neither is in the figures, the
  list or the matrix; `computation_basis.unmatched_sells` says so. The
  security's own trades read below lists the same sells as `orphan_sells`.

  Since issue #1108 (the ADR-0015 amendment of 2026-10-07) a trade's fees
  and taxes are read in its cash account's currency, the currency of the
  cash leg they are part of: a cross-currency trade booked in the
  security's currency converts them into it at its own stored
  `settlement_fx_rate` (fee ÷ rate, account units per one security unit),
  never at a hub rate, before they enter `basis` and `proceeds`. So
  `basis`, `proceeds`, `realized_pnl_abs` and `realized_pnl_pct` are in the
  trade's `currency_code`, and `realized_base` is the cash the round trip
  moved when the broker's rate and the hub's agree and the hub rate did not
  move between purchase and sale: 10 bought at 100 USD for
  800.00 EUR with 6.00 EUR in fees and taxes and sold at 120 USD for 960.00
  EUR with 3.00 EUR in fees read `basis` `"1007.5"`, `proceeds`
  `"1196.25"`, `realized_pnl_abs` `"188.75"` and `realized_base` `"151"`.
  A trade booked in its account's currency (a Portfolio Performance
  import's form) adds them as recorded. Since issue #1198 (the ADR-0015
  amendment of 2026-10-09) a closed trade is in its sell's `currency_code`
  whatever booked its lots: each lot enters in that currency through its
  own stored legs, never a rate looked up — an imported lot sold in the
  security's currency at `security_amount` ÷ quantity, its fees and taxes ÷
  its own `settlement_fx_rate`; a booking-form lot sold in the account's
  currency at `settlement_amount` ÷ quantity, its fees and taxes as
  recorded. An imported purchase sold through the booking form so reads
  `basis` `"1007.5"`, `realized_pnl_abs` `"188.75"` USD and `realized_base`
  `"151"`. Such a trade, whose sell closes a lot booked in another
  currency, reads `realized_base` as the cash its bookings moved where the
  sell and every lot it closes carry their stored leg in the base currency:
  the sale's settlement less the lots' (prorated), fees and taxes as
  recorded, no rate looked up (the ADR-0015 amendment's note of
  2026-10-31). Where the hub rate moved between purchase and sale this is
  not the trade's result at the close date's rate: a franc share imported
  for 1,004.00 EUR at 0.94 francs a euro and sold through the booking form
  for 1,154.90 EUR at 0.95 reads `realized_base` `"150.9"`, where the
  close-date conversion of its 153.39 CHF read 161.46. Every trade names
  its path in **`realized_base_source`**, `"settlement_legs"` or
  `"close_date_rate"` (every other trade, a trade whose sell and lots are
  booked in one currency among them), and `computation_basis.realized_base`
  states both. Since issue #1317 `computation_basis.reference` and
  `computation_basis.gaps` name both paths too: the reference is the hub
  rate stored on the close date for `close_date_rate` (never a neighbouring
  day's) and no rate for `settlement_legs`, and the gaps say that a trade
  read on its settlement legs is never excluded under `no_rate`. A lot without the leg it needs (or booked in another account's
  currency), or a lot or a sell priced in a third currency (a row stored
  before issue #1199, even where the two share it), makes the trade
  unavailable: the
  trades read keeps it with its sell's own figures (`proceeds`,
  `sell_fees`, `avg_sell_price`), `null` for `basis`, `avg_buy_price`,
  `buy_fees`, `buy_taxes`, `realized_pnl_abs`, `realized_pnl_pct` and
  `annualized_return`, `unavailable_reason` `"missing_settlement_leg"` and
  `lots_missing_leg` (`open_date`, `currency_code` of each such lot; a sell
  in a third currency names every lot it closes);
  `GET /api/v1/realized_gains` leaves it out of `trades`, the matrix and the
  summary and counts it in `excluded`, whose `by_reason` tells
  `missing_settlement_leg` from `no_rate` (a sale with no close-date rate).
  Every available trade carries `unavailable_reason` `null` and
  `lots_missing_leg` `[]`. `computation_basis.fees_and_taxes` states the
  rule. A new buy or sell priced in neither its security's currency nor its
  cash account's answers 422 on `currency_code`, naming both (issue
  #1199).
  Since issue #1310 an unavailable trade tells its two causes apart.
  `unavailable_reason` is `"third_currency"` where the sell or a lot it
  names is priced in neither the security's currency nor its account's (a
  row stored before issue #1199), which no rate fixes: the remedy is to
  correct the stored booking's currency or amounts. It is
  `"missing_settlement_leg"` otherwise, whose remedy is a rate for the
  lot's date or the figure in the sell's currency on the booking. Each
  entry of `lots_missing_leg` carries its own `reason`, one of the two, so
  a trade closing a legless lot and a third-currency lot names each. Where
  the sell itself is priced in a third currency, `proceeds`, `sell_fees`
  and `sell_taxes` are `null` too, since its fees are in its account's
  currency and no figure under the sell's code could state them;
  `annualized_return_reason` reads the trade's reason.
  `GET /api/v1/realized_gains` counts such a trade under
  `excluded.by_reason.third_currency`, apart from
  `missing_settlement_leg` and `no_rate`.
  Two more causes no rate fixes have values of their own, each on the
  trade, on the lot and under `excluded.by_reason`:
  `"other_account_currency"` where a lot was paid through an account in
  neither the security's currency nor the sale's, so none of its legs can
  ever be in the sale's currency (a dollar share bought through a dollar
  account and sold through a euro account; the backfill gives the sale its
  legs, and the trade stays unavailable; remedy: correct the stored
  bookings' currency or amounts), and `"zero_amount"` where a lot of zero
  amount, a free allotment, lacks its leg, which the rate backfill does not
  complete (issue #1311; remedy: enter the figures on the booking by hand).
  A trade's reason is the first its lots name of `third_currency`,
  `other_account_currency`, `zero_amount` and `missing_settlement_leg`.
- `GET /api/v1/external_flows` (issue #725) returns the Deposits &
  withdrawals roll-up: the booked external **cash** flows (`deposit` and
  `removal`) across all portfolios, per year and month with deposits,
  withdrawals and a net. Deliberately narrower than the performance walk's
  `invested_capital`, which additionally counts securities delivered in/out
  at market value and balance-snapshot residuals — the difference is stated
  in `computation_basis.excludes`. FX basis as in the sibling facet: EUR hub
  at the rate stored on each flow's own booking date, unconvertible flows
  excluded and named by their cash account. Each flow is read in its cash
  account's currency, never the booking's: a deposit booked in another
  currency with a stored settlement rate (ADR-0015) is the cash the account
  was credited, and `computation_basis.currency` states the rule (issue
  #1107). The human view is `/cashflow?tab=flows`.
  `limit` bounds the annual matrix to its newest years (default 100, max
  1000); `computation_basis.window` names the cut when years were dropped, and
  the answer echoes the applied `limit`.
- `GET /api/v1/costs` (issue #726) returns the Costs roll-up: fees and taxes
  across all portfolios at **overview level only**, per year and month with
  yearly fee, tax and combined totals. Since issue #1210 every month carries
  its own `total` beside `fees` and `taxes` — that month's fees plus its
  taxes, as Decimal strings (`{"fees": "5", "taxes": "1", "total": "6"}`) —
  and `computation_basis.totals` states how a month's and a year's totals are
  formed. The series sums the fee and tax
  **legs** riding any transaction plus the standalone `fee`/`tax` bookings,
  with `tax_refund` netted against taxes; gross amounts are never summed —
  a buy's gross **includes** its legs while a sell's is **net** of them, so
  a gross sum would describe something else. The legs-not-gross rule is
  stated in `computation_basis.series`. FX basis as in the sibling facets:
  EUR hub at the rate stored on each booking's own date, unconvertible costs
  excluded and named by their **currency**. Since issue #1107 each cost is
  read in its cash account's currency, the currency of the cash leg it is
  part of, as the performance walk reads trade costs: a cross-currency
  trade's fees and taxes are converted from the account's currency, never
  from the security's, and an unconvertible one is named by the cash
  account's currency; a booking without a cash account is read in its own.
  `computation_basis.currency` states the rule. The human view is `/cashflow?tab=costs`.
  `limit` bounds the annual matrix to its newest years (default 100, max
  1000); `computation_basis.window` names the cut when years were dropped, and
  the answer echoes the applied `limit`.
- `GET /api/v1/sales/hindsight` (`portfolixir.sales.hindsight`, in every
  profile; FR-50, idea I18; Sprint 25 plan D-3)
  answers **what each sale missed**: one row per sale booking (type `sell`,
  an orphan sell included; an outbound delivery is no sale, it moves shares
  without a price), newest first, with the sold security's price return in
  EUR over four spans after the sale. Read-only; nothing is stored, every
  read derives the figures from the closes and rates stored at that moment.
  Optional `portfolio_id`, `security_id`, `from` and `to` (the sale date,
  both inclusive) narrow the rows; `limit` caps them (default 100, at most
  500) and the answer echoes it with `truncated`. An optional `benchmark=`
  is the benchmark comparison's (ADR-0046): `rate:<decimal>`, a fixed annual
  rate compounding daily, or `security:<id>`, any security with a stored
  quote, flagged `is_benchmark` or not, refused as on the comparison below;
  `computation_basis.benchmark_security` names its kind as there (`null`
  without a security); without it each span answers the
  security's own return only. The answer is `{as_of, spans, benchmark, include,
  rows, limit, truncated, computation_basis}`, `include` echoing the
  `include` applied (`[]` without one). A row carries `sale_id` (the
  booking's transaction id), `portfolio_id`, `securities_account_id`,
  `date`, `security` `{id, name, currency_code}`, the booked `quantity`, `price` and `currency_code`, and
  `start`: the close standing for the sale day (the last positive close on
  or before it, at most 7 days older), `{stands_for, date, close,
  stored_close, source, fx_rate, eur_value}`, or `null` with `start_reason`.
  The booked price is shown beside it and enters no figure: both sides are
  measured from a close. Each of the four `spans` carries `span` (`1m`,
  `3m`, `12m`: the sale day shifted by calendar months; `latest`: the date
  of the security's latest stored close, today at most), `end_on`, `days`,
  `status`, `reason`, `security` `{return, start, end}`, `benchmark`
  `{return, start, end}` (`start` and `end` `null` for a rate) and
  `difference`, the security's return minus the benchmark's. `status` is
  `complete`, `pending` (the span ends after today; no figure) or
  `incomplete` with `reason` `no_start_close`, `no_end_close`, `no_fx_rate`
  or `no_benchmark_close`, where the security's own figure is kept. A sale
  at a close of 100 followed by 110 a month later reads `"0.1"` for `1m`;
  against a benchmark from 200 to 210, a benchmark return of `"0.05"` and a
  difference of `"0.05"`. It is a price return: distributions after the
  sale are not booked, so a dividend payer's miss is understated, and
  `computation_basis` (input series, window, reference, gaps, `price_only`,
  `sales`, `booked_price`) says so. No field gives a verdict. A malformed id,
  date, `limit` or `benchmark` answers `422` naming it, `to` before `from`
  `422` on `to`; an unknown id answers no rows. The human view is **After
  the sale** under the trades list of `/cashflow?tab=realized` and on a
  security's Trades tab (Sprint 26), computed by the same function.

  **What a switch cost** (`include=reinvestment`; I18 mode 3, ADR-0057):
  each row gains `reinvestment`, the purchases the sale's money went into,
  **found by rule, never chosen**. The proceeds (the sale's booked cash
  amount on its cash account, after its fees and taxes) go into the buys
  that debit the same cash account, dated from the sale's date to 30
  calendar days after it, of any security other than the one sold; oldest
  proceeds first (by sale date), each buy taking at most its own cash
  debit, so a larger buy is funded in part. Same-day sales and same-day buys
  share **pro rata** (each sale by its remaining proceeds, each buy by its
  remaining debit), never by booking id: a booking deleted and booked again
  unchanged moves no figure. A `tax_refund` of the sold security on the
  sale's date and cash account joins that sale's proceeds whatever order
  the two were booked in. The block carries `status` (`matched` or
  `no_match`), `reason` (`no_buy_within_30_days`,
  `proceeds_taken_by_earlier_sale`, `no_cash_account`), `cash_account_id`,
  `currency_code` (the cash account's), `proceeds`, `buys` (`buy_id`,
  `date`, `security`, `quantity`, `cash_debit`, `amount_taken`,
  `share_of_buy`), `days_to_first_buy` (calendar days from the sale's date
  to the first matched buy, `0` on the sale day),
  `share_of_proceeds_matched` (the ADR's `a`: the sum the buys took over
  the proceeds) and `unallocated` (money that waited, left out). Per FR-50 span, `kept` is `a` × the sold
  quantity × the sold security's close at the end, `switched` each matched
  buy's share × its quantity × the bought security's close at the end (a
  buy dated after the end counts as cash in its account's currency at the
  end's rate), and `difference` is `switched + taxes_apart − kept`, both in
  EUR and **before tax**: the fees are inside it and named as
  `fees_inside` (a buy's own taxes are part of its debit, so inside the
  difference and not in `fees_inside`); the sale's taxes are named as
  `taxes_apart` (a refund negative) and added back, because the kept
  position's latent tax is not booked. They are added back as cash at face
  value, so it is not a fully before-tax comparison: the difference is off
  by about `−taxes_apart` × the bought security's return since the buy.
  A sale whose booked cash is not positive (a write-off at price 0) reads
  `no_cash_account`. It is **price only**: `income_apart` names the bought positions'
  distributions and is never added. A span is `pending`, or `incomplete`
  with `side` (`kept` or `switched`) and its reason. A sale of 1000 whose
  money bought 5 at 200, the sold close moving from 100 to 110 and the
  bought one to 210, reads `kept` `"1100"`, `switched` `"1050"` and
  `difference` `"-50"` for `1m`. `computation_basis.reinvestment` states
  the rule, the window, the order, the spans, the prices, before tax, price
  only, that money is fungible (a deposit in between could have paid the
  buy), that dates carry no time and that a `cash_transfer` is not
  followed. `benchmark=` and `include=reinvestment` combine. Any other
  `include` value, an empty one or a list (`include=reinvestmnt`,
  `include=`) answers `422` on `include`, so a misspelled include value
  never drops the block silently. An unknown key is ignored, as on every
  read (`includ=reinvestment` answers `200` without the block); `data`
  echoes the include applied as `include` (`[]` or `["reinvestment"]`),
  as it echoes `benchmark`, so a missing block is never silent. No verdict
  and no total over all switches.
- `GET /api/v1/holdings/by_security` returns the **global per-security
  valuation** across **all** portfolios: one `holdings` row per currently held
  security with its `security_id` (an integer), total `quantity`, and current
  `market_value` converted to the **EUR hub**, plus a `valued` flag. `valued`
  is `false` (and `market_value` is `null`) when the security has neither a
  quote nor a trade price, or no exchange-rate path to EUR, so a missing quote
  or rate never silently distorts a value. Each row also carries the resolved
  native `latest_price` with `price_currency` and `price_source`, and an
  `unvalued_reason` that says *why* a row is unvalued: `"no_price"` (nothing
  resolves at all) or `"missing_fx"` (the price is known but no stored rate
  path reaches EUR); `null` when valued. Rows are sorted by `security_id`.
  The response is self-describing: a top-level `currency` of `"EUR"`, an
  `as_of` read date (the report is derived on read, so `as_of` is today's date,
  not a stored snapshot), and a `note` describing the hub conversion. This is
  the cross-portfolio, base-currency counterpart to the per-portfolio holdings
  list (which stays in each security's own currency with no FX); for one
  portfolio's totals and weights use the valuation endpoint instead.
- `GET /api/v1/holdings/negative` returns the **negative-holdings
  data-quality report**: every (depot, security) position whose derived
  quantity is below zero — import debris from unmodeled corporate actions —
  as `rows` (with `depot_name`, `security_name`, `isin`, `portfolio_id` and
  the negative `quantity` as a Decimal string) plus `totals` with each listed
  security's total quantity across **all** depots, so transfer debris
  (negative in one depot, positive in another) is distinguishable from a
  truly negative total. Self-describing with an `as_of` read date and a
  `note`. Nothing is repaired automatically; fix the security's transaction
  history.
- `GET /api/v1/splits/incomplete` returns the **incomplete-split check**
  (#1292): every stored split event (its rows sharing security, date and
  normalized ratio) that carries no row for a portfolio holding the security
  entering the effective date — the set `POST /api/v1/splits` books for. Such
  a portfolio's FIFO lots are scaled by the split while its holding is not.
  Each row names the security (`security_id`, `security_name`, `isin`), the
  `date`, the integer `ratio_numerator` and `ratio_denominator`, the booked
  rows' `booked_portfolio_ids` and `transaction_ids`, and
  `missing_portfolios`, each with `portfolio_id`, `portfolio_name` and
  `quantity_before` (a Decimal string). Self-describing with `as_of`, a
  `note` and a `remedy`: book the same split again through
  `POST /api/v1/splits`, which adds only the missing rows, or delete a wrong
  event with `DELETE /api/v1/splits/:transaction_id`. Read-only and
  uncapped, like the negative-holdings report; nothing is booked or
  rewritten.
- `GET /api/v1/transactions/rate_only` returns the **rate-only trades**
  (#1290): every stored buy or sell booked in another currency than its cash
  account's that carries a `settlement_fx_rate` but neither `gross_amount`
  nor `settlement_amount` — the shape a new write is refused for (H35) —
  whatever the size of its gap. Each row carries its ids, `security_name`,
  `cash_account_currency_code`, `date`, `type`, `currency_code`, and as
  Decimal strings `quantity`, `price`, `fees`, `taxes`,
  `settlement_fx_rate`, `booked_cash` (quantity × price plus fees and taxes
  on a buy, less on a sell: the cash the ledger books), `expected_cash` (the
  same with quantity × price × rate as the settlement) and `difference`
  (`booked_cash - expected_cash`). Self-describing with `as_of`, a `note`
  and a `remedy`: record the cash the broker settled as the trade's
  `gross_amount` (`PATCH /api/v1/transactions/:id`), after which the row is
  no longer listed; the settlement backfill does not touch these rows.
  Read-only and uncapped.
- `GET /api/v1/transactions/cash_mismatch` returns the **trades whose cash
  misses their figures** (#1371; ADR-0053, amendment of 2026-11-02): every
  stored buy or sell with a `gross_amount` and no `settlement_amount` whose
  cash does not agree with quantity × price plus fees and taxes (a buy),
  less them (a sale), as the PATCH above reads agreement (`tolerance_rule`
  says how) — a row edited before the rule, whose cash balance reads the stored cash while its FIFO lots and
  realized gains read the figures. Each row carries its ids,
  `security_name`, `cash_account_id`, `date`, `type`, `currency_code`, and
  as Decimal strings `quantity`, `price`, `fees`, `taxes`, `stored_cash`,
  `derived_cash`, `difference` (`stored_cash - derived_cash`) and its
  `tolerance`; ordered by date, then id. A row that passed §2 at import is
  not listed. Self-describing with `as_of`, a `note` and a `remedy`:
  state the cash in the booking form (Edit) or as `gross_amount` with
  `PATCH /api/v1/transactions/:id`, the amount settled or the one the
  figures give; a row stated within its tolerance leaves the list. Read-only and
  uncapped; nothing is rewritten.

  These three checks have one human view (Sprint 23): the Overview's
  data-quality line names each above zero, its count the read's row count,
  and links to the transaction history filtered to exactly the read's rows —
  `/transactions?dq=cash_mismatch`, `?dq=rate_only`, `?dq=incomplete_split`
  (a split event's `transaction_ids`) — so an agent can hand the operator
  that link. `dq=` is the page's parameter, not the API's:
  `GET /api/v1/transactions` takes no such filter, because these three reads
  are its twins and carry the figures the page shows.
- `POST /api/v1/holdings/reconcile` compares a **user-supplied external
  position list** (a broker statement or depot overview, parsed client-side
  into rows) against the ledger-derived holdings — **strictly read-only**:
  the list arrives only in the request body, is never persisted or logged,
  and no data is fetched from anywhere (ADR-0029 §6, FR-35). Each row is
  `{identifier, quantity}` with optional `currency` and an optional pinning
  `security_id`; `quantity` must be a **canonical dot-decimal string**
  (anything else — comma decimals, thousands separators, exponents — is a
  `422` naming the row; locale parsing is the client's job), and an empty
  `rows` list is a `422`. Identifiers match through the same stable-identity
  ladder the import uses: an ISIN-shaped string (format and check digit)
  matches via the ISIN tier only (current ISINs first, then recorded former
  ISINs — `matched_via: "former_isin"`); any other string is tried against
  WKN, ticker+currency and name+currency with the exactly-one rule applied
  across the union of those tiers — a string matching one security's WKN and
  another's ticker lands under `ambiguous` with the candidate securities,
  never a silent pick, and a currency-less row cannot match by ticker or name
  (`unmatched` with reason `currency_required`). The response is
  self-describing (`basis` with `as_of`, `scope`, and a delta note) and
  reports: `matched` rows (one per security — rows resolving to the same
  security are aggregated with their external quantities summed and the
  contributing rows listed), ordered by the **lowest input row index** each
  match aggregates so a finding maps back to the submitted line, each embedding
  the security's identity only (`id`, `name`, `ticker_symbol`, `isin`, `wkn`,
  `currency_code`), with the `matched_via` tier (`isin`,
  `former_isin`, `wkn`, `ticker`, `name`, or `pinned`), `ledger_quantity`,
  `external_quantity` and `delta` (`external - ledger`) as exact Decimal
  strings — ticker/name matches carry `weak_match: true` and the caveat
  "confirm the security before booking" —, `ambiguous` and `unmatched` rows,
  and `missing_from_list` (held ledger positions the external list does not
  cover). The embedded `guidance` is part of the contract: resolve a
  difference by booking the missing transaction of the correct kind; balance
  snapshots and unpriced deliveries are last resorts that distort cost basis.
  Optional scope: `portfolio_id` or `view` (a view id; mutually exclusive —
  both at once is a `422`), default the whole instance; an unknown portfolio
  or view is a `404`.
- `GET /api/v1/portfolios/:portfolio_id/valuation` returns a live valuation of a
  portfolio: each held position priced from its latest quote close, a
  `total_value`, and each valued position's `weight` (its share of the total).
  Each position's market value is converted into the portfolio
  `base_currency` (top-level field) from stored exchange rates; per-position
  `security_currency` shows the native currency. A security without any quote
  is priced at the latest own trade price (`price_source: "trade"`, counted in
  the top-level `trade_priced_count`); a quoted position carries
  `price_source: "quote"`. Every position carries `price_date`, the date its
  price is from, and the top-level `stale_priced_count` counts the quoted
  positions whose quote is older than the data-quality staleness threshold
  (the same `?dq=stale_quote` day count) — the remedy is the security's
  `is_retired` flag, which the performance walk keys on, or a quote sync; a
  retired holding is therefore not counted, its stale close is expected.
  The top-level `newest_quote_date` is the newest stored quote date across
  the quoted, non-retired positions (`null` when none is quote-priced) — the
  freshness fact the Overview's key-figure strip shows; the view valuation
  carries both fields as well.
  A position with neither price **or** no
  exchange-rate path to the base currency is returned with `valued: false`,
  `price_source: null` and `null` market value and weight, so a missing price
  or rate never distorts the total. Unknown portfolios return `404 Not Found`.
  Weights are raw shares (`market_value / total_value`) emitted at full Decimal
  precision; because they are normalized ratios they need not sum to exactly
  `1` (round for display). Market values and `total_value` are exact.
  The valuation also carries cash: `cash_balances` lists each cash account
  (`balance` in its own currency, plus `base_value`/`valued` after converting to
  the base currency, its `liquidity_role`, and a `deployable` flag), `total_cash`
  is the base-currency sum of the valued cash accounts (so a drawn credit line's
  negative balance still reduces it), and `total_with_cash` is
  `total_value + total_cash`. `cash_quote` is the deployable-cash share of the
  portfolio: deployable cash is the sum of `free_cash` accounts with a
  non-negative balance (`deployable: true`), and the quote is computed as if the
  other accounts did not exist (`counting_cash / (total_value + counting_cash)`,
  `0` when there is nothing to value yet) — so a reserve account or a credit line
  stays listed and inside `total_cash` without ever reporting fake liquidity. The
  response also emits `counting_cash` (Decimal string) — the deployable cash that
  enters the quote — so a consumer can reconstruct `cash_quote` itself. An
  account whose currency has no rate path to the base is reported
  `valued: false` and excluded from `total_cash`, mirroring how unpriceable
  positions are handled. `unvalued_cash_count` (#1081) counts such accounts
  that hold a non-zero balance — the money `total_cash` and
  `total_with_cash` leave out; an empty one is listed with `valued: false`
  and not counted — in every form of the read, with or without
  `include_positions`, so the roll-up-only read states the gap too; the
  `valuation_note` states the rule.
  The response is self-describing (FR-13): it carries an `as_of` date (the read
  date — the valuation is computed live with no stored snapshot) and a
  `valuation_note` stating that totals are in `base_currency` via the EUR hub and
  that the per-position `price_source` and `valued` fields indicate price
  staleness. An optional `include_positions=false` (FR-37) returns the
  roll-up only — totals, cash balances and cash quote without the
  per-position rows; the response states which shape was returned via
  `positions_included`.
- `GET /api/v1/portfolios/:portfolio_id/performance` returns the portfolio's
  **true time-weighted rate of return (TTWROR)**, computed the Portfolio
  Performance way: the portfolio is valued daily (quotes on or before each day,
  converted at that day's rates, plus cash), external flows — deposits,
  removals, deliveries, and balance-snapshot jumps — are neutralised, and daily
  returns chain geometrically (see ADR-0010). Optional query params: `period`
  (`ytd`, `1y`, `3y`, `5y`, `max` — default `max`; an unknown period returns
  `422 Unprocessable Entity`), `year=YYYY` for one calendar year, `from=`/`to=`
  (ISO dates, both required, `from <= to`) for a custom range — both clamped
  honestly to the available history, with a backwards or malformed range
  returning `422` — and `series=true` to include the daily points
  (`date`, `value`, `flow`, `cumulative_ttwror`). The response carries
  `ttwror`, `start_date`/`end_date`, `start_value`/`end_value`,
  `net_external_flows` as Decimal strings, and `suspect_dates` — dates of
  bookings older than 1970 (import typos) whose effects were applied on the
  first plausible day. Alongside `ttwror` the response also carries the
  **money-weighted return** `irr` — the single annualised rate that discounts
  the period's dated external flows and terminal value back to zero
  (`NPV(r) = Σ cf/(1+r)^(days/365) = 0`), the figure Portfolio Performance
  shows next to TTWROR. It is a Decimal string, or `null` when no rate exists
  (fewer than two flows, all flows the same sign, or the solver does not
  converge) or when an amount lies outside the range the solver's one float
  step carries, which only implausible stored data reaches; the read never
  fails on such an amount, and `computation_basis.gaps` names these cases
  (E25 S4). Securities without quotes are priced at the latest own trade
  price (see the valuation endpoint). Unknown portfolios return
  `404 Not Found`. Since the daily walk may be served from a durable derived
  value (ADR-0039), the response is **never silent about freshness**: `as_of`
  (ISO-8601 datetime) is the instant the walk was computed — possibly older
  than the request when the underlying data has not changed since — and
  `stale` (boolean) marks a superseded value served while a fresh one
  computes; a stored value is invalidated by every write that can affect it,
  so `stale: false` means current against the ledger. The response also
  states the metric's **computation basis** (`computation_basis`): the input
  series, the effective window, the reference series (`null` — TTWROR/IRR
  have none) and the treatment of gaps. A cash account in a foreign currency
  counts zero on every day it holds money while its currency has no rate
  path to the base currency, and the day the first rate arrives its whole
  balance enters the end value without being a flow: `unvalued_cash_accounts`
  names each such account of the scope that counted zero on a window day or
  on the day before the window, whose close is the start value (#1055,
  ADR-0051 §10) — `cash_account_id`, `name`, `currency_code`, `balance` (its
  native balance on its last such day, a Decimal string in that currency,
  never converted), `unvalued_days` (its days, the day before the window
  (the start value) included), `unvalued_reason` (`no_rate`),
  `unvalued_through_end` (`true` when it still counted zero on the window's
  last day) and `first_rate_date` (the ISO date the currency's first rate
  path arrived when that falls inside the window and the account held money
  at zero on the day before, else `null`) — sorted by name, `[]` when every
  balance was valued; `computation_basis.gaps` names the field.
- `GET /api/v1/portfolios/:portfolio_id/performance/benchmark` returns the
  **benchmark comparison** (ADR-0046, FR-9): the portfolio's own external
  flows replayed into a benchmark, the read that answers "was the effort
  worth it". `benchmark=` is required — `rate:<decimal>` for a fixed
  effective annual rate compounding daily from a base of 1 (Act/365;
  `rate:0.02` is 2 % p.a., the savings-account baseline and, in v1, how
  inflation is expressed; accepted between `-0.999999` and `10`, the IRR
  solver's own domain) or `security:<id>` for **any catalog security with
  at least one stored quote, flagged `is_benchmark` or not** (ADR-0046's
  amendment of 2026-11-07, #1416: a fund you hold can be the benchmark and
  stays bookable and in every data-quality check; `GET
  /api/v1/securities?is_benchmark=true` lists the flagged reference
  instruments). A security with no stored quote answers `422`, `{"errors":
  {"benchmark": ["has no stored quote"]}}`; an unknown id answers `422`,
  `{"errors": {"benchmark": ["is not a benchmark security"]}}`. A security a
  merge took away is refused the same way; when the survivor at the live
  end of its merge chain has a stored quote, the body adds `merged_into`
  `{"kind": "security", "id": …}` naming it, as the merged-away reads do,
  and a retry with that id compares (#959). A survivor without a stored
  quote, a chain that ends at a row deleted since, and an id no merge names
  answer without it. The view and
  the view-less comparison below answer the same. `period`, `year`, `from`/`to`, `view=`
  and `series=true` behave like the performance read. The response carries
  `benchmark` (`kind`, then `annual_rate` or `security_id`/`name`/
  `currency_code`), `requested_window` and `window` — the days the
  comparison actually covers, `window.rebase_day` naming the close the
  benchmark is rebased to (the close before the window, or the window's
  first day when it opens with no value): a flow dated before the
  benchmark's first *priced* day (a close and a rate path to the base
  currency; a stored close of 0 is not a price) is not replayed on its own
  day — it enters through the window's opening value and is listed in
  `excluded_flows` (`date`, `flow`) — and both sides are chained over the
  covered window — then the two comparisons Portfolio Performance shows.
  `bought_once` is flow-neutral: `benchmark_return`, the benchmark rebased
  at `rebase_day`, next to `portfolio_ttwror` over the same window; with
  `series=true` it also carries the daily `cumulative_return` points for a
  chart overlay. `savings_plan` is flow-matched: `invested_capital`,
  `portfolio_end_value` and `benchmark_end_value` — the window's opening
  value and every external flow invested into the benchmark at that day's
  price (a fixed rate: at par) — `end_value_delta` (real minus synthetic,
  the figure that answers the question), `portfolio_irr` and
  `benchmark_irr` (ADR-0034's XIRR on identical dated flows),
  `portfolio_mwr` and `benchmark_mwr` (the non-annualized period rates a
  window shorter than a year reads instead) and `benchmark_units`. All
  financial values are
  Decimal strings; `as_of`/`stale` carry the walk's freshness (ADR-0039) and
  `computation_basis` states the input series, the window, the reference,
  the treatment of gaps and the `assumptions` — the synthetic portfolio is
  frictionless (`frictionless: true`: no fees, no taxes), which biases the
  comparison against the real portfolio. The basis names a benchmark
  security as `security <id> (<currency>)`, never by its stored name, which
  travels only as data in `benchmark.name` (E25), and
  `computation_basis.benchmark_security` says which kind it read:
  `flagged` (flagged `is_benchmark`, held or not), `held` (not flagged,
  held today in any depot) or `unheld`; `null` for a fixed rate. A missing or malformed `benchmark`
  is `422`; a portfolio with nothing to walk, or a benchmark without a quote
  in the window, answers `null` figures with `window.start_date: null` and
  every flow named in `excluded_flows`. A cash account whose balance counted
  zero before its currency's first rate — the jump that rate brings sits in
  `portfolio_ttwror` and `end_value_delta` — is named in
  `unvalued_cash_accounts`, the performance read's entries for the covered
  window (`[]` without one; #1055). `costs_paid` (ADR-0046, amended
  2026-11-04) reports what the frictionless benchmark never pays: the
  `fees` and the `taxes` the real portfolio booked in the
  `requested_window`, both days included, as Decimal strings in the base
  currency, by the cost facet's rule (`GET /api/v1/costs`: the fee and tax
  legs of any booking plus the standalone `fee` and `tax` bookings,
  `tax_refund` netted against the taxes, each converted at the EUR-hub rate
  stored on its own booking date). A cost counts where the cash account
  that paid it counts: in the portfolio the account belongs to, in a view
  whose buckets hold the account, always in the total; a fee on a buy whose
  depot is in the view and whose cash account is not is outside the view.
  It is the same for every benchmark of one request. A cost with no stored
  rate on its day is left out of both sums and named in `excluded`
  (`count`, `currencies`); `costs_paid.window` and its own
  `computation_basis` state the rule. It is not subtracted from
  `end_value_delta`, and no residual is named: a cost paid early would
  have compounded until the window's end, which the booked figure leaves
  out. A 5.00 EUR fee on a buy in the window reads `fees` `"5"`, `taxes`
  `"0"`. Nothing is persisted: the comparison
  is derived on read and memoised like the walk it depends on.
- `GET /api/v1/portfolios/:portfolio_id/performance/contribution` returns the
  **contribution analysis** (FR-41, ADR-0051): which position made how much of
  the period's money result, the "+x EUR in the period" figure beside the
  TTWROR. `period`, `year`, `from`/`to` and `view=` behave like the
  performance read, and so do its errors (a malformed `view` or period `422`,
  an unknown portfolio or view `404`). Each row of `positions` carries
  `security_id`, `name`, `isin`, `start_value`, `end_value`, `net_flows`,
  `income`, `costs` and `contribution` — `end_value − start_value − net_flows
  + income − costs`, in the base currency with the currency move included —
  where `income` is the dividends and the interest bookings that name the
  position's security (a bond's coupon), each as credited; a coupon credited
  to an in-view account counts even when its position sits outside the view
  (#928, ADR-0051's amendment of 2026-10-09; computation version 4) —
  plus `held_at_start`, `held_at_end`, `unvalued_days` and `unvalued_reason`
  (`no_price`, `no_rate` or `null`). `costs` are the fees and taxes of the
  position's own trades, converted from each trade's cash account currency,
  the currency they are recorded in (#1051); a trade with no rate for its
  price currency flows in at its cash leg less those costs. A position bought
  and sold inside the window is listed although it is held at neither end. A
  day on which a held
  position has no price or no rate path counts zero, as in the walk, and the
  position stays in the sum, named with its days. A foreign-currency cash
  balance held before its currency's first rate counts zero the same way,
  and the first rate brings its whole value into `cash_currency_effect`:
  `unvalued_cash_accounts` names the account, exactly as the performance
  read of the same scope and window does, with its native `balance`, its
  `unvalued_days` (the day before the window included),
  `unvalued_through_end` and the `first_rate_date` (#1055). The rows are sorted by
  contribution, largest first, with no share, rank or label. `remainder`
  holds what no position does, each line summed from its own bookings and
  never a plug: `interest` (the interest bookings that name no security:
  account interest, and every coupon stored without its bond),
  `standalone_fees_and_taxes` (fee, tax and tax-refund bookings no trade
  carries) and `cash_currency_effect` (the revaluation of foreign-currency
  cash, a trade's settlement difference between its cash leg and price ×
  quantity plus costs, and what a cash transfer between currencies leaves).
  `totals` carries `result` (`end_value −
  start_value − net_external_flows` of the performance read over the same
  window), `positions` and `remainder`, and `positions + remainder =
  result`, exact in Decimal while the conversion quotients terminate and to
  34 significant digits otherwise. The response carries `portfolio_id`,
  `view_id` (`null` unscoped; a `view` also echoes `view: {id, name}`),
  `period`, `base_currency`, `start_date`/`end_date`, `as_of`/`stale` and
  `computation_basis` with `assumptions`; all financial values are Decimal
  strings. A window holding no walked day — a future year, a range before the
  history — answers `start_date: null`, no positions and `"0"` lines and
  totals, as the performance read answers it. Nothing is persisted.
- `GET /api/v1/portfolios/:portfolio_id/performance/bands`,
  `GET /api/v1/views/:view_id/performance/bands` and
  `GET /api/v1/performance/bands` return the **stacked value chart's bands**
  (I23, FR-53) beside the contribution read, in its three forms and with its
  period parameters (and `view=` on the portfolio form): the performance
  read's value series split into bands that sum to it exactly on every day
  (at the category level within one unit in the 34th significant digit per
  band added when a conversion quotient does not terminate, as
  `computation_basis.input_series` states). The view and view-less forms answer in EUR, or in `base_currency=` (a
  supported currency code, echoed as `base_currency`): the Wealth screen
  asks in its page's base currency, so the two agree when asked alike; the
  portfolio form answers in the portfolio's base currency. `level` is `total` (one band, the series), `category` (the default: one
  band per root category of the classification, plus `cash` and
  `unclassified`) or `security` (one band per security plus `cash`). A call
  without `level` answers `category`; the Wealth screen's default level is
  its own choice and does not change the API's. **`category_id=` filters
  every level** (FR-56) to that category's subtree, without `cash` and
  `unclassified`, so the bands add up to the category's band one level up:
  at `total` one band, the category's line (key `category:<id>`); at
  `category` one band per direct sub-category over its subtree plus one
  band of kind `direct` (key `direct:<id>`, the category's own id and name,
  `color` null) for the securities filed in the category itself, absent
  when it holds none, or, for a category without sub-categories, one band,
  its own; at `security` its securities. `category_id=unclassified` filters
  to the securities the tree files nowhere: one band `unclassified` at
  `total` and `category`, one band per security at `security`. The
  `direct` band carries the plain name; the screen labels it „‹name›
  (direkt)“ in its own language. The answer echoes `category_id` (the id,
  `"unclassified"` or `null`) and `computation_basis.filter`.
  `classification_id=` picks the tree; without it the category
  level stacks by the tree the scope's allocation targets use, else the
  first custom classification, else the built-in asset classes, and
  `classification.chosen_by` says which (`requested`, `targets`, `default`,
  `category`). `sort` is `size` (the last day's value, largest first, the
  default) or `change`. The response carries `level`, `sort`,
  `classification`, `category_id`, `category`, `dates` and `bands`; each
  band has `key`,
  `kind`, `id`, `name`, `color` (the category's own colour, else `null`),
  `tree_index`, `values` (Decimal strings aligned with `dates`),
  `start_value`, `end_value`, `net_flows`, `share` (of the last day, a net
  share: above 1 or negative when a band is negative) and
  `change` (`(end_value − start_value − net_flows) / start_value`, `null`
  without a positive start value; a security's net flows are ADR-0051's).
  More than eight bands merge the smallest into `other` (with its
  `members`), ties by name, never by id; `cash` and `unclassified` keep
  their own, and `other` is always the last band, on top of the stack,
  whatever the sort. An unpriced day counts zero, as in the series, and a security
  is drawn in its category of today for the whole window;
  `computation_basis` states each rule. **`scale=ttwror`** (FR-57; `scale`
  is `value`, the default and the answer above, or `ttwror`, echoed as
  `scale`) answers each band as a line instead: its own time-weighted
  return over the window, not stacked, since returns do not add up. Its
  flows are ADR-0051's net flows of its securities per day (buys, sells,
  deliveries, boundary flows; a group's the sum of its members'); the
  day's net flow counts at the day's start when it is an inflow,
  `1 + r = V / (V_prev + F + B)`, and at its end when an outflow,
  `1 + r = (V − F) / (V_prev + B)`, `B` the day's trade-price basis step as
  in the walk, and a day without a positive base contributes no return,
  nor does a day whose opening value `V_prev + B` is not positive (a
  short covered inside the window adds no return; the line waits until
  the band opens above zero again). A
  band holding a value at the close of the day before the window chains
  from it, as the view's line does; else its line starts at 0 % on its
  first day with a value. After its start a day on which it holds nothing
  and moved nothing has no point, so a band sold out inside the window ends
  at the sale day. Dividends, interest and trade costs are no flow: they
  move cash, which has no line. At most eight lines, the largest by value
  on the window's last day, ties by name and never by id (bands equal in
  value and name at the cut are both left out); never `other`, and without
  `category_id` no `cash` or `unclassified`. Each line has `key`, `kind`,
  `id`, `name`, `color`, `tree_index`, `start_value`, `end_value`,
  `net_flows`, `returns` (the cumulative return through each of `dates`, a
  Decimal string, `null` where the line has no point) and `ttwror` (its
  last point); `sort=change` orders the lines by `ttwror`. `parent` is the
  line one level up: the view's own TTWROR (the performance read's
  `cumulative_ttwror` series, exactly) without `category_id`, the filter's
  band with it. The view's line counts every flow at the day's start, the
  bands an outflow at its end, so a band that holds the whole view can
  differ from it on a day with a sale; `computation_basis.reference` says
  so; `null` with `scale=value`. `computation_basis` names
  `flows`, `start_rule` and `selection_rule` in place of `merge_rule`. An
  unknown `level`, `sort` or `scale`, a
  malformed or unknown `classification_id` or `category_id` (anything but an
  id or exactly `unclassified`), or a category of another tree answers
  `422` naming the parameter, and so does an unsupported `base_currency`.
  Nothing is persisted.
- `GET /api/v1/portfolios/:portfolio_id/income` returns the **retrospective
  income report**: the dividends and interest already booked in the ledger,
  aggregated three ways (no forecast — the dividend calendar is a separate
  feature). `annual` is a list of years (newest first), each with `months` (a
  map keyed by month number `"1"`–`"12"`, each carrying `dividends` and
  `interest`), and per-year `dividends_total`, `interest_total`, `total` and
  `excluded_count`, the year's payments left out of every total for want of
  a rate (below); a year whose payments are all left out keeps its row, with
  `"0"` totals (#1293).
  `positions` is the per-position table, one row per security and payment
  currency, the cash account's currency (#1274): an interest booking that names a security (a bond's coupon) is
  that security's row, and the interest naming none shares the row with
  `security_id` `null` (#928): `security_id`, `security_name`,
  `security_currency` (the security's own currency; the payment currency on
  a row naming no security), `currency` (the payment currency),
  `native_gross`, `native_tax` and `native_net` (in `currency`), `gross`,
  `tax` (the withheld tax stored on the transaction, a dividend's or an
  interest booking's) and `net` (`gross - tax`), converted into the base
  currency, `payment_count` and `last_payment`. A USD security paid once
  into a USD account and once into a EUR account has two rows. `transactions` is the
  per-transaction detail for a year drilldown (`kind`, `date`, `year`,
  `security_id`/`security_name`, `currency`, the native `native_gross`/
  `native_tax`/`native_net`, the base-currency `gross`/`tax`/`net`, and
  `converted`). A dividend's gross is its net cash (`gross_amount`) plus the
  withheld tax (`taxes`), and an interest booking's, a bond's coupon included,
  is read the same way: an interest row booked with withheld taxes reads
  `gross` = net + tax, `tax` = the stored taxes, `net` = the cash credited; one
  booked without taxes has `gross` equal to `net` (#1309). Nothing stored
  changes, and the writes keep accepting taxes on interest. All amounts are Decimal strings
  in the portfolio's `base_currency`, converted via the EUR hub at the most
  recent stored rate on or before each booking date (the same mechanics as the
  valuation endpoint), with the original currency retained. A booking with no
  such rate path is excluded from every total (`annual`, its months,
  `positions`) and named in `excluded` (`count`, and per currency its
  `currency_code`, `count`, `securities` and `interest_count`, its payments
  naming no security), as the other Cash-flow reads
  do; `transactions` keeps it with `converted: false`, its native amounts and
  `null` base-currency `gross`, `tax` and `net` — never its native amount at
  parity (security review 2026-10-12, K07). `unconverted_count` counts it,
  `conversion_note` states the basis and `computation_basis` (`series`,
  `currency`, `window`, `reference`, `gaps`, `positions`) the rule.
  A booking's cash and withheld tax are read in its cash account's currency,
  the currency it was credited in (the ADR-0015 amendment of 2026-10-07): a
  dividend of a USD security credited to a EUR account is converted from
  euros, and its `transactions` row's and its `positions` row's `currency`
  name EUR, the currency their `native_*` amounts are in.
  Unknown portfolios return `404 Not Found`.
  Since ADR-0020 a target plan **belongs to a view**: the target read/write
  endpoints accept an optional `view` (a view id). Omitting it (or sending
  `null`) addresses the portfolio-wide **Gesamt** plan — the behaviour before
  views existed. A view carries its own plan, so the same classification can hold
  a different plan per view without the plans summing across each other. A
  malformed `view` returns `422 Unprocessable Entity` (`{"view": ["is
  invalid"]}`) and an unknown view id returns `404 Not Found`, the same
  structured contract the analytics endpoints use.
- `GET /api/v1/portfolios/:portfolio_id/targets` lists a portfolio's stored
  target weights (the target side of the allocation). Optional `classification_id`
  scopes the list to one tree; one that is not an id answers `422`
  (`{"classification_id": ["is invalid"]}`, issue #1301), on this read and on
  `/position_targets`, beside `plan_id` or alone; optional `view` selects the
  plan (omitted = Gesamt); optional `plan_id` reads that plan version, a draft or the active
  plan, with the `422`s of the `PUT` below (issue #1185). Unknown portfolios
  return `404 Not Found`.
- `PUT /api/v1/portfolios/:portfolio_id/targets` upserts target weights for one
  classification. The body is `{"classification_id": id, "targets": [{"category_id":
  id, "target_weight": "0.25"}]}` and may carry an optional `"view": id` to write
  that view's plan (omitted = Gesamt). Each `target_weight` is a string fraction
  in `[0, 1]` with at most 6 decimal places (four in percent); a finer weight
  answers `422` on `target_weight`, and the database refuses it too unless the
  instance already held a finer weight when it was upgraded (the upgrade then
  logs how many). Duplicating a plan, or saving it in the SOLL editor, rounds
  such a stored weight half up to 6 decimal places. A weight refused for its
  precision or for lying outside `[0, 1]` also names its row, as the plan
  editor puts the refused row first: `errors.row` is `{"category_id": id,
  "security_id": id}`, with `security_id` `null` for a category row, beside
  `errors.target_weight` (issue #1143). Targets need not sum to
  `1`. Only the supplied categories are
  changed. A category from another tree returns `422 Unprocessable Entity`, and an
  unknown classification returns `404 Not Found`. A batch names each category
  row once and carries at most one row per category and one per security
  assigned in the classification, and never more than `10000` rows; a repeated
  category row or a larger batch answers `422` (`errors.detail` naming the
  category, or `errors.targets` stating the bound) and writes nothing.
  **Position-level SOLL
  (ADR-0030):** a target entry that also carries a `"security_id"` sets a weight
  on that individual position under the category (the security must sit under it,
  else `422`); a category entry (no `security_id`) and its position entries are
  stored side by side. A present `security_id` must be a positive integer or
  `null` (`null` = category row) — anything else (a non-numeric string, a float)
  returns `422` instead of being coerced into a category write. A plan carries
  at most **one position row per security**: filing a security under a second
  category, or naming the same `(category, security)` twice in one batch,
  returns `422`. The database holds the rule as well, so a write that loses a
  race to file the security under another category answers the same `422`
  and stores nothing. Each serialized target carries `security_id` (`null` for
  a category row).
  **A plan version (issue #1133):** an optional `"plan_id": id` writes that
  plan version — a draft from `POST /api/v1/plans/:id/duplicate`, or the
  active plan — instead of the view's active plan, so a draft's category and
  position targets are edited over the API as in the SOLL editor, and
  activated when ready; the two target reads take the same `plan_id` (issue
  #1185), and without it follow the active plan. The plan
  must be one of this portfolio's, of this classification and, when `view` is
  given, of that view, and it must not be `archived`: an archived version
  steers nothing and is reused by activating it or duplicating it into a
  draft. A malformed id, an unknown plan or another portfolio's, another
  classification's, another view's and an archived one each answer `422` on
  `plan_id` (`is invalid`, `is not a plan of this portfolio`, `is a plan of
  another classification`, `is a plan of another view`, `is archived: activate
  it, or duplicate it into a draft`) and write nothing.
- `DELETE /api/v1/portfolios/:portfolio_id/targets/:category_id` removes a
  portfolio's **category** target for one category and returns `{deleted}` (the
  number of rows removed). Position rows for the category are left in place.
  Optional `view` selects the plan (omitted = Gesamt); optional `plan_id`
  addresses a plan version as on the `PUT`, with the same `422`s.
- `GET /api/v1/portfolios/:portfolio_id/position_targets` lists a portfolio's
  **position-level** SOLL targets (ADR-0030): `{"position_targets": [...],
  "effective_targets": [...]}`. Each `position_targets` row is a target on a
  security under a category (with `security_id` and `security_name`); each
  `effective_targets` entry
  is a category's roll-up — `explicit` (the category-row weight or `null`),
  `position_sum` (the sum of the position rows filed directly under it —
  descendants' rows roll up to their own category), `effective` (the resolved steering
  weight — the position sum wins) and `conflict` (`true` when explicit and
  position sum disagree, surfacing the mismatch). Each position row also carries
  `stale` (`true` when its security no longer sits under the stored category —
  reclassified or unassigned; the row still counts where it was filed, re-filing
  is the remedy) and each roll-up `has_stale`. Weights are Decimal strings.
  Optional `classification_id` / `view` scope as above. Read ergonomics
  (FR-37, issue #740): `min_drift=` — the allocation read's threshold, same
  spelling (a non-negative Decimal string on `|drift_weight|`) — returns only
  the position rows whose drift meets it, where `drift_weight` is the
  security's actual weight in the steering basis minus its position target,
  renormalised as the allocation renormalises a short plan (ADR-0040), exactly
  as the allocation computes it (one predicate, two surfaces). Kept
  rows carry `drift_weight`; rows without a drift are filtered out; the
  response states the applied `min_drift`, `position_targets_total` (the
  pre-filter count) and a `drift_basis` sentence. Without `min_drift` the rows
  carry no `drift_weight` and the shape is unchanged. An invalid threshold is
  a `422`. Optional `plan_id` reads that plan version, with the `422`s of the
  `PUT` (issue #1185): its rows, its `effective_targets` and, with
  `min_drift`, the drift against its targets as the allocation would measure
  it with that version active, in its view; for a draft, `drift_basis` says
  so and names the plan.
- `DELETE /api/v1/portfolios/:portfolio_id/position_targets/:category_id/:security_id`
  removes one position target and returns `{deleted}`. The category row and the
  category's other positions are untouched. Optional `view` selects the plan;
  optional `plan_id` addresses a plan version as on the `PUT`.
- `GET /api/v1/portfolios/:portfolio_id/plans` lists a portfolio's SOLL **plan
  versions** (ADR-0027): active first, then drafts and archived plans, each with
  `name`, `status` (`active` / `draft` / `archived`), its scope (`view_id`,
  `classification_id`) and `cash_target_weight` as a Decimal string. Optional
  `classification_id` scopes to one tree; a value that is not an id is
  ignored, and every plan is listed. Only the **active** plan of a scope
  steers the allocation.
- `POST /api/v1/plans/:id/duplicate` copies a plan version (category and
  position targets, and cash target) into a new **draft** of the same scope and
  returns it with `201 Created`. Optional body `{"name": "Plan 2027"}` names the
  copy (default: `"<source name> (copy)"`).
- `POST /api/v1/plans/:id/activate` makes a draft or archived version the active
  plan of its scope, archiving the previously active plan in the same
  transaction. Activating the already-active plan is a no-op.
- `PATCH /api/v1/plans/:id` renames a plan version (`{"name": "..."}`).
- `DELETE /api/v1/plans/:id` deletes one plan version (any status) including its
  category and position targets. Deleting the active plan leaves the scope
  without a plan (the allocation falls back to actual-only). Each target is
  journaled as its own `target` delete before the plan's `target_plan` delete.
- `GET /api/v1/snapshots` lists depot **snapshot markers** (ADR-0027): each is a
  `name`, a scope (`view_id`, `null` = everything) and an `as_of` date. A
  snapshot copies no financial data — the holdings it represents derive from
  the transaction ledger on demand.
  `limit` keeps the newest snapshots (default 1000, max 10000); the answer
  echoes the applied `limit`.
- `POST /api/v1/snapshots` creates a marker
  (`{"name": "...", "as_of": "2026-02-15", "view_id": 3}`; `view_id` optional).
  A future `as_of` or a duplicate name within the scope returns
  `422 Unprocessable Entity`.
- `DELETE /api/v1/snapshots/:id` deletes one marker; no transactions or
  holdings are affected.

### Recorded tax statements (ADR-0031)

**These pots are recorded, not derived** — and the reason is *not* a missing
FIFO. Portfolixir matches lots FIFO already (`GET
/api/v1/securities/:id/trades`), and that gives a **gross gain**. A gross gain
is not a tax pot: Teilfreistellung, Vorabpauschale, chronological allowance
consumption and certified prior-year carry-forward are not in the transaction
data at all, and the pots are kept per tax-reporting institution, which
Portfolixir does not model. A derived pot would be wrong, and invisibly so — so
these endpoints transcribe a broker statement, they never compute one from
holdings. Every money value is a
**positive magnitude** Decimal string: a loss pot is the volume of loss
available for offsetting, not the negative number the statement prints, and a
negative input is rejected rather than silently flipped. Nothing here is tax
advice, and the recorded statement remains the authority. (A tax actually
credited back to a cash account — for example after a loss sale — is a ledger
event, not a pot: book it as a separate `tax_refund` transaction as described
under "Transactions and Holdings" above.)

- `GET /api/v1/tax/parameters` lists the year-scoped statutory parameters
  (optional `jurisdiction`, currently only `DE`): `capital_gains_tax_rate`,
  `solidarity_surcharge_rate` and the `saver_allowance_single` /
  `saver_allowance_joint` ceilings. Rates are Decimal string **fractions**
  (`"0.25"`, never `"25"`). Seeded 2009–2026; a year with no row is simply
  absent — the API never substitutes a neighbouring year's ceiling.
- `PUT /api/v1/tax/parameters` inserts or replaces one year's parameters
  (`{"parameters": {"tax_year": 2027, ...}}`).
- `GET /api/v1/tax/profiles` lists a holder's effective-dated tax profiles
  (required `holder`; a missing one returns `422 Unprocessable Entity`), newest
  `valid_from` first. The profile in force for a date is the row with the
  greatest `valid_from` at or before it — never an exact match. Church-tax
  liability defaults to **not liable** with rate `0`.
- `POST /api/v1/tax/profiles` records a profile from a date
  (`{"profile": {"holder": "...", "valid_from": "2024-01-01"}}`). A non-zero
  `church_tax_rate` on a not-liable profile is rejected.
- `PATCH /api/v1/tax/profiles/:id` corrects one profile row. To record a
  *change* in the situation, create a new row with a later `valid_from` —
  editing rewrites history, adding does not.
- `DELETE /api/v1/tax/profiles/:id` deletes one profile row. Snapshots already
  recorded keep their frozen church-tax rate and are unaffected.
- `GET /api/v1/tax/allowance_orders` lists the Freistellungsaufträge the
  taxpayer **instructed** (optional `holder`, `institution`, `tax_year`;
  free-text filters fold case, so `comdirect` and `Comdirect` are one
  institution). Every `holder` and `institution` the tax endpoints write or
  filter on is normalised one way — composed to NFC, invisible format
  characters removed, every run of Unicode spaces one space, a value that is
  only such characters a `422` — and matched by the database's own case
  fold on both sides, the fold of the unique indexes (E25 S6).
- `PUT /api/v1/tax/allowance_orders` records or replaces the instructed amount
  for one `(holder, institution, tax_year)`
  (`{"allowance_order": {...}}`).
- `DELETE /api/v1/tax/allowance_orders/:id` deletes one configured order.
- `GET /api/v1/tax/statement_snapshots` lists recorded statements (optional
  `holder`, `institution`, `tax_year`), newest `as_of` first. Each row carries
  the eleven recorded figures plus `allowance_remaining`,
  `tax_free_trim_budget`, `expected_capital_gains_tax`, the `as_of` they rest
  on, a `stale` flag, and the advisory `findings`. Each row also carries the
  activity-aware `staleness` assessment (#667): staleness as a function of
  activity, not only of the calendar. It states its own computation basis —
  `age_days` against `age_threshold_days` (90), `activity_since_count` (the
  ledger transactions of `activity_kinds` — `sell`, `dividend`, `interest`,
  `tax`, `tax_refund` — dated strictly after `as_of`), the two component
  warnings and the combined `warning`, plus a `basis` note recording that
  bookings are not attributed to an institution or tax year. `warning` is the
  signal to act on; the bare `stale` flag flips the day after any `as_of` and
  is kept for compatibility.
- `POST /api/v1/tax/statement_snapshots` records a statement
  (`{"statement_snapshot": {"institution": "...", "holder": "...",
  "tax_year": 2025, "as_of": "2025-12-31", ...}}`). `as_of` must not lie in the
  future. Omit `church_tax_rate` to take the holder's profile in force at
  `as_of`; the resolved rate is then frozen on the row, so a later profile edit
  never rewrites a recorded transcription. Re-recording the same
  `(institution, holder, tax_year, as_of)` is a `422`, not a silent duplicate.
  A recorded statement's `source` is `manual`, set by the system: a `source`
  in the body of a create or a correction is ignored. Who wrote it is a
  separate pair (security review K12): `author` is who recorded it and
  `corrected_by` who corrected it last (`null` until a correction), each
  `operator` for the Tax page and `agent` for an API or MCP token, derived
  from the write's credential and never read from the body. An update that
  changes nothing sets no `corrected_by`. An allowance order carries the same
  pair for its first put and its last replacing put. Rows stored before
  authors existed take what their journaled creation and last correction
  name, `null` without one.
- `GET /api/v1/tax/trim_budget` rolls the latest statement per institution up
  to one holder and year (required `holder` and `tax_year`); institutions are
  grouped by the database's case fold, so a later statement under another
  case spelling of one bank replaces the earlier one. It reports which
  `institutions` it covers, which of them rest on a statement the agent
  recorded or corrected last (`agent_institutions`, K12), the `as_of` of its
  **oldest** component, the
  summed `allowance_granted` and `allowance_used` the fill level on the Tax
  page is read from (beside `allowance_remaining`), and
  `complete: false` with `missing_institutions` when a configured allowance
  order has no recorded statement for the year — the total is then a partial
  picture and says so. The response carries the same `staleness` assessment,
  computed against the roll-up's (oldest) `as_of`.
- `GET /api/v1/tax/statement_snapshots/:id` reads one recorded statement.
- `PATCH /api/v1/tax/statement_snapshots/:id` corrects one recorded statement
  in place — the re-issued-statement case.
- `DELETE /api/v1/tax/statement_snapshots/:id` deletes one recorded statement.

Consistency findings are advisory and computed at read time. A finding names
the `recorded` and the `expected` number and the `gap`; it never proposes a
corrected value and never blocks a write. Two rules are hard instead, and come
back as `422` changeset errors: allowance used above allowance granted, and
church tax withheld at a zero church-tax rate.
- `GET /api/v1/portfolios/:portfolio_id/snapshots/:id/comparison` answers
  "would I have done better keeping what I had?": the snapshot's frozen
  holdings valued **buy-and-hold** over the stored quote history (daily, EUR-hub
  FX) against the scope's real TTWROR since the as-of date. The response
  carries `as_of_value`, `current_value`, `snapshot_return`, `real_ttwror`, a
  daily `series` (`snapshot_value`, `snapshot_indexed`, `real_indexed`), a
  `gaps.unvalued_securities` list of securities excluded for missing quotes or
  FX at the as-of date, and a self-describing `basis` (gross, price-return only
  in v1; it carries the `window`, the `base_currency`, and `costs_removed` /
  `costs_kept` naming which cost kinds left the return). All financial values
  are Decimal strings.

  **The two sides are not on one basis, and the payload says so** (#708,
  ADR-0027 amendment): the frozen side pays nothing ever, while the real
  TTWROR is net of the fees and taxes actually booked. The response therefore
  also carries `real_ttwror_before_costs` (the same walk with the window's
  **trade** fees and taxes reclassified as external flows — standalone
  fee/tax bookings and dividend withholding deliberately stay inside the
  return, because the frozen holder would have paid those too),
  `transaction_costs` (their total in the base currency) and `cost_recovery`
  with `state` one of `recovered`, `partly_recovered` (ahead before costs,
  not yet after; `outstanding` states the gap), `not_recovered` (behind even
  before costs, so the costs are not the reason) or `not_comparable` (the
  frozen side has no value at the as-of date — an all-cash snapshot, for
  example — so there is nothing to be ahead of; the costs still report).
  Read the three together: `real_ttwror_before_costs` alone flatters.
- `GET /api/v1/portfolios/:portfolio_id/category-results?classification_id=<id>` —
  per-category **result** (ADR-0041 slice one, #712): `invested` (the sum of the
  members' `base_cost`, without the buys' fees and taxes, so the result is
  before them; `basis_note` says so since issue #1212), `current_value`,
  `result_abs` and `result_pct` per category, plus the member `positions`
  that produced it and the `excluded` rows it could not cover.

  **Read the basis before the numbers.** The payload states it in one line
  (`basis: "current_composition"`, with a `basis_note` spelling it out): this is
  a figure about the positions filed under each category **today**, so there is
  no period, no membership variant and no as-of — and it is not a time-weighted
  return series.

  `result_pct` is `Σ result ÷ Σ invested`, **never** a mean of the members'
  percentages: averaging lets a tiny position at +300 % dominate a category that
  is flat in money. A member whose result is not derivable — no usable price, or
  no base-currency decomposition (ADR-0033) — is excluded from **both** sides of
  the sum and listed under `excluded` with its `reason`; it is never counted as
  zero, which would quietly understate the category. `covered_count` and
  `member_count` state how much of the category the figure covers. A category
  with nothing invested reports `result_pct: null` rather than `"0"`, because
  having nothing to measure is a different claim from being flat. MCP:
  `portfolixir.portfolios.category_results`.

  **A member is priced as the valuation prices it** (ADR-0010, #1368): its
  latest quote, without one its last own trade price, so a category's
  `current_value`, `invested` and `result_abs` add up to what
  `GET /api/v1/portfolios/:portfolio_id/valuation` and the holdings read give
  for the same positions. Each `positions` row names it in `price_source`
  (`"quote"` or `"trade"`) and `price_date`, and `basis_note` states the rule.
  Only a member with neither a quote nor an own trade price is excluded as
  `no_usable_price`.

  **The view scope (#901)** comes in the performance family's two forms
  (ADR-0051 §6). `?view=<id>` narrows the portfolio read to the portfolio's
  positions matching that view and echoes it as `view: {id, name}`; a
  malformed view is a `422`, an unknown one a `404`. The view read below spans
  every portfolio, and `GET /api/v1/category-results` every portfolio with no
  view (#1091). Every answer states the scope it was computed over:
  `scope` (`portfolio`, `view` or `all`), `portfolio_id`, `view_id`,
  `base_currency` (the currency of every money figure: the portfolio's on the
  portfolio read, `EUR` on the view read and on the every-portfolio read,
  `scope: "all"`), and a closing sentence of `basis_note` that names it. The MCP tool takes the same scope:
  `portfolio_id`, which `view` narrows, `view` alone for the view across every
  portfolio, or neither for every portfolio.

  **Every form names what it leaves out once** (#1091): `excluded_members`
  lists each excluded member a single time across the tree, however many
  levels it rolls into, sorted by name without regard to case (ties by
  `security_id`), with `security_id`, `security_name`, `category_id` (the
  category it is filed under), `reason` and `native_costs` — `[{amount,
  currency}]`, the cost in the currency it was paid in, amounts as Decimal
  strings, when only that currency keeps it out of a EUR sum, and `[]`
  otherwise. A security held in a EUR and a non-EUR portfolio is left out
  whole and carries one entry per currency, the result's currency first,
  then the others by code. Every `basis_note` names the list; the
  per-category `excluded` rows are unchanged.

- `GET /api/v1/portfolios/:portfolio_id/allocation` returns the target/actual
  breakdown for one classification (required `classification_id` query param; a
  missing one returns `422 Unprocessable Entity`). For each category it reports
  `parent_id` and `depth` (the categories form a tree), `color`,
  `own_market_value` (positions assigned directly to it), `market_value` (its
  whole subtree rolled up), `actual_weight` (the rolled-up share of
  `total_value`), `target_weight`, `drift_weight`
  (`actual_weight - target_weight`: positive = overweight, negative =
  underweight; ADR-0023), and `drift_value` (the drift restated in
  the base currency — how much to sell (positive) or buy (negative) to reach
  the target). Each row also carries `child_target_sum` (Decimal string):
  the advisory sum of its **direct** children's targets, or `null` when no direct
  child carries a target — a target-consistency hint the UI can flag against the
  row's own `target_weight`. A position assigned to a child counts toward that child
  **and every ancestor**, so a parent category with a target is compared
  against its subtree rather than showing 0%; the rows come back in tree order
  (parent before its children). Because parents aggregate their children, the
  per-category `actual_weight` values intentionally do not sum to 1 across
  levels — only the leaves plus `unassigned` do. Each category (and
  `unassigned`) also carries `positions`: the per-security breakdown of its
  **own** (directly assigned) value — `security_id`, `security_name`,
  `quantity`, `market_value`, `weight`, plus the display-only rebalancing
  hints (ADR-0023): `drift_value` (the position's proportional share of the
  category drift) and `rebalance_quantity` (indicative units to sell
  (positive) or buy (negative) at the valuation's implied base-currency unit
  price; no fee/tax modelling, never an order). Both hints are `null` without
  a plan, for `unassigned` positions without their own position SOLL, and for a
  position valued at `0` without its own SOLL, which holds no share of its
  category's drift (E25 S4); the page shows "—" and sorts such a row after the
  rows that drift. With the position rows, the payload's `computation_basis`
  states the drift share's basis (`drift_value`) and lists these gaps.
  Entries come largest first,
  securities merged across depots;
  this is what the sunburst's outermost ring renders. **Position-level SOLL
  (ADR-0030 slice 2a):** a category's `positions` are the union of its held
  positions and the active plan's position-target rows, matched by security.
  Each entry additionally carries `target_weight` (its position SOLL, `null`
  when none), `drift_weight` (`actual weight − target weight`, ADR-0023 sign)
  and `held`. An entry with its own SOLL derives `drift_value` and
  `rebalance_quantity` from that own drift instead of the category share. A
  position with SOLL > 0 that is not yet held appears with IST 0 (`held:
  false`, quantity/value/weight `"0"`) and full underweight drift — "this
  needs buying" — with its indicative quantity priced at the **latest stored
  quote** (`null` when no price exists; none is invented); `quote_date` names
  that quote's date (`null` when the hint is not quote-based). `held` means
  holdings presence: a held security whose price cannot be determined is never
  reported as unheld (it stays on the unvalued surfaces instead). Each entry
  also carries `stale` (`true` when its attached position-target row no longer
  matches the security's current category). A position is
  hidden only when its SOLL is 0/absent **and** its holdings are zero. Each
  category row also carries `conflict` (its explicit weight and position sum
  disagree — the sum steers) and `has_stale` (a position row filed under it is
  stale), and the breakdown carries `deep_target_sum` — the effective targets'
  sum at the topmost targeted level per subtree, which explains a `0`
  `top_level_target_sum` over a plan steered deeper in the tree.
  Securities held but not
  assigned in the tree are summed into `unassigned`; unassigned entries attach
  their position SOLL too. Weights are shares of the
  **steering basis**: the valued positions' total (scoped by the active `view`
  when one is passed), **plus the deployable cash** (`free_cash`
  accounts with a non-negative balance). `total_value`
  here is that steering basis (not the full valuation). The response carries a
  `cash` object — `market_value` (the counting cash), `actual_weight` (its share
  of `total_value`), `target_weight` (the active view's plan cash target, or `0`
  when unset; see the cash-target endpoints below), `drift_weight`
  (`actual_weight - target_weight`, ADR-0023),
  `drift_value` (restated in the base currency), and `distributed` (boolean) —
  so cash is steered in the same drift logic as the categories. When the active
  classification is the built-in **currency** tree, each cash account's
  deployable balance is attributed to its own currency-code category instead of
  appearing as a separate cash row: EUR cash flows into the EUR category, USD
  cash into USD, and so on. In that case `cash.distributed` is `true` and
  consumers should omit the separate cash row; for all other classifications
  `distributed` is `false` and the cash row behaves as before. Because cash is
  part of the 100% basis, the category percentages shrink accordingly once cash
  is present. The `top_level_target_sum` is the sum of the root categories'
  targets **plus the cash target** (except for the currency classification where
  cash is distributed into categories), compared against `1`. A plan may
  deliberately allocate **less** than 100%: `unallocated_remainder` states that
  gap (`1 − top_level_target_sum`, `"0"` when the plan is full) and
  `drift_basis` names what the drift figures were measured against —
  `"allocated_portion"` when each target was renormalised to the allocated share
  first, so the unsteered remainder is not reported as phantom overweight, and
  `"full_plan"` when the plan sums to 100% and drift is the plain
  `actual − target`. The remainder is computed on read, never stored (ADR-0040). To keep a holding
  out of the steering basis while it still counts toward total wealth, tag it
  with a bucket and exclude that bucket from the `view` the allocation is read
  under — it then falls outside the scoped positions. Since ADR-0020 the **target**
  side reflects the **active view's plan**: passing `view=<id>` reports that
  view's target weights, cash target and `top_level_target_sum` (omitting it uses
  the Gesamt plan), so the drift table steers against one coherent 100% plan per
  view. Category `target_weight` values are the **effective** targets
  (ADR-0030): the sum of a category's position rows when any exist (positions
  are the source of truth), else its explicit category weight — the Σ figures
  consume the same effective values. For the raw position-target rows and
  per-category roll-up (the maintenance view) use the `position_targets`
  endpoint above. Unknown portfolios or
  classifications return `404 Not Found`. Read ergonomics (FR-37):
  `include_positions=false` omits the per-category (and `unassigned`)
  position rows for a roll-up-only read, and `min_drift=<decimal>` (an
  absolute drift-weight threshold, e.g. `0.02`) returns only the category
  rows whose `|drift_weight|` meets it — targetless categories carry no
  drift and are filtered out with it, and kept rows come back flat (an
  ancestor under the threshold is absent). The response states its own
  basis: `positions_included`, the applied `min_drift` and
  `categories_total` (the pre-filter category count). Invalid values are a
  `422`, and so is a value that is not a finite decimal (`NaN`, `Infinity`),
  here and on `position_targets`. The allocation page carries the same filter as its
  drift-threshold chips (one shared predicate, so the two surfaces cannot
  select different categories); the chips speak percentage points, so
  `≥ 5 pp` on screen is `min_drift=0.05` here. `tax_context=true` (#667) additionally attaches the current-year
  tax-free trim budgets — one entry per holder identity with recorded
  statements (case spellings of one taxpayer are one entry),
  each with its activity-aware `staleness` — so the tax headroom is
  readable where the trim decision is made; the block states that it rolls
  up per `(holder, tax_year)` across institutions and is never scoped to
  the portfolio or view.
- `GET /api/v1/portfolios/:portfolio_id/risk` returns a **risk/concentration
  lens** for one portfolio over the **steerable basis** (the valued positions,
  scoped by the active `view`, the same
  basis the allocation drift uses). A security held across several depots is
  merged into one single-name exposure. Weights, caps and the HHI are all on a
  **0-100 percentage scale** (Decimal strings, full precision, no rounding):
  - `steerable_basis` is the basis the weights are a share of, and
    `base_currency` the portfolio's base currency.
  - `top_holdings` is the largest single-name exposures, largest first, default
    **N = 10** (override with the `top_n` query param). `top_n` keeps the
    list reads' capped-and-echoed contract: at most `1000`, a larger value is
    capped, and the answer echoes the applied `top_n` (E25 S4). Each entry carries
    `security_id`, `security_name`, `asset_class`, `market_value`, `weight` and a
    `severity` (`ok`/`warn`/`hard`). The severity is **instrument-type aware**: a
    single stock warns above `7` and goes hard above `10`; an **ETF** (the `etf`
    asset class) warns above `25` and never goes hard. Override the defaults with
    the `stock_thresholds[warn]`/`stock_thresholds[hard]` and
    `etf_thresholds[warn]` query params.
  - `hhi` carries the Herfindahl-Hirschman Index of the single-name weights
    (`value` = the sum of the squared percentage weights, on the `0-10000`
    scale) plus a `band`: `low` (`< 1500`), `moderate` (`[1500, 2500]`) or
    `concentrated` (`> 2500`). Override the cutoffs with the `hhi_bands[low]` and
    `hhi_bands[high]` query params.
  - `asset_class_violations` are **opt-in** asset-class cap violations: there are
    no shipped defaults, so caps are configured per call with the
    `asset_class_caps[<asset_class>]` query param (a percentage, e.g.
    `asset_class_caps[equity]=50`). Only classes whose current percentage weight
    exceeds the cap come back, each with `asset_class`, `current_weight`, `cap`
    and `overage` (current − cap, in percentage points).

  The lens is a pure read-time derivation of the live valuation and the
  securities' asset classification — nothing is stored, so it is deterministic on
  read. A malformed override (e.g. a non-positive `top_n`) returns `422
  Unprocessable Entity`; unknown portfolios return `404 Not Found`.

  **The portfolio's derived metrics ride the same read** (ADR-0047, FR-40,
  scope-ladder level (a)) under `metrics`, additively. The risk family has
  **exactly one endpoint**: there is no `/views/:id/risk`, and the view
  arrives as the `view` parameter the lens already honours.
  - `volatility`, `max_drawdown` (with `peak_date`, `trough_date`,
    `recovery_date`; `recovery_date` is `null` while the index is still
    below the peak, and all three are `null` when the drawdown is exactly
    `0`: there was no decline, so none is dated) and `risk_adjusted_return`,
    each over `30d`, `90d` and `365d`. They read the **flow-adjusted daily return factors of the TTWROR
    chain** — never the day-over-day change of the portfolio's value — so a
    deposit or a withdrawal is not a return: a portfolio whose prices never
    move has volatility and drawdown exactly `0` however much money moves in
    and out. A walked day whose return base is zero or negative produces no
    observation rather than a zero return. Volatility is the population
    standard deviation of the daily returns, annualized by `√365` (the walk is
    a calendar walk); the drawdown runs over the chained return index.
  - `risk_adjusted_return` is the mean daily excess return over the
    risk-free leg, times 365, divided by the annualized volatility. The
    **`risk_free_rate`** query parameter is a Decimal fraction (`0.02` is 2 %
    p.a.), compounded daily as ADR-0046's fixed-rate benchmark is, bounded like
    it, and **defaults to `0`** — at the default the figure is return per unit
    of risk, and `computation_basis.reference` says so. No rate is inferred,
    fetched or stored; each window echoes the rate it used. A malformed or
    out-of-bound rate is a `422`. Over a volatility of exactly `0` the ratio is
    `null` without `insufficient_data`: undefined, not short of data.
  - A figure whose square root lies beyond what the one float step can
    carry — a magnitude only implausible stored prices or exchange rates
    reach — is `null` without `insufficient_data` as well: that volatility
    and the risk-adjusted return beside it, or that correlation pair. The
    read never fails on such data, and never answers a number over it; the
    Risk page shows such a pair as "not computable" with its observations.
  - `correlations` is the Pearson matrix of the daily returns of **at most
    the 20 leading** Top-N single names (`leading_names` states how many it
    ran over; the pair count grows with the square of the names, so the
    matrix is bounded while the list is not, and `computation_basis` says so),
    with `security_ids` in Top-N order and `pairs` with `security_id_a`,
    `security_id_b`, `value`, over a `365d` window. The closes are
    **converted to the base currency first** — the opposite of the
    per-security metrics, because two holdings sharing an FX leg do move
    together in the operator's money — and a pair reads only the days on
    which **both** securities have a stored close. A security whose currency
    has no stored rate path is absent from the matrix and listed in `excluded`
    with `reason: "no_rate_path"`, never silently unconverted.
  - Every metric carries `window`, `observations`, `required` and
    `insufficient_data`; below its minimum — 20 observations for volatility
    and the risk-adjusted return, 2 index points for the drawdown, 60
    overlapping returns per correlation pair — `value` is `null` at `200`.
    `metrics.computation_basis` carries `input_series`, `window`, `reference`,
    `gaps` and `assumptions` once; figures are ratios rounded at scale 6.
  - **The read reports; it does not evaluate.** No key in `metrics` is a
    signal, recommendation, rating, score or action, and a meta-test walks
    the rendered key set of both metric payloads to keep it so.
- `GET /api/v1/portfolios/:portfolio_id/cash_target` reads a plan's cash target,
  the target cash share of the allocation's 100% basis (securities + counting
  cash). The response is `{"cash_target_weight": "0.05"}` (a string fraction in
  `[0, 1]`, or `null` when none is steered). Optional `view` selects the plan
  (omitted = the Gesamt plan). Unknown portfolios return `404 Not Found`, a
  malformed `view` returns `422`, and an unknown view id returns `404`.
- `PUT /api/v1/portfolios/:portfolio_id/cash_target` sets (or clears with
  `null`) a plan's cash target. The body is `{"cash_target_weight": "0.05"}` and
  may carry an optional `"view": id` (omitted = Gesamt). It echoes the stored
  value back. Out-of-range weights, and weights with more than 6 decimal places,
  return `422 Unprocessable Entity` on `cash_target_weight`, beside
  `errors.row` `"cash"`, the row the plan editor names (issue #1143). The cash target feeds the allocation's `cash` row and the `top_level_target_sum` for the
  addressed view.
- `PATCH /api/v1/portfolios/:portfolio_id` patches a portfolio's master data.
  **Deprecated (ADR-0024)** — answers with `Deprecation: true`; compatibility
  only, use buckets/views for grouping. The body is `{"portfolio": {...}}`. **Cash target move (ADR-0020):** the cash
  target moved off the portfolio object onto the per-view target plan, served by
  the two `cash_target` endpoints above. For **back-compatibility** the portfolio
  object still exposes `cash_target_weight` — a string fraction in `[0, 1]` (e.g.
  `"0.05"` for 5%), or `null` to stop steering a cash quote — and patching it
  reads/writes the **Gesamt** plan's cash target (`view` omitted). So a client
  that only knows the old field keeps working unchanged; use `PUT
  /cash_target?view=<id>` to steer a per-view cash target. Out-of-range weights
  return `422 Unprocessable Entity`; unknown portfolios return `404 Not Found`.
  The cash target is written **only when the body carries
  `cash_target_weight`**, in the same transaction as the rest of the patch: a
  patch without it (a rename, say) leaves the stored cash target and its
  journal untouched, and a refused cash-target write answers `422` with
  nothing written, the rest of the patch included. The response carries the
  cash target as stored after the write.
  The `cash_target_weight` is also included in the portfolio objects returned by
  `GET`/`POST /api/v1/portfolios` (the Gesamt cash target).
- `GET /api/v1/securities/:security_id/trades` returns FIFO-matched trades for
  one security: open lots, closed round-trips (with realised P&L and holding
  period in days) and any orphan sells. Each open lot carries `buy_price` (as
  recorded, transaction currency) plus `buy_price_native` — the
  security-currency basis its `unrealized_pnl_*` is computed against
  (ADR-0033) — and the same base-currency decomposition fields as the
  holdings rows (`base_cost`, `price_return_*`, `currency_return_*`,
  `total_return_base_*`, `decomposed`/`undecomposed_reason`, against the EUR
  hub, since FIFO lots are matched per security across portfolios). A lot
  with no derivable native leg reports `null` P&L instead of a blind
  cross-currency figure. Since issue #1369 an open lot is priced by the
  holdings read's rule (ADR-0010): its `latest_price` is the latest quote
  close, else the last own trade price across all portfolios, in the
  security's own currency, and the lot names it in `price_source` (`quote`
  | `trade`) and `price_date`, `null` with no price;
  `computation_basis.latest_price` states the rule. A security without a
  quote, bought 15 at 18.00 and 5 at 19.20, reads `latest_price` 19.20 with
  `price_source` `trade` on both lots and `unrealized_pnl_abs` 18.00 and
  0.00, the figure its holding reads. The response is self-describing (FR-13):
  it carries `method: "fifo"`, so a client never has to assume how lots were
  paired against sells. Since a sale consumes the oldest lot whatever
  portfolio bought it, a split scales every open lot of the security once on
  its date, so the lots follow the shares held. Optional `from`/`to` (ISO dates) filter each leg by its
  own date: open lots by open date, closed round-trips by close date, orphan
  sells by sell date.
  There is no `limit`: `from`/`to` are the bound (the FIFO matcher needs the
  whole history, and each leg is filtered by its own date afterwards), stated
  in the payload's `basis`.
  Since issue #984 every closed round-trip carries `annualized_return` and
  `annualized_return_reason`, the same figure and rule as the realized-gains
  read above, and the payload carries `computation_basis.annualized_return`.
  Since issue #1108 an open lot's `buy_fees` and `buy_taxes` and a closed
  round-trip's `buy_fees`, `buy_taxes`, `sell_fees` and `sell_taxes` are in
  its `currency_code`, like its `basis` and `proceeds`: a cross-currency
  trade booked in the security's currency converts them from the cash
  account's currency at its own stored `settlement_fx_rate`, as the
  realized-gains read above describes, and
  `computation_basis.fees_and_taxes` states the rule.
  Since issue #1142 a closed round-trip whose `basis` is `"0"` reads
  `realized_pnl_pct` `null` with `annualized_return_reason` `no_cost_basis`,
  as on the realized-gains read, and an open lot whose cost (`quantity` ×
  `buy_price_native`) is `"0"` keeps its `unrealized_pnl_abs` and reads
  `unrealized_pnl_pct` `null`, never `"0"`;
  `computation_basis.realized_pnl_pct` and
  `computation_basis.unrealized_pnl_pct` state the rules. As on the holdings
  read, an open lot whose `base_cost` is `"0"` reads the decomposition's
  three percentages `null` too, and `computation_basis.decomposition_pct`
  states the rule.
  Since issue #1212 `computation_basis.fees_and_taxes_in_figures` says which
  figures carry the fees and taxes: an open lot's `buy_price`,
  `buy_price_native`, `base_cost` and `unrealized_pnl_*` are without them;
  its `buy_fees` and `buy_taxes` are the whole buy's, for
  `original_quantity`, the quantity the lot opened with (split-adjusted),
  and the share already in a closed round-trip's `basis` is in that
  round-trip's `buy_fees` and `buy_taxes`. A closed round-trip's `basis`
  includes the buy fees and taxes of the lots it closes, prorated, its
  `proceeds` are net of the sell's, and `realized_pnl_abs` is after all
  four. No figure changed.

## Policy rules (ADR-0049)

A **policy rule** is a stored standard over a figure the product already
serves: "no single name above 10 %", "cash never below 5 %", "the bond
category within ±3 percentage points of its target", "the portfolio's 90-day
volatility under 15 %". It is stored as an object instead of living as prose
in a scheduled prompt, which is where such limits used to drift. The operator
writes rules on the Risk page and an agent writes them over the API with its
token, so a rule is a stored rule whoever wrote it: the audit journal
(`resource_type` `policy_rule` and `policy_rule_version`) says who wrote each
rule and each version, and the list's `rules_note` points there. Every
version also carries **`author`** (E25): `operator` for a version saved on
the Risk page, `agent` for one written with an API or MCP token, derived from
the write's credential and never read from the body; a finding carries the
`author` of the version in force. A version stored before authors existed
takes the author its journaled creation names, `null` only without one.
`author` covers the version, not the name: a rename is no version, so the
rule carries its own **`name_author`** (security review H14), who last named
it, set the same way by the create and by every rename, and a finding
carries it as `rule_name_author`. A rule stored before name authors existed
takes the author of its last journaled rename, or of the version written
with its name, `null` only without either. Risk marks the agent's rules
with the word "Agent", after the name where the agent named the rule; when
a rule is in force does not depend on its author.

**What a rule is.** A predicate over **one named measure**, for one subject,
in one evaluation context:

- the **context** is the portfolio plus an optional `view_id` (`null` is the
  portfolio-wide context, the convention target plans use); the measure is
  read on that context's steerable basis;
- the **subject** is `basis`, `security` (`security_id`), `category`
  (`classification_id` + `category_id`), `view` (`subject_view_id`) or `cash`;
- the **measure** is one of these, and each is read off a payload the product
  already serves — the rules compute no figure of their own:

  | `measure` | Subjects | Scale of the thresholds |
  |---|---|---|
  | `weight` | security, category, cash, view | percent, `0`–`100` |
  | `drift` | category, security | percentage points, `−100`–`100` (actual − target of the active plan) |
  | `hhi` | basis | `0`–`10000` |
  | `volatility` | basis, with a `window` (`30d`, `90d`, `365d`) | percent, annualized, `≥ 0` |
  | `max_drawdown` | basis, with a `window` | percent in its own sign, `−100`–`0` |

  A `security` subject read for `drift` also names the `classification_id`
  whose plan carries its position target. A `view` subject is how a **bucket**
  is capped: "the speculative bucket stays under 5 % of everything" is a
  `weight` cap on the view that selects that bucket, evaluated in the
  portfolio-wide context.
- the **kind** is `cap` (breached strictly above `threshold`), `floor`
  (strictly below) or `band` (outside `[lower, upper]`) — the risk lens's own
  reading of a line, so a rule and the lens never disagree about where one is;
- the **severity** is `warn` or `hard`; `name` and `note` are the rule's
  words, whoever wrote them, and are never parsed. The `name` is a **label on the rule**, not part
  of its identity: it can be changed at any time without a new version (see
  the rename below), and it need not be unique.

Thresholds are Decimal strings (ADR-0016). A predicate that does not fit its
measure — a subject outside the matrix, a missing or superfluous `window`, a
band with `lower > upper`, a threshold off the scale — is a `422` naming the
field under `version`.

**Versioned and effective-dated.** A rule has a stable identity and one or
more **versions**, each the standard of its own period `[valid_from,
valid_until]`. An **edit adds a version** from `valid_from` (today by default,
never earlier) and closes the previous one the day before; both stay readable,
so "what was the standard on date D" is a read (`as_of=`), not an
investigation of the audit journal. A version that has been in force is
**never changed and never deleted** — the database refuses it, and refuses two
overlapping versions of one rule. A version only scheduled for a later date is
replaced by adding a version from the same date. The database also refuses,
on any version, a change to its rule, its predicate or its start date; on any
rule, a change to its portfolio or view; and a `TRUNCATE` of either table. A
version's end date and a rule's name stay writable, through the retirement,
the edit and the rename. Every write is journaled.

The reads:

- `GET /api/v1/portfolios/:portfolio_id/policy_rules` — the portfolio's rules,
  each with `status` (`in_force`, `scheduled` or `retired`, relative to
  `as_of`), `version_in_force` and `next_version`. `as_of` (ISO date, default
  today) reads the standard in force on a date; `include_retired=true` adds the
  retired rules; `view` narrows to one evaluation context (absent: every
  context); `since` is the row delta (a rule counts as changed when its row or
  any of its versions did); `limit` (default 1000, max 10000).
- `GET /api/v1/policy_rules/:id` — one rule with its **whole version
  history**, oldest first.

The writes:

- `POST /api/v1/portfolios/:portfolio_id/policy_rules` — body
  `{"rule": {"name", "view_id", "version": {…}}}`; creates the rule with its
  first version (`201`).
- `POST /api/v1/policy_rules/:id/versions` — body `{"version": {…}}`; the edit
  (`201`). On both, a version's `note` holds at most 10000 characters
  (Unicode code points); a longer one answers `422` on `note`.
- `PATCH /api/v1/policy_rules/:id` — body `{"name": "…"}`; the **rename**, a
  rule-level edit **outside the versioning**: no version is added or changed,
  and the new name reads for the rule with all its versions (`200`, the rule
  with its versions). The journal keeps the previous name and who changed it.
  Allowed on a retired rule. Only `name` is read, as on
  `PATCH /api/v1/plans/:id`: a blank, missing or non-text name is a `422` on
  `name`; a predicate field, a `version`, the version keys of the rule's own
  read shape (`version_in_force`, `next_version`, `versions`) or the context
  (`view_id`, `portfolio_id`) in the same body is a `422` naming each such
  field, and nothing is written — a new line is a new version, and a rule in
  another context is a new rule. Any other key is ignored. A rule deleted
  since it was read is a `404`.
- `POST /api/v1/policy_rules/:id/retire` — optional `valid_until`; ends the
  version in force yesterday by default (tonight when it only started today)
  and drops any version scheduled after it. The rule stays readable with
  `include_retired=true`. A rule none of whose versions has been in force, or
  one already retired, is a `409`.
- `DELETE /api/v1/policy_rules/:id` — only while **no** version has ever been
  in force (`204`); otherwise `409`, and the remedy is retiring it.

A new version, a retirement and a delete each hold the rule while they read
its versions, so two of them on one rule take turns: a version added while a
retirement runs waits for it and is judged against the retired rule, never
surviving it. A rule deleted since it was read is a `404` on all three.

**What a rule reads is protected.** Deleting a security, a category, a
classification or a view that a rule version (or a rule's context) references
answers **`409`** with `errors.policy_rules` — each rule's `id`, `name` and
`status` — and a `detail` naming each rule by its id and status
(`policy rule(s): #7 (in_force)`), never by its name (#965), and stating the
remedy. A version that has been in force
keeps its subject as the record of what the standard was, so retiring the rule
stops its evaluation but does not free the object; only a rule none of whose
versions was ever in force can be deleted, which does. A security stays
retirable (`is_retired`) as before.

**The findings read.** `GET /api/v1/portfolios/:portfolio_id/policy_findings`
evaluates the rules in force **today** for one evaluation context (`view`;
absent: the portfolio-wide rules) over the figures the product already serves,
and answers one **finding** per rule, sorted breached, undetermined, ok:

- `state` is `breached` (strictly beyond the line), `ok`, or `undetermined` —
  the figure could not be read. **Undetermined is never a pass** and is never
  filtered out by default; it carries its `reason`: `insufficient_data` (a
  refused portfolio metric, with ADR-0047's `required` and `observations`),
  `undefined`, `no_active_plan` or `no_target` (a drift with nothing to drift
  from), `empty_basis` (a weight of nothing is not 0 %), `unvalued` (the
  subject is held but its position cannot be valued, e.g. a quote with no
  stored exchange rate), `subject_not_found` or `not_measured`. A security
  that is simply not held has a weight of `0`, which is a reading.
- each finding carries the rule's identity and words, the version, the
  thresholds, the measured `value` and the signed `distance` to the nearest
  line (value − line, on the measure's scale), and its own
  `computation_basis` naming the read it used; the payload carries `summary`
  (a count per state) and a `computation_basis` stating the input series,
  window, reference and gap treatment.
- `status` narrows to a comma-separated set of states: `status=breached` is
  the **retrievable alarm list**. It is a pull; nothing is pushed anywhere.
  An unknown state is a `422`; `since` deliberately does not apply, because
  findings are a derived projection rather than rows.

The measures are read, never computed: the risk lens's single-name weight and
HHI, the allocation breakdown's category and cash weight and the drift of the
active plan (fractions × 100), the valuation for a view's share, and the
portfolio metrics' volatility and maximum drawdown at the rule's window
(ratios × 100). The read is memoised under the portfolio's data version and
its rules counter, so an edited cap is evaluated on the very next read.

**What this surface is not.** A rule is a standard, never an instruction, and
a finding carries **no action** — no quantity, no trade verb, no suggestion; a
meta-test walks the rendered payload to keep it so. Nothing here places,
proposes or sizes a trade, nothing is pushed anywhere, and no rule is replayed
over a period before its `valid_from` (that would be backtesting, scope-ladder
level (d)).

## Exchange Rates

- `GET /api/v1/exchange_rates` lists stored exchange rates. Rates are kept
  against the EUR hub (`1 base_currency = rate quote_currency`); other pairs are
  derived by triangulation, and `GBX` (pence) is handled as `GBP × 100`.
  `limit` keeps the most recent rates (default 50000, max 200000).
  Every rate a writer stores is bounded like a quote: positive once rounded
  to its 15 decimal places, and dated no later than tomorrow. A sync drops a
  provider rate outside the bound instead of failing the run, and the
  latest-rate reads never use a stored row dated past it. A rate a release
  before 2026.10.1 could store as 0 (a value finer than the column) is no
  rate to any conversion: the figure that needs it excludes and names the
  booking, or reports the rate missing, as for a day with no rate. The row
  is neither deleted nor changed — it stays in this list, a history
  backfill replaces it on a day the provider publishes, and the boot log
  names each such row (security review 2026-10-12, K06).
- `POST /api/v1/exchange_rates/sync` fetches rates from the configured
  provider (ECB by default) and returns `{provider, status, upserted, scope}`.
  `scope=latest` (the default) fetches the **daily** feed — today's rates,
  nothing in the past. `scope=history` (issue #737, Sprint 9 D-1) runs the
  **one-shot backfill** of the historical ECB series (`eurofxref-hist.xml`)
  through the same upsert path: every published day at once, so a dated
  conversion (a realized gain, a cost or a flow the Cash-flow facets excluded
  and named for a missing booking-date rate) can find its rate. The
  rate-availability rule is unchanged — a day the ECB did not publish (a
  weekend, a currency it does not list) stays excluded and named; the
  backfill fills dates, it does not relax the "exact booking-date rate"
  basis. An unknown `scope` is a `422`, a provider without a history answers
  `422` naming `scope`, and a provider failure, or rates the database cannot
  store, returns `502 Bad Gateway` with nothing stored. One backfill runs at a
  time: while one runs, a second answers `409 Conflict`. The
  human view is the **Backfill historical rates** control inside the
  exclusion notes on `/cashflow`. Since issue #1120 (Sprint 20 D-5) the
  instance also runs this backfill **by itself**, once, after its boot sync
  and after an import, when a booking or a cash account in a non-EUR
  currency predates that currency's earliest stored rate, unless background
  fetches are off (`PORTFOLIXIR_BACKGROUND_FETCH=off`). `scope=history`
  remains for a manual run: where the automatic one could not reach the
  provider, on an instance with background fetches off, or for any other
  reason to refetch; while the automatic one runs it answers `409` like any
  second backfill. No parameter is added and no tool changes.
  Since issue #1196 (Sprint 21 α2, ADR-0015's amendment of 2026-10-09,
  point 6) a history run that stored rates also derives, in the same
  single-flight run, the settlement legs of every buy and sell booked in its
  cash account's currency with none of the three legs stored, journaled
  under the system actor `settlement_backfill`, as
  `mix portfolixir.backfill_settlement_legs` does. The answer carries
  `settlement_legs`: `{status, derived, skipped_no_rate, skipped_changed,
  stopped_at_transaction_id}`, where `status` is `completed` (`derived`
  bookings gained their legs, `skipped_no_rate` still lack a rate for their
  date, `skipped_changed` gained a leg, had their cash or another input of
  their legs changed, or were deleted after the run read them, and are left
  as they are until a re-run), `not_run` (no rate was stored, every
  count `0`) or `stopped` (the ledger refused a booking: the rates stay
  stored, the counts are `null`, `stopped_at_transaction_id` names it, and a
  re-run derives the rest; after the automatic run stops it does not retry
  by itself, so the re-run is this call or the mix task).
  `scope=latest` answers `settlement_legs: null`: the daily sync derives no
  legs. A booking that already carries a leg, or is priced in a third
  currency, is never touched.
  Since issue #1311 `settlement_legs` also carries `skipped_zero_amount`
  (`null` on a stop, `0` when the run did not derive): the bookings whose
  trade amount is zero, such as a free allotment bought at a price of 0,
  which no rate converts into a leg, so a re-run never changes them.
  `skipped_no_rate` no longer counts them, and counts only the bookings
  whose date still has no rate; the mix task lists the zero-amount rows
  apart, by id and date.

## Classifications

Classification trees organise securities like folders. Built-in trees
(`asset_class`, `currency`) are derived automatically and their structure is
locked; editing the structure of a built-in tree returns `422 Unprocessable
Entity`. The **asset-class** tree's membership, however, is just a view of each
security's `asset_class` field: in the UI a security is dragged between its
categories (which sets that field), and the same effect is achieved over the API
with `PATCH /api/v1/securities/:id` (`{"security": {"asset_class": "etf"}}`) or
the `securities.update` MCP tool. Set it to empty/`null` for "automatic", which
re-infers the class from the security's name/ISIN/ticker on read. The currency
tree stays intrinsic and cannot be reassigned.

- `GET /api/v1/classifications` lists every classification as a tree with its
  `categories` and `assignments` (`{security_id, category_id}`). Built-in trees
  carry `built_in: true` and a `key`.
- `POST /api/v1/classifications` creates a custom classification from a
  `classification` object (`name`, optional `position`, `description`).
- `PATCH /api/v1/classifications/:id` updates a custom classification's
  `classification` object (`name`, `position`, `description` — all optional).
- `DELETE /api/v1/classifications/:id` deletes a custom classification with its
  categories, its stored assignments and every plan on it with the plan's
  targets. Each of those rows is journaled as its own delete before the
  classification's; no row goes by database cascade alone.
- `POST /api/v1/classifications/:classification_id/categories` adds a `category`
  (`name`, optional `color`, `description`, `parent_id`, `position`) to a custom
  classification.
- `PATCH /api/v1/classifications/:classification_id/categories/:id` patches a
  `category` (`name`, `color`, `description`, `parent_id`, `position` — all
  optional). The category's `classification_id` cannot be changed this way.
  On both writes a `parent_id` must name a category of the same classification
  that is neither the category itself nor one of its descendants; any other
  parent answers `422` on `parent_id` and nothing is written, so a tree never
  loops (E25 S4). A tree has at most 32 levels: a parent under which the
  written category, or the deepest category of the subtree a `PATCH` moves,
  would sit below level 32 answers `422` on `parent_id` as well, naming the
  level ("would put a category on level 33; a classification has at most 32
  levels", issue #940).
  A `position`, on a classification or a category, is an integer from
  -2147483648 to 2147483647 (the column's range); any other answers `422` on
  `position` and nothing is written. The companion's schemas carry the same
  bounds.
- `DELETE /api/v1/classifications/:classification_id/categories/:id` deletes a
  category with the categories below it, the securities assigned there and
  the targets filed under them; each row is journaled as its own delete,
  the lowest categories first and the category itself last.
- `?dry_run=true` on the three cascading deletes (the two `DELETE` routes
  above and `DELETE /api/v1/views/:id`) deletes nothing: the real delete
  runs in a transaction that always rolls back, so the answer is exactly
  what the delete would do, never a count computed beside it (issue #894).
  It answers `200` with, per kind of row the delete reaches, the count and
  the ids (ascending) it would remove, every kind listed, `0` where none
  would go; a category's dry run, for example:

  ```json
  {"data": {"dry_run": true, "would_remove": {"categories": {"count": 2, "ids": [12, 13]}, "assignments": {"count": 1, "ids": [40]}, "targets": {"count": 2, "ids": [21, 22]}}}}
  ```

  A classification answers `classifications`, `categories`, `assignments`,
  `target_plans` and `targets`; a category `categories` (itself and those
  below it), `assignments` and `targets`; a view `views`,
  `view_include_buckets`, `view_exclude_buckets`, `target_plans`, `targets`
  and `depot_snapshots`. A delete the server refuses is refused by its dry
  run with the same status and body: `422` for a built-in classification,
  `409` naming the policy rules that read it, `404` for an unknown id.
  Nothing is written, the audit journal included. The dry run's
  transaction is `REPEATABLE READ`, so its reads before and after the
  delete see one snapshot, and a row a concurrent transaction deleted
  meanwhile is never listed; a dry run that meets such a change answers
  `409` `{"errors": {"code": "concurrent_change", "detail": "..."}}`,
  nothing deleted, and a retry decides. Absent or `false` is the
  delete itself; any other value, an empty `dry_run=` included, answers
  `422` `{"errors": {"dry_run": ["is invalid"]}}`, and any other query
  parameter (`dryRun`, `dry-run`, ...) answers `422` naming it,
  `{"errors": {"dryRun": ["is unknown: this delete takes only dry_run"]}}`;
  either deletes nothing, so a typo never turns the question into the
  delete. The MCP tools refuse a misspelled key before any request.
- `PUT /api/v1/classifications/:classification_id/assignments` assigns a security
  to a category (`security_id`, `category_id`), replacing any existing assignment
  for that security in the classification. The response carries a `status` of
  `created`, `moved`, or `unchanged` plus `previous_category_id`.
- `PUT /api/v1/classifications/:classification_id/assignments/bulk` assigns many
  securities to one category in a single call (`category_id`, `security_ids`),
  returning `{assigned, category_id, security_ids}`.
- `DELETE /api/v1/classifications/:classification_id/assignments/:security_id`
  removes a security's assignment from the classification.

Example transaction payload:

```json
{
  "transaction": {
    "portfolio_id": 1,
    "securities_account_id": 1,
    "security_id": 1,
    "type": "buy",
    "date": "2026-05-15",
    "quantity": "10.00000000",
    "price": "123.45",
    "fees": "1.50",
    "taxes": "0",
    "currency_code": "EUR"
  }
}
```

## Buckets and Views

Buckets are overlapping tags applied to holdings (depots, cash accounts and
individual security positions) for tag-based wealth scoping. Views are named,
global filters over those buckets: a holding matches when it is included
(always under `include_all`, otherwise when it carries one of the view's include
buckets) and carries none of the view's exclude buckets — exclude always wins.
Bucket-definition and assignment writes are journaled (ADR-0017). A view's
definition is journaled too (ADR-0018 §5 as amended in Sprint 16), because a
policy rule in force reads it: `PATCH /api/v1/views/:id`, `PUT
/api/v1/views/:id/buckets` and `DELETE /api/v1/views/:id` each leave one
`resource_type=view` entry, filed under the view, whose `before` and `after`
carry the whole definition — `name`, `include_all`, `include_bucket_ids` and
`exclude_bucket_ids`; resending the stored definition leaves none. Creating
a view is not journaled: no rule can read it yet.

- `GET /api/v1/buckets` lists buckets (`id`, `name`, `color`, `dimension`).
  `dimension` is `"tag"` (a free overlapping tag) or `"scope"` — the exclusive
  dimension: a depot or cash account carries **at most one** scope bucket, so
  scope-scoped totals always add up (ADR-0024).
- `POST /api/v1/buckets` creates a bucket from a `bucket` object (`name`
  required, optional `color`, optional `dimension` defaulting to `"tag"`).
  A blank or duplicate name, or an unknown dimension, returns `422`.
- `GET /api/v1/buckets/:id` returns one bucket; unknown ids return `404`.
- `PATCH /api/v1/buckets/:id` patches a bucket's `name`/`color`. The
  `dimension` is fixed at creation; attempts to change it return `422`.
- `DELETE /api/v1/buckets/:id` deletes a bucket (`204 No Content`). It is
  first removed from every view and assignment that names it, each through
  its journaled writer, so each affected owner gets its own entry: every
  view's sets before and after, every depot default set and cash-account set,
  every position override. **A position override whose only bucket this was
  stays explicit-empty** ("no buckets") and does not inherit its depot's
  buckets, so the position enters no view it was not in. The bucket's own
  `delete` entry carries its row and every membership it had
  (`memberships`: `view_include`, `view_exclude`, `depot_defaults`,
  `cash_accounts`, `position_overrides`). A bucket a policy rule's view reads
  is deleted too; a bucket already gone answers `404`. Removing the bucket
  from a set never re-checks the exclusive scope dimension, so a set stored
  before that rule held never blocks the delete; a set the bucket cannot be
  removed from answers `422`, and nothing is deleted.
- `GET /api/v1/views` lists views. Each view carries `include_all`, the resolved
  `include` set (the literal `"all"` under `include_all`, otherwise a list of
  bucket ids) and the `exclude` list of bucket ids.
- `POST /api/v1/views` creates a view from a `view` object (`name` required,
  optional `include_all` defaulting to `true`).
- `GET /api/v1/views/:id` returns one view with its resolved filter.
- `PATCH /api/v1/views/:id` patches a view's `name`/`include_all`, sent inside
  a `view` object. Either field at the top level of the body, outside it,
  answers `422` naming it (`{"include_all": ["must be sent inside the view
  object"]}`) and changes nothing (issue #1315). So does a top-level
  `include` or `exclude`, the bucket sets, which `PUT
  /api/v1/views/:id/buckets` sets (`{"include": ["is set with PUT
  /api/v1/views/:id/buckets"]}`).
- `DELETE /api/v1/views/:id` deletes a view and its bucket sets (`204`); the
  plans scoped to it, with their targets, and its depot snapshots are
  journaled one delete each before the view's. With `?dry_run=true` it
  deletes nothing and answers `200` with what it would remove, as the
  classification deletes above describe.
- `PUT /api/v1/views/:id/buckets` replaces a view's include/exclude bucket sets.
  Body: `{"include": [..], "exclude": [..], "include_all": false}` (the sets
  optional, default `[]`, arrays of bucket ids). Optional `include_all` is
  saved with both sets in the same journaled write, as the bucket picker
  saves it: `false` narrows a view that includes `"all"` to the include
  list, `true` widens it back; omitted or `null`, the flag is left as it is
  (issue #1315). A malformed id list, or an `include_all` that is not a
  boolean, returns `422` naming the field; a bucket named twice in one list
  counts once.
- `GET /api/v1/views/:view_id/valuation` returns the live valuation of a view
  **across all portfolios** (ADR-0024): the deduplicated union of every depot,
  position and cash account matching the view — an account tagged into several
  included buckets counts exactly once. The shape mirrors the portfolio
  valuation (totals, positions with weights and `price_source`/`valued` flags,
  `cash_balances`, `cash_quote`, `unvalued_cash_count`, `as_of`, a
  `valuation_note`) with `view_id` in place of `portfolio_id`, the count
  covering the cash accounts matching the view; totals are in EUR, converted via the EUR hub, and
  all financial values are Decimal strings. An `overlap` object reports the
  account-level bucket overlap for UI badges (`overlapping`, plus the
  `securities_account_ids`/`cash_account_ids` carrying more than one included
  bucket — the totals are already deduplicated). The active view is echoed as
  `view: {id, name}`. Unknown and malformed view ids return `404`.
  `include_positions=false` (FR-37, issue #740 — the same parameter the
  portfolio valuation has) returns the roll-up only: totals, cash balances
  and cash quote without the per-position rows, and the response states
  `positions_included`. An invalid value is a `422`.
- `GET /api/v1/valuation` returns the **total across every portfolio** with no
  view (#1007): the unscoped union of every depot, position and cash account,
  each counted once, always in EUR, and the first figure a fresh instance can
  answer, since it has no view yet. It equals the dashboard's total when the
  first portfolio's base currency is EUR and no default view is set; the
  dashboard values its card in that currency and follows the default view, so
  otherwise the two can differ. The
  shape is the view valuation's with `view_id: null` and no `view` echo
  (`overlap` reports no overlap, `matches_no_accounts` is `false`), and the
  `valuation_note` names the scope. `include_positions=false` returns the
  roll-up only, as on the view read; an invalid value is a `422`. MCP:
  `portfolixir.views.valuation` without an `id`. The performance, the
  benchmark comparison and the contribution analysis have the same view-less
  form (#1056), listed after their view reads below.
- `GET /api/v1/views/:view_id/performance` returns the view's TTWROR and
  money-weighted IRR **across all portfolios**: exactly the deduplicated
  account scope the view valuation covers, so the total and the return always
  speak about the same accounts. Money crossing the view boundary counts as an
  external flow (ADR-0019); money moving between two in-scope accounts nets
  out. `?period=` (`ytd|1y|3y|5y|max`, default `max`), `?year=YYYY`,
  `?from=`/`?to=` (custom range) and `?series=true` behave like the portfolio
  performance endpoint; the shape mirrors it with `view_id` in place of
  `portfolio_id`, and all financial values are Decimal strings. Unknown and
  malformed view ids return `404`; a bad period `422`.
- `GET /api/v1/views/:view_id/performance/benchmark` returns the view's
  benchmark comparison **across all portfolios** (ADR-0046 §3): the same
  deduplicated account scope the view valuation and the view performance
  cover, so the view's total, its return and its benchmark speak about the
  same accounts. `benchmark=` is required and `period`, `year`, `from`/`to`
  and `series=true` behave like the portfolio benchmark read; the shape
  mirrors it with `view_id` in place of `portfolio_id`. Unknown and
  malformed view ids return `404`; a bad period or benchmark `422`.
- `GET /api/v1/views/:view_id/performance/contribution` returns the view's
  contribution analysis **across all portfolios** (FR-41, ADR-0051 §6): the
  same deduplicated account scope the view performance covers, in EUR, so
  `totals.result` is that read's money result and a position held in several
  portfolios is one row. `period`, `year` and `from`/`to` behave like the
  portfolio contribution read; the shape is its shape with `portfolio_id:
  null`, `view_id` and the view echoed. Unknown and malformed view ids return
  `404`; a bad period `422`.
- `GET /api/v1/performance`, `GET /api/v1/performance/benchmark` and
  `GET /api/v1/performance/contribution` are the three reads above **with no
  view** (#1056): every account of every portfolio, each counted once, the
  scope Wealth calls Everything, readable before any view exists. Each takes
  its view read's parameters (`benchmark=` stays required on the comparison)
  and answers its view read's shape with `view_id: null` (and `portfolio_id:
  null` on the contribution) and no `view` echo; a bad period is a `422`, a
  missing or refused benchmark a `422` on `benchmark`. None takes a scope:
  `view=` and `portfolio_id=` are ignored, as on `GET /api/v1/valuation`.
  **They answer in EUR**,
  the hub, as the view reads and `GET /api/v1/valuation` do. Wealth computes
  its Everything figures in the first portfolio's base currency, so the two
  differ when that is not EUR, and each payload says so:
  `computation_basis.input_series` closes on the scope (every account in
  every portfolio, no view) and the currency. A view with `include_all` and
  nothing excluded reads the same figures. MCP: `portfolixir.views.performance`,
  `portfolixir.views.benchmark` and `portfolixir.views.contribution` without
  an `id`.
- `GET /api/v1/views/:view_id/category-results?classification_id=<id>`
  returns the per-category result (ADR-0041) of the positions matching the
  view **across all portfolios**, each account counted once (#901). The shape
  is the portfolio read's with `scope: "view"`, `portfolio_id: null` and the
  view echoed. Its figures are in EUR: a member's invested amount is the
  settlement leg actually paid (ADR-0033), so a member held in a portfolio
  whose base currency is not EUR has no EUR cost to add and is excluded with
  `missing_base_cost`, never summed across currencies. Unknown and malformed
  view ids return `404`, a missing `classification_id` `422`, an unknown one
  `404`. MCP: `portfolixir.portfolios.category_results` with `view` and no
  `portfolio_id`.
- `GET /api/v1/category-results?classification_id=<id>` returns the
  per-category result of **every portfolio, with no view** (#1091): the
  roll-up the classification page shows, in the portfolio read's shape with
  `scope: "all"`, `portfolio_id: null`, `view_id: null`, `base_currency:
  "EUR"` and no `view` echo. The view read's EUR rule holds: a member held in
  a portfolio whose base currency is not EUR is excluded with
  `missing_base_cost`, and `excluded_members` names it with its cost in the
  currency it was paid in; `basis_note` closes on the scope. It takes no
  scope: `view=` and `portfolio_id=` are ignored, as on `GET
  /api/v1/valuation`. A missing `classification_id` is a `422`, an unknown
  one a `404`. MCP: `portfolixir.portfolios.category_results` with neither
  `portfolio_id` nor `view`.
- `PUT /api/v1/securities_accounts/:id/buckets` replaces a depot's default
  bucket set (the buckets each position inherits unless overridden). Body:
  `{"bucket_ids": [..]}`. At most one of the ids may be a scope-dimension
  bucket; a violating set returns `422` without writing anything.
- `PUT /api/v1/cash_accounts/:id/buckets` replaces a cash account's bucket set.
  Body: `{"bucket_ids": [..]}`. The same at-most-one-scope-bucket rule applies.
- `PUT /api/v1/securities_accounts/:id/positions/:security_id/buckets` sets the
  per-position override for one security in one depot. An empty `bucket_ids`
  records the **explicit-empty** state (deliberately no buckets), distinct from
  inheriting the depot default; the override always wins over the depot default.
  The response reports the resolved `override` (`inherit`, `explicit_empty` or
  `explicit`) and the `effective_bucket_ids`.
- `DELETE /api/v1/securities_accounts/:id/positions/:security_id/buckets` clears
  the override, returning the position to inherit the depot default.

The four assignment writes above hold the depot or cash account while they
replace its set, so two writes to one account take turns: the one that
commits last is the set that stays, never a mix of both. An account deleted
while the write waits answers `404` and writes nothing. The two position
override writes also hold the security, after the depot, and a security
deleted while they wait answers `404` the same way (#919).

The analytics endpoints accept an optional `view` query param (a view id) to
scope the result to the holdings matching that view:

- `GET /api/v1/portfolios/:portfolio_id/valuation?view=<id>`
- `GET /api/v1/portfolios/:portfolio_id/allocation?classification_id=<id>&view=<id>`
- `GET /api/v1/portfolios/:portfolio_id/performance?view=<id>`
- `GET /api/v1/portfolios/:portfolio_id/performance/contribution?view=<id>`
- `GET /api/v1/portfolios/:portfolio_id/risk?view=<id>`
- `GET /api/v1/portfolios/:portfolio_id/category-results?classification_id=<id>&view=<id>`

When a `view` is supplied, the response echoes the active view as
`view: {id, name}` (FR-13); the unscoped/default call is unchanged and carries
no `view` field. A malformed view id returns `422`; an unknown view id returns
`404`. The same `view` scope (and the same `422`/`404` contract) applies to the
target endpoints — `GET`/`PUT
/api/v1/portfolios/:portfolio_id/targets`, `DELETE
/api/v1/portfolios/:portfolio_id/targets/:category_id` and the cash-target
endpoints `GET`/`PUT /api/v1/portfolios/:portfolio_id/cash_target` — where a
view selects the target plan (omitted = the Gesamt plan). The holdings endpoint
(`GET /api/v1/portfolios/:portfolio_id/holdings`) is **not** view-scoped: it
returns the raw per-(depot, security) rows in each security's own currency, so a
client can apply the buckets/views model itself using each row's
`securities_account_id` and `security_id`.

## Settings

A minimal keyed preference store backs the user-facing defaults (ADR-0024).
It carries the **default view** the Wealth page and dashboard open on when no
explicit view was chosen in the UI, and the **crash benchmark** the crash
rule reads (ADR-0058 §1). No financial decimals are involved.

- `GET /api/v1/settings/default_view` returns the current default:
  `{"data": {"view_id": null, "view": null}}` when unset (the built-in
  Everything scope), otherwise the id plus a `view: {id, name}` echo.
- `PUT /api/v1/settings/default_view` sets it. Body: `{"view_id": <id>}` with a
  live view id, or `{"view_id": null}` to clear back to Everything. An unknown
  view id returns `404` (nothing is written); a malformed `view_id` returns
  `422`. The response mirrors the `GET` shape. A change is journaled under
  the token's principal (`resource_type` `setting`, an `upsert`, or a
  `delete` when cleared), so the previous default is in its before-image.
- `PUT /api/v1/settings/crash_benchmark` names the **crash benchmark**
  (ADR-0058 §1), the security whose closes the crash rule reads. Body:
  `{"security_id": <id>}` with any security that has at least one stored
  quote, flagged `is_benchmark` or not, or `{"security_id": null}` to clear
  it; there is no default. The answer is `{"data": {"security_id", "security":
  {id, name, is_benchmark, benchmark_security}}}` (`benchmark_security` is
  `flagged`, `held` or `unheld`), both `null` when cleared. A security without
  a stored quote answers `422` with `errors.security_id` `["has no stored
  quote"]`; an unknown id `["is not a benchmark security"]`, and a merged-away
  one the same with `errors.merged_into` `{kind, id}` naming the survivor; a
  malformed or missing `security_id` and any other field answer `422` naming
  it. Nothing is written on a refusal. The change is journaled under the
  token's principal (`resource_type` `setting`). It applies to the screen and
  every agent alike: switching it changes the detected windows, the names
  given for the former benchmark move to `unmatched_names` and return when it
  is chosen again, and clearing it leaves the manual windows (see Crash
  windows above). The MCP tool is `portfolixir.crashes.benchmark_put`.

## Imports

Portfolio Performance imports (CSV/JSON v1) run through the **Imports view**
only: there is no import endpoint under `/api/v1` and no MCP tool for it, by
design — the preview-then-apply step with its mapping decisions is an
operator action (ADR-0029). What the API and MCP consumer needs to know is
the **re-import preservation guarantee**, because everything an agent writes
through this API lives next to the imported history:

- **Re-applying the same export is a content-hash no-op.** Every transaction
  row that already exists is skipped as a duplicate; no security is created
  twice; the response of the apply reports the skipped count. The hash is
  injective (two different rows never share one) and every hash stored before
  it became so is still found. A tax refund split off a row is hashed with
  that row and checked by its own hashes and economic key, so two equal
  refunds of two different sales both book, a refund already imported is
  found under either formula, and a refund added to a row already imported
  books; a refund whose row is not imported is skipped with it.
- **A rename is safe for the next import (ADR-0050 §3, §4).** The hash is
  checked before anything resolves, and a cash account or depot is created
  only with its first new booking, so a rename over
  `PATCH /api/v1/cash_accounts/:id` or `PATCH /api/v1/securities_accounts/:id`
  (`portfolixir.cash_accounts.update`, `portfolixir.securities_accounts.update`,
  whose descriptions say so) leaves no empty account under the old name. The
  rename keeps the old name in `former_names`, and the import resolves a
  file's account name by the live name first, then by the former names, so a
  re-export that changed inside Portfolio Performance (other decimals, an
  edited booking) books onto the renamed account too and nothing twice. What
  stays outside: an old name another account still carries as its live name
  books to that account, and a rename older than the accounts' audit journal
  left nothing to remember. A prefilled choice the operator changes in the
  preview to an account of another name is remembered as a former name of
  that account by default. Where the name is another account's former
  name, the import page moves it only after its row said so before the
  confirm, and the result names the account it left;
  `DELETE /api/v1/cash_accounts/:id/former_names?name=` (or the
  `securities_accounts` twin) still removes a former name by hand. A
  transfer whose two sides lead to one account is skipped and listed, never
  a failed import.
- **A cash-account merge is safe for the next import (ADR-0050 §2, §7).**
  After `POST /api/v1/cash_accounts/:id/merge`, re-applying an export
  already applied creates nothing, byte-identical or drifted: the moved
  bookings keep their content hashes, every booking the merge deleted has
  its hash retired, the source's name resolves to the target as a former
  name, and a transfer between the two is skipped as internal. A later
  export's new rows that name the merged-away account are booked once, on
  the target. Two limits are stated, not hidden: a new row whose economic
  key equals an existing booking of the target is taken for that booking
  (reported with the layer `economics`), and a row dated on or before a
  balance anchor the merge restated is booked but absorbed by that anchor —
  the import lists it as booked behind a restated anchor, with the anchor.
- **A depot merge is safe for the next import (ADR-0050 §2, §7).** After
  `POST /api/v1/securities_accounts/:id/merge`, re-applying an export already
  applied creates nothing, byte-identical or drifted: the moved bookings keep
  their content hashes, every booking the merge deleted has its hash retired,
  the source depot's name resolves to the target as a former name, and a
  security transfer between the two is skipped as internal. A later export's
  new rows that name the merged-away depot are booked once, on the target. A
  new row whose economic key equals an existing booking of the target is
  taken for that booking (reported with the layer `economics`).
- **A security merge is safe for the next import (ADR-0050 §2, §9).** After
  `POST /api/v1/securities/:id/merge`, re-applying an export already applied
  creates nothing, byte-identical or drifted, whichever ISIN it carries and
  under either identity choice: the moved bookings keep their content hashes,
  every booking the merge deleted has its hash retired, and every identity of
  the source — its ISIN (the target's now, or a former ISIN of the target),
  its former ISINs, the identity its import recorded — resolves to the target.
  A later export's new rows that name the merged-away security by any of them
  are booked once, on the target. The merge is refused rather than leave an
  identity unresolved (`identity_unresolvable`).
- **What survives a re-import, unchanged, same ids, exact `Decimal` values:**
  classification assignments; every target plan version with its category and
  position targets and the cash target; each security's `note` and
  `attributes` including custom keys; the **security research log**
  (`/api/v1/securities/:id/notes` — the append-only entries and the
  `thesis_state` derived from them, ADR-0044); the **security events**
  (`/api/v1/securities/:id/events` — every dated calendar fact with its
  timing qualifier, its confirmation and its `checked_at`, ADR-0048 §7); the
  **policy rules** (`/api/v1/portfolios/:id/policy_rules` — every rule and
  every version with its subject ids, thresholds and period, ADR-0049 §8);
  security ids and `updated_at`.
  Pinned by `test/portfolixir/imports/reimport_preservation_test.exs` since
  issue #664 (research log added by #748, security events by #829, policy
  rules by #864).
- **A mutated re-import** (a rename, a recorded ISIN change resolved through
  an alias or an explicit mapping) keeps the same guarantee for the matched
  securities; only the genuinely new bookings land.
- **Stated where an agent reads it (issue #831).** The descriptions of the
  eight MCP reads the guarantee protects — `portfolixir.notes.list`,
  `.unreviewed`, `.uncorroborated`, `.expiring` and `portfolixir.events.list`,
  `.upcoming`, `.unconfirmed`, `.stale` — carry the sentence "A Portfolio
  Performance re-import does not destroy the research log or the security
  events", so an agent meets the answer in the tool list it already reads
  instead of on this page. The mutated path pins the research log as well as
  the events. The policy-rule reads (`portfolixir.policy_rules.list`, `.get`
  and `portfolixir.portfolios.policy_findings`) carry the rules' own sentence,
  "A Portfolio Performance re-import does not destroy the policy rules", and
  the mutated path pins a rule over the re-ISINed security.
- **Not covered:** a booking that changed in the source. An edited
  transaction hashes differently and is imported as a new row beside the old
  one; the old booking is removed or corrected through
  `PATCH`/`DELETE /api/v1/transactions/:id`. The guarantee is about what
  Portfolixir maintains around the history, not about reconciling two
  versions of the history itself.

A research log, a calendar, a rule, a plan or an assignment therefore never
"disappears at the next import"; an agent that observes otherwise has found a
defect, not a documented limitation.

## Contract Version

The surface says what it is, so a consumer can notice it changed
(ADR-0044 §8). A tool description is read once at connect time; this read is
how an agent learns that the list or the descriptions moved.

- `GET /api/v1/contract` returns the **contract manifest**: `version` (an
  integer, the newest entry's), `last_changed_at` (ISO date),
  `endpoints_total`, `tools_total`, and `entries` newest first — each with
  `version`, `date`, `summary`, the `endpoints` (`"VERB /api/v1/path"`) and
  `tools` the change added, `parameters` (one sentence per parameter added to
  an existing read) and any `removed_endpoints` / `removed_tools`. Optional
  `since=YYYY-MM-DD` narrows the entries to those dated **strictly after**
  that day and answers `changed` — the `?since=` idea applied to the contract
  instead of the rows: store `last_changed_at`, poll with it, and re-read the
  tool list and descriptions when `changed` is `true`. An invalid `since` is
  a `422`.
- The manifest is **code-maintained** (`PortfolixirWeb.Api.V1.Contract`) and
  a meta-test ties the router's `/api/v1` inventory and the MCP companion's
  tool and prompt inventories to it in both directions, so a route, tool or
  MCP prompt added, renamed or removed without a manifest entry fails the
  build; an entry names a prompt in its `summary` and `parameters`. Its first
  entry records the Sprint 9 additions — the research log, the thesis state,
  the `include_positions` / `min_drift` parameters that reached the view
  scope and the position level (#740), the historical backfill scope (#737),
  and this read.

## Instance Version

The instance says which version it was built from (FR-55), so an agent knows
which release it is talking to without asking the operator.

- `GET /api/v1/version` returns `kind`, `value` and `url`: `release` (the
  calendar tag `YYYY.M.N` the build is exactly at; `url` its release notes on
  GitHub), `build` (`branch · short hash · commit date`, the branch left out
  for a detached checkout; `url` the commit on GitHub) or `unknown` (`value`
  `"unknown"`, `url` `null`). Beside them `tag`, `branch`, `commit` (the full
  hash where it is known), `date` (the commit's own date, ISO), `source`
  (`build_arguments`, `git` or `none`) and a `version_note`. The version is
  read **once, when the code compiles**: from the build arguments
  `PORTFOLIXIR_VERSION`, `PORTFOLIXIR_COMMIT` and `PORTFOLIXIR_BUILD_DATE`
  when any is set (the release image's way, [Home
  Deployment](../home-deployment.html), "Upgrade"), else from `git` in the
  source checkout, else `unknown` — never a guess. The `url` is for
  the operator to follow; the app requests nothing.

## Audit Journal

Every financial write (create, update, delete) is recorded in an append-only
audit journal in the same database transaction as the write itself, so any
change — including deletions — stays attributable and reversible by inspection.
Market-data ingestion (quote and exchange-rate sync) is operational data and is
deliberately **not** journaled. A quote someone writes is not ingestion: the
quote upsert and the release of manual quotes are journaled under
`resource_type=security_quotes`, filed under the security's id, with the rows
they replaced or released as the before-image.

- `GET /api/v1/journal` lists journal entries, newest first. Each entry carries
  `actor_type` (`owner_ui`, `api_token_rw`, `api_token_ro`, `import_session`,
  `system_job`) and an optional `actor_label` (for an API token, the name of
  its `PORTFOLIXIR_API_TOKENS` entry; `null` for the unnamed default), the `operation`
  (`create`, `update`, `delete`, `upsert`), the `resource_type`/`resource_id`
  it touched, and the `before`/`after` snapshots (Decimal values are strings).
  Optional filters: `resource_type`, `resource_id`, `actor_type`, `operation`,
  `limit` (default 100, max 1000) and `include_scenarios` (`true` to include
  persisted what-if writes; real writes only by default). The response is
  self-describing: a `meta` object echoes the `as_of` instant, the `order`
  (`inserted_at:desc,id:desc`), the `count` and the `filters` applied.
  The Audit journal page (`/journal`) takes the same parameters and lists
  the same entries, so an agent can hand the operator a link to the rows it
  read: `/journal?actor_type=api_token_rw&operation=delete`.
- `since` (a date, an instant, or the cursor a full page answered as `as_of`)
  makes the read a paged delta, as every capped delta read is (K17, above):
  the entries written strictly after the cut, **oldest first**
  (`meta.order` `inserted_at:asc,id:asc`), with `since`, `has_more`, a
  `delta_note` and a top-level `as_of` that is the next `since` — on a full
  page a cursor at its last entry, `2026-10-28T09:15:02.250000Z~48`, its
  instant to the microsecond, as the journal stamps it. `meta.as_of` stays
  the read's instant, not the cursor. It combines with the five filters,
  `meta.filters.since` echoes it, and `limit` keeps its default and maximum.
  A walk from `since=1970-01-01`, feeding each `as_of` back, reaches every
  entry at least once and skips none, including those past the newest 1000
  that a read without `since` cannot show. A full page that reaches a write
  still in flight answers an `as_of` with no `~<id>`, the in-flight bound:
  poll again later, not at once, and expect the next read to re-deliver
  entries already read, as the response's `delta_note` says. Without `since` the read is unchanged, newest first.
  The page takes the same `since` (`/journal?since=2026-10-28`, or the
  instant or cursor the read answered) and lists the same entries newest
  first.
  SOLL target writes (category and position rows alike) are journaled under
  `resource_type=target`; plan-version writes under `resource_type=target_plan`.
- An update's or a delete's `before` is the row as stored when the write took
  its lock, and an update's `after` is the row as stored after it — decimals
  at their column's scale. Two writes made from one read therefore chain: the
  second's `before` is the first's `after`. A write to a record deleted in
  the meantime answers `404` and leaves no entry.
- A bucket assignment's entry (`depot_bucket_assignment`,
  `cash_account_bucket_assignment`, `position_bucket_override`) images the
  set as stored, its `bucket_ids` in id order: `before` is the set when the
  write locked its account, `after` the set it stored. A position override's
  `before` is `null` where the position inherited its depot's set, and `[]`
  where it had no buckets. Resending the stored set leaves no entry, and so
  does clearing the override of a position that already inherits (#953).
- A delete's `after` is `null`, whatever was deleted: nothing stands after it,
  and the deleted record is its `before`, read under the write's lock. This
  holds for every writer from the release that ships Sprint 24 on (ADR-0017,
  amendment of 2026-11-04; #1378). Entries written before it, by release
  2026.11.8 and earlier, are append-only and keep one of two older shapes: a
  row's delete repeats the deleted record in `after`, and a set's delete
  stores the emptied set — a release of manual quotes (`security_quotes`)
  `{"security_id": …, "quotes": []}`, a cleared position override
  (`position_bucket_override`) the position without its `bucket_ids`,
  `{"id": null, "securities_account_id": …, "security_id": …}`. Read a
  deleted record from `before` in every case.

Every financial write context journals: the rollout ADR-0017 sequenced is
complete. Each table that holds financial records carries a guard trigger that
refuses a write made without an actor, so a write path that forgets the
journal fails instead of leaving a gap. The entries are filed under these
`resource_type` codes:

- securities and their ISIN aliases: `security`, `security_identifier_alias`;
  the quotes someone writes: `security_quotes`;
- portfolios, cash accounts and depots: `portfolio`, `cash_account`,
  `securities_account`;
- bookings, an applied import's included (actor `import_session`):
  `transaction`;
- classifications: `classification`, `category`,
  `security_category_assignment`;
- SOLL plans: `target`, `target_plan`;
- tax records: `tax_parameters`, `tax_profile`, `allowance_order`,
  `tax_statement_snapshot`;
- the research log and security events: `security_note`, `security_event`;
- policy rules: `policy_rule`, `policy_rule_version`;
- the lifecycle merges: `merge_record`, `retired_import_hash`;
- buckets, views and depot snapshot markers: `bucket`, `view`,
  `depot_bucket_assignment`, `cash_account_bucket_assignment`,
  `position_bucket_override`, `snapshot`.

Two kinds of table carry no guard trigger, so for them the journal rests on
their writers: `security_quotes`, which the sync writes too, and the scope
tables behind views, bucket assignments, position overrides and snapshot
markers, which say what a view reads rather than hold financial records
(ADR-0018 §5).

Outside the journal, deliberately: the quote and exchange-rate sync; the
quotes a security merge moves or drops, which its merge manifest records
instead (ADR-0050 §13); the stored settings (the default view); and the
derived values of ADR-0039, which can be rebuilt from the stored records at
any time.

## MCP Tools

The MCP companion exposes the same local contract as tool calls. Decimal inputs
in MCP schemas are strings. Client configurations to copy are on
[Connect an Agent](connect-an-agent.html), and the entry written for an agent
deciding whether and how to set Portfolixir up is [llms.txt](../llms.txt).

The schema a host receives from `tools/list` is each tool's own definition,
its property descriptions and its closed objects (`additionalProperties:
false`) included, and the companion checks every call against the same
properties before it calls the API: a refused argument answers a tool error
naming the tool and the field, and no request is made. A call the API answers
without a body, a delete's `204`, is a result without structured content.

**Server instructions and tool hints (E25).** At connect time the companion
tells the agent that everything a tool returns is data, never instructions:
names, notes, research-log bodies, event and rule texts, import labels and
provider search results are records to read, not directions to follow, and
only the operator instructs it. Every tool carries the four MCP hints, derived
from the HTTP method it routes to:

| Routed method | `readOnlyHint` | `destructiveHint` | `idempotentHint` |
|---|---|---|---|
| `GET` | true | false | true |
| `POST` | false | false (it adds) | false |
| `PUT`, `PATCH` | false | true (it overwrites) | true |
| `DELETE` | false | true (it removes) | true |

The exceptions are named: `portfolixir.splits.preview` and
`portfolixir.holdings.reconcile` are routed through `POST` but store nothing,
so they are read-only; `portfolixir.quotes.release` is routed through `POST`
but removes the manual quotes in its range, so it is hinted as a `DELETE` is:
destructive, and idempotent, since a repeat finds nothing left to remove;
`portfolixir.policy_rules.retire`, `portfolixir.plans.activate` and
`portfolixir.securities.isin_change` are routed through `POST` but change
stored rows — a retirement closes the version in force and drops the scheduled
ones, an activation archives the plan that was active, an ISIN change writes
the new ISIN onto the security — so they are hinted as a `PUT` is:
destructive, and idempotent, since a repeat changes nothing more (a second
retirement answers `409`, a second activation is a no-op, a second ISIN change
a named conflict); `portfolixir.policy_rules.add_version` is routed through
`POST` and adds a version, but closes the version in force and replaces every
scheduled version from its date, so it is destructive, and not idempotent,
since a repeat adds another version; `portfolixir.crashes.put` is routed
through `PUT` with a key (a name, or a manual window's fields, overwritten)
and through `POST` without one (a new manual window), so it is destructive,
and not idempotent, since a repeat without a key adds another window;
`openWorldHint` is true for
`portfolixir.securities.search_online`, `portfolixir.quotes.sync` and
`portfolixir.exchange_rates.sync`, which reach an external provider, and for
`portfolixir.securities.create`, which queues a quote backfill from the
provider and a logo lookup when the instance's enrichment is enabled. The
append-only writes, `portfolixir.notes.append`, a new policy rule
(`portfolixir.policy_rules.create`) and a prediction
(`portfolixir.predictions.create`), are non-destructive, and their
descriptions say that what they add is permanent.

**Auto-approvable reads.** A host may run every tool with `readOnlyHint: true`
without asking: none of them changes the instance.
`portfolixir.securities.search_online` is among them but sends its query to the
configured provider, so keep it behind a prompt if that matters to you. A host
that asks before every other tool, and at the least before each one with
`destructiveHint: true`, keeps every write in view.

**Read-only mode.** Set `PORTFOLIXIR_MCP_READ_ONLY=true` to run the companion
read-only: `tools/list` then lists only the tools with `readOnlyHint: true`,
and a call to any other tool, listed or not, is refused as a tool error naming
the switch before any request is made. It is off by default, and a value other
than `true`, `false`, `1`, `0` or empty stops the companion with the variable
named. The switch narrows the companion, not the token: `PORTFOLIXIR_API_TOKEN`
keeps its full authority over the API.

**Tool profiles.** `PORTFOLIXIR_MCP_PROFILE` takes `read`, `book` or `full` (the
default), in any case. `read` is the read-only mode above. `full` lists and
calls every tool but the news labeller's two. A fourth profile, `label`,
lists `portfolixir.news.unlabeled` and `portfolixir.news.label_put` and
nothing else, and no other profile lists them: it is for a labeller's
script that runs its own companion with its own named token (ADR-0056 §7),
and each side refuses the other's tools at the call. `book` lists the reads,
every create and the replace-shaped
writes, and leaves out the **admin set**, an explicit list in the companion
(`mcp-server/src/profiles.ts`) drawn by one line, as implemented:
removal-shaped tools are admin, and replace-shaped writes stay in `book`. Every
removal is admin (every delete, the former-name and ISIN-alias removals, a
classification's unassignment, a position's override cleared, the release of
manual quotes), even where a later write could put an equal row back, and so
are the three merges, the ISIN change, a rule's new version (it closes the
version in force and replaces the scheduled ones) and a rule's retirement. A
replace-shaped write (an update, an upsert, a bucket set, a plan's activation)
stays in `book`, because the same write sent the former value undoes it; a
bucket set sent narrower, or a position's override set to `[]`, stays too,
while clearing the override is admin. Three kept writes leave a residue their
inverse does not clear: a rename back restores the live name but keeps the
in-between name as a former name, which no new account may take and a later
import naming it books onto that account, until
`portfolixir.cash_accounts.remove_former_name` (or the depot twin), an admin
tool, clears it; an upsert over a date that held provider data leaves that
date manual, which only `portfolixir.quotes.release`, an admin tool, hands
back; and `portfolixir.news.sources_put` rating a domain back from `blocked`
restores its tier and re-rates its stored items, but the items the block
removed come back only when a feed lists them again (ADR-0056 E1: stored
news items are a staging area a fetch refills, so the rating stays a
replace). The writes `book` keeps are a second list beside the admin set, each
with its reason, and a companion test fails any tool with
`destructiveHint: true` that sits in neither. Under `book` a call to an admin
tool, listed or not, is refused as a tool error naming the profile and
`PORTFOLIXIR_MCP_PROFILE=book` before any request is made, and the server
instructions name the profile in one clause. `PORTFOLIXIR_MCP_READ_ONLY=true`
is `read`: alone or beside `PORTFOLIXIR_MCP_PROFILE=read` it agrees, and beside
`PORTFOLIXIR_MCP_PROFILE=book` or `full` it stops the companion naming both
variables; `PORTFOLIXIR_MCP_READ_ONLY=false`, the shipped default, only means
the switch is off and never conflicts. Any other value stops the companion
with the variable named. A profile narrows the companion, not the API token.
It keeps an unattended agent run from deleting or merging through the
companion; an agent that can reach the API with the token can still call every
route.

**Scope twins.** Valuation, performance, the benchmark comparison and the
contribution analysis exist at two scopes, and each tool of a pair names the
other in its description with
the difference (Sprint 17, D-6): `portfolixir.portfolios.*` answers one portfolio
record in its base currency, its `view` narrowing within that portfolio;
`portfolixir.views.*` answers a view across every portfolio, each account
counted once, in EUR. The total across every portfolio needs no view:
`portfolixir.views.valuation` without an id reads it (`GET /api/v1/valuation`,
#1007), always in EUR over every account — the dashboard's total when the first
portfolio's base currency is EUR and no default view is set — so a sum of
portfolio valuations is never the route to it. The view performance, benchmark and
contribution tools need no view either: without an id each reads every
account in EUR (`GET /api/v1/performance`, `/performance/benchmark`,
`/performance/contribution`, #1056), so a return or a contribution of
everything is one read, never a sum of portfolios — returns of several
portfolios never add up. Wealth computes its Everything figures in the first
portfolio's base currency, so they differ from these when that is not EUR, as
each payload's `computation_basis` says.

**Prompts.** The companion offers three MCP prompts (`prompts/list`,
`prompts/get`), the same under every profile, each carrying the no-advice
framing in its own text: the system prepares decisions and the operator
executes them, and nothing places, proposes or sizes a trade.

- `first_setup` checks the instance (`portfolixir.contract.get`) and names the
  active profile, reads what exists, proposes cash accounts, depots, buckets
  and views (none for the total across everything, which needs no view),
  explains how data gets in, and writes nothing without the operator's
  confirmation.
- `import_converter` (optional argument `export_file`) guides the user's
  agent to write and run, on the operator's machine, a converter from a bank
  or broker export to a Portfolio Performance CSV v1 file the operator drops on
  the Imports page, which previews it and applies it idempotently. It states
  the format exactly: the header, `;`, `YYYY-MM-DD` dates, German numbers, the
  German type labels, `Betrag` as each row's cash effect, `Konto` and
  `Gegenkonto` per type, the EUR-only rule, and the JSON v1 variant for other
  currencies and for ISINs, with one synthetic example of each that a test
  takes through the real Imports page. It names the rows the preview refuses:
  a transfer without both sides, a trade without its cash account, an ISIN
  without a valid check digit, and, in JSON
  v1, a currency other than those the security dialog offers. It binds the
  agent: no broker sync, no network call and no model call, synthetic examples
  only, and booking the converted rows one by one through
  `portfolixir.transactions.create` is not a substitute, because it skips the
  preview and the content-hash idempotency.
- `position_review` (optional argument `security_id`; ADR-0055 §5) walks the
  agent through one position: the dossier (`portfolixir.securities.dossier`),
  the open theses and their invalidation conditions (`portfolixir.notes.list`),
  the upcoming events (`portfolixir.events.list`) and the calls already
  recorded (`portfolixir.predictions.list`); then it asks for predictions
  (direction, a probability from `"0.50"` to `"0.99"`, `resolves_on` and a
  benchmark), or none where the agent has no view, each recorded with
  `portfolixir.predictions.create` naming the agent's model and, where one
  exists, the thesis's `note_id`. Its text says a prediction is permanent and
  is a recorded call, never a trade: no order and no size. Where two
  catalogue rows match the security, it asks the operator which to keep
  before recording, since a prediction keeps both its security and its
  benchmark from a merge; it checks with `portfolixir.quotes.list` that the
  security and a benchmark security have a stored close in the last 7 days,
  and uses a `rate:` benchmark otherwise. Under the `read` profile it records
  nothing and hands the operator the list.

The prompts exist over MCP only: a prompt is an instruction to the user's
agent, and the API has nothing to serve it to.

**Invisible characters.** Every write refuses the characters an operator
cannot see (see "Text" above), but a row stored before that rule may still
carry them. The companion is where they are made visible: every string an API
answer carries, a value or a key at any depth, reaches the agent with each
such character spelled `[U+XXXX]` (`[U+200B]` for a zero-width space) — the
same spelling Portfolixir's screens show the operator for that row, and the
server instructions say so. The JSON API itself answers stored text as it is
stored. A text the agent writes back carries the escapes as the visible
letters they are.

**A record named in a sentence (#965).** A sentence the app writes names
another record by its kind and id, never by its stored name, so a name that
reads like an instruction never sits inside the app's own words: an
ISIN-change or alias refusal names `security #12`, and a former-name refusal
of a cash-account or depot write names `cash account #5` or `securities
account #5` (`errors.former_names`: "include the name of cash account #5 in
this portfolio"), and a security merge's guard detail names its rules,
depots, buckets and portfolios by their ids (`policy rule(s): #7 (in_force)`,
`In depot #3`, `in portfolio #1`) and an identity's name and identifiers by
their kind ("its recorded name", "its stored ISIN"), and a split booked again names the existing event's portfolio by its
id (`for portfolio #1`). A delete refused because a policy rule reads the object (`409`) names
the rules the same way, and a cash-account or depot merge's guard detail names
its buckets and a position by their ids (`the buckets #3, #7`,
`security #12 sits in the bucket #9`). The record's name is a field of the
record, read by its id (a depot's from `GET /api/v1/securities_accounts/:id`,
a bucket's from `GET /api/v1/buckets/:id`, a rule's from
`GET /api/v1/policy_rules/:id`, a security's from `GET /api/v1/securities/:id`,
a portfolio's from `GET /api/v1/portfolios`). A refusal's `errors` carry a
name beside the detail in two places only: `errors.policy_rules[].name`, with
each rule's `id` and `status`, and `errors.unresolvable[].ref.name`, the
identity's recorded name; a depot, a portfolio and a bucket travel there by
their ids alone. A security merge's refusal carries an identity's stored
ISIN, WKN and ticker as data beside the sentence too:
`errors.unresolvable[].ref`, `errors.source_isin` and `errors.isins`. Portfolixir's screens keep naming it by its name.

**A write that times out.** Every API call carries a 30-second deadline. A
read that misses it — a `GET`, or one of the tools routed through `POST` that
change nothing (`readOnlyHint: true`) — changes nothing and answers
`ApiReadTimeoutError`, so it can be retried; any other call that misses it
answers `ApiOutcomeUnknownError`: the companion stopped waiting, but the
server may still have committed the write, so re-read what it would have
changed before retrying. A blind retry of a write that adds a record can store
a duplicate, and every such tool (each write that is not idempotent) says so
in its description; the server instructions say it once for every write.

**A write whose connection fails** in a way that does not show the request
never left (a reset, a socket closed while the answer arrives, a TLS failure,
a failure with no code) answers `ApiOutcomeUnknownError` the same way, with
the failure's code in its message: the request may have been sent, and the
server may have committed it. A failure that shows the request never reached
the API (the connection refused, the name not resolved, the host or network
unreachable, the address family unsupported or no local address available,
the connect itself timing out, a base URL that does not parse as a URL) stays
a plain error and is safe to retry, as is any failure of a read. For a name
that resolves to several addresses, the request counts as never sent only
when the connect failed that way on every one of them; otherwise the message
names each address's code.

**A gateway error, or an answer that is not JSON.** Behind a reverse proxy, a
write answered `502`, `504`, or Cloudflare's `520` or `524` answers
`ApiOutcomeUnknownError`: its message says the gateway answered that status
instead of the server, and the server may still have committed the write, so
re-read what it would have changed before retrying. The exception is a `502`
in the API's own JSON error envelope, a body of exactly one key, `errors`,
holding a non-empty object: the API answers `502` that way when the rate
provider fails during `portfolixir.exchange_rates.sync`, with nothing stored,
so that is the server's answer, nothing about the write is unknown, and it
stays the plain error `Portfolixir API request failed: 502 {…}` with the API's
detail. An empty `errors` object, or one beside other keys, is a gateway's. The
API answers none of the other three statuses, so they are a gateway's whatever
their body. A read answered any of the four changes nothing; it stays a plain
error that names the status, or says the answer had no body, and says a retry
is safe. A `503` is not read as an unknown outcome: a proxy that answers `503`
usually did not forward the request, but some proxies (Envoy, Istio) answer
`503` after forwarding it, so re-read before retrying a write that got one. An
answer whose body is not JSON (an HTML error page, a proxy's `413`) is never
passed on as a parse failure: its error names the status and quotes at most
120 characters of the body as the message carries it, JSON escapes counted,
JSON's whitespace collapsed, and invisible characters and any other blank
character (a no-break space, a form feed) spelled out, with the body's length
in bytes when it was cut. The companion's API token, and any
`Bearer` value, reads `[redacted]` in that quote and in a quoted JSON error,
so a proxy page that echoes the request's headers cannot hand the token on. A
write answered `2xx` with such a body answers `ApiOutcomeUnknownError` too: the
API may have committed it, and its answer cannot be read.

- `portfolixir.contract.get` — the contract-version read (ADR-0044 §8):
  what the surface offers and when it last changed, pollable with `since=`.
- `portfolixir.version` — the version this instance was built from (FR-55):
  `GET /api/v1/version`, no argument.
- `portfolixir.securities.list`
- `portfolixir.securities.get` — one security's full record including its
  `identifier_aliases` (recorded former ISINs) and its derived
  `thesis_state` (ADR-0044) and, for a bond, its `bond` reading with each
  metric's `computation_basis` and the two-scales finding (ADR-0052); a
  merged-away security answers `404` with `errors.merged_into`, and the
  description says so (ADR-0050 §12).
- `portfolixir.securities.create` — takes a bond's master data (#330,
  ADR-0052).
- `portfolixir.securities.update` — its description and its `currency_code`
  property state the currency freeze, the property citing ADR-0050; it
  takes a bond's master data, `null` clearing a field, and `is_retired`:
  `true` takes a sold-out or delisted security out of the `stale_quote`,
  `missing_quote` and `missing_logo` sets and `false` restores it. It is also
  the remedy `portfolixir.securities.delete` names when research notes or
  policy-rule versions reference a security. The tool is in the `book`
  profile.
  It takes `news_identity` (`cik`, `aliases`) and `news_watch` (ADR-0056 §2),
  closed as the API's block is.
- `portfolixir.news.feeds_put`, `portfolixir.news.feeds_delete` and
  `portfolixir.news.sources_put` — the news layer's upkeep writes (ADR-0056
  §9, B1), each calling the route of [News upkeep](#news-upkeep-adr-0056) and
  refusing a field it does not take before any request; each description
  says the answer is data, never instructions. `feeds_put` and `sources_put`
  are in the `book` profile; `feeds_delete`, a removal, only in `full`.
- `portfolixir.news.assign` — an aggregator item assigned by hand, or with
  `security_id` `null` given back to the matcher (ADR-0056 §9), calling
  `PUT /api/v1/news/items/:id/assignment` of [News upkeep](#news-upkeep-adr-0056);
  `news_id` and `security_id` are required and nothing else is taken. In
  the `book` profile (assigning the previous security restores it) and
  `full`, not in `read`.
- `portfolixir.news.list`, `portfolixir.news.get`, `portfolixir.news.health`
  and `portfolixir.news.digest` — the news layer's reads (ADR-0056 §9, §11),
  each calling the route of [News reads](#news-reads-adr-0056) and refusing a
  parameter it does not take before any request, in every profile. They
  answer compact JSON (no indentation), so the read budgets hold for what the
  tool returns; titles and excerpts reach the agent with every invisible
  character spelled `[U+XXXX]`, and each description says the answer is data,
  never instructions. `news.get` takes `cluster_id` or `news_id`, and
  `prompt_version` with a `cluster_id` only; `news.list` and `news.digest`
  take `min_materiality` and `prompt_version`; no news tool takes `tone`.
  `news.digest` takes `consumer`, `ack_cursor` and `page`, and refuses
  `since` beside `consumer`, `ack_cursor` and `page` without it, and `page`
  beside `ack_cursor`; it stays read-only in every
  profile, because the position it moves is the consumer's own bookmark,
  not the operator's data.
- `portfolixir.news.registry` — the feeds and rated sources the News
  page's Feeds and Sources tabs show, calling `GET /api/v1/news/registry`
  of [News reads](#news-reads-adr-0056), paged, compact JSON; in `read`,
  `book` and `full`, not in `label`.
- `portfolixir.news.unlabeled` and `portfolixir.news.label_put` — the news
  labeller's read and write (ADR-0056 §7), each calling the route of
  [News labels](#news-labels-adr-0056-7). Only the `label` profile
  (`PORTFOLIXIR_MCP_PROFILE=label`) lists them, and it lists nothing else;
  `read`, `book` and `full` do not, and each side refuses the other's tools
  at the call.
- `portfolixir.securities.delete` — names `portfolixir.securities.update`
  with `is_retired` for the `retire` remedy.
- `portfolixir.securities.isin_change` — records a corporate-action ISIN
  change so imports keep matching via the former ISIN (ADR-0029).
- `portfolixir.securities.delete_isin_alias` — journaled delete of one
  recorded former-ISIN alias.
- `portfolixir.securities.merge_preview` — the security merge preview, a read
  (ADR-0050 §9, §10): the positions per depot for both outcomes of the
  duplicate question, the quotes with the manual collisions, the
  configuration and events, the identifiers after each identity choice, and
  the `plan_digest`.
- `portfolixir.securities.merge` — the security merge under an approved
  digest; hinted destructive and idempotent (a retry answers the original
  record). Its description says that `identity_choice` is required when both
  carry an ISIN and never preselected, what each value does, that the quotes
  fill the target's gaps with the target's winning a collision, that the
  configuration and events move, and what the merge does to the next import:
  every identity of the source resolves to the target, a later import naming
  it books there, a re-import of an applied export creates nothing, and a
  merge that would leave an identity unresolved is refused.
- `portfolixir.securities.search_online`
- `portfolixir.events.list` — one security's calendar (ADR-0048); the
  description states that an event books nothing and is never converted into a
  transaction.
- `portfolixir.events.create` — records a dated fact; the description spells
  out that `timing` says how well the date is known. Its `event` takes
  `news_id`, a news item of the security as the source: the
  companion refuses `source_url` or `source_quality` beside it, and an event
  with neither `news_id` nor `source_quality`, before any request.
- `portfolixir.events.update` — corrects or confirms one in place, because an
  event is mutable by design.
- `portfolixir.events.delete` — removes a duplicate, journaled.
- `portfolixir.events.upcoming` — what is due within N days across the **whole
  catalog**; `held_only` narrows and is never the default.
- `portfolixir.events.unconfirmed` — dates that passed with nobody confirming
  them.
- `portfolixir.events.stale` — dates nobody has re-read in N days.
- `portfolixir.securities.metrics` — one security's derived price metrics
  (ADR-0047) over its own split-adjusted close series: moving averages,
  volatility, maximum drawdown, momentum and the distance to the 52-week
  extremes, each with its window and observation count. Reports only; the
  description says so.
- `portfolixir.securities.dossier` — one security's position dossier (FR-49):
  its record, holdings, metrics, newest research-log entries, upcoming and
  recent events, categories, position targets and its news of the week in
  one read, each part as its own read answers it and naming that read. It
  answers compact JSON (no indentation), so the news block's
  budget of about 50 tokens holds on the text the agent receives.
- `portfolixir.securities.logo_put`, `portfolixir.securities.logo_discover`
  and `portfolixir.securities.logo_delete` — a security's logo set from an
  https image URL, searched again, or removed as "no logo", through the
  [logo endpoints](#logos) (#1413). The first two reach outside the instance
  (`openWorldHint`) and are in `book`; the delete is admin (`full` only).
- `portfolixir.notes.list` — a security's research log newest first with the
  derived thesis state; the description states that entries never vanish
  (ADR-0044).
- `portfolixir.notes.append` — the only write the log admits; a retraction
  with `supersedes_id` is how a finding is withdrawn. It takes `headline`,
  `event_type` and `tone` on an evidence or event_result entry, and
  `cluster_id`: a news story kept with the agent's body, the server setting
  the rest as [Research log](#research-log-adr-0044) says; the
  companion refuses `as_of`, `source_url` or `source_quality` beside
  `cluster_id`, and a note without `cluster_id` missing `kind`,
  `source_quality` or `as_of`, before any request. A summary, never the
  article, and a direction to score as a prediction with `note_id`.
- `portfolixir.notes.unreviewed` — held positions with no entry for N days.
- `portfolixir.notes.uncorroborated` — entries whose source quality is not
  primary.
- `portfolixir.notes.expiring` — dated blocks expiring within N days.
- `portfolixir.predictions.create` — records one prediction (ADR-0055), a
  write in the `book` and `full` profiles; its description says, before its
  first field, that a prediction cannot be edited, withdrawn or deleted, that
  a mistaken one stays and counts and that a correction is a new prediction,
  and tells the agent to name its model, which the schema requires; the
  probability is a string from `"0.50"` to `"0.99"` (`"0.49"` is refused
  before any request: record the other direction at `"0.51"`), a `rate:`
  benchmark is a fraction up to 1, and a `made_at`, `author` or `actor` is
  refused before any request. It says the start close is the last on or
  before the UTC day made, that a call stays open after `resolves_on` until
  its end close is in (at most 7 days), and that a prediction keeps its
  security and benchmark from a merge or a delete.
- `portfolixir.predictions.list` — the predictions with their status at
  read, filtered as `GET /api/v1/predictions` is, the due query
  (`due_before`) among them.
- `portfolixir.predictions.get` — one prediction with its resolution and the
  closes it used.
- `portfolixir.predictions.calibration` — the calibration report; the three
  reads are read-only, in every profile, and say briefly that a prediction is
  permanent.
- `portfolixir.quotes.sync`
- `portfolixir.quotes.list`
- `portfolixir.quotes.upsert` — every row stored as manual; its schema offers
  `source: manual` only, and the answer names the replaced dates.
- `portfolixir.quotes.manual` — a security's manual quotes over the whole
  history: count, first and last date, the stretches, the count of a range,
  and whether the sync can refill a released date; a read.
- `portfolixir.quotes.release` — the journaled release of a range's manual
  quotes back to provider data; the operator's control is **Release…** on the
  security's Quotes tab.
- `portfolixir.portfolios.list` — deprecated (ADR-0024): steers to
  buckets/views in its description.
- `portfolixir.portfolios.create` — deprecated (ADR-0024): compatibility only;
  prefer `portfolixir.buckets.create` / `portfolixir.views.create`.
- `portfolixir.cash_accounts.list`
- `portfolixir.cash_accounts.create`
- `portfolixir.cash_accounts.update` — its description and its
  `currency_code` property state the currency freeze (ADR-0050 §11).
- `portfolixir.cash_accounts.delete`
- `portfolixir.cash_accounts.set_balance`
- `portfolixir.cash_accounts.remove_former_name` — removes one former name
  (ADR-0050 §4); its description says what that costs: an import that still
  names it then creates a new account.
- `portfolixir.cash_accounts.merge_preview` — the merge preview, a read
  (ADR-0050 §7, §10): both outcomes of the duplicate question and the
  `plan_digest`.
- `portfolixir.cash_accounts.merge` — the merge under an approved digest;
  hinted destructive and idempotent (a retry answers the original record).
  Its description says what the merge does to the next import: the source's
  names become former names of the target, a later import naming them books
  there — except a name another account still carries, which is not kept —
  and a re-import of an applied export creates nothing.
- `portfolixir.securities_accounts.list`
- `portfolixir.securities_accounts.create`
- `portfolixir.securities_accounts.update`
- `portfolixir.securities_accounts.delete`
- `portfolixir.securities_accounts.remove_former_name` — the same for a depot.
- `portfolixir.securities_accounts.merge_preview` — the depot merge preview,
  a read (ADR-0050 §7, §10): every affected position before and after for
  both outcomes of the duplicate question, the bucket plan, `positions_basis`
  and the `plan_digest`.
- `portfolixir.securities_accounts.merge` — the depot merge under an approved
  digest; hinted destructive and idempotent (a retry answers the original
  record). Its description says that bookings keep their cash account, that
  every position keeps its view membership, and what the merge does to the
  next import: the source's names become former names of the target, a later
  import naming them books there — except a name another depot still
  carries, which is not kept — and a re-import of an applied export creates
  nothing.
- `portfolixir.transactions.list`
- `portfolixir.transactions.create`
- `portfolixir.transactions.update`
- `portfolixir.transactions.delete` — one row; on a split it names
  `portfolixir.splits.delete`
- `portfolixir.splits.preview`
- `portfolixir.splits.create`
- `portfolixir.splits.delete` — the whole split from any of its rows, every
  portfolio's row in one journaled step (#912); an admin tool, so the `book`
  profile leaves it out
- `portfolixir.holdings.list`
- `portfolixir.cashflow.realized_gains` — the #724 roll-up with its stated
  FX basis and the excluded-and-named gap treatment, and each trade's
  annualized return (#984)
- `portfolixir.cashflow.external_flows` — the #725 roll-up with the stated
  invested-capital difference
- `portfolixir.cashflow.costs` — the #726 roll-up with the stated
  legs-not-gross series rule
- `portfolixir.sales.hindsight` — what each sale missed (FR-50):
  `GET /api/v1/sales/hindsight` with its filters and the optional
  `benchmark`, read-only in every profile; the description says it scores
  nothing and gives no verdict. Its `include` (`reinvestment`) adds what a
  switch cost, and the description says what that block is: found by rule,
  before tax, price only
- `portfolixir.holdings.by_security`
- `portfolixir.holdings.negative`
- `portfolixir.splits.incomplete` — the incomplete-split check (#1292),
  read-only, with its remedy
- `portfolixir.transactions.rate_only` — the stored rate-only trades
  (#1290), read-only, with its remedy
- `portfolixir.transactions.cash_mismatch` — the stored trades whose cash
  misses their figures (#1371), read-only, with its remedy
- `portfolixir.holdings.reconcile` — read-only compare of a pasted external
  position list against the ledger; its description steers the agent toward
  booking the missing transaction of the correct kind instead of balance
  snapshots or unpriced deliveries.
- `portfolixir.portfolios.valuation` — scope twin of `portfolixir.views.valuation`
  (see "Scope twins" above). Both pass `unvalued_cash_count` through, with
  or without `include_positions` (#1081).
- `portfolixir.exchange_rates.list`
- `portfolixir.exchange_rates.sync` — `scope=latest` (daily feed) or
  `scope=history` (the one-shot historical backfill, issue #737).
- `portfolixir.classifications.list`
- `portfolixir.classifications.create`
- `portfolixir.classifications.categories.create`
- `portfolixir.classifications.update`
- `portfolixir.classifications.delete` — one call removes the tree with every
  category, every security's assignment in it, every target weight on its
  categories and every target plan of it; the description names each, and
  that each of those rows is journaled as its own delete before the
  classification's (E25). `dry_run: true` deletes nothing and answers
  `would_remove`, per kind the count and the ids, or the delete's refusal
  (issue #894).
- `portfolixir.classifications.categories.update`
- `portfolixir.classifications.categories.delete` — one call removes the
  category with its sub-categories at every depth, the assignments to any of
  them and the target weights on any of them; the journal keeps each as its
  own delete, the category itself last. `dry_run: true` answers what would
  go, as on the classification delete.
- `portfolixir.classifications.assign`
- `portfolixir.classifications.assign_bulk`
- `portfolixir.classifications.unassign`
- `portfolixir.trades.list`
- `portfolixir.targets.list`
- `portfolixir.targets.set`
- `portfolixir.targets.delete`
- `portfolixir.targets.list_positions`
- `portfolixir.targets.delete_position`
- `portfolixir.portfolios.allocation`
- `portfolixir.portfolios.category_results` — one portfolio, which `view`
  narrows, `view` alone for the view across every portfolio (#901), or
  neither for every portfolio in EUR (#1091).
- `portfolixir.portfolios.risk`
- `portfolixir.policy_rules.list` — the stored rules with the version in
  force on `as_of` (ADR-0049); the description tells the agent to read them
  here instead of restating them, calls each a stored rule whoever wrote it,
  and points to the audit journal for its author.
- `portfolixir.policy_rules.get` — one rule with its whole version history.
- `portfolixir.policy_rules.create` — stores a rule with its first version; the
  description carries the measure matrix and the scales, and states that a
  version is permanent once in force: the rule can then only be retired.
- `portfolixir.policy_rules.add_version` — the edit: a new version, never an
  overwrite, and permanent once in force. It closes the version in force the
  day before and replaces every scheduled version from its date, so it is
  hinted destructive and held with the admin tools.
- `portfolixir.policy_rules.rename` — the name only; the description states
  that a rename creates no version and the versions do not change.
- `portfolixir.policy_rules.retire` — ends the version in force; everything
  stays readable.
- `portfolixir.policy_rules.delete` — only for a rule nobody was ever measured
  against.
- `portfolixir.portfolios.policy_findings` — did anything cross a line? The
  rules in force today evaluated into findings; `status=breached` is the
  alarm list, and the description says undetermined is never a pass.
- `portfolixir.portfolios.cash_target`
- `portfolixir.portfolios.set_cash_target`
- `portfolixir.portfolios.income`
- `portfolixir.portfolios.performance` — scope twin of `portfolixir.views.performance`.
- `portfolixir.portfolios.benchmark` — scope twin of `portfolixir.views.benchmark`.
- `portfolixir.portfolios.contribution` — scope twin of `portfolixir.views.contribution`;
  which position made how much of a period's money result (FR-41).
- `portfolixir.portfolios.bands` — scope twin of `portfolixir.views.bands`;
  the value series split into bands by total, category or security, for the
  stacked chart (I23, FR-53); with `scale: "ttwror"` each band's own TTWROR
  as a line (FR-57).
- `portfolixir.journal.list`
- `portfolixir.merges.list` — the merge records, newest first, each with
  what went into what, who did it, when, and the manifest summarized
  (ADR-0050 §12), the removed bookings also per reason; a read — the
  operator's list is **Merges** on Accounts & depots.
- `portfolixir.buckets.list`
- `portfolixir.buckets.get`
- `portfolixir.buckets.create`
- `portfolixir.buckets.update`
- `portfolixir.buckets.delete`
- `portfolixir.views.list`
- `portfolixir.views.get`
- `portfolixir.views.create`
- `portfolixir.views.update`
- `portfolixir.views.delete` — one call removes the view with its bucket
  sets, every target plan scoped to it and every depot snapshot taken in its
  scope; each is journaled as its own delete before the view's.
  `dry_run: true` answers what would go, as on the classification delete.
- `portfolixir.views.set_buckets`
- `portfolixir.views.valuation` — scope twin of `portfolixir.portfolios.valuation`;
  without an `id`, the total of every account (#1007).
- `portfolixir.views.performance` — scope twin of `portfolixir.portfolios.performance`.
- `portfolixir.views.benchmark` — scope twin of `portfolixir.portfolios.benchmark`.
- `portfolixir.views.contribution` — scope twin of `portfolixir.portfolios.contribution`.
- `portfolixir.views.bands` — scope twin of `portfolixir.portfolios.bands`.
- `portfolixir.securities_accounts.set_buckets`
- `portfolixir.cash_accounts.set_buckets`
- `portfolixir.securities_accounts.set_position_buckets`
- `portfolixir.securities_accounts.clear_position_buckets`
- `portfolixir.settings.get_default_view`
- `portfolixir.settings.set_default_view`
- `portfolixir.plans.list`
- `portfolixir.plans.duplicate`
- `portfolixir.plans.activate`
- `portfolixir.plans.rename`
- `portfolixir.plans.delete`
- `portfolixir.snapshots.list`
- `portfolixir.snapshots.create`
- `portfolixir.snapshots.delete`
- `portfolixir.snapshots.comparison`
- `portfolixir.tax_parameters.list`
- `portfolixir.tax_parameters.upsert`
- `portfolixir.tax_profiles.list`
- `portfolixir.tax_profiles.create`
- `portfolixir.tax_profiles.update`
- `portfolixir.tax_profiles.delete`
- `portfolixir.allowance_orders.list`
- `portfolixir.allowance_orders.put`
- `portfolixir.allowance_orders.delete`
- `portfolixir.tax_snapshots.list`
- `portfolixir.tax_snapshots.get`
- `portfolixir.tax_snapshots.create`
- `portfolixir.tax_snapshots.update`
- `portfolixir.tax_snapshots.delete`
- `portfolixir.tax_snapshots.trim_budget`
- `portfolixir.news.feeds_put`
- `portfolixir.news.feeds_delete`
- `portfolixir.news.sources_put`
- `portfolixir.news.list`
- `portfolixir.news.get`
- `portfolixir.news.health`
- `portfolixir.news.digest`
- `portfolixir.news.assign`
- `portfolixir.news.registry`
- `portfolixir.news.unlabeled` (`label` profile only)
- `portfolixir.news.label_put` (`label` profile only)

The `portfolixir.portfolios.valuation`, `portfolixir.portfolios.allocation`,
`portfolixir.portfolios.performance`, `portfolixir.portfolios.contribution`,
`portfolixir.portfolios.risk` and `portfolixir.portfolios.category_results`
tools accept an optional `view` (a view id) that scopes the result to the
holdings matching that bucket view; the response then echoes the active view. `portfolixir.portfolios.category_results`
also takes `view` without `portfolio_id`: the view across every portfolio, in
EUR (#901); with neither it reads every portfolio, in EUR (#1091).
`portfolixir.views.valuation` values a view **across all portfolios** in one
call (each matching account counted once, EUR totals, `overlap` badge data),
and without an `id` the total of every account (#1007) — use it instead of
summing per-portfolio valuations client-side.
`portfolixir.views.performance` computes the matching cross-portfolio
TTWROR/IRR for the same account scope, with boundary-crossing money treated
as an external flow (ADR-0019), and without an `id` the return of every
account, in EUR (#1056).
`portfolixir.settings.get_default_view` / `portfolixir.settings.set_default_view`
read and set the default-view preference (ADR-0024): pass a `view_id` to pin a
view, or `null`/omit it to clear back to the built-in Everything scope.

`portfolixir.portfolios.benchmark` and `portfolixir.views.benchmark` are
the twins of the two benchmark reads (ADR-0046): `benchmark` is
`rate:<decimal>` or `security:<id>`, the period, view and series parameters
are the performance tools', and the response carries both comparisons,
the covered window, the excluded flows and the computation basis with the
frictionless assumption stated. The view tool without an `id` compares every
account, in EUR (#1056). A refused benchmark comes back as the API's `422`
body, `merged_into` included for a merged-away security whose survivor is a
benchmark (#959).

`portfolixir.portfolios.contribution` and `portfolixir.views.contribution`
are the twins of the two contribution reads (FR-41, ADR-0051): the period and
view parameters are the performance tools' (there is no `series`), and the
response carries each position's contribution, the three remainder lines, the
totals — `positions` plus `remainder` is `result`, the performance read's
money result — and the computation basis with its assumptions stated. Both
are reads, so every profile lists them. The view tool without an `id` reads
every account, in EUR (#1056).

Since ADR-0020 the target tools (`portfolixir.targets.list`,
`portfolixir.targets.set`, `portfolixir.targets.delete`) and the cash-target
tools (`portfolixir.portfolios.cash_target` to read,
`portfolixir.portfolios.set_cash_target` to set or clear) also accept an optional
`view` (a view id) that selects the target plan; omitting it addresses the
portfolio-wide Gesamt plan. The cash target moved off the portfolio object onto
the plan, but `portfolixir.portfolios.set_cash_target` without a `view` still
steers the Gesamt cash target, so it keeps the same effect as the legacy
portfolio `cash_target_weight` field. All cash targets and target weights are
exposed and accepted as Decimal strings.

Since ADR-0030 (#481) the same tools carry **position-level** SOLL: a
`portfolixir.targets.set` entry that adds a `security_id` sets a weight on that
individual position under its category, `portfolixir.targets.list_positions`
reads the position rows plus each category's effective roll-up (explicit,
position sum, effective steering weight, and a `conflict` flag surfacing an
explicit/position mismatch — plus per-row `stale` and per-category `has_stale`
flags marking rows whose security no longer sits under the stored category),
and `portfolixir.targets.delete_position` removes one position target.
Category-only calls are unchanged.

Since ADR-0027 the plan tools (`portfolixir.plans.list`,
`portfolixir.plans.duplicate`, `portfolixir.plans.activate`,
`portfolixir.plans.rename`, `portfolixir.plans.delete`) manage named plan
**versions**: duplicate the active plan into a draft, edit the draft by passing
its id as `plan_id` to `portfolixir.targets.set`, `portfolixir.targets.delete`
and `portfolixir.targets.delete_position` (issue #1133; without it they write
the view's active plan, and an archived plan is refused), or in the SOLL
editor, read it back by passing the same `plan_id` to `portfolixir.targets.list`
and `portfolixir.targets.list_positions` (issue #1185), then activate it. The snapshot tools
(`portfolixir.snapshots.list`, `portfolixir.snapshots.create`,
`portfolixir.snapshots.delete`, `portfolixir.snapshots.comparison`) freeze a
depot state as a marker and read the counterfactual comparison; every financial
value in the comparison is a Decimal string and the response labels its basis
(gross, price-return only).
