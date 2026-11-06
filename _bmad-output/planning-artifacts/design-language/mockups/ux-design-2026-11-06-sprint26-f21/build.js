// Builds the Sprint 26 planning board 04 for F21 (#894): the three
// cascading deletes — a classification, a category, a view — confirm in an
// in-app dialog that says what the delete removes, read from the delete's
// own dry run (Sprint 25 X1, plan D-4: the real delete in a transaction that
// always rolls back), instead of today's native `window.confirm` via
// `data-confirm`, which names no count.
//
// Copied from the Sprint 24 P1 board's tooling (../ux-design-2026-11-05-
// sprint24-p1/build.js: the catalogue reader, the in-page helpers, isolate,
// the static frames) and the I22 board's frame chrome; this header, the
// frames, the dialog builder and the proposal CSS differ.
//
// Every frame is captured from the review instance on the synthetic review
// seed (priv/demo/finding_surfaces_seed.exs) with read-only steps: GET
// requests, and on /buckets one click on a view's kebab, which opens its row
// menu (view state, nothing written). No delete is sent, not even its dry
// run: the counts the dialogs show are the seed's rows, which the dry run
// of each delete would name (README.md, "Where the counts come from").
//
// A "Vorher" frame is the shipped page with today's native confirmation
// drawn over it — an approximation of Chrome's dialog, labelled as such,
// its text the catalogue's. A "Nachher" frame is the shipped page with the
// proposed dialog written into the live DOM in the anatomy of
// `PortfolixirWeb.Transactions.BookingDeleteDialog` (`.modal
// .booking-delete-dialog`, its subject box, its band foot), shown open over
// the scrim showModal() paints (app.css's ::backdrop colours). The story's
// CSS is PROPOSAL_CSS, carried by each "Nachher" frame in
// <style id="proposal">.
//
// Usage (the review instance on port 4011, see README.md):
//   node build.js     # captures every frame, writes frames/ and both boards
//   node render.js    # renders both boards to PNG
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
// de(msgid[, count, bindings]): the German msgstr, plural-aware.
function de(msgid, count, bindings = {}) {
  const e = PO.get('\u0004' + msgid);
  if (!e) throw new Error('not in the catalogue: ' + msgid);
  const s = e.msgid_plural !== undefined ? e[count === 1 ? 'msgstr[0]' : 'msgstr[1]'] : e.msgstr;
  if (!s) throw new Error('no translation: ' + msgid);
  const b = Object.assign({ count }, bindings);
  return s.replace(/%\{(\w+)\}/g, (_, k) => (b[k] !== undefined ? b[k] : '%{' + k + '}'));
}

// The proposed strings: English source and German, listed in README.md.
// nu(key[, count, bindings]) answers the German, as de() does.
const NEW = {
  titleView: { en: 'Delete view', de: 'Ansicht löschen' },
  removes: { en: 'The delete removes:', de: 'Das Löschen entfernt:' },
  nothingElse: { en: 'Nothing else is removed with it.', de: 'Sonst wird nichts mit gelöscht.' },
  categorySelf: {
    en: ['“%{name}” and %{count} category below it', '“%{name}” and %{count} categories below it'],
    de: ['„%{name}“ und %{count} Kategorie darunter', '„%{name}“ und %{count} Kategorien darunter']
  },
  assignments: {
    en: ['%{count} security assignment', '%{count} security assignments'],
    de: ['%{count} Wertpapierzuordnung', '%{count} Wertpapierzuordnungen']
  },
  plans: { en: ['%{count} target plan', '%{count} target plans'], de: ['%{count} Soll-Plan', '%{count} Soll-Pläne'] },
  targets: { en: ['%{count} target weight', '%{count} target weights'], de: ['%{count} Zielgewicht', '%{count} Zielgewichte'] },
  snapshots: { en: ['%{count} snapshot', '%{count} snapshots'], de: ['%{count} Snapshot', '%{count} Snapshots'] },
  categoryIn: { en: 'Category in %{classification}', de: 'Kategorie in %{classification}' },
  keptClassification: {
    en: 'The securities themselves, their bookings and quotes stay.',
    de: 'Die Wertpapiere selbst, ihre Buchungen und Kurse bleiben.'
  },
  keptCategory: {
    en: 'The securities themselves stay; in this classification they then sit under “Unassigned”.',
    de: 'Die Wertpapiere selbst bleiben; in dieser Klassifizierung stehen sie danach unter „Nicht zugeordnet“.'
  },
  keptView: { en: 'The buckets and their assignments stay.', de: 'Die Buckets und ihre Zuordnungen bleiben.' },
  journal: {
    en: 'The audit journal records each deletion with every value; none of it can be restored.',
    de: 'Das Audit-Journal hält jede Löschung mit allen Werten fest; wiederherstellen lässt sich nichts davon.'
  },
  refusalWhy: {
    en: 'A rule that has been in force keeps its subject as part of its history, so the delete stays blocked; retiring the rule on Wealth → Risk stops its evaluation.',
    de: 'Eine Regel, die gegolten hat, behält ihren Bezug als Teil ihrer Geschichte; darum bleibt das Löschen gesperrt. Sie auf „Vermögen → Risiko“ zu beenden, stoppt ihre Auswertung.'
  },
  changed: {
    en: 'What the delete removes changed while this dialog was open. Nothing was deleted; the dialog now shows the new state.',
    de: 'Was das Löschen entfernt, hat sich geändert, während dieser Dialog offen war. Nichts wurde gelöscht; der Dialog zeigt jetzt den neuen Stand.'
  },
  concurrent: {
    en: 'Something changed while the check ran, and nothing was deleted. Check again to see what the delete removes now.',
    de: 'Während der Prüfung hat sich etwas geändert, und nichts wurde gelöscht. Erneut prüfen, um zu sehen, was das Löschen jetzt entfernt.'
  },
  more: { en: '%{names} and %{count} more', de: '%{names} und %{count} weitere' }
};
function nu(key, count, bindings = {}) {
  const e = NEW[key];
  const s = Array.isArray(e.de) ? e.de[count === 1 ? 0 : 1] : e.de;
  const b = Object.assign({ count }, bindings);
  return s.replace(/%\{(\w+)\}/g, (_, k) => (b[k] !== undefined ? b[k] : '%{' + k + '}'));
}

// ------------------------------------------------------------ frame chrome
// The proposal: what the story adds to priv/static/app.css. The dialog
// itself is `.modal .booking-delete-dialog` as shipped (460 px; under
// 720 px the bottom sheet with its stacked band foot); a refusal adds
// `.confirm-delete-blocked`, the securities' "Cannot delete" text rules.
// Only the removal list is new.
const PROPOSAL_CSS = `
.delete-preview { margin: 0; }
.delete-preview__lead { margin: 0 0 4px; font-size: 13px; color: var(--color-text); }
.delete-preview__list { margin: 0; padding-left: 18px; font-size: 13px; line-height: 1.55; color: var(--color-text); }
.delete-preview__list li { overflow-wrap: anywhere; }
.delete-preview__list li + li { margin-top: 2px; }
.delete-preview__list li::marker { color: var(--color-text-muted); }
.delete-preview__names { color: var(--color-text-muted); }
.confirm-delete-blocked .modal-body ul { margin: 0; padding-left: 18px; font-size: 13px; line-height: 1.55; }
`;

// Frame chrome: what showModal() and the browser would paint, drawn into a
// static page. The scrim takes app.css's ::backdrop colours; the native
// confirmation is an approximation of Chrome's and says so on the board.
const FRAME_CSS = `
body { margin: 0; background: var(--color-bg); position: relative; }
body.mock-noside .app-frame { padding-left: 0 !important; margin-left: 0 !important; }
.app-shell, .app-frame, .app-main, .workspace-page { min-height: 0 !important; }
.topbar { position: relative !important; top: auto !important; }
.mock-scrim { position: fixed; inset: 0; z-index: 90; background: rgba(15, 23, 42, 0.4); }
[data-theme="dark"] .mock-scrim { background: rgba(0, 0, 0, 0.55); }
@media (min-width: 721px) {
  dialog.mock-open { position: absolute; top: 0; left: 0; right: 0; z-index: 100; }
}
@media (max-width: 720px) {
  dialog.mock-open { z-index: 100; }
}
.mock-new { outline: 2px dashed var(--color-accent); outline-offset: 3px; }
dialog.mock-new { outline-offset: 4px; }
.mock-synth { box-shadow: inset 3px 0 0 #f59e0b; padding-left: 10px !important; }
.mock-pin { display: inline-grid; place-items: center; flex: none; width: 20px; height: 20px; border-radius: 50%; background: #c026d3; color: #fff; font: 700 12px/1 var(--font-sans); letter-spacing: 0; text-transform: none; margin: 0 4px; vertical-align: middle; box-shadow: 0 0 0 2px #fff; }
.mock-pin--abs { position: absolute; left: -22px; top: 0; margin: 0; z-index: 120; }
.modal-footer .mock-pin--abs { left: -10px; top: -10px; }
@media (max-width: 720px) { .mock-pin--abs { left: -16px; top: -8px; } }
.mock-clicked { outline: 2px solid var(--color-danger) !important; outline-offset: 2px; border-radius: 6px; }
.mock-pinned { position: relative; }
.mock-native { position: absolute; top: 12px; left: 50%; transform: translateX(-50%); z-index: 100; width: 448px; box-sizing: border-box;
  padding: 20px 24px 16px; border-radius: 8px; background: #fff; color: #1f1f1f; box-shadow: 0 2px 6px rgba(0,0,0,.15), 0 8px 24px rgba(0,0,0,.25);
  font: 13px/1.45 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; letter-spacing: 0; }
.mock-native__origin { margin: 0 0 10px; font-size: 14px; font-weight: 500; }
.mock-native__text { margin: 0 0 20px; }
.mock-native__buttons { display: flex; justify-content: flex-end; gap: 8px; }
.mock-native__buttons span { display: inline-block; min-width: 64px; padding: 7px 16px; border-radius: 16px; text-align: center; font-weight: 500; }
.mock-native__ok { background: #0b57d0; color: #fff; }
.mock-native__cancel { border: 1px solid #747775; color: #0b57d0; }
.mock-native--phone { top: auto; bottom: 0; left: 0; right: 0; transform: none; width: auto; border-radius: 12px 12px 0 0; }
`;

const ICON_X = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>';

// In-page helpers, injected before a prep runs (window.M).
const HELPERS = `
window.M = {
  el(html) { const t = document.createElement('template'); t.innerHTML = html.trim(); return t.content.firstElementChild; },
  esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); },
  pin(target, n, mode) {
    const t = typeof target === 'string' ? document.querySelector(target) : target;
    if (!t) { console.warn('pin target missing', target); return; }
    const s = document.createElement('span');
    s.className = 'mock-pin' + (mode === 'abs' ? ' mock-pin--abs' : '');
    s.textContent = String(n);
    if (mode === 'abs') { t.classList.add('mock-pinned'); t.prepend(s); }
    else if (mode === 'pre') t.prepend(s);
    else if (mode === 'after') t.after(s);
    else t.appendChild(s);
  },
  // Today's confirmation: window.confirm(data-confirm), as Chrome draws it.
  native(text, phone) {
    document.body.prepend(this.el('<div class="mock-native' + (phone ? ' mock-native--phone' : '') + '" role="presentation">'
      + '<p class="mock-native__origin">localhost:4011 meldet</p>'
      + '<p class="mock-native__text">' + this.esc(text) + '</p>'
      + '<div class="mock-native__buttons"><span class="mock-native__ok">OK</span><span class="mock-native__cancel">Abbrechen</span></div></div>'));
  },
  // The proposed dialog, in BookingDeleteDialog's anatomy.
  dialog(o) {
    const e = (s) => this.esc(s);
    const subject = '<p id="delete-preview-subject" class="booking-delete__subject" data-role="delete-preview-subject">'
      + '<span class="phone-row__body"><span class="phone-row__name"><bdi>' + e(o.subject.name) + '</bdi></span>'
      + (o.subject.ids ? '<span class="phone-row__ids"><span>' + o.subject.ids + '</span></span>' : '') + '</span>'
      + (o.subject.figure ? '<span class="phone-row__figures"><span class="phone-row__figure">' + e(o.subject.figure) + '</span>'
        + (o.subject.figure2 ? '<span class="phone-row__figure2">' + e(o.subject.figure2) + '</span>' : '') + '</span>' : '')
      + '</p>';
    let body = '';
    if (o.changed) body += '<div role="status" class="booking-delete__region"><div class="data-note data-note--attention" data-role="delete-preview-changed"><span class="data-note__icon" aria-hidden="true">' + o.icons.attention + '</span><span class="data-note__word">Achtung</span><div class="data-note__body">' + e(o.changed) + '</div></div></div>';
    body += subject;
    if (o.refusal) {
      body += '<p>' + o.refusal.lead + '</p><ul data-role="delete-preview-rules">'
        + o.refusal.rules.map((r) => '<li>' + r + '</li>').join('') + '</ul>'
        + '<p class="muted">' + e(o.refusal.why) + '</p>';
    } else {
      if (o.items && o.items.length) {
        body += '<div class="delete-preview' + (o.synth ? ' mock-synth' : '') + '" data-role="delete-preview-removes"><p class="delete-preview__lead">' + e(o.lead) + '</p><ul class="delete-preview__list">'
          + o.items.map((i) => '<li>' + i + '</li>').join('') + '</ul></div>';
      } else {
        body += '<p class="hint delete-preview__nothing" data-role="delete-preview-nothing">' + e(o.nothing) + '</p>';
      }
      body += '<p class="hint" data-role="delete-preview-kept">' + e(o.kept) + '</p>';
      body += '<p class="hint" data-role="delete-preview-journal">' + e(o.journal) + '</p>';
    }
    const foot = o.refusal
      ? '<button type="button" class="button-ghost">' + e(o.close) + '</button>'
      : '<button type="button" class="button-ghost" data-role="delete-preview-cancel">' + e(o.cancel) + '</button><span class="modal-footer__spacer"></span><button type="button" class="button-danger" id="delete-preview-confirm">' + e(o.confirm) + '</button>';
    const d = this.el('<dialog open id="delete-preview-dialog" class="modal booking-delete-dialog' + (o.refusal ? ' confirm-delete-blocked' : '') + ' mock-open mock-new" aria-labelledby="delete-preview-title" aria-describedby="delete-preview-subject">'
      + '<header class="modal-head"><h2 id="delete-preview-title">' + e(o.title) + '</h2><button type="button" class="icon-button" aria-label="' + e(o.closeLabel) + '">' + o.icons.x + '</button></header>'
      + '<div class="modal-body">' + body + '</div>'
      + '<div class="modal-footer modal-footer--band">' + foot + '</div></dialog>');
    document.body.prepend(d);
    document.body.prepend(this.el('<div class="mock-scrim" aria-hidden="true"></div>'));
    if (o.pins) {
      this.pin(d.querySelector('.booking-delete__subject'), 1, 'abs');
      const list = d.querySelector('.delete-preview, .delete-preview__nothing, [data-role=delete-preview-rules]');
      if (list) this.pin(list, 2, 'abs');
      const kept = d.querySelector('[data-role=delete-preview-kept], .muted');
      if (kept) this.pin(kept, 3, 'abs');
      const act = d.querySelector('.modal-footer--band > :last-child');
      if (act) this.pin(act, 4, 'abs');
    }
    return d;
  },
  // A rule named in a refusal, as PolicyRuleReferences.rule renders it.
  rule(template, r) {
    return template.split(/(%\\{name\\}|%\\{status\\}|%\\{view\\})/).map((seg) =>
      seg === '%{name}' ? '<a href="' + r.href + '" data-role="policy-rule-link"><bdi>' + this.esc(r.name) + '</bdi></a>'
      : seg === '%{status}' ? this.esc(r.status)
      : seg === '%{view}' ? '<bdi>' + this.esc(r.view) + '</bdi>'
      : this.esc(seg)).join('');
  }
};
`;

// Runs in the page last: keep only the kept elements and their ancestors,
// then hand back the body's markup, cleaned.
function isolate(args) {
  document.querySelectorAll('script, #app-sidebar, .sidebar-backdrop').forEach((s) => s.remove());
  const kept = args.keep.flatMap((s) => [...document.querySelectorAll(s)]);
  const chain = new Set();
  kept.forEach((k) => { let n = k; while (n && n !== document.body) { chain.add(n); n = n.parentElement; } });
  const visit = (el) => {
    [...el.children].forEach((c) => {
      if (kept.includes(c)) return;
      if (chain.has(c)) visit(c); else c.remove();
    });
  };
  visit(document.body);
  const html = document.body.innerHTML
    .replace(/\s(?:data-phx-[\w-]+|phx-[\w-]+)="[^"]*"/g, '')
    .replace(/\sid="phx-[^"]*"/g, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/<meta name="csrf-token"[^>]*>/g, '')
    .replace(/\snonce="[^"]*"/g, '')
    .replace(/(src|href)="\/(images|favicon)/g, '$1="../../../../../../priv/static/$2')
    .replace(/\n\s*\n+/g, '\n');
  return { html };
}

async function load(page, url) {
  await page.goto(BASE + url + (url.includes('?') ? '&' : '?') + 'locale=de', { waitUntil: 'networkidle' });
  await page.waitForTimeout(1200);
}

// ------------------------------------------------------------ the frames
const ICONS = {
  x: ICON_X,
  attention: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0Z"></path><path d="M12 9v4"></path><circle cx="12" cy="17" r=".6"></circle></svg>'
};

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const andList = (parts) => (parts.length === 1 ? parts[0] : de('%{first} and %{second}', undefined, { first: parts.slice(0, -1).join(', '), second: parts[parts.length - 1] }));

// The words every dialog shares.
const COMMON = {
  icons: ICONS,
  cancel: de('Cancel'),
  close: de('Close'),
  closeLabel: de('Close'),
  journal: nu('journal'),
  lead: nu('removes'),
  nothing: nu('nothingElse')
};

// The rules the seed has reading what is deleted (policy_rule_versions),
// named as PolicyRuleReferences names them: "„name“ (gilt, Ansicht „…“)".
const RULE = de('“%{name}” (%{status}, view “%{view}”)');
const RULES = {
  strategies: [
    { name: 'Wachstum im Band', status: de('in force'), view: de('Everything'), href: '/risk?view=total' },
    { name: 'Helios nahe am Ziel', status: de('in force'), view: de('Everything'), href: '/risk?view=total' }
  ],
  growth: [{ name: 'Wachstum im Band', status: de('in force'), view: de('Everything'), href: '/risk?view=total' }],
  youngView: [{ name: 'Neuzugang: Schwankung unter 20 %', status: de('in force'), view: 'Nur Neuzugang', href: '/risk?view=2' }]
};
const refusal = (name, rules) => ({
  lead: esc(de('%{name} is read by policy rules:', undefined, { name: '\u0000' })).replace('\u0000', '<bdi>„' + esc(name) + '“</bdi>'),
  rulesRaw: rules,
  why: nu('refusalWhy')
});

// The seed's rows (README.md, "Where the counts come from"): Strategies holds
// 6 categories, 9 assignments and 2 target plans (the active "Plan" and the
// archived "Earlier mix") with 18 targets between them; Stability holds
// Quality below it, Quality's 2 assignments, and 2 targets each (one per
// plan); "Ohne Krypto" has no plan and no snapshot.
const D = {
  classificationSubject: { name: 'Strategies', ids: esc(de('%{count} category', 6) + ' · ' + de('%{count} level', 2)) },
  categorySubject: { name: 'Stability', ids: esc(nu('categoryIn', undefined, { classification: '\u0000' })).replace('\u0000', '<bdi>Strategies</bdi>'), figure: de('%{count} position', 2) },
  growthSubject: { name: 'Growth', ids: esc(nu('categoryIn', undefined, { classification: '\u0000' })).replace('\u0000', '<bdi>Strategies</bdi>'), figure: de('%{count} position', 6) },
  classificationItems: [
    esc(de('%{count} category', 6)),
    esc(nu('assignments', 9)),
    esc(nu('plans', 2)),
    esc(nu('targets', 18))
  ],
  // Variant B: the same counts, each with the names the page holds for it
  // (the tree's order; the plan picker's name and status).
  classificationItemsNamed: [
    esc(de('%{count} category', 6)) + ': <span class="delete-preview__names">' + ['Stability', 'Quality', 'Growth', 'Global Core', 'Platforms', 'Crypto'].map((n) => '<bdi>' + n + '</bdi>').join(', ') + '</span>',
    esc(nu('assignments', 9)) + ': <span class="delete-preview__names">' + esc(nu('more', 7, { names: '\u0000' })).replace('\u0000', ['Allianz SE vinkulierte Namens-Aktien o.N.', 'Larkspur Robotics Inc'].map((n) => '<bdi>' + n + '</bdi>').join(', ')) + '</span>',
    esc(nu('plans', 2)) + ': <span class="delete-preview__names"><bdi>Plan</bdi> (' + esc(de('active')) + '), <bdi>Earlier mix</bdi> (' + esc(de('archived')) + ')</span>',
    esc(nu('targets', 18))
  ],
  categoryItems: [
    esc(nu('categorySelf', 1, { name: '\u0000' })).replace('\u0000', '<bdi>Stability</bdi>'),
    esc(nu('assignments', 2)),
    esc(nu('targets', 4))
  ],
  // The changed state: a security assigned to Quality since the dialog
  // opened (synthetic: the seed has two).
  categoryItemsChanged: [
    esc(nu('categorySelf', 1, { name: '\u0000' })).replace('\u0000', '<bdi>Stability</bdi>'),
    esc(nu('assignments', 3)),
    esc(nu('targets', 4))
  ]
};

const CLS = '/classifications/3';
const KEEP_CLS = ['header.topbar', 'header.detail-head', '.workspace-section--controls', '#soll-editor'];
const KEEP_TREE = ['header.topbar', 'header.detail-head', '.workspace-section--controls', '.tree-head', 'section.tree', '#unsorted'];
const KEEP_VIEWS = ['header.topbar', '#views-section', '.row-context-menu'];

// A prep runs in the page (window.M is there); `a` carries its strings.
function prepNative(a) {
  M.native(a.text, a.vw <= 600);
  // The control that was clicked, ringed in the danger colour.
  if (a.clicked) { const t = document.querySelector(a.clicked); if (t) t.classList.add('mock-clicked'); else console.warn('clicked missing', a.clicked); }
}
function prepDialog(a) {
  // Close the open details so the tree reads as the page opens.
  document.querySelectorAll('section.tree details[open], #unsorted[open]').forEach((d) => d.removeAttribute('open'));
  if (a.spec.refusal) a.spec.refusal.rules = a.spec.refusal.rulesRaw.map((r) => M.rule(a.ruleTemplate, r));
  M.dialog(a.spec);
}
function closeTree() {
  document.querySelectorAll('section.tree details[open], #unsorted[open]').forEach((d) => d.removeAttribute('open'));
}
// The view row's kebab: the menu the "Delete" item sits in.
async function openViewMenu(page) {
  // The sidebar leaves first and the window takes the frame's width, so the
  // PositionedMenu hook places the menu where the static frame shows it.
  await page.evaluate(() => { document.querySelectorAll('#app-sidebar, .sidebar-backdrop').forEach((e) => e.remove()); document.body.classList.add('mock-noside'); const f = document.querySelector('.app-frame'); if (f) { f.style.paddingLeft = '0'; f.style.marginLeft = '0'; } });
  await page.setViewportSize({ width: 980, height: 900 });
  await page.waitForTimeout(300);
  await page.click('#view-kebab-1');
  await page.waitForSelector('.row-context-menu', { state: 'visible', timeout: 10000 });
  await page.waitForTimeout(400);
}

const specClassification = (o) => Object.assign({}, COMMON, {
  title: de('Delete classification'),
  subject: D.classificationSubject,
  confirm: de('Delete classification'),
  kept: nu('keptClassification')
}, o);
const specCategory = (o) => Object.assign({}, COMMON, {
  title: de('Delete category'),
  subject: D.categorySubject,
  confirm: de('Delete category'),
  kept: nu('keptCategory'),
  items: D.categoryItems
}, o);
const specView = (o) => Object.assign({}, COMMON, {
  title: nu('titleView'),
  confirm: nu('titleView'),
  kept: nu('keptView')
}, o);
const specRefusal = (subject, name, rules) => Object.assign({}, COMMON, {
  title: de('Cannot delete'),
  subject,
  refusal: refusal(name, rules)
});

function frames(viewSubject, youngSubject) {
  return [
    // --- the classification: the detail head's "Klassifizierung löschen"
    { id: 'cls-before', url: CLS, keep: KEEP_CLS, widths: [1200], prep: { fn: prepNative, args: { text: de('Delete this classification and all its categories?'), clicked: 'header.detail-head .button-danger' } } },
    { id: 'cls-refused', url: CLS, keep: KEEP_CLS, widths: [1200], proposal: true, prep: { fn: prepDialog, args: { spec: Object.assign(specRefusal(D.classificationSubject, 'Strategies', RULES.strategies), { pins: true }) } } },
    { id: 'cls-after-a', url: CLS, keep: KEEP_CLS, widths: [1200], proposal: true, prep: { fn: prepDialog, args: { spec: specClassification({ items: D.classificationItems, synth: true, pins: true }) } } },
    { id: 'cls-after-b', url: CLS, keep: KEEP_CLS, widths: [1200], proposal: true, prep: { fn: prepDialog, args: { spec: specClassification({ items: D.classificationItemsNamed, synth: true }) } } },
    // --- the category: the × in Stability's row
    { id: 'cat-before', url: CLS, keep: KEEP_TREE, widths: [1200], prep: [{ fn: closeTree }, { fn: prepNative, args: { text: de('Delete this category?'), clicked: 'section.tree > details:first-child > summary .cat-actions button:last-child' } }] },
    { id: 'cat-after', url: CLS, keep: KEEP_TREE, widths: [1200, 390], proposal: true, prep: { fn: prepDialog, args: { spec: specCategory({ pins: true }) } }, looks: [{ suffix: '' }, { suffix: '-dark', theme: 'dark', widths: [1200] }] },
    { id: 'cat-changed', url: CLS, keep: KEEP_TREE, widths: [1200], proposal: true, prep: { fn: prepDialog, args: { spec: specCategory({ items: D.categoryItemsChanged, changed: nu('changed'), synth: true }) } } },
    { id: 'cat-refused', url: CLS, keep: KEEP_TREE, widths: [390], proposal: true, prep: { fn: prepDialog, args: { spec: specRefusal(D.growthSubject, 'Growth', RULES.growth) } } },
    // --- the view: the row menu's "Löschen" on "Ohne Krypto"
    { id: 'view-before', url: '/buckets', keep: KEEP_VIEWS, widths: [1200], act: openViewMenu, prep: { fn: prepNative, args: { text: de('Delete this view?'), clicked: '.row-context-menu__item--danger' } } },
    { id: 'view-after', url: '/buckets', keep: KEEP_VIEWS.slice(0, 2), widths: [1200, 390], proposal: true, prep: { fn: prepDialog, args: { spec: specView({ subject: viewSubject, items: [], pins: true }) } } },
    { id: 'view-refused', url: '/buckets', keep: KEEP_VIEWS.slice(0, 2), widths: [1200], proposal: true, prep: { fn: prepDialog, args: { spec: specRefusal(youngSubject, 'Nur Neuzugang', RULES.youngView) } } }
  ];
}

function framePage(f, body, look = {}) {
  return `<!doctype html>
<html lang="de" data-theme="${look.theme || 'light'}" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${f.id}</title>
<link rel="stylesheet" href="../../../../../../priv/static/app.css">
${f.proposal ? `<style id="proposal">${PROPOSAL_CSS}</style>\n` : ''}<style id="frame">${FRAME_CSS}</style>
</head>
<body class="mock-noside">
${body}
</body>
</html>
`;
}

// Injected markup arrives on one line; long lines break before block tags,
// so a frame stays a readable multiline file (AGENTS.md).
const BLOCK = /><(?=(?:tr|li|section|details|table|thead|tbody|div|p|ul|label|form|fieldset|header|dialog|button|span class="phone-row)[\s>])/g;
const tidy = (s) => s.split('\n').map((l) => (l.length > 200 ? l.replace(BLOCK, '>\n<') : l)).join('\n').split('\n').map((l) => l.replace(/[ \t]+$/, '')).filter((l, i, a) => l !== '' || a[i - 1] !== '').join('\n');

async function captureAll(browser) {
  fs.mkdirSync(FRAMES, { recursive: true });
  // The two views' rows as the list shows them: the name and the rule
  // ("Alles · außer Crypto"); the counts are the row's, its amount is left out.
  const probe = await browser.newPage({ viewport: { width: 1200, height: 900 } });
  await load(probe, '/buckets');
  const rows = await probe.evaluate(() => [1, 2].map((id) => {
    const li = document.querySelector('#view-' + id);
    const t = (sel) => { const e = li.querySelector(sel); return e ? e.textContent.replace(/\s+/g, ' ').trim() : ''; };
    return { id, name: t('.bucket-list__name'), desc: t('.bucket-list__rule') };
  }));
  await probe.close();
  console.log('view rows', JSON.stringify(rows));
  const subj = (r, pos, acc) => ({ name: r.name, ids: esc(r.desc), figure: pos, figure2: acc });
  const viewS = subj(rows[0], de('%{count} position', 37), de('%{count} account', 28));
  const youngS = subj(rows[1], de('%{count} position', 1), de('%{count} account', 1));

  const out = {};
  const only = process.env.ONLY ? new RegExp(process.env.ONLY) : null;
  for (const f of frames(viewS, youngS)) {
    if (only && !only.test(f.id)) continue;
    for (const vw of f.widths) {
      const page = await browser.newPage({ viewport: { width: vw, height: 900 } });
      page.on('console', (m) => { if (m.type() === 'warning') console.warn('  page:', m.text()); });
      await load(page, f.url);
      if (f.act) await f.act(page, vw);
      await page.evaluate(HELPERS);
      for (const p of [].concat(f.prep || [])) {
        await page.evaluate(p.fn, Object.assign({ vw, ruleTemplate: RULE }, JSON.parse(JSON.stringify(p.args || {}))));
      }
      const keep = f.keep.concat(['.mock-scrim', 'dialog.mock-open', '.mock-native']);
      const r = await page.evaluate(isolate, { keep });
      await page.close();
      // A frame's own width: the main column a 1200 px window leaves beside
      // the 220 px sidebar, else the phone's viewport.
      const width = vw > 600 ? 980 : vw;
      for (const look of f.looks || [{ suffix: '' }]) {
        if (look.widths && !look.widths.includes(vw)) continue;
        const id = f.id + (look.suffix || '');
        const file = `${id}--${vw}.html`;
        fs.writeFileSync(path.join(FRAMES, file), tidy(framePage(f, r.html, look)));
        // Height: the dialog's (or the native box's) bottom plus a margin,
        // at least the part of the page that says where the delete was
        // chosen; a phone frame is a phone's screen.
        const m = await browser.newPage({ viewport: { width, height: vw > 600 ? 640 : 780 } });
        await m.goto('file://' + path.join(FRAMES, file));
        await m.waitForTimeout(300);
        const height = vw > 600
          ? await m.evaluate(() => {
              const b = Math.max(0, ...[...document.querySelectorAll('dialog.mock-open, .mock-native, .row-context-menu')].map((d) => d.getBoundingClientRect().bottom));
              return Math.max(Math.ceil(b) + 48, document.querySelector('.mock-native') ? 420 : 0);
            })
          : 780;
        await m.close();
        out[`${id}@${vw}`] = { file: 'frames/' + file, width, height };
        console.log(vw, id, width + 'x' + height);
      }
    }
  }
  return out;
}

module.exports = { de, nu, NEW, PROPOSAL_CSS };

if (require.main === module) {
  (async () => {
    const browser = await chromium.launch(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {});
    const sizesFile = path.join(FRAMES, 'sizes.json');
    const prev = process.env.ONLY && fs.existsSync(sizesFile) ? JSON.parse(fs.readFileSync(sizesFile, 'utf8')) : {};
    const sizes = Object.assign(prev, await captureAll(browser));
    await browser.close();
    fs.writeFileSync(sizesFile, JSON.stringify(sizes, null, 2) + '\n');
    require('./board.js').main(sizes);
  })().catch((e) => { console.error(e); process.exit(1); });
}
