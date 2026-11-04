// Builds the Sprint 24 boards (01 the journal's time filter, I16; 02 the
// costs beside the benchmark gap, I17) from the running review instance.
// Copied from the Sprint 23 boards' build.js; only this header and the
// proposal CSS below differ.
//
// Every frame is captured from the instance on the synthetic review seed
// (priv/demo/finding_surfaces_seed.exs) with read-only steps: GET requests,
// client-side <details> toggles; the benchmark is picked by its URL
// parameter (benchmark_rate=5), which the page only remembers.
// Nothing is submitted. A frame's "after" state is the shipped markup with
// the proposal applied to the live DOM as markup (preps below); where the
// seed has no row for a state, the prep writes a synthetic row into the
// shipped markup of a real one and the board says so.
//
// Each frame is written as its own static page under frames/ (it links the
// real priv/static/app.css), measured, and placed on a board by board.js as
// an <iframe>. No script runs on any board or frame page.
//
// Usage (the server on port 4003, see README.md):
//   node build.js     # captures every frame, writes frames/ and the boards
//   node render.js    # renders the boards to PNG
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const BASE = process.env.BASE || 'http://localhost:4003';
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
/* 01 A: the journal's date field sits in the filter form beside the kind. */
.journal-filters__since { display: inline-flex; align-items: center; gap: 6px; font-size: 13px; }
.journal-filters__since input[type="date"] { font: inherit; }
/* 02: the costs line under the benchmark rows, the rows' detail anatomy. */
.benchmark-costs { display: block; margin-top: var(--space-1); font-size: 12.5px; color: var(--color-text-muted); }
.benchmark-costs .benchmark-costs__fig { font-weight: 600; color: var(--color-text); font-variant-numeric: tabular-nums; }
.benchmark-row__split { display: block; font-size: 12.5px; color: var(--color-text-muted); }
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
    .replace(/(src|href)="\/(images|favicon)/g, '$1="../../../../../../priv/static/$2')
    .replace(/\n\s*\n+/g, '\n');
  return { html, width, sidebar: !!document.querySelector('#app-sidebar') };
}

async function trigger(page, attrs) {
  await page.evaluate((a) => {
    const x = document.createElement('button');
    x.id = 'mock-trigger';
    x.type = 'button';
    Object.entries(a).forEach(([k, v]) => x.setAttribute(k, v));
    (document.querySelector('[data-phx-main]') || document.querySelector('main')).appendChild(x);
  }, attrs);
  await page.evaluate(() => document.getElementById('mock-trigger').click());
  await page.waitForTimeout(900);
}

async function load(page, url) {
  await page.goto(BASE + url + (url.includes('?') ? '&' : '?') + 'locale=de', { waitUntil: 'networkidle' });
  await page.waitForTimeout(1600);
}

// ------------------------------------------------------------ the frames
const F = require('./frames.js')({ de, trigger });

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

// Injected markup arrives on one line; long lines break before block tags,
// so a frame stays a readable multiline file (AGENTS.md).
const BLOCK = /><(?=(?:tr|li|section|details|table|thead|tbody|div|p|ul|label|form|fieldset)[\s>])/g;
const tidy = (s) => s.split('\n').map(l => (l.length > 300 ? l.replace(BLOCK, '>\n<') : l)).join('\n').split('\n').map(l => l.replace(/[ \t]+$/, '')).filter((l, i, a) => l !== '' || a[i - 1] !== '').join('\n');

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
      const width = vw > 600 ? (f.frameWidth || r.width || 1060) : 390;
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
        await m.close();
        out[`${id}@${vw}`] = { file: 'frames/' + file, width, height };
        console.log(vw, id, width + 'x' + height);
      }
    }
  }
  return out;
}

module.exports = { de, PROPOSAL_CSS, FRAME_CSS };

if (require.main === module) {
  (async () => {
    const browser = await chromium.launch();
    const sizesFile = path.join(FRAMES, 'sizes.json');
    const prev = process.env.ONLY && fs.existsSync(sizesFile) ? JSON.parse(fs.readFileSync(sizesFile, 'utf8')) : {};
    const sizes = Object.assign(prev, await captureAll(browser));
    await browser.close();
    fs.writeFileSync(sizesFile, JSON.stringify(sizes, null, 2) + '\n');
    require('./board.js').main(sizes);
  })().catch(e => { console.error(e); process.exit(1); });
}
