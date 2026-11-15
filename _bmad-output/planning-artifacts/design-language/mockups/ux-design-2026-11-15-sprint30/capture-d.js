// Captures what board 04 (idea I32, „Tops und Flops“) starts from, from the
// same review instance as capture.js (synthetic review seed, port 4013),
// with GET requests and one click that only opens „Alle N anzeigen“ on the
// contribution table; nothing is written to the instance. The fragments
// are built as capture.js builds them (the element inside empty copies of
// its ancestors, LiveView's attributes stripped). Writes
// captured/d-*.html and captured/d-measures.json:
//
//   d-overview-1200.html   the Overview (DashboardLive) at 1200 px, every
//                          section, the host of the new card;
//   d-overview-390.html    the same at 390 px;
//   d-overview-privacy-1200.html the same at 1200 px in the privacy mode;
//   d-perf-1200.html       Vermögen › Bestände › Performance, period YTD,
//                          the chart and „Beitrag je Position“ (the host of
//                          alternative B and the contribution bars' markup);
//   d-perf-privacy-1200.html the same in the privacy mode;
//
// and in d-measures.json the Overview's sections (top, height), the
// contribution table's rows for YTD (every row, „Alle N anzeigen“ opened:
// name, contribution as printed, the held note) and the names Positionen
// lists (what the view „Alles“ holds today).
//
// Usage: BASE=http://localhost:4013 node capture-d.js
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

// In the page: the element inside empty copies of its ancestors up to
// <body> (capture.js's grab, without its row options).
function grab(sel, opts = {}) {
  const el = document.querySelector(sel);
  if (!el) return null;
  const c = el.cloneNode(true);
  (opts.remove || []).forEach((r) => c.querySelectorAll(r).forEach((n) => n.remove()));
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
  const session = async (privacy) => {
    const ctx = await b.newContext({ viewport: { width: 1200, height: 900 }, locale: 'de-DE' });
    await ctx.addInitScript(`window.__grab = ${grab.toString()};`);
    const p = await ctx.newPage();
    if (privacy) await p.goto(BASE + '/?privacy=on', { waitUntil: 'networkidle' });
    const open = async (url, wait, w = 1200) => {
      await p.setViewportSize({ width: w, height: 900 });
      await p.goto(BASE + url, { waitUntil: 'networkidle' });
      if (wait) await p.waitForSelector(wait, { timeout: 30000 });
      await p.waitForTimeout(1500);
    };
    const take = async (file, sel, opts = {}) => {
      const r = await p.evaluate(([s, o]) => window.__grab(s, o), [sel, opts]);
      if (!r) throw new Error('not found: ' + sel + ' for ' + file);
      write(file, r.html);
      measures[file] = { width: r.width, height: r.height, viewport: p.viewportSize().width };
    };
    return { ctx, p, open, take };
  };

  // 1. The Overview, every section, at both widths.
  const s = await session(false);
  await s.open('/', '#dashboard-kpi-strip [data-role="kpi-ttwror"] strong');
  await s.p.waitForSelector('#dashboard-attention .attention-list, #dashboard-attention [data-role="all-clear"]', { timeout: 30000 });
  await s.take('d-overview-1200.html', '#dashboard-overview');
  measures.overviewSections = await s.p.evaluate(() => [...document.querySelectorAll('#dashboard-overview > section')].map((e) => ({ id: e.id || e.className, top: Math.round(e.getBoundingClientRect().top), height: Math.round(e.getBoundingClientRect().height) })));
  await s.open('/', '#dashboard-kpi-strip [data-role="kpi-ttwror"] strong', 390);
  await s.p.waitForSelector('#dashboard-attention .attention-list, #dashboard-attention [data-role="all-clear"]', { timeout: 30000 });
  await s.take('d-overview-390.html', '#dashboard-overview');

  // 2. Performance with the contribution table, YTD.
  await s.open('/portfolio?period=ytd', '#contribution-table');
  await s.take('d-perf-1200.html', '#portfolio-performance', { remove: ['.perf-table-disclosure', '#period-custom', '.benchmark-disclosure'] });
  measures.held = await s.p.evaluate(() => [...document.querySelectorAll('#holdings-positions-table tbody tr [data-column="security"]')].map((td) => td.textContent.trim().replace(/\s+/g, ' ')));
  await s.p.click('[data-role="contribution-show-all"]');
  await s.p.waitForTimeout(1200);
  measures.contribution = await s.p.evaluate(() => [...document.querySelectorAll('#contribution-table tr[data-role="contribution-row"]')].map((tr) => ({
    id: tr.getAttribute('data-security-id'),
    name: tr.querySelector('.contribution-table__name').childNodes[0].textContent.trim(),
    note: (tr.querySelector('.contribution-table__note') || { textContent: '' }).textContent.trim(),
    unvalued: (tr.querySelector('.contribution-unvalued-mark') || { textContent: '' }).textContent.trim(),
    figure: tr.querySelector('.contribution-table__figure span').textContent.trim(),
    bar: (tr.querySelector('.drift-bar__fill') || { style: { width: '' } }).style.width
  })));
  await s.ctx.close();

  // 3. The privacy mode: the Overview and the contribution table.
  const q = await session(true);
  await q.open('/', '#dashboard-kpi-strip [data-role="kpi-ttwror"] strong');
  await q.p.waitForSelector('#dashboard-attention .attention-list, #dashboard-attention [data-role="all-clear"]', { timeout: 30000 });
  await q.take('d-overview-privacy-1200.html', '#dashboard-overview');
  await q.open('/portfolio?period=ytd', '#contribution-table');
  await q.take('d-perf-privacy-1200.html', '#portfolio-performance', { remove: ['.perf-table-disclosure', '#period-custom', '.benchmark-disclosure'] });
  measures.privacyHtml = await q.p.evaluate(() => [...document.documentElement.attributes].map((a) => `${a.name}=${a.value}`));
  await q.ctx.close();

  fs.writeFileSync(path.join(OUT, 'd-measures.json'), JSON.stringify(measures, null, 1) + '\n');
  console.log(JSON.stringify({ sections: measures.overviewSections, held: measures.held.length, rows: measures.contribution.length }, null, 1));
  await b.close();
})();
