// Builds the Sprint 23 Lane I board: I1's later pages (idea I1, #1351's
// rule, Sprint 22's board 01 and its classification), with #1339 and the
// re-read of Sprint 22 R5's exclusion sentences on Income.
//
// Adapted from Sprint 22's build.js (../ux-design-2026-11-01-sprint22/).
// For every frame and width it loads the shipped page twice from the review
// instance (synthetic review seed, read-only: GET requests, client-side
// <details> toggles, a tab click, a category expand and an import preview,
// which stores nothing before its confirmation). The first load is captured
// as "Before". On the second load variant R, with Sprint 22's Q1
// corrections, is applied to the live DOM as the page stories would render
// it — in the markup Sprint 22 built (`AppShell.section_info`, `data_note`
// with `clamp`, `data_note_fold`), so app.css draws it as shipped — measured
// at that width ("mehr" only where the clamp cuts), and captured as "After".
// The board files hold that markup as static HTML; they run no script.
//
// Usage (the server on port 4005, see README.md):
//   BASE=http://localhost:4005 node build.js   # writes 01-i1-later.html and 01-i1-later-390.html
//   node render.js                             # renders both to PNG
const fs = require('fs');
const path = require('path');

const BASE = process.env.BASE || 'http://localhost:4005';
const REPO = path.resolve(__dirname, '../../../../..');

// ------------------------------------------------------------ the catalogue
// Every existing German string comes from the catalogue, so a frame never
// carries a paraphrase of a shipped string (Sprint 23 board 02's helper).
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
  const s = e.msgid_plural !== undefined ? e[count === 1 ? 'msgstr[0]' : 'msgstr[1]'] : e.msgstr;
  if (!s) throw new Error('no translation: ' + msgid);
  const b = Object.assign({ count }, bindings);
  return s.replace(/%\{(\w+)\}/g, (_, k) => (b[k] !== undefined ? b[k] : '%{' + k + '}'));
}
// isNew(msgid): true when the catalogue has no such msgid (README's check).
const isNew = (msgid, ctxt = '') => !PO.has(ctxt + '\u0004' + msgid);

// The strings the build reads from the catalogue: Sprint 22's components.
const T = {
  section: de('About this section'),
  more: de('more', null, {}, 'data-note clamp'),
  less: de('less', null, {}, 'data-note clamp'),
  show: de('Show details'),
  hide: de('Hide details'),
  // The fold's words as templates (they cross into the page as text).
  attention: [de('%{count} Attention', 1, { count: '%{count}' }, 'data-note fold'), de('%{count} Attention', 2, { count: '%{count}' }, 'data-note fold')],
  note: [de('%{count} Note', 1, { count: '%{count}' }, 'data-note fold'), de('%{count} Note', 2, { count: '%{count}' }, 'data-note fold')]
};

// The NEW strings: English msgid drafts with their German. README.md lists
// each; NEW_CHECK below proves none is in the catalogue yet.
const NEW = {
  // Allocation: the overshoot note's remedy link leaves the sentence for the
  // note's actions, so the sentence ends with a full stop and the link reads
  // as a command of its own.
  overshoot: {
    msgid: 'The plan\'s top-level targets sum to %{sum} % — more than 100 %. Drift keeps steering against the stored weights.',
    de: 'Die Top-Level-Ziele des Plans summieren sich auf %{sum} % — mehr als 100 %. Die Drift steuert weiter gegen die gespeicherten Gewichte.'
  },
  overshootLink: { msgid: 'Trim the plan on the Classifications page', de: 'Plan auf der Klassifizierungsseite kürzen' },
  // Snapshots: the gaps note names rows left out of the comparison, so its
  // count leads (UX-DR25 under the clamp).
  gapsLead: {
    msgid: 'Not included: %{count} position with no usable quote or exchange rate at the as-of date — %{names}',
    plural: 'Not included: %{count} positions with no usable quote or exchange rate at the as-of date — %{names}',
    de1: 'Nicht enthalten: %{count} Position ohne verwendbaren Kurs oder Wechselkurs zum Stichtag — %{names}',
    de: 'Nicht enthalten: %{count} Positionen ohne verwendbaren Kurs oder Wechselkurs zum Stichtag — %{names}'
  },
  // Income (Cash flow → Trades): with two or more reasons the lead carries
  // every count, and each reason names its sales without a second count.
  reasonNames: { msgid: '%{reason}: %{securities}.', de: '%{reason}: %{securities}.' },
  // … and, as R5's sentences do (StoredText.ending_on), without the closing
  // full stop when the last name ends in one („Arbolia Inc.“).
  reasonNamesBare: { msgid: '%{reason}: %{securities}', de: '%{reason}: %{securities}' },
  reason: {
    no_rate: { msgid: 'No stored rate', de: 'Ohne gespeicherten Wechselkurs' },
    missing_leg: { msgid: 'Buy without a figure in the sale\'s currency', de: 'Kauf ohne Gegenwert in der Währung des Verkaufs' },
    third: { msgid: 'Third currency', de: 'Dritte Währung' },
    other: { msgid: 'Buy paid in another currency', de: 'Kauf in anderer Währung bezahlt' },
    zero: { msgid: 'Buy of amount zero', de: 'Kauf mit Betrag null' }
  },
  // … and what each reason means moves into the facet's ⓘ (method). The
  // facet's ⓘ already says what a missing rate does, so that one is not
  // repeated (⑥).
  reasonInfo: {
    missing_leg: { msgid: 'Buy without a figure in the sale\'s currency: a buy the sale closes has no figure in the sale\'s currency.', de: 'Kauf ohne Gegenwert in der Währung des Verkaufs: Ein Kauf, den der Verkauf schließt, hat keinen Gegenwert in der Währung des Verkaufs.' },
    third: { msgid: 'Third currency: the sale or a buy it closes is priced in a currency that is neither the security\'s nor its account\'s; no rate fixes it.', de: 'Dritte Währung: Der Verkauf oder ein Kauf, den er schließt, ist weder in der Währung des Wertpapiers noch in der seines Kontos bepreist; kein Wechselkurs behebt das.' },
    other: { msgid: 'Buy paid in another currency: a buy the sale closes was paid in another currency than the sale\'s, which no stored figure bridges; no rate fixes it.', de: 'Kauf in anderer Währung bezahlt: Ein Kauf, den der Verkauf schließt, wurde in einer anderen Währung als der des Verkaufs bezahlt, die kein gespeicherter Wert überbrückt; kein Wechselkurs behebt das.' },
    zero: { msgid: 'Buy of amount zero: a buy the sale closes has an amount of zero, which the rate backfill does not complete.', de: 'Kauf mit Betrag null: Ein Kauf, den der Verkauf schließt, hat einen Betrag von null, den das Nachladen der Kurse nicht ergänzt.' }
  },
  // Classifications (#1362's S2 line): a category's value is the sum of the
  // members with a usable price and names how many it leaves out.
  without: {
    msgid: 'without %{count} position', plural: 'without %{count} positions',
    de1: 'ohne %{count} Position', de: 'ohne %{count} Positionen'
  }
};
const NEW_CHECK = [
  NEW.overshoot.msgid, NEW.overshootLink.msgid, NEW.gapsLead.msgid, NEW.reasonNames.msgid, NEW.reasonNamesBare.msgid,
  ...Object.values(NEW.reason).map(r => r.msgid), ...Object.values(NEW.reasonInfo).map(r => r.msgid), NEW.without.msgid
];
NEW_CHECK.forEach(m => { if (!isNew(m)) throw new Error('not new, reuse it: ' + m); });

// ---------------------------------------------------------------- the rule
// Proposal CSS: what the page stories add to priv/static/app.css. Sprint 22
// built the section ⓘ, the clamp and the fold, so only two rules are new.
const PROPOSAL_CSS = `
/* #1362's S2 line ⑨: a category's partial value names what it leaves out,
   in the cell note's voice (the security rows' "zum Handelspreis"). */
.cat-value .cell-note {
  display: block;
  font-size: 11px;
  font-weight: 500;
  color: var(--color-text-muted);
  white-space: nowrap;
}
/* ① a section without a heading: the ⓘ ends its basis line, as a facet's
   does (Cash flow), with the line's gap before it. */
.detail-tab-hint > .metric-tooltip--section,
.summary-basis > .metric-tooltip--section {
  margin-left: var(--space-1);
}
`;

// The board's pins, also present while the live page is measured.
const PIN_CSS = `
.mock-pin { display: inline-grid; place-items: center; flex: none; width: 20px; height: 20px; border-radius: 50%; background: #c026d3; color: #fff; font: 700 12px/1 var(--font-sans); letter-spacing: 0; text-transform: none; margin-left: 6px; vertical-align: middle; box-shadow: 0 0 0 2px #fff; z-index: 60; }
.mock-pin--abs { position: absolute; left: -9px; top: -9px; margin: 0; }
.mock-pin--pre { margin: 0 6px 0 0; }
.mock-pinned { position: relative; }
`;
const PINS = '①②③④⑤⑥⑦⑧⑨';

// ---------------------------------------------------------------- frames
// Each frame: where it is captured, the read-only steps that put the page
// into its state, what is cut (the same in both frames), and R as data.
//   moves: a basis line's method parts → the section's ⓘ. `split` cuts the
//     line into clauses (" · ") or sentences; `move` lists the parts that
//     move (regex); the rest stays as the basis line (②). `heading` puts a
//     new ⓘ beside that heading (in .section-title); `into` appends to an
//     existing ⓘ; `tail` ends the kept line in a new ⓘ (a section with no
//     heading); `drop` removes parts the existing ⓘ already says (⑥).
//   noteToTip: a data note that states no data fact moves into the ⓘ.
//   actions: per note, the children that are its remedy controls.
//   exclusions: notes that name rows left out of a total: clamp, never fold.
//   custom: one more in-page change (named function below).
const SEC = (id, tab) => ({ url: '/securities/' + id, steps: tab ? [{ click: '#detail-tab-' + tab }] : [] });
const FRAMES = [
  {
    key: 'alloc', page: 'Vermögen → Allokation', url: '/portfolio?tab=allocation',
    keep: ['#portfolio-allocation'],
    elide: [['.donut-wrap', 'Sunburst and its legend — unchanged, cut for the board'], ['[data-role="allocation-disclosure"]', '„Daten als Tabelle“ — closed in both frames; #1339 is drawn below']],
    actions: { 'plan-overshoot-note': 'a' },
    custom: 'overshoot'
  },
  {
    key: 'alloc1339', page: 'Vermögen → Allokation, #1339', url: '/portfolio?tab=allocation',
    steps: [{ open: '[data-role="allocation-disclosure"]' }, { click: '[data-role="toggle-all-categories"]' }],
    keep: ['[data-role="allocation-disclosure"]'],
    rows: ['[data-role="allocation-disclosure"] table tbody > tr', 6],
    custom: 'keepOpen1339', r: 'none'
  },
  Object.assign({
    key: 'secOverview', page: 'Wertpapier → Überblick', keep: ['#security-detail-pane'],
    elide: [['#detail-tab-panel-overview .overview-chart', 'The overview chart — unchanged, cut for the board']],
    actions: { 'implausible-quote-note': 'a' }
  }, SEC(50)),
  Object.assign({
    key: 'secTrades', page: 'Wertpapier → Trades', keep: ['#security-detail-pane'],
    moves: [{ line: '[data-role="trades-basis"]', split: 'clause', move: ['^Einlieferungen eröffnen keinen Lot', '^p\\. a\\. erst ab'], heading: '#detail-tab-panel-trades h3.detail-section-title' }],
    open: { sel: '#detail-tab-panel-trades [data-role="section-info"]', place: 'above' }
  }, SEC(49, 'trades')),
  Object.assign({
    key: 'secChart', page: 'Wertpapier → Chart', keep: ['#security-detail-pane'],
    elide: [['#detail-tab-panel-chart .chart-frame', 'The price chart — unchanged, cut for the board']],
    moves: [{ line: '[data-role="metrics-basis"]', split: 'sentence', move: ['^Ein Tag ohne', '^Die Volatilität', '^Berichtet, nicht bewertet'], tail: true }],
    open: { sel: '#detail-tab-panel-chart [data-role="section-info"]', place: 'above' }
  }, SEC(49, 'chart')),
  Object.assign({
    key: 'secQuotes', page: 'Wertpapier → Kurse', keep: ['#security-detail-pane'],
    rows: ['#detail-tab-panel-quotes table tbody > tr', 2],
    moves: [{ line: '[data-role="quotes-basis"]', split: 'sentence', move: ['^Die Spalte Gespeichert', '^Wo ein Split'], dedupe: true, tail: true }],
    actions: { 'manual-quotes-note': 'button, a' }
  }, SEC(36, 'quotes')),
  Object.assign({
    key: 'secResearch', page: 'Wertpapier → Research', keep: ['#security-detail-pane'],
    moves: [{ line: '#detail-tab-panel-research > p.detail-tab-hint', split: 'sentence', move: ['^Einträge werden nie'], tail: true }],
    cutAfter: '#detail-tab-panel-research > p.detail-tab-hint'
  }, SEC(36, 'research')),
  Object.assign({
    key: 'secEvents', page: 'Wertpapier → Termine', keep: ['#security-detail-pane'],
    moves: [{ line: '[data-role="events-basis"]', split: 'sentence', move: ['^Ein Termin bucht nichts'], tail: true }],
    cutAfter: '[data-role="events-basis"]'
  }, SEC(36, 'events')),
  {
    key: 'income', page: 'Cashflow → Trades (Income), R5', url: '/cashflow?tab=realized', topbar: false,
    keep: ['#realized-trades', '[data-role="facet-basis"]'],
    elide: [['#realized-figures', 'The three figures — unchanged, cut for the board']],
    cut: ['#realized-trades-table', '#realized-trades-phone-rows', '#realized-unmatched', '[data-role="trades-basis"]'],
    custom: 'r5', r: 'custom'
  },
  {
    // The facet's ⓘ of the After frame above, opened on its own.
    key: 'incomeTip', page: 'Cashflow → Trades, the facet ⓘ', url: '/cashflow?tab=realized',
    keep: ['[data-role="facet-basis"]'], custom: 'r5', r: 'custom',
    open: { sel: '[data-role="facet-info"]', place: 'below' }
  },
  {
    key: 'incomeR5only', page: 'Cashflow → Trades, R5 reasons alone', url: '/cashflow?tab=realized',
    keep: ['#realized-excluded'], custom: 'r5only', r: 'custom'
  },
  {
    key: 'snapshots', page: 'Snapshots', url: '/snapshots',
    keep: ['[data-role="snapshot-comparison"]'],
    elide: [['[data-role="comparison-chart"]', 'Comparison chart and its legend — unchanged, cut for the board']],
    cut: ['[data-role="comparison-legend"]', '[data-role="comparison-disclosure"]'],
    moves: [{ line: '[data-role="comparison-basis"]', split: 'clause', move: ['^Transaktionskosten ='], heading: '[data-role="snapshot-comparison"] > header h2' }],
    noteToTip: [{ note: '[data-role="comparison-limitation"]', heading: '[data-role="snapshot-comparison"] > header h2' }],
    exclusions: ['comparison-gaps'],
    open: { sel: '[data-role="snapshot-comparison"] [data-role="section-info"]', place: 'below' },
    custom: 'gapsLead'
  },
  {
    key: 'tax', page: 'Steuern', url: '/tax',
    keep: ['#tax-budget', '#tax-statements'],
    cut: ['#tax-statements .tax-panel', '#tax-statements details.tax-orders-disclosure'],
    elide: [['#tax-statement-2', 'The statement the agent recorded — no note, unchanged, cut for the board']],
    actions: { 'budget-stale': 'button', 'statement-finding': 'button' }
  },
  {
    key: 'views', page: 'Ansichten', url: '/buckets',
    keep: ['#views-section', '#buckets-section'],
    rows: ['#view-list > li', 2],
    rows2: ['#bucket-list > li', 2],
    cut: ['#buckets-section form'],
    moves: [
      { line: '[data-role="views-basis"]', split: 'clause', move: ['.'], drop: true },
      { line: '[data-role="buckets-basis"]', split: 'clause', move: ['.'], drop: true }
    ]
  },
  {
    key: 'classif', page: 'Klassifizierungen', url: '/classifications/1',
    keep: ['#classifications-workspace'],
    cut: ['#classifications-workspace .workspace-section--controls', '#tree-search-form', '#current-only-form', '.select-toolbar'],
    treeKeep: 6,
    actions: { 'assignment-nudge': 'a', 'category-result-excluded': 'details' },
    exclusions: ['assignment-nudge', 'category-result-excluded'],
    custom: 'partialValue'
  },
  {
    key: 'imports', page: 'Import (Vorschau)', url: '/imports', steps: [{ file: 'priv/demo/portfolio_performance_demo.json' }],
    keep: ['#imports-workspace > section.workspace-section'],
    cut: ['#imports-workspace .import-stats', '#imports-workspace form#pp-import-apply > section.panel.inner:not(#import-security-mapping)', '#imports-workspace form#pp-import-apply > .actions'],
    actions: { 'unmatched-config': 'ul' },
    custom: 'matched1339'
  },
  {
    key: 'risk', page: 'Risiko', url: '/risk',
    keep: ['#policy-rules', '#risk-metrics', '[data-role="risk-caps"]'],
    elide: [['#policy-rules .data-table-wrapper', 'The rules and their findings — unchanged, cut for the board']],
    cut: ['#policy-rules-retired', '#risk-correlations', '#policy-rules .policy-rules-scheduled'],
    moves: [
      { line: '[data-role="risk-basis"]', split: 'sentence', move: ['^Ein Tag ohne Renditebasis', '^Korrelationen rechnen'], heading: '#risk-metrics-title' },
      { line: '[data-role="risk-caps"] .empty-state', split: 'sentence', move: ['^Obergrenzen werden'], heading: '#risk-caps-title' },
      { line: '[data-role="policy-rules-basis"]', split: 'sentence', move: ['^Jede Regel nennt', '^Ein Befund sagt'], heading: '#policy-rules-title' }
    ]
  }
];

// Runs in the page: keep only the given subtrees of <main> (and their
// ancestors), cut and elide the same way in both frames.
function trim(f) {
  const main = document.querySelector('main');
  main.querySelectorAll('script').forEach(s => s.remove());
  const elide = (el, text) => {
    const d = document.createElement(el.tagName === 'LI' || el.tagName === 'TR' ? el.tagName : 'div');
    d.className = 'mock-elided';
    if (el.tagName === 'TR') { d.innerHTML = '<td colspan="9">' + text + '</td>'; } else { d.textContent = text; }
    el.replaceWith(d);
    return d;
  };
  const keeps = (f.keep || []).flatMap(s => [...document.querySelectorAll(s)]);
  if (keeps.length) {
    const keepSet = new Set();
    keeps.forEach(k => { let n = k; while (n && n !== main) { keepSet.add(n); n = n.parentElement; } });
    const prune = (node) => {
      [...node.children].forEach(c => {
        if (keeps.includes(c)) return;
        if (keepSet.has(c)) { prune(c); return; }
        c.remove();
      });
    };
    prune(main);
  }
  (f.cut || []).forEach(s => document.querySelectorAll(s).forEach(e => e.remove()));
  (f.elide || []).forEach(([s, t]) => { const e = document.querySelector(s); if (e) elide(e, t); });
  const cutList = (sel, keep, label) => {
    const items = [...document.querySelectorAll(sel)];
    if (items.length <= keep) return;
    const rest = items.slice(keep);
    rest.slice(1).forEach(x => x.remove());
    elide(rest[0], '… ' + rest.length + ' more ' + label + ', cut for the board');
  };
  if (f.rows) cutList(f.rows[0], f.rows[1], 'rows');
  if (f.rows2) cutList(f.rows2[0], f.rows2[1], 'rows');
  if (f.cutAfter) { const a = document.querySelector(f.cutAfter); let n = a && a.nextElementSibling; while (n) { const x = n.nextElementSibling; n.remove(); n = x; } }
  if (f.treeKeep) {
    // Classifications: the tree's category rows stay, their member lists are cut.
    document.querySelectorAll('section.tree > details.cat-node').forEach((d, i) => { if (i >= f.treeKeep) d.remove(); });
    const left = document.querySelectorAll('section.tree > details.cat-node').length;
    const tree = document.querySelector('section.tree');
    if (tree) { const m = document.createElement('div'); m.className = 'mock-elided'; m.textContent = 'The other top-level categories and every member list (closed) — unchanged, cut for the board'; tree.appendChild(m); }
    void left;
  }
  // The security page: the list above the detail pane is cut.
  const list = document.querySelector('#securities-list-pane');
  if (list) { document.querySelector('#securities-detail-splitter')?.remove(); elide(list, 'The securities list — unchanged, cut for the board'); }
}

// Runs in the page: variant R with Sprint 22's Q1 corrections, as markup.
function applyR(a) {
  const { f, css, T } = a;
  const st = document.createElement('style');
  st.id = 'mock-measure';
  st.textContent = css;
  document.head.appendChild(st);
  const pins = [];
  const pinLater = (el, n, mode) => { if (el) pins.push({ el, n, mode }); };

  // ① the section's ⓘ: AppShell.section_info's markup.
  const newTip = () => {
    const d = document.createElement('details');
    d.className = 'metric-tooltip metric-tooltip--inline metric-tooltip--section';
    d.dataset.role = 'section-info';
    d.innerHTML = '<summary aria-label="' + T.section + '">ⓘ</summary><p role="tooltip"></p>';
    return d;
  };
  const tips = new Map();
  const tipFor = (m, keptLine) => {
    if (m.into) return document.querySelector(m.into);
    if (m.tail) {
      // A <details> is not phrasing content: a <p> line becomes a <div>
      // with the same class and role, as Cash flow's facet-basis is.
      if (keptLine.tagName === 'P') {
        const div = document.createElement('div');
        [...keptLine.attributes].forEach(at => div.setAttribute(at.name, at.value));
        while (keptLine.firstChild) div.appendChild(keptLine.firstChild);
        keptLine.replaceWith(div);
        keptLine = div;
      }
      const d = newTip();
      keptLine.appendChild(document.createTextNode(' '));
      keptLine.appendChild(d);
      return { tip: d, line: keptLine };
    }
    if (tips.has(m.heading)) return tips.get(m.heading);
    const h = document.querySelector(m.heading);
    const wrap = document.createElement('div');
    wrap.className = 'section-title';
    h.replaceWith(wrap);
    wrap.appendChild(h);
    const d = newTip();
    wrap.appendChild(d);
    tips.set(m.heading, d);
    pinLater(wrap, '①', 'in');
    return d;
  };
  const addLines = (tip, lines) => {
    const p = tip.querySelector('p');
    lines.forEach(t => {
      if (p.childNodes.length) p.appendChild(document.createElement('br'));
      p.appendChild(document.createTextNode(t));
    });
  };
  for (const m of (f.moves || [])) {
    const line = document.querySelector(m.line);
    if (!line) { console.warn('no line', m.line); continue; }
    const text = line.textContent.trim().replace(/\s+/g, ' ');
    let parts = m.split === 'clause' ? text.split(' · ') : text.split(/(?<=\.)\s+(?=[A-ZÄÖÜ])/);
    if (m.dedupe) parts = parts.filter((p, i) => parts.indexOf(p) === i);
    const moved = parts.filter(p => m.move.some(r => new RegExp(r).test(p)));
    const kept = parts.filter(p => !moved.includes(p));
    if (m.drop) {
      // ⑥ the heading's ⓘ already says it: the line leaves without a copy.
      const mark = document.createElement('p');
      mark.className = 'mock-gone';
      mark.textContent = '„' + text + '“ — the heading\'s ⓘ already says this';
      line.replaceWith(mark);
      pinLater(mark, '⑥', 'pre');
      continue;
    }
    line.textContent = kept.join(m.split === 'clause' ? ' · ' : ' ');
    let tip = tipFor(m, line);
    let keptLine = line;
    if (m.tail) { keptLine = tip.line; tip = tip.tip; pinLater(keptLine, '①', 'in'); }
    if (kept.length) pinLater(keptLine, '②', 'pre');
    addLines(tip, moved);
  }
  for (const n of (f.noteToTip || [])) {
    const note = document.querySelector(n.note);
    if (!note) continue;
    const t = note.querySelector('.data-note__body').textContent.trim().replace(/\s+/g, ' ');
    addLines(tipFor({ heading: n.heading }), [t]);
    note.remove();
  }

  // ③ every note clamps (data_note's `clamp`): its text in .data-note__text,
  // its remedy controls in .data-note__actions, „mehr“ after the body.
  const notes = [...document.querySelectorAll('main .data-note')].filter(n => !n.closest('table') && !n.classList.contains('data-note--clamped'));
  const sev = n => n.classList.contains('data-note--problem') ? 'problem' : n.classList.contains('data-note--attention') ? 'attention' : 'note';
  notes.forEach((n, i) => {
    const body = n.querySelector(':scope > .data-note__body');
    if (!body) return;
    const id = n.id || ((n.dataset.role || 'note-' + i) + '-note');
    n.id = id;
    const text = document.createElement('div');
    text.className = 'data-note__text';
    text.id = id + '-text';
    const actions = document.createElement('div');
    actions.className = 'data-note__actions';
    const actSel = (f.actions || {})[n.dataset.role] || '.fx-sync, .fx-backfill';
    [...body.childNodes].forEach(c => {
      if (c.nodeType === 1 && c.matches(actSel)) { actions.appendChild(c); return; }
      text.appendChild(c);
    });
    // A dangling separator between moved links stays with them.
    [...text.childNodes].reverse().find(c => c.nodeType === 3 && c.textContent.trim() === '·')?.remove();
    if (actions.querySelectorAll(':scope > a').length > 1) {
      const links = [...actions.querySelectorAll(':scope > a')];
      links.slice(1).forEach(l => l.before(document.createTextNode(' · ')));
    }
    body.innerHTML = '';
    body.appendChild(text);
    if (actions.childNodes.length) body.appendChild(actions);
    n.classList.add('data-note--clamped');
    const more = document.createElement('button');
    more.type = 'button';
    more.className = 'link-button data-note__more';
    more.setAttribute('aria-expanded', 'false');
    more.setAttribute('aria-controls', text.id);
    more.textContent = T.more;
    n.appendChild(more);
    if (sev(n) === 'problem') pinLater(n, '⑤', 'abs');
    else pinLater(n, '③', 'abs');
  });
  // „mehr“ only where the clamp cuts (measured before folding hides notes).
  notes.forEach(n => {
    const t = n.querySelector('.data-note__text');
    const more = n.querySelector('.data-note__more');
    if (t && more && t.scrollHeight <= t.clientHeight + 1) more.remove();
  });

  // ④ ⑤ fold: per block, problems lead, exclusions stay, two or more others fold.
  const word = (pair, k) => pair[k === 1 ? 0 : 1].replace('%{count}', k);
  const iconOf = s => { const n = notes.find(x => sev(x) === s); return n ? n.querySelector('.data-note__icon').innerHTML : ''; };
  const byParent = new Map();
  notes.forEach(n => { const p = n.parentElement; if (!byParent.has(p)) byParent.set(p, []); byParent.get(p).push(n); });
  byParent.forEach((ns) => {
    const foldable = ns.filter(n => sev(n) !== 'problem' && !(f.exclusions || []).includes(n.dataset.role));
    if (foldable.length < 2) return;
    const cnt = { attention: 0, note: 0 };
    foldable.forEach(n => cnt[sev(n)]++);
    const d = document.createElement('details');
    d.className = 'data-note-group data-note-group--' + (cnt.attention ? 'attention' : 'note');
    d.dataset.role = 'folded-notes';
    const parts = [];
    if (cnt.attention) parts.push('<span class="data-note-group__count data-note-group__count--attention"><span aria-hidden="true">' + iconOf('attention') + '</span>' + word(T.attention, cnt.attention) + '</span>');
    if (cnt.attention && cnt.note) parts.push('<span aria-hidden="true">·</span>');
    if (cnt.note) parts.push('<span class="data-note-group__count data-note-group__count--note"><span aria-hidden="true">' + iconOf('note') + '</span>' + word(T.note, cnt.note) + '</span>');
    d.innerHTML = '<summary>' + parts.join('') + '<span class="data-note-group__toggle" data-hide="' + T.hide + '">— <span class="data-note-group__show">' + T.show + '</span></span></summary><div class="data-note-group__body"></div>';
    ns[ns.length - 1].after(d);
    foldable.forEach(n => d.querySelector('.data-note-group__body').appendChild(n));
    const parent = d.parentElement;
    ns.filter(n => sev(n) === 'problem').reverse().forEach(n => parent.prepend(n));
    pinLater(d, '④', 'abs');
  });
  window.__mockPins = pins;
  return pins.length;
}

// Runs in the page: the frame's own change, beside R.
function custom(a) {
  const { name, NEW, T, de } = a;
  const fmt = (s, b) => s.replace(/%\{(\w+)\}/g, (_, k) => b[k]);
  const pinAt = (el, n, mode) => { if (el) (window.__mockPins = window.__mockPins || []).push({ el, n, mode }); };
  if (name === 'overshoot') {
    // The remedy link leaves the sentence for the note's actions.
    const n = document.querySelector('[data-role="plan-overshoot-note"]');
    if (!n) return;
    const text = n.querySelector('.data-note__text');
    const sum = (text.textContent.match(/auf ([\d.,]+) %/) || [])[1];
    text.textContent = fmt(NEW.overshoot.de, { sum });
    const link = n.querySelector('.data-note__actions a');
    if (link) link.textContent = NEW.overshootLink.de;
  }
  if (name === 'gapsLead') {
    // ⑧ the count leads: „Nicht enthalten: 20 Positionen … — names“.
    const n = document.querySelector('[data-role="comparison-gaps"]');
    if (!n) return;
    const text = n.querySelector('.data-note__text') || n.querySelector('.data-note__body');
    const raw = text.textContent.trim().replace(/\s+/g, ' ');
    const names = raw.replace(/^[^:]*\):\s*/, '');
    const count = names.split(', ').length;
    text.textContent = fmt(count === 1 ? NEW.gapsLead.de1 : NEW.gapsLead.de, { count, names });
    pinAt(n.querySelector('.data-note__word'), '⑧', 'after');
  }
  if (name === 'partialValue') {
    // ⑨ #1362: the value of a category whose members are not all priced is
    // the sum of the priced ones, naming how many it leaves out (ADR-0041 §5).
    const parseDe = s => Number(s.replace(/\./g, '').replace(',', '.'));
    const fmtDe = x => x.toLocaleString('de-DE', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    document.querySelectorAll('section.tree > details.cat-node').forEach(d => {
      const cell = d.querySelector(':scope > summary [data-role="category-value"]');
      if (!cell || !cell.querySelector('.cat-na')) return;
      const vals = [...d.querySelectorAll('[data-role="security-value"]')].map(v => v.textContent.trim());
      const priced = vals.filter(v => v !== '—' && v !== '');
      if (!priced.length) return;
      const left = vals.length - priced.length;
      cell.innerHTML = fmtDe(priced.reduce((s, v) => s + parseDe(v), 0)) + (left ? '<small class="cell-note">' + fmt(left === 1 ? NEW.without.de1 : NEW.without.de, { count: left }) + '</small>' : '');
      pinAt(cell, '⑨', 'abs');
    });
  }
  if (name === 'keepOpen1339') {
    // ⑦ #1339: with id + DisclosureState the disclosure is open again after
    // the patch the category toggle caused.
    const d = document.querySelector('[data-role="allocation-disclosure"]');
    d.id = 'allocation-disclosure';
    d.open = true;
    pinAt(d.querySelector('summary'), '⑦', 'in');
  }
  if (name === 'matched1339') {
    const d = document.querySelector('[data-role="matched-securities"]');
    if (!d) return;
    d.id = 'import-matched-securities';
    d.open = true;
    pinAt(d.querySelector('summary'), '⑦', 'in');
  }
}

// Runs in the page: the Before state of a frame whose bug needs a step.
function before(a) {
  if (a.name === 'matched1339') {
    const d = document.querySelector('[data-role="matched-securities"]');
    if (d) d.open = false;
  }
}

// Runs in the page: Sprint 22 R5's three sentences as built (board 02 ①d's
// synthetic names), into the live note beside the seed's two real reasons.
function r5(a) {
  const { state, R5 } = a;
  const pinAt = (el, k, mode) => { if (el) (window.__mockPins = window.__mockPins || []).push({ el, n: k, mode }); };
  const add = (text, reason, list) => list.forEach(s => {
    const sp = document.createElement('span');
    sp.dataset.role = s.role;
    sp.textContent = s.text;
    reason.before(sp);
    reason.before(document.createTextNode(' '));
  });
  const n = document.querySelector('#realized-excluded');
  if (n) {
    const text = n.querySelector('.data-note__text');
    const counts = text.querySelector('[data-role="realized-excluded-counts"]');
    const reason = text.querySelector('[data-role="fx-backfill-reason"]');
    counts.textContent = R5.lead + ' ';
    if (state === 'before') {
      add(text, reason, R5.sentences);
    } else {
      // After: the lead carries every count once; each reason names its
      // sales without a second count.
      text.querySelectorAll('[data-role^="realized-excluded-"]:not([data-role$="-counts"])').forEach(s => s.remove());
      add(text, reason, R5.after);
      pinAt(counts, '⑧', 'pre');
    }
    // Drawn expanded („mehr“ pressed), as board 02 ①d draws it.
    n.dataset.mockExpanded = R5.less;
  }
  if (state === 'after') {
    // What each reason means is method: the facet's ⓘ, under its text.
    const p = document.querySelector('[data-role="facet-info"] p');
    // After a blank line, one reason per line.
    p.appendChild(document.createElement('br'));
    R5.info.forEach(t => { p.appendChild(document.createElement('br')); p.appendChild(document.createTextNode(t)); });
    pinAt(document.querySelector('[data-role="facet-basis"]'), '①', 'pre');
  }
}

// Runs in the page: R5's reasons alone (no stored rate missing): the note
// names them and offers no remedy, because no rate fixes them.
function r5only(a) {
  const { state, R5 } = a;
  const n = document.querySelector('#realized-excluded');
  const text = n.querySelector('.data-note__text');
  const counts = text.querySelector('[data-role="realized-excluded-counts"]');
  const pinAt = (el, k, mode) => { if (el) (window.__mockPins = window.__mockPins || []).push({ el, n: k, mode }); };
  text.querySelectorAll('[data-role^="realized-excluded-"]:not([data-role$="-counts"])').forEach(s => s.remove());
  const reason = text.querySelector('[data-role="fx-backfill-reason"]');
  counts.textContent = R5.leadOnly + ' ';
  const list = state === 'before' ? R5.sentences : R5.after.filter(s => !/no-rate|missing-leg/.test(s.role));
  list.forEach(s => {
    const sp = document.createElement('span');
    sp.dataset.role = s.role;
    sp.textContent = s.text;
    reason.before(sp);
    reason.before(document.createTextNode(' '));
  });
  n.dataset.mockExpanded = R5.less;
  if (state === 'after') {
    // No reason the backfill can fix: no remedy sentence and no button.
    reason.remove();
    n.querySelector('.data-note__actions')?.remove();
    pinAt(counts, '⑧', 'pre');
  }
}

// Runs in the page: place the recorded pins, then report "mehr" placements.
function placePins() {
  const pins = window.__mockPins || [];
  for (const { el, n, mode } of pins) {
    if (!el.isConnected) continue;
    const s = document.createElement('span');
    s.className = 'mock-pin' + (mode === 'abs' ? ' mock-pin--abs' : '');
    s.textContent = String('①②③④⑤⑥⑦⑧⑨'.indexOf(n) + 1);
    s.title = n;
    if (mode === 'pre') { el.prepend(s); s.classList.add('mock-pin--pre'); continue; }
    if (mode === 'abs') { if (getComputedStyle(el).position === 'static') el.classList.add('mock-pinned'); el.prepend(s); continue; }
    if (mode === 'after') { el.after(s); continue; }
    el.appendChild(s);
  }
  window.__mockPins = [];
  // Re-measure „mehr“ with the pins in place, as the board shows it.
  document.querySelectorAll('.data-note--clamped:not([data-expanded]):not([data-mock-expanded])').forEach(n => {
    const t = n.querySelector('.data-note__text');
    let more = n.querySelector('.data-note__more');
    const cut = t && t.scrollHeight > t.clientHeight + 1;
    if (more && !cut) more.remove();
    if (more && cut) more.hidden = false;
    if (!more && cut && n.dataset.mockAfter) {
      more = document.createElement('button');
      more.type = 'button';
      more.className = 'link-button data-note__more';
      more.textContent = n.dataset.mockAfter;
      n.appendChild(more);
    }
  });
  return [...document.querySelectorAll('.data-note--clamped')].map(n => (n.dataset.role || n.id) + (n.querySelector('.data-note__more:not([hidden])') ? ':mehr' : ''));
}

// Runs in the page: opens an ⓘ for the After frame and places it as the
// #1336 hook does — the given side, shifted so both edges stay 1 rem inside
// the viewport (--tip-shift) — so the static frame shows the placement.
function openTip(a) {
  const d = document.querySelector(a.sel);
  if (!d) return null;
  d.open = true;
  if (a.place === 'below') d.dataset.place = 'below';
  d.style.removeProperty('--tip-shift');
  const vw = document.documentElement.clientWidth;
  const r = d.querySelector('p').getBoundingClientRect();
  let shift = 0;
  if (r.right > vw - 16) shift = (vw - 16) - r.right;
  if (r.left + shift < 16) shift = 16 - r.left;
  if (shift) d.style.setProperty('--tip-shift', Math.round(shift) + 'px');
  return { place: a.place, shift: Math.round(shift), left: Math.round(r.left + shift), right: Math.round(r.right + shift) };
}

function capture() {
  // A note drawn expanded („weniger“): set last, so the NoteClamp hook
  // cannot measure it back in between.
  document.querySelectorAll('[data-mock-expanded]').forEach(n => {
    n.setAttribute('data-expanded', '');
    const more = n.querySelector('.data-note__more');
    if (more) { more.textContent = n.dataset.mockExpanded; more.setAttribute('aria-expanded', 'true'); more.hidden = false; }
    n.removeAttribute('data-mock-expanded');
  });
  document.getElementById('mock-measure')?.remove();
  const clean = h => h
    .replace(/\s(?:data-phx-[\w-]+|phx-[\w-]+)="[^"]*"/g, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/\n\s*\n+/g, '\n')
    .replace(/(src|href)="\/(images|favicon|security_logos)/g, '$1="../../../../../priv/static/$2');
  return clean(document.querySelector('main').outerHTML);
}

async function load(page, f) {
  await page.goto(BASE + f.url + (f.url.includes('?') ? '&' : '?') + 'locale=de', { waitUntil: 'networkidle' });
  await page.waitForTimeout(1500); // the count-up settles
  for (const s of (f.steps || [])) {
    if (s.click) { await page.click(s.click); await page.waitForTimeout(1000); }
    if (s.open) { await page.evaluate(sel => { document.querySelector(sel).open = true; }, s.open); await page.waitForTimeout(200); }
    // The preview is kept per session: a second load shows it again.
    if (s.file && await page.$('input[type=file]')) { await page.setInputFiles('input[type=file]', path.join(REPO, s.file)); await page.waitForTimeout(4000); }
  }
}

// R5's texts: the catalogue's own sentences for "before" (board 02 ①d's
// synthetic names for the three reasons the seed lacks), the new ones for "after".
function r5Texts() {
  const real = [
    { role: 'realized-excluded-no-rate', reason: 'no_rate', names: 'Harborline Freight Inc', label: '%{count} sale with no stored rate' },
    { role: 'realized-excluded-missing-leg', reason: 'missing_leg', names: 'Arbolia Inc.', label: '%{count} sale whose buy has no figure in its currency' }
  ];
  const synth = [
    { role: 'realized-excluded-third-currency', reason: 'third', names: 'Saltmarsh Mining plc', label: '%{count} sale priced in a third currency',
      sentence: '%{count} sale is not convertible — it or a buy it closes is priced in a currency that is neither the security\'s nor its account\'s — and is excluded from every total: %{securities}.' },
    { role: 'realized-excluded-other-account', reason: 'other', names: 'Brightwater Tools AG', label: '%{count} sale whose buy was paid in another currency',
      sentence: '%{count} sale is not convertible — a buy it closes was paid in another currency than the sale\'s, which no stored figure bridges — and is excluded from every total: %{securities}.' },
    { role: 'realized-excluded-zero-amount', reason: 'zero', names: 'Fernhill Bonus AG', label: '%{count} sale whose buy has an amount of zero',
      sentence: '%{count} sale is not convertible — a buy it closes has an amount of zero, which the rate backfill does not complete — and is excluded from every total: %{securities}.' }
  ];
  const lead = (list) => de('Excluded from every total: %{counts}.', null, { counts: list.map(r => de(r.label, 1)).join('; ') });
  const fmt = (s, b) => s.replace(/%\{(\w+)\}/g, (_, k) => b[k]);
  const after = [...real, ...synth].map(r => ({ role: r.role, text: fmt(r.names.endsWith('.') ? NEW.reasonNamesBare.de : NEW.reasonNames.de, { reason: NEW.reason[r.reason].de, securities: r.names }) }));
  return {
    lead: lead([...real, ...synth]),
    leadOnly: lead(synth),
    less: T.less,
    sentences: synth.map(r => ({ role: r.role, text: de(r.sentence, 1, { securities: r.names }) })),
    after,
    info: [...real, ...synth].filter(r => NEW.reasonInfo[r.reason]).map(r => NEW.reasonInfo[r.reason].de)
  };
}

async function framesAt(browser, vw) {
  const page = await browser.newPage({ viewport: { width: vw, height: 900 } });
  page.on('console', m => { if (m.type() === 'warning') console.warn('page:', m.text()); });
  const R5 = r5Texts();
  const out = {};
  for (const f of FRAMES) {
    out[f.key] = {};
    for (const state of ['before', 'after']) {
      await load(page, f);
      await page.evaluate(trim, f);
      await page.addStyleTag({ content: PROPOSAL_CSS + PIN_CSS }).then(h => h.evaluate(e => { e.id = 'mock-measure'; }));
      if (state === 'before' && f.custom === 'matched1339') await page.evaluate(before, { name: f.custom });
      if (f.custom === 'r5') await page.evaluate(r5, { state, R5 });
      if (f.custom === 'r5only') await page.evaluate(r5only, { state, R5 });
      if (state === 'after' && f.r !== 'none' && f.r !== 'custom') await page.evaluate(applyR, { f, css: '', T });
      if (state === 'after' && f.custom && !['r5', 'r5only'].includes(f.custom)) await page.evaluate(custom, { name: f.custom, NEW });
      const facts = await page.evaluate(placePins);
      if (state === 'after' && f.open) facts.push(await page.evaluate(openTip, f.open));
      out[f.key][state] = { html: await page.evaluate(capture), facts };
      console.log(vw, f.key, state, JSON.stringify(facts));
    }
  }
  await page.close();
  return out;
}

module.exports = { openTip, FRAMES, NEW, T, de, isNew, PROPOSAL_CSS, PIN_CSS, PINS, framesAt };

if (require.main === module) {
  require('./board.js').main().catch(e => { console.error(e); process.exit(1); });
}
