// The boards' layout and text. build.js captures the frames into frames/
// and hands over their measured sizes; this file places them as <iframe>s
// with the picks, the reasons and the pins' legend, and writes
//   01-coverage.html / 01-coverage-390.html
//   02-money.html    / 02-money-390.html
//   03-journal.html  / 03-journal-390.html
// The desktop boards render at 1200 px, the phone boards at 390 px.
// `node board.js` alone rebuilds the boards from frames/sizes.json.
const fs = require('fs');
const path = require('path');

const BOARD_CSS = `
/* Artboard chrome only; everything inside a frame is priv/static/app.css. */
body { margin: 0; padding: 24px; background: var(--color-bg); color: var(--color-text); font-family: var(--font-sans); }
.mock-board { max-width: 1120px; margin: 0 auto 36px; }
.mock-head h1 { margin: 0 0 6px; font-size: 20px; }
.mock-head h1 small, .mock-board > h2 small { font-weight: 500; color: var(--color-text-muted); margin-left: 6px; font-size: 12.5px; }
.mock-board > h2 { margin: 0 0 4px; font-size: 16px; font-weight: 760; }
.mock-board p.mock-note, .mock-notes { font-size: 12.5px; color: var(--color-text-muted); line-height: 1.5; }
.mock-board p.mock-note { margin: 0 0 12px; max-width: 110ch; }
.mock-board b { color: var(--color-text); }
.mock-board code { font-size: 11.5px; }
.mock-pickbar { margin: 0 0 16px; padding: 10px 14px; border: 1px solid var(--color-accent); border-left-width: 4px; border-radius: var(--radius-md); background: var(--color-accent-soft); font-size: 12.5px; line-height: 1.5; }
.mock-pickbar p { margin: 0 0 6px; } .mock-pickbar p:last-child { margin: 0; }
.mock-legend { margin: 0; padding: 0 0 0 18px; font-size: 12.5px; color: var(--color-text-muted); line-height: 1.5; }
.mock-fig { margin: 0 0 18px; }
.mock-tag { display: inline-block; margin: 0 0 6px; padding: 2px 10px; border-radius: 999px; font-size: 11px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; }
.mock-tag--before { color: var(--color-danger); background: var(--color-danger-soft); }
.mock-tag--after { color: var(--color-positive); background: #ecfdf5; }
.mock-tag--alt { color: var(--color-text-muted); background: var(--color-bg-muted); }
.mock-tag--built { color: #92400e; background: #fef3c7; }
.mock-frame { width: max-content; max-width: 100%; border: 1px solid var(--color-border-strong); border-radius: 10px; background: var(--color-bg); overflow: hidden; box-shadow: var(--shadow-panel); }
.mock-frame iframe { display: block; border: 0; }
.mock-crop { overflow: hidden; }
.mock-row { display: flex; gap: 20px; align-items: flex-start; }
.mock-row > .mock-notes { flex: 1 1 0; min-width: 0; }
.mock-notes ul { margin: 0; padding-left: 18px; }
.mock-notes li { margin: 0 0 6px; }
.mock-pin { display: inline-grid; place-items: center; width: 18px; height: 18px; border-radius: 50%; background: #c026d3; color: #fff; font: 700 11px/1 var(--font-sans); vertical-align: 1px; margin-right: 4px; }
.mock-why { margin: 8px 0 0; padding: 8px 12px; border-left: 3px solid var(--color-accent); background: var(--color-bg-elevated); font-size: 12.5px; line-height: 1.5; color: var(--color-text-muted); }
.consequence { margin: 0 0 8px; padding: 8px 10px; border-left: 3px solid var(--color-danger); background: var(--color-danger-soft); color: var(--color-text); }
.mock-why p { margin: 0 0 6px; } .mock-why p:last-child { margin: 0; }
table.mock-rules { width: 100%; border-collapse: collapse; font-size: 12.5px; background: var(--color-bg-elevated); border: 1px solid var(--color-border); border-radius: var(--radius-md); }
table.mock-rules th { text-align: left; font-size: 11px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; color: var(--color-text-muted); background: var(--color-bg-muted); padding: 8px 10px; }
table.mock-rules td { padding: 7px 10px; border-top: 1px solid var(--color-border); vertical-align: top; }
.mock-key { display: inline-block; width: 22px; height: 12px; vertical-align: -1px; margin: 0 4px 0 2px; border-radius: 3px; }
.mock-key--new { outline: 2px dashed var(--color-accent); outline-offset: -2px; }
.mock-key--synth { box-shadow: inset 4px 0 0 #f59e0b; background: var(--color-bg-elevated); border: 1px solid var(--color-border); }
/* The phone board: the frames are the 390 px viewport. */
body.mock-phone { padding: 16px 0; }
body.mock-phone .mock-board > :not(.mock-fig), body.mock-phone .mock-head > * { margin-left: 16px; margin-right: 16px; }
body.mock-phone .mock-fig > .mock-tag { margin-left: 16px; }
body.mock-phone .mock-frame { width: 100%; border-radius: 0; border-left: 0; border-right: 0; box-shadow: none; }
`;

module.exports.main = function main(sizes) {
  sizes = sizes || JSON.parse(fs.readFileSync(path.join(__dirname, 'frames', 'sizes.json'), 'utf8'));
  const iframe = (key, title, crop) => {
    const s = sizes[key];
    if (!s) throw new Error('frame not captured: ' + key);
    const f = `<iframe src="${s.file}" width="${s.width}" height="${s.height}" title="${title}" scrolling="no"></iframe>`;
    return crop ? `<div class="mock-crop" style="width:${crop}px">${f}</div>` : f;
  };
  const fig = (kind, label, key, opts = {}) => `<figure class="mock-fig"><figcaption class="mock-tag mock-tag--${kind}">${label}</figcaption><div class="mock-frame">${iframe(key, label, opts.crop)}</div></figure>`;
  const row = (figure, notes) => `<div class="mock-row">${figure}<div class="mock-notes">${notes}</div></div>`;
  const pin = (n) => `<span class="mock-pin">${n}</span>`;
  const page = (title, sub, phone, body) => `<!doctype html>
<html lang="en" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mockup — ${title}${phone ? ' — 390 px' : ''} (Sprint 23)</title>
<link rel="stylesheet" href="../../../../../priv/static/app.css">
<!-- Generated by build.js and board.js from the review instance on the
     synthetic review seed. Each frame is a static page under frames/ that
     links app.css; "Heute" frames are the shipped markup, the other frames
     carry the proposal in their own <style id="proposal">. The block below
     is artboard chrome only. No script runs on this page or in a frame. -->
<style id="board">${BOARD_CSS}</style>
</head>
<body class="${phone ? 'mock-phone' : ''}" data-widths="${phone ? '390' : '1200'}">
<div class="mock-board mock-head">
  <h1>${title} <small>${sub}${phone ? ' · 390 px' : ''}</small></h1>
  ${body.head}
  <p class="mock-note"><span class="mock-key mock-key--new"></span> dashed = new or changed · <span class="mock-key mock-key--synth"></span> amber edge = a synthetic row written into the shipped markup of a real one (the seed has no such row) · ${pin(1)} ties a change to its section's text. Synthetic data only.</p>
</div>
${phone ? body.phone : body.desk}
</body>
</html>
`;
  const write = (file, html) => {
    fs.writeFileSync(path.join(__dirname, file), html.split('\n').map(l => l.replace(/[ \t]+$/, '')).join('\n'));
    console.log('wrote', file);
  };

  // =========================================================== board 01
  const b1head = `<div class="mock-pickbar">
    <p><b>Two-way coverage, due by the end of Sprint 23.</b> R6 (Sprint 22) shipped two agent-only reads, <code>GET /api/v1/splits/incomplete</code> and <code>GET /api/v1/transactions/rate_only</code>; the ADR-0053 amendment of 2026-11-02 adds a third, <code>GET /api/v1/transactions/cash_mismatch</code>. A4 (#957) shipped <code>flow_changes</code> in the depot and security merge previews' API. None of them has a human view.</p>
    <p><b>Q1 — where the three checks are read: A</b>, three more findings on the Overview's data-quality line, each opening the history filtered to its rows under its remedy. B (a section on the Imports page) is drawn for contrast. A comment „Q1 B“ flips it. <b>Q2 — severity: problem</b>; each can make a figure wrong. „Q2 attention“ flips it. <b>①b is a conformance repair</b> (before/after); <b>Q3 — the absorbed phrase stays in „Ändert auch“</b> as well as in the new section; „Q3 drop it“ flips it.</p>
  </div>`;
  const b1desk = `
<section class="mock-board">
  <h2>①a — R6's reads and the cash check on the data-quality line <small>Übersicht → Datenqualität · Transaktionen → Historie</small></h2>
  <p class="mock-note"><b>Today.</b> The line names five catalog findings, each linking to the securities list pre-filtered (<code>/securities?dq=…</code>). The ledger's three checks are read by the agent only. <b>After (A).</b> Each check with a count above zero adds one finding, in the line's shape: the count with its noun as the link, then what it does to the figures (#1121's <code>data-effect-of</code>). The link opens the history filtered <code>?dq=cash_mismatch</code>, <code>?dq=rate_only</code> or <code>?dq=incomplete_split</code>, URL-driven like <code>?since=</code>. The seed has none of these rows: the counts here are 1 each and the rows are synthetic.</p>
  ${fig('before', 'Heute — fünf Katalog-Befunde, keiner aus dem Hauptbuch', '01a-dq-today@1280')}
  ${fig('after', 'Nachher A — drei Befunde mehr, je nur bei Anzahl > 0 ' , '01a-dq-after@1280')}
  ${fig('after', 'Nachher A — der Link öffnet die Historie, gefiltert auf genau diese Buchungen, die Abhilfe darüber (?dq=cash_mismatch)', '01a-hist-cash@1280')}
  <div class="mock-row">
    <div>${fig('after', 'Nachher A — ?dq=rate_only (nur Hinweis und Tabelle)', '01a-hist-rate@1280')}${fig('after', 'Nachher A — ?dq=incomplete_split (nur Hinweis und Tabelle)', '01a-hist-split@1280')}</div>
  </div>
  <div class="mock-why">
    <p>${pin(1)}<b>The filtered history's note</b> is a problem data note, clamped, with „Alle Buchungen zeigen“ in its actions (UX-DR17: the remedy is a child of the note). It states the report's <code>note</code> and <code>remedy</code> in the operator's words: the API's remedy names <code>PATCH /api/v1/transactions/:id</code> and <code>POST /api/v1/splits</code>, the screen names „Bearbeiten“ and „Split erfassen“. The incomplete split's note names the missing portfolio and its quantity, which the history row cannot show, and links „Split erfassen“ on the security.</p>
    <p><b>A row's second line</b> (<code>.cell-note</code>, Sprint 22's anatomy lifted to <code>#transaction-list</code>) gives the figure the check compares: „aus den Zahlen: 816,00“ for the cash check (stored 806,00; the ADR's example, 10 × 81,00 + 5,00 + 1,00), „zum eigenen Kurs …“ for a rate-only trade. The other columns are the history's own.</p>
  </div>
  ${fig('alt', 'Variante B — ein Abschnitt „Datenqualität“ auf der Import-Seite, die Zeilen inline (zum Vergleich)', '01a-imports-b@1280')}
  <div class="mock-why">
    <p><b>Q1, recommended A.</b> (1) <b>One finding surface.</b> The Overview's data-quality line is where the operator already reads what is wrong (UX-DR2: one line, a count only when non-zero, no all-clear); a second surface splits it, and an operator who never opens Imports never sees B. (2) <b>The existing pattern.</b> A count linking to the list pre-filtered to exactly its rows is how every finding on the line works (#561, #651); the history is that list for bookings, and a row there already has „Bearbeiten“, the remedy. (3) <b>No new page, no second table.</b> B re-draws booking rows outside the history, with their own edit buttons and their own drift from the history's columns. (4) <b>The agent's reads stay one-to-one</b>: each finding is one API read, each filter its rows.</p>
    <p>B fits only if these checks were tied to imports. They are not: a hand edit (#1371) or an agent's PATCH makes a cash mismatch as well.</p>
  </div>
</section>

<section class="mock-board">
  <h2>①b — A4's flow changes in the merge previews <small>Konten & Depots → Depot 1 → Zusammenführen in… · Wertpapiere → Thornbury Water Fund → Zusammenführen in…</small></h2>
  <p class="mock-note"><b>Today.</b> The API serves <code>flow_changes</code> with <code>flow_basis</code>; the screens show only the absorbed flows, as a phrase in the „als Duplikate entfernen“ option's „Ändert auch“, and never a removed delivery or a flow across a view's boundary. <b>After.</b> A section „Externe Zu- und Abflüsse — bei „als Duplikate entfernen““ after the choice: one row per entry (date, effect, booking and where, quantity, the flow's change with what it is valued at). Under 720 px it becomes the preview's two-line rows. The <code>flow_basis</code> method sentences go into the section's ⓘ (I1, Sprint 22 board 01 ①); the short basis stays visible (②). <b>The seed's depot pairs have no equal bookings</b>, so both depot frames carry two synthetic pairs (amber) and the flows they would remove.</p>
  ${row(fig('before', 'Heute — nur „Ändert auch“ nennt den aufgenommenen Fluss', '01b-depot-today@1280'), `<ul><li><b>A removed delivery</b> (14.03.2025, 5 Helios into Depot 1) is an external flow of the portfolio; today nothing on the screen says the return's flows change.</li><li><b>A buy straddling a view</b> („Nur Neuzugang“) is a flow across that view's boundary; not shown today.</li><li>Only the <b>absorbed</b> cash leg is named, inside the option.</li></ul>`)}
  ${row(fig('after', 'Nachher — der Abschnitt mit seinen Einträgen', '01b-depot-after@1280'), `<ul><li>${pin(1)}<b>Columns:</b> Datum · Wirkung · Buchung · wo (depot, view or account) · Stück · Fluss, with what the amount is valued at as its second line („zum gebuchten Preis“, „zum gebuchten Wert“; „zum Tageskurs“ where the delivery has no price and the change is null).</li><li><b>Wirkung</b> names the three kinds: <code>removed</code> „entfällt“, <code>boundary_removed</code> „entfällt an der Ansichtsgrenze“, <code>absorbed</code> „vom gesetzten Saldo aufgenommen“.</li><li><b>The ⓘ</b> holds the method (what each kind is, why no recomputed return, view membership unchanged); it is drawn open on the 390-px board.</li><li><b>Q3:</b> „Ändert auch“ keeps its absorbed phrase: it is what the operator reads while choosing.</li></ul>`)}
  ${row(fig('before', 'Heute — Wertpapier-Vorschau ohne gleiche Buchungen', '01b-security-today@1280'), '<p>Thornbury Water Fund into its twin (seed 17c): no equal bookings, so no flow can change. Today the preview says nothing about flows.</p>')}
  ${row(fig('after', 'Nachher — eine Zeile, wo nichts wandert (leerer Zustand)', '01b-security-after@1280'), `<ul><li>${pin(1)}<b>Empty state:</b> one basis line, the anatomy the preview already uses for FIFO („Realisierte Gewinne (FIFO): … bewegt sich …“): „Externe Zu- und Abflüsse: Keiner entfällt oder wandert; die Rendite liest dieselben Flüsse.“</li><li>It shows when <code>flow_changes</code> is empty, with or without equal bookings, so the screen states the same thing the API does.</li><li>A security preview with entries takes the depot's section unchanged.</li></ul>`)}
</section>`;
  const b1phone = `
<section class="mock-board">
  <h2>①a</h2>
  ${fig('before', 'Heute', '01a-dq-today@390')}
  ${fig('after', 'Nachher A', '01a-dq-after@390')}
  ${fig('after', 'Nachher A — Historie ?dq=cash_mismatch', '01a-hist-cash@390')}
</section>
<section class="mock-board">
  <h2>①b</h2>
  ${fig('before', 'Heute — Depot-Vorschau', '01b-depot-today@390')}
  ${fig('after', 'Nachher — Zeilen statt Tabelle, ⓘ geöffnet', '01b-depot-info@390')}
</section>`;
  write('01-coverage.html', page('Board 01 — the coverage views', 'R6 #1292 #1290 · ADR-0053 (2026-11-02) · A4 #957', false, { head: b1head, desk: b1desk }));
  write('01-coverage-390.html', page('Board 01 — the coverage views', 'R6 #1292 #1290 · ADR-0053 (2026-11-02) · A4 #957', true, { head: b1head, phone: b1phone }));

  // =========================================================== board 02
  const b2head = `<div class="mock-pickbar">
    <p><b>Money on screen.</b> ①a #1371: an edit of an imported trade's figures leaves its stored cash. <b>Q4 — answer (b), adopted by the ADR-0053 amendment of 2026-11-02:</b> the drawer shows the cash field, prefilled with what the new figures derive, and saves what the field states; a figure off by more than a cent is refused. Variant (a), the cash re-derived silently, is drawn for contrast. „(a)“ in a comment flips it, as the ADR says.</p>
    <p>①b #1369 and ①c #1368 are conformance repairs (before/after): Sprint 22's valuation rule, a held position with no quote at its last own trade price, named where it is read („Handelspreis · 14.03.2025“, „zum Handelspreis“). ①d draws two of Sprint 22's R5 notes after the fact, as built.</p>
  </div>`;
  const b2desk = `
<section class="mock-board">
  <h2>①a — #1371: the cash of an imported trade follows an edit only when stated <small>Transaktionen → Arbolia Inc., Kauf 16.04.2026 → Bearbeiten</small></h2>
  <p class="mock-note">The seed's imported Arbolia buy is the ADR's example: 10 at 80,00 EUR, fees 5,00, taxes 1,00, cash 806,00. Each frame is that buy opened for editing with its price typed as 81, never saved. (The note about the booking currency is today's, #1335: Arbolia trades in USD and was booked in EUR without legs.)</p>
  ${row(fig('before', 'Heute — Preis 81, der Betrag bleibt unsichtbar 806,00', '02a-drawer-today@1280'), `<p class="consequence"><b>Saving this</b> stores price 81,00 and keeps cash 806,00: the cash balance and the holding's cost read 806,00, the lot (realized gains, trade returns) 816,00. The drawer has no cash field, so nothing on screen says so; §2 of ADR-0053 would have refused this row at import.</p>`)}
  ${row(fig('after', 'Nachher (b), empfohlen — das Feld zeigt den Betrag, vorbelegt mit 816,00', '02a-drawer-b@1280'), `<ul><li>${pin(1)}<b>„Betrag (EUR)“</b>, the drawer's existing label for the cash (the cash form's and the history column's word), shows on a buy or sell that stores its cash and has no settlement legs. Its help line says what it is and what is stored.</li><li><b>When quantity, price, fees or taxes change</b>, the field is prefilled with what they derive (816,00), dashed, and an attention note gives the sum and that saving takes what the field states.</li><li><b>Saving states the cash</b>: the field is part of the submitted form (ADR point 2), so the PATCH always carries <code>gross_amount</code>.</li><li>A date, note or account edit leaves the field at the stored figure and shows no note.</li></ul>`)}
  ${row(fig('after', 'Nachher (b) — 806,00 stehen gelassen: abgelehnt', '02a-drawer-b-refused@1280'), `<ul><li><b>The refusal</b> is §2's check, the field's own error in the drawer's <code>field-error</code> anatomy: „passt nicht zu Menge × Preis, Gebühren und Steuern — erwartet 816,00“. Nothing is saved.</li><li>The operator either takes the derived figure or types the broker's statement figure and corrects the price that disagrees with it.</li></ul>`)}
  ${row(fig('alt', 'Variante (a) — der Betrag wird still neu abgeleitet (zum Vergleich)', '02a-drawer-a@1280'), `<div class="mock-why"><p><b>Q4, recommended (b)</b> (the ADR's answer). An imported row's cash is the broker's figure. Under (a) a typo fix in the price silently overwrites it with the app's guess. Under (b) nothing changes that the operator has not seen in the field. (a) is one field fewer to read and is right when the edit is the correction of a typo in a hand-made booking; that case is unaffected, since a hand-made buy stores no cash.</p></div>`)}
</section>

<section class="mock-board">
  <h2>①b — #1369: open lots and the sell preview at the last own trade price <small>Wertpapiere → Helios Solar Systems SE → Trades · Transaktionen → Transaktion erfassen → Verkauf</small></h2>
  <p class="mock-note"><b>Today.</b> Helios has no quote. Its head says it counts in the totals at its last own trade price, 19,20 EUR (14.03.2025), since Sprint 22 (#1316); its open lots read „—“ in Letzter and every result column, and the sell preview prices the lots at the latest quote, so Bruttogewinn reads „—“. <b>After.</b> Both read the valuation's rule and name it, with Sprint 22's words.</p>
  ${fig('before', 'Heute — Offene Positionen: „—“ für Letzter und jedes Ergebnis', '02b-lots-today@1280')}
  ${fig('after', 'Nachher — 19,20 mit „Handelspreis · 14.03.2025“, die Ergebnisse daraus', '02b-lots-after@1280')}
  ${row(fig('before', 'Heute — Verkaufsvorschau: Bruttogewinn „—“', '02b-sell-today@1280'), '<p>A sell of 5 Helios from Depot Nord typed into the drawer, not saved. FIFO consumes the 12.02.2025 lot (18,00).</p>')}
  ${row(fig('after', 'Nachher — bepreist zum letzten eigenen Handelspreis, und so gesagt', '02b-sell-after@1280'), `<ul><li>${pin(1)}<b>The preview's price line</b> takes the place of „Bepreist zum zuletzt gespeicherten Preis: …“ when no quote exists: „Bepreist zum letzten eigenen Handelspreis: 19,20 (14.03.2025).“</li><li>Bruttogewinn +6,00 EUR = 5 × (19,20 − 18,00). A price typed by the operator still wins, as today.</li><li>No new CSS. The API's sell preview names <code>price_source: trade</code> in its basis.</li></ul>`)}
</section>

<section class="mock-board">
  <h2>①c — #1368: the category result at the last own trade price <small>Klassifizierungen → Anlageklasse (Ansicht Alles)</small></h2>
  <p class="mock-note"><b>Today.</b> The roll-up prices its members by quotes only (<code>CategoryResult.quote_priced/1</code>), while its „Wert“ column and the member rows already value them at the trade price. So ETF reads Wert 21.493,20 but Einstand 13.000,00 and Ergebnis −869,20 over 2 of 15 positions, and the note lists 19 positions as „kein brauchbarer Kurs“. <b>After.</b> The same rule as the holdings: Einstand 21.749,40, Ergebnis −256,20 (−1,2 %) over all 15; Fund 451,11 / 0,00. The note keeps the three positions no rule can value. Figures computed from the seed's holdings with the trade-price fallback.</p>
  ${fig('before', 'Heute — „Wert“ zählt sie, „Einstand“ und „Ergebnis“ nicht; 19 Positionen im Hinweis', '02c-cat-today@1280')}
  ${fig('after', 'Nachher — eine Regel für Wert, Einstand und Ergebnis; die Quelle in der Zeile', '02c-cat-after@1280')}
  <div class="mock-why"><p>${pin(1)}<b>The row figures</b> follow the rule; <b>a member valued at its trade price</b> says „zum Handelspreis“ under its value (<code>.cell-note</code>), and <b>the basis line</b> gains „Kurse: der neueste, ohne Kurs der letzte eigene Handelspreis“, so the rule is stated where the figures are read (UX-DR11). The API's <code>computation_basis</code> names it as well (review-blocking per AGENTS.md).</p></div>
</section>

<section class="mock-board">
  <h2>①d — Sprint 22 R5, drawn after the fact <small>Cashflow → Trades · Übersicht → Abgeschlossene Trades</small></h2>
  <p class="mock-note"><b>As built</b> (#1310, #1311; no board before the code, the retrospective's carry-forward). R5 added three exclusion sentences to both notes: a sale or its lot priced in a third currency, a buy paid in another currency than the sale's, and a buy of amount zero, each with its count in the note's lead. The seed has none of these sales, so the three sentences (pins 2–4) carry synthetic names in the live note beside the seed's two real reasons. The notes are drawn expanded („mehr“ pressed).</p>
  ${fig('built', 'Gebaut — Cashflow → Trades, „Aus jeder Summe ausgeschlossen“', '02d-realized-built@1280')}
  ${fig('built', 'Gebaut — Übersicht, „Fehlt bei den Trades“', '02d-overview-built@1280')}
  <div class="mock-why"><p><b>Found while drawing (S3, polish list „Cash flow“ and „Overview“).</b> (1) On Cash flow → Trades the backfill's method sentence and „Historische Wechselkurse nachladen“ follow every reason, though the three R5 reasons say „which no rate fixes“: with only those reasons the note offers a remedy that cannot act (UX-DR25 clause 3). (2) On the Overview the pointer „Das Nachladen der Wechselkurse steht unter „Alle Trades““ sits after the missing-leg sentence, and with R5's sentences after it, it reads as if it covered them. (3) With five reasons the lead repeats each count once more, so the note runs to nine lines at 1200 px.</p></div>
</section>`;
  const b2phone = `
<section class="mock-board"><h2>①a</h2>
  ${fig('before', 'Heute', '02a-drawer-today@390')}
  ${fig('after', 'Nachher (b)', '02a-drawer-b@390')}
</section>
<section class="mock-board"><h2>①b</h2>
  ${fig('before', 'Heute', '02b-lots-today@390')}
  ${fig('after', 'Nachher', '02b-lots-after@390')}
</section>
<section class="mock-board"><h2>①c</h2>
  ${fig('after', 'Nachher', '02c-cat-after@390')}
</section>
<section class="mock-board"><h2>①d</h2>
  ${fig('built', 'Gebaut — Cashflow → Trades', '02d-realized-built@390')}
  ${fig('built', 'Gebaut — Übersicht', '02d-overview-built@390')}
</section>`;
  write('02-money.html', page('Board 02 — money on screen', '#1371 · #1369 · #1368 · R5 #1310 #1311', false, { head: b2head, desk: b2desk }));
  write('02-money-390.html', page('Board 02 — money on screen', '#1371 · #1369 · #1368 · R5 #1310 #1311', true, { head: b2head, phone: b2phone }));

  // =========================================================== board 03
  const b3head = `<div class="mock-pickbar">
    <p><b>U2 — the audit journal viewer</b>, the two-way coverage debt standing since Sprint 19: <code>GET /api/v1/journal</code> and <code>portfolixir.journal.list</code> exist, no screen does. <b>Q5 — A</b>, one page „Audit-Journal“ (<code>/journal</code>), newest first, filtered by actor, operation and kind, each row linking to its entity and to that entity's own history. B, a „Verlauf“ fold on each entity's page, is drawn for contrast. „Q5 B“ flips it. <b>Q6 — the entry sits in the sidebar's „Verwaltung“ group</b>, after „Klassifizierungen“; „Q6 tab“ moves it to a third Transactions tab.</p>
  </div>`;
  const b3desk = `
<section class="mock-board">
  <h2>A — one page, the API's shape <small>/journal · Verwaltung → Audit-Journal</small></h2>
  <p class="mock-note">The seed's journal, filtered to the agent: the seven writes of the API token „review seed“ (actor <code>api_token_rw</code>), read from <code>audit_journal</code>, newest first. The seed wrote them within one second, so they share a time.</p>
  ${row(fig('after', 'Nachher — Navigation', '03-journal-nav@1280', { crop: 240 }), `<ul><li>${pin(1)}<b>Q6:</b> the low-traffic „Verwaltung“ group, where the other record-keeping pages are (ADR-0022's five areas). There is no Settings page to hang it from.</li><li>A Transactions tab would say the journal is about bookings; it holds every entity kind.</li></ul>`)}
  ${fig('after', 'Nachher A — Audit-Journal, Akteur Agent', '03-journal-a@1280')}
  <div class="mock-why">
    <p>${pin(1)}<b>Columns</b> map <code>JSON.journal_entry/1</code>: <code>inserted_at</code> (UTC, as the history's <code>since</code> note), <code>actor_type</code> with its <code>actor_label</code> (the token's name) as the second line, <code>operation</code>, <code>resource_type</code> + <code>resource_id</code> as the entry with its current name, and the change. ${pin(2)}<b>Filters</b> are the API's: actor and operation as chips, the kind as a select, <code>include_scenarios</code> as a checkbox; the basis line restates them. ${pin(3)}<b>„Gespeicherte Werte“</b> folds the stored <code>before</code>/<code>after</code> to the changed fields; the line above says the change in words. A delete shows its stored values with „—“ after.</p>
    <p><b>Per-entity links:</b> the entry links to its page where it has one (a rule to Risiko, an account to Konten &amp; Depots, a tax statement to Steuern); „Nur dieser Eintrag“ filters by <code>resource_type</code> + <code>resource_id</code>, so one entity's history is a URL. A deleted entity has no page and reads as text.</p>
    <p><b>Q5, recommended A.</b> (1) <b>The operator's question is global</b>: „what did the agent change this week?“ crosses entity kinds, and only one list answers it. (2) <b>It matches the API's shape</b>, one list with the same filters, so a link an agent hands over can open the same slice. (3) <b>One surface</b>, built once. B needs a fold on every page that shows an entity (securities, accounts, depots, views, rules, targets, tax statements, categories), and a booking has no page of its own, so B cannot show the most frequent entry at all. A gives B's per-entity view through „Nur dieser Eintrag“.</p>
  </div>
  ${fig('alt', 'Variante B — „Verlauf“ als Klappbereich auf der Seite des Eintrags (zum Vergleich)', '03-journal-b@1280')}
  <p class="mock-note"><b>B</b> on Meridian Global Equity ETF: its two journal entries (the ISIN change of the Sprint 16 merge and its creation). It answers „what happened to this security“ where it is read, but no question across entities, and nothing for a booking.</p>
  <div class="mock-why"><p><b>Found while drawing.</b> (1) <b>S3</b>, idea: the API has no time filter, so „this week“ is read by paging newest-first; a <code>since=</code> on <code>/api/v1/journal</code>, mirrored on the page as on the history, would answer it directly; it needs its own story (API and MCP first). (2) <b>S3</b>: a booking has no URL of its own, so the journal (and any agent hand-over) can link a transaction only to the history as a whole. (3) <b>S3</b>, to check against the API reference: a <code>delete</code> entry's <code>after</code> repeats the deleted record instead of being empty, so a reader comparing before/after sees no change; the page reads the operation, not the diff.</p></div>
</section>`;
  const b3phone = `
<section class="mock-board"><h2>A</h2>
  ${fig('after', 'Nachher A — Zeilen statt Tabelle', '03-journal-a@390')}
</section>
<section class="mock-board"><h2>B</h2>
  ${fig('alt', 'Variante B', '03-journal-b@390')}
</section>`;
  write('03-journal.html', page('Board 03 — U2, the audit journal viewer', 'GET /api/v1/journal · portfolixir.journal.list', false, { head: b3head, desk: b3desk }));
  write('03-journal-390.html', page('Board 03 — U2, the audit journal viewer', 'GET /api/v1/journal · portfolixir.journal.list', true, { head: b3head, phone: b3phone }));

  // =========================================================== board 04
  const b4 = module.exports.board04(sizes);
  write('04-number-colours.html', page('Board 04 — number colours against the three accents', 'owner request, 2026-11-02', false, { head: b4.head, desk: b4.desk }));
  write('04-number-colours-390.html', page('Board 04 — number colours against the three accents', 'owner request, 2026-11-02', true, { head: b4.head, phone: b4.phone }));
};

// The WCAG 2.x contrast ratio, the method of
// test/invariants/css_accent_contrast_test.exs: a translucent ground is
// composited over the surface below it in sRGB first.
function hex(h) { h = h.replace('#', ''); return [0, 2, 4].map(i => parseInt(h.slice(i, i + 2), 16)); }
function lum(rgb) { const c = rgb.map(v => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; }
function ratio(a, b) { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); }
function over(rgb, alpha, base) { return rgb.map((v, i) => Math.round(v * alpha + base[i] * (1 - alpha))); }
// Token values read from priv/static/app.css, so the table moves with it.
function tokens() {
  const css = fs.readFileSync(path.join(__dirname, '../../../../../priv/static/app.css'), 'utf8');
  const block = (sel) => { const i = css.indexOf(sel + ' {'); return css.slice(i, css.indexOf('}', i)); };
  const get = (b, name) => { const m = b.match(new RegExp('--' + name + ':\\s*([^;]+);')); return m && m[1].trim(); };
  const light = block('[data-theme="light"]');
  const dark = block('[data-theme="dark"]');
  return { light: (n) => get(light, n), dark: (n) => get(dark, n) };
}
function contrastRows() {
  const t = tokens();
  const rows = [];
  for (const theme of ['light', 'dark']) {
    const g = t[theme];
    const bg = hex(g('color-bg'));
    const el = hex(g('color-bg-elevated'));
    const soft = g('color-danger-soft');
    const softRgb = soft.startsWith('#') ? hex(soft) : (() => { const m = soft.match(/rgb\((\d+) (\d+) (\d+) \/ ([\d.]+)\)/); return over([+m[1], +m[2], +m[3]], +m[4], el); })();
    for (const [label, tok] of [['brand teal (C: gain)', 'color-accent-teal'], ['brand coral (C: loss, problem)', 'color-accent-coral'], ['today: --color-positive', 'color-positive'], ['today: --color-danger', 'color-danger']]) {
      const ink = hex(g(tok));
      rows.push({ theme, label, value: g(tok), bg: ratio(ink, bg), el: ratio(ink, el), soft: ratio(ink, softRgb) });
    }
  }
  return rows;
}

module.exports.board04 = function board04(sizes) {
  sizes = sizes || JSON.parse(fs.readFileSync(path.join(__dirname, 'frames', 'sizes.json'), 'utf8'));
  const iframe = (key, title) => { const s = sizes[key]; if (!s) throw new Error('frame not captured: ' + key); return `<iframe src="${s.file}" width="${s.width}" height="${s.height}" title="${title}" scrolling="no"></iframe>`; };
  const fig = (kind, label, key) => `<figure class="mock-fig"><figcaption class="mock-tag mock-tag--${kind}">${label}</figcaption><div class="mock-frame">${iframe(key, label)}</div></figure>`;
  const f2 = (n) => n.toFixed(2).replace('.', ',') + ':1';
  const ok = (n) => n >= 4.5 ? f2(n) : `<b style="color:var(--color-danger)">${f2(n)}</b>`;
  const crow = contrastRows().map(r => `<tr><td>${r.theme === 'light' ? 'hell' : 'dunkel'}</td><td>${r.label}</td><td><code>${r.value}</code></td><td>${ok(r.bg)}</td><td>${ok(r.el)}</td><td>${ok(r.soft)}</td></tr>`).join('');
  const ACC = { violet: 'Violett', teal: 'Teal', coral: 'Koralle' };
  const variant = (v, kind, title, note) => `<section class="mock-board"><h2>${title}</h2><p class="mock-note">${note}</p>${['violet', 'teal', 'coral'].map(a => fig(kind, `${title.split(' —')[0]} · Akzent ${ACC[a]} · hell`, `04-wealth-${v}-${a}@1280`)).join('')}</section>`;
  const head = `<div class="mock-pickbar">
    <p><b>The owner's complaint:</b> with the teal accent the unsigned figures are teal (<code>#0f766e</code>) and the gains another green (<code>#047857</code>), two greens on one card; with coral, a coral total beside a red loss (<code>#b91c1c</code>). Today's rule (DESIGN.md, stat-card <code>value-color</code>): a KPI value takes the active accent, except signed money, which takes <code>--color-positive</code>/<code>--color-danger</code>.</p>
    <p><b>Q7 — C</b>: the accent is for controls only. Unsigned figures take <code>--color-text</code>; a signed figure takes gain = brand teal, loss = brand coral, whatever the accent; <code>--color-positive</code> and <code>--color-danger</code> become aliases of those, so the app has one green and one red. A comment „Q7 A“ or „Q7 B“ flips it.</p>
  </div>`;
  const desk = `
<section class="mock-board">
  <h2>Heute — die Regel, wie sie gebaut ist <small>Vermögen → Bestände (Kennzahlen, Positionen mit G&amp;V) · Übersicht → Kennzahlen-Leiste</small></h2>
  <p class="mock-note">Captured as shipped on the review seed (positions cut to two gains and two losses, the value columns switched on in the browser's column preference). The Overview's strip already shows unsigned figures in <code>--color-text</code>, against DESIGN.md's rule; Wealth's cards follow the rule (<code>.stat strong</code> takes the accent).</p>
  ${['violet', 'teal', 'coral'].map(a => fig('before', `Heute · Akzent ${ACC[a]} · hell${a === 'teal' ? ' — zwei Grüne' : a === 'coral' ? ' — Koralle neben Rot' : ''}`, `04-wealth-today-${a}@1280`)).join('')}
  ${fig('before', 'Heute · Akzent Teal · dunkel', '04-wealth-today-teal-dark@1280')}
</section>
${variant('a', 'alt', 'Variante A — Gewinn immer Teal, Verlust immer Koralle', 'Owner option 1. Signed figures take brand teal and brand coral whatever the accent; unsigned KPI values keep the active accent. <b>Under the teal accent the total is teal and the gain is teal</b>: the two greens become one, but then a total reads as a gain. Under coral the total reads as a loss. Under violet it works.')}
${variant('b', 'alt', 'Variante B — jede Zahl im Akzent', 'Owner option 2. No gain/loss colour: every figure in the active accent, the sign carried by its +/− glyph alone. One colour on the card, but a loss of -975,15 reads in the same colour as a gain, and under coral every gain is red-ish; the colour no longer helps the scan the table exists for.')}
<section class="mock-board">
  <h2>Variante C (empfohlen) — der Akzent nur für Bedienelemente <small>Vermögen → Bestände</small></h2>
  <p class="mock-note">Unsigned figures in <code>--color-text</code>, a gain in brand teal, a loss in brand coral, under every accent. <b>Where C still collides, honestly:</b> under the teal accent the active tab, links and buttons are teal beside teal gains, and under coral they are coral beside coral losses. The collision moves from figure-against-figure to control-against-figure: a control is told apart by its shape (underline, button frame, link underline), and no figure is accent-coloured any more.</p>
  ${['violet', 'teal', 'coral'].map(a => fig('after', `C · Akzent ${ACC[a]} · hell${a === 'teal' ? ' — der aktive Tab teal wie der Gewinn' : a === 'coral' ? ' — der aktive Tab koralle wie der Verlust' : ''}`, `04-wealth-c-${a}@1280`)).join('')}
  ${fig('after', 'C · Akzent Teal · dunkel', '04-wealth-c-teal-dark@1280')}
  ${fig('after', 'C · Akzent Koralle · dunkel', '04-wealth-c-coral-dark@1280')}
</section>
<section class="mock-board">
  <h2>Die Kennzahlen-Leiste der Übersicht <small>Akzent Teal, jede Variante</small></h2>
  ${fig('before', 'Heute · Teal · hell', '04-strip-today-teal@1280')}
  ${fig('alt', 'A · Teal · hell', '04-strip-a-teal@1280')}
  ${fig('alt', 'B · Teal · hell — jede Zahl teal', '04-strip-b-teal@1280')}
  ${fig('after', 'C · Teal · hell', '04-strip-c-teal@1280')}
  ${fig('before', 'Heute · Teal · dunkel', '04-strip-today-teal-dark@1280')}
  ${fig('after', 'C · Teal · dunkel', '04-strip-c-teal-dark@1280')}
</section>
<section class="mock-board">
  <h2>Kontrast und Vorzeichen</h2>
  <p class="mock-note">WCAG 2.x ratios computed from the tokens in <code>priv/static/app.css</code> by the method of <code>test/invariants/css_accent_contrast_test.exs</code> (a translucent tint composited over the panel colour). Bar 4.5:1 for body text. „Problem-Tönung“ is <code>--color-danger-soft</code>, the ground C's coral takes in a problem note.</p>
  <table class="mock-rules"><thead><tr><th>Thema</th><th>Farbe</th><th>Wert</th><th>auf --color-bg</th><th>auf --color-bg-elevated</th><th>auf Problem-Tönung</th></tr></thead><tbody>${crow}</tbody></table>
  <div class="mock-why">
    <p><b>The sign is never colour alone.</b> Every signed figure on these frames carries its glyph: „+9,0%“, „+7.348,65“, „+75,00“, „-975,15“ (the cards' sub-line too); B leans on that alone, A and C add colour on top. An unsigned figure has no colour to read under C, so it cannot be mistaken for a gain.</p>
    <p><b>Q7, recommended C.</b> (1) <b>One green, one red</b>: the two greens and the two reds disappear under every accent, which A achieves only for signed figures and B by dropping colour from the sign. (2) <b>The accent keeps one job</b>, „you can act here“, so a teal total no longer reads like a teal gain or a teal link. (3) <b>The brand colours carry the meaning</b> and already pass 4.5:1 on every surface (table above, and the invariant test pins them for the accent use). (4) The strip already does it: the Overview's KPI strip shows unsigned figures in the text colour today. Cost: C recolours every consumer of <code>--color-positive</code>/<code>--color-danger</code> (README lists them), and DESIGN.md's stat-card rule changes.</p>
  </div>
</section>`;
  const phone = `
<section class="mock-board"><h2>Heute</h2>${fig('before', 'Heute · Teal · hell', '04-wealth-today-teal@390')}${fig('before', 'Heute · Teal · dunkel', '04-wealth-today-teal-dark@390')}</section>
<section class="mock-board"><h2>C (empfohlen)</h2>${['violet', 'teal', 'coral'].map(a => fig('after', 'C · ' + ACC[a] + ' · hell', `04-wealth-c-${a}@390`)).join('')}${fig('after', 'C · Teal · dunkel', '04-wealth-c-teal-dark@390')}${fig('after', 'C · Teal · hell — Kennzahlen-Leiste', '04-strip-c-teal@390')}</section>`;
  return { head, desk, phone };
};

if (require.main === module) module.exports.main();
