# Sprint 26 planning board 02: predictions, the human view (idea F1)

Drawn on 2026-11-06, before any code. ADR-0055 §5 put predictions over
API and MCP first and their screens in the next sprint; the two-way
coverage rule makes them due in Sprint 26. The board shows:

1. the security page's new tab **Prognosen** (`/securities/:id`), with
   its empty state and its basis behind the ⓘ;
2. **where the calibration report lives**, a genuine choice: A, a Wealth
   tab of its own (recommended), or B, a block on Risk;
3. two lines of #1365 (the Securities polish list) that the same story
   fixes, before and after: the delete confirmation names predictions, and
   unflagging a benchmark says what happens to the predictions that name it.

| File | What it is |
|---|---|
| `02-predictions.html` → `02-predictions--1200.png` | The desktop board, rendered at 1200 px: parts 1 to 3. |
| `02-predictions-390.html` → `02-predictions--390.png` | The phone board, rendered at 390 px: the tab (light, empty, dark) and A. |
| `build.js` | Captures the frames from the running review instance, writes `frames/` and both boards. Copied from `../ux-design-2026-11-05-sprint24-p1/build.js`; the header, the proposal CSS and the frame CSS differ. |
| `frames.js` | The frames, the new strings (`NEW`), the synthetic predictions and the in-page preps that write the proposal into the live page. |
| `board.js` | Lays out the boards and their text. |
| `render.js` | Renders both boards to PNG (256 colours when Pillow is there). |
| `frames/` | One static page per frame and width; each links the real `priv/static/app.css`, the proposal frames carry the story's CSS in `<style id="proposal">`. |

## What each frame shows

| Frame | Shows |
|---|---|
| `tab@1200`, `tab@390` | Apple Inc. (`/securities/1`): the tenth tab „Prognosen“ after „Research“, four predictions newest first: open (145 days left), missed, hit, unresolved (no benchmark close). Pins ① to ⑦ on the board. |
| `tab-tip@1200` | The same with the ⓘ open: the computation basis (ADR-0055 §3 and the amendment, the payload's `computation_basis`) in sentences. |
| `tab-empty@1200`, `tab-empty@390` | Harborline Freight Inc (`/securities/36`): no prediction yet. |
| `tab-dark@1200`, `tab-dark@390` | The tab in the dark theme. |
| `report-a@1200`, `report-a@390` | **A:** Wealth's seventh tab „Prognosen“ (`/predictions`): author and model chips; „Kalibrierung“ with Brier score ± standard error and the 0,25 reference, sharpness, hit rate ± standard error beside the mean stated probability, the resolved count; the bands with fewer than 20 (a sentence why, and the count per band); the same by author and model; „Alle Prognosen“ across securities with status chips (Fällig = `due_before`). At 390 px groups and list are two-line rows (UX-DR27). |
| `report-a-dark@1200` | A in the dark theme. |
| `report-a-later@1200` | A at a later, invented state (86 resolved): the band table, two bands past 20 with their hit rate, the others „zu wenige · n von 20“. |
| `report-b@1200` | **B:** the same report as a block on Risk under „Eigene Regeln“, without filters and without the list. |
| `delete-before@1200`, `delete-after@1200` | #1365 line 1: the browser's native confirmation (`data-confirm`), redrawn over the list, with the shipped sentence and with „Prognosen“ added. |
| `unflag-before@1200`, `unflag-after@1200` | #1365 line 2: the inline result after „Benchmark-Markierung entfernen“, shipped and with the added sentence. |

**Markers:** dashed accent outline (`mock-new`) = new UI; amber left
stripe (`mock-synth`) = invented data; magenta pins tie a spot to the
board's list.

## The pick

- **A, a Wealth tab „Prognosen“ (recommended).** It has room for what
  ADR-0055 §4 and §5 ask: filters by author and model, the groups, the
  bands, and the list of all predictions with the due query, which has no
  other home (the security's tab lists only that security's calls). It
  sits with Wealth's other analyses and can be linked. Its cost: a seventh
  tab in a row that already scrolls on a phone, and a tab in a view-scoped
  area that does not depend on the view, which its subtitle says.
- **B, a block on Risk.** No new tab, and it stands beside the policy
  rules, the other evaluation of decisions. But Risk reads concentration
  and volatility of the view, while calibration measures an author across
  all securities, so the page's „Ansicht: Alles“ is wrong for the block;
  the page already has five sections; the cross-security list and the due
  query get no place; author and model filters would be a second filter
  system on a page whose filter is the view.
- **C (considered, not drawn): a sidebar entry of its own.** View-free,
  but a main area for a page that will mostly read „zu wenige“ for a year;
  the sidebar carries the four core areas.

**Silence adopts the recommendation (A).** A comment „F1 B“ changes it.

## Judgment calls, each flippable by a comment

1. **The tab sits after „Research“**, before „Termine“: a prediction
   points at a research entry (`note_id`), so the two stand together.
2. **The tab uses the research timeline's anatomy** (`.research-timeline`,
   `.research-entry`, head, meta, facts, body), the anatomy of the
   security's other permanent records, not a table: a prediction carries a
   sentence and a rationale. The cross-security list in A is a table.
3. **Figures appear only once resolved** (return, benchmark return, excess
   in Pp, the dates of the closes used); an open or unresolved prediction's
   claim line already says everything.
4. **„verfehlt“ is muted, not red**: a miss is an expected outcome, not a
   data fault. „Treffer“ takes the intact thesis's green outline,
   „nicht aufgelöst“ the dashed „nicht bestimmbar“ badge of the rules. The
   entry's left edge follows the status.
5. **The excess keeps its sign colour** (DESIGN.md, sign colour holds),
   so a missed „Fällt“ call shows a green +2,2 Pp beside „verfehlt“: the
   colour is the measurement's sign, the badge the call's outcome.
6. **No form.** Predictions are recorded over API or MCP (the empty state
   and the ⓘ say so); an operator form on the security page is a new idea,
   not this story.
7. **Bands collapse to one sentence and a count line** while no band
   has 20; the table appears with the first band at 20.
8. **The unflag sentence appears only when predictions name the
   security as their benchmark**, with their count.
9. **Under 480 px a resolved prediction's four facts stay two abreast**
   (the shipped facts grid stacks to one column there, for the thesis's
   long labels).

## What the story builds, and what it does not

**Builds:** the „Prognosen“ tab on the security page with its empty
state and ⓘ basis; the picked report surface (A: `/predictions` as
Wealth's seventh tab, with author and model filters, the calibration
block, the bands in both states, the groups, and the cross-security list
with its status chips and phone rows; B: the block on Risk); the two
#1365 strings; the anatomy written into `DESIGN.md`.

**Does not build:** any write path in the UI (no form, no edit, no
withdrawal: ADR-0055 §2); any advice or action wording (no „kaufen“,
„verkaufen“, nothing that proposes a trade: ADR-0055 §6); a `resolves_on`
range control unless the story finds it needed (the endpoint has it; the
board does not draw it); per-source calibration (deferred by ADR-0055 §9).

## New strings (German proposals)

Tab and list on the security page:

- „Prognosen“ (tab; also Wealth's tab and the page title in A)
- „Festgehaltene Prognosen zu diesem Wertpapier, die neueste zuerst. Keine wird geändert oder gelöscht.“
- ⓘ, one sentence per line:
  - „Eine Prognose bleibt, wie sie abgegeben wurde: Sie wird nie geändert, zurückgezogen oder gelöscht. Eine korrigierte Prognose ist eine neue, und beide zählen.“
  - „Ausgewertet wird beim Lesen aus gespeicherten Schlusskursen, beide Seiten in EUR zum gespeicherten Wechselkurs ihres Tages; ein Ergebnis wird nie gespeichert.“
  - „Start: der letzte Schlusskurs am oder vor dem Tag der Abgabe. Ende: der letzte am oder vor dem Auflösungstag. Gewertet wird erst, wenn ein Schlusskurs ab dem Auflösungstag vorliegt, längstens 7 Tage danach.“
  - „Ein Schlusskurs, der mehr als 7 Tage vor seinem Datum liegt, zählt nicht; dann bleibt die Prognose nicht aufgelöst, mit ihrem Grund, und wird nie geschätzt.“
  - „Überrendite = Rendite − Rendite der Benchmark. „Übertrifft“ trifft bei mehr als 0, „bleibt zurück“ bei weniger als 0; genau 0 verfehlt beide. Ein fester Satz wird täglich verzinst; 0 % ist die absolute Aussage (steigt, fällt).“
  - „Nur Kursrendite: Ausschüttungen zählen auf keiner Seite.“
  - „Festgehalten wird über die API oder MCP.“
- „Für dieses Wertpapier ist keine Prognose festgehalten. Festgehalten wird über die API oder MCP.“
- Claims: „Übertrifft %{benchmark} bis %{date}“, „Bleibt bis %{date} hinter %{benchmark} zurück“, „Übertrifft %{rate} p. a. bis %{date}“, „Bleibt bis %{date} unter %{rate} p. a.“, „Steigt bis %{date}“, „Fällt bis %{date}“
- Status: „offen · noch %{count} Tage“ / „offen · noch 1 Tag“, „offen · wartet auf den Schlusskurs“, „Treffer“, „verfehlt“, „nicht aufgelöst“
- „Der Auflösungstag ist vorbei; gewertet wird, sobald ein Schlusskurs ab dem %{date} vorliegt, spätestens am %{last}.“
- Reasons: „kein Startkurs“, „kein Endkurs“, „kein Benchmark-Kurs“, „kein Wechselkurs“; sentences „Für die Benchmark liegt am oder bis 7 Tage vor dem %{date} kein Schlusskurs vor.“, „Für den %{date} ist kein Wechselkurs %{currency} → EUR gespeichert.“ (and one each for the start and end close)
- Labels: „Wahrscheinlichkeit“, „Auflösungstag“, „Rendite“, „Benchmark-Rendite“, „Überrendite“, „Schlusskurse“, „Research #%{n} · %{kind}“

The report (A; B takes the same strings but the filters and the list):

- „Wie gut die festgehaltenen Prognosen getroffen haben · über alle Wertpapiere, unabhängig von der Ansicht“ (subtitle)
- „Urheber“, „Modell“, „alle Modelle“, „Kalibrierung“, „· %{resolved} aufgelöst · %{open} offen · %{unresolved} nicht aufgelöst“
- „Brier-Score“, „± Standardfehler · Referenz 0,25 = immer 50 % · niedriger ist besser“
- „Schärfe“, „Ø Abstand der Wahrscheinlichkeit von 0,50 · 0 = immer 50 %“
- „± %{se} Pp Standardfehler · Ø angegeben %{mean}“ (under „Trefferquote“)
- „Aufgelöst“, „%{open} offen und %{unresolved} nicht aufgelöst zählen in keinem Score“
- „Grundlage: jede aufgelöste Prognose einmal, Wahrscheinlichkeit und Ergebnis wie im Tab „Prognosen“ des Wertpapiers.“
- ⓘ: „Brier-Score: Mittel von (p − o)² über die aufgelösten Prognosen, p die angegebene Wahrscheinlichkeit, o 1 bei Treffer und 0 sonst. Die Referenz 0,25 ist der Score von „immer 50 %“.“ · „Standardfehler: die Standardabweichung der quadrierten Fehler in der Stichprobe, geteilt durch √n; bei der Trefferquote die der Treffer.“ · „Schärfe: Mittel von p − 0,50. Wer immer 50 % sagt, ist perfekt kalibriert und sagt nichts.“ · „Trefferquote: Treffer durch n, neben der mittleren angegebenen Wahrscheinlichkeit, der eine kalibrierte Quote entspricht.“ · „Offene und nicht aufgelöste Prognosen zählen in keinem Score; sie werden gezählt.“ · „Auflösung wie im Tab „Prognosen“ des Wertpapiers; nur Kursrendite.“
- „Nach Wahrscheinlichkeit“, „Eine Trefferquote je Band zeigt sich erst ab 20 aufgelösten Prognosen im Band; bisher erreicht keines 20. Bis dahin trägt der Brier-Score mit seinem Standardfehler die Aussage.“, „Aufgelöst je Band:“, „Band“, „Ø angegeben“, „zu wenige · %{n} von 20“
- „Nach Urheber und Modell“, „Alle Prognosen“, „Abgegeben“, „Aussage“, „Wahrsch.“, „Stand“, „Offen“, „Aufgelöst“, „Nicht aufgelöst“; phone rows „noch %{count} Tage“, „wartet auf Schlusskurs“
- B only: „Die einzelnen Prognosen stehen je Wertpapier im Tab „Prognosen“.“

#1365, the two lines (each a new msgid replacing a shipped one):

- **Delete confirmation:** „Dieses Wertpapier löschen? Buchungen, Kurse, Termine, Research-Einträge, Prognosen und eigene Regeln blockieren das Löschen. Mit entfernt werden seine Klassifizierungen, Positionsziele, Bucket-Zuordnungen und früheren ISINs, jeweils im Journal festgehalten, und das Logo.“ (en: „… research entries, predictions and policy rules block the deletion. …“)
- **After unflagging a benchmark** that predictions name, appended to the shipped „%{name} ist keine Benchmark mehr“ with a full stop: „%{count} festgehaltene Prognosen messen weiter an ihr; eine neue Prognose kann sie nicht mehr als Benchmark nennen.“ / „1 festgehaltene Prognose misst weiter an ihr; …“

**Existing strings used** (from `priv/gettext/de/LC_MESSAGES/default.po`):
„Research“, „Termine“, „Agent“, „Operator“, „Benchmark“, „Trefferquote“,
„Wertpapier“, „These“, „Risiko“, „Alle“, „Fällig“, the shipped delete
confirmation, „%{name} ist keine Benchmark mehr“; everything else on a
frame is the live page's own.

## The synthetic figures

The review seed holds no prediction. `frames.js` invents 21 on the seed's
securities („today“ is the seed's 06.11.2026): 12 resolved, 7 open (one
waiting for its end close, so „Fällig 1“), 2 unresolved (no benchmark
close; no exchange rate). The benchmark security is the seed's only one,
„Kestrel Industrial Group NV Index“; the rate benchmarks are `rate:0` and
`rate:0.02`. The models are invented placeholders („model-alpha-2“,
„model-alpha-3“). The report's figures are computed in `frames.js` from
the 12 resolved calls with ADR-0055 §4's formulas (Brier 0,186 ± 0,041,
sharpness 0,17, hit rate 66,7 % ± 14,2 Pp beside a mean stated 66,7 %);
the later band table is invented as a whole. Returns, rationales and
dates are invented. No real portfolio, person or machine detail appears.

## Found while drawing (shipped UI, not filed here)

- The thesis card's facts grid on the Research tab breaks the label
  „Invalidierungsbedingung“ mid-word at 1200 px („INVALIDIERUNGSBEDINGUN /
  G“): `overflow-wrap: anywhere` on a 150 px column; `hyphens: auto` under
  `lang="de"` would break it at a syllable.
- A Termine entry's `p.research-entry__meta` keeps the browser's paragraph
  margins, so each entry ends in roughly 30 px of empty space below
  „Zuletzt geprüft …“ (Apple's events); the new tab's proposal sets
  `margin: 0` on its own meta line only.
- In the same meta line, „Quelle“ and „Zuletzt geprüft 04.11.2026“ run
  together with no separator („Quelle Zuletzt geprüft 04.11.2026“).
- The security form has no field for the benchmark flag: it is set only
  from the row menu, so line 2 of #1365 lands in the inline result after
  „Benchmark-Markierung entfernen“, not in a help text.

## Rebuilding

Run a review instance on port 4011 with the synthetic review seed, from
the repository root (the database of board 01 serves; see
`../ux-design-2026-11-06-sprint26-i22/README.md`):

```bash
DATABASE_NAME=portfolixir_review_i22 PORT=4011 PORTFOLIXIR_BACKGROUND_FETCH=off mix phx.server
```

Then, from this folder (`NODE_PATH` names a global Playwright if there is
no local one; `PLAYWRIGHT_CHROMIUM_EXECUTABLE` names a Chromium of your
own, if Playwright's is not installed):

```bash
node build.js    # captures every frame, writes frames/ and both boards
node render.js   # renders 02-predictions--1200.png and 02-predictions--390.png
```

The build sends GET requests only; nothing is clicked or submitted. The
security tab is captured from `?tab=events` and the events panel is
replaced by the proposal; the report from `/risk`, whose sections are
replaced. `ONLY=<regex>` recaptures the matching frames and keeps the
rest of `frames/sizes.json`.
