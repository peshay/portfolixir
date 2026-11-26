# Sprint 32 UAT persona on the review seed (2026-11-26)

The closing act's last walk of the Sprint 32 plan
(`sprint-plan-2026-11-25-sprint32.md`, D-1 criterion 6: "the UAT persona
walks the five boards' frames on the review seed at the widths of Sprint
31's walk"), walked on `e315545` (the sprint's second PR branch after the
closing act's fix batches), as the operator would: German first, English
spot-checked, light and dark, at 1200 × 900, 834 × 1112, 393 × 852 and
844 × 390. Every figure is from the synthetic review seed
(`priv/demo/finding_surfaces_seed.exs`); nothing describes a real person or
portfolio.

**No real phone was at hand in this environment.** Every compact
measurement below is a 393 px window in a desktop browser engine at device
scale 2, not a handset; Sprint 31's carry-forward 1 (the compact type on a
phone) stays open.

## How the walk ran

- A fresh development database, migrated and seeded with the review seed as
  `priv/demo/README.md` says (`PORTFOLIXIR_BACKGROUND_FETCH=off`), then
  `mix phx.server` on a loopback port with the same switch and a throwaway
  UI password. Nothing was fetched; the browser aborted every request to
  another origin (none was attempted).
- The browser: Playwright 1.63's `chromium-headless-shell`, device scale 2,
  time zone UTC. The app's day was Thursday 26.11.2026 for the whole walk.
- The API reads used a bearer token made for the walk and read from the
  server's environment; it is in no file here. Its writes are journaled as
  "Agent".
- **The starters, before and after.** The boot stored them: the seed's own
  `mix run` was the first start of the release on the empty database, and
  its boot step stored „Überblick“ and the four starters (journal entries
  65 to 74, `system_job`, one `dashboard` and one `dashboard_seed` entry
  each) before the seed wrote its data. The server's three later boots ran
  the step again and stored nothing. After the walk, with the server
  stopped, `Portfolixir.Dashboards.Starters.seed/0` called directly
  answered `{:ok, %{stored: [], counted: []}}`.
- What the walk wrote, all journaled (screenshot 28): the own period
  „Seit Juni“ (01.06.2026 until today, in the quick choice), the quick
  choice changed twice (★ „Seit Juni“ off, ★ 3M on), the own period
  „Herbst“ created, edited and deleted, a pin on Überblick, one edit of
  Bestände, the Snapshots starter deleted through the API, „Krypto Lover“
  and „Rücksetzer“ from the gallery, one agent `PUT` with `arrange: "push"`.
  The database was a throwaway; nothing was undone.

## Steps and what they showed

1. **Starters** (01, 02). The menu reads Dashboards: Überblick, Bestände,
   Allokation & Ziele, Snapshots, Risiko, „Neues Dashboard“; Entdecken:
   Vermögen, Wertpapiere, Nachrichten, Alle Widgets. Wealth's tab bar leads
   Bestände, Allokation & Ziele, Snapshots and Risiko to `/dashboards/2`,
   `3`, `4`, `5`, and Cashflow, Steuern, Prognosen to their pages. Stored
   names stay English („Holdings“) and every German screen shows the
   template's title. **Delete and restart:** the Snapshots starter was
   deleted with `DELETE /api/v1/dashboards/4` (its dry run named only
   dashboard 4), the server stopped by its pid and started again: the boot
   took the starters' lock, stored nothing, and the seed table still lists
   `snapshots`; Wealth's Snapshots tab now leads to `/snapshots` (02).
   **No screen deletes a dashboard** (finding 1). **A read never writes:**
   between the seed (journal at 428) and the walk's first write, every
   dashboard, every Wealth tab and every API read above wrote nothing; each
   later entry is one of the walk's writes.
2. **Every section widget against its route and its tab** at 1J, YTD,
   Vorjahr, „Seit Juni“ and Max: see the tables. Bestände's six sections,
   Allokation & Ziele's two and Risiko's six stand in their tab's order;
   Snapshots' two too, with the tab's write actions left on the page
   („Neuer Snapshot →“). The Risk tab's „Crash-Fenster · 1 erkannt · 1
   manuell“ list has no place in the widget (finding 5; 16, 17).
   **Every period key resolves the same on every route:** `prev_year`,
   `saved:1`, `mtd`, `q3`, `prev_quarter` and `year:2024` against their
   `from`/`to` on `/performance`, `/performance/contribution`,
   `/performance/bands`, `/performance/benchmark`, `/views/1/performance`
   and the three portfolio routes: 48 of 48 answers equal; `q4` (begun)
   answers 01.10.–31.12.2026.
3. **The others make room** on Bestände at 1200 px (10 to 12): Kennzahlen
   Zeile → M said „Kennzahlen ist jetzt M · Spalte 1, Zeile 1 · 5 Widgets
   sind nachgerückt“ at the widget, with „Rückgängig“, which restored the
   Zeile („Letzter Schritt rückgängig gemacht“); Verrechnungskonten → S at
   the page's foot said it under the widget, in the viewport (11), and
   Ctrl+Z took it back; ↑ on Verrechnungskonten' handle moved it above
   Positionen („nach oben verschoben, Spalte 1, Zeile 5 · 1 Widget ist
   nachgerückt“); the catalogue added Klumpenrisiko S beside Kennzahlen S
   („hinzugefügt, Spalte 4, Zeile 1, Größe S“); Ctrl+Z removed it. No edit
   message reached the top flash. „Fertig“ wrote one journal entry, the
   stored layout without a gap. **The API stays strict:** a `PUT` on
   „Rücksetzer“ with two overlapping Tops und Flops was refused with 422
   (`overlap`, items 3 and 4); the same body with `arrange: "push"` and
   `arranged_index: 3` was stored, the other Tops und Flops and the
   Erholer pushed down (`lock_version` 2).
4. **Periods** (05 to 09). The quick choice `1w mtd ytd 1y max` and one
   button „Zeitraum ▾“; the menu's four groups Rollierend · bis heute,
   Kalender (Q1 26 to Q4 26, Vorjahr), Eigene · gespeichert, Jahr (2026 to
   2021). An own period with `from` after `to` was refused at the field
   („muss am oder nach dem ersten Tag liegen“, 07); „Seit Juni“ stored,
   applied (`?period=saved:1`, „Seit Juni ▾ 01.06.2026 – 26.11.2026“) and
   added to the quick choice; a seventh ★ was refused („Die Schnellwahl
   hält höchstens 6 Zeiträume.“). **Pin by reference:** Überblick's
   „Wertentwicklung nach Kategorien“ pinned through ⋯ → „Zeitraum
   festpinnen“ to „Herbst“ (01.10.2026, „📌 eigener: Herbst“, 08); „Herbst“
   edited to 01.09.2026 and the pinned widget followed (TTWROR −0,7 % →
   +0,6 %); deleted after the confirm („Widgets, die auf ihn festgepinnt
   sind, folgen dann dem Zeitraum des Dashboards.“), the widget read the
   bar's 1J and said „eigener Zeitraum gelöscht · folgt 1J“ in its footer
   (09). `GET /api/v1/periods` and `/periods/quick` answered each state.
5. **The gallery** (13 to 15): „Leer beginnen“, the five starters („wie der
   Tab in Vermögen heute“, with the counts and names) and the themes
   „Krypto Lover“ and „Rücksetzer“. A taken name is suggested as „Bestände
   (2)“. „Krypto Lover“ asked for a view („Keine: folgt der Ansicht in der
   Leiste“, „Nur Neuzugang“, „Ohne Krypto“); stored with „Nur Neuzugang“,
   the bar reads „Nur Neuzugang · Ansicht dieses Dashboards“ and its five
   widgets read that view (Bitcoin-Zyklus XL draws the cycle chart).
   „Rücksetzer“ asked for no view and holds Crash-Chart XL at 1J, Crash-Chart
   L pinned to 1M, Crashes im Vergleich L (the running fall first), Tops und
   Flops pinned to 1W and 1M, Erholer nach Crashes XL. Both are in the menu.
6. **One look** (18 to 27): see "The look and the type" below.
7. **The docs' widget catalogue**: `docs/guides/widgets.md` and
   `docs/de/guides/widgets.md` each name 29 kinds, the registry's 29, with
   the registry's sizes (`full` aside, which is no family), and each of
   their 100 picture references exists under `docs/assets/widgets/`. The
   pictures were made on this day's seed: „Key figures“ Zeile reads Start
   2025-11-26 76,617.17 + 4,341.20 + 7,348.65 = 88,307.02, Crash-Chart XL
   87.95 / 84.22 / 95.35 / 87.21 and „running −11.5%“, both as the app
   draws them in English at 1J.

## Figures compared

Read from the screen at 1200 px in German, then the API with the same
scope (Alles, no view) and period, and Wealth's tab with the same period
(`?period=` or `from`/`to`); percentages rounded half-up to one place,
amounts to the cent. **298 figures against the API, all equal; 80 against
the Wealth tab, all equal.** The value of the total is `GET /valuation`:
`total_with_cash` 88307.0155 → 88.307,02 EUR, `total_cash` 19.178,75,
`cash_quote` 21,7 %; Wertpapiere 69.128,26.

### Kennzahlen (Bestände) per period, `GET /performance?period=…`

| Period | Window | Anfang + Nettoflüsse + Ergebnis = Ende | TTWROR | IRR / MWR | Multiplikator | Adds up? |
|---|---|---|---|---|---|---|
| 1J | 26.11.2025–26.11.2026 | 76.617,17 + 4.341,20 + 7.348,65 = heute 88.307,02 | +8,0 % / 0.079944 | IRR +9,4 % / 0.094318 | ×1,09 / 1.0908 | yes |
| YTD | 01.01.–26.11.2026 | 77.651,97 + 4.341,20 + 6.313,84 = heute 88.307,02 | +6,5 % / 0.064867 | MWR +8,0 % / 0.079823 | ×1,08 / 1.077 | **no: „⚠ Rundungsdifferenz +0,01“** |
| Vorjahr | 01.01.–31.12.2025 | 47.563,50 + 23.640,00 + 6.448,47 = **am 31.12.2025** 77.651,97 | +3,3 % / 0.033010 | IRR +9,6 % / 0.095537 | ×1,09 / 1.0906 | yes |
| Seit Juni (`saved:1`) | 01.06.–26.11.2026 | 82.018,25 + 2.341,20 + 3.947,56 = heute 88.307,02 | +3,4 % / 0.033638 | MWR +4,8 % / 0.047857 | ×1,05 / 1.0468 | **no: „⚠ Rundungsdifferenz +0,01“** |
| Max | 02.01.2023–26.11.2026 | 0,00 + 77.981,20 + 10.325,82 = heute 88.307,02 | +7,3 % / 0.073304 | IRR +4,1 % / 0.041212 | ×1,13 / 1.1324 | yes |

Each figure equals the API's (start 77651.973, flows 4341.2, end
88307.0155 at YTD; the Ergebnis is `/performance/contribution`'s
`totals.result` 6313.8425). The gap is the cents of three rounded figures,
not a wrong one (finding 2). Wertentwicklung (Zeile) reads the same TTWROR
and Ergebnis at every period; Beitrag je Position's „Summe = Ergebnis im
Zeitraum“ equals `totals.result` at every period and the tab's row in all
six columns (1J 63.341,58 · +925,20 · +412,50 · 32,90 · 69.128,26 ·
+7.348,65). Wealth's tab reads the same total, split, TTWROR, IRR/MWR,
Anfangswert, Nettoflüsse and multiplier at all five periods.

### Überblick's Gesamtwert and Wertentwicklung nach Kategorien (`/performance/bands?level=category`)

| Period | Gesamtwert S | Band value · share · change: Crypto · Stability · Growth · Nicht zugeordnet · Cash |
|---|---|---|
| 1J | 88.307,02, +8,0 % | 2.569,68 · 2,9 · +12,3 / 7.011,60 · 7,9 · +14,2 / 26.320,60 · 29,8 · +11,0 / 33.226,39 · 37,6 · +3,8 / 19.178,75 · 21,7 · +18,7 |
| YTD | +6,5 % | changes +10,8 · +10,6 · +7,0 · +4,0 · +18,7 (values as 1J) |
| Vorjahr | +3,3 % | 2.319,55 · 3,0 · −22,7 / 5.506,20 · 7,1 · −8,2 / 24.596,30 · 31,7 · −6,1 / 31.954,33 · 41,2 · +173,0 / 13.275,59 · 17,1 · +0,1 („Die Bänder am 31.12.2025“) |
| Seit Juni | +3,4 % | changes +4,3 · −5,4 · +2,9 · +3,9 · +16,4 |
| Max | +7,3 % | every change „—“ (`change: null`) |
| pinned „Herbst“ 01.10. / 01.09. | — | TTWROR −0,7 % / +0,6 %; changes +3,8 · −9,1 · 0,0 · +0,2 · −0,1 / +5,8 · −5,2 · +2,6 · +1,5 · −0,1 |

### The other section widgets

| Widget | Screen | API |
|---|---|---|
| Kennzahlen-Zeile (Allokation & Ziele) | 88.307,02 EUR · Cashquote 21,7 % · TTWROR 1J +8,0 % | as above |
| Allokation | Allokiert 75.035,12; Stability 9,3 % · 7.011,60; Growth 35,1 % · 26.320,60; Crypto 3,4 % · 2.569,68; Nicht zugeordnet 30,6 % · 22.956,59; Cash 21,6 % · 16.176,65; Σ Soll 105,0 % | `/portfolios/1/allocation?classification_id=3`: `total_value` 75035.1155, the weights and values, `top_level_target_sum` 1.05 |
| Vergleich gegen einen Snapshot | Real +0,7 %; Eingefroren +1,1 %, 47.301,57 → 47.834,43; vor Kosten +0,7 %; Kosten 4,90 | `/portfolios/1/snapshots/1/comparison`: 0.007252, 0.011265, 47301.565 → 47834.426, 0.007317, 4.9 |
| Kennzahlen des Portfolios | Volatilität 4,1 %, 365 Beob.; Max. Rückgang −1,9 % 28.06. → 09.07.2026; Risikoadj. 1,92; Korrelationen 52 von 60 | `/portfolios/1/risk` `metrics` 365d: 0.041237, −0.018663, 1.916507, 52/60 |
| Größte Einzelpositionen, Klumpenrisiko | ten rows, Apple 9.443,50 · 16,0 % … Microsoft 2.345,20 · 4,0 %; HHI 920 niedrig | `top_holdings` (20 figures), `hhi` 919.80 `low` |
| Crashes (Zeile) | Synthetic dip 17.10. → 06.11.2026: Allianz −3,1 % … Bitcoin +6,3 % | as the tab, `GET /crashes/m:1/rankings` |
| Positionen, Verrechnungskonten | 34 rows of the Demo Depot's portfolio; 20 accounts, the USD ones „kein Wechselkurs“ | `/portfolios/1/holdings` quantities; `/cash_accounts` balances |
| Krypto Lover (view „Nur Neuzugang“) | Wertentwicklung −1,2 %, Wert 240,00; Abstand zum Hoch: Kestrel Industrial, größter Rückgang −1,2 % | `/views/2/performance?period=1y` −0.012346, 240; `/securities/11/metrics` −0.012346 |
| Rücksetzer | Crash-Chart XL 27.11.2025: 87,95 · Tief 84,22 · Hoch 95,35 · 26.11.2026: 87,21, läuft −11,5 %; L 1M 84,37 / 87,21; Tops und Flops 1W Apple +1,4, NVIDIA +1,1, Alpine +1,1, Vanguard +1,0 / Allianz −1,4, iShares −0,7; 1M Microsoft +5,3, Vanguard +3,4, Bitcoin +1,2, NVIDIA +0,6 / Allianz −4,8, iShares −1,8, Apple −1,6; Erholer Microsoft +6,7, Bitcoin +3,8, „vollständig am 06.02.2027“ | Vanguard's stored closes; `/crashes` −0.11515; `/movers?window=week|month`; `/crashes/m:1/rankings?list=rebounders` |

## The look and the type

Measured on Überblick, Bestände, Allokation & Ziele, Risiko, Krypto Lover
and Rücksetzer at the four widths, light and dark (the same in both):

- **No sideways page scroll** at any width. **One surface:** every widget
  without a card border or radius, separated by the 1 px hairline
  (`box-shadow: 0 0 0 1px`), the grid one frame.
- **The head on one line** in the wide grid on every widget; in the
  compact forms only „Wertentwicklung nach Kategorien“ takes two lines, not
  cut, as the anatomy allows.
- **No figure cut** in the wide grid. At 834 px Größte Einzelpositionen'
  last column runs past the widget (finding 6), and at 1200 px Crashes im
  Vergleich's column head reads „BENCH…“ (finding 10).
- **No text under 12 px** in the eleven Overview kinds and the themes at
  393 px; the section widgets carry 11 px and 9 px text in the compact
  class (finding 4). At 1200 px the sidebar's group labels are 10,5 px
  and the medium class's subtitle 11 px, as in Sprint 31.
- **Compact** (18 to 21): two S side by side, M, L, XL and Zeile at full
  width; Überblick is 5,2 screens at 393 × 852, Bestände 8,1, Risiko 4,5.
  Gesamtwert's footer line breaks inside words (finding 3).
- **Short-wide** (24, 25): the rail and the switcher; Sprint 31's
  hyphenated rail labels are gone.
- **English** (26, 27): „Key figures“, „Last year“, „on 2025-12-31“, the
  menu's starters in English, the user-named copies as named.

## Screenshots

| # | File | What it shows |
|---|---|---|
| 01 | `01-light-menu-starters-1200.png` | Überblick, the menu with the four starters |
| 02 | `02-light-wealth-tab-bar-1200.png` | Wealth's tab bar after the Snapshots starter's delete |
| 03 | `03-light-bestaende-1j-1200.png` | Bestände at 1J: Kennzahlen A, Datenhinweise, Wertentwicklung |
| 04 | `04-light-kennzahlen-vorjahr-1200.png` | Kennzahlen at Vorjahr, „am 31.12.2025“ |
| 05 | `05-light-own-period-rounding-gap-1200.png` | „Seit Juni“ applied; the bridge's rounding gap; the top bar on two lines (findings 2, 7) |
| 06 | `06-light-period-menu-1200.png` | The period menu's four groups and ★ |
| 07 | `07-light-period-dialog-refusal-1200.png` | „Eigener Zeitraum“, the refusal at the field; ISO dates (finding 9) |
| 08 | `08-light-pin-own-period-1200.png` | „📌 eigener: Herbst“ |
| 09 | `09-light-pin-dangling-1200.png` | After the delete: „eigener Zeitraum gelöscht · folgt 1J“ |
| 10 | `10-light-edit-resize-note-1200.png` | Kennzahlen → M, the note at the widget with „Rückgängig“ |
| 11 | `11-light-edit-note-at-foot-1200.png` | A resize at the page's foot, its note in view; the S footer „A..“ (finding 8) |
| 12 | `12-light-edit-add-catalogue-1200.png` | Klumpenrisiko added; the drawer over „Rückgängig“, „row“ (finding 8); the edit bar with no delete (finding 1) |
| 13 | `13-light-gallery-1200.png` | „Neues Dashboard“: Leer, the starters, the themes |
| 14 | `14-light-krypto-lover-1200.png` | „Krypto Lover“ on „Nur Neuzugang“ |
| 15 | `15-dark-ruecksetzer-1200.png` | „Rücksetzer“ in dark; „BENCH…“ (finding 10) |
| 16 | `16-light-risk-tab-crash-windows-1200.png` | The Risk tab's „Crash-Fenster · 1 erkannt · 1 manuell“ |
| 17 | `17-light-risk-widget-crashes-1200.png` | The Crashes widget without it (finding 5) |
| 18 | `18-light-compact-overview-393.png` | Compact Überblick; Gesamtwert's footer broken in words (finding 3) |
| 19 | `19-light-compact-risk-small-type-393.png` | Compact Risiko, 11 px heads and badges (finding 4) |
| 20 | `20-light-compact-allocation-393.png` | Compact Allokation, 11 px in the sunburst (finding 4) |
| 21 | `21-dark-compact-bestaende-393.png` | Compact Bestände in dark; a lone S at half width (finding 11) |
| 22 | `22-light-medium-risk-table-cut-834.png` | 834 px: Größte Einzelpositionen' last column cut (finding 6) |
| 23 | `23-dark-medium-overview-834.png` | 834 px in dark, YTD |
| 24 | `24-light-short-wide-844x390.png` | 844 × 390: the rail, Bestände |
| 25 | `25-dark-short-wide-844x390.png` | 844 × 390 in dark, Überblick |
| 26 | `26-light-english-1200.png` | English spot check, Bestände at „Last year“ |
| 27 | `27-light-english-compact-393.png` | English at 393 px, the compact Key figures |
| 28 | `28-light-journal-1200.png` | The journal: periods, the quick choice, the pin, the copies |

## Findings

Ranked; "introduced" means by this sprint's diff, "older" before it.

1. **S2, older, made sharp by this sprint. No screen deletes or renames a
   dashboard.** The boot now stores five dashboards and the gallery adds
   copies, but neither the menu, the ⋯ menu nor the edit bar („Widget
   hinzufügen“, „Zurücksetzen“, „Fertig“) offers a delete or a rename
   (screenshot 12); the walk deleted the Snapshots starter through
   `DELETE /api/v1/dashboards/4`. ADR-0062's amendment, point 5, calls a
   starter "renamed, changed, reordered, deleted" like any dashboard; on a
   screen the operator can only change it. Smallest fix: „Umbenennen“ and
   „Dashboard löschen …“ (with the API's dry-run sentence as the confirm)
   in the edit bar, calling the context's existing functions.
2. **S3, introduced. The Kennzahlen bridge does not add up to the cent at
   YTD and „Seit Juni“:** 77.651,97 + 4.341,20 + 6.313,84 = 88.307,01
   against 88.307,02, and the widget says „⚠ Rundungsdifferenz +0,01“
   (screenshot 05). Every figure equals its read; the cent is three
   roundings. The plan's W1 asks the bridge to add up to the cent, so this
   check fails. Smallest fix: a decision on which figure carries the cent
   (for example the Ergebnis as rounded end − rounded start − rounded
   flows, said in the ⓘ, at the price of a cent against Wealth's
   „im Zeitraum“), or the criterion amended to the gap line.
3. **S3, introduced. Gesamtwert's compact form breaks its footer inside
   words** at 393 px: „Nicht in der Summe: 3 Verrech|nungsko|nten, …
   Position|en ohne Wechsel|kurs.“ in a column about 100 px wide beside
   „Details →“ (screenshot 18). Smallest fix: the warning line at the
   tile's full width, the link under it, no break inside a word.
4. **S3, introduced. The section widgets bring text under 12 px into the
   compact class:** at 393 px Risiko 36 text nodes at 11 px (table heads,
   badges), Allokation 8 (the sunburst's centre, the „▸“ toggles,
   „Unterkategorien“), Bestände three 11 px badges and seven 9 px chart
   axis labels (screenshots 19, 20). The eleven Overview kinds and the
   themes have none. Smallest fix: the compact class's 12 px floor applied
   to the moved sections' tables, badges and axes.
5. **S3, introduced. Risiko's „Crashes“ widget leaves out the tab's
   „Crash-Fenster · 1 erkannt · 1 manuell“ list** (the windows with high,
   low, decline, recovery and gap), so the starter shows less than the tab
   it stands for (screenshots 16, 17). Smallest fix: the disclosure,
   read-only, with „Fenster bearbeiten →“ to the tab.
6. **S3, introduced. At 834 px Größte Einzelpositionen' table is wider
   than its widget:** „ALLGEMEINE SCHWEL…“ is cut at the right edge
   (screenshot 22). Smallest fix: the table's wrapper scrolls, or the
   medium class drops a column.
7. **S3, introduced. With an own period active the top bar takes two
   lines at 1200 px:** the chips, „Seit Juni ▾“, its dates and the status
   „„Seit Juni“ ist gespeichert und angewendet.“ push „Bearbeiten“ under
   them, and Kennzahlen' „+3.947,56“ puts its „EUR“ on its own line
   (screenshot 05). Smallest fix: the status as the menu's own line, not in
   the bar.
8. **S3, introduced. The edit mode:** the catalogue names the size „row“
   in German where the widget's switch says „Zeile“; at 1200 px the open
   drawer covers the note's „Rückgängig“ (screenshot 12); an S widget's
   footer cuts „Ansicht Alles“ to „A..“ beside its size switch (11, 12);
   Kennzahlen S ends „Cash 19.178,75 ·“ with the cash quote dropped (12);
   Ctrl+Z after an add leaves no note anywhere, since it stood at the
   removed widget.
9. **S3, introduced. The own-period dialog asks for „2026-06-01“** in a
   German screen that writes 01.06.2026 everywhere else (screenshot 07).
10. **S3, introduced. Crashes im Vergleich L cuts its column head to
    „BENCH…“** at 1200 px (screenshot 15); the figures under it are whole.
11. **S3, introduced. A lone S widget in the compact class takes half the
    width** and leaves the other half empty (Bestände after Kennzahlen →
    S; screenshot 21, and „TTWROR · Last y…“ cut in 27).

No S1: no figure or stored record was wrong, and nothing contradicted
between the dashboards, the Wealth tabs and the API. Seen and as designed,
not defects: Tops und Flops translates „Vorjahr“ and Max to „→ 1J“ and
„Seit Juni“ to „→ Quartal“, and says so; Crashes im Vergleich reads every
held security whatever the dashboard's view (its catalogue entry has no
scope) and names the benchmark in its footer; a dangling pin stays stored
until the next save; a starter the operator deleted is still offered in
the gallery. Not walked: the MCP companion.
