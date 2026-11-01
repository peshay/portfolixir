// The board's layout and text. build.js captures the frames; this file puts
// them on the artboard with the anatomy legend and the rule table, and
// writes 01-i1.html (desktop frames, rendered at 1200 px) and 01-i1-390.html
// (the same pages at 390 px).
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const B = require('./build.js');

const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

const BOARD_CSS = `
/* Artboard chrome only; everything inside a frame is priv/static/app.css. */
body { margin: 0; padding: 24px; background: var(--color-bg); color: var(--color-text); font-family: var(--font-sans); }
.mock-board { max-width: 1120px; margin: 0 auto 36px; overflow-x: clip; }
.mock-board > h2 { margin: 0 0 4px; font-size: 16px; font-weight: 760; }
.mock-board > h2 small { font-weight: 500; color: var(--color-text-muted); margin-left: 6px; }
.mock-board > p.mock-note, .mock-board li { font-size: 12.5px; color: var(--color-text-muted); max-width: 86ch; line-height: 1.5; }
.mock-board > p.mock-note { margin: 0 0 12px; }
.mock-board > p.mock-note b, .mock-board li b { color: var(--color-text); }
.mock-head h1 { margin: 0 0 6px; font-size: 20px; }
.mock-pickbar { margin: 0 0 16px; padding: 10px 14px; border: 1px solid var(--color-accent); border-left-width: 4px; border-radius: var(--radius-md); background: var(--color-accent-soft); font-size: 12.5px; line-height: 1.5; }
.mock-pickbar p { margin: 0 0 6px; } .mock-pickbar p:last-child { margin: 0; }
.mock-legend { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 6px 24px; margin: 0; padding: 0; list-style: none; }
.mock-legend li { display: flex; gap: 8px; align-items: flex-start; }
.mock-fig { margin: 0 0 18px; }
.mock-tag { display: inline-block; margin: 0 0 6px; padding: 2px 10px; border-radius: 999px; font-size: 11px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; }
.mock-tag--before { color: var(--color-danger); background: var(--color-danger-soft); }
.mock-tag--after { color: var(--color-positive); background: #ecfdf5; }
.mock-frame { width: max-content; max-width: 100%; border: 1px solid var(--color-border-strong); border-radius: 10px; background: var(--color-bg); overflow: hidden; box-shadow: var(--shadow-panel); }
.mock-frame--open { overflow: visible; }
.mock-app { width: 1060px; position: relative; }
.mock-app .topbar { position: relative; top: auto; }
.mock-app .app-main, .mock-app .workspace-page { min-height: 0; }
.mock-board q { quotes: "„" "“"; }
.mock-offscreen { width: 1060px; display: flex; align-items: flex-start; justify-content: flex-end; box-sizing: border-box; padding: 6px 10px; border: 1px dashed var(--color-border-strong); border-bottom: 0; border-radius: 10px 10px 0 0; background: repeating-linear-gradient(135deg, transparent 0 8px, rgba(148,163,184,.18) 8px 16px); font-size: 11px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; color: var(--color-text-muted); }
.mock-elided { margin: 8px 0; padding: 6px 10px; border: 1px dashed var(--color-border-strong); border-radius: 6px; font-size: 11.5px; color: var(--color-text-muted); list-style: none; text-align: center; }
tr.mock-elided td { padding: 6px 10px; font-size: 11.5px; color: var(--color-text-muted); text-align: center; }
.mock-legend .mock-pin { margin: 0; }
table.mock-rules { width: 100%; border-collapse: collapse; font-size: 12.5px; background: var(--color-bg-elevated); border: 1px solid var(--color-border); border-radius: var(--radius-md); }
table.mock-rules th { text-align: left; font-size: 11px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; color: var(--color-text-muted); background: var(--color-bg-muted); padding: 8px 10px; }
table.mock-rules td { padding: 9px 10px; border-top: 1px solid var(--color-border); vertical-align: top; line-height: 1.45; }
table.mock-rules td:first-child { font-weight: 700; white-space: nowrap; }
table.mock-rules q { quotes: "„" "“"; color: var(--color-text); }
table.mock-rules small { display: block; color: var(--color-text-muted); }
.mock-cols { columns: 2; column-gap: 28px; }
.mock-cols li { break-inside: avoid; margin-bottom: 4px; }
/* The phone board: the frames are the 390 px viewport. */
body.mock-phone { padding: 16px 0; }
body.mock-phone .mock-board > :not(.mock-fig), body.mock-phone .mock-head, body.mock-phone .mock-fig > .mock-tag { margin-left: 16px; margin-right: 16px; }
body.mock-phone .mock-fig > .mock-tag { margin-left: 16px; }
body.mock-phone .mock-frame { width: 100%; border-radius: 0; border-left: 0; border-right: 0; }
body.mock-phone .mock-app, body.mock-phone .mock-offscreen { width: 100%; }
body.mock-phone .mock-offscreen { border-radius: 0; border-left: 0; border-right: 0; }
body.mock-phone .mock-legend { grid-template-columns: 1fr; }
body.mock-phone .mock-cols { columns: 1; }
body.mock-phone table.mock-rules, body.mock-phone table.mock-rules tbody, body.mock-phone table.mock-rules tr, body.mock-phone table.mock-rules td { display: block; }
body.mock-phone table.mock-rules thead { display: none; }
body.mock-phone table.mock-rules td { border-top: 0; padding: 4px 12px; }
body.mock-phone table.mock-rules tr { border-top: 1px solid var(--color-border); padding: 6px 0; }
`;

const LEGEND = [
  ['①', '<b>Section ⓘ.</b> The section\'s method sentences — how a figure is computed, what a term means — leave the page and sit in one ⓘ beside the heading, one source line per line (the existing <code>details.metric-tooltip</code>, label „Zu diesem Abschnitt“). A facet that already has an ⓘ on its basis line takes them there.'],
  ['②', '<b>The basis line stays.</b> View, period, currency, as-of, gross/net, the set of rows and a threshold stay visible (UX-DR11: every number states its basis). Only the method clauses of a line move; a line that already ends in its own ⓘ stays whole.'],
  ['③', '<b>A clamped data note.</b> Two lines, three under 560 px; „mehr“ only where the text is cut. A remedy control (button, disclosure) stays visible under the text. A note that names rows left out of a total keeps its count in its first line; the names are one tap away (UX-DR25 as the owner amended it on 2026-11-01).'],
  ['④', '<b>Folded notes.</b> Two or more attention/note items in one block that do not name excluded rows fold into one line with their counts, at the highest folded severity: „1 Achtung · 1 Hinweis — Details anzeigen“.'],
  ['⑤', '<b>Problems stay visible.</b> A problem never folds and leads its block; it clamps like every note.'],
  ['⑥', '<b>#1350.</b> The view switcher\'s ⓘ is a <code>metric-tooltip</code>: its panel floats below the switcher instead of opening as a paragraph that pushes the KPI cards down.'],
  ['⑦', '<b>#1336.</b> An ⓘ panel opens upward unless there is no room above, then below; it is shifted so both edges stay 1 rem inside the viewport. A small hook measures on toggle (data-place, --tip-shift).'],
  ['⑧', '<b>#1342, no picture.</b> Escape closes an open ⓘ and returns focus to its summary — every ⓘ on this board, the section ⓘ and the view switcher\'s included. The Imports picker\'s (H45) hit count and „Kein Wertpapier passt.“ move into a <code>role="status"</code> region; that page is not drawn here.']
];

const RULES = [
  {
    cls: 'Problem', test: 'A data note at severity problem.',
    does: 'Always visible: never folds, leads its block, clamps like every note with „mehr“ where cut.',
    ex: [
      ['2 Anleihen sind auf zwei Skalen bepreist (Kurse um 100, gebuchter Preis je Stück um 1) und zählen hundertfach zu hoch in den Summen; …', 'Vermögen, Datenqualität'],
      ['Eine gehaltene Position wird mit Kursen bewertet, die nicht zu ihren eigenen Buchungen passen …', 'Vermögen, Datenqualität'],
      ['29 Wertpapiere im Katalog ohne Kurs seit 7 Tagen · eins ohne Anlageklasse · 47 ohne Logo · …', 'Übersicht, Datenqualität']
    ]
  },
  {
    cls: 'Basis clause', test: 'Names a parameter the figure was computed with — view, period or window, currency, as-of or computed-at, gross/net, the set of rows or depots, a threshold. It would read differently if the operator chose another parameter, not if the data changed.',
    does: 'Stays visible as the basis line. A clause that mixes a parameter with a method word stays whole: hiding the parameter would break UX-DR11.',
    ex: [
      ['Ansicht Alles · Rendite über 1J bis 01.11.2026 · in EUR · Kurse: der neueste über die gehaltenen Positionen', 'Übersicht, Kennzahlen-Leiste (ends in its own ⓘ, stays whole)'],
      ['FIFO über alle Depots, unabhängig von der Ansicht', 'Übersicht, Abgeschlossene Trades'],
      ['Gebühren und Steuern in Einstand und Erlös · Erträge während der Haltedauer nicht enthalten', 'Cashflow, Trades (gross/net)'],
      ['Datierte Fakten zu jedem Wertpapier im Katalog — gehalten oder nicht —, die in den nächsten 30 Tagen anstehen.', 'Übersicht, Fällig (set and window)'],
      ['Kategorien, die mehr als ±5 pp von ihrem Soll-Gewicht abweichen.', 'Übersicht, Ziel-Abweichungen (threshold)']
    ]
  },
  {
    cls: 'Data fact', test: 'Changes when the stored records change: a count, a name, an amount, a record\'s date, a yes/no.',
    does: 'Inside a data note: clamps; folds when two or more attention/note items share a block — unless the note names rows left out of a total (UX-DR25), which only clamps. Outside a note (a .hint, a .muted, a table cell, a row): stays where it is.',
    ex: [
      ['Nicht in der Summe: 3 Verrechnungskonten ohne Wechselkurs zu EUR — USD Settlement (1.850,00 USD), …', 'Übersicht, value card (excluded rows: clamps, never folds)'],
      ['11 gehaltene Positionen werden zum letzten Handelspreis bewertet, die Gesamtsumme ist daher nicht aktuell: …', 'Vermögen, Datenqualität (folds)'],
      ['2 gehaltene Positionen werden mit Kursen bewertet, die älter als 7 Tage sind; …', 'Vermögen, Datenqualität (folds)']
    ]
  },
  {
    cls: 'Method sentence', test: 'True on any instance with any data: how a figure is computed, what a term means, what a control does.',
    does: 'Moves into the section\'s ⓘ — the heading\'s, or the facet\'s where the section has no heading. Exception: a sentence inside a note that says why its remedy can or cannot act stays in the note (UX-DR25 clause 3) and clamps with it.',
    ex: [
      ['Beitrag = Endwert − Anfangswert − Zu-/Abflüsse + Erträge − Kosten · Anfangswert: der Schluss des Vortags', 'Vermögen, Beitrag je Position'],
      ['p. a. erst ab 365 Tagen Haltedauer und nur, wo ein Zinssatz die Zahlungen löst', 'Übersicht, Abgeschlossene Trades; Cashflow, Trades'],
      ['Ein als Zeitraum oder Monat angegebener Termin gilt als fällig, sobald irgendein Tag, auf den er fallen kann, im Horizont liegt.', 'Übersicht, Fällig'],
      ['Einlieferungen eröffnen keinen Lot', 'Cashflow, Trades']
    ]
  }
];

const KEEP = [
  ['Wieder eingespielt? Ja', 'Snapshots, comparison — <code>small.hint[cost-recovery]</code>'],
  ['Buy-and-hold der am 03.08.2026 eingefrorenen Bestände: 47.301,57 → 47.834,43 EUR', 'Snapshots, comparison — <code>small.hint</code>'],
  ['netto, alle Kosten enthalten · Gebühren und Steuern auf Handelsgeschäfte ausgenommen', 'Snapshots, comparison — <code>small.hint</code>, basis of a stat'],
  ['31.12.2025 · Steuerjahr 2025 · erfasst · Erfasst von: Agent', 'Steuern, recorded statements — <code>span.hint</code>'],
  ['Steuerfreier Verkaufsspielraum bei diesem Institut: 0,00.', 'Steuern, recorded statements — a figure in <code>p.summary-basis</code>'],
  ['Freistellungsauftrag 640,00 von 1.000,00 verbraucht · Stand 31.12.2025 · …', 'Steuern, budget — <code>[budget-basis]</code>'],
  ['netto 120,00', 'Cashflow, Erträge, Top-Beiträge — <code>span.muted</code>'],
  ['Standard-Ansicht', 'Vermögen, view switcher — <code>span.hint[default-view-marker]</code>'],
  ['Σ Soll oberste Ebene: 105,0%', 'Allokation — a figure in <code>[allocation-basis]</code>'],
  ['Broker Nord Verrechnung, Broker Süd Verrechnung, …', 'Ansichten, Buckets — the account names in <code>[assignment-basis]</code>; its first sentence is a method sentence'],
  ['Anlageklasse Fonds', 'Wertpapier, Überblick — <code>[overview-basis]</code>'],
  ['am Ende nicht mehr im Bestand · zu Beginn nicht im Bestand', 'Vermögen, Beitrag je Position — row text; nothing in a table or a row moves']
];

const FOUND = [
  '<b>Excluded rows never fold</b> (default; a comment „fold them too“ flips it to the prototype). R folded every attention note; on Cash flow → Trades that hid both exclusion notes behind „2 Achtung“, and on Wealth three of the four. The owner\'s decision keeps the count of excluded rows visible, so a note that names rows left out of a total only clamps. Wealth\'s fold therefore reads „1 Achtung · 1 Hinweis“, not the prototype\'s „4 Achtung · 1 Hinweis“.',
  '<b>Remedy controls stay visible under the clamp</b> (default). R clamped the whole note body, which hid „Wechselkurse synchronisieren“ and „Historische Wechselkurse nachladen“ behind „mehr“; the note\'s text clamps, its button or disclosure does not (UX-DR17 clause 3, the remedy is a child of the note).',
  '<b>The prototype decided by clause length</b> (42 characters); the build decides per text by the table below. Two lines the length rule would have hidden stay: Fällig\'s first sentence (the set and the window) and the threshold of Ziel-Abweichungen.',
  '<b>The section ⓘ panel is wider</b> (26 rem, still 1 rem inside a phone screen) because it holds several lines; a term\'s ⓘ keeps 18 rem.'
];

function rulesHtml() {
  const rows = RULES.map(r => `<tr><td>${r.cls}</td><td>${r.test}</td><td>${r.does}</td><td>${r.ex.map(([q, w]) => `<q>${esc(q)}</q><small>${w}</small>`).join('')}</td></tr>`).join('\n');
  return `<table class="mock-rules"><thead><tr><th>Class</th><th>Test, in this order</th><th>What the build does</th><th>Real examples (review seed, German UI)</th></tr></thead><tbody>${rows}</tbody></table>`;
}

function frame(kind, label, inner, opts = {}) {
  const off = opts.offscreen ? `<div class="mock-offscreen" style="height:${opts.offscreen}px">outside the screen</div>` : '';
  return `<figure class="mock-fig"><figcaption class="mock-tag mock-tag--${kind}">${label}</figcaption>${off}<div class="mock-frame${opts.offscreen ? ' mock-frame--open' : ''}"><div class="mock-app">${inner}</div></div></figure>`;
}

function page(vw, F) {
  const phone = vw < 600;
  const w = phone ? '390 px' : '1280 px window (main 1060 px)';
  const cashBeforeTop = F.cash.before.facts['[data-role="facet-info"]'];
  const off = cashBeforeTop && cashBeforeTop.top < 0 ? Math.ceil(-cashBeforeTop.top) + 14 : 0;
  const cashAfter = F.cash.after.facts['[data-role="facet-info"]'] || {};
  const legend = LEGEND.map(([n, t]) => `<li><span class="mock-pin">${'①②③④⑤⑥⑦⑧'.indexOf(n) + 1}</span><span>${t}</span></li>`).join('\n');
  return `<!doctype html>
<html lang="en" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mockup — I1: explanations behind a section ⓘ, data notes clamped and folded (#1351, #1350, #1336, #1342)${phone ? ' — 390 px' : ''}</title>
<link rel="stylesheet" href="../../../../../priv/static/app.css">
<!-- Generated by build.js from the running app on the synthetic review seed.
     "Before" frames are the shipped markup; "After" frames are the same
     markup with the variant-R change applied as markup. The proposal block
     below is what the story adds to priv/static/app.css; the board block
     after it is artboard chrome only. No script runs on this page. -->
<style id="proposal">${B.PROPOSAL_CSS}</style>
<style id="board">${BOARD_CSS}${B.PIN_CSS}</style>
</head>
<body class="${phone ? 'mock-phone' : ''}" data-widths="${phone ? '390' : '1200'}">
<div class="mock-board mock-head">
  <h1>I1 — explanations behind a section ⓘ, data notes clamped and folded <small>#1351, with #1350, #1336, #1342 · ${w}</small></h1>
  <div class="mock-pickbar">
    <p><b>The pick is made:</b> variant R of the I1 prototype (<code>ux-design-2026-11-01-i1/proposal.js</code>), adopted by the owner on 2026-11-01. No other variant is drawn. This board draws R on the shipped markup of three pages, before and after, with the classification the build uses per text.</p>
    <p><b>Two corrections, found while drawing, are the default unless a comment flips them:</b> a note that names rows left out of a total never folds, it only clamps; and a note's remedy control stays visible under the clamp. Synthetic data only (review seed).</p>
  </div>
  <ul class="mock-legend">${legend}</ul>
</div>

<section class="mock-board">
  <h2>Vermögen <small>/portfolio, above the positions table</small></h2>
  <p class="mock-note">Before: the view switcher's ⓘ is open and lays its text out as a paragraph under the switcher (#1350); eight notes stack in Datenqualität; the contribution's method sentences sit under its table. After: the ⓘ floats (⑥); the three problems lead (⑤), the three notes that name rows left out of the totals clamp (③), the two others fold (④); the contribution's formula and its two rules move into the ⓘ beside „Beitrag je Position“ (①) while „je Position in EUR, einschließlich der Währungsbewegung“ stays (②). The second row of KPI cards, the chart, all but three contribution rows and the rows that belong to no position are cut in both frames.</p>
  ${frame('before', 'Before — shipped' + (phone ? ', 390 px' : ''), F.wealth.before.html)}
  ${frame('after', 'After — R' + (phone ? ', 390 px' : ''), F.wealth.after.html)}
</section>

<section class="mock-board">
  <h2>Übersicht <small>/</small></h2>
  <p class="mock-note">After: the value card's note keeps „Nicht in der Summe: 3 Verrechnungskonten …“ in its first line and clamps the names (③); the KPI strip's basis line already ends in its own ⓘ and stays whole (②). „Abgeschlossene Trades“ keeps its basis „Die 5 zuletzt abgeschlossenen · Ergebnis in EUR · FIFO über alle Depots, unabhängig von der Ansicht“ (②) and its p. a. rule moves into the ⓘ, drawn open (①). „Fällig“ keeps its first sentence, the set and the window, and its second moves (①). The data-quality line is a problem and stays (⑤). Lists are cut in both frames; Ziel-Abweichungen does not change.</p>
  ${frame('before', 'Before — shipped' + (phone ? ', 390 px' : ''), F.overview.before.html)}
  ${frame('after', 'After — R' + (phone ? ', 390 px' : ''), F.overview.after.html)}
</section>

<section class="mock-board">
  <h2>Cashflow → Trades <small>/cashflow?tab=realized, the facet ⓘ opened</small></h2>
  <p class="mock-note">Before: the facet's ⓘ panel opens upward from a line near the top of the page, so it starts ${cashBeforeTop ? Math.round(-cashBeforeTop.top) : '?'} px above the screen${phone ? ` and runs to x = ${Math.round(cashBeforeTop.right)} on a 390 px screen` : ''} (#1336); the hatched band is what cannot be read. After: with no room above it opens below${cashAfter.shift ? `, shifted ${cashAfter.shift} px to stay inside the screen` : ''} (⑦), and it now also holds the method clauses of the trades' basis line, „Einlieferungen eröffnen keinen Lot“ and the p. a. rule (①). The two exclusion notes clamp and keep their buttons (③); the gross/net clauses stay under the table (②). The three figures, all but one trade and the sections below are cut in both frames.</p>
  ${frame('before', 'Before — shipped' + (phone ? ', 390 px' : ''), F.cash.before.html, { offscreen: off })}
  ${frame('after', 'After — R' + (phone ? ', 390 px' : ''), F.cash.after.html)}
</section>

<section class="mock-board">
  <h2>How the build classifies a text</h2>
  <p class="mock-note">Per text, not per CSS class: <code>.hint</code>, <code>.muted</code> and <code>.summary-basis</code> carry all four classes today. The tests run top to bottom; the first that holds decides. Anything inside a table, a row, a form's field help or a dialog is out of scope and does not move.</p>
  ${rulesHtml()}
  <p class="mock-note" style="margin-top:14px"><b><code>.hint</code> / <code>.muted</code> / basis texts that carry data facts and must NOT move</b> (scanned on every page of the review seed):</p>
  <ul class="mock-cols">${KEEP.map(([q, w]) => `<li><q>${esc(q)}</q> — ${w}</li>`).join('\n')}</ul>
</section>

<section class="mock-board">
  <h2>Found while drawing</h2>
  <ul>${FOUND.map(f => `<li>${f}</li>`).join('\n')}</ul>
</section>
</body>
</html>
`;
}

async function main() {
  const browser = await chromium.launch();
  for (const [vw, file] of [[1280, '01-i1.html'], [390, '01-i1-390.html']]) {
    const F = await B.framesAt(browser, vw);
    // Trailing whitespace and blank runs from the captured markup are dropped (pre-commit).
    fs.writeFileSync(path.join(__dirname, file), page(vw, F).split('\n').map(l => l.replace(/[ \t]+$/, '')).filter((l, i, a) => l !== '' || a[i - 1] !== '').join('\n'));
    console.log('wrote', file);
  }
  await browser.close();
}

module.exports = { main };
