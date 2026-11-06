// Builds the Sprint 26 planning board 01 for idea I22, the privacy mode:
// three looks for a hidden figure (A, B, C) beside today's screen, on Wealth
// and on the Overview, in the light and the dark theme.
//
// Every frame is captured from the running review instance on the synthetic
// review seed (priv/demo/finding_surfaces_seed.exs) with GET requests only.
// The theme and Wealth's column pick are written to the browser's own
// storage before the load, as a reader's earlier pick would be. The frame is
// then cut to the part the board shows, and for A, B and C the proposal is
// applied to the live DOM: every figure in a currency and every quantity is
// replaced by ONE constant placeholder of a fixed width, so neither the
// digits nor their count reach the page; the proposal's CSS draws it.
// Percentages, dates and day counts stay.
//
// Each frame is written as a static page under frames/ that links the real
// priv/static/app.css; board.html places them as <iframe>s. No script runs
// on the board or in a frame.
//
// Usage (the review instance on port 4011, see README.md):
//   node build.js    # captures every frame, writes frames/ and board.html
//   node render.js   # renders board.html to PNG
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const BASE = process.env.BASE || 'http://localhost:4011';
const FRAMES = path.join(__dirname, 'frames');
const WIDTH = 1000; // the content column of a 1220 px window with the sidebar cut away

// The one placeholder every hidden figure shows, whatever its value.
const PLACEHOLDER = '38.519,46';

const VARIANTS = {
  today: { name: 'Heute', css: '' },
  a: {
    name: 'A — Weichzeichner',
    css: `
.pf-mask { display: inline-block; width: 4.4em; overflow: hidden; white-space: nowrap; vertical-align: bottom; user-select: none; }
.pf-mask__ph { display: inline-block; filter: blur(max(3.5px, 0.26em)); opacity: 0.8; }`
  },
  b: {
    name: 'B — Milchglas',
    css: `
.pf-mask { display: inline-block; width: 4.4em; overflow: hidden; white-space: nowrap; vertical-align: bottom; user-select: none;
  padding: 0 0.2em; border-radius: 0.3em;
  background: color-mix(in oklab, currentColor 9%, transparent);
  box-shadow: inset 0 0 0 1px color-mix(in oklab, currentColor 12%, transparent); }
.pf-mask__ph { display: inline-block; filter: blur(max(3.5px, 0.3em)); opacity: 0.55; }`
  },
  c: {
    name: 'C — Nebelbalken',
    css: `
.pf-mask { display: inline-block; width: 4.4em; height: 0.7em; vertical-align: 0.02em; user-select: none; border-radius: 999px;
  background: linear-gradient(90deg, color-mix(in oklab, currentColor 32%, transparent), color-mix(in oklab, currentColor 14%, transparent));
  filter: blur(0.08em); }
.pf-mask__ph { visibility: hidden; }`
  }
};

// The switch the mode adds to the top bar, drawn in every proposal frame.
const TOGGLE_CSS = `
.mock-privacy { list-style: none; }
.mock-privacy summary { color: var(--color-accent); background: var(--color-accent-soft); border-color: var(--color-accent) !important; }
.mock-new { outline: 2px dashed var(--color-accent); outline-offset: 3px; border-radius: 8px; }`;

const FRAME_CSS = `
body { margin: 0; background: var(--color-bg); }
.app-frame { padding-left: 0 !important; margin-left: 0 !important; }
.app-shell, .app-frame, .app-main, .workspace-page { min-height: 0 !important; }
.topbar { position: relative !important; top: auto !important; }
.mock-elided td, li.mock-elided { padding: 6px 10px; font-size: 11.5px; color: var(--color-text-muted); text-align: center; }`;

const PAGES = {
  wealth: {
    url: '/portfolio',
    keep: ['header.topbar', '#area-tabs', '#portfolio-kpis', '#portfolio-positions'],
    rows: 5
  },
  overview: {
    url: '/',
    keep: ['header.topbar', '.app-main > *:nth-child(-n+3)'],
    rows: 4
  }
};

// Runs in the page: cut, mask, serialize.
function transform(a) {
  document.querySelectorAll('script').forEach((s) => s.remove());
  document.querySelectorAll('#app-sidebar, .sidebar-backdrop, .data-note, #portfolio-data-quality, #portfolio-load-error').forEach((e) => e.remove());
  if (a.page === 'overview') {
    // the hero, the KPI row and the closed trades; everything after them goes
    const main = document.querySelector('.app-main');
    const blocks = [...main.querySelectorAll('section, .workspace-section')].filter((s) => s.parentElement.closest('section, .workspace-section') === null);
    const trades = blocks.find((s) => /Abgeschlossene Trades/.test(s.textContent));
    let cut = false;
    blocks.forEach((s) => { if (cut) s.remove(); if (s === trades) cut = true; });
  } else {
    const keep = a.keep.flatMap((s) => [...document.querySelectorAll(s)]);
    const main = document.querySelector('.app-main');
    const visit = (el) => [...el.children].forEach((c) => {
      if (keep.some((k) => k === c || k.contains(c))) return;
      if (keep.some((k) => c.contains(k))) visit(c); else c.remove();
    });
    visit(main);
  }
  // fewer rows: the board shows the look, not the list
  for (const sel of ['#holdings-positions-table > tbody > tr', '#holdings-phone-rows > li']) {
    const rows = [...document.querySelectorAll(sel)];
    rows.slice(a.rows).forEach((r) => r.remove());
  }
  document.querySelectorAll('.closed-trades li, [id*="closed-trades"] li').forEach((li, i) => { if (i >= a.rows) li.remove(); });

  if (a.variant !== 'today') {
    // the switch, beside the appearance menu
    const controls = document.querySelector('.topbar-controls');
    const eye = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 3l18 18"></path><path d="M10.6 5.1A9.8 9.8 0 0 1 12 5c5 0 9 4.5 10 7-0.4 1-1.3 2.4-2.6 3.7M6.6 6.6C4.4 8 2.8 10.2 2 12c1 2.5 5 7 10 7 1.9 0 3.6-.6 5.1-1.5"></path><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"></path></svg>';
    const d = document.createElement('details');
    d.className = 'theme-menu mock-privacy mock-new';
    d.innerHTML = '<summary class="theme-menu-trigger" title="Beträge verbergen" aria-pressed="true">' + eye + '</summary>';
    controls.prepend(d);

    const mask = () => {
      const s = document.createElement('span');
      s.className = 'pf-mask';
      s.setAttribute('aria-label', 'verborgen');
      s.innerHTML = '<span class="pf-mask__ph" aria-hidden="true">' + a.placeholder + '</span>';
      return s;
    };
    // a figure in a currency or a quantity: digits with a decimal comma,
    // not a percentage, not a ratio (×1,09), not inside a date
    const re = /[+\-−]?\d{1,3}(?:\.\d{3})*,\d+(?!\d)(?!\s*%)/g;
    const main = document.querySelector('.app-main');
    const walker = document.createTreeWalker(main, NodeFilter.SHOW_TEXT);
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    for (const n of nodes) {
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
    // integer quantities in the holdings table (no decimal comma)
    document.querySelectorAll('#holdings-positions-table td.num').forEach((td) => {
      if (td.querySelector('.pf-mask') || /%/.test(td.textContent) || !/\d/.test(td.textContent)) return;
      td.textContent = '';
      td.append(mask());
    });
  }
  const html = document.documentElement.outerHTML
    .replace(/\s(?:data-phx-[\w-]+|phx-[\w-]+)="[^"]*"/g, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/<meta name="csrf-token"[^>]*>/g, '')
    .replace(/\snonce="[^"]*"/g, '')
    .replace(/[ \t]+$/gm, '');
  const bottom = Math.max(...[...document.querySelectorAll('.app-main .workspace-section, .app-main section, #area-tabs')].map((c) => c.getBoundingClientRect().bottom));
  return { html, height: Math.ceil(bottom) + 20 };
}

function framePage(html, variant) {
  return '<!doctype html>\n' + html.replace(/\s*$/, '\n')
    .replace(/href="\/app\.css[^"]*"/, 'href="../../../../../../priv/static/app.css"')
    .replace(/src="\/images\//g, 'src="../../../../../../priv/static/images/')
    .replace('</head>', '<style id="frame">' + FRAME_CSS + '</style>\n<style id="proposal">' + (variant === 'today' ? '' : TOGGLE_CSS + VARIANTS[variant].css) + '</style>\n</head>');
}

(async () => {
  fs.mkdirSync(FRAMES, { recursive: true });
  const browser = await chromium.launch(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {});
  const sizes = {};
  for (const [pageKey, pg] of Object.entries(PAGES)) {
    for (const theme of ['light', 'dark']) {
      for (const variant of Object.keys(VARIANTS)) {
        const page = await browser.newPage({ viewport: { width: WIDTH + 220, height: 1000 }, locale: 'de-DE' });
        await page.addInitScript(([th]) => {
          try {
            localStorage.setItem('portfolixir-theme', th);
            localStorage.setItem('wealth.holdings.columns', JSON.stringify(['depot', 'security', 'quantity', 'avg_cost', 'latest_price', 'market_value', 'unrealized_pnl_abs', 'unrealized_pnl_pct']));
          } catch (_) {}
        }, [theme]);
        await page.goto(BASE + pg.url, { waitUntil: 'networkidle' });
        await page.waitForTimeout(800);
        await page.setViewportSize({ width: WIDTH, height: 1000 });
        const r = await page.evaluate(transform, { page: pageKey, keep: pg.keep, rows: pg.rows, variant, placeholder: PLACEHOLDER });
        const file = `${pageKey}-${variant}-${theme}.html`;
        fs.writeFileSync(path.join(FRAMES, file), framePage(r.html, variant));
        sizes[file] = r.height;
        await page.close();
        console.log('frame', file, r.height);
      }
    }
  }
  await browser.close();
  fs.writeFileSync(path.join(FRAMES, 'sizes.json'), JSON.stringify(sizes, null, 2) + '\n');
  require('./board.js')(sizes, VARIANTS, WIDTH);
})();
