# Sprint 30 UAT persona on the review seed, without Inter installed (2026-11-19)

The closing act's last bullet of the Sprint 30 plan
(`sprint-plan-2026-11-15-sprint30.md`, D-5; D-1 criterion 1), walked on
head `e4c2c9e` in CI's browser (Playwright 1.65.0's chromium-headless-shell,
revision 1254), German, device scale 2, 1200 px unless a name says `phone`
(390 px), light theme. Every figure is from the synthetic review seed
(`priv/demo/finding_surfaces_seed.exs`, step 25 included: the negative cash
days and the crash benchmark); nothing describes a real person or
portfolio.

## How the walk ran

- A fresh development database, migrated and seeded with the review seed as
  `priv/demo/README.md` says, then `mix phx.server` on a loopback port with
  `PORTFOLIXIR_BACKGROUND_FETCH=off`, so nothing was fetched. The walk
  started shortly before midnight UTC, so the server ran in a time zone west
  of UTC: the app's day stayed 19.11.2026, the seed's day, for the whole
  walk.
- **No Inter on the machine:** the browser ran with a fontconfig that lists
  the system's fonts without Inter (`fc-list` finds no Inter under it;
  `fc-match Inter` answers DejaVu Sans). Every request to another origin was
  aborted by the walk; none was made.
- The API reads used a bearer token from the server's environment, made for
  the walk; it is in no file here.
- Two states were made for the walk and undone afterwards, both journaled:
  the detected crash window named „Synthetic summer slide“ and the crash
  benchmark switched to iShares Core MSCI World over the API (for the names
  table, screenshots 27 and 28), then the benchmark set back to Vanguard
  FTSE All-World and the name deleted; and a deposit of 1,00 EUR on Demo
  Cash, booked and deleted for the Allocation tab's busy figure (screenshot
  21). The 1J TTWROR read the same to the last digit before and after.

## The font check (D-1 criterion 1)

| Case | `document.fonts` and what drew the text | Connected | Font requests |
|---|---|---|---|
| Inter not installed, `/fonts/` served | the latin face `loaded`, the other three `unloaded` (no glyph of theirs on the page); Chrome's platform fonts for the headings and the card's basis line: „Inter (web font)“; the walks' own check (`test/browser/fonts.js`, `checkFonts`) passes | yes | one, `/fonts/inter-latin-wght-normal.woff2?vsn=5.3.0`, same origin |
| `/fonts/*` blocked | the latin face `error`; the same nodes draw in „DejaVu Sans (installed)“; `checkFonts` refuses the page („no Inter face loaded“), as it should | yes | the one request, aborted |

Screenshots 01 (own Inter) and 02 (fallback). ⓘ, ≈ and → come from the
next font in the stack in both cases, as D-4 planned. **Result: the page
draws in its own Inter from `/fonts/` on a machine without Inter, and in the
fallback, connected, when the file is blocked; no request leaves the app.**

## Screenshots

| # | File | What it shows |
|---|---|---|
| 01 | `01-light-overview-own-inter-no-inter-installed.png` | The Overview without Inter installed, drawn in the app's own Inter |
| 02 | `02-light-overview-fonts-blocked-fallback.png` | The same with `/fonts/*` blocked: DejaVu Sans, connected |
| 03 | `03-light-overview-tops-flops-day.png` | „Tops und Flops“ on „Tag“: each price row with its two dates, „Beitrag am 19.11.2026“, the counts incl. „23 Positionen ohne Beitrag an ihrem Tag“ (finding 1) |
| 04 | `04-light-overview-tops-flops-week.png` | „Woche“: Schlusskurs 15.11.2026 bis 19.11.2026 |
| 05 | `05-light-overview-tops-flops-month.png` | „Monat“: 31.10.2026 bis 19.11.2026 |
| 06 | `06-light-overview-tops-flops-quarter.png` | „Quartal“: 30.09.2026 bis 19.11.2026 |
| 07 | `07-light-overview-tops-flops-ytd-sold.png` | „YTD“: Wrenfield Gardens AG and Tamarisk Mining Ltd „verkauft“ |
| 08 | `08-light-overview-tops-flops-1y.png` | „1J“: 19.11.2025 bis 19.11.2026 |
| 09 | `09-light-overview-tops-flops-basis-info.png` | The card's ⓘ open: the method, five lines |
| 10 | `10-light-wealth-landing-month-contribution.png` | „In Vermögen ansehen“ from „Monat“: Wealth on 01.11.2026 – 19.11.2026, „Beitrag je Position“ |
| 11 | `11-light-wealth-landing-day.png` | The same from „Tag“: Wealth on 19.11.2026 – 19.11.2026 |
| 12 | `12-light-overview-tops-flops-privacy.png` | Privacy mode: percentages kept, each amount the mask, its colour and bar kept |
| 13 | `13-phone-overview-tops-flops-day-390.png` | 390 px, „Tag“: the rankings stacked, „Kursrendite“ first, no sideways scroll |
| 14 | `14-phone-overview-tops-flops-ytd-390.png` | 390 px, „YTD“ with „verkauft“ |
| 15 | `15-phone-overview-tops-flops-basis-info-390.png` | 390 px, the ⓘ open inside the viewport |
| 16 | `16-light-wealth-total-axis-window-mark.png` | Wealth › Gesamt in „Wert“: „Achse: Ausschnitt · ab 0“, the axis from 54.870 with the axis-break mark, the overdraft dent |
| 17 | `17-light-wealth-total-axis-from-zero.png` | „ab 0“: the stack's axis, −25.000 to 75.000, no mark (finding 2) |
| 18 | `18-light-wealth-categories-overdraft-tick.png` | „Kategorien“: the cash band below 0 on the overdraft days, one tick at −25.000, the values outside the plot |
| 19 | `19-light-wealth-total-ttwror-no-axis-switch.png` | „% (TTWROR)“: no axis switch, no mark |
| 20 | `20-light-wealth-holdings-notes-depot-1200.png` | Positions at 1200 px with all eight columns: notes on one line, depot on one line, no sideways scroll (finding 7) |
| 21 | `21-light-allocation-ttwror-busy.png` | Allocation & Ziele after a booking superseded the walk: every figure and the TTWROR busy, „wird berechnet“ |
| 22 | `22-light-crashes-detected-window-1200.png` | Risiko › Crashes: the window select, the detected window, „ggü. Vanguard FTSE All-World UCITS ETF USD Acc“ wrapping in its head, the basis line (finding 5) |
| 23 | `23-phone-crashes-rankings-390.png` | The rankings at 390 px as rows |
| 24 | `24-phone-crashes-axis-basis-390.png` | 390 px: the axis under the rows and the basis line (finding 3) |
| 25 | `25-light-crashes-windows-table-1200.png` | „Crash-Fenster“ open: the windows table at 1200 px |
| 26 | `26-phone-crashes-windows-rows-390.png` | The windows at 390 px as rows (finding 6) |
| 27 | `27-light-crashes-names-table-1200.png` | „Name ohne Fenster (1)“ with its reason sentence, the table inside its 922 px wrapper |
| 28 | `28-phone-crashes-names-table-390.png` | The same at 390 px (finding 4) |
| 29 | `29-light-security-chart-axis-mark.png` | Apple's price chart: the mark at the foot, „Achse ab 145,22, nicht ab 0“ in its accessible name |
| 30 | `30-phone-security-chart-axis-mark-390.png` | The same at 390 px |

## Steps and how they compared

| Step | Seen | Against the API |
|---|---|---|
| Each window chip, Tag to 1J | every name, rank, half, figure, „verkauft“, „n Tage mit 0“ mark, row dates („letzter Schlusskurs …“ where older than the end), each count line and the basis's dates | `GET /api/v1/movers?window=…&include_unanswered=true` for the six windows (the card reads the default view, Alles): **all equal**, price figures rounded half-up from the exact ratio, contributions to the cent |
| The counts | e.g. „Tag“: 21 ohne Kursrendite (19 ohne aktuellen Kurs, 2 mit nur einem Schlusskurs); 3 an keinem Tag bewertet; 23 ohne Beitrag an ihrem Tag | `unanswered` per reason, each equal |
| „In Vermögen ansehen“ | lands on `/portfolio?from=S+1&to=T` (Tag: `from=to=D`), Wealth's custom range chip and „Beitrag je Position“ on the same window | the link equals the contribution's `from`/`to` for all six windows |
| Wealth's contribution on each card window | all rows (after „Alle n anzeigen“), 35 to 41 per window, and the sum, e.g. Monat −213,47 EUR, 1J +7.348,65 EUR | `GET /api/v1/performance/contribution?from=…&to=…`: every row and the sum equal; every card contribution equals Wealth's row |
| Privacy mode | amounts masked, percentages, colours and bars kept; back off afterwards | — |
| Wealth KPIs and the stack's legend | 88.307,02 EUR, TTWROR 1J +8,0%, +7.348,65 EUR, IRR +9,4%; Crypto 2.569,68 · 2,9% · +12,3%, Stability 7.011,60 · 7,9% · +14,2%, Growth 26.320,60 · 29,8% · +11,0%, Nicht zugeordnet 33.226,39 · 37,6% · +3,8%, Cash 19.178,75 · 21,7% · +18,7% | `GET /performance?period=1y`, `GET /performance/bands?level=category&period=1y`: equal |
| „ab 0“ against „Kategorien“ | the same five ticks at the same heights; the line on the stack's top edge on 364 of 366 days; on 05.10. and 06.10.2026 it runs 24,88 viewBox units below it, the overdraft's 11.865,00 EUR at 25.000 per 52,42 units, as W1's test states | the bands on 05.10.2026 sum to 68.327,66 above 0 and −11.865,00 below, the line's point reads 56.462,66 EUR |
| Crashes, both windows × Verlierer, Gewinner, Erholer × Im Depot, Ganzer Katalog | every rank, security, „%“, „Pp“, „Tage bis Vorkrisenkurs“ and the counts without an answer; the detected window −11,5 %, gap 7 days | `GET /crashes` and `GET /crashes/:key/rankings?list=…&universe=held|catalogue`: **all 12 lists equal**, and again with iShares as crash benchmark (the manual window's six lists) |
| Security chart | Apple, axis from 145,22, the mark | the stored closes (`GET /securities/1/quotes`) |

**Every figure the screens showed matched the API.**

Seen and as designed, not defects: „Niedrigste“ can hold positive figures
(ADR-0061 §4's split); a position valued on no day stays off the card
although Wealth lists it, e.g. Larkspur Robotics Inc −930,00 EUR in YTD,
counted „an keinem Tag des Zeitraums bewertet“ (§4); with the seed's weekly
closes most shares' „Tag“ is Thursday to Thursday, and the card shows the
dates.

## Defects

1. **S3** On „Tag“ a price row's previous close may be months old: Tamarisk
   Systems Inc. „Di 23.06.2026 → Mi 18.11.2026“ (+1,2%, second highest),
   Kestrel Anleihe 2030 2,75% „Mi 15.10.2025 → Mi 18.11.2026“, Wexmoor
   Instruments AG „Mo 04.05.2026 → Do 19.11.2026“. ADR-0061 §3 bounds `E`
   at 7 days, and its amendment bounded the money side's `D`, but nothing
   bounds `P`, so a 13-month move ranks among the day's moves. The dates
   stand at the row, so nothing is hidden; whether `P` gets `E`'s bound is
   the ADR's to decide (screenshot 03).
2. **S3** At „ab 0“ the Total chart's area fill runs down to the stack's
   floor (−25.000), not to 0: the band between 0 and −25.000 is shaded under
   the line on every day, though the total never goes below 0 (the area
   path closes at the plot's foot). The line and the ticks are right
   (screenshot 17).
3. **S3** The crash rankings at 390 px: the axis under the rows spans 294 px,
   the rows' bar track 249 px, so „0 %“ stands 22 px right of the bars' zero
   line and „+20 %“ 45 px past the track's end; the dashed benchmark mark
   (−11,5 %) reads as about −14 % against the axis. At 1200 px they agree to
   1 px (screenshot 24).
4. **S3** „Name ohne Fenster“ at 390 px: the names table needs 694 px in a
   356 px wrapper; „Hoch“ and the actions („Als manuelles Fenster anlegen …“,
   „Löschen“) are reachable only by scrolling it sideways. W2 fixed it at
   1200 px, where it fits (screenshots 27, 28).
5. **S3** The Crashes basis line ends „nur Wertpapiere im Katalog.“ also
   under „Im Depot“, where the list holds the depot's securities; the
   clause is the same for both universes (screenshot 22).
6. **S3** The selected window's phone row (its tint) has no inner padding:
   „ohne Namen“, „-11,5 %“ and „läuft“ sit on the tint's edges (screenshot
   26).
7. **S3, older** Positions at 1200 px with all columns: „Larkspur Rail AG
   4,00 % Anleihe 2031“ breaks between „4,00“ and „%“ in the 9.5rem name
   column (screenshot 20).

No S1 or S2. Defects 1 to 6 are lines for their screens' polish lists
(1 with the ADR question), 7 for the Wealth list as an older finding.
