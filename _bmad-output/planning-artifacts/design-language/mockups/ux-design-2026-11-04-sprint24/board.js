// The boards' layout and text. build.js captures the frames into frames/
// and hands over their measured sizes; this file places them as <iframe>s
// with the picks, the reasons and the pins' legend, and writes
//   01-journal-since.html    / 01-journal-since-390.html
//   02-benchmark-costs.html  / 02-benchmark-costs-390.html
// The desktop boards render at 1200 px, the phone boards at 390 px.
// `node board.js` alone rebuilds the boards from frames/sizes.json.
// BOARD_CSS is the Sprint 23 boards' artboard chrome, unchanged.
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
  const iframe = (key, title) => {
    const s = sizes[key];
    if (!s) throw new Error('frame not captured: ' + key);
    return `<iframe src="${s.file}" width="${s.width}" height="${s.height}" title="${title}" scrolling="no"></iframe>`;
  };
  const fig = (kind, label, key) => `<figure class="mock-fig"><figcaption class="mock-tag mock-tag--${kind}">${label}</figcaption><div class="mock-frame">${iframe(key, label)}</div></figure>`;
  const pin = (n) => `<span class="mock-pin">${n}</span>`;
  const page = (title, sub, phone, body) => `<!doctype html>
<html lang="en" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mockup — ${title}${phone ? ' — 390 px' : ''} (Sprint 24)</title>
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
  <p class="mock-note"><span class="mock-key mock-key--new"></span> dashed = new or changed · <span class="mock-key mock-key--synth"></span> amber edge = an invented figure (the seed's window has no such booking total worked out) · ${pin(1)} ties a change to its section's text. Synthetic data only.</p>
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
    <p><b>I16, a time filter on the audit journal.</b> <code>GET /api/v1/journal</code> gains <code>since=</code> the way the delta reads take it (SinceParam's <code>parse_page/1</code>: a date, an instant or the cursor a full page answered as <code>as_of</code>). The page takes the same parameter in its URL, so a link the agent hands over (<code>/journal?since=2026-10-28</code>) opens the slice it read.</p>
    <p><b>Q1 — the control: A</b>, one date field „Seit“ in the filter form beside the kind. B (a chip family „Zeitraum“: Alle · Heute · 7 Tage · 30 Tage) is drawn for contrast. A comment „Q1 B“ flips it.</p>
  </div>`;
  const b1why = `<div class="mock-why">
    <p>${pin(1)}<b>The field</b> is a native date input (a tap and a pick on a phone), named <code>since</code> in the form the page already sends on every change; empty means no cut. ${pin(2)}<b>The basis line</b> names the cut in its existing clause order, after „Neueste zuerst“.</p>
    <p><b>Q1, recommended A.</b> (1) <b>Any cut the agent hands over shows as itself.</b> A link with <code>since=2026-10-28</code> has no chip in B; B would need a fifth, „custom“ state that shows a date anyway. (2) <b>One parameter, one control:</b> the API's <code>since</code> and the field are the same value, so the basis line and the agent's read state the same cut. (3) <b>No second chip row</b> on a phone, where the actor and operation families already wrap.</p>
    <p><b>The page stays newest first</b> within the cut; the API, given <code>since</code>, answers oldest first with a cursor, as every paged delta read does (K17). Same rows, a different order, deliberately: a screen answers „what changed this week“, a poller walks forward. Without <code>since</code> both stay as today. The seed's entries are all from the day it ran, so the cut drops none here.</p>
  </div>`;
  const b1desk = `
<section class="mock-board">
  <h2>The journal's time filter <small>Verwaltung → Audit-Journal</small></h2>
  ${fig('before', 'Heute — Akteur, Vorgang, Art, Szenarien; kein Zeitfilter', '01-today@1280')}
  ${fig('after', 'Nachher A — ein Datumsfeld „Seit“ im Filterformular', '01-a@1280')}
  ${b1why}
  ${fig('alt', 'Variante B — eine Chip-Familie „Zeitraum“ (zum Vergleich)', '01-b@1280')}
</section>`;
  const b1phone = `
<section class="mock-board">
  <h2>The journal's time filter</h2>
  ${fig('before', 'Heute', '01-today@390')}
  ${fig('after', 'Nachher A', '01-a@390')}
  ${b1why}
  ${fig('alt', 'Variante B (zum Vergleich)', '01-b@390')}
</section>`;
  write('01-journal-since.html', page('01 — I16, the journal since a date', 'Audit-Journal', false, { head: b1head, desk: b1desk }));
  write('01-journal-since-390.html', page('01 — I16, the journal since a date', 'Audit-Journal', true, { head: b1head, phone: b1phone }));

  // =========================================================== board 02
  const b2head = `<div class="mock-pickbar">
    <p><b>I17, the costs beside the benchmark gap</b> (scope ladder (b), a decomposition that reports what was booked). The savings-plan benchmark is frictionless (ADR-0046 §2); the real portfolio paid fees and taxes. The comparison gains the fees and taxes booked in <b>its own window and scope</b> (the portfolio, the view or the total), by the cost facet's series rule, with its basis in the payload.</p>
    <p><b>Q2 — the shape: A</b>, one line under the benchmark rows: what was paid, and that the benchmark pays none. B (each row split into „davon Gebühren und Steuern“ and a „Rest (Auswahl und Timing)“) is drawn for contrast. A comment „Q2 B“ flips it.</p>
  </div>`;
  const b2why = `<div class="mock-why">
    <p>${pin(1)}<b>One line, not one per row:</b> the costs are the portfolio's, the same for every benchmark beside it. The ⓘ gains one sentence: what was summed, at which rate, and what is not in it.</p>
    <p class="consequence"><b>Why not B.</b> The rest is not „selection and timing“. A fee paid in March would have compounded until December; the line counts the fee, not its forgone return. Flows the comparison excludes, and taxes settled through the year-end tax pot (ADR-0031), move the gap too. A residual labelled as attribution would state a decomposition the arithmetic does not make. A reports two booked totals and lets the reader subtract.</p>
    <p><b>The figures are invented</b> (amber): 84,20 EUR fees and 312,55 EUR taxes in the year. The delta and the pairs are the seed's own at 5 % p. a.</p>
  </div>`;
  const b2desk = `
<section class="mock-board">
  <h2>The costs beside the gap <small>Vermögen → Performance · Benchmark 5 % p. a.</small></h2>
  ${fig('before', 'Heute — Sparplan-Differenz, Einmalanlage, IRR', '02-today@1280')}
  ${fig('after', 'Nachher A — eine Zeile: im Zeitraum gezahlt', '02-a@1280')}
  ${b2why}
  ${fig('alt', 'Variante B — die Differenz je Zeile zerlegt (zum Vergleich)', '02-b@1280')}
</section>`;
  const b2phone = `
<section class="mock-board">
  <h2>The costs beside the gap</h2>
  ${fig('before', 'Heute', '02-today@390')}
  ${fig('after', 'Nachher A', '02-a@390')}
  ${fig('after', 'Nachher A — das ⓘ mit seinem neuen Satz', '02-a-info@390')}
  ${b2why}
  ${fig('alt', 'Variante B (zum Vergleich)', '02-b@390')}
</section>`;
  write('02-benchmark-costs.html', page('02 — I17, the costs beside the benchmark gap', 'Vermögen → Performance', false, { head: b2head, desk: b2desk }));
  write('02-benchmark-costs-390.html', page('02 — I17, the costs beside the benchmark gap', 'Vermögen → Performance', true, { head: b2head, phone: b2phone }));
};

if (require.main === module) module.exports.main();
