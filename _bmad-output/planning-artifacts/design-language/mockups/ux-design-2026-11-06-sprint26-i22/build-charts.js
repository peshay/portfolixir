// Builds the Sprint 26 planning board 02 for idea I22, the privacy mode:
// what the charts do while the mode is on, in look C ("Nebelbalken"), which
// the owner picked on board 01. Board 01's files (build.js, board.js,
// render.js, 01-*, frames/*-{today,a,b,c}-*.html) are not touched; this
// script writes only frames/chart-*.html, frames/sizes-charts.json and,
// through board-charts.js, 02-privacy-charts.html.
//
// Every frame is captured from the running review instance on the
// synthetic review seed (priv/demo/finding_surfaces_seed.exs). The steps are
// read-only: GET requests, the theme written to the browser's own storage
// before the load, and clicks that change only what a page shows — Wealth's
// "Wert (EUR)" series, the security chart's "Prozent" toggle, a year on
// Cashflow — and a pointer resting over a chart, so its tooltip shows.
// Nothing is submitted.
//
// "Aus" is the page as shipped. "An" is the same page with the rule of
// board 01 applied to the live DOM — every figure in a currency and every
// quantity becomes one constant placeholder drawn as look C — and the
// charts' own change:
//   * the security chart: its own "Prozent" view (SecurityChart's
//     percent_mode?, re-based on the window's first close), switched on in
//     the live page — the server's drawing, not a redraw;
//   * Wealth's "Wert" series: the same component has no percent view on
//     Wealth, so the axis is relabelled in the page from the chart's own
//     points — a REDRAW of the five labels, said so on the board. It is
//     exact, not an approximation: percent_mode? re-bases each value as
//     (v − v0) / v0 and pads the range by 5 % of its span, an affine map,
//     so the line, the fill and the gridlines stay where the server drew
//     them and only the labels change; the values come from the points'
//     tooltip labels, the map from their positions (least squares);
//   * tooltips: the amount in each becomes the placeholder; on "Wert" the
//     tooltip says the plotted percent instead.
//
// Each frame is a static page under frames/ that links the real
// priv/static/app.css; board-charts.js places them as <iframe>s. No script
// runs on the board or in a frame.
//
// Usage (the review instance on port 4011, see README.md):
//   node build-charts.js    # captures the chart frames, writes the board
//   node render-charts.js   # renders 02-privacy-charts--1200.png
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const BASE = process.env.BASE || 'http://localhost:4011';
const FRAMES = path.join(__dirname, 'frames');
const WIDTH = 980; // the main column a 1200 px window leaves beside the 220 px sidebar

// Board 01's placeholder and look C, copied from build.js unchanged (that
// script runs when required, so it is not imported).
const PLACEHOLDER = '38.519,46';
const LOOK_C = `
.pf-mask { display: inline-block; width: 4.4em; height: 0.7em; vertical-align: 0.02em; user-select: none; border-radius: 999px;
  background: linear-gradient(90deg, color-mix(in oklab, currentColor 32%, transparent), color-mix(in oklab, currentColor 14%, transparent));
  filter: blur(0.08em); }
.pf-mask__ph { visibility: hidden; }`;
const TOGGLE_CSS = `
.mock-privacy { list-style: none; }
.mock-privacy summary { color: var(--color-accent); background: var(--color-accent-soft); border-color: var(--color-accent) !important; }
.mock-new { outline: 2px dashed var(--color-accent); outline-offset: 3px; border-radius: 8px; }`;
// What board 02 adds: the caption under Wealth's chart, and the frame
// chrome (synthetic marker, pins). A tooltip that is open in a frame stays
// where the hook put it.
const CHART_CSS = `
.mock-synth { box-shadow: inset 3px 0 0 #f59e0b; }
.mock-pin { display: inline-grid; place-items: center; width: 20px; height: 20px; border-radius: 50%; background: #c026d3; color: #fff; font: 700 12px/1 var(--font-sans); letter-spacing: 0; text-transform: none; margin: 0 4px; vertical-align: middle; box-shadow: 0 0 0 2px #fff; }
.mock-pin--abs { position: absolute; left: -10px; top: -10px; margin: 0; z-index: 60; }
.mock-pinned { position: relative; }
.chart-tooltip .pf-mask { font-size: inherit; }`;

const FRAME_CSS = `
body { margin: 0; background: var(--color-bg); }
.app-frame { padding-left: 0 !important; margin-left: 0 !important; }
.app-shell, .app-frame, .app-main, .workspace-page { min-height: 0 !important; }
.topbar { position: relative !important; top: auto !important; }
#security-detail-pane { position: static !important; inset: auto !important; max-height: none !important; height: auto !important; width: auto !important; box-shadow: none !important; }
#securities-detail-splitter { display: none !important; }
.securities-workspace--split { display: block !important; height: auto !important; max-height: none !important; }
#security-detail-pane { flex: none !important; min-height: 0 !important; overflow: visible !important; }`;

// The proposed strings, listed in README.md (Board 02).
const NEW = {
  valueToggle: { en: 'Value (%)', de: 'Wert (%)' },
  valueCaption: {
    en: 'In privacy mode the axis shows the value in percent of the value at the window’s start, deposits and withdrawals included; the return is TTWROR.',
    de: 'Im Privatsphäre-Modus zeigt die Achse den Wert in Prozent des Werts am Fensterbeginn, Ein- und Auszahlungen eingeschlossen; die Rendite zeigt TTWROR.'
  },
  valueTooltip: { en: 'Value %{percent}', de: 'Wert %{percent}' },
  percentLocked: { en: 'Always on in privacy mode', de: 'Im Privatsphäre-Modus immer an' }
};

// ------------------------------------------------------------ in the page
// Runs in the page: the mode switched on (board 01's rule, look C), plus
// the chart-specific change `a.chart` names.
function privacyOn(a) {
  // the switch, beside the appearance menu (board 01)
  const controls = document.querySelector('.topbar-controls');
  const eye = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 3l18 18"></path><path d="M10.6 5.1A9.8 9.8 0 0 1 12 5c5 0 9 4.5 10 7-0.4 1-1.3 2.4-2.6 3.7M6.6 6.6C4.4 8 2.8 10.2 2 12c1 2.5 5 7 10 7 1.9 0 3.6-.6 5.1-1.5"></path><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"></path></svg>';
  const d = document.createElement('details');
  d.className = 'theme-menu mock-privacy mock-new';
  d.innerHTML = '<summary class="theme-menu-trigger" title="Beträge verbergen" aria-pressed="true">' + eye + '</summary>';
  if (controls) controls.prepend(d);

  const mask = () => {
    const s = document.createElement('span');
    s.className = 'pf-mask';
    s.setAttribute('aria-label', 'verborgen');
    s.innerHTML = '<span class="pf-mask__ph" aria-hidden="true">' + a.placeholder + '</span>';
    return s;
  };
  const fmtPct = (p) => {
    const r = Math.round(p * 10) / 10;
    const s = Math.abs(r).toFixed(1).replace('.', ',');
    return (r > 0 ? '+' : r < 0 ? '-' : '') + s + '%';
  };
  const parseDe = (s) => parseFloat(s.replace(/\./g, '').replace(',', '.'));

  // --- Wealth's "Wert" series: the axis in percent of the window's first
  // value, relabelled from the chart's own points (an exact redraw, see the
  // header), the tooltip with the plotted percent instead of the amount.
  if (a.chart === 'perf-value') {
    const figure = document.querySelector('#performance-figure');
    const payload = JSON.parse(figure.querySelector('script[data-chart-payload]').textContent);
    const pts = payload.points.map((p) => ({ label: p[1], py: p[3], date: p[4], v: parseDe(p[1].split(' · ')[1]) })).filter((p) => !isNaN(p.v));
    const n = pts.length;
    const mx = pts.reduce((s, p) => s + p.v, 0) / n;
    const my = pts.reduce((s, p) => s + p.py, 0) / n;
    const b = pts.reduce((s, p) => s + (p.v - mx) * (p.py - my), 0) / pts.reduce((s, p) => s + (p.v - mx) ** 2, 0);
    const c = my - b * mx;
    const v0 = pts[0].v;
    figure.querySelectorAll('.chart-axis-y').forEach((t) => {
      const v = (parseFloat(t.getAttribute('y')) - c) / b;
      t.textContent = fmtPct((v - v0) / v0 * 100);
    });
    const tip = figure.querySelector('.chart-tooltip');
    if (tip && !tip.hidden) {
      const date = tip.querySelector('.chart-tooltip__date').textContent.trim();
      const p = pts.find((q) => q.date === date) || pts[pts.length - 1];
      tip.querySelector('.chart-tooltip__price').textContent = p.label.split(' · ')[0] + ' · ' + a.valueTooltip.replace('%{percent}', fmtPct((p.v - v0) / v0 * 100));
    }
    // the series' name says it is not in euro any more
    const opt = [...document.querySelectorAll('#portfolio-performance .segmented-control__option')].find((o) => o.getAttribute('phx-value-mode') === 'value' || /Wert \(/.test(o.textContent));
    if (opt) { opt.textContent = a.valueToggle; opt.classList.add('mock-new'); }
    const cap = document.createElement('p');
    cap.className = 'hint mock-new';
    cap.dataset.role = 'perf-privacy-basis';
    cap.textContent = a.valueCaption;
    figure.querySelector('.chart-frame').after(cap);
    figure.querySelector('.chart-frame').classList.add('mock-new');
  }

  // --- the security chart: "Prozent" stays on while the mode is on.
  if (a.chart === 'security') {
    const pct = document.querySelector('#toggle-percent-mode');
    if (pct) { pct.setAttribute('disabled', ''); pct.setAttribute('title', a.percentLocked); pct.classList.add('mock-new'); }
    // a trade's tooltip line: its quantity and price are figures to hide
    document.querySelectorAll('.chart-tooltip__tx').forEach((line) => {
      line.innerHTML = line.textContent.replace(/&/g, '&amp;').replace(/</g, '&lt;')
        .replace(/(^|[\s×(])(\d{1,3}(?:\.\d{3})*(?:,\d+)?)(?=[\s×)]|$)(?!\s*%)/g, (m, pre) => pre + '\u0000');
      line.innerHTML = line.innerHTML.split('\u0000').join('<span class="pf-mask" aria-label="verborgen"><span class="pf-mask__ph" aria-hidden="true">' + a.placeholder + '</span></span>');
    });
  }

  // --- Cashflow: a bar's native tooltip (<title>) loses its amount.
  if (a.chart === 'cashflow') {
    document.querySelectorAll('svg title').forEach((t) => {
      t.textContent = t.textContent.replace(/:\s*[^:]*\d[^:]*$/, '').trim();
    });
  }

  // Board 01's rule: a figure in a currency or a quantity, digits with a
  // decimal comma, not a percentage, not a ratio, not inside an SVG.
  const re = /[+\-−]?\d{1,3}(?:\.\d{3})*,\d+(?!\d)(?!\s*%)/g;
  const main = document.querySelector('.app-main');
  const walker = document.createTreeWalker(main, NodeFilter.SHOW_TEXT);
  const nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  for (const n of nodes) {
    if (n.parentElement && n.parentElement.closest('svg, script')) continue;
    const t = n.nodeValue;
    re.lastIndex = 0;
    const hits = [...t.matchAll(re)].filter((m) => t[m.index - 1] !== '×');
    if (!hits.length) continue;
    const frag = document.createDocumentFragment();
    let at = 0;
    for (const m of hits) {
      frag.append(t.slice(at, m.index), mask());
      at = m.index + m[0].length;
    }
    frag.append(t.slice(at));
    n.replaceWith(frag);
  }
}

// Runs in the page last: cut to the kept blocks, clean, serialize.
function isolate(a) {
  document.querySelectorAll('script, #app-sidebar, .sidebar-backdrop, .data-note, #portfolio-data-quality').forEach((e) => e.remove());
  const kept = a.keep.flatMap((s) => [...document.querySelectorAll(s)]);
  const chain = new Set();
  kept.forEach((k) => { let n = k; while (n && n !== document.body) { chain.add(n); n = n.parentElement; } });
  const visit = (el) => [...el.children].forEach((c) => {
    if (kept.includes(c)) return;
    if (chain.has(c)) visit(c); else c.remove();
  });
  visit(document.body);
  (a.drop || []).forEach((s) => document.querySelectorAll(s).forEach((e) => e.remove()));
  const html = document.documentElement.outerHTML
    .replace(/\s(?:data-phx-[\w-]+|phx-[\w-]+)="[^"]*"/g, '')
    .replace(/\sid="phx-[^"]*"/g, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/<meta name="csrf-token"[^>]*>/g, '')
    .replace(/\snonce="[^"]*"/g, '')
    .replace(/[ \t]+$/gm, '');
  return { html };
}

// ------------------------------------------------------------ the frames
const PERF_KEEP = ['header.topbar', '#area-tabs', '#portfolio-performance > header.section-head', '#portfolio-performance > p.perf-badge', '#performance-figure', '#portfolio-performance > p.hint'];
const SEC_KEEP = ['header.topbar', '#security-detail-pane'];
const CASH_KEEP = ['header.topbar', '#area-tabs', '.workspace-section--controls', '#income-annual'];

async function hoverChart(page, root, at) {
  await page.waitForSelector(root + ' svg.security-chart', { state: 'visible', timeout: 30000 });
  const box = await page.evaluate(([root, at]) => {
    const svg = document.querySelector(root + ' svg.security-chart');
    svg.scrollIntoView({ block: 'center' });
    const r = svg.getBoundingClientRect();
    let x = r.left + r.width * (at.frac || 0.7);
    if (at.tx) {
      const node = document.querySelector(root + ' script[data-chart-payload]');
      const p = JSON.parse(node.textContent);
      if (p.txs && p.txs.length) x = r.left + p.txs[0].x * (r.width / p.view.width);
    }
    return { x, y: r.top + r.height * 0.5 };
  }, [root, at]);
  await page.mouse.move(box.x - 30, box.y);
  await page.mouse.move(box.x, box.y, { steps: 4 });
  await page.waitForTimeout(400);
}

const FRAMES_LIST = [
  // Wealth → Performance, the default series (TTWROR, a percent axis)
  { id: 'perf-ttwror', url: '/portfolio', keep: PERF_KEEP, drop: ['.perf-table-disclosure'], chart: 'perf-ttwror', themes: ['light'],
    act: async (page) => { await page.waitForTimeout(1500); await hoverChart(page, '#performance-figure', { frac: 0.74 }); } },
  // Wealth → Performance, "Wert (EUR)" (a euro axis)
  { id: 'perf-value', url: '/portfolio', keep: PERF_KEEP, drop: ['.perf-table-disclosure'], chart: 'perf-value', themes: ['light', 'dark'],
    act: async (page) => {
      await page.click('#portfolio-performance button[phx-value-mode="value"]');
      await page.waitForTimeout(1200);
      await hoverChart(page, '#performance-figure', { frac: 0.74 });
    } },
  // Wertpapiere → Nordic Timber Holdings AB → Diagramm (a buy in the window)
  { id: 'security', url: '/securities/8?tab=chart', keep: SEC_KEEP, drop: ['#detail-period-custom .period-popover'], chart: 'security', themes: ['light'],
    act: async (page, on) => {
      if (on) { await page.click('#toggle-percent-mode'); await page.waitForTimeout(1200); }
      await hoverChart(page, '#security-detail-pane', { tx: true });
    } },
  // Vermögen → Cashflow → Erträge, the year 2023 opened
  { id: 'cashflow', url: '/cashflow', keep: CASH_KEEP.concat(['#income-detail']), chart: 'cashflow', themes: ['light'],
    act: async (page) => {
      await page.click('[phx-click="select_year"][phx-value-year="2023"]');
      await page.waitForTimeout(1200);
    } }
];

// A chart's path and point lists arrive on one line of several thousand
// characters; they break every sixteen coordinates (whitespace inside the
// attribute), so a frame stays a readable multiline file (AGENTS.md).
const wrapLong = (s) => s.split('\n').map((l) => (l.length > 300 ? l.replace(/((?:\S+ ){16})/g, '$1\n') : l)).join('\n').replace(/[ \t]+$/gm, '');

function framePage(html, on) {
  return '<!doctype html>\n' + wrapLong(html).replace(/\s*$/, '\n')
    .replace(/href="\/app\.css[^"]*"/, 'href="../../../../../../priv/static/app.css"')
    .replace(/src="\/images\//g, 'src="../../../../../../priv/static/images/')
    .replace('</head>', '<style id="frame">' + FRAME_CSS + CHART_CSS + '</style>\n<style id="proposal">' + (on ? TOGGLE_CSS + LOOK_C : '') + '</style>\n</head>');
}

(async () => {
  fs.mkdirSync(FRAMES, { recursive: true });
  const browser = await chromium.launch(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {});
  const sizes = {};
  const de = (k) => NEW[k].de;
  for (const f of FRAMES_LIST) {
    for (const theme of f.themes) {
      for (const on of [false, true]) {
        const page = await browser.newPage({ viewport: { width: WIDTH + 220, height: 1000 }, locale: 'de-DE' });
        await page.addInitScript(([th]) => { try { localStorage.setItem('portfolixir-theme', th); } catch (_) {} }, [theme]);
        await page.goto(BASE + f.url + (f.url.includes('?') ? '&' : '?') + 'locale=de', { waitUntil: 'networkidle' });
        await page.waitForTimeout(1000);
        // The frame's layout before the pointer moves: the sidebar gone, the
        // window the frame's width, so the tooltip sits where the frame shows it.
        await page.evaluate(() => document.querySelectorAll('#app-sidebar, .sidebar-backdrop').forEach((e) => e.remove()));
        await page.addStyleTag({ content: FRAME_CSS });
        await page.setViewportSize({ width: WIDTH, height: 1000 });
        await page.waitForTimeout(500);
        await f.act(page, on);
        if (on) {
          await page.evaluate(privacyOn, { chart: f.chart, placeholder: PLACEHOLDER, valueToggle: de('valueToggle'), valueCaption: de('valueCaption'), valueTooltip: de('valueTooltip'), percentLocked: de('percentLocked') });
        }
        const r = await page.evaluate(isolate, { keep: f.keep, drop: f.drop });
        await page.close();
        const file = `chart-${f.id}-${on ? 'on' : 'off'}-${theme}.html`;
        fs.writeFileSync(path.join(FRAMES, file), framePage(r.html, on));
        const m = await browser.newPage({ viewport: { width: WIDTH, height: 200 } });
        await m.goto('file://' + path.join(FRAMES, file));
        await m.waitForTimeout(300);
        const height = await m.evaluate(() => Math.ceil(document.documentElement.scrollHeight));
        await m.close();
        sizes[file] = height;
        console.log('frame', file, height);
      }
    }
  }
  await browser.close();
  fs.writeFileSync(path.join(FRAMES, 'sizes-charts.json'), JSON.stringify(sizes, null, 2) + '\n');
  require('./board-charts.js')(sizes, WIDTH, NEW);
})().catch((e) => { console.error(e); process.exit(1); });
