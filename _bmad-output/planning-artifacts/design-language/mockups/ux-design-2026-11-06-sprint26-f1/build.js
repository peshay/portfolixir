// Builds the Sprint 26 planning board 02 (idea F1, ADR-0055 §5: the human
// view of predictions and of the calibration report) from the running review
// instance. Copied from the Sprint 24 P1 board's build.js
// (../ux-design-2026-11-05-sprint24-p1/), itself the Sprint 23 and 24
// boards' tooling; this header, the proposal CSS, the frame CSS (the native
// confirm, the synthetic stripe on cards and table rows) and the logo path
// differ.
//
// Every frame is captured from the instance on the synthetic review seed
// (priv/demo/finding_surfaces_seed.exs) with read-only steps: GET requests
// only. Nothing is clicked or submitted. The seed holds
// no prediction, so a frame's new UI is written into the live DOM from the
// shipped classes (preps in frames.js), dashed (mock-new), and every
// invented prediction carries the amber stripe (mock-synth).
//
// Each frame is written as its own static page under frames/ (it links the
// real priv/static/app.css), measured, and placed on a board by board.js as
// an <iframe>. No script runs on any board or frame page.
//
// Usage (the server on port 4011, see README.md):
//   node build.js     # captures every frame, writes frames/ and the boards
//   node render.js    # renders the boards to PNG
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const BASE = process.env.BASE || 'http://localhost:4011';
const REPO = path.resolve(__dirname, '../../../../..');
const FRAMES = path.join(__dirname, 'frames');

// ------------------------------------------------------------ the catalogue
// The German strings that exist come from the catalogue itself, so a frame
// never carries a paraphrase of a shipped string.
function parsePo(text) {
  const map = new Map();
  let cur = {};
  let field = null;
  const flush = () => {
    if (cur.msgid !== undefined) map.set((cur.msgctxt || '') + '\u0004' + cur.msgid, cur);
    cur = {};
    field = null;
  };
  const unq = (s) => JSON.parse(s);
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (line === '') { flush(); continue; }
    if (line.startsWith('#')) continue;
    const m = line.match(/^(msgctxt|msgid_plural|msgid|msgstr(?:\[\d\])?)\s+(".*")$/);
    if (m) {
      if (m[1] === 'msgid' && cur.msgid !== undefined) flush();
      field = m[1];
      cur[field] = unq(m[2]);
    } else if (line.startsWith('"') && field) {
      cur[field] += unq(line);
    }
  }
  flush();
  return map;
}
const PO = parsePo(fs.readFileSync(path.join(REPO, 'priv/gettext/de/LC_MESSAGES/default.po'), 'utf8'));
// de(msgid[, count, bindings, ctxt]): the German msgstr, plural-aware.
function de(msgid, count, bindings = {}, ctxt = '') {
  const e = PO.get(ctxt + '\u0004' + msgid);
  if (!e) throw new Error('not in the catalogue: ' + msgid);
  let s = e.msgid_plural !== undefined ? e[count === 1 ? 'msgstr[0]' : 'msgstr[1]'] : e.msgstr;
  if (!s) throw new Error('no translation: ' + msgid);
  const b = Object.assign({ count }, bindings);
  return s.replace(/%\{(\w+)\}/g, (_, k) => (b[k] !== undefined ? b[k] : '%{' + k + '}'));
}

// ------------------------------------------------------------ frame chrome
// The proposal: what the stories add to priv/static/app.css. Frames marked
// `proposal` carry it; the "today" frames render app.css as shipped.
const PROPOSAL_CSS = `
/* F1 (ADR-0055 §5): the security's Prognosen tab. The list is the research
   timeline's anatomy (.research-timeline, .research-entry, its head, meta,
   facts and body); only the claim line, the probability, the status's left
   edge and the reason line are new. */
.prediction-entry__claim { margin: 0; display: flex; flex-wrap: wrap; align-items: baseline; gap: var(--space-1) var(--space-3); }
.prediction-entry__claim strong { font-weight: 650; }
.prediction-entry__p { font-variant-numeric: tabular-nums; font-weight: 700; white-space: nowrap; }
.prediction-entry__p-label { font-size: 11px; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; color: var(--color-text-muted); }
.prediction-entry__facts dd.num { font-variant-numeric: tabular-nums; white-space: nowrap; }
.prediction-entry p.research-entry__meta { margin: 0; }
.prediction-entry__reason { margin: 0; font-size: 12px; color: var(--color-text-muted); }
.research-entry.prediction-entry--hit { border-left-color: var(--color-positive); }
.research-entry.prediction-entry--miss { border-left-color: var(--color-border-strong); }
.research-entry.prediction-entry--unresolved { border-left-style: dashed; border-left-color: var(--color-border-strong); }
/* The report: the KPI band's compact cards, data tables, the summary-basis
   voice; new are the bands' "too few" sentence and the model rows' indent. */
.prediction-filters { margin: 0 0 var(--space-4); }
.prediction-bands, .prediction-groups { margin-top: var(--space-5); display: grid; gap: var(--space-2); }
.prediction-bands__why { margin: 0; max-width: 72ch; font-size: 13px; }
.prediction-too-few { color: var(--color-text-muted); font-size: 12px; }
.prediction-groups__model td:first-child { padding-left: 1.75rem; color: var(--color-text-muted); }
.prediction-list-table td.cell-name a { display: block; }
/* The list fits its wrapper (Risk's fit tables, Sprint 24 P1's floor and
   break): the name cell keeps a 14 rem floor and wraps, figures never do. */
.data-table-wrapper > .prediction-list-table { min-width: 0; }
.prediction-list-table td.cell-name { min-width: 14rem; overflow-wrap: anywhere; }
.prediction-list-table td.num { white-space: nowrap; }
.prediction-list-table td .policy-rule__words { display: block; }
.prediction-list-table td.cell-name .policy-rule__words { white-space: normal; }
.prediction-list-table td .badge { white-space: normal; }
.filter-chip__count { margin-left: 0.4em; color: var(--color-text-muted); font-variant-numeric: tabular-nums; }
.prediction-bands .section-title h3, .prediction-groups .section-title h3 { margin: 0; }
.prediction-list-table td .badge + .policy-rule__reason { display: block; }
/* Rows without a logo: the body takes the elastic track (as the trades'). */
#prediction-list-phone-rows .phone-row,
#prediction-groups-phone-rows .phone-row { grid-template-columns: minmax(0, 1fr) auto; }
@media (max-width: 560px) {
  #prediction-list-table-wrap { display: none; }
  .research-entry__facts.prediction-entry__facts { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  #prediction-groups-table-wrap { display: none; }
}
`;

const FRAME_CSS = `
body { margin: 0; background: var(--color-bg); }
body.mock-noside .app-frame { padding-left: 0 !important; }
.app-shell, .app-frame, .app-main, .workspace-page { min-height: 0 !important; }
.app-main { padding-bottom: 12px; }
.topbar { position: relative !important; top: auto !important; }
.transactions-columns { display: block !important; }
dialog[open] { position: static !important; inset: auto !important; transform: none !important; margin: 0 !important; max-height: none !important; box-shadow: none !important; }
dialog.booking-drawer { position: static !important; max-height: none !important; margin: 0 !important; }
.modal-body { max-height: none !important; overflow: visible !important; }
.mock-new { outline: 2px dashed var(--color-accent); outline-offset: 2px; border-radius: 4px; }
tr.mock-new { outline-offset: -2px; }
.mock-synth { box-shadow: inset 3px 0 0 #f59e0b; }
tr.mock-synth { box-shadow: none; }
p.mock-synth, li.phone-row.mock-synth { padding-left: 9px; }
tr.mock-synth > td:first-child { box-shadow: inset 3px 0 0 #f59e0b; }
.stat.mock-synth { box-shadow: inset 3px 0 0 #f59e0b, var(--shadow-panel); }
.mock-report { padding: 4px; }
.native-confirm { margin: 14px auto 18px; width: 460px; box-sizing: border-box; border: 1px solid #c9ced6; border-radius: 10px; background: #fff; color: #1f2937; box-shadow: 0 8px 24px rgba(0, 0, 0, .18); padding: 12px 14px; font: 13px/1.45 system-ui, sans-serif; }
.native-confirm p { margin: 0 0 8px; }
.native-confirm .origin { font-weight: 600; font-size: 12.5px; }
.native-confirm .btns { display: flex; justify-content: flex-end; gap: 8px; }
.native-confirm .btns span { padding: 4px 14px; border-radius: 6px; border: 1px solid #c9ced6; font-size: 12.5px; }
.native-confirm .btns span.ok { background: #2563eb; border-color: #2563eb; color: #fff; }
.native-confirm.mock-new { outline-offset: 3px; }
.workspace-panel, .securities-workspace, .securities-workspace--split { display: block !important; height: auto !important; max-height: none !important; overflow: visible !important; }
.detail-pane { overflow: visible !important; max-height: none !important; }
.securities-list-pane, .securities-list-pane .data-table-wrapper, .workspace-panel .data-table-wrapper { height: auto !important; min-height: 0 !important; }
.mock-pin { display: inline-grid; place-items: center; flex: none; width: 20px; height: 20px; border-radius: 50%; background: #c026d3; color: #fff; font: 700 12px/1 var(--font-sans); letter-spacing: 0; text-transform: none; margin: 0 4px; vertical-align: middle; box-shadow: 0 0 0 2px #fff; }
.mock-pin--abs { position: absolute; left: -8px; top: -8px; margin: 0; z-index: 60; }
.mock-pinned { position: relative; }
.mock-elided { margin: 8px 0; padding: 6px 10px; border: 1px dashed var(--color-border-strong); border-radius: 6px; font-size: 11.5px; color: var(--color-text-muted); list-style: none; text-align: center; }
tr.mock-elided td { padding: 6px 10px; font-size: 11.5px; color: var(--color-text-muted); text-align: center; }
`;

const ICONS = {
  problem: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M7.86 2h8.28L22 7.86v8.28L16.14 22H7.86L2 16.14V7.86L7.86 2Z"></path><path d="M12 8v4"></path><circle cx="12" cy="16" r=".6"></circle></svg>',
  attention: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0Z"></path><path d="M12 9v4"></path><circle cx="12" cy="17" r=".6"></circle></svg>',
  note: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5.94 8.5l12.12 7M18.06 8.5l-12.12 7"></path></svg>'
};

// In-page helpers, injected before a prep runs (window.M).
const HELPERS = `
window.M = {
  icons: ${JSON.stringify(ICONS)},
  words: { problem: 'Problem', attention: 'Achtung', note: 'Hinweis' },
  el(html) { const t = document.createElement('template'); t.innerHTML = html.trim(); return t.content.firstElementChild; },
  // A data note in AppShell.data_note's markup; clamp puts the text and the
  // actions apart, as the shipped component does.
  note(sev, text, o = {}) {
    const id = o.id || ('mock-note-' + Math.random().toString(36).slice(2, 8));
    const body = o.clamp
      ? '<div class="data-note__body"><div id="' + id + '-text" class="data-note__text">' + text + '</div>' + (o.actions ? '<div class="data-note__actions">' + o.actions + '</div>' : '') + '</div><button type="button" class="link-button data-note__more" aria-expanded="false" hidden>mehr</button>'
      : '<div class="data-note__body">' + text + (o.actions || '') + '</div>';
    return this.el('<div id="' + id + '" class="data-note data-note--' + sev + (o.clamp ? ' data-note--clamped' : '') + (o.isNew ? ' mock-new' : '') + '"' + (o.role ? ' data-role="' + o.role + '"' : '') + '><span class="data-note__icon" aria-hidden="true">' + this.icons[sev] + '</span><span class="data-note__word">' + this.words[sev] + '</span>' + body + '</div>');
  },
  pin(target, n, mode) {
    const t = typeof target === 'string' ? document.querySelector(target) : target;
    if (!t) { console.warn('pin target missing', target); return; }
    const s = document.createElement('span');
    s.className = 'mock-pin' + (mode === 'abs' ? ' mock-pin--abs' : '');
    s.textContent = String(n);
    if (mode === 'abs') { if (getComputedStyle(t).position === 'static') t.classList.add('mock-pinned'); t.prepend(s); }
    else if (mode === 'pre') t.prepend(s);
    else if (mode === 'after') t.after(s);
    else t.appendChild(s);
  },
  neu(el) { if (typeof el === 'string') el = document.querySelector(el); if (el) el.classList.add('mock-new'); return el; },
  elide(el, text, tag) {
    const d = document.createElement(tag || (el.tagName === 'TR' ? 'tr' : el.tagName === 'LI' ? 'li' : 'div'));
    d.className = 'mock-elided';
    if (d.tagName === 'TR') d.innerHTML = '<td colspan="12">' + text + '</td>'; else d.textContent = text;
    el.replaceWith(d);
    return d;
  },
  // Keep the first n of a list, the rest become one elided line.
  cut(sel, keep, text) {
    const items = [...document.querySelectorAll(sel)];
    if (items.length <= keep) return;
    const rest = items.slice(keep);
    rest.slice(1).forEach(x => x.remove());
    this.elide(rest[0], text.replace('%n', rest.length));
  },
  setText(sel, text, root) { const e = (root || document).querySelector(sel); if (e) e.textContent = text; return e; },
  setHtml(sel, html, root) { const e = (root || document).querySelector(sel); if (e) e.innerHTML = html; return e; }
};
`;

// Runs in the page last: keep only the kept elements and their ancestors,
// then hand back the body's markup, cleaned.
function isolate(args) {
  const { keep, measure } = args;
  document.querySelectorAll('script, #mock-trigger').forEach(s => s.remove());
  const kept = keep.flatMap(s => [...document.querySelectorAll(s)]);
  const chain = new Set();
  kept.forEach(k => { let n = k; while (n && n !== document.body) { chain.add(n); n = n.parentElement; } });
  const visit = (el) => {
    [...el.children].forEach(c => {
      if (kept.includes(c)) return;
      if (chain.has(c)) visit(c); else c.remove();
    });
  };
  visit(document.body);
  let width = null;
  if (measure) { const m = document.querySelector(measure); if (m) width = Math.ceil(m.getBoundingClientRect().width); }
  const html = document.body.innerHTML
    .replace(/\s(?:data-phx-[\w-]+|phx-[\w-]+)="[^"]*"/g, '')
    .replace(/\sid="phx-[^"]*"/g, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/(src|href)="\/(images|favicon|security_logos)/g, '$1="../../../../../../priv/static/$2')
    .replace(/\n\s*\n+/g, '\n');
  return { html, width, sidebar: !!document.querySelector('#app-sidebar') };
}

async function load(page, url) {
  await page.goto(BASE + url + (url.includes('?') ? '&' : '?') + 'locale=de', { waitUntil: 'networkidle' });
  await page.waitForTimeout(1600);
}

// ------------------------------------------------------------ the frames
const F = require('./frames.js')({ de });

function framePage(f, body, sidebar, look = {}) {
  return `<!doctype html>
<html lang="de" data-theme="${look.theme || 'light'}" data-accent="${look.accent || 'violet'}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${f.id}</title>
<link rel="stylesheet" href="../../../../../../priv/static/app.css">
${f.proposal ? `<style id="proposal">${PROPOSAL_CSS}</style>\n` : ''}${look.css ? `<style id="proposal">${look.css}</style>\n` : ''}<style id="frame">${FRAME_CSS}${f.css || ''}</style>
</head>
<body class="${sidebar ? '' : 'mock-noside'}"${f.padTop ? ` style="padding-top:${f.padTop}px"` : ''}>
${body}
</body>
</html>
`;
}

// Injected markup arrives on one line; long lines break before their tags,
// so a frame stays a readable multiline file (AGENTS.md).
const BLOCK = /><(?=(?:tr|td|th|li|section|header|details|summary|table|thead|tbody|div|p|ul|ol|dl|dt|dd|label|form|fieldset|article|button|span|a|h2|h3|br|small|strong|svg|select|option)[\s>\/])/g;
const tidy = (s) => s.split('\n').map(l => (l.length > 200 ? l.replace(BLOCK, '>\n<').replace(/<br>(?=\S)/g, '<br>\n') : l)).join('\n').split('\n').map(l => l.replace(/[ \t]+$/, '')).filter((l, i, a) => l !== '' || a[i - 1] !== '').join('\n');

async function captureAll(browser) {
  fs.mkdirSync(FRAMES, { recursive: true });
  const out = {};
  const only = process.env.ONLY ? new RegExp(process.env.ONLY) : null;
  for (const f of F.FRAMES) {
    if (only && !only.test(f.id)) continue;
    for (const vw of f.widths || [1280, 390]) {
      const page = await browser.newPage({ viewport: { width: vw, height: 900 } });
      if (f.init) await page.addInitScript(f.init);
      page.on('console', m => { if (m.type() === 'warning') console.warn('  page:', m.text()); });
      await load(page, f.url);
      if (f.act) await f.act(page, vw);
      await page.evaluate(HELPERS);
      for (const p of [].concat(f.prep || [])) await page.evaluate(p.fn, Object.assign({ vw }, p.args || {}));
      const r = await page.evaluate(isolate, { keep: f.keep, measure: vw > 600 ? f.measure : null });
      await page.close();
      // A frame's own width: given per viewport where the sidebar is cut away
      // (the main column the viewport leaves), else the phone's viewport.
      const width = (f.frameWidths && f.frameWidths[vw]) || (vw > 600 ? (f.frameWidth || r.width || 1060) : vw);
      // One capture, one or more looks: board 04 writes the same markup
      // under each accent, theme and variant stylesheet.
      for (const look of f.looks || [{ suffix: '' }]) {
        if (look.widths && !look.widths.includes(vw)) continue;
        const id = f.id + (look.suffix || '');
        const file = `${id}--${vw}.html`;
        fs.writeFileSync(path.join(FRAMES, file), tidy(framePage(f, r.html, r.sidebar, look)));
        // Height at the frame's own width, every min-height released.
        const m = await browser.newPage({ viewport: { width, height: 120 } });
        await m.goto('file://' + path.join(FRAMES, file));
        await m.waitForTimeout(250);
        const height = await m.evaluate(() => Math.ceil(document.documentElement.scrollHeight));
        // What the board's text quotes: each frame's scroller, measured in
        // the static frame itself.
        const probe = f.probe ? await m.evaluate(f.probe) : null;
        await m.close();
        out[`${id}@${vw}`] = Object.assign({ file: 'frames/' + file, width, height }, probe ? { probe } : {});
        console.log(vw, id, width + 'x' + height, probe ? JSON.stringify(probe) : '');
      }
    }
  }
  return out;
}

module.exports = { de, PROPOSAL_CSS, FRAME_CSS };

if (require.main === module) {
  (async () => {
    const browser = await chromium.launch(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {});
    const sizesFile = path.join(FRAMES, 'sizes.json');
    const prev = process.env.ONLY && fs.existsSync(sizesFile) ? JSON.parse(fs.readFileSync(sizesFile, 'utf8')) : {};
    const sizes = Object.assign(prev, await captureAll(browser));
    await browser.close();
    fs.writeFileSync(sizesFile, JSON.stringify(sizes, null, 2) + '\n');
    if (fs.existsSync(path.join(__dirname, 'board.js'))) require('./board.js').main(sizes);
  })().catch(e => { console.error(e); process.exit(1); });
}
