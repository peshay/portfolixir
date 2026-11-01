# Sprint 22 — the severity pass over every open issue

Part of [`sprint-plan-2026-11-01-sprint22.md`](sprint-plan-2026-11-01-sprint22.md)
(D-3). Adopted with it, by the merge of the Sprint 22 planning PR.

**What this is.** Every open issue on 2026-11-01 except the six area
trackers and the two `needs-uat` runs (#328, #354), read with its comments
and checked against the code on `main` at `ad2f052` by four read-only
triage passes, then given a severity under [ADR-0026's amendment of
2026-11-01](../../docs/decisions/0026-epic-batch-workflow.md):

- **S1:** a figure, booking, stored record or derivation can be wrong; a
  security boundary can be crossed; a gate silently checks nothing.
- **S2:** a defect the operator or the agent meets in normal use.
- **S3:** polish.
- **FEATURE:** not a defect; new capability.
- **—:** does not reproduce, or is already done (closed with evidence).

**Where each goes.** "builds in <lane>" is a story of this sprint (the
plan's lane tables). "polish list: <screen>" is a line on that screen's
`tracking` issue, which Lane Z creates; the issue is closed by hand with a
pointer to its line, and its text stays the specification. "stays open"
names its reason.

**The counts.** 106 issues: 11 S1, 20 S2, 61 S3, 6 features, 7 that do not
reproduce. 39 build in this sprint (every S1, every S2, I1 and seven S3s
that sit in a function a story rewrites); 53 go onto twelve polish lists;
7 close with evidence; 7 stay open.

**What the per-issue evidence is.** Each triage pass recorded file:line
evidence, a commit estimate and a recommended answer per issue. The
evidence lives in the passes' working notes, outside the repository; the
implementation session re-reads each issue it builds against the code, as
the story workflow orders.

| Issue | Severity | Where it goes | Title |
|---|---|---|---|
| #894 | FEATURE | stays open: feature; F21 on the idea list | Dry-run deletes: show what a cascading delete removes before it removes it |
| #899 | FEATURE | stays open: feature; widening phase (owner, 2026-10-02) | Idempotency-Key on irreversible writes (architecture D11/P8, AR-5) |
| #900 | FEATURE | stays open: feature; its own story after the launch | ADR-0041 §5's slice two (realized result and income per category) has no issue |
| #925 | S3 | polish list: Imports | Bulk-preload import hashes for the per-row hash check |
| #951 | S3 | polish list: API/MCP | Add MCP maxLength to the G02 free-text fields |
| #957 | S2 | builds in A | List the flow effects of depot and security collapses in the merge preview |
| #971 | — | close by hand, with evidence (D-4) | Profile the import apply's added per-row cost (about 37 % on a large synthetic file) |
| #1070 | FEATURE | stays open: feature; needs an ADR-0050 reading | A security merge does not carry bond master data from the merged-away security |
| #1115 | FEATURE | stays open: dependency lane; before v1 support ends 2027-01-27 | The MCP companion moves from @modelcontextprotocol/sdk v1 to v2's server package |
| #1177 | S3 | stays open: owner-only data model; trigger: a switcher's export (D1) | PP JSON: the INTEREST_CHARGE and FEE_REFUND types are refused, and a negative FEE unit is stored as a posit… |
| #1219 | S2 | builds in R3 | Decide: a refused row's "book it by hand" remedy is shown although the booking already exists |
| #1220 | S3 | stays open: parked: fails closed, deferred by design | Decide: the rename probe could count as seen a former name the import preview's "remember" wrote |
| #1221 | S3 | polish list: Shell+global | The app names Inter but ships no font file, so every width floor depends on the reader's system font |
| #1222 | S3 | polish list: Overview | Overview: when the total leaves nothing out, nothing says Wealth opens on another view |
| #1223 | S3 | polish list: Cash flow+Income | Cash flow → Ein- & Auszahlungen: the Netto row never shows a month's net |
| #1224 | S3 | polish list: History+drawer | With the booking drawer open the history hides Preis and Betrag behind a sideways scroll |
| #1225 | S3 | polish list: Accounts | Accounts: "Saldo setzen" sits under the balance below about 1500 px, where #670 put it beside |
| #1226 | S3 | polish list: Classifications+targets | Decide: a duplicated plan version is named "… (copy)" in English |
| #1241 | S3 | polish list: Merge pages | Merge refusals on the page still put stored names inside their sentences |
| #1251 | S3 | polish list: Imports | Decide: the import preview's parse moves off the page process (T-18's design issue) |
| #1252 | S3 | polish list: History+drawer | An edit that moves a booking to another depot or security takes the new parent's lock after its row lock, t… |
| #1253 | — | close by hand, with evidence (D-4) | A cash merge and a depot merge over overlapping bookings lock depots and bookings in opposite orders, so on… |
| #1254 | S2 | builds in A | The capped list reads outside the five delta reads carry no truncated flag, and several do not echo their l… |
| #1255 | S3 | polish list: Accounts | The account dialog labels any bare changeset error after a refusal as "The new tag could not be created." |
| #1256 | S3 | polish list: Shell+global | A FunctionClauseError crash report of a live page can still print the handler's arguments, form values incl… |
| #1257 | S3 | polish list: Engineering/tests | config/config.exs imports the environment file by Mix.env(), so a test that reads the prod configuration th… |
| #1258 | — | close by hand, with evidence (D-4) | The holdings reconcile endpoint documents no row cap, so its body is bounded by bytes alone |
| #1259 | S3 | polish list: Accounts | The account dialog crashes on a bucket-set refusal it has no clause for ({:error, :bucket_ids} or {:error, … |
| #1260 | S3 | polish list: Engineering/tests | The invisible-Unicode gate does not flag the line and paragraph separators U+2028 and U+2029 |
| #1261 | S3 | polish list: Engineering/tests | The invisible-Unicode gate skips a file by its binary extension even when it is valid UTF-8 text |
| #1262 | S3 | polish list: Shell+global | A swapped token=name entry in PORTFOLIXIR_API_TOKENS can still echo the token into the boot refusal as the … |
| #1263 | S3 | polish list: Shell+global | On the run-from-source route a local process can test password guesses through LiveView mounts, outside the… |
| #1264 | S3 | polish list: Shell+global | The login lifetime does not slide over the socket: a page used only through events is sent to the login whe… |
| #1265 | S3 | polish list: Imports | The import parsers hand a numeric cell of any length to Decimal.new, so a many-megabyte amount is still mat… |
| #1266 | S3 | polish list: Imports | Two Imports tabs in one browser session overwrite each other's parked mapping |
| #1267 | S3 | polish list: Imports | The Imports page's file error names an unsupported JSON version string at any length |
| #1268 | S2 | builds in F | SecuritySearchTest "isolates a crashing provider" fails under machine load: the expected log line is not ca… |
| #1269 | S1 | builds in R2 | The write-actor gate's classifier overwrites its accumulator, so most writers are never checked |
| #1270 | S3 | polish list: API/MCP | The journal read has no actor filter, so a principal's writes cannot be listed by name |
| #1271 | S3 | builds in R2 | The securities page's "update logo" action calls the lookup directly and skips the locked-security check th… |
| #1272 | S3 | builds in R2 | Settings.put/2 and Settings.delete/1 are public unjournaled writers that could set the default-view key aro… |
| #1273 | S2 | builds in F | The Wealth phone-twins test runs close to render_async's two-second default and times out under parallel load |
| #1274 | S1 | builds in R9 | The income drilled-year table shows base-currency amounts beside a Currency column that names the cash acco… |
| #1275 | — | close by hand, with evidence (D-4) | The logo discovery's slug builder runs a lazy parenthesis pattern over the security's name without a length… |
| #1276 | S3 | polish list: Securities | A refused second catalog price sync still sends the "Price sync complete" notification with the refusal as … |
| #1277 | S3 | polish list: Accounts | The Accounts page's inline tag error and two forms print raw changeset field keys in English |
| #1278 | — | close by hand, with evidence (D-4) | Account dialog creates the new tag bucket before the depot name is validated, leaving an orphan bucket on r… |
| #1284 | S3 | polish list: Merge pages | Security merge preview: the split-event remedy and the identity-choice sentences still put a stored ISIN in… |
| #1285 | S3 | polish list: Merge pages | Securities merge page: a reverse refusal's reason carries no data fields, so an unresolvable reverse identi… |
| #1286 | S3 | polish list: Engineering/tests | The pre-commit invisible-Unicode gate checks the Cf category only and misses the default-ignorable code poi… |
| #1288 | S3 | polish list: API/MCP | A portfolio created through the API during a first import or account create can take over as the default po… |
| #1289 | S3 | polish list: Engineering/tests (rescoped to the lock-site inventory gate) | No test reads the lock-order table against the lock sites in lib, so a new lock site can diverge from it un… |
| #1290 | S2 | builds in R6 | The stored cross-currency trades the settlement guard lists have no operator surface: only a console call r… |
| #1291 | S1 | builds in R1 | Decide: the API accepts JSON numbers for money fields, so a float crosses the boundary before Ecto casts it… |
| #1292 | S1 | builds in R6 | A split event whose rows miss a portfolio that held the security scales that portfolio's FIFO lots but not … |
| #1293 | S3 | builds in R9 | Income: a year whose payments are all unconverted has no annual row, so the note counts payments the page c… |
| #1294 | S2 | builds in A | Securities list: a sort by an attribute or a column has no id tie-break, so limit/offset paging over ties c… |
| #1295 | S2 | builds in A | A delta read accepts offset beside a cursor, which skips rows; refuse the combination |
| #1297 | — | close by hand, with evidence (D-4) | mix portfolixir.backfill_settlement_legs raises on a booking deleted mid-run instead of reporting it |
| #1298 | — | close by hand, with evidence (D-4) | The settlement-leg derivation re-checks the legs under the row lock, not the figures it derived them from |
| #1299 | S2 | builds in U | The history's "Record transaction" button needs a depot, so a cash-only instance cannot reach the drawer's … |
| #1300 | S3 | polish list: Imports | An import whose depot first appears on a delivery row stops with depot_needs_cash when no account mapping i… |
| #1301 | S2 | builds in A | Targets reads: a malformed classification_id beside plan_id is silently ignored instead of refused |
| #1302 | S3 | polish list: Shell+global | app.css: the `.chart rect` rule looks unused (no template uses the `chart` class) |
| #1303 | S3 | polish list: Imports | Import preview: a security created by the operator's "+ Create new" on a decision row is not simulated for … |
| #1304 | S3 | polish list: Imports | Import correction confirm: a booking created after its locked read is not seen, so the confirm can correct … |
| #1305 | S2 | builds in R3 | Import preview: a JSON v1 row missing a required security previews clean, and the apply then refuses the wh… |
| #1306 | S1 | builds in R3 | Import: a JSON v1 `time` the parser cannot read silently becomes no time, so two rows can fold into one hash |
| #1307 | S3 | builds in R3 | Import: a negative JSON v1 `amount` on a cash row shows no preview warning and is skipped at apply with a w… |
| #1308 | S3 | polish list: Imports | Decide: the import preview's dry run, stopped by a writer in flight, is parked as answered and never re-run… |
| #1309 | S1 | builds in R7 | Decide: withheld taxes on an interest booking are stored but Income reads interest as carrying no withholding |
| #1310 | S1 | builds in R5 | Trades: a trade unavailable because a lot or its sale is priced in a third currency carries the missing-leg… |
| #1311 | S2 | builds in R5 | Settlement backfill: a zero-amount lot (a free allotment) is counted "no rate" on every run and its trade s… |
| #1312 | S3 | polish list: Engineering/tests | Review seed: a second run rewrites six securities' quotes, touches 18 target and assignment rows and flips … |
| #1313 | S1 | builds in R4 | Decide: the UI import books into the default portfolio only, so a file first imported into another portfoli… |
| #1314 | S3 | polish list: History+drawer | Date fields accept ISO dates only and show the English "YYYY-MM-DD" placeholder in the German UI; a German … |
| #1315 | S2 | builds in A | Views API: PUT /views/:id/buckets and PATCH /views/:id with include_all=false answer 200 and leave include … |
| #1316 | S1 | builds in R8 | Security page, Bestände tab: a position with no quote shows its value as "—" and "Gesamt 0,00" while the ho… |
| #1317 | S2 | builds in R5 | Realized gains: computation_basis.reference and .gaps still describe the close-date rate for trades read on… |
| #1319 | S3 | polish list: Shell+global | Decide: EXPERIENCE.md's Accessibility Floor writes "+/−" (U+2212) while Format and DESIGN.md use the hyphen… |
| #1320 | S3 | polish list: Overview | Twin names in the excluded-sales and unvalued notes need security ids in the payloads the notes read |
| #1321 | S3 | polish list: Cash flow+Income | Cash flow → Trades: the money cells have no text space before the currency, so their text reads "300,00EUR" |
| #1322 | S3 | polish list: Wealth | Wealth's holdings table scrolls sideways at 1200 px on the review seed: long names and a 12-digit quantity … |
| #1324 | S3 | polish list: Classifications+targets | Classifications: a dismissed result is focused twice, first by the shared hook, then by the page's own focu… |
| #1325 | S3 | polish list: Imports | Imports: while a mapped recount runs, a row the choice did not touch keeps its old count unmarked, though t… |
| #1326 | S3 | polish list: Imports | Import mapping: a pushed security id that names a benchmark is accepted, and the apply books the file's row… |
| #1327 | S3 | polish list: Imports | Imports done page: "1 Wertpapiere wurden manuell zugeordnet." is a hand-made plural |
| #1328 | S3 | polish list: Classifications+targets | Classifications: a move's confirmation lands in the result slot far above the tree, out of view, with the f… |
| #1329 | S3 | polish list: Classifications+targets | Classifications: an archived or draft plan version's table scrolls its weights out of view between about 64… |
| #1330 | S2 | builds in U | Shell: a sidebar collapsed to its rail re-opens on any click that updates the page, flipping the accounts t… |
| #1331 | S1 | builds in R8 | Security page, Transaktionen tab: a dividend's Brutto prints the net cash when no gross is stored, while In… |
| #1332 | S2 | builds in R8 | Wealth: a holding valued at its last trade price reads "—" in Letzter Kurs, Marktwert and G&V while the tot… |
| #1333 | S2 | builds in U | Accounts and the history's account filter cannot tell two same-named accounts in different portfolios apart |
| #1334 | S3 | polish list: Securities | Securities: the logo fallback builds a flag avatar from an ISIN's first two letters even when they are no c… |
| #1335 | S1 | builds in R10 | Booking drawer: an imported cross-currency buy without settlement legs opens with "Preis (USD)" though the … |
| #1336 | S2 | builds in I | Cash flow: the facets' ⓘ panels open above the top of the page and, on a phone, past its right edge |
| #1337 | S3 | builds in R10 | Sell preview: the Kaufpreis prints the stored price as "24 EUR" where the history prints "24,00 EUR" |
| #1338 | S3 | polish list: Engineering/tests | Review seed: add a refund-only month, an unconvertible cost and a today snapshot, so Cash flow's and the sn… |
| #1339 | S3 | polish list: Wealth | Wealth: the "Daten als Tabelle" disclosure collapses on every category toggle inside it, lacking the Disclo… |
| #1340 | S3 | polish list: Securities | The logo dialog and the two blocked-delete dialogs return the focus to the body, not to the row menu that o… |
| #1341 | S3 | polish list: Securities | Security chart: the hover readout is a status region with no keyboard path that announces on every pointer … |
| #1342 | S3 | builds in I | ⓘ panels (details.metric-tooltip, Buckets ⓘ) do not close on Escape, and the H45 picker has no live region … |
| #1343 | S2 | builds in U | Risk: a zero drawdown's sub-line names a peak, a trough and a recovery that never happened |
| #1345 | S2 | builds in F | Flaky test: the log-noise harness's "records a warning that reaches its handler" can see no event under the… |
| #1350 | S3 | builds in I | The view switcher's ⓘ opens as a plain paragraph in the page flow, not as a popover |
| #1351 | FEATURE | builds in I | Explanations behind a section ⓘ, data notes clamped and collected (idea I1) |
