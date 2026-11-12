// Walks every page of the review instance (synthetic review seed, GET
// requests and in-page clicks that only switch a mode) at 390 and 1200 px
// and measures, for issue 1435's inventory:
//
//   1. every bar of controls: the container, its visible labels, its
//      controls, the rows they fall on, and the left edge of the first
//      control on each row (the rule "labelled controls start on one edge",
//      DESIGN.md amendment of 2026-11-08, asks the edges to agree, ±1 px);
//   2. every visible free paragraph outside a details.metric-tooltip, a
//      data note, a table, a dialog and the chart's tooltip, with its text,
//      its word count and its sentence count.
//
// Writes inventory-b.json beside this file; build-b.js and the inventory
// (06-control-bar-inventory.md) read it. Nothing is written to the instance.
// Usage: BASE=http://localhost:4012 node capture-b-inventory.js
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const BASE = process.env.BASE || 'http://localhost:4012';
const PAGES = [
  ['/', 'Übersicht'],
  ['/portfolio', 'Vermögen · Bestände'],
  ['/portfolio?level=category', 'Vermögen · Bestände, gestapelt (Kategorien)', 'value'],
  ['/portfolio?tab=allocation', 'Vermögen · Allokation'],
  ['/cashflow', 'Vermögen · Cashflow · Einkommen'],
  ['/cashflow?tab=realized', 'Vermögen · Cashflow · Trades'],
  ['/cashflow?tab=flows', 'Vermögen · Cashflow · Ein- und Auszahlungen'],
  ['/cashflow?tab=costs', 'Vermögen · Cashflow · Kosten'],
  ['/snapshots', 'Vermögen · Snapshots'],
  ['/tax', 'Vermögen · Steuern'],
  ['/risk', 'Vermögen · Risiko'],
  ['/predictions', 'Vermögen · Prognosen'],
  ['/securities', 'Wertpapiere'],
  ['/securities/1', 'Wertpapier · Übersicht'],
  ['/securities/1?tab=chart', 'Wertpapier · Diagramm'],
  ['/securities/1?tab=trades', 'Wertpapier · Trades'],
  ['/securities/1?tab=research', 'Wertpapier · Research'],
  ['/securities/1?tab=news', 'Wertpapier · Nachrichten'],
  ['/securities/1?tab=predictions', 'Wertpapier · Prognosen'],
  ['/news', 'Nachrichten · Meldungen'],
  ['/news?tab=feeds', 'Nachrichten · Feeds'],
  ['/portfolios', 'Konten'],
  ['/transactions', 'Transaktionen'],
  ['/imports', 'Import'],
  ['/buckets', 'Töpfe'],
  ['/classifications', 'Klassifizierungen'],
  ['/classifications/1', 'Klassifizierung'],
  ['/journal', 'Journal'],
  ['/cashflow?tab=realized&hindsight=rate', 'Vermögen · Cashflow · Trades, Vergleich „Fester Zins“'],
  ['/portfolio?tab=allocation', 'Vermögen · Allokation, Positionen', 'flat'],
  ['/securities', 'Wertpapiere, Filterblatt offen', 'sheet'],
  ['/transactions', 'Transaktionen, Filterblatt offen', 'sheet'],
];

const BARS = [
  '.filter-sheet__families',
  '.stack-bar__controls', '.section-head-controls', '.workspace-section--controls',
  '.filter-chips', '.hs-controls', '.select-toolbar', '.toolbar', '.journal-filters',
  '.detail-pane-toolbar', '.chart-toggles', '.overview-chart__toggles',
].join(',');

function measure() {
  const visible = (e) => {
    const r = e.getBoundingClientRect();
    const s = getComputedStyle(e);
    return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && !e.closest('.visually-hidden, [hidden], details:not([open]) > :not(summary)');
  };
  const CONTROL = '.segmented-control, select, .filter-chip, input:not([type=hidden]):not([type=checkbox]), label:has(input[type=checkbox]), .more-filters-link, .filter-sheet-toggle, summary, button:not(.segmented-control button):not(.filter-chip)';
  const LABEL = '.filter-chips__family, .stack-bar__label, .hs-controls__label, label:not(:has(input[type=checkbox])):not(.visually-hidden)';
  const bars = [];
  const seen = new Set();
  for (const bar of document.querySelectorAll(window.__BARS)) {
    if (!visible(bar) || bar.closest(window.__SHEET ? '.modal, details:not([open])' : '.modal, .filter-sheet, details:not([open])')) continue;
    const box = bar.getBoundingClientRect();
    const controls = [...bar.querySelectorAll(CONTROL)].filter((c) => visible(c) && !c.parentElement.closest('.segmented-control') && !(c.matches('summary') && c.closest('.metric-tooltip')) && !c.closest('details[open] > :not(summary)'));
    // an outer control (a segmented control) hides its inner options
    const atomic = controls.filter((c) => !controls.some((o) => o !== c && o.contains(c)));
    if (atomic.length < 2) continue;
    const labels = [...bar.querySelectorAll(LABEL)].filter((l) => visible(l) && !l.closest('.segmented-control') && l.textContent.trim() && !atomic.some((c) => c.contains(l)) && !l.querySelector('select, input'));
    const boxes = atomic.map((c) => ({ el: c, r: c.getBoundingClientRect() })).sort((a, b) => a.r.top - b.r.top || a.r.left - b.r.left);
    const rows = [];
    for (const b of boxes) {
      const mid = b.r.top + b.r.height / 2;
      const row = rows.find((r) => mid > r.top && mid < r.bottom);
      if (row) { row.items.push(b); row.top = Math.min(row.top, b.r.top); row.bottom = Math.max(row.bottom, b.r.bottom); } else rows.push({ top: b.r.top, bottom: b.r.bottom, items: [b] });
    }
    const describe = (e) => (e.matches('.segmented-control') ? 'segmented' : e.matches('select') ? 'select' : e.matches('.filter-chip') ? 'chip' : e.matches('input') ? 'input' : e.matches('summary') ? 'disclosure' : e.matches('label') ? 'checkbox' : 'button');
    const key = [...atomic].map((a) => a.outerHTML.length).join(',');
    if (seen.has(key)) continue; // a bar nested in a bar: keep the outer one
    seen.add(key);
    const rowsOut = rows.sort((a, b) => a.top - b.top).map((r) => {
      const items = r.items.sort((a, b) => a.r.left - b.r.left);
      const rowLabels = labels.filter((l) => { const lr = l.getBoundingClientRect(); const m = lr.top + lr.height / 2; return m > r.top && m < r.bottom; });
      return {
        top: Math.round(r.top - box.top),
        firstControlLeft: Math.round((items[0].r.left - box.left) * 10) / 10,
        firstKind: describe(items[0].el),
        firstText: items[0].el.textContent.trim().replace(/\s+/g, ' ').slice(0, 30),
        labels: rowLabels.map((l) => ({ text: l.textContent.trim().replace(/\s+/g, ' '), left: Math.round(l.getBoundingClientRect().left - box.left) })),
        kinds: [...new Set(items.map((i) => describe(i.el)))],
      };
    });
    // Groups: a visible label and the controls after it up to the next
    // label; controls before the first label are a group of their own. The
    // rule compares the first control of every group and of every row.
    const order = [...labels.map((l) => ({ l })), ...atomic.map((c) => ({ c }))]
      .sort((a, b) => ((a.l || a.c).compareDocumentPosition(b.l || b.c) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1));
    const groups = [];
    let cur = { label: null, first: null };
    for (const o of order) {
      if (o.l) { if (cur.first || cur.label) groups.push(cur); cur = { label: o.l, first: null }; } else if (!cur.first) cur.first = o.c;
    }
    if (cur.first || cur.label) groups.push(cur);
    const groupsOut = groups.filter((g) => g.first).map((g) => ({
      label: g.label ? g.label.textContent.trim().replace(/\s+/g, ' ') : null,
      controlLeft: Math.round((g.first.getBoundingClientRect().left - box.left) * 10) / 10,
      top: Math.round(g.first.getBoundingClientRect().top - box.top),
    }));
    const lefts = [...rowsOut.map((r) => r.firstControlLeft), ...(labels.length ? groupsOut.map((g) => g.controlLeft) : [])];
    bars.push({
      selector: bar.className.split(/\s+/).filter(Boolean).map((c) => '.' + c).join(''),
      id: bar.id || null,
      role: bar.getAttribute('data-role'),
      width: Math.round(box.width),
      labels: [...new Set(labels.map((l) => l.textContent.trim().replace(/\s+/g, ' ')))],
      kinds: [...new Set(atomic.map(describe))],
      rows: rowsOut,
      groups: groupsOut,
      spread: rowsOut.length > 1 ? Math.round((Math.max(...lefts) - Math.min(...lefts)) * 10) / 10 : 0,
      html: rowsOut.length > 1 || labels.length ? bar.outerHTML.length : 0,
    });
  }
  // Free paragraphs: visible text blocks outside an ⓘ, a data note, a table,
  // a dialog, a chart tooltip, a form's error list.
  const paras = [];
  for (const p of document.querySelectorAll('main p, main .hint, main .detail-tab-hint, main .summary-basis')) {
    if (!visible(p) || p.closest('details.metric-tooltip, .data-note, table, .modal, .chart-tip, .chart-tooltip, .research-entry, .phone-row, .attention-list, li, dd, .filter-sheet')) continue;
    if (p.parentElement.closest('main p, main .hint, main .detail-tab-hint, main .summary-basis')) continue;
    const clone = p.cloneNode(true);
    clone.querySelectorAll('details, .visually-hidden, script').forEach((d) => d.remove());
    const text = clone.textContent.replace(/\s+/g, ' ').trim();
    if (!text) continue;
    const words = text.split(' ').filter((w) => /[\p{L}\p{N}]/u.test(w)).length;
    // A sentence ends at . ! ? followed by a space and a capital or a
    // digit, or at the end; "z. B.", "u. a.", "ggf." and ordinals stay inside.
    const guarded = text.replace(/\b(z|u|d|o|v|bzw|ggf|inkl|ca|Nr|vgl|etc|evtl|max|min|bspw|S|Pp)\.(\s)/g, '$1§$2').replace(/(\d)\.(\s)/g, '$1§$2');
    const sentences = guarded.split(/(?<=[.!?])\s+(?=[A-ZÄÖÜ„"(0-9])/).filter((s) => /[\p{L}]/u.test(s)).length;
    paras.push({ cls: p.className || p.tagName.toLowerCase(), role: p.getAttribute('data-role'), words, sentences, text: text.slice(0, 400) });
  }
  return { bars, paras };
}

(async () => {
  const launch = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {};
  const browser = await chromium.launch(launch);
  const out = [];
  for (const width of [390, 1200]) {
    const ctx = await browser.newContext({ viewport: { width, height: 900 }, locale: 'de-DE' });
    const page = await ctx.newPage();
    for (const [url, name, mode] of PAGES) {
      try {
        await page.goto(BASE + url, { waitUntil: 'networkidle', timeout: 30000 });
        if (mode === 'flat') {
          const btn = await page.$('[data-role="allocation-mode-flat"]');
          if (btn) { await btn.click(); await page.waitForTimeout(800); }
        }
        if (mode === 'sheet') {
          const btn = await page.$('.filter-sheet-toggle:visible');
          if (!btn) continue;
          await btn.click(); await page.waitForTimeout(800);
          await page.evaluate(() => { window.__SHEET = true; });
        }
        if (mode === 'value') {
          const btn = await page.$('[data-role="chart-series"] button[phx-value-mode="value"]');
          if (btn) { await btn.click(); await page.waitForTimeout(800); }
        }
        await page.waitForTimeout(600);
        await page.evaluate((s) => { window.__BARS = s; }, BARS);
        const m = await page.evaluate(measure);
        out.push({ url, name, width, state: mode || null, ...m });
        console.log(width, url, m.bars.length, 'bars', m.paras.length, 'paragraphs');
      } catch (e) {
        console.log(width, url, 'failed', e.message.split('\n')[0]);
      }
    }
    await ctx.close();
  }
  // The seed's first security carries a listed company's name and ISIN; the
  // inventory names it generically.
  const json = JSON.stringify(out, null, 1).replace(/US0378331005 · AAPL/g, 'XX0000000001 · TICK');
  fs.writeFileSync(path.join(__dirname, 'inventory-b.json'), json + '\n');
  await browser.close();
})();
