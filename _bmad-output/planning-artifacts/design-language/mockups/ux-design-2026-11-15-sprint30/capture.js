// Captures what the Sprint 30 boards start from, from a review instance on
// the synthetic review seed (priv/demo/finding_surfaces_seed.exs), with GET
// requests and in-page clicks that only open a disclosure or a sheet;
// nothing is written. Each fragment is the served element inside empty
// copies of its ancestors (tag, id and class), so app.css's descendant
// rules and container queries still hold, with LiveView's attributes
// stripped. Writes captured/*.html and captured/measures.json:
//
//   perf-total-1200.html   Vermögen › Bestände › Performance, „Wert“, level
//                          Gesamt, at 1200 px (and -390, -privacy-390);
//   perf-category-1200.html the same window at the level Kategorien;
//   security-chart-1200.html a security's price chart (Diagramm, 1J);
//   positions-1200.html    Positionen with eight columns (the browser's own
//                          column choice, as #1322 measured it);
//   kpis-allocation-1200.html Allokation & Ziele' line of key figures;
//   crash-390.html, crash-1200.html, crash-catalogue-1200.html the Crashes
//                          section on Vermögen › Risiko, the windows open;
//   risk-head-1200.html    Risiko's area tabs, for the state without a
//                          portfolio;
//   kpi-strip-1200.html    the Overview's KPI strip;
//   tx-filter-390.html     Transaktionen at 390 px with the filter sheet open.
//
// Usage: BASE=http://localhost:4013 node capture.js
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const BASE = process.env.BASE || 'http://localhost:4013';
const OUT = path.join(__dirname, 'captured');
fs.mkdirSync(OUT, { recursive: true });
const strip = (s) => s
  .replace(/ data-phx-[a-z-]+="[^"]*"/g, '')
  .replace(/ phx-[a-z-]+="[^"]*"/g, '')
  .replace(/ id="phx-[^"]*"/g, '')
  .replace(/<script\b[^>]*>[\s\S]*?<\/script>/g, '');
const write = (f, s) => fs.writeFileSync(path.join(OUT, f), strip(s).replace(/[ \t]+\n/g, '\n').trim() + '\n');
// The six rows #1366's line names: the notes under a figure and „Demo
// Depot“ breaking.
const SIX_ROWS = ['Alder Creek Timber Fund', 'Meridian Global Equity ETF', 'Placeholder Anleihe 2031', 'Harborline Freight Inc', 'Larkspur Robotics Inc', 'Birchwood Global Savings Fund'];
const HOLDINGS_COLUMNS = ['depot', 'security', 'quantity', 'avg_cost', 'latest_price', 'market_value', 'unrealized_pnl_abs', 'unrealized_pnl_pct'];

// In the page: the element inside empty copies of its ancestors up to
// <body>, and its rendered width; `remove` drops the descendants a board
// leaves out (each named on the board), `limit` keeps a list's first items,
// `keepRows` marks the rows a board shows (`mock-keep`); the others stay in
// the markup, so the table's columns keep the widths the page gives them.
function grab(sel, opts = {}) {
  const el = document.querySelector(sel);
  if (!el) return null;
  const c = el.cloneNode(true);
  (opts.remove || []).forEach((r) => c.querySelectorAll(r).forEach((n) => n.remove()));
  Object.entries(opts.limit || {}).forEach(([r, n]) => [...c.querySelectorAll(r)].slice(n).forEach((x) => x.remove()));
  if (opts.keepRows) {
    const [rowSel, names] = opts.keepRows;
    const seen = new Set();
    [...c.querySelectorAll(rowSel)].forEach((tr) => {
      const name = tr.querySelector('[data-column="security"]').textContent.trim().replace(/\s+/g, ' ');
      const want = names.find((n) => name.startsWith(n) && !seen.has(n) && tr.querySelector('.cell-note'));
      if (want) { seen.add(want); tr.classList.add('mock-keep'); }
    });
  }
  let out = c.outerHTML;
  for (let a = el.parentElement; a && a.tagName !== 'BODY'; a = a.parentElement) {
    const t = a.tagName.toLowerCase();
    const attrs = ['id', 'class', 'style'].filter((k) => a.getAttribute(k) && !(k === 'id' && a.id.startsWith('phx-'))).map((k) => ` ${k}="${a.getAttribute(k)}"`).join('');
    out = `<${t}${attrs}>${out}</${t}>`;
  }
  return { html: out, width: Math.round(el.getBoundingClientRect().width), height: Math.round(el.getBoundingClientRect().height) };
}

(async () => {
  const launch = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {};
  const b = await chromium.launch(launch);
  const measures = {};
  const ctx = await b.newContext({ viewport: { width: 1200, height: 900 }, locale: 'de-DE' });
  await ctx.addInitScript(`window.__grab = ${grab.toString()};
    try { localStorage.setItem('wealth.holdings.columns', ${JSON.stringify(JSON.stringify(HOLDINGS_COLUMNS))}); } catch (e) {}`);
  const p = await ctx.newPage();
  const open = async (url, wait, w = 1200) => {
    await p.setViewportSize({ width: w, height: 900 });
    await p.goto(BASE + url, { waitUntil: 'networkidle' });
    if (wait) await p.waitForSelector(wait, { timeout: 30000 });
    await p.waitForTimeout(800);
  };
  const take = async (file, sel, opts = {}) => {
    const r = await p.evaluate(([s, o]) => window.__grab(s, o), [sel, opts]);
    if (!r) throw new Error('not found: ' + sel + ' for ' + file);
    write(file, r.html);
    measures[file] = { width: r.width, height: r.height, viewport: p.viewportSize().width };
    return r;
  };

  // 1. The performance section at Gesamt and at Kategorien, value series.
  await open('/portfolio?level=total', '#performance-figure svg.security-chart');
  const PERF_CUT = { remove: ['#performance-contribution', '.perf-table-disclosure', '#period-custom', '[data-role="benchmark-picker"]', '.benchmark-disclosure'] };
  await take('perf-total-1200.html', '#portfolio-performance', PERF_CUT);
  measures.totalChart = await p.evaluate(() => {
    const f = document.querySelector('#performance-figure .chart-frame');
    return { width: Math.round(f.getBoundingClientRect().width), ticks: [...f.querySelectorAll('.chart-axis-y')].map((t) => t.textContent.trim()) };
  });
  await open('/portfolio?level=category', '#performance-figure-stack svg.stack-chart');
  await take('perf-category-1200.html', '#portfolio-performance', PERF_CUT);
  measures.stackChart = await p.evaluate(() => {
    const c = document.querySelector('#stack-figure-chart');
    const svg = c.querySelector('svg');
    const plotLeft = svg.getBoundingClientRect().left + 56 * svg.getBoundingClientRect().width / 960;
    const labels = [...svg.querySelectorAll('.chart-axis-y')].map((t) => { const r = t.getBoundingClientRect(); return { text: t.textContent.trim(), left: Math.round(r.left - svg.getBoundingClientRect().left), right: Math.round(r.right - svg.getBoundingClientRect().left), width: Math.round(r.width) }; });
    return { width: Math.round(svg.getBoundingClientRect().width), inside: c.hasAttribute('data-axis-inside'), upx: c.getAttribute('style'), gutterPx: Math.round(plotLeft - svg.getBoundingClientRect().left), labels, negative: svg.querySelectorAll('.stack-band--negative').length };
  });
  await open('/portfolio?level=total', '#performance-figure svg.security-chart', 390);
  await take('perf-total-390.html', '#portfolio-performance', PERF_CUT);

  // 2. A security's price chart.
  await open('/securities/8?tab=chart', '#security-detail-pane svg.security-chart');
  await take('security-chart-1200.html', '#security-detail-pane .chart-frame');

  // 3. Positionen with eight columns, and the six rows' heights.
  await open('/portfolio', '#holdings-positions-table');
  await take('positions-1200.html', '#portfolio-positions', { keepRows: ['#holdings-positions-table tbody tr', SIX_ROWS] });
  measures.positions = await p.evaluate(() => {
    const w = document.querySelector('#holdings-positions-wrapper');
    const t = document.querySelector('#holdings-positions-table');
    const cols = [...t.querySelectorAll('thead th')].map((th) => ({ label: th.textContent.trim(), width: Math.round(th.getBoundingClientRect().width) }));
    const rows = [...t.querySelectorAll('tbody tr')].map((tr) => ({ name: tr.querySelector('[data-column="security"]')?.textContent.trim().replace(/\s+/g, ' '), height: Math.round(tr.getBoundingClientRect().height), notes: tr.querySelectorAll('.cell-note').length }));
    return { wrapper: Math.round(w.getBoundingClientRect().width), table: Math.round(t.scrollWidth), cols, rows };
  });

  // 4. Allokation & Ziele: the key figures.
  await open('/portfolio?tab=allocation', '[data-role="kpi-summary"] strong.gain, [data-role="kpi-summary"] strong.loss, [data-role="kpi-summary"] strong:nth-of-type(1)');
  await p.waitForFunction(() => !document.querySelector('[data-role="kpi-summary"]').hasAttribute('aria-busy'), null, { timeout: 30000 });
  await take('kpis-allocation-1200.html', '[data-role="kpi-summary"]');

  // 5. Risiko: the area tabs, and the Crashes section with its windows open.
  await open('/risk', '#risk-crashes');
  await take('risk-head-1200.html', '.workspace-page > nav, .workspace-page > .area-tabs');
  await p.click('#crash-windows > summary');
  await p.waitForTimeout(300);
  await take('crash-1200.html', '#risk-crashes');
  await open('/risk?crash_universe=catalogue', '#risk-crashes');
  await p.click('#crash-windows > summary');
  await p.waitForTimeout(300);
  await take('crash-catalogue-1200.html', '#risk-crashes');
  await open('/risk', '#risk-crashes', 390);
  await p.click('#crash-windows > summary');
  await p.waitForTimeout(300);
  await take('crash-390.html', '#risk-crashes');
  measures.crashWindows390 = await p.evaluate(() => {
    const t = document.querySelector('#crash-windows-table');
    return { wrapper: Math.round(t.parentElement.getBoundingClientRect().width), table: Math.round(t.scrollWidth) };
  });

  // 6. The Overview's KPI strip, and Transaktionen at 390 with the sheet open.
  await open('/', '.kpi-strip');
  await take('kpi-strip-1200.html', '.kpi-strip');
  await open('/transactions', '.filter-sheet-toggle', 390);
  await p.click('.filter-sheet-toggle');
  await p.waitForTimeout(400);
  measures.txHead = await p.evaluate(() => document.querySelector('main').firstElementChild?.className);
  await take('tx-filter-390.html', 'main > *:first-child', { remove: ['#transaction-table-wrapper', '#transaction-more-filters', '.inline-result', '#transaction-summary', '.column-picker-bar'], limit: { '#transaction-phone-rows > li': 4 } });
  await ctx.close();

  // 7. The privacy mode, its own browser: the value series in percent.
  const priv = await b.newContext({ viewport: { width: 390, height: 900 }, locale: 'de-DE' });
  await priv.addInitScript(`window.__grab = ${grab.toString()};`);
  const q = await priv.newPage();
  await q.goto(BASE + '/portfolio?privacy=on', { waitUntil: 'networkidle' });
  await q.goto(BASE + '/portfolio?level=total', { waitUntil: 'networkidle' });
  await q.waitForSelector('#performance-figure svg.security-chart', { timeout: 30000 });
  await q.waitForTimeout(800);
  const pr = await q.evaluate(([s, o]) => window.__grab(s, o), ['#portfolio-performance', { remove: ['#performance-contribution', '.perf-table-disclosure', '#period-custom'] }]);
  write('perf-total-privacy-390.html', pr.html);
  measures['perf-total-privacy-390.html'] = { width: pr.width, height: pr.height, viewport: 390, htmlAttrs: await q.evaluate(() => [...document.documentElement.attributes].map((a) => `${a.name}=${a.value}`)) };
  await priv.close();

  fs.writeFileSync(path.join(OUT, 'measures.json'), JSON.stringify(measures, null, 1) + '\n');
  console.log(JSON.stringify(measures, null, 1));
  await b.close();
})();
