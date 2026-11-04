// The board's layout and text. build.js captures the frames into frames/
// and hands over their measured sizes and probes; this file places them as
// <iframe>s with the reasons and the pins' legend, and writes
//   01-wealth-tables.html      (the desktop board, rendered at 1200 px)
//   01-wealth-tables-390.html  (the phone board, rendered at 390 px)
// `node board.js` alone rebuilds the boards from frames/sizes.json.
// BOARD_CSS is the Sprint 23 and 24 boards' artboard chrome, unchanged.
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
  const size = (key) => { const s = sizes[key]; if (!s) throw new Error('frame not captured: ' + key); return s; };
  const iframe = (key, title) => {
    const s = size(key);
    return `<iframe src="${s.file}" width="${s.width}" height="${s.height}" title="${title}" scrolling="no"></iframe>`;
  };
  const fig = (kind, label, key) => `<figure class="mock-fig"><figcaption class="mock-tag mock-tag--${kind}">${label}</figcaption><div class="mock-frame">${iframe(key, label)}</div></figure>`;
  const pin = (n) => `<span class="mock-pin">${n}</span>`;
  const H = (key) => size(key).probe.holdings;
  const C = (key) => size(key).probe.contribution;
  const holdingsLine = (key) => { const h = H(key); return `Scroller ${h.wrapper} px, Tabelle ${h.scroll} px, G&amp;V ${h.pnlInView ? 'sichtbar' : 'außer Sicht'}, Namensspalte ${h.nameColumn} px`; };
  const contribLine = (key) => { const c = C(key); return `Block ${c.block} px: ${c.table ? `Tabelle, Scroller ${c.wrapper} px, Tabelle ${c.scroll} px${c.scroll > c.wrapper ? ' — scrollt seitwärts' : ''}` : 'Zeilen'}`; };

  const page = (title, sub, phone, body) => `<!doctype html>
<html lang="en" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mockup — ${title}${phone ? ' — 390 px' : ''} (Sprint 24 P1)</title>
<link rel="stylesheet" href="../../../../../priv/static/app.css">
<!-- Generated by build.js and board.js from the review instance on the
     synthetic review seed. Each frame is a static page under frames/ that
     links app.css; "Vorher" frames are the shipped markup, "Nachher" frames
     carry the story's CSS in their own <style id="proposal"> and its class
     in their markup. The block below is artboard chrome only. No script
     runs on this page or in a frame. -->
<style id="board">${BOARD_CSS}</style>
</head>
<body class="${phone ? 'mock-phone' : ''}" data-widths="${phone ? '390' : '1200'}">
<div class="mock-board mock-head">
  <h1>${title} <small>${sub}${phone ? ' · 390 px' : ''}</small></h1>
  ${body.head}
  <p class="mock-note"><span class="mock-key mock-key--new"></span> dashed = new or changed · ${pin(2)} ${pin(3)} tie a change to #1366's line. Every row is the synthetic review seed's; nothing is invented. Synthetic data only.</p>
</div>
${phone ? body.phone : body.desk}
</body>
</html>
`;
  const write = (file, html) => {
    fs.writeFileSync(path.join(__dirname, file), html.split('\n').map(l => l.replace(/[ \t]+$/, '')).join('\n'));
    console.log('wrote', file);
  };

  const head = `<div class="mock-pickbar">
    <p><b>Two conformance repairs on Wealth (#1366, lines 2 and 3), before and after.</b> Nothing is picked: each line applies an anatomy already signed. Line 1 (the sunburst returns to „Allokiert“) changes behaviour, not the picture, and has no frame here (plan D-8).</p>
    <p>${pin(2)} <b>„Beitrag je Position“ takes its phone rows where its columns stop fitting</b>, not under a 560 px viewport: a container query on the block (<code>@container contribution (width &lt; 820px)</code>), the way the accounts table became its card in #1145, so the sidebar's 220, 72 or 0 px never decides it. ${pin(3)} <b>#1322: the holdings table's name column gets #1145's floor and break</b> — the table fits its wrapper, „Wertpapier“ keeps a 12 rem floor and breaks inside its cell (<code>overflow-wrap: anywhere</code>), the figures never wrap and the quantity keeps every digit („0,333333333333“).</p>
  </div>`;

  const why2 = `<div class="mock-why">
    <p>${pin(2)} <b>Measured on the seed:</b> the German table needs ${size('c-before@1200').probe.contribution.scroll} px of columns (the English one 753 px), plus the wrapper's 2 px border; the seed's numbers are the same in every period. Below that the scroller cut „Beitrag“ off with no cue — from a 1090 px window with the sidebar open down to 900 px, and from 856 px to 561 px without it, where the sidebar leaves the layout. The bound is 820 px of block; a longer figure than the seed's still has UX-DR15's scroller above it.</p>
    <p><b>Why the rows and not a narrower table:</b> its seven columns are already the reading table's (the name at least 14ch and wrapping, six figures that never wrap); what is left to give is the figures themselves. The rows are the anatomy the phone already reads, with every figure the row needs (DESIGN.md, the contribution table, „Under 560 px“).</p>
  </div>`;
  const why3 = `<div class="mock-why">
    <p>${pin(3)} <b>#1322's eight columns at 1200 px with the sidebar open:</b> before, ${holdingsLine('h-before@1200')}; after, ${holdingsLine('h-after@1200')}. The floor is what the seven other columns leave of the 922 px scroller on the seed: 13.5 rem, the accounts table's own bound, would have been 942 px. The two cell notes („Handelspreis · 03.02.2025“, „ohne Wechselkurs · nicht in der Summe“) wrap between words; on one line they set the widest columns (196 and 246 px).</p>
    <p><b>Kept:</b> the quantity prints every stored digit, so the issue's „bound on the quantity's digits“ is not taken; with all eleven columns picked the table is still wider than 922 px and keeps UX-DR15's scroller. Under 560 px the phone rows are unchanged.</p>
  </div>`;

  const desk = `
<section class="mock-board">
  <h2>#1322 — the holdings table <small>Vermögen → Bestände → Positionen · #1322's eight columns · 1200 px, sidebar open</small></h2>
  ${fig('before', 'Vorher — ' + holdingsLine('h-before@1200'), 'h-before@1200')}
  ${fig('after', 'Nachher — ' + holdingsLine('h-after@1200'), 'h-after@1200')}
  ${why3}
  ${fig('after', 'Nachher, dunkel', 'h-after-dark@1200')}
</section>
<section class="mock-board">
  <h2>„Beitrag je Position“ <small>Vermögen → Bestände → Performance · 1024 px, sidebar open</small></h2>
  ${fig('before', 'Vorher — ' + contribLine('c-before@1024'), 'c-before@1024')}
  ${fig('after', 'Nachher — ' + contribLine('c-after@1024'), 'c-after@1024')}
  ${why2}
  ${fig('after', 'Nachher, dunkel', 'c-after-dark@1024')}
  <div class="mock-row">
    ${fig('before', 'Vorher, 600 px — ' + contribLine('c-before@600'), 'c-before@600')}
    ${fig('after', 'Nachher, 600 px — ' + contribLine('c-after@600'), 'c-after@600')}
  </div>
  ${fig('after', 'Unverändert, 1200 px — ' + contribLine('c-after@1200'), 'c-after@1200')}
</section>`;

  const phone = `
<section class="mock-board">
  <h2>390 px: both unchanged</h2>
  <p class="mock-note">Under 560 px both tables already give way to their rows, and the story keeps them: the frames are the shipped page with the story's CSS and class applied. The contribution rows now come from the container query (the block is under 820 px at every phone width), the holdings rows from the phone lists' 560 px block as before.</p>
  ${fig('after', 'Positionen, nachher — wie vorher', 'h-after@390')}
  ${fig('after', 'Beitrag je Position, nachher — ' + contribLine('c-after@390'), 'c-after@390')}
  ${fig('before', 'Beitrag je Position, vorher (zum Vergleich)', 'c-before@390')}
</section>`;

  write('01-wealth-tables.html', page("P1 — Wealth's two tables", '#1366 lines 2 and 3', false, { head, desk }));
  write('01-wealth-tables-390.html', page("P1 — Wealth's two tables", '#1366 lines 2 and 3', true, { head, phone }));
};

if (require.main === module) module.exports.main();
