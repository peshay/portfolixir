// The layout and text of board 03 (Sprint 26, I18, "what a sale missed").
// build.js captures the frames into frames/ and hands over their measured
// sizes; this file places them as <iframe>s with the reasons, the pick and
// the legend, and writes
//   03-sale-hindsight.html      (the desktop board, rendered at 1200 px)
//   03-sale-hindsight-390.html  (the phone board, rendered at 390 px)
// `node board.js` alone rebuilds both boards from frames/sizes.json.
// BOARD_CSS is the Sprint 23 and 24 boards' artboard chrome.
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
.mock-fig { margin: 0 0 18px; }
.mock-tag { display: inline-block; margin: 0 0 6px; padding: 2px 10px; border-radius: 999px; font-size: 11px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; }
.mock-tag--rec { color: var(--color-positive); background: #ecfdf5; }
.mock-tag--alt { color: var(--color-text-muted); background: var(--color-bg-muted); }
.mock-tag--state { color: #92400e; background: #fef3c7; }
.mock-frame { width: max-content; max-width: 100%; border: 1px solid var(--color-border-strong); border-radius: 10px; background: var(--color-bg); overflow: hidden; box-shadow: var(--shadow-panel); }
.mock-frame iframe { display: block; border: 0; }
.mock-pin { display: inline-grid; place-items: center; width: 18px; height: 18px; border-radius: 50%; background: #c026d3; color: #fff; font: 700 11px/1 var(--font-sans); vertical-align: 1px; margin-right: 4px; }
.mock-why { margin: 8px 0 18px; padding: 8px 12px; border-left: 3px solid var(--color-accent); background: var(--color-bg-elevated); font-size: 12.5px; line-height: 1.5; color: var(--color-text-muted); }
.mock-why p { margin: 0 0 6px; } .mock-why p:last-child { margin: 0; }
.mock-why ul { margin: 0; padding-left: 18px; } .mock-why li { margin: 0 0 4px; }
.mock-key { display: inline-block; width: 22px; height: 12px; vertical-align: -1px; margin: 0 4px 0 2px; border-radius: 3px; }
.mock-key--new { outline: 2px dashed var(--color-accent); outline-offset: -2px; }
.mock-key--synth { box-shadow: inset 4px 0 0 #f59e0b; background: var(--color-bg-elevated); border: 1px solid var(--color-border); }
table.mock-rules { width: 100%; border-collapse: collapse; font-size: 12.5px; background: var(--color-bg-elevated); border: 1px solid var(--color-border); border-radius: var(--radius-md); }
table.mock-rules th { text-align: left; font-size: 11px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; color: var(--color-text-muted); background: var(--color-bg-muted); padding: 8px 10px; }
table.mock-rules td { padding: 7px 10px; border-top: 1px solid var(--color-border); vertical-align: top; }
/* The phone board: the frames are the 390 px viewport. */
body.mock-phone { padding: 16px 0; }
body.mock-phone .mock-board > :not(.mock-fig), body.mock-phone .mock-head > * { margin-left: 16px; margin-right: 16px; }
body.mock-phone .mock-fig > .mock-tag { margin-left: 16px; }
body.mock-phone .mock-frame { width: 100%; border-radius: 0; border-left: 0; border-right: 0; box-shadow: none; }
`;

module.exports.main = function main(sizes) {
  sizes = sizes || JSON.parse(fs.readFileSync(path.join(__dirname, 'frames', 'sizes.json'), 'utf8'));
  const size = (key) => { const s = sizes[key]; if (!s) throw new Error('frame not captured: ' + key); return s; };
  const iframe = (key, title) => { const s = size(key); return `<iframe src="${s.file}" width="${s.width}" height="${s.height}" title="${title}" scrolling="no"></iframe>`; };
  const fig = (kind, label, key) => `<figure class="mock-fig"><figcaption class="mock-tag mock-tag--${kind}">${label}</figcaption><div class="mock-frame">${iframe(key, label)}</div></figure>`;
  const pin = (n) => `<span class="mock-pin">${n}</span>`;
  const a = size('a').scroller;

  const legend = `<p class="mock-note"><span class="mock-key mock-key--new"></span> dashed = new · <span class="mock-key mock-key--synth"></span> amber stripe = synthetic figure, invented for the board (the seed stores no closes around its sales, so the read answers every span „kein Startkurs“ there) · ${pin(1)}–${pin(6)} tie a frame to its note. The rows are the seed's ten sale bookings as <code>GET /api/v1/sales/hindsight</code> answers them: security, date, quantity, booked price and currency, and the span dates, which decide „läuft“ (today is 06.11.2026). Synthetic data only.</p>`;

  const page = (title, phone, body) => `<!doctype html>
<html lang="en" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mockup — ${title}${phone ? ' — 390 px' : ''} (Sprint 26, board 03)</title>
<link rel="stylesheet" href="../../../../../priv/static/app.css">
<!-- Generated by build.js and board.js from the review instance on the
     synthetic review seed. Each frame is a static page under frames/ that
     links app.css and carries the proposal (proposal.css) in its own
     <style id="proposal">. The block below is artboard chrome only. No
     script runs on this page or in a frame. -->
<style id="board">${BOARD_CSS}</style>
</head>
<body class="${phone ? 'mock-phone' : ''}" data-widths="${phone ? '390' : '1200'}">
${body}
</body>
</html>
`;
  const write = (file, html) => {
    fs.writeFileSync(path.join(__dirname, file), html.split('\n').map((l) => l.replace(/[ \t]+$/, '')).join('\n'));
    console.log('wrote', file);
  };

  const pickbar = `<div class="mock-pickbar">
    <p><b>Where the operator sees what a sale missed</b> (FR-50, I18 modes 1 and 2, today only <code>GET /api/v1/sales/hindsight</code> and <code>portfolixir.sales.hindsight</code>), and mode 3, the purchase the proceeds went into (ADR-0057). <b>The pick: A, B or C. Recommended: C</b>, a section of its own, „Nach dem Verkauf“, on Cashflow → Trades under the trades list, and the same section on a security's Trades tab. <b>Silence adopts C.</b> A comment naming A or B changes it.</p>
    <p><b>Why C:</b> the read has one row per <i>sale booking</i>; „Alle Trades“ has one row per closed FIFO round trip. On the seed the two lists differ: of ten sales, three have no trade row (Harborline Freight Inc and Arbolia Inc. are excluded from the totals for want of a rate or a leg, Saltmarsh Logistics SE matched no buy), and Brightwater sold 13 shares of which 10 are a trade. A and B could only show the seven that have a row, and a sale that closes two lots would repeat its figures on both. C lists every sale, keeps the trades table as it is, and has room for all three figures per span without a click.</p>
    <p><b>Mode 3 sits in C's chooser</b> as its fourth choice, „Anschlusskauf“, beside „Fester Zins“ and „Wertpapier“: it is one more thing to compare the sale with, over the same four spans and the same rows. No figure on any frame says whether a sale was right; the figures are the answer.</p>
  </div>`;

  const head = (phone) => `<div class="mock-board mock-head">
  <h1>Nach dem Verkauf <small>Sprint 26 · board 03 · I18 · FR-50${phone ? ' · 390 px' : ' · 1200 px'}</small></h1>
  ${pickbar}
  ${legend}
</div>`;

  const desk = `${head(false)}
<section class="mock-board">
  <h2>A — a column group on „Alle Trades“ <small>Cashflow → Trades · 1280 px window, sidebar open (1060 px)</small></h2>
  ${fig('alt', 'A — Spaltengruppe an jedem Trade', 'a')}
  <div class="mock-why">
    <p>${pin(1)} Four columns after „Ergebnis“, the difference to the chosen benchmark per span; the chooser above the table. <b>Against it:</b> the table already fills its scroller; with four more columns it is ${a ? a.scroll : '?'} px in a ${a ? a.client : '?'} px scroller, so „1M“ onward is off to the right at a laptop width, the three figures per span do not fit (only the difference), and the rows are trades, not sales: the seed's three sales without a trade row are not on it.</p>
  </div>
</section>
<section class="mock-board">
  <h2>B — a row that opens under a trade <small>Cashflow → Trades · 1060 px</small></h2>
  ${fig('alt', 'B — aufklappbare Zeile unter dem Trade (Wrenfield Gardens AG geöffnet)', 'b')}
  <div class="mock-why">
    <p>${pin(1)} Each trade gets a toggle „Nach dem Verkauf“; the row under it shows the four spans with all three figures. <b>For it:</b> the table stays as wide as today. <b>Against it:</b> one sale at a time, so two sales cannot be read side by side; the same trade-versus-sale mismatch as A; and a toggle in every name cell of a table that has none.</p>
  </div>
</section>
<section class="mock-board">
  <h2>C — a section of its own, one row per sale (recommended) <small>Cashflow → Trades, under the trades list (cut to two rows here) · 1060 px</small></h2>
  ${fig('rec', 'C — „Nach dem Verkauf“, verglichen mit einem Benchmark-Wertpapier', 'c')}
  <div class="mock-why">
    <ul>
      <li>${pin(1)} <b>The chooser:</b> „Vergleich: Ohne · Fester Zins · Wertpapier · Anschlusskauf“, the shipped segmented control. „Wertpapier“ opens a select of the securities flagged <code>is_benchmark</code> (ADR-0046, reused unchanged); „Fester Zins“ the rate field and „Anwenden“. The choice is query state on the page, as the facet is; a page reload keeps it. Without a flagged security the select is replaced by the shipped hint „Noch keine Benchmark-Wertpapiere — eines auf der Seite Wertpapiere markieren.“</li>
      <li><b>A span cell:</b> the lead figure is what the group head names (here the difference to the benchmark), the line under it the security's return „ggü.“ the benchmark's; signed and coloured as every return is, <code>.num</code>-aligned and tabular. The start close in EUR stands beside the booked sale („13 × 33,00 EUR“), with its date where it is not the sale day (Brightwater: sold on a Sunday, the close is Friday's).</li>
      <li>${pin(2)} <b>A span that has not ended</b> has no figure: „läuft“ over „bis 27.12.2026“, muted, never a dash, so it cannot be read as a missing price.</li>
      <li>${pin(3)} <b>A span the read cannot measure</b> is the muted dash with its reason in words under it, and the longer reason as the cell's title: „kein Startkurs“, „kein Endkurs“, „kein Wechselkurs“ (Kestrel Bay 3M), „kein Benchmark-Kurs“. With no benchmark close the security's own figure stays on the line (Microsoft). Harborline and Tamarisk are the read's own answer on the seed.</li>
      <li>${pin(4)} <b>The computation basis</b> is behind the section's ⓘ (idea I1: method clauses in the ⓘ, the gross/net line under the table); the frame below shows it open. The API's <code>computation_basis</code> keeps its own wording; the ⓘ is its German reading.</li>
    </ul>
  </div>
  ${fig('state', 'C — ⓘ geöffnet: die Berechnungsgrundlage', 'c-info')}
  ${fig('state', 'C — Vergleich „Ohne“: die Kursrendite des Wertpapiers allein', 'c-none')}
  ${fig('state', 'C — Vergleich „Fester Zins“, 3,00 % p. a.', 'c-rate')}
  ${fig('rec', 'C — dunkel', 'c-dark')}
  ${fig('rec', 'C — auf der Wertpapierseite, Tab Trades (Wrenfield Gardens AG; ohne Wertpapier-Spalte)', 'security')}
  <div class="mock-why"><p><b>The per-security home:</b> the same section under „Abgeschlossene Trades (FIFO)“, filtered to the security (<code>security_id=</code>), its heading an h3 with the section ⓘ as the trades list has it. The trades list links each name to this tab already.</p></div>
</section>
<section class="mock-board">
  <h2>Mode 3 — „Anschlusskauf“, the purchase the proceeds went into <small>ADR-0057 · C's fourth choice · 1060 px · cut to five sales</small></h2>
  ${fig('rec', 'C — Vergleich „Anschlusskauf“', 'm3')}
  <div class="mock-why">
    <ul>
      <li><b>No link is chosen by hand.</b> By rule, the buys from the sale's cash account on the sale day or up to 30 days after consume the proceeds in date order, the last pro rata. „Angelegt“ is the part of the proceeds that went into them and its share; the kept side is scaled to that part.</li>
      <li><b>A span cell:</b> the lead is „gewechselt − behalten“ in EUR, the lines under it the two values, „behalten“ (the sold position, price only) and „gewechselt“ (the bought position; before its buy date the money counts as cash at its booked amount). Measured from the sale day.</li>
      <li>${pin(5)} <b>The line under a matched sale:</b> the buys with their dates and the days after the sale (one pro rata: „anteilig 610,10 von 655,00 EUR“), then the cost line: the sale's and the buys' booked fees, which are <i>inside</i> the difference; the sale's booked taxes, stated apart and <i>not</i> inside it, because the kept side's latent tax is not known either (both sides before tax; the ⓘ says so); the buys' booked income, named, not added.</li>
      <li>${pin(6)} <b>A sale with no such buy</b> says so in the spans' place, with the rule as its reason: „Keine Anschlusskäufe gefunden: kein Kauf vom Verrechnungskonto des Verkaufs binnen 30 Tagen ab dem Verkaufstag“.</li>
    </ul>
  </div>
</section>
<section class="mock-board">
  <h2>What the story builds, and what it does not</h2>
  <table class="mock-rules">
    <thead><tr><th>Builds (C)</th><th>Does not</th></tr></thead>
    <tbody>
      <tr><td>„Nach dem Verkauf“ on Cashflow → Trades, under the trades list and before „Realisiert je Periode“; the same section on a security's Trades tab, filtered to it.</td><td>No change to the trades table, its three figures or its notes; no column on a trade row (A), no toggle (B).</td></tr>
      <tr><td>The chooser with four kinds (none, a fixed rate, a flagged security, the follow-on purchase), as query state; rows newest first, the read's <code>limit</code> of 100.</td><td>No second benchmark, no benchmark beyond <code>is_benchmark</code> (the plan's flip „I18 any security“ stays a flip).</td></tr>
      <tr><td>Per span the lead figure and its sub-lines; „läuft“ for a span that has not ended; the muted dash with its reason in words; the start close beside the booked sale.</td><td>No verdict anywhere: no „zu früh verkauft“, no „richtig“, no colour on a row, no ranking, no total of what all sales missed.</td></tr>
      <tr><td>The section's ⓘ with the computation basis (I1); the gross/net line under the table; the phone rows under 560 px.</td><td>No distributions after the sale (price only, the basis says so); no tax on the kept side; no stored link between a sale and a buy.</td></tr>
    </tbody>
  </table>
</section>`;

  const phone = `${head(true)}
<section class="mock-board">
  <h2>C at 390 px</h2>
  <p class="mock-note">${pin(1)} The chooser spans the row. Under 560 px each sale is one row: name, sale and start close, then the four spans as a 2 × 2 grid, each the span's label over the lead figure over its sub-line, so the phone shows every figure the table row has. ${pin(2)} „läuft“ and ${pin(3)} the reason in words, as on the desktop.</p>
  ${fig('rec', 'C — Benchmark-Wertpapier (the trades list cut to one row, five of the ten sales)', 'c-390')}
  ${fig('rec', 'C — dunkel (four sales)', 'c-390-dark')}
  <p class="mock-note">${pin(5)} Mode 3 on the phone: the grid holds the difference and both values; the buys and the cost line follow under it. ${pin(6)} A sale with no follow-on purchase says so in the grid's place.</p>
  ${fig('rec', 'Mode 3 — „Anschlusskauf“', 'm3-390')}
</section>`;

  write('03-sale-hindsight.html', page('Nach dem Verkauf', false, desk));
  write('03-sale-hindsight-390.html', page('Nach dem Verkauf', true, phone));
};

if (require.main === module) module.exports.main();
