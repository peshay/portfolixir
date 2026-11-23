# Sprint 31 UAT persona on the review seed, every width class (2026-11-23)

The closing act's last bullet of the Sprint 31 plan
(`sprint-plan-2026-11-21-sprint31.md`, D-1 criterion 4 and D-8: "the UAT
persona on the review seed at the end, in every width class, and on a real
phone if one is at hand"), walked on head `2488030` of the sprint's second
PR branch, as the operator would: German first, English spot-checked, light
and dark, at 1200 × 900, 834 × 1112, 760 × 580, 440 × 956, 393 × 852,
375 × 667 and 844 × 390. Every figure is from the synthetic review seed
(`priv/demo/finding_surfaces_seed.exs`); nothing describes a real person or
portfolio.

**No real phone was at hand in this environment.** Every compact
measurement below is a 375, 393 or 440 px window in a desktop browser
engine at device scale 2, not a handset; D-1 criterion 4's phone check is
still open.

## How the walk ran

- A fresh development database, migrated and seeded with the review seed as
  `priv/demo/README.md` says, then `mix phx.server` on a loopback port with
  `PORTFOLIXIR_BACKGROUND_FETCH=off` and a throwaway UI password. Nothing
  was fetched; the browser aborted every request to another origin.
- The browser: Playwright 1.65.1's `chromium-headless-shell` (Chromium
  159), CI's browser, device scale 2, time zone UTC. The app's day was
  Monday 23.11.2026 for the whole walk.
- The API reads used a bearer token from the server's environment, made for
  the walk; it is in no file here. Its writes are journaled as "Agent".
- **Lane Z's legacy row:** before the server started, one close of **0.00**
  was inserted directly into `security_quotes` for Allianz SE (security 3,
  held, 60 shares) on Friday 20.11.2026, between the seed's weekly closes
  118.52 (16.11.) and 116.86 (23.11.), and a global basis bump was queued.
  This is the sharpest place for it: it is the close before today's for
  „1T“ and inside „1W“, „1M“ and the Wealth chart's last week.
- What the walk wrote, all journaled (screenshot 13): „Überblick“ stored by
  „Anpassen“ (id 1) and edited, a period pinned on its Tops und Flops, two
  agent `PUT`s for the stale saves, „Leer-Test“ (empty) and
  „Vorlagen-Kopie“ (from the template) through „Neues Dashboard“, and the
  agent's „Agent: Risiko-Blick“ through `POST` and `PUT`. The database was
  a throwaway; nothing was undone.

## Steps and what they showed

1. **A fresh instance** (screenshots 01, 02): `/` draws „Überblick“ as
   „Vorlage · mitgeliefert, nur lesend“ with „Anpassen“; the menu marks it
   „Vorlage“. After `/` had been read at all eight periods, in seven widths
   and both themes, `GET /api/v1/dashboards` still answered the template
   alone (`id: null, type: template`), the `dashboards` table was empty and
   the journal held no dashboard entry. **A read stored nothing.**
2. **„Anpassen“** (03): one `create` journal entry, `/dashboards/1`, and
   `GET /api/v1/dashboards` lists „Überblick“ (`lock_version` 1) and the
   template, no longer `in_menu`. The menu: Dashboards (stored ones,
   „Neues Dashboard“), Entdecken (Vermögen, Wertpapiere, Nachrichten, „Alle
   Widgets“), Pflege at the foot. Compact (25 to 27): the tab bar
   Dashboards · Wertpapiere · Nachrichten · Mehr, the title „Überblick ▾“
   switching dashboards, „Mehr“ a sheet above the bar. Short-wide (30 to
   32): the rail at the side, „Mehr“ beside it (findings 1 and 2).
3. **Every widget against its route**, at 1J, then 1T, 1W, 1M, 3M, YTD, 3J
   and Max, and with Tops und Flops pinned to 1W („📌 eigener: 1W → Woche“,
   07, 08): see the tables. The period is carried in the address
   (`?period=1d`) and kept from `/dashboards/1` to `/` (`period=max`
   carried). The pin is one journal entry; switching the dashboard's period
   afterwards left the pinned widget on its week while Gesamtwert and
   Wertentwicklung followed (1T, 3M, Max).
4. **The edit mode** at 1200 px (09 to 12): the arrow keys move a widget
   one step and say so („Snapshots nach rechts verschoben, Spalte 2, Zeile
   9“), and refuse with the reason („Wertentwicklung kann nicht nach
   rechts: Es würde „Allokation und Drift“ überdecken.“); a drag of Crashes'
   handle below the grid places it („an Spalte 7, Zeile 10 gesetzt“); the
   size switch (Crashes M → L); × and the Delete key remove; the catalogue
   is a drawer at 1200 px and adds at the first free place („Snapshots
   hinzugefügt, Spalte 1, Zeile 9, Größe S“); „Zurücksetzen“ restores every
   place („Ungespeicherte Änderungen verworfen.“); „Fertig“ after three
   changes wrote **one** journal entry (`update`, `lock_version` 1 → 2).
   **Stale save:** with a local move pending, the agent removed a widget
   through `PUT /api/v1/dashboards/1`; „Fertig“ then said „Dieses Dashboard
   wurde anderswo geändert … Nichts wurde gespeichert“ and drew the stored
   layout beside the edit (12). „Weiter bearbeiten“ then „Fertig“ saved the
   local layout over it, as its line says; on a second round „Gespeicherte
   Fassung laden“ showed the agent's layout and left the edit mode. Journal:
   operator and agent entries alternate, one per save (13). **Compact** (28):
   ↑ ↓, the size switch and × only, no handle and no catalogue; each step
   said; „Zurücksetzen“ discards.
5. **„Alle Widgets“** (14): the slice's eleven kinds with „hinzufügen ›“ and
   the later passes' kinds dashed („kommt mit dem Umbau seines Screens“);
   „hinzufügen ›“ → „Überblick“ added Verkaufsrückblick at its free place
   („wurde zu Überblick hinzugefügt. Öffnen“). **„Neues Dashboard“** (15,
   16): „Leer beginnen“ opens the empty dashboard in the edit mode with the
   catalogue open; „Aus Vorlage“ copies the template's eleven widgets. **An
   agent's dashboard** (17, 18): `POST` then `PUT /api/v1/dashboards/4`
   („Agent: Risiko-Blick“, Crashes L, Gesamtwert S, Tops und Flops M pinned
   to 1M) appears in the menu, in the compact switcher (27) and draws its
   pin („📌 eigener: 1M → Monat“). An overlapping layout was refused with
   422 naming the item and the overlap.
6. **Lane Z** (33 to 35): see its table. Every read agrees and nothing
   values Allianz at 0, except the security's own price chart (finding 4).
7. **The compact type** (21 to 24, 25 to 29): see "The type" below.

## Figures compared

All figures read from the screen at 1200 px in German, then the API with the
same scope (Everything, no view) and period; percentages rounded half-up to
one place, amounts to the cent. **Every figure the widgets showed matched
the API.**

### Gesamtwert and Wertentwicklung (S/M/L) per period

The total is `GET /valuation` (`total_with_cash` 88307.0155 → 88.307,02 EUR,
`cash_quote` → 21,7 %, `total_cash` → 19.178,75 EUR, `newest_quote_date`
23.11.2026, 19 held stale quotes); the change is `GET /performance` with the
catalogue's parameters (`period=` for YTD, 1J, 3J, Max; `from`/`to` ending
today for the short ones), the bands `GET /performance/bands?level=category`
with the same. Band values and shares are equal at every period: Crypto
2.569,68 · 2,9 %, Stability 7.011,60 · 7,9 %, Growth 26.320,60 · 29,8 %,
Nicht zugeordnet 33.226,39 · 37,6 %, Cash 19.178,75 · 21,7 %.

| Period | Window (API) | TTWROR screen / API | Band change Crypto · Stability · Growth · Nicht zugeordnet · Cash |
|---|---|---|---|
| 1T | 23.11.–23.11.2026 (one day, from 22.11.'s close) | +0,1 % / 0.000757 | +0,8 · −1,4 · +0,5 · 0,0 · 0,0 |
| 1W | 17.11.–23.11.2026 | +0,1 % / 0.001047 | +0,8 · −1,4 · +0,5 · +0,1 · 0,0 |
| 1M | 24.10.–23.11.2026 | −0,2 % / −0.002463 | +3,8 · −5,6 · +0,3 · +0,1 · −0,1 |
| 3M | 24.08.–23.11.2026 | +0,5 % / 0.005023 | +4,1 · −3,1 · +1,9 · +1,4 · −0,1 |
| YTD | 01.01.–23.11.2026 | +6,2 % / 0.061931 | +9,0 · +9,5 · +6,5 · +4,0 · +18,7 |
| 1J | 23.11.2025–23.11.2026 | +8,0 % / 0.079949 | +12,3 · +14,2 · +11,0 · +3,8 · +18,7 |
| 3J | 23.11.2023–23.11.2026 | +10,2 % / 0.101999 | −14,3 · +1,5 · +0,5 · — · +21,3 |
| Max | 02.01.2023–23.11.2026 | +7,3 % / 0.073309 | — · — · — · — · — (every start value 0, `change: null`) |

IRR at 1J: +9,4 % / `irr` 0.094318; at 1T the compact form reads „MWR —“,
the API `irr: null`. **1T is one day's return**: from = to = today, its
baseline the close before (the Stability band 7.111,20 → 7.011,60, Allianz's
16.11. close carried over 20.11. to its 23.11. close).

### Tops und Flops per window (`GET /movers?window=…&include_unanswered=true`)

| Dashboard period → window | Header dates | Price return, highest / lowest (screen = API) | Contribution, highest / lowest (screen = API) | Counts (screen = API) |
|---|---|---|---|---|
| 1T → Tag | each row's own dates (Mo 16.11. → Mo 23.11.; Kestrel So 22.11. → Mo 23.11.); Beitrag am 23.11. | Apple +1,4, NVIDIA +1,1, Vanguard +1,0, Bitcoin +0,8 / Allianz −1,4, iShares −0,7, Kestrel Ind. −0,4, Microsoft +0,2 | Apple +132,50, Vanguard +34,40, NVIDIA +26,30, Bitcoin +19,17 / Allianz −99,60, iShares −61,20, Kestrel Ind. −1,00, Microsoft +5,70 | 27 ohne Kursrendite: 19 ohne aktuellen Kurs, 8 mit nur einem Schlusskurs; 3 an keinem Tag bewertet; 23 ohne Beitrag |
| 1W → Woche | Schlusskurs 22.11. bis 23.11.2026 | as Tag, the 4th lowest Birkenhain 0,0 („letzter Kurs 22.11.2026“); API's 5th rows hidden (finding 7) | as Tag | 23 ohne Kurs zu Beginn; 3; 23 |
| 1M → Monat | 31.10. bis 23.11.2026 | Microsoft +5,3, Vanguard +3,4, Bitcoin +1,2, NVIDIA +0,6 / Allianz −4,8, iShares −1,8, Apple −1,6 | Microsoft +117,80, Vanguard +113,60, Bitcoin +30,30, NVIDIA +15,40 / Allianz −352,80, iShares −154,80, Apple −139,00, Birkenhain +0,03 | 28 ohne Kurs zu Beginn; 3; 20 |
| 3M → Quartal | 30.09. bis 23.11.2026 | Microsoft +7,9, Bitcoin +5,5, Apple +5,2, NVIDIA +5,1 / iShares −7,6, Allianz −7,1, Vanguard +1,3 | Apple +476,50, Microsoft +172,10, Bitcoin +134,44, NVIDIA +116,80 / iShares −711,60, Allianz −537,00, Nordic Timber −74,70, Birkenhain +0,03 | 27 + 1; 3; 19 |
| YTD | 31.12.2025 bis 23.11.2026 | Allianz +26,1, Apple +17,9, NVIDIA +17,3, Microsoft +14,3 / iShares −5,1, Vanguard −0,4, Bitcoin +9,0 | Allianz +1.450,20, Apple +1.448,00, Larkspur Rail +525,00, Wrenfield „verkauft“ +420,00 / iShares −463,20, Tamarisk Mining „verkauft“ −400,00, Vanguard −15,60, Birkenhain +0,03 | 26 + 2; 3; 17 |
| 1J, and 3J → 1J, Max → 1J | 23.11.2025 bis 23.11.2026 | Allianz +31,4, Apple +25,3, NVIDIA +19,9, Microsoft +17,1 / iShares −0,6, Vanguard +0,3, Bitcoin +12,3 | Apple +1.916,50, Allianz +1.675,80, Larkspur Rail +475,00, Wrenfield +420,00 / Tamarisk Mining −400,00, iShares −48,00, Birkenhain +0,03, Alpine +5,63 | 27 + 1; 3; 17 |

The pinned widget (1W) read the week's figures at every dashboard period.

### The other widgets

| Widget | Screen | API |
|---|---|---|
| Datenqualität (S; compact form) | 3 Anleihen auf zwei Preisskalen, 1 Kursreihe gegen ihre Buchungen, 19 Kurse älter als 7 Tage, +2 weitere (1 ohne Anlageklasse, 35 ohne Logo) | `GET /securities?data_quality=…&holding_status=held`: two_scales 3, implausible_quote 1, stale_quote 19, missing_logo 35, asset class unset 1; the three ledger checks 0 rows each |
| Fällig | 28.11.2026 Helios Solar Systems SE ○, 02.12.2026 Apple, +1 weiterer | `GET /events/upcoming` (30 days): 28.11. lockup window unconfirmed, 02.12. earnings, 16.12. ex-dividend |
| Abseits des Ziels | 5 Kategorien außerhalb ±5 pp, Plan „Plan“ auf Strategies; compact: Growth −29,9, Global Core −18,8, Platforms −11,1, Stability −5,7, Quality −5,7 pp with their amounts | `GET /portfolios/1/allocation?classification_id=3`: drift −29.92, −18.83, −11.09, −5.66, −5.66 pp |
| Allokation und Drift (T) | Stability 9,3 / 15,0 / −5,7 pp; Growth 35,1 / 65,0 / −29,9; Crypto 3,4 / 5,0 / −1,6; Cash 21,6 / 20,0 / +1,6; zum Soll Stability ≈ +4.243,67, Quality ≈ +4.243,67, Growth ≈ +22.452,23, Global Core ≈ +14.131,49, Platforms ≈ +8.320,73 EUR; „5 bei ±5 pp oder mehr“ | the same read: equal, each amount the negated `drift_value` |
| Crashes im Vergleich (Im Depot · Katalog) | Synthetic dip 14.10.→03.11.2026, Benchmark −2,4 %, Allianz −3,1 % / Katalog Sable Point Energy ASA −3,7 %; ohne Namen 29.06.→26.10.2026 andauernd, −11,5 %, iShares −4,0 % in both | `GET /crashes`, `GET /crashes/:key/rankings?list=losers&universe=held|catalogue` for `m:1` and `d:5:2026-06-29`: equal |
| Bitcoin-Zyklus (Ferncoin) | Nächstes Tief 22.06.2026–25.06.2027, 300,00–382,93 USD, läuft, Top → Tief n = 3 · Tief → Tief n = 2; Nächstes Top 25.08.2027–23.12.2028, 4.500,00–5.599,50 USD, offen, Halving → Top n = 4 · Top → Top n = 3 | `GET /securities/51/cycles`: equal (the halving's n is its time n, 4; its price n is 3) |
| Verkaufsrückblick | Brightwater +30,00 · +7,9 % p. a. · 460 Tage; Tamarisk Mining −400,00 · −100,0 % gesamt · 600; Kestrel Bay +151,00 · +18,7 % gesamt · 80; Wrenfield +420,00 · +17,8 % p. a. · 780; Thornbury −25,00 · −4,5 % gesamt · 91; excluded Harborline (no rate), Arbolia (no leg) | `GET /realized_gains`: the five newest trades and `excluded`, equal |
| Snapshots | 25.08.2026, der einzige, seitdem +0,7 % | `GET /snapshots` (one), `GET /portfolios/1/snapshots/1/comparison`: `real_ttwror` 0.007258 |

### Lane Z: the legacy close of 0 on 20.11.2026 (Allianz)

| Read | Screen | API |
|---|---|---|
| Overview total | 88.307,02 EUR; Stability band 7.011,60 (60 × 116,86) | `/valuation` equal; `/performance/bands` Stability 7.111,20 on 16.–22.11. (60 × 118,52 carried), 7.011,60 on 23.11.; no day at 0 |
| Wealth chart, 1M (35) | TTWROR −0,2 %, −210,64 EUR, the line flat across 20.–22.11. | `/performance` 1M −0.002463 |
| Wealth contribution | 1W: Allianz 7.111,20 → 7.011,60, −99,60; 1M: 7.425,00 → 7.011,60, −413,40 | `/performance/contribution?from=2026-11-17&to=2026-11-23`: start 7111.2, end 7011.6, −99.6 |
| Securities list (33) | Allianz 116,86, Tagesänderung −1,4 % | `/movers?window=day`: 16.11. → 23.11., −0.014006 |
| Security panel | Letzter Kurs 116,86, Tagesänderung −1,4 %, 1J +31,4 %; Max. Drawdown −9,1 %, 52-Wochen-Spanne „−9,1 % zum Hoch · +31,4 % zum Tief“ | the 0 is not the low |
| Tops und Flops 1T | „Mo 16.11.2026 → Mo 23.11.2026 −1,4 %“: the walk skips Friday's 0 | equal |
| Stored quotes | the Kurse tab lists 20.11.2026 0,00 EUR „Manuell“ | `GET /securities/3/quotes` returns the stored row, as it should |

## The type (compact class), and the phone

- **No text under 12 px** in the dashboard at 375, 393 and 440 px, light and
  dark, the tab bar included (every visible text node, an SVG text at its
  drawn size). The type at 393 px: 12 to 13 px for basis lines and tags,
  16 px for a widget's rows (labels and figures), 17 px for its title, 28 px
  for the total; the wide grid uses 13 px rows and 15 px titles. The medium
  and short-wide windows hold one 11 px text, the top bar's subtitle (see
  finding 10); the wide grid's chart axes are 9 px (the floor is the compact
  class's).
- **Does it feel large?** On the 393 px screenshot (22, 25) the rows are at
  the scale of a phone's own system text (16 to 17 px is a handset's body
  size), not oversized: one widget title per line, the total on one line.
  What makes it read large is the density: a long security name takes two
  lines at 16 px („Allianz SE vinkulierte Namens- / Aktien o.N.“), the
  template is 6.6 screens long at 393 × 852 and 8.6 at 375 × 667, and
  Gesamtwert alone fills the first screen. Whether a handset draws it
  larger than the board did stays for a real phone: **none was at hand.**

## Screenshots

| # | File | What it shows |
|---|---|---|
| 01 | `01-light-template-read-only-1200.png` | `/` on a fresh instance: the template, read-only, „Anpassen“ |
| 02 | `02-dark-template-1200.png` | The same in dark; „Gesamtwert“'s title under its ⓘ (finding 9) |
| 03 | `03-light-stored-copy-menu-1200.png` | After „Anpassen“: the stored copy, the menu |
| 04 | `04-light-performance-1t-empty-plot-1200.png` | Wertentwicklung at 1T: an empty plot (finding 5) |
| 05 | `05-light-movers-1t-1200.png` | Tops und Flops at 1T, each row's dates |
| 06 | `06-light-crashes-catalogue-1200.png` | Crashes im Vergleich, „Katalog“ |
| 07 | `07-light-movers-pinned-week-1200.png` | „📌 eigener: 1W → Woche“ |
| 08 | `08-light-period-max-with-pin-1200.png` | Max above the dashboard, the pin kept |
| 09 | `09-light-edit-mode-1200.png` | The edit mode: handles, ×, size switches, „ohne Zeitraum“ |
| 10 | `10-light-edit-moved-resized-1200.png` | After a keyboard move, a drag, a resize and a removal |
| 11 | `11-light-edit-catalogue-drawer-1200.png` | The catalogue drawer over „Zurücksetzen“ and „Fertig“; „bearbeiten“ (finding 8) |
| 12 | `12-light-stale-save-1200.png` | The stale save: the stored layout, „Gespeicherte Fassung laden“, „Weiter bearbeiten“ |
| 13 | `13-light-journal-dashboards-1200.png` | The journal: one entry per save, operator and agent |
| 14 | `14-light-alle-widgets-1200.png` | „Alle Widgets“ with the later kinds dashed |
| 15 | `15-light-neues-dashboard-1200.png` | „Neues Dashboard“: „Leer beginnen“ or „Aus Vorlage“ |
| 16 | `16-light-new-empty-edit-catalogue-1200.png` | The empty dashboard in the edit mode, the catalogue open |
| 17 | `17-light-menu-with-agent-dashboard-1200.png` | The menu with the agent's „Agent: Risiko-Blick“ |
| 18 | `18-light-agent-dashboard-1200.png` | The agent's dashboard, its pin drawn |
| 19 | `19-light-medium-834x1112.png` | Medium, 834 px: two columns |
| 20 | `20-dark-medium-760x580.png` | Medium, 760 × 580, dark |
| 21 | `21-light-compact-440x956.png` | Compact, 440 px |
| 22 | `22-light-compact-template-393x852.png` | Compact, 393 px, the template (the type question) |
| 23 | `23-dark-compact-template-393x852.png` | The same in dark |
| 24 | `24-light-compact-375x667.png` | Compact, 375 × 667 |
| 25 | `25-light-compact-stored-393.png` | The stored dashboard at 393 px, the tab bar |
| 26 | `26-light-compact-mehr-393.png` | „Mehr“ at 393 px: no „Abmelden“ (finding 1) |
| 27 | `27-light-compact-switcher-393.png` | „Überblick ▾“: the four dashboards and „Neues Dashboard“ |
| 28 | `28-light-compact-edit-crashes-393.png` | The compact edit; Crashes' „Depot −3,1 %“ (finding 3) |
| 29 | `29-light-compact-data-quality-393.png` | Datenqualität's compact form, „eins ohne Anlageklasse“ (finding 11) |
| 30 | `30-light-short-wide-rail-844x390.png` | 844 × 390: the rail, the top bar's subtitle under the title (finding 10) |
| 31 | `31-light-short-wide-mehr-cut-844x390.png` | „Mehr“ at 844 × 390: „Audit-Journal“ cut off (finding 2) |
| 32 | `32-dark-short-wide-844x390.png` | The short-wide window in dark |
| 33 | `33-light-lanez-securities-list-panel-1200.png` | Lane Z: Allianz in the list and its panel, −1,4 % and +31,4 % |
| 34 | `34-light-lanez-allianz-price-chart-1y-1200.png` | Lane Z: Allianz's price chart diving to the stored 0 (finding 4) |
| 35 | `35-light-lanez-wealth-ttwror-contribution-1m-1200.png` | Lane Z: Wealth's 1M chart and contribution, no dip |
| 36 | `36-light-english-1200.png` | English spot check, 1200 px |
| 37 | `37-light-english-compact-393.png` | English spot check, 393 px |

## Defects

Ranked; "introduced" means by this sprint's diff, "older" before it.

1. **S2, introduced. No way to sign out in the compact and short-wide
   classes.** At 1200 px „Abmelden“ is at the sidebar's foot; at 393 × 852
   and 844 × 390 the sidebar is gone (no burger), and neither the tab bar
   nor „Mehr“ lists „Abmelden“: no visible control on the page names it
   (screenshot 26). With a UI password set, the operator cannot end the
   session on a phone.
2. **S2, introduced. „Mehr“ cuts off its last row at 844 × 390.** The sheet
   is `position: fixed`, 431 px tall in a 390 px window, with no scroller;
   „Audit-Journal“ ends at 414 px and a wheel or swipe does not bring it in.
   The journal has no other entry in that class (screenshot 31).
3. **S2, introduced. Crashes' compact form drops the security's name:**
   „Synthetic dip … −2,4 % · Depot −3,1 %“ reads as the depot's own return
   beside the benchmark's, while −3,1 % is the lowest single held security
   (Allianz; the wide form says „Niedrigste im Depot: Allianz … −3,1 %“).
   The figure is right; its label names another quantity, so a reader
   concludes the depot fell more than the benchmark (screenshot 28). S2 by
   the misreading it invites; S3 if the ⓘ is judged enough.
4. **S3, older. The security's price chart draws a stored close of 0 as a
   price:** Allianz's line dives to 0 on 20.11.2026 and the axis starts at
   „0,0000“ (four decimals). Every Lane Z read skips it — the metrics beside
   the chart too (drawdown −9,1 %, 52-week low) — so the chart is the one
   place that values it at 0 (screenshot 34). ADR-0051's amendment reads a
   close of 0 as no price in the walk; whether the chart follows is the
   ADR's to say. A line for the Securities polish list.
5. **S3, introduced. Wertentwicklung at 1T draws an empty plot:** axes 0 to
   80.000 and the same date at both ends, no band; the table under it is
   right (screenshot 04).
6. **S3, introduced. On a Monday „1W → Woche“ is one day:** Tops und Flops'
   week runs 22.11. to 23.11.2026 (ADR-0061's week to date) and reads the
   same figures as „1T → Tag“, while Gesamtwert and Wertentwicklung's 1W
   are 17.–23.11. The tag says the translation, but one period above the
   dashboard shows two different weeks (screenshot 07).
7. **S3, introduced. Tops und Flops at M shows four rows a half and drops
   the fifth unsaid:** the read answers five (limit 5); the CSS hides
   `li:nth-child(n+5)`, so at 1W Microsoft +0,2 % and Kestrel Anleihe 0,0 %
   are missing, with no „+1 weitere“ as Datenqualität and Fällig say.
8. **S3, introduced. The edit bar's label reads „bearbeiten“** (msgid
   "editing"), a bare infinitive; „Bearbeitung“ or „Wird bearbeitet“ reads
   as a state. And at 1200 px the open catalogue drawer covers
   „Zurücksetzen“ and „Fertig“: a click on them lands on the drawer until ×
   closes it (screenshot 11).
9. **S3, introduced. A widget title under its ⓘ:** „Gesamtwert“ at 1200 px
   in German (text 2 px past the ⓘ's edge, the heading clipped), and
   „Datenqualität“ in the edit mode (screenshots 02, 11). At 834 and
   1440 px, and in English, none.
10. **S3, introduced. The short-wide top bar:** at 844 × 390 the subtitle
    „Lokales Portfolio-Tracking“ (11 px) drops under „Überblick ▾“, apart
    from the brand it belongs to, and the rail hyphenates „Dash-boards“,
    „Wertpa-piere“, „Nachrich-ten“ (screenshot 30).
11. **S3, older. „eins ohne Anlageklasse“** in Datenqualität: the German
    singular of "one without an asset class" reads „eines“ (or „1“)
    (screenshot 29).

No S1. Seen and as designed, not defects: the template's own kinds move
only within free cells (a full first row refuses every keyboard move of
Wertentwicklung, and says why); „Weiter bearbeiten“ then „Fertig“ replaces
the agent's layout, as its line says; the compact edit's announcements name
the grid column („Spalte 7, Zeile 5“), the wide place the widget keeps;
„2 Positionen ohne Wechselkurs“ counts securities (Harborline, Larkspur),
the valuation's `unvalued_count` 4 counts position rows (Larkspur in two
depots), as Wealth's note does.
