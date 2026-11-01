// Builds the I1 board (#1351, with #1350, #1336, #1342) from the running app.
//
// For every page and width it loads the shipped page twice from the review
// instance (synthetic review seed, read-only: GET requests and client-side
// <details> toggles only). The first load is captured as "Before". On the
// second load the variant-R change is applied to the live DOM as the story
// would render it (the classification below is per text, not per CSS
// class), measured at that width ("mehr" only where the clamp cuts, the ⓘ
// panel's place and shift), and captured as "After". The board files hold
// that markup as static HTML; they run no script.
//
// Usage (the server on port 4003, see README.md):
//   node build.js            # writes 01-i1.html and 01-i1-390.html
//   node render.js           # renders both to PNG
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const BASE = process.env.BASE || 'http://localhost:4003';

// ---------------------------------------------------------------- the rule
// Proposal CSS: what the story adds to priv/static/app.css. The board
// carries it in <style id="proposal">; the "Before" frames do not need it
// because no rule matches their markup.
const PROPOSAL_CSS = `
/* I1 (#1351) ①: the section's ⓘ sits beside its heading. The wrapper keeps
   the heading a pure heading (a <details> is not phrasing content). */
.section-title {
  display: flex;
  align-items: center;
  gap: var(--space-1);
  min-width: 0;
}
.section-title > .metric-tooltip--inline {
  margin-left: 0;
}
/* ① the section's panel holds several method lines: wider than a term's. */
.metric-tooltip--section p {
  width: 26rem;
  max-width: calc(100vw - 2rem);
}
/* #1336 ⑦: the panel opens upward by default and below when there is no
   room above; the TooltipPlacement hook sets data-place on toggle and
   --tip-shift so both panel edges stay 1rem inside the viewport. */
.metric-tooltip[data-place="below"] p {
  top: calc(100% + 0.4rem);
  bottom: auto;
}
.metric-tooltip--inline p {
  left: var(--tip-shift, 0px);
}
/* #1350 ⑥: the view switcher's ⓘ is a metric-tooltip like every other ⓘ,
   so its panel floats instead of pushing the KPI cards down. */
.view-switcher__help.metric-tooltip {
  margin-left: 0;
}
/* I1 ③: a data note's text clamps to two lines, three under 560 px; its
   remedy controls stay visible below the text. */
.data-note__text {
  min-width: 0;
}
.data-note--clamped .data-note__text {
  display: -webkit-box;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
  overflow: hidden;
}
.data-note__actions {
  margin-top: var(--space-2);
}
.data-note__more {
  flex: none;
  align-self: flex-end;
  margin-left: auto;
  color: inherit;
  font-size: 12px;
}
@media (max-width: 560px) {
  .data-note--clamped .data-note__text {
    -webkit-line-clamp: 3;
  }
}
/* I1 ④: two or more attention/note items in one block fold into one line
   with their counts, at the highest folded severity. */
.data-note-group {
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  background: var(--color-bg-muted);
}
.data-note-group--attention {
  border-color: var(--color-warning);
  background: var(--color-warning-soft);
}
.data-note-group > summary {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-1) var(--space-2);
  padding: var(--space-2) var(--space-3);
  cursor: pointer;
  list-style: none;
  font-size: 12px;
}
.data-note-group > summary::-webkit-details-marker {
  display: none;
}
.data-note-group__count {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 11px;
  font-weight: 650;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}
.data-note-group__count--attention {
  color: var(--color-warning);
}
.data-note-group__count--note {
  color: var(--color-text-muted);
}
.data-note-group__toggle {
  color: var(--color-text-muted);
  text-decoration: underline;
  text-underline-offset: 2px;
}
.data-note-group__body {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  padding: 0 var(--space-3) var(--space-3);
}
`;

// The board's pins, also present while the live page is measured, so the
// measured places hold with the pins drawn.
const PIN_CSS = `
.mock-pin { display: inline-grid; place-items: center; flex: none; width: 20px; height: 20px; border-radius: 50%; background: #c026d3; color: #fff; font: 700 12px/1 var(--font-sans); letter-spacing: 0; text-transform: none; margin-left: 6px; vertical-align: middle; box-shadow: 0 0 0 2px #fff; z-index: 60; }
.mock-pin--abs { position: absolute; left: -9px; top: -9px; margin: 0; }
.mock-pin--pre { margin: 0 6px 0 0; }
.mock-pinned { position: relative; }
`;

// Notes that name rows left out of a total next to them (UX-DR25). They
// clamp but never fold: the owner's decision keeps their count visible.
const EXCLUSION_NOTES = [
  'dq-no-price', 'dq-missing-fx', 'dq-unvalued-cash', 'contribution-unvalued',
  'wealth-card-excluded', 'trades-card-excluded', 'realized-excluded', 'realized-unmatched'
];

// Basis lines whose method parts move. Each entry: the line, how it splits,
// which parts move (the rest stays as the basis line), and the ⓘ they join.
const MOVES = {
  '/': [
    { line: '[data-role="trades-card-basis"]', split: 'clause', move: ['^p\\. a\\. erst ab'], heading: '#dashboard-trades h2' },
    { line: '[data-role="upcoming-basis"]', split: 'sentence', move: ['^Ein als Zeitraum oder Monat'], heading: '#dashboard-upcoming > h2' }
  ],
  '/portfolio': [
    { line: '[data-role="contribution-basis"]', split: 'clause', move: ['^Beitrag =', '^Anfangswert:', '^Positionen und Restposten'], heading: '#contribution-title' }
  ],
  '/cashflow?tab=realized': [
    { line: '[data-role="trades-basis"]', split: 'clause', move: ['^Einlieferungen eröffnen keinen Lot', '^p\\. a\\. erst ab'], into: '[data-role="facet-info"]' }
  ]
};

// ---------------------------------------------------------------- pages
const PAGES = [
  { key: 'wealth', url: '/portfolio', title: 'Vermögen — Bestände, above the positions table' },
  { key: 'overview', url: '/', title: 'Übersicht' },
  { key: 'cash', url: '/cashflow?tab=realized', title: 'Cashflow — Trades, the facet ⓘ opened' }
];

// Runs in the page: cut what the board does not need, the same in both frames.
function trim(key) {
  const elide = (el, text) => {
    const d = document.createElement(el.tagName === 'LI' || el.tagName === 'TR' ? el.tagName : 'div');
    d.className = 'mock-elided';
    if (el.tagName === 'TR') { d.innerHTML = '<td colspan="9">' + text + '</td>'; } else { d.textContent = text; }
    el.replaceWith(d);
    return d;
  };
  const cutList = (sel, keep, label) => {
    const items = [...document.querySelectorAll(sel)];
    if (items.length <= keep) return;
    const rest = items.slice(keep);
    rest.slice(1).forEach(x => x.remove());
    elide(rest[0], '… ' + rest.length + ' more ' + label + ', cut for the board');
  };
  document.querySelectorAll('main script').forEach(s => s.remove());
  if (key === 'wealth') {
    document.querySelectorAll('#portfolio-positions, #portfolio-cash').forEach(s => {
      let n = s; while (n) { const next = n.nextElementSibling; n.remove(); n = next; }
    });
    const support = document.querySelector('#portfolio-kpis .kpi-band__support');
    if (support) elide(support, 'Four more KPI cards — unchanged, cut for the board');
    const chart = document.querySelector('#performance-figure');
    if (chart) elide(chart, 'Performance chart and its table — unchanged, cut for the board');
    cutList('#contribution-table tbody tr[data-role="contribution-row"]', 3, 'rows');
    const rest = [...document.querySelectorAll('#contribution-table tbody tr.contribution-table__more, #contribution-table tbody tr.contribution-table__rest-head, #contribution-table tbody tr.contribution-table__rest')];
    if (rest.length) { rest.slice(1).forEach(x => x.remove()); elide(rest[0], '… the hidden-rows line and the three rows that belong to no position, cut for the board'); }
    const prest = [...document.querySelectorAll('#contribution-phone-rows li.contribution-phone-rows__more, #contribution-phone-rows li.contribution-phone-rows__rest')];
    if (prest.length) { prest.slice(1).forEach(x => x.remove()); elide(prest[0], '… the hidden-rows line and the rest row, cut for the board'); }
    cutList('#contribution-phone-rows li[data-role="contribution-row"]', 3, 'rows');
  }
  if (key === 'overview') {
    cutList('#dashboard-trades .attention-list > li', 1, 'trades');
    cutList('#dashboard-attention .attention-list > li', 0, 'categories (unchanged)');
    cutList('#dashboard-upcoming .attention-list > li', 1, 'dates');
  }
  if (key === 'cash') {
    const annual = document.querySelector('#realized-annual');
    if (annual) { let n = annual; while (n) { const next = n.nextElementSibling; n.remove(); n = next; } }
    const figs = document.querySelector('#realized-figures');
    if (figs) elide(figs, 'The three figures — unchanged, cut for the board');
    cutList('#realized-trades-table tbody tr', 1, 'trades');
    cutList('#realized-trades-phone-rows > li', 1, 'trades');
  }
}

// Runs in the page: the variant-R change, as markup.
function applyR(args) {
  const { moves, exclusions, css, vw } = args;
  const st = document.createElement('style');
  st.id = 'mock-measure';
  st.textContent = css + args.pinCss;
  document.head.appendChild(st);

  // ① ② the method parts move into the section's ⓘ; the basis stays.
  const sectionTip = (heading) => {
    const h = document.querySelector(heading);
    const wrap = document.createElement('div');
    wrap.className = 'section-title';
    h.replaceWith(wrap);
    wrap.appendChild(h);
    const d = document.createElement('details');
    d.className = 'metric-tooltip metric-tooltip--inline metric-tooltip--section';
    d.dataset.role = 'section-info';
    d.innerHTML = '<summary aria-label="Zu diesem Abschnitt">ⓘ</summary><p role="tooltip"></p>';
    wrap.appendChild(d);
    return d;
  };
  for (const m of moves) {
    const line = document.querySelector(m.line);
    if (!line) continue;
    const text = line.textContent.trim().replace(/\s+/g, ' ');
    const parts = m.split === 'clause' ? text.split(' · ') : text.split(/(?<=\.)\s+(?=[A-ZÄÖÜ])/);
    const moved = parts.filter(p => m.move.some(r => new RegExp(r).test(p)));
    const kept = parts.filter(p => !moved.includes(p));
    line.textContent = kept.join(m.split === 'clause' ? ' · ' : ' ');
    const tip = m.into ? document.querySelector(m.into) : sectionTip(m.heading);
    const p = tip.querySelector('p');
    // One source line per line; below an existing text, after a blank line.
    if (m.into && moved.length) { p.appendChild(document.createElement('br')); p.appendChild(document.createElement('br')); }
    moved.forEach((t, i) => {
      if (i > 0) p.appendChild(document.createElement('br'));
      p.appendChild(document.createTextNode(t));
    });
  }

  // ⑥ #1350: the view switcher's ⓘ becomes a metric-tooltip.
  const vs = document.querySelector('details.view-switcher__help');
  if (vs) vs.classList.add('metric-tooltip', 'metric-tooltip--inline');

  // ③ every note clamps; its remedy controls stay visible below the text.
  const notes = [...document.querySelectorAll('main .data-note')].filter(n => !n.closest('table'));
  const sev = n => n.classList.contains('data-note--problem') ? 'problem' : n.classList.contains('data-note--attention') ? 'attention' : 'note';
  notes.forEach(n => {
    const body = n.querySelector('.data-note__body');
    if (!body) return;
    const text = document.createElement('div');
    text.className = 'data-note__text';
    const actions = document.createElement('div');
    actions.className = 'data-note__actions';
    [...body.childNodes].forEach(c => {
      if (c.nodeType === 1 && c.matches('.fx-sync, details')) { actions.appendChild(c); return; }
      if (c.nodeType === 1 && c.matches('.fx-backfill')) {
        // The reason the remedy can or cannot act stays in the note's text
        // (UX-DR25 clause 3); the button stays visible.
        c.querySelectorAll('.muted').forEach(m => { text.appendChild(document.createTextNode(' ')); text.appendChild(m); });
        actions.appendChild(c);
        return;
      }
      text.appendChild(c);
    });
    body.appendChild(text);
    if (actions.childNodes.length) body.appendChild(actions);
    n.classList.add('data-note--clamped');
    const more = document.createElement('button');
    more.type = 'button';
    more.className = 'link-button data-note__more';
    more.setAttribute('aria-expanded', 'false');
    more.textContent = 'mehr';
    n.appendChild(more);
  });
  // "mehr" only where the clamp cuts (measured before folding hides notes).
  notes.forEach(n => {
    const t = n.querySelector('.data-note__text');
    const more = n.querySelector('.data-note__more');
    if (t && more && t.scrollHeight <= t.clientHeight + 1) more.remove();
  });

  // ④ ⑤ fold: per block, problems stay, exclusions stay, the rest folds when two or more.
  const iconOf = s => { const n = notes.find(x => sev(x) === s); return n ? n.querySelector('.data-note__icon').innerHTML : ''; };
  const byParent = new Map();
  notes.forEach(n => { const p = n.parentElement; if (!byParent.has(p)) byParent.set(p, []); byParent.get(p).push(n); });
  byParent.forEach((ns) => {
    const foldable = ns.filter(n => sev(n) !== 'problem' && !exclusions.includes(n.dataset.role));
    if (foldable.length < 2) return;
    const cnt = { attention: 0, note: 0 };
    foldable.forEach(n => cnt[sev(n)]++);
    const worst = cnt.attention ? 'attention' : 'note';
    const d = document.createElement('details');
    d.className = 'data-note-group data-note-group--' + worst;
    d.dataset.role = 'folded-notes';
    const parts = [];
    if (cnt.attention) parts.push('<span class="data-note-group__count data-note-group__count--attention"><span aria-hidden="true">' + iconOf('attention') + '</span>' + cnt.attention + ' Achtung</span>');
    if (cnt.note) parts.push('<span class="data-note-group__count data-note-group__count--note"><span aria-hidden="true">' + iconOf('note') + '</span>' + cnt.note + (cnt.note > 1 ? ' Hinweise' : ' Hinweis') + '</span>');
    d.innerHTML = '<summary>' + parts.join('<span aria-hidden="true">·</span>') + '<span class="data-note-group__toggle">— Details anzeigen</span></summary><div class="data-note-group__body"></div>';
    const last = ns[ns.length - 1];
    last.after(d);
    foldable.forEach(n => d.querySelector('.data-note-group__body').appendChild(n));
    // Problems first, then the notes that stay, then the folded line.
    const parent = d.parentElement;
    const mark = document.createComment('problems');
    parent.insertBefore(mark, parent.firstChild);
    ns.filter(n => sev(n) === 'problem').forEach(n => parent.insertBefore(n, mark));
    mark.remove();
  });
  return vw;
}

// Runs in the page: opens a <details> and, for "after", places its panel as
// the #1336 hook would (below when there is no room above; shifted inside).
function openTip(args) {
  const { sel, place } = args;
  const d = document.querySelector(sel);
  if (!d) return null;
  d.open = true;
  if (!place) return d.querySelector('p').getBoundingClientRect().toJSON();
  const vw = document.documentElement.clientWidth;
  const s = d.querySelector('summary').getBoundingClientRect();
  const p = d.querySelector('p');
  const h = p.getBoundingClientRect().height;
  if (s.top - h - 8 < 0) d.dataset.place = 'below';
  d.style.removeProperty('--tip-shift');
  const r = p.getBoundingClientRect();
  const edge = 16;
  let shift = 0;
  if (r.right > vw - edge) shift = (vw - edge) - r.right;
  if (r.left + shift < edge) shift = edge - r.left;
  if (shift) d.style.setProperty('--tip-shift', Math.round(shift) + 'px');
  return { place: d.dataset.place || 'above', shift: Math.round(shift) };
}

// Runs in the page: numbered pins. abs: pinned to the target's top-left corner.
function pin(args) {
  const { sel, n, mode } = args;
  const t = typeof sel === 'string' ? document.querySelector(sel) : null;
  if (!t) return false;
  const s = document.createElement('span');
  s.className = 'mock-pin' + (mode === 'abs' ? ' mock-pin--abs' : '');
  s.textContent = String('①②③④⑤⑥⑦⑧'.indexOf(n) + 1);
  s.title = n;
  if (mode === 'pre') { t.prepend(s); s.classList.add('mock-pin--pre'); return true; }
  if (mode === 'abs') { if (getComputedStyle(t).position === 'static') t.classList.add('mock-pinned'); t.prepend(s); } else if (mode === 'after') { t.after(s); } else { t.appendChild(s); }
  return true;
}

function capture(withTopbar) {
  document.getElementById('mock-measure')?.remove();
  const clean = h => h
    .replace(/\s(?:data-phx-[\w-]+|phx-[\w-]+)="[^"]*"/g, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/\n\s*\n+/g, '\n')
    .replace(/(src|href)="\/(images|favicon)/g, '$1="../../../../../priv/static/$2');
  return (withTopbar ? clean(document.querySelector('header.topbar').outerHTML) + '\n' : '') + clean(document.querySelector('main').outerHTML);
}

async function load(page, url) {
  await page.goto(BASE + url + (url.includes('?') ? '&' : '?') + 'locale=de', { waitUntil: 'networkidle' });
  await page.waitForTimeout(1800); // the count-up settles
}

const PINS = {
  wealth: {
    before: [{ sel: 'details.view-switcher__help > p', n: '⑥', mode: 'abs' }],
    after: [
      { sel: 'details.view-switcher__help > p', n: '⑥', mode: 'abs' },
      { sel: '#portfolio-data-quality .data-note--problem', n: '⑤', mode: 'abs' },
      { sel: '[data-role="dq-missing-fx"]', n: '③', mode: 'abs' },
      { sel: '[data-role="folded-notes"]', n: '④', mode: 'abs' },
      { sel: '[data-role="performance-basis"]', n: '②', mode: 'pre' },
      { sel: '#performance-contribution .section-title', n: '①', mode: 'in' },
      { sel: '[data-role="contribution-basis"]', n: '②', mode: 'pre' },
      { sel: '[data-role="contribution-unvalued"]', n: '③', mode: 'abs' }
    ]
  },
  overview: {
    before: [],
    after: [
      { sel: '[data-role="wealth-card-excluded"]', n: '③', mode: 'abs' },
      { sel: '[data-role="kpi-strip-basis"]', n: '②', mode: 'pre' },
      { sel: '#dashboard-trades .section-title', n: '①', mode: 'in' },
      { sel: '[data-role="trades-card-basis"]', n: '②', mode: 'pre' },
      { sel: '#dashboard-upcoming .section-title', n: '①', mode: 'in' },
      { sel: '[data-role="data-quality-line"]', n: '⑤', mode: 'abs' }
    ]
  },
  cash: {
    before: [{ sel: '[data-role="facet-info"] > p', n: '⑦', mode: 'abs' }],
    after: [
      { sel: '[data-role="facet-basis"]', n: '⑦', mode: 'pre' },
      { sel: '[data-role="realized-excluded"]', n: '③', mode: 'abs' },
      { sel: '[data-role="trades-basis"]', n: '②', mode: 'pre' }
    ]
  }
};

// Which ⓘ is open in each frame.
const OPEN = {
  wealth: { before: ['details.view-switcher__help'], after: ['details.view-switcher__help'] },
  overview: { before: [], after: ['#dashboard-trades [data-role="section-info"]'] },
  cash: { before: ['[data-role="facet-info"]'], after: ['[data-role="facet-info"]'] }
};

async function framesAt(browser, vw) {
  const page = await browser.newPage({ viewport: { width: vw, height: 900 } });
  const out = {};
  for (const pg of PAGES) {
    out[pg.key] = {};
    for (const state of ['before', 'after']) {
      await load(page, pg.url);
      await page.evaluate(trim, pg.key);
      const facts = {};
      if (state === 'after') {
        await page.evaluate(applyR, { moves: MOVES[pg.url] || [], exclusions: EXCLUSION_NOTES, css: PROPOSAL_CSS, pinCss: PIN_CSS, vw })
          .catch(e => { throw e; });
      }
      // "Before" is measured as shipped, so the pins come after; "after" is
      // measured with its pins in place, as the board shows it.
      const pins = async (list) => { for (const p of list) { if (!(await page.evaluate(pin, p))) console.warn('pin not placed', pg.key, state, p.sel); } };
      const all = PINS[pg.key][state];
      if (state === 'after') await pins(all.filter(p => !p.sel.endsWith('> p')));
      for (const sel of OPEN[pg.key][state]) facts[sel] = await page.evaluate(openTip, { sel, place: state === 'after' });
      await pins(state === 'after' ? all.filter(p => p.sel.endsWith('> p')) : all);
      // The top bar only where the frame must be the viewport (the ⓘ panel's place).
      out[pg.key][state] = { html: await page.evaluate(capture, pg.key === 'cash'), facts };
      console.log(vw, pg.key, state, JSON.stringify(facts));
    }
  }
  await page.close();
  return out;
}

module.exports = { PIN_CSS, PROPOSAL_CSS, EXCLUSION_NOTES, MOVES, PAGES, trim, applyR, openTip, pin, capture, load, framesAt, PINS, OPEN };

if (require.main === module) {
  require('./board.js').main().catch(e => { console.error(e); process.exit(1); });
}
