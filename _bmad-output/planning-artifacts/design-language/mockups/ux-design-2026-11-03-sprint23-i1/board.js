// The board's layout and text. build.js captures the frames; this file puts
// them on the artboard with the anatomy legend, writes 01-i1-later.html
// (desktop frames, rendered at 1200 px) and 01-i1-later-390.html (the same
// frames at 390 px). With FRAMES_CACHE=<file outside the repository> the
// captured frames are kept there, and `node board.js` rebuilds the boards
// from them without the server.
const fs = require('fs');
const path = require('path');
const B = require('./build.js');

// The frames whose After draws an ⓘ open (build.js opens and places it).
const OPENED = new Set(B.FRAMES.filter(f => f.open).map(f => f.key));

const BOARD_CSS = `
/* Artboard chrome only; everything inside a frame is priv/static/app.css. */
body { margin: 0; padding: 24px; background: var(--color-bg); color: var(--color-text); font-family: var(--font-sans); }
.mock-board { max-width: 1120px; margin: 0 auto 36px; overflow-x: clip; }
.mock-board > h2 { margin: 0 0 4px; font-size: 16px; font-weight: 760; }
.mock-board > h2 small { font-weight: 500; color: var(--color-text-muted); margin-left: 6px; }
.mock-board > h3 { margin: 18px 0 4px; font-size: 13.5px; font-weight: 720; }
.mock-board > h3 small { font-weight: 500; color: var(--color-text-muted); margin-left: 6px; }
.mock-board > p.mock-note, .mock-board li { font-size: 12.5px; color: var(--color-text-muted); max-width: 92ch; line-height: 1.5; }
.mock-board > p.mock-note { margin: 0 0 12px; }
.mock-board > p.mock-note b, .mock-board li b { color: var(--color-text); }
.mock-head h1 { margin: 0 0 6px; font-size: 20px; }
.mock-head h1 small { font-size: 13px; font-weight: 500; color: var(--color-text-muted); margin-left: 6px; }
.mock-pickbar { margin: 0 0 16px; padding: 10px 14px; border: 1px solid var(--color-accent); border-left-width: 4px; border-radius: var(--radius-md); background: var(--color-accent-soft); font-size: 12.5px; line-height: 1.5; }
.mock-pickbar p { margin: 0 0 6px; } .mock-pickbar p:last-child { margin: 0; }
.mock-legend { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 6px 24px; margin: 0; padding: 0; list-style: none; }
.mock-legend li { display: flex; gap: 8px; align-items: flex-start; }
.mock-pair { display: grid; grid-template-columns: 1fr; gap: 0; }
.mock-fig { margin: 0 0 18px; }
.mock-tag { display: inline-block; margin: 0 0 6px; padding: 2px 10px; border-radius: 999px; font-size: 11px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; }
.mock-tag--before { color: var(--color-danger); background: var(--color-danger-soft); }
.mock-tag--after { color: var(--color-positive); background: #ecfdf5; }
.mock-frame { width: max-content; max-width: 100%; border: 1px solid var(--color-border-strong); border-radius: 10px; background: var(--color-bg); overflow: hidden; box-shadow: var(--shadow-panel); }
.mock-frame--open { overflow: visible; }
.mock-app { width: 1060px; position: relative; }
.mock-app .topbar { position: relative; top: auto; }
.mock-app .app-main, .mock-app .workspace-page, .mock-app .workspace-panel { min-height: 0; height: auto; max-height: none; overflow: visible; }
.mock-app .securities-workspace--split { grid-template-rows: auto; }
.mock-board q { quotes: "„" "“"; }
.mock-elided { margin: 8px 0; padding: 6px 10px; border: 1px dashed var(--color-border-strong); border-radius: 6px; font-size: 11.5px; color: var(--color-text-muted); list-style: none; text-align: center; }
tr.mock-elided td { padding: 6px 10px; font-size: 11.5px; color: var(--color-text-muted); text-align: center; }
.mock-gone { margin: 4px 0; padding: 4px 8px; border: 1px dashed var(--color-positive); border-radius: 6px; font-size: 11.5px; color: var(--color-text-muted); text-decoration: line-through; text-decoration-color: var(--color-text-muted); }
.mock-legend .mock-pin { margin: 0; }
table.mock-rules { width: 100%; border-collapse: collapse; font-size: 12px; background: var(--color-bg-elevated); border: 1px solid var(--color-border); border-radius: var(--radius-md); margin: 0 0 14px; }
table.mock-rules th { text-align: left; font-size: 11px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; color: var(--color-text-muted); background: var(--color-bg-muted); padding: 7px 10px; }
table.mock-rules td { padding: 7px 10px; border-top: 1px solid var(--color-border); vertical-align: top; line-height: 1.45; }
table.mock-rules td:first-child { font-weight: 700; white-space: nowrap; }
table.mock-rules q { quotes: "„" "“"; color: var(--color-text); }
.mock-cols { columns: 2; column-gap: 28px; }
.mock-cols li { break-inside: avoid; margin-bottom: 4px; }
/* The phone board: the frames are the 390 px viewport. */
body.mock-phone { padding: 16px 0; }
body.mock-phone .mock-board > :not(.mock-fig), body.mock-phone .mock-head, body.mock-phone .mock-fig > .mock-tag { margin-left: 16px; margin-right: 16px; }
body.mock-phone .mock-frame { width: 100%; border-radius: 0; border-left: 0; border-right: 0; }
body.mock-phone .mock-app { width: 100%; }
body.mock-phone .mock-legend { grid-template-columns: 1fr; }
body.mock-phone .mock-cols { columns: 1; }
body.mock-phone table.mock-rules, body.mock-phone table.mock-rules tbody, body.mock-phone table.mock-rules tr, body.mock-phone table.mock-rules td { display: block; }
body.mock-phone table.mock-rules thead { display: none; }
body.mock-phone table.mock-rules td { border-top: 0; padding: 3px 12px; }
body.mock-phone table.mock-rules tr { border-top: 1px solid var(--color-border); padding: 5px 0; }
`;

const LEGEND = [
  ['①', '<b>Section ⓘ</b> (Sprint 22 ①, <code>AppShell.section_info</code>). A section\'s method sentences leave the page for one ⓘ beside its heading, label „Zu diesem Abschnitt“, one source line per line. <b>New here:</b> a section with no heading (the security page\'s Chart, Kurse, Research and Termine tabs) ends its kept basis line in that ⓘ, as a facet\'s basis line does on Cash flow.'],
  ['②', '<b>The basis line stays</b> (UX-DR11): view, period, currency, as-of, gross/net, the set of rows, a threshold. Only a line\'s method parts move; a mixed clause stays whole.'],
  ['③', '<b>Clamped data note</b> (Sprint 22 ③, <code>data_note clamp</code>): two lines, three under 560 px, „mehr“ only where cut. Its remedy control — a button, a disclosure, a link — sits in the note\'s actions below the text, never under the clamp.'],
  ['④', '<b>Folded notes</b> (Sprint 22 ④): two or more attention/note items in one block that name no excluded rows. <b>None of these nine pages has such a block on the review seed</b>, so nothing folds here.'],
  ['⑤', '<b>Problems lead</b> and never fold; they clamp like every note.'],
  ['⑥', '<b>New: a method line the heading\'s ⓘ already says leaves without a copy.</b> Views: „Gespeicherte Ein-/Ausschlussfilter über Buckets …“ and „Überlappende Tags … · Werte je Bucket sind keine Summe“ restate the ⓘ beside „Ansichten“ and „Buckets“ in meaning; nothing is appended. On Income the definition of a missing rate is what the facet\'s ⓘ already says.'],
  ['⑦', '<b>#1339.</b> „Daten als Tabelle“ on Wealth\'s Allokation and the matched-securities list on Imports take an <code>id</code> and <code>phx-hook="DisclosureState"</code>, so a LiveView patch no longer folds them shut. No pixel changes except that the disclosure stays open.'],
  ['⑧', '<b>A count leads.</b> Snapshots\' gaps note gains its count (UX-DR25 under the clamp: every count in the first line). Income: with two or more reasons the lead carries every count once and each reason names its sales without a second count (#1359\'s count-lead line).'],
  ['⑨', '<b>#1362\'s S2 line.</b> A category whose members are not all priced shows the sum of the priced ones and names how many it leaves out („ohne 1 Position“), as the category result\'s API read does (ADR-0041 §5), instead of „—“.']
];

const PAGES = [
  {
    h: 'Vermögen → Allokation', sub: '/portfolio?tab=allocation',
    note: 'The section has no method sentence outside a table, a disclosure or an existing ⓘ: the basis line „Plan auf Strategies · Σ Soll oberste Ebene: 105,0% · Ansicht Alles · Stand …“ is parameters and a data fact and stays whole (②). The one note on the seed, the plan overshoot, clamps (③); its remedy link „den Plan auf der Klassifizierungsseite kürzen.“ was the end of the sentence, so it leaves the sentence for the note\'s actions as „Plan auf der Klassifizierungsseite kürzen“ and the sentence ends with a full stop (two new strings). The target-conflict and stale-target notes (not on the seed) take the same treatment.',
    frames: ['alloc']
  },
  {
    h: 'Vermögen → Allokation, #1339', sub: '„Daten als Tabelle“ after „Alle aufklappen“',
    note: 'Before: the disclosure was opened and „Alle aufklappen“ pressed; the server\'s patch removed the <code>open</code> the browser had set, so the table the operator was working in folded shut (captured, not drawn). After: <code>id="allocation-disclosure"</code> with the shell\'s <code>DisclosureState</code> hook restores it after the patch, with the categories expanded (⑦). All but six rows are cut.',
    frames: ['alloc1339']
  },
  {
    h: 'Wertpapier → Überblick', sub: '/securities/50, Tamarisk Systems Inc.',
    note: 'The problem note „Kurs passt nicht zu den Buchungen: …“ leads and clamps (⑤); its two remedy links „Kurse · Transaktionen“ move into its actions, so the clamp never hides them. „Anlageklasse Aktie“ is a data fact and stays (must-not-move list).',
    frames: ['secOverview']
  },
  {
    h: 'Wertpapier → Trades', sub: '/securities/49, Arbolia Inc.',
    note: 'The trades\' basis line keeps „Über alle Depots · Gebühren und Steuern im G/V, nicht in Ø Kauf und Ø Verkauf · Erträge während der Haltedauer nicht enthalten“ (②); „Einlieferungen eröffnen keinen Lot“ and the p. a. rule move into a new ⓘ beside „Abgeschlossene Trades (FIFO)“ (①), drawn open in the After frame as Cash flow\'s are. The unavailable-trade note clamps (③); its „Abhilfe: …“ says where the remedy acts and stays in the note\'s text (Sprint 22\'s exception).',
    frames: ['secTrades']
  },
  {
    h: 'Wertpapier → Chart', sub: '/securities/49, the metrics under the chart',
    note: 'The metrics\' line keeps its first sentence, the input series and its currency (②). The gap rule, the volatility\'s formula and „Berichtet, nicht bewertet …“ are true for every security and move into an ⓘ that ends the kept line, because the tab has no heading (① as amended here). The window and the observation count stay in each metric\'s own sub-line.',
    frames: ['secChart']
  },
  {
    h: 'Wertpapier → Kurse', sub: '/securities/36, Harborline Freight Inc',
    note: 'The quotes\' line read „Kursbasis: wie erfasst.“ twice (found while drawing 3). It keeps it once (②); the two sentences about the „Gespeichert“ column move into the line\'s ⓘ (①). The manual-quote note clamps (③); „Ein manueller Kurs hat Vorrang …“ says why its remedy is needed and stays in its text; „Freigeben…“ sits in its actions. „Zeitraum 1J · wie im Diagramm“ stays.',
    frames: ['secQuotes']
  },
  {
    h: 'Wertpapier → Research und Termine', sub: '/securities/36',
    note: 'Each tab\'s line keeps its first sentence, the set (②): „Datierte, belegte Einträge zu diesem Wertpapier.“, „Datierte Kalenderfakten zu diesem Wertpapier.“ The rule after it — entries are never changed; a date books nothing — moves into the line\'s ⓘ (①). The Überblick\'s thesis and note panels, the Transaktionen, Bestände and Klassifizierungen tabs carry no text that moves (README).',
    frames: ['secResearch', 'secEvents']
  },
  {
    h: 'Income: Cashflow → Trades, Sprint 22 R5 re-read', sub: 'against board 02 ①d; #1359\'s two lines',
    note: 'Before: board 02 ①d — R5\'s three sentences (synthetic names) in the live note beside the seed\'s two reasons, expanded. Each reason repeats its count after the lead, and each carries a definition between dashes. After (R, flippable): the lead keeps every count, once (⑧); each reason names its sales without a count („Dritte Währung: Saltmarsh Mining plc.“); the definitions between the dashes are method — true on any instance — and four of them move into the facet\'s ⓘ after a blank line (①); the fifth, a missing rate, is what the ⓘ already says (⑥). The backfill\'s sentence says why its remedy can act and stays in the note, with its button, because the seed\'s two reasons are ones a rate fixes. One reason alone keeps today\'s sentence: there is no lead to repeat.',
    frames: ['income'], extra: [{ key: 'incomeTip', label: 'After — R, the facet\'s ⓘ opened', minHeight: 720 }]
  },
  {
    h: 'Income: R5\'s reasons alone', sub: '#1359: a remedy that cannot act',
    note: 'With only reasons no rate fixes, today\'s note still ends in the backfill\'s sentence and „Historische Wechselkurse nachladen“ (Before). After: the sentence and the button render only while a reason the backfill can fix is present (no stored rate; a buy without a figure in the sale\'s currency), so this note offers no remedy (UX-DR25 clause 3: none exists).',
    frames: ['incomeR5only']
  },
  {
    h: 'Snapshots', sub: '/snapshots, the comparison',
    note: 'The comparison\'s basis line keeps „seit 05.08.2026 · in EUR · brutto, nur Kursentwicklung“ (②); the definition „Transaktionskosten = …“ moves into a new ⓘ beside the heading (①). The note „Der Vergleich ist brutto und nur Kursentwicklung — Dividenden sind noch nicht enthalten.“ states no data fact — it is the method, partly a copy of the basis — so it leaves for the same ⓘ. The gaps note names the rows left out and gains its count (⑧, one new string), clamps and never folds (③). The stat hints („netto, alle Kosten enthalten“, the buy-and-hold figures, „Wieder eingespielt? Ja“) stay (must-not-move list).',
    frames: ['snapshots']
  },
  {
    h: 'Steuern', sub: '/tax',
    note: 'Both notes clamp (③) and keep their buttons in their actions: „Neue Abrechnung erfassen“, „Gegen die Abrechnung prüfen“. Every other text is a data fact („Freistellungsauftrag 640,00 von 1.000,00 verbraucht …“, „Steuerfreier Verkaufsspielraum bei diesem Institut: 0,00.“) or already behind the heading\'s ⓘ, and stays. The entry forms are cut.',
    frames: ['tax']
  },
  {
    h: 'Ansichten', sub: '/buckets',
    note: 'Both basis lines are method only and restate the ⓘ their headings already carry, so they leave with no copy (⑥). The assignment line stays whole: its first sentence is the pointer to the remedy („→ Konten &amp; Depots“) of the names after it, a data fact (must-not-move list).',
    frames: ['views']
  },
  {
    h: 'Klassifizierungen', sub: '/classifications/1, Asset class',
    note: 'The assignment nudge and the category result\'s exclusion note both name rows left out (of the allocation, of „Einstand“ and „Ergebnis“): they clamp and never fold (③); „Nicht zugeordnet“ and „Die 3 Positionen“ sit in their actions. The basis line ends in its own ⓘ and stays whole (②). #1362\'s S2 line: Equity and Bond read „—“; After they read the sum of their priced members, 14.897,35 for Bond as the API reports, with „ohne 1 Position“ (⑨, one new string). The member lists are cut.',
    frames: ['classif']
  },
  {
    h: 'Import (Vorschau)', sub: '/imports, the demo export previewed (nothing is stored before confirmation)',
    note: 'The two notes clamp (③): „Alle 12 Einträge sind bereits importiert …“ fits; the unconfigured-securities note keeps its title and sentence in the clamp and its two security links — where its remedy is made — in its actions. #1339 (⑦): the list „7 Wertpapiere passen zu bestehenden Einträgen“ is drawn closed in Before, as a patch leaves it (a mapping change), and open in After. „Quellformat: JSON“ stays.',
    frames: ['imports']
  },
  {
    h: 'Risiko', sub: '/risk',
    note: 'Three lines split by sentence. „Kennzahlen des Portfolios“ keeps „Grundlage: … in EUR, annualisiert mit √365 — eine Einzahlung ist keine Rendite.“ whole (it mixes the series and the currency with the method, ②) and moves the gap rule and the correlations\' rule into its ⓘ (①). „Anlageklassen-Obergrenzen“ keeps „Keine Obergrenze konfiguriert …“ and moves „Obergrenzen werden pro Abfrage über die API gesetzt.“ „Eigene Regeln“ keeps the as-of and the view and moves its two rule sentences. The stat sub-lines and the HHI scale stay.',
    frames: ['risk']
  }
];

const FOUND = [
  '<b>S3 — Wertpapier → Kurse:</b> the basis line says „Kursbasis: wie erfasst.“ twice (two msgids rendered one after the other). Fixed by the security page\'s repair (the moves keep it once).',
  '<b>S3 — Steuern:</b> the statement note reads „Zahl gegen die Abrechnung prüfen.“ and its button „Gegen die Abrechnung prüfen“: the sentence repeats the control. Polish list „Wealth“ (#1366; Steuern is one of its area tabs).',
  '<b>S3 — Snapshots:</b> the gaps note names 20 securities with no count, and names that two securities share („Juniper Rail AG“, „Pinecrest Utilities SA“ …) appear twice with nothing to tell them apart. The count is fixed here (⑧); the twin names go to the polish list „Wealth“ (#1366; Snapshots is one of its area tabs).',
  '<b>S3 — Ansichten:</b> the assignment line lists 28 accounts without a default bucket in a basis line; at 390 px it runs to many lines. A data fact outside a note does not clamp under the rule; a note would. Polish list „Accounts“ (#1361, where the default buckets are set).',
  '<b>S3 — Klassifizierungen:</b> the predefined „Anlageklasse“ tree shows its categories by their stored English names („Equity“, „Bond“, „Government bond“, also in the exclusion note\'s list) under a German heading, though the catalogue has „Aktie“, „Anleihe“, „Staatsanleihe“ (<code>Catalog.AssetClasses.label/1</code>). Polish list „Classifications and targets“.',
  '<b>S3 — Allokation:</b> the target-conflict and stale-target notes (not on the seed) end in remedy links that are halves of their sentences („bis es auf der Klassifizierungsseite neu hinterlegt wird.“); under the clamp they move to the actions and need a command of their own each, as the overshoot note\'s does here. The Allocation repair fixes them the same way (two more strings, written when the story lands; not drawn, the seed has neither note).',
  '<b>Rule, default (flip by comment):</b> a section with no heading ends its kept basis line in the section\'s ⓘ (the security page\'s Chart, Kurse, Research and Termine tabs). The alternative, a heading per tab, adds a line the tab label already says.',
  '<b>Rule, default (flip by comment):</b> a method line the heading\'s ⓘ already says leaves without a copy (⑥, Views). The alternative appends it to the ⓘ, which would then say it twice.',
  '<b>Rule, default (flip by comment):</b> a data note that states no data fact — Snapshots\' „Der Vergleich ist brutto und nur Kursentwicklung …“ — is a method sentence and moves into the ⓘ.'
];

function frame(kind, label, inner, opts = {}) {
  const open = opts.open ? ' mock-frame--open' : '';
  const style = opts.minHeight ? ` style="min-height:${opts.minHeight}px"` : '';
  return `<figure class="mock-fig"><figcaption class="mock-tag mock-tag--${kind}">${label}</figcaption><div class="mock-frame${open}"${style}><div class="mock-app">${inner}</div></div></figure>`;
}

function page(vw, F) {
  const phone = vw < 600;
  const w = phone ? '390 px' : '1280 px window (main 1060 px)';
  const legend = LEGEND.map(([n, t]) => `<li><span class="mock-pin">${B.PINS.indexOf(n) + 1}</span><span>${t}</span></li>`).join('\n');
  const sections = PAGES.map(p => `
<section class="mock-board">
  <h2>${p.h} <small>${p.sub}</small></h2>
  <p class="mock-note">${p.note}</p>
  ${p.frames.map(k => `${frame('before', 'Before — shipped' + (phone ? ', 390 px' : ''), F[k].before.html)}
  ${frame('after', 'After — R' + (phone ? ', 390 px' : '') + (OPENED.has(k) ? ', its ⓘ opened' : ''), F[k].after.html, { open: OPENED.has(k) })}`).join('\n')}
  ${(p.extra || []).map(x => frame('after', x.label + (phone ? ', 390 px' : ''), F[x.key].after.html, { open: true, minHeight: x.minHeight })).join('\n')}
</section>`).join('\n');
  return `<!doctype html>
<html lang="en" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mockup — Sprint 23 Lane I: I1's later pages, before and after${phone ? ' — 390 px' : ''}</title>
<link rel="stylesheet" href="../../../../../priv/static/app.css">
<!-- Generated by build.js from the running app on the synthetic review seed.
     "Before" frames are the shipped markup; "After" frames are the same
     markup with variant R (Sprint 22's board 01, with its Q1 corrections)
     applied as the markup Sprint 22 built. The proposal block below is
     what the page stories add to priv/static/app.css; the board block after
     it is artboard chrome only. No script runs on this page. -->
<style id="proposal">${B.PROPOSAL_CSS}</style>
<style id="board">${BOARD_CSS}${B.PIN_CSS}</style>
</head>
<body class="${phone ? 'mock-phone' : ''}" data-widths="${phone ? '390' : '1200'}">
<div class="mock-board mock-head">
  <h1>I1's later pages — before and after <small>Sprint 23, Lane I · #1351's rule, #1339, R5 re-read · ${w}</small></h1>
  <div class="mock-pickbar">
    <p><b>Nothing to pick.</b> The anatomy is signed: variant R of the I1 prototype with Sprint 22's four Q1 corrections (board <code>ux-design-2026-11-01-sprint22/01-i1</code>, DESIGN.md's amendment of 2026-11-02). Each page is a conformance repair; this board draws each one as shipped and with R applied, so the page stories have a picture to build against and the design critic one to review against.</p>
    <p><b>Three small rule readings, found while drawing, are the default unless a comment flips them</b> (⑥, ① without a heading, a note with no data fact). Synthetic data only (review seed).</p>
  </div>
  <ul class="mock-legend">${legend}</ul>
</div>
${sections}
<section class="mock-board">
  <h2>Found while drawing</h2>
  <ul>${FOUND.map(f => `<li>${f}</li>`).join('\n')}</ul>
</section>
</body>
</html>
`;
}

function write(file, html) {
  // Trailing whitespace and blank runs from the captured markup are dropped (pre-commit).
  fs.writeFileSync(path.join(__dirname, file), html.split('\n').map(l => l.replace(/[ \t]+$/, '')).filter((l, i, a) => l !== '' || a[i - 1] !== '').join('\n'));
  console.log('wrote', file);
}

async function main() {
  const store = process.env.FRAMES_CACHE;
  let all;
  if (require.main === module && store && fs.existsSync(store)) {
    all = JSON.parse(fs.readFileSync(store, 'utf8'));
  } else {
    const { chromium } = require('playwright');
    const browser = await chromium.launch();
    all = {};
    for (const vw of [1280, 390]) all[vw] = await B.framesAt(browser, vw);
    await browser.close();
    if (store) fs.writeFileSync(store, JSON.stringify(all) + '\n');
  }
  for (const [vw, file] of [[1280, '01-i1-later.html'], [390, '01-i1-later-390.html']]) {
    const F = all[vw];
    write(file, page(vw, F));
  }
}

module.exports = { main, PAGES, LEGEND, FOUND };

if (require.main === module) {
  main().catch(e => { console.error(e); process.exit(1); });
}
