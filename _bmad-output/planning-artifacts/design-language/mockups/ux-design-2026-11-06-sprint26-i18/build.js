// Builds the Sprint 26 planning board 03 for idea I18, "what a sale
// missed" (FR-50): the human view of GET /api/v1/sales/hindsight (modes 1
// and 2) and of mode 3, the comparison with the purchase the proceeds went
// into (ADR-0057). Three options for where modes 1 and 2 live (A, a column
// group on "All trades"; B, an expandable row under a trade; C, a section of
// its own, one row per sale booking: recommended), C's three comparison
// states, its ⓘ, the dark theme, the security page's Trades tab, mode 3 and
// the phone at 390 px.
//
// Every frame is captured from the running review instance on the synthetic
// review seed (priv/demo/finding_surfaces_seed.exs) with GET requests only.
// The theme is written to the browser's own storage before the load. The
// proposal is then written into the live DOM: its markup from the builders
// below, its CSS in the frame's <style id="proposal">.
//
// The sale rows are the seed's ten sale bookings as the hindsight read
// answers them (sale id, security, date, quantity, booked price, currency,
// and the span dates, which decide "pending"). The seed stores no closes
// around its sales, so the read answers every span "incomplete,
// no_start_close" there; the figures drawn are therefore SYNTHETIC
// (mock-synth, the amber stripe), invented for the board. Two rows keep the
// read's own answer (Harborline Freight Inc and Tamarisk Mining Ltd: no
// start close), so the incomplete state is drawn from a real reason too.
//
// German: every existing string comes from priv/gettext/de/LC_MESSAGES/
// default.po through de(); the new strings are the NEW table (proposals,
// listed in README.md).
//
// Usage (the review instance on port 4011, see README.md):
//   node build.js    # captures every frame, writes frames/ and both boards
//   node render.js   # renders both boards to PNG
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const BASE = process.env.BASE || 'http://localhost:4011';
const REPO = path.resolve(__dirname, '../../../../..');
const FRAMES = path.join(__dirname, 'frames');
const TODAY = '2026-11-06'; // the instance's as_of
const LATEST = '2026-11-05'; // the latest close the board assumes (synthetic)

// ------------------------------------------------------------ the catalogue
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
function de(msgid, count, bindings = {}) {
  const e = PO.get('\u0004' + msgid);
  if (!e) throw new Error('not in the catalogue: ' + msgid);
  const s = e.msgid_plural !== undefined ? e[count === 1 ? 'msgstr[0]' : 'msgstr[1]'] : e.msgstr;
  if (!s) throw new Error('no translation: ' + msgid);
  const b = Object.assign({ count }, bindings);
  return s.replace(/%\{(\w+)\}/g, (_, k) => (b[k] !== undefined ? b[k] : '%{' + k + '}'));
}

// ------------------------------------------------------------ new strings
// Proposals; README.md lists them with their English source.
const NEW = {
  section: 'Nach dem Verkauf',
  basis: 'Kursentwicklung je Verkauf in EUR · ab dem Verkaufstag · eine Zeile je Verkaufsbuchung',
  compare: 'Vergleich',
  none: 'Ohne',
  rate: 'Fester Zins',
  security: 'Wertpapier',
  switch: 'Anschlusskauf',
  sale: 'Verkauf',
  start: 'Startkurs',
  invested: 'Angelegt',
  m1: '1M', m3: '3M', m12: '12M', latest: 'Bis heute',
  latestSub: 'letzter Kurs',
  groupNone: 'Kursentwicklung des Wertpapiers',
  groupBm: (name) => 'Differenz zu ' + name,
  groupRate: (r) => 'Differenz zu ' + r + ' % p. a.',
  groupSwitch: 'Differenz gewechselt − behalten, in EUR',
  versus: 'ggü.',
  open: 'läuft',
  openUntil: (d) => 'bis ' + d,
  closeOf: (d) => 'Schluss ' + d,
  reasons: {
    no_start_close: 'kein Startkurs',
    no_end_close: 'kein Endkurs',
    no_fx_rate: de('no exchange rate'),
    no_benchmark_close: 'kein Benchmark-Kurs'
  },
  reasonTitles: {
    no_start_close: 'Kein Schlusskurs am Verkaufstag und keiner in den 7 Tagen davor',
    no_end_close: 'Kein Schlusskurs am Ende der Spanne und keiner in den 7 Tagen davor',
    no_fx_rate: 'Kein gespeicherter Wechselkurs nach EUR für einen der beiden Kurse',
    no_benchmark_close: 'Das Benchmark-Wertpapier hat keinen Kurs für den Start oder das Ende; die Zahl des Wertpapiers bleibt'
  },
  kept: 'behalten',
  switched: 'gewechselt',
  ofProceeds: (p) => p + ' des Erlöses',
  noBuys: 'Keine Anschlusskäufe gefunden: kein Kauf vom Verrechnungskonto des Verkaufs binnen 30 Tagen ab dem Verkaufstag',
  wentInto: 'Erlös angelegt in',
  bought: (d) => 'gekauft ' + d,
  daysAfter: (n) => n + (n === 1 ? ' Tag' : ' Tage') + ' nach dem Verkauf',
  prorata: (a, b) => 'anteilig ' + a + ' von ' + b + ' EUR',
  feesIn: 'Gebühren, in der Differenz',
  feeSale: 'Verkauf', feeBuy: 'Kauf', feeBuys: 'Käufe',
  taxesApart: 'Steuern des Verkaufs, nicht in der Differenz',
  incomeApart: 'Erträge der Käufe, nicht addiert',
  nothing: 'keine',
  legendBm: (name) => 'Je Spanne die Differenz zu ' + name + ', darunter Wertpapier ggü. Benchmark',
  legendNone: 'Je Spanne die Kursrendite des verkauften Wertpapiers',
  legendRate: (r) => 'Je Spanne die Differenz zu ' + r + ' % p. a., darunter Wertpapier ggü. Zins',
  legendSwitch: 'Je Spanne gewechselt − behalten in EUR, beide vor Steuern',
  priceOnly: 'Kursrendite: Ausschüttungen nach dem Verkauf nicht enthalten',
  info: [
    'Wie sich das verkaufte Wertpapier nach dem Verkauf bewegt hat: in EUR, über 1, 3 und 12 Kalendermonate ab dem Verkaufstag und bis zum letzten Schlusskurs.',
    'Start ist der Schlusskurs des Verkaufstags oder der letzte davor, höchstens 7 Tage älter; der gebuchte Verkaufskurs steht daneben und geht in keine Zahl ein.',
    'Kursrendite: Ausschüttungen nach dem Verkauf sind nicht gebucht, bei einem Dividendenzahler ist die Zahl also zu niedrig.',
    'Ein Benchmark-Wertpapier wird gleich gemessen, vom selben Start- bis zum selben Endtag; ein fester Zins wird täglich über die Kalendertage der Spanne verzinst.',
    'Eine Spanne, die nach heute endet, läuft noch und hat keine Zahl. Fehlt ein Kurs oder ein Wechselkurs, bleibt die Spanne ohne Zahl und nennt den Grund: nie geschätzt.',
    'Eine Zeile je Verkaufsbuchung, nicht je FIFO-Lot; ein Verkauf ohne zugeordneten Kauf zählt mit, eine Auslieferung ist kein Verkauf.'
  ],
  infoSwitch: [
    'Anschlusskauf: die Käufe vom Verrechnungskonto des Verkaufs, am Verkaufstag oder bis zu 30 Tage danach, verbrauchen den Erlös in Datumsfolge, bis er aufgebraucht ist; der letzte zählt anteilig.',
    'Behalten: was die verkaufte Position wert wäre, auf den angelegten Teil des Erlöses skaliert, nur Kurs. Gewechselt: der Wert der gekauften Position; vor dem Kaufdatum zählt das Geld als Cash zum gebuchten Betrag.',
    'Die gebuchten Gebühren des Verkaufs und der Käufe stecken in der Differenz. Die Steuern des Verkaufs stehen daneben und nicht in der Differenz, weil die latente Steuer der behaltenen Seite ebenso unbekannt ist: beide Seiten vor Steuern. Erträge der gekauften Position werden genannt, nicht addiert.'
  ],
  showHide: 'Nach dem Verkauf',
  elided: (n) => '… ' + n + ' weitere Verkäufe, für das Board gekürzt',
  elidedTrades: (n) => '… ' + n + ' weitere Trades, für das Board gekürzt'
};

// ------------------------------------------------------------ the rows
// The seed's ten sale bookings (the read's own fields), with SYNTHETIC
// figures: start close in EUR, and per span the security's return r and the
// benchmark's b (Kestrel Industrial Group NV Index, the seed's one security
// flagged is_benchmark). A span is [r, b], or { i: reason, r? } where the
// read cannot measure it; spans whose end is after TODAY are pending by date.
const BENCH = 'Kestrel Industrial Group NV Index';
const RATE = 0.03;
const SALES = [
  { id: 65, sec: 'Harborline Freight Inc', date: '2026-10-07', qty: '10', price: 36, cur: 'USD', real: true,
    start: null, startReason: 'no_start_close',
    spans: [null, null, null, { i: 'no_start_close' }] },
  { id: 63, sec: 'Brightwater Utilities plc', date: '2026-09-27', qty: '13', price: 33, cur: 'EUR', trade: '27.09.2026',
    start: { eur: 32.8, date: '2026-09-25' },
    spans: [[0.024, 0.011], null, null, [0.037, 0.02]] },
  { id: 60, sec: 'Saltmarsh Logistics SE', date: '2026-09-07', qty: '15', price: 22, cur: 'EUR',
    start: { eur: 22.1, date: '2026-09-07' },
    spans: [[-0.042, 0.008], null, null, [-0.019, 0.026]] },
  { id: 58, sec: 'Tamarisk Mining Ltd', date: '2026-07-29', qty: '10', price: 0, cur: 'EUR', real: true, trade: '29.07.2026',
    start: null, startReason: 'no_start_close',
    spans: [{ i: 'no_start_close' }, { i: 'no_start_close' }, null, { i: 'no_start_close' }] },
  { id: 98, sec: 'Arbolia Inc.', date: '2026-07-09', qty: '10', price: 120, cur: 'USD',
    start: { eur: 102.35, native: '118,40 USD', date: '2026-07-09' },
    spans: [[0.061, 0.014], [0.098, 0.022], null, [0.112, 0.029]] },
  { id: 97, sec: 'Kestrel Bay Resources Inc.', date: '2026-07-09', qty: '10', price: 120, cur: 'CAD', trade: '09.07.2026',
    start: { eur: 75.1, native: '119,60 CAD', date: '2026-07-09' },
    spans: [[-0.023, 0.014], { i: 'no_fx_rate' }, null, [-0.008, 0.029]] },
  { id: 56, sec: 'Wrenfield Gardens AG', date: '2026-07-09', qty: '20', price: 71, cur: 'EUR', trade: '09.07.2026',
    start: { eur: 70.6, date: '2026-07-09' },
    spans: [[0.01, 0.014], [0.044, 0.022], null, [0.051, 0.029]] },
  { id: 80, sec: 'Thornbury Water Fund', twin: 'XS0000000173', date: '2025-05-05', qty: '5', price: 105, cur: 'EUR', trade: '05.05.2025',
    start: { eur: 104.2, date: '2025-05-05' },
    spans: [[-0.012, 0.009], [0.006, 0.027], [0.063, 0.089], [0.094, 0.131]] },
  { id: 79, sec: 'Thornbury Water Fund', twin: 'XS0000000165', date: '2025-04-07', qty: '5', price: 120, cur: 'EUR', trade: '07.04.2025',
    start: { eur: 119.5, date: '2025-04-07' },
    spans: [[0.031, 0.042], [0.027, 0.061], [0.04, 0.097], [0.068, 0.14]] },
  { id: 11, sec: 'Microsoft Corporation Registered Shares DL-,00000625', date: '2023-09-10', qty: '10', price: 220, cur: 'EUR', trade: '10.09.2023',
    start: { eur: 218.9, date: '2023-09-08' },
    spans: [{ r: 0.027, bm: 'no_benchmark_close' }, { r: 0.124, bm: 'no_benchmark_close' }, { r: 0.318, bm: 'no_benchmark_close' }, { r: 0.842, bm: 'no_benchmark_close' }] }
];

// Mode 3 (ADR-0057), SYNTHETIC: the buys the proceeds went into, by rule
// (same cash account, on or after the sale day, within 30 days, consumed in
// date order, the last pro rata). Per span [kept, switched] in EUR.
const SWITCH = {
  63: { invested: 400.0, share: '94,3 %',
    buys: [{ sec: 'Vanguard FTSE All-World UCITS ETF USD Acc', date: '2026-10-02', amount: '400,00' }],
    fees: { sale: '4,90', buy: '1,50' }, taxes: null, income: null,
    spans: [[410.2, 418.6], null, null, [415.0, 421.9]] },
  60: null,
  56: { invested: 1410.1, share: '100 %',
    buys: [{ sec: 'Birchwood Global Savings Fund', date: '2026-07-10', amount: '800,00' },
      { sec: 'Harborline Freight Inc', date: '2026-07-23', amount: '610,10', of: '655,00' }],
    fees: { sale: '9,90', buy: '2,50' }, taxes: '110,78', income: '6,20',
    spans: [[1434.2, 1451.8], [1482.4, 1461.3], null, [1492.6, 1470.0]] },
  79: { invested: 300.0, share: '50,4 %',
    buys: [{ sec: 'Vanguard FTSE All-World UCITS ETF USD Acc', date: '2025-04-14', amount: '300,00' }],
    fees: { sale: '4,90', buy: '1,50' }, taxes: '5,27', income: null,
    spans: [[309.3, 305.1], [308.1, 318.6], [312.0, 331.8], [320.4, 349.7]] },
  11: { invested: 2186.4, share: '99,8 %',
    buys: [{ sec: 'Allianz SE vinkulierte Namens-Aktien o.N.', date: '2023-09-25', amount: '2.186,40' }],
    fees: { sale: '9,90', buy: '9,90' }, taxes: null, income: '114,00',
    spans: [[2245.4, 2241.7], [2457.5, 2380.2], [2881.9, 2702.6], [4027.3, 3398.9]] }
};

// ------------------------------------------------------------ formatting
const nf = (x, d = 2) => {
  const s = Math.abs(x).toFixed(d).split('.');
  return s[0].replace(/\B(?=(\d{3})+(?!\d))/g, '.') + (d ? ',' + s[1] : '');
};
const signOf = (x, d) => (Number(Math.abs(x).toFixed(d)) === 0 ? 0 : Math.sign(x));
const pct = (x) => { const s = signOf(x * 100, 1); return (s > 0 ? '+' : s < 0 ? '−' : '') + nf(x * 100, 1) + '%'; };
const money = (x) => { const s = signOf(x, 2); return (s > 0 ? '+' : s < 0 ? '−' : '') + nf(x, 2); };
const cls = (x, d) => { const s = signOf(x, d); return s > 0 ? 'decimal-positive' : s < 0 ? 'decimal-negative' : ''; };
const dmy = (iso) => iso.split('-').reverse().join('.');
const shift = (iso, months) => {
  const [y, m, d] = iso.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1 + months, 1));
  const last = new Date(Date.UTC(t.getUTCFullYear(), t.getUTCMonth() + 1, 0)).getUTCDate();
  t.setUTCDate(Math.min(d, last));
  return t.toISOString().slice(0, 10);
};
const days = (a, b) => Math.round((Date.parse(b) - Date.parse(a)) / 86400000);
const endOn = (sale, i) => (i < 3 ? shift(sale.date, [1, 3, 12][i]) : LATEST);
const rateReturn = (sale, i) => Math.pow(1 + RATE, days(sale.date, endOn(sale, i)) / 365) - 1;
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');

// ------------------------------------------------------------ the builders
// One span, as { lead, leadClass, subs[], state, synth, title }.
function span(sale, i, mode) {
  const end = endOn(sale, i);
  if (end > TODAY) return { state: 'open', lead: NEW.open, subs: [NEW.openUntil(dmy(end))] };
  const s = sale.spans[i];
  if (mode === 'switch') {
    const sw = SWITCH[sale.id];
    const v = sw.spans[i];
    if (!v) return { state: 'open', lead: NEW.open, subs: [NEW.openUntil(dmy(end))] };
    const diff = v[1] - v[0];
    return { lead: money(diff) + ' <small class="value-suffix">EUR</small>', leadClass: cls(diff, 2), subs: [NEW.kept + ' ' + nf(v[0]), NEW.switched + ' ' + nf(v[1])], synth: true };
  }
  if (s && s.i) return { state: 'na', lead: '—', subs: [NEW.reasons[s.i]], title: NEW.reasonTitles[s.i], synth: !sale.real };
  const r = Array.isArray(s) ? s[0] : s.r;
  if (mode === 'none') return { lead: pct(r), leadClass: cls(r * 100, 1), subs: [], synth: true };
  if (mode === 'security' && s.bm) return { state: 'na', lead: '—', subs: [pct(r) + ' ' + NEW.versus + ' —', NEW.reasons[s.bm]], title: NEW.reasonTitles[s.bm], synth: true };
  const b = mode === 'rate' ? rateReturn(sale, i) : s[1];
  const d = r - b;
  return { lead: pct(d), leadClass: cls(d * 100, 1), subs: [pct(r) + ' ' + NEW.versus + ' ' + pct(b)], synth: true };
}

const nameCell = (sale) => esc(sale.sec) + (sale.twin ? ` <span class="twin-id"><span class="visually-hidden">ISIN</span> ${sale.twin}</span>` : '');
const saleCell = (sale) => `${dmy(sale.date)}<span class="stat__sub">${sale.qty} × ${nf(sale.price)} ${sale.cur}</span>`;
const startNone = (sale) => NEW.reasons[sale.startReason];
function startCell(sale) {
  if (!sale.start) return `<td class="num trade-pa--na" title="${NEW.reasonTitles[sale.startReason]}"><span aria-hidden="true">—</span><span class="stat__sub">${NEW.reasons[sale.startReason]}</span></td>`;
  const st = sale.start;
  const subs = [NEW.closeOf(dmy(st.date))].concat(st.native ? [st.native] : []);
  return `<td class="num mock-synth">${nf(st.eur)} <small class="value-suffix">EUR</small>${subs.map((t) => `<span class="stat__sub">${t}</span>`).join('')}</td>`;
}
function spanTd(sp) {
  const c = ['num', 'hs-span', sp.state === 'open' && 'hs-span--open', sp.state === 'na' && 'trade-pa--na', sp.synth && 'mock-synth'].filter(Boolean).join(' ');
  return `<td class="${c}"${sp.title ? ` title="${sp.title}"` : ''}><span class="hs-lead ${sp.leadClass || ''}">${sp.lead}</span>${sp.subs.map((t) => `<span class="stat__sub">${t}</span>`).join('')}</td>`;
}
const SPAN_HEADS = [NEW.m1, NEW.m3, NEW.m12, NEW.latest];

function chooser(mode) {
  const opt = (m, label) => `<a href="#" class="segmented-control__option${m === mode ? ' is-active' : ''}"${m === mode ? ' aria-current="true"' : ''}>${label}</a>`;
  let field = '';
  if (mode === 'rate') field = `<span class="hs-controls__field"><label for="hs-rate">${de('Fixed rate % p.a.')}</label><input type="number" id="hs-rate" value="3.00" step="0.01"><button type="button">${de('Apply')}</button></span>`;
  if (mode === 'security') field = `<span class="hs-controls__field"><label for="hs-bench" class="visually-hidden">${de('Benchmark')}</label><select id="hs-bench"><option selected>${BENCH}</option></select></span>`;
  return `<div class="hs-controls" data-role="hindsight-compare">
<span class="hs-controls__label" id="hs-compare-label">${NEW.compare}</span>
<nav class="segmented-control" aria-labelledby="hs-compare-label">${opt('none', NEW.none)}${opt('rate', NEW.rate)}${opt('security', NEW.security)}${opt('switch', NEW.switch)}</nav>
${field}
</div>`;
}
const groupHead = (mode) => ({ none: NEW.groupNone, rate: NEW.groupRate('3,00'), security: NEW.groupBm(BENCH), switch: NEW.groupSwitch })[mode];
const legend = (mode) => ({ none: NEW.legendNone, rate: NEW.legendRate('3,00'), security: NEW.legendBm(BENCH), switch: NEW.legendSwitch })[mode];

function info(mode, open) {
  const lines = NEW.info.concat(mode === 'switch' ? [''].concat(NEW.infoSwitch) : []);
  return `<details class="metric-tooltip metric-tooltip--inline" data-role="hindsight-info"${open ? ' open' : ''}><summary aria-label="${de('About this section')}">ⓘ</summary><p role="tooltip">${lines[0]}<br><br>${lines.slice(1).join('<br>')}</p></details>`;
}

function switchDetail(sale) {
  const sw = SWITCH[sale.id];
  const buys = sw.buys.map((b) => `<b>${esc(b.sec)}</b>, ${NEW.bought(dmy(b.date))} (${NEW.daysAfter(days(sale.date, b.date))}), ${b.of ? NEW.prorata(b.amount, b.of) : b.amount + ' EUR'}`).join('; ');
  const costs = [
    `${NEW.feesIn}: ${sw.fees.sale} EUR ${NEW.feeSale}, ${sw.fees.buy} EUR ${sw.buys.length > 1 ? NEW.feeBuys : NEW.feeBuy}`,
    `${NEW.taxesApart}: ${sw.taxes ? sw.taxes + ' EUR' : NEW.nothing}`,
    `${NEW.incomeApart}: ${sw.income ? sw.income + ' EUR' : NEW.nothing}`
  ];
  return `<span class=.hs-detail__buys">${NEW.wentInto}: ${buys}</span><span class="hs-detail__costs">${costs.join(' · ')}</span>`;
}

// The section's table and phone rows for a mode; `ids` limits the rows,
// `noName` drops the security column (the security page).
function table(mode, ids, o = {}) {
  const rows = SALES.filter((s) => ids.includes(s.id));
  const cols = (o.noName ? 0 : 1) + 2 + 4;
  const head = `<thead>
<tr class="hs-grouprow"><th colspan="${cols - 4}"></th><th colspan="4" class="hs-group">${NEW.section} <span class="hs-group__sub">· ${groupHead(mode)}</span></th></tr>
<tr>${o.noName ? '' : `<th>${de('Security')}</th>`}<th>${NEW.sale}</th><th class="num">${mode === 'switch' ? NEW.invested : NEW.start}</th>${SPAN_HEADS.map((h, i) => `<th class="num">${h}${i === 3 ? `<span class="hs-th-sub">${NEW.latestSub}</span>` : ''}</th>`).join('')}</tr>
</thead>`;
  const body = rows.map((sale) => {
    const first = (o.noName ? '' : `<td data-role="hindsight-name"><a href="#">${nameCell(sale)}</a></td>`) + `<td class="hs-sale">${saleCell(sale)}</td>`;
    if (mode !== 'switch') return `<tr data-role="hindsight-row" data-sale="${sale.id}">${first}${startCell(sale)}${[0, 1, 2, 3].map((i) => spanTd(span(sale, i, mode))).join('')}</tr>`;
    const sw = SWITCH[sale.id];
    if (!sw) return `<tr data-role="hindsight-row" data-sale="${sale.id}">${first}<td class="num trade-pa--na"><span aria-hidden="true">—</span></td><td colspan="4" class="hs-nobuys mock-synth">${NEW.noBuys}</td></tr>`;
    return `<tr data-role="hindsight-row" class="hs-has-detail" data-sale="${sale.id}">${first}<td class="num mock-synth">${nf(sw.invested)} <small class="value-suffix">EUR</small><span class="stat__sub">${NEW.ofProceeds(sw.share)}</span></td>${[0, 1, 2, 3].map((i) => spanTd(span(sale, i, mode))).join('')}</tr>
<tr class="hs-detail" data-sale="${sale.id}"><td colspan="${cols}" class="mock-synth">${switchDetail(sale)}</td></tr>`;
  }).join('\n');
  const phone = rows.map((sale) => {
    const ids2 = `${o.noName ? '' : ''}${NEW.sale} ${dmy(sale.date)} · ${sale.qty} × ${nf(sale.price)} ${sale.cur}`;
    let extra;
    if (mode === 'switch') {
      const sw = SWITCH[sale.id];
      extra = sw ? `${NEW.invested} ${nf(sw.invested)} EUR · ${NEW.ofProceeds(sw.share)}` : '';
    } else {
      extra = sale.start ? `${NEW.start} ${nf(sale.start.eur)} EUR · ${dmy(sale.start.date)}` : startNone(sale);
    }
    const grid = mode === 'switch' && !SWITCH[sale.id]
      ? `<p class="hs-nobuys hs-nobuys--phone mock-synth">${NEW.noBuys}</p>`
      : `<dl class="hs-grid">${[0, 1, 2, 3].map((i) => { const sp = span(sale, i, mode); return `<div class="hs-grid__cell${sp.state === 'na' ? ' trade-pa--na' : ''}${sp.state === 'open' ? ' hs-span--open' : ''}${sp.synth ? ' mock-synth' : ''}"><dt>${SPAN_HEADS[i]}</dt><dd><span class="hs-lead ${sp.leadClass || ''}">${sp.lead}</span>${sp.subs.map((t) => `<span class="stat__sub">${t}</span>`).join('')}</dd></div>`; }).join('')}</dl>`;
    const detail = mode === 'switch' && SWITCH[sale.id] ? `<p class="hs-detail-phone mock-synth">${switchDetail(sale)}</p>` : '';
    return `<li class="phone-row hs-phone-row" data-role="hindsight-row" data-sale="${sale.id}"><span class="phone-row__body">${o.noName ? '' : `<span class="phone-row__name">${nameCell(sale)}</span>`}<span class="phone-row__ids">${ids2}</span><span class="phone-row__ids">${extra}</span></span>${grid}${detail}</li>`;
  }).join('\n');
  return { head, body, phone };
}

function section(mode, ids, o = {}) {
  const t = table(mode, ids, o);
  const h = o.h3
    ? `<div class="section-title"><h3 class="detail-section-title">${NEW.section}</h3>${info(mode, o.infoOpen).replace('metric-tooltip--inline', 'metric-tooltip--inline metric-tooltip--section')}</div>`
    : `<h2>${NEW.section}</h2><div class="summary-basis hs-basis">${NEW.basis}${info(mode, o.infoOpen)}</div>`;
  return `<section id="${o.h3 ? 'detail-sale-hindsight' : 'sale-hindsight'}" class="${o.h3 ? 'hs-detail-section' : 'workspace-section'} hs-section mock-new" data-role="sale-hindsight">
${h}
${chooser(mode)}
<div class="data-table-wrapper hs-table-wrapper"><table class="data-table hs-table">${t.head}<tbody>
${t.body}
</tbody></table></div>
<ul class="phone-rows hs-phone-rows" aria-label="${NEW.section}">
${t.phone}
</ul>
<p class="summary-basis hs-legend">${legend(mode)} · ${NEW.priceOnly}</p>
</section>`;
}

// ------------------------------------------------------------ option A, B
// A: four columns on each trade row; B: a row that opens under a trade.
function optionA(tradeRows) {
  const heads = `<th class="num hs-a-first mock-new">${NEW.m1}</th><th class="num mock-new">${NEW.m3}</th><th class="num mock-new">${NEW.m12}</th><th class="num mock-new">${NEW.latest}</th>`;
  const cells = {};
  for (const sale of SALES) if (sale.trade) cells[sale.sec + '|' + sale.trade] = [0, 1, 2, 3].map((i) => { const sp = span(sale, i, 'security'); sp.subs = sp.state === 'open' ? [] : sp.state === 'na' ? [sp.subs[sp.subs.length - 1]] : []; return spanTd(sp); }).join('');
  return { heads, cells };
}

const CSS = fs.readFileSync(path.join(__dirname, 'proposal.css'), 'utf8');

// ------------------------------------------------------------ frame chrome
const FRAME_CSS = `
body { margin: 0; background: var(--color-bg); }
.app-frame { padding-left: 0 !important; margin-left: 0 !important; }
.app-shell, .app-frame, .app-main, .workspace-page { min-height: 0 !important; }
.app-main { padding-bottom: 12px; }
.topbar { position: relative !important; top: auto !important; }
.mock-new { outline: 2px dashed var(--color-accent); outline-offset: 2px; border-radius: 4px; }
th.mock-new, td.mock-new { outline-offset: -2px; border-radius: 0; }
.mock-synth { box-shadow: inset 3px 0 0 #f59e0b; }
.mock-pin { display: inline-grid; place-items: center; flex: none; width: 20px; height: 20px; border-radius: 50%; background: #c026d3; color: #fff; font: 700 12px/1 var(--font-sans); letter-spacing: 0; text-transform: none; margin: 0 4px; vertical-align: middle; box-shadow: 0 0 0 2px #fff; }
.mock-pin--abs { position: absolute; left: 4px; top: 4px; margin: 0; z-index: 5; }
.mock-pinned { position: relative; }
.mock-elided { margin: 8px 0; padding: 6px 10px; border: 1px dashed var(--color-border-strong); border-radius: 6px; font-size: 11.5px; color: var(--color-text-muted); list-style: none; text-align: center; }
tr.mock-elided td { padding: 6px 10px !important; font-size: 11.5px; color: var(--color-text-muted); text-align: center; }
#security-detail-pane { position: static !important; inset: auto !important; transform: none !important; max-height: none !important; height: auto !important; box-shadow: none !important; }
`;

// In-page: cut the page to what a frame shows, then insert the proposal.
function transform(a) {
  const el = (html) => { const t = document.createElement('template'); t.innerHTML = html.trim(); return t.content.firstElementChild; };
  const pin = (target, n, where) => {
    const t = typeof target === 'string' ? document.querySelector(target) : target;
    if (!t) { console.warn('pin target missing', target); return; }
    const s = el(`<span class="mock-pin">${n}</span>`);
    if (where === 'abs') { s.classList.add('mock-pin--abs'); t.classList.add('mock-pinned'); t.prepend(s); } else if (where === 'pre') t.prepend(s); else t.appendChild(s);
  };
  const elide = (rows, text, cols) => {
    if (!rows.length) return;
    const tr = rows[0].tagName === 'TR';
    const line = el(tr ? `<tr class="mock-elided"><td colspan="${cols || 12}">${text}</td></tr>` : `<li class="mock-elided">${text}</li>`);
    rows[0].before(line);
    rows.forEach((r) => r.remove());
  };
  document.querySelectorAll('script').forEach((s) => s.remove());
  document.querySelectorAll('#app-sidebar, .sidebar-backdrop').forEach((e) => e.remove());

  if (a.page === 'realized') {
    const main = document.querySelector('.app-main');
    if (a.cutNotes) document.querySelectorAll('#realized-excluded, #realized-unmatched').forEach((e) => e.remove());
    if (a.cutKpis) document.querySelectorAll('#realized-figures').forEach((e) => e.remove());
    const trs = [...document.querySelectorAll('#realized-trades-table > tbody > tr')];
    const lis = [...document.querySelectorAll('#realized-trades-phone-rows > li')];
    if (a.variant === 'a') {
      const head = document.querySelector('#realized-trades-table thead tr');
      head.insertAdjacentHTML('beforeend', a.A.heads);
      trs.forEach((tr) => {
        const name = tr.querySelector('[data-role="trade-name"] a').textContent.replace(/\s+/g, ' ').trim();
        const close = tr.children[1].textContent.replace(/\s+/g, ' ').split('→')[1].trim();
        tr.insertAdjacentHTML('beforeend', a.A.cells[name + '|' + close] || '');
      });
      const wrap = document.querySelector('#realized-trades-table-wrapper');
      wrap.before(el(a.A.chooser));
      pin(document.querySelector('.hs-a-first'), 1, 'abs');
    }
    if (a.variant === 'b') {
      trs.forEach((tr) => {
        const nameTd = tr.querySelector('[data-role="trade-name"]');
        nameTd.insertAdjacentHTML('beforeend', a.B.toggle);
      });
      const target = trs.find((tr) => /Wrenfield/.test(tr.textContent));
      target.querySelector('.hs-b-toggle').setAttribute('aria-expanded', 'true');
      target.querySelector('.hs-b-toggle').classList.add('is-open');
      target.insertAdjacentHTML('afterend', a.B.row);
      document.querySelector('#realized-trades-table-wrapper').before(el(a.B.chooser));
      pin(target.querySelector('.hs-b-toggle'), 1);
    }
    if (a.variant === 'c' || a.variant === 'm3') {
      if (a.keepTrades !== undefined) {
        elide(trs.slice(a.keepTrades), a.elidedTrades.replace('%n', trs.length - a.keepTrades), 8);
        elide(lis.slice(a.keepTrades), a.elidedTrades.replace('%n', lis.length - a.keepTrades));
      }
      document.querySelector('#realized-trades').after(el(a.section));
      if (a.onlySection) {
        const keep = document.querySelector('#sale-hindsight');
        [...main.children].forEach((c) => { if (!c.contains(keep) && c !== keep) c.remove(); });
        const visit = (n) => [...n.children].forEach((c) => { if (c === keep) return; if (c.contains(keep)) visit(c); else c.remove(); });
        visit(main);
      }
    }
    if (a.dropAnnual) document.querySelectorAll('#realized-annual').forEach((e) => e.remove());
  }
  if (a.page === 'security') {
    document.querySelector('#detail-closed-trades-basis').after(el(a.section));
    const pane = document.querySelector('#security-detail-pane');
    const body = document.body;
    const frame = el('<div class="mock-pane-frame"></div>');
    frame.appendChild(pane);
    [...body.children].forEach((c) => c.remove());
    body.appendChild(frame);
  }
  if (a.noTopbar) document.querySelectorAll('header.topbar').forEach((e) => e.remove());
  // pins on the new section
  for (const [sel, n, where] of a.pins || []) pin(sel, n, where);
  const html = document.body.innerHTML
    .replace(/\s(?:data-phx-[\w-]+|phx-[\w-]+)="[^"]*"/g, '')
    .replace(/\sid="phx-[^"]*"/g, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/(src|href)="\/(images|favicon)/g, '$1="../../../../../../priv/static/$2')
    .replace(/\n\s*\n+/g, '\n');
  return { html };
}

function framePage(id, body, theme) {
  return `<!doctype html>
<html lang="de" data-theme="${theme}" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${id}</title>
<link rel="stylesheet" href="../../../../../../priv/static/app.css">
<style id="proposal">${CSS}</style>
<style id="frame">${FRAME_CSS}</style>
</head>
<body>
${body}
</body>
</html>
`;
}
const BLOCK = /><(?=(?:tr|td|th|li|section|details|table|thead|tbody|div|p|ul|dl|dt|dd|label|form|nav|select|button)[\s>]|span class="(?:phone-row__|hs-lead|stat__sub|hs-detail__))/g;
const tidy = (s) => s.split('\n').map((l) => (l.length > 300 ? l.replace(BLOCK, '>\n<') : l)).join('\n').split('\n').map((l) => l.replace(/[ \t]+$/, '')).filter((l, i, a) => l !== '' || a[i - 1] !== '').join('\n');

// ------------------------------------------------------------ the frames
const ALL = SALES.map((s) => s.id);
const B_ROW = (() => {
  const sale = SALES.find((s) => s.id === 56);
  const cells = [0, 1, 2, 3].map((i) => {
    const end = endOn(sale, i);
    const s = sale.spans[i];
    if (end > TODAY) return `<div class="hs-b-cell hs-span--open"><dt>${SPAN_HEADS[i]}</dt><dd>${NEW.open} <span class="stat__sub">${NEW.openUntil(dmy(end))}</span></dd></div>`;
    const d = s[0] - s[1];
    return `<div class="hs-b-cell mock-synth"><dt>${SPAN_HEADS[i]} <span class="hs-th-sub">${dmy(end)}</span></dt><dd><span class="hs-b-k">${NEW.security}</span><span class="${cls(s[0] * 100, 1)}">${pct(s[0])}</span><span class="hs-b-k">${de('Benchmark')}</span><span class="${cls(s[1] * 100, 1)}">${pct(s[1])}</span><span class="hs-b-k">Differenz</span><b class="${cls(d * 100, 1)}">${pct(d)}</b></dd></div>`;
  }).join('');
  return `<tr class="hs-b-row mock-new"><td colspan="8"><div class="hs-b-head">${NEW.section} · ${NEW.sale} ${dmy(sale.date)}, ${NEW.start} ${nf(sale.start.eur)} EUR (${NEW.closeOf(dmy(sale.start.date))}) · ${NEW.groupBm(BENCH)}</div><dl class="hs-b-grid">${cells}</dl></td></tr>`;
})();
const B_TOGGLE = `<button type="button" class="hs-b-toggle mock-new" aria-expanded="false"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 18 6-6-6-6"></path></svg>${NEW.showHide}</button>`;

const SEC = { 'security': ALL, 'none': ALL, 'rate': ALL, 'switch': [63, 60, 56, 79, 11] };
const PINS_C = [
  ['#sale-hindsight .hs-controls', 1, 'pre'],
  ['#sale-hindsight tr[data-sale="63"] td.hs-span--open', 2, 'abs'],
  ['#sale-hindsight tr[data-sale="65"] td.hs-span.trade-pa--na', 3, 'abs'],
  ['#sale-hindsight .hs-basis', 4]
];
const PINS_PHONE = [
  ['#sale-hindsight .hs-controls', 1, 'pre'],
  ['#sale-hindsight li[data-sale="63"] .hs-span--open dt', 2, 'pre'],
  ['#sale-hindsight li[data-sale="65"] .trade-pa--na dt', 3, 'pre'],
  ['#sale-hindsight .hs-basis', 4]
];
const PINS_M3 = [
  ['#sale-hindsight .hs-controls', 1, 'pre'],
  ['#sale-hindsight tr.hs-detail[data-sale="56"] td', 5, 'pre'],
  ['#sale-hindsight tr[data-sale="60"] td.hs-nobuys', 6, 'pre']
];
const elided = (ids) => (ids.length < SALES.length ? `<tr class="mock-elided"><td colspan="7">${NEW.elided(SALES.length - ids.length)}</td></tr>` : '');
function sec(mode, ids, o = {}) {
  let s = section(mode, ids, o);
  if (ids.length < SALES.length && !o.noName) s = s.replace('</tbody>', elided(ids) + '\n</tbody>').replace('</ul>', `<li class="mock-elided">${NEW.elided(SALES.length - ids.length)}</li>\n</ul>`);
  return s;
}

const FRAMES_DEF = [
  { id: 'a', page: 'realized', url: '/cashflow?tab=realized', vw: 1280, theme: 'light', variant: 'a', cutNotes: false, dropAnnual: true },
  { id: 'b', page: 'realized', url: '/cashflow?tab=realized', vw: 1280, theme: 'light', variant: 'b', cutNotes: true, cutKpis: true, dropAnnual: true },
  { id: 'c', page: 'realized', url: '/cashflow?tab=realized', vw: 1280, theme: 'light', variant: 'c', mode: 'security', ids: ALL, cutNotes: true, cutKpis: true, keepTrades: 2, pins: PINS_C },
  { id: 'c-dark', page: 'realized', url: '/cashflow?tab=realized', vw: 1280, theme: 'dark', variant: 'c', mode: 'security', ids: ALL, cutNotes: true, cutKpis: true, keepTrades: 2, pins: PINS_C },
  { id: 'c-none', page: 'realized', url: '/cashflow?tab=realized', vw: 1280, theme: 'light', variant: 'c', mode: 'none', ids: [65, 63, 56, 80, 11], onlySection: true },
  { id: 'c-rate', page: 'realized', url: '/cashflow?tab=realized', vw: 1280, theme: 'light', variant: 'c', mode: 'rate', ids: [65, 63, 56, 80, 11], onlySection: true },
  { id: 'c-info', page: 'realized', url: '/cashflow?tab=realized', vw: 1280, theme: 'light', variant: 'c', mode: 'security', ids: [63, 56], onlySection: true, infoOpen: true, noTopbar: true, pins: [['#sale-hindsight .hs-basis', 4]] },
  { id: 'm3', page: 'realized', url: '/cashflow?tab=realized', vw: 1280, theme: 'light', variant: 'm3', mode: 'switch', ids: SEC.switch, onlySection: true, pins: PINS_M3 },
  { id: 'security', page: 'security', url: '/securities/32?tab=trades', vw: 1280, theme: 'light', mode: 'security', ids: [56], h3: true },
  { id: 'c-390', page: 'realized', url: '/cashflow?tab=realized', vw: 390, theme: 'light', variant: 'c', mode: 'security', ids: [65, 63, 97, 56, 11], cutNotes: true, cutKpis: true, keepTrades: 1, dropAnnual: true, pins: PINS_PHONE },
  { id: 'c-390-dark', page: 'realized', url: '/cashflow?tab=realized', vw: 390, theme: 'dark', variant: 'c', mode: 'security', ids: [63, 97, 56, 11], onlySection: true },
  { id: 'm3-390', page: 'realized', url: '/cashflow?tab=realized', vw: 390, theme: 'light', variant: 'm3', mode: 'switch', ids: [63, 60, 56], onlySection: true, pins: [['#sale-hindsight .hs-controls', 1, 'pre'], ['#sale-hindsight li[data-sale="56"] .hs-detail-phone', 5, 'pre'], ['#sale-hindsight li[data-sale="60"] .hs-nobuys', 6, 'pre']] }
];

async function capture(browser, f) {
  const page = await browser.newPage({ viewport: { width: f.vw, height: 1000 }, locale: 'de-DE' });
  await page.addInitScript((th) => { try { localStorage.setItem('portfolixir-theme', th); } catch (_) {} }, f.theme);
  page.on('console', (m) => { if (m.type() === 'warning') console.warn('  page:', m.text()); });
  await page.goto(BASE + f.url + (f.url.includes('?') ? '&' : '?') + 'locale=de', { waitUntil: 'networkidle' });
  await page.waitForTimeout(900);
  const width = f.vw > 600 ? f.vw - 220 : f.vw;
  if (f.vw > 600) await page.setViewportSize({ width, height: 1000 });
  const args = Object.assign({}, f, {
    elidedTrades: NEW.elidedTrades('%n'),
    section: f.mode ? sec(f.mode, f.ids, { h3: f.h3, noName: f.h3, infoOpen: f.infoOpen }) : null
  });
  if (f.variant === 'a') { const A = optionA(); A.chooser = chooser('security').replace('hs-controls"', 'hs-controls mock-new"'); args.A = A; }
  if (f.variant === 'b') args.B = { toggle: B_TOGGLE, row: B_ROW, chooser: chooser('security').replace('hs-controls"', 'hs-controls mock-new"') };
  const r = await page.evaluate(transform, args);
  await page.close();
  const file = `${f.id}.html`;
  fs.writeFileSync(path.join(FRAMES, file), tidy(framePage(f.id, r.html, f.theme)));
  const m = await browser.newPage({ viewport: { width, height: 200 } });
  await m.goto('file://' + path.join(FRAMES, file));
  await m.waitForTimeout(300);
  // An open ⓘ panel opens upward, as it ships: give it room above the
  // frame's top bar instead of moving it.
  const tipTop = await m.evaluate(() => { const t = document.querySelector('details[open] p[role="tooltip"]'); return t ? Math.floor(t.getBoundingClientRect().top) : null; });
  if (tipTop !== null && tipTop < 8) {
    fs.writeFileSync(path.join(FRAMES, file), fs.readFileSync(path.join(FRAMES, file), 'utf8').replace('<body>', `<body style="padding-top:${8 - tipTop}px">`));
    await m.reload();
    await m.waitForTimeout(300);
  }
  const probe = await m.evaluate(() => {
    const w = document.querySelector('.hs-table-wrapper') || document.querySelector('#realized-trades-table-wrapper');
    const out = { height: Math.ceil(document.documentElement.scrollHeight) };
    if (w && w.clientWidth) out.scroller = { client: w.clientWidth, scroll: w.scrollWidth };
    const tip = document.querySelector('details[open] p[role="tooltip"]');
    if (tip) out.height = Math.max(out.height, Math.ceil(tip.getBoundingClientRect().bottom + window.scrollY + 16));
    return out;
  });
  await m.close();
  console.log(f.id, width + 'x' + probe.height, probe.scroller ? JSON.stringify(probe.scroller) : '');
  return { file: 'frames/' + file, width, height: probe.height, scroller: probe.scroller || null };
}

module.exports = { NEW, de, SALES, SWITCH };

if (require.main === module) {
  (async () => {
    fs.mkdirSync(FRAMES, { recursive: true });
    const browser = await chromium.launch(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {});
    const sizesFile = path.join(FRAMES, 'sizes.json');
    const only = process.env.ONLY ? new RegExp(process.env.ONLY) : null;
    const sizes = only && fs.existsSync(sizesFile) ? JSON.parse(fs.readFileSync(sizesFile, 'utf8')) : {};
    for (const f of FRAMES_DEF) {
      if (only && !only.test(f.id)) continue;
      sizes[f.id] = await capture(browser, f);
    }
    await browser.close();
    fs.writeFileSync(sizesFile, JSON.stringify(sizes, null, 2) + '\n');
    require('./board.js').main(sizes);
  })().catch((e) => { console.error(e); process.exit(1); });
}
