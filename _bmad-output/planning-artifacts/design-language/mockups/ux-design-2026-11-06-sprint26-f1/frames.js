// The frames of the Sprint 26 planning board 02 (F1, the human view of
// predictions, ADR-0055 §5): where each is captured, at which viewport, and
// the prep that writes the proposal into the live page. build.js runs them.
//
// German: a string that exists comes from the catalogue (de(), build.js);
// every new string is in NEW below and listed in README.md as new.
// Synthetic data only: the securities are the review seed's
// (priv/demo/finding_surfaces_seed.exs), which holds no prediction; every
// prediction, model name, figure and rationale below is invented for the
// board and carries the amber stripe (mock-synth) where it is drawn.
module.exports = function ({ de }) {
  // ---------------------------------------------------------------- strings
  // Existing strings, from the catalogue.
  const S = {
    research: de('Research'),
    dates: de('Dates'),
    agent: de('Agent'),
    operator: de('Operator'),
    benchmark: de('Benchmark'),
    hitRate: de('Hit rate'),
    security: de('Security'),
    thesis: de('Thesis'),
    risk: de('Risk'),
    all: de('All'),
    due: de('Due'),
    prediction: de('Prediction', undefined, {}, 'journal kind'),
    nPredictions: (n) => de('%{count} prediction', n),
    deleteConfirm: de('Delete this security? Bookings, quotes, events, research entries and policy rules block the deletion. Removed with it: its classifications, position targets, bucket assignments and former ISINs, each recorded in the journal, and its logo.'),
    noLongerBenchmark: de('%{name} is no longer a benchmark'),
    unmarkBenchmark: de('Unmark benchmark'),
    noDates: de('No dates recorded for this security.')
  };

  // New strings, German proposals (README.md, "New strings").
  const NEW = {
    tab: 'Prognosen',
    hint: 'Festgehaltene Prognosen zu diesem Wertpapier, die neueste zuerst. Keine wird geändert oder gelöscht.',
    tip: [
      'Eine Prognose bleibt, wie sie abgegeben wurde: Sie wird nie geändert, zurückgezogen oder gelöscht. Eine korrigierte Prognose ist eine neue, und beide zählen.',
      'Ausgewertet wird beim Lesen aus gespeicherten Schlusskursen, beide Seiten in EUR zum gespeicherten Wechselkurs ihres Tages; ein Ergebnis wird nie gespeichert.',
      'Start: der letzte Schlusskurs am oder vor dem Tag der Abgabe. Ende: der letzte am oder vor dem Auflösungstag. Gewertet wird erst, wenn ein Schlusskurs ab dem Auflösungstag vorliegt, längstens 7 Tage danach.',
      'Ein Schlusskurs, der mehr als 7 Tage vor seinem Datum liegt, zählt nicht; dann bleibt die Prognose nicht aufgelöst, mit ihrem Grund, und wird nie geschätzt.',
      'Überrendite = Rendite − Rendite der Benchmark. „Übertrifft“ trifft bei mehr als 0, „bleibt zurück“ bei weniger als 0; genau 0 verfehlt beide. Ein fester Satz wird täglich verzinst; 0 % ist die absolute Aussage (steigt, fällt).',
      'Nur Kursrendite: Ausschüttungen zählen auf keiner Seite.',
      'Festgehalten wird über die API oder MCP.'
    ],
    empty: 'Für dieses Wertpapier ist keine Prognose festgehalten.',
    emptyHow: 'Festgehalten wird über die API oder MCP.',
    claimOut: 'Übertrifft %{benchmark} bis %{date}',
    claimUnder: 'Bleibt bis %{date} hinter %{benchmark} zurück',
    claimRateOut: 'Übertrifft %{rate} p. a. bis %{date}',
    claimRateUnder: 'Bleibt bis %{date} unter %{rate} p. a.',
    claimRise: 'Steigt bis %{date}',
    claimFall: 'Fällt bis %{date}',
    open: (n) => (n === 1 ? 'offen · noch 1 Tag' : `offen · noch ${n} Tage`),
    waiting: 'offen · wartet auf den Schlusskurs',
    waitingShort: 'wartet auf Schlusskurs',
    daysLeft: (n) => (n === 1 ? 'noch 1 Tag' : `noch ${n} Tage`),
    waitingLine: 'Der Auflösungstag ist vorbei; gewertet wird, sobald ein Schlusskurs ab dem %{date} vorliegt, spätestens am %{last}.',
    hit: 'Treffer',
    miss: 'verfehlt',
    unresolved: 'nicht aufgelöst',
    reason: {
      no_start_close: 'kein Startkurs',
      no_end_close: 'kein Endkurs',
      no_benchmark_close: 'kein Benchmark-Kurs',
      no_fx_rate: 'kein Wechselkurs'
    },
    reasonLine: {
      no_benchmark_close: 'Für die Benchmark liegt am oder bis 7 Tage vor dem %{date} kein Schlusskurs vor.',
      no_fx_rate: 'Für den %{date} ist kein Wechselkurs USD → EUR gespeichert.'
    },
    probability: 'Wahrscheinlichkeit',
    resolvesOn: 'Auflösungstag',
    ret: 'Rendite',
    benchRet: 'Benchmark-Rendite',
    excess: 'Überrendite',
    closes: 'Schlusskurse',
    researchLink: 'Research #%{n} · %{kind}',
    // The report
    areaTab: 'Prognosen',
    title: 'Prognosen',
    subtitle: 'Wie gut die festgehaltenen Prognosen getroffen haben · über alle Wertpapiere, unabhängig von der Ansicht',
    author: 'Urheber',
    model: 'Modell',
    calibration: 'Kalibrierung',
    countsMeta: '· %{resolved} aufgelöst · %{open} offen · %{unresolved} nicht aufgelöst',
    brier: 'Brier-Score',
    brierSub: '± Standardfehler · Referenz 0,25 = immer 50 % · niedriger ist besser',
    sharpness: 'Schärfe',
    sharpnessSub: 'Ø Abstand der Wahrscheinlichkeit von 0,50 · 0 = immer 50 %',
    hitSub: '± %{se} Pp Standardfehler · Ø angegeben %{mean}',
    resolved: 'Aufgelöst',
    resolvedSub: '%{open} offen und %{unresolved} nicht aufgelöst zählen in keinem Score',
    reportBasis: 'Grundlage: jede aufgelöste Prognose einmal, Wahrscheinlichkeit und Ergebnis wie im Tab „Prognosen“ des Wertpapiers.',
    reportTip: [
      'Brier-Score: Mittel von (p − o)² über die aufgelösten Prognosen, p die angegebene Wahrscheinlichkeit, o 1 bei Treffer und 0 sonst. Die Referenz 0,25 ist der Score von „immer 50 %“.',
      'Standardfehler: die Standardabweichung der quadrierten Fehler in der Stichprobe, geteilt durch √n; bei der Trefferquote die der Treffer.',
      'Schärfe: Mittel von p − 0,50. Wer immer 50 % sagt, ist perfekt kalibriert und sagt nichts.',
      'Trefferquote: Treffer durch n, neben der mittleren angegebenen Wahrscheinlichkeit, der eine kalibrierte Quote entspricht.',
      'Offene und nicht aufgelöste Prognosen zählen in keinem Score; sie werden gezählt.',
      'Auflösung wie im Tab „Prognosen“ des Wertpapiers; nur Kursrendite.'
    ],
    bandsTitle: 'Nach Wahrscheinlichkeit',
    bandsFew: 'Eine Trefferquote je Band zeigt sich erst ab 20 aufgelösten Prognosen im Band; bisher erreicht keines 20. Bis dahin trägt der Brier-Score mit seinem Standardfehler die Aussage.',
    bandsLine: 'Aufgelöst je Band:',
    band: 'Band',
    meanStated: 'Ø angegeben',
    tooFew: 'zu wenige · %{n} von 20',
    groupsTitle: 'Nach Urheber und Modell',
    allModels: 'alle Modelle',
    listTitle: 'Alle Prognosen',
    made: 'Abgegeben',
    claim: 'Aussage',
    probShort: 'Wahrsch.',
    state: 'Stand',
    statusOpen: 'Offen',
    statusResolved: 'Aufgelöst',
    statusUnresolved: 'Nicht aufgelöst',
    more: '… %{n} weitere Prognosen, für das Board gekürzt',
    // Option B
    riskBlockTitle: 'Prognosen',
    riskBlockLink: 'Die einzelnen Prognosen stehen je Wertpapier im Tab „Prognosen“.',
    // #1365, line 1 and line 2
    deleteConfirmAfter: 'Dieses Wertpapier löschen? Buchungen, Kurse, Termine, Research-Einträge, Prognosen und eigene Regeln blockieren das Löschen. Mit entfernt werden seine Klassifizierungen, Positionsziele, Bucket-Zuordnungen und früheren ISINs, jeweils im Journal festgehalten, und das Logo.',
    unflagAfter: (n) => (n === 1
      ? '1 festgehaltene Prognose misst weiter an ihr; eine neue Prognose kann sie nicht mehr als Benchmark nennen.'
      : `${n} festgehaltene Prognosen messen weiter an ihr; eine neue Prognose kann sie nicht mehr als Benchmark nennen.`)
  };

  // ---------------------------------------------------------------- data
  // 21 synthetic predictions on the seed's securities; "today" is the
  // seed's 06.11.2026. Statuses are what ADR-0055 §3 would derive; the
  // report's figures are computed from the twelve resolved ones below
  // (README.md, "The synthetic figures").
  const TODAY = '2026-11-06';
  const INDEX = 'Kestrel Industrial Group NV Index'; // the seed's one benchmark security
  const P = [
    { id: 1, sid: 6, sec: 'Bitcoin', made: '2026-04-20', a: 'agent', m: 'model-alpha-2', dir: 'under', bm: 'rate:0', p: 0.60, on: '2026-11-30', st: 'open' },
    { id: 2, sid: 49, sec: 'Arbolia Inc.', made: '2026-04-28', a: 'agent', m: 'model-alpha-2', dir: 'out', bm: 'index', p: 0.85, on: '2026-10-28', st: 'hit', r: 9.1, b: 6.6, from: '2026-04-28', to: '2026-10-28' },
    { id: 3, sid: 3, sec: 'Allianz SE vinkulierte Namens-Aktien o.N.', made: '2026-05-04', a: 'operator', dir: 'out', bm: 'rate:0.02', p: 0.60, on: '2026-08-04', st: 'hit', r: 5.1, b: 0.5, from: '2026-05-04', to: '2026-08-04' },
    { id: 4, sid: 4, sec: 'iShares Core MSCI World UCITS ETF USD (Acc)', made: '2026-05-11', a: 'operator', dir: 'out', bm: 'rate:0.02', p: 0.55, on: '2026-08-11', st: 'hit', r: 2.2, b: 0.5, from: '2026-05-11', to: '2026-08-11' },
    { id: 5, sid: 10, sec: 'Helios Solar Systems SE', made: '2026-05-20', a: 'operator', dir: 'under', bm: 'index', p: 0.70, on: '2026-08-20', st: 'hit', r: -4.3, b: 3.1, from: '2026-05-20', to: '2026-08-20' },
    { id: 6, sid: 7, sec: 'NVIDIA Corporation Registered Shares DL-,001', made: '2026-06-02', a: 'agent', m: 'model-alpha-2', dir: 'under', bm: 'index', p: 0.60, on: '2026-09-02', st: 'miss', r: 8.8, b: 2.8, from: '2026-06-02', to: '2026-09-02' },
    { id: 7, sid: 6, sec: 'Bitcoin', made: '2026-06-05', a: 'operator', dir: 'out', bm: 'rate:0', p: 0.60, on: '2026-07-05', st: 'miss', r: -9.8, b: 0, from: '2026-06-05', to: '2026-07-03' },
    { id: 8, sid: 1, sec: 'Apple Inc. Registered Shares o.N.', made: '2026-06-15', a: 'operator', dir: 'out', bm: 'index', p: 0.80, on: '2026-08-31', st: 'unresolved', why: 'no_benchmark_close', whyDate: '2026-06-15' },
    { id: 9, sid: 3, sec: 'Allianz SE vinkulierte Namens-Aktien o.N.', made: '2026-06-22', a: 'agent', m: 'model-alpha-3', dir: 'out', bm: 'index', p: 0.65, on: '2026-09-22', st: 'miss', r: 1.4, b: 3.2, from: '2026-06-22', to: '2026-09-22' },
    { id: 10, sid: 2, sec: 'Microsoft Corporation Registered Shares DL-,00000625', made: '2026-06-30', a: 'agent', m: 'model-alpha-3', dir: 'out', bm: 'index', p: 0.75, on: '2026-09-30', st: 'hit', r: 6.9, b: 3.0, from: '2026-06-30', to: '2026-09-30' },
    { id: 11, sid: 14, sec: 'Meridian Global Equity ETF', made: '2026-07-01', a: 'agent', m: 'model-alpha-3', dir: 'out', bm: 'index', p: 0.65, on: '2026-10-01', st: 'hit', r: 3.9, b: 3.0, from: '2026-07-01', to: '2026-10-01' },
    { id: 12, sid: 1, sec: 'Apple Inc. Registered Shares o.N.', made: '2026-07-09', a: 'agent', m: 'model-alpha-2', dir: 'out', bm: 'index', p: 0.70, on: '2026-10-09', st: 'hit', r: 8.4, b: 3.1, from: '2026-07-09', to: '2026-10-09', note: { n: 1, kind: 'thesis' }, why_: 'Thesis #1: the services mix keeps margins up through the cycle; the index has no services exposure.' },
    { id: 13, sid: 7, sec: 'NVIDIA Corporation Registered Shares DL-,001', made: '2026-07-14', a: 'agent', m: 'model-alpha-3', dir: 'out', bm: 'rate:0', p: 0.80, on: '2026-10-14', st: 'hit', r: 11.2, b: 0, from: '2026-07-14', to: '2026-10-14' },
    { id: 14, sid: 49, sec: 'Arbolia Inc.', made: '2026-07-20', a: 'agent', m: 'model-alpha-3', dir: 'out', bm: 'index', p: 0.60, on: '2026-10-20', st: 'unresolved', why: 'no_fx_rate', whyDate: '2026-10-20' },
    { id: 15, sid: 14, sec: 'Meridian Global Equity ETF', made: '2026-08-03', a: 'operator', dir: 'under', bm: 'index', p: 0.65, on: '2027-01-29', st: 'open' },
    { id: 16, sid: 4, sec: 'iShares Core MSCI World UCITS ETF USD (Acc)', made: '2026-08-17', a: 'agent', m: 'model-alpha-3', dir: 'out', bm: 'index', p: 0.55, on: '2026-12-31', st: 'open' },
    { id: 17, sid: 1, sec: 'Apple Inc. Registered Shares o.N.', made: '2026-09-07', a: 'agent', m: 'model-alpha-3', dir: 'under', bm: 'rate:0', p: 0.55, on: '2026-10-07', st: 'miss', r: 2.2, b: 0, from: '2026-09-07', to: '2026-10-07', note: { n: 3, kind: 'risk' }, why_: 'The regulatory case on the app store fee could compress the services margin before the ruling.' },
    { id: 18, sid: 3, sec: 'Allianz SE vinkulierte Namens-Aktien o.N.', made: '2026-09-21', a: 'agent', m: 'model-alpha-2', dir: 'out', bm: 'rate:0.02', p: 0.75, on: '2027-05-03', st: 'open' },
    { id: 19, sid: 2, sec: 'Microsoft Corporation Registered Shares DL-,00000625', made: '2026-10-12', a: 'operator', dir: 'out', bm: 'rate:0', p: 0.60, on: '2026-12-15', st: 'open' },
    { id: 20, sid: 50, sec: 'Tamarisk Systems Inc.', made: '2026-10-20', a: 'agent', m: 'model-alpha-3', dir: 'out', bm: 'index', p: 0.70, on: '2026-11-05', st: 'waiting' },
    { id: 21, sid: 1, sec: 'Apple Inc. Registered Shares o.N.', made: '2026-11-04', a: 'agent', m: 'model-alpha-3', dir: 'out', bm: 'index', p: 0.65, on: '2027-03-31', st: 'open', note: { n: 1, kind: 'thesis' }, why_: 'Services margin holds above 40 % while the index carries no services exposure; recorded at the end of a position review.' }
  ];
  const KIND = { thesis: S.thesis, risk: S.risk };

  // ---------------------------------------------------------------- format
  const NB = '&nbsp;';
  const dmy = (iso) => iso.split('-').reverse().join('.');
  const days = (from, to) => Math.round((Date.parse(to) - Date.parse(from)) / 86400000);
  const addDays = (iso, n) => new Date(Date.parse(iso) + n * 86400000).toISOString().slice(0, 10);
  const dec = (x, places) => Math.abs(x).toFixed(places).replace('.', ',');
  const signed = (x, places) => (x > 0 ? '+' : x < 0 ? '−' : '') + dec(x, places);
  const pct = (p) => Math.round(p * 100) + NB + '%';
  const fill = (s, b) => s.replace(/%\{(\w+)\}/g, (_, k) => (b[k] !== undefined ? b[k] : '%{' + k + '}'));
  const sign = (x) => (x > 0 ? 'is-positive' : x < 0 ? 'is-negative' : '');
  const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
  const rateOf = (p) => Number(p.bm.split(':')[1]);
  function claim(p) {
    const date = dmy(p.on);
    if (p.bm === 'index') {
      const b = `<bdi>${INDEX}</bdi>`;
      return fill(p.dir === 'out' ? NEW.claimOut : NEW.claimUnder, { benchmark: b, date });
    }
    const r = rateOf(p);
    if (r === 0) return fill(p.dir === 'out' ? NEW.claimRise : NEW.claimFall, { date });
    return fill(p.dir === 'out' ? NEW.claimRateOut : NEW.claimRateUnder, { rate: dec(r * 100, 1) + NB + '%', date });
  }
  const authorWords = (p) => (p.a === 'agent' ? `${S.agent} · ${p.m}` : S.operator);
  const excessOf = (p) => Math.round((p.r - p.b) * 10) / 10;
  function badge(p) {
    if (p.st === 'open') return `<span class="badge badge--neutral" data-role="prediction-status" data-status="open">${NEW.open(days(TODAY, p.on))}</span>`;
    if (p.st === 'waiting') return `<span class="badge badge--neutral" data-role="prediction-status" data-status="open">${NEW.waiting}</span>`;
    if (p.st === 'hit') return `<span class="badge badge--thesis-intact" data-role="prediction-status" data-status="resolved" data-outcome="hit">${NEW.hit}</span>`;
    if (p.st === 'miss') return `<span class="badge badge--retired" data-role="prediction-status" data-status="resolved" data-outcome="miss">${NEW.miss}</span>`;
    return `<span class="badge badge--undetermined" data-role="prediction-status" data-status="unresolved">${NEW.unresolved}</span>`;
  }

  // ------------------------------------------------- the security's tab
  function entry(p) {
    // Resolved: the measurement (both returns, the excess, the closes used).
    // Open and unresolved: the claim line already says all there is.
    const facts = [];
    if (p.st === 'hit' || p.st === 'miss') {
      const x = excessOf(p);
      facts.push([NEW.ret, `<span class="${sign(p.r)}">${signed(p.r, 1)}${NB}%</span>`, true]);
      facts.push([NEW.benchRet, `${signed(p.b, 1)}${NB}%`, true]);
      facts.push([NEW.excess, `<span class="${sign(x)}">${signed(x, 1)}${NB}Pp</span>`, true]);
      facts.push([NEW.closes, `${dmy(p.from)} → ${dmy(p.to)}`, false]);
    }
    const dl = facts.length === 0 ? '' : `<dl class="research-entry__facts prediction-entry__facts">${facts.map(([k, v, num]) => `<div><dt>${k}</dt><dd${num ? ' class="num"' : ''}>${v}</dd></div>`).join('')}</dl>`;
    const line = p.st === 'waiting'
      ? `<p class="prediction-entry__reason">${fill(NEW.waitingLine, { date: dmy(p.on), last: dmy(addDays(p.on, 7)) })}</p>`
      : p.st === 'unresolved'
        ? `<p class="prediction-entry__reason"><b>${NEW.reason[p.why]}:</b> ${fill(NEW.reasonLine[p.why], { date: dmy(p.whyDate) })}</p>`
        : '';
    const body = p.why_ ? `<p class="research-entry__body">${esc(p.why_)}</p>` : '';
    const link = p.note ? `<p class="research-entry__meta"><a href="#research-entry-${p.note.n}">${fill(NEW.researchLink, { n: p.note.n, kind: KIND[p.note.kind] })}</a></p>` : '';
    return `<li id="prediction-${p.id}" class="research-entry prediction-entry prediction-entry--${p.st} mock-synth" data-role="prediction-entry">` +
      `<div class="research-entry__head">${badge(p)}<span class="research-entry__meta">#${p.id} · ${dmy(p.made)} · ${authorWords(p)}</span></div>` +
      `<p class="prediction-entry__claim"><strong>${claim(p)}</strong><span class="prediction-entry__p"><span class="prediction-entry__p-label">${NEW.probability}</span> ${pct(p.p)}</span></p>` +
      line + dl + body + link + '</li>';
  }
  const tipHtml = (lines) => `<details class="metric-tooltip metric-tooltip--inline metric-tooltip--section" data-role="section-info"><summary aria-label="Zu diesem Abschnitt">ⓘ</summary><p role="tooltip">${lines.join('<br>')}</p></details>`;
  function tabPanel(sid) {
    const list = P.filter((p) => p.sid === sid).sort((x, y) => y.id - x.id);
    const hint = `<div class="detail-tab-hint" data-role="predictions-basis">${NEW.hint} ${tipHtml(NEW.tip)}</div>`;
    const body = list.length
      ? `<ol class="research-timeline prediction-timeline" data-role="prediction-timeline">${list.map(entry).join('')}</ol>`
      : `<p class="empty-state">${NEW.empty} ${NEW.emptyHow}</p>`;
    return `<section id="detail-tab-panel-predictions" role="tabpanel" aria-labelledby="detail-tab-predictions" class="detail-tab-panel detail-tab-panel--predictions mock-new">${hint}${body}</section>`;
  }

  // Runs in the page: the tenth tab after Research, the panel in place of
  // the events panel the URL opened.
  function securityTab(a) {
    const tabs = document.querySelector('#detail-pane-tabs');
    tabs.querySelectorAll('.detail-pane-tab').forEach((t) => { t.classList.remove('is-active'); t.setAttribute('aria-selected', 'false'); t.setAttribute('tabindex', '-1'); t.removeAttribute('aria-controls'); });
    const btn = M.el(`<button type="button" id="detail-tab-predictions" role="tab" tabindex="0" aria-selected="true" aria-controls="detail-tab-panel-predictions" class="detail-pane-tab is-active mock-new">${a.label}</button>`);
    document.querySelector('#detail-tab-research').after(btn);
    // The row rests where the hook would scroll it: the selected tab in view.
    // A static frame keeps no scroll position, so the first tab's margin
    // stands in for it, and the row loses its "rests at the start" mark.
    tabs.scrollLeft = 0;
    const r = btn.getBoundingClientRect(); const rr = tabs.getBoundingClientRect();
    if (r.right > rr.right - 8) {
      const shift = Math.ceil(r.right - rr.right + 40);
      tabs.querySelector('.detail-pane-tab').style.marginLeft = -shift + 'px';
      tabs.removeAttribute('data-scroll-start');
    }
    document.querySelector('#detail-tab-panel-events').replaceWith(M.el(a.panel));
    if (a.pins) {
      M.pin(btn, 1, 'pre');
      M.pin('[data-role="predictions-basis"]', 2, 'pre');
      const first = document.querySelector('[data-role="prediction-entry"]');
      if (first) {
        M.pin(first.querySelector('[data-role="prediction-status"]'), 3, 'pre');
        M.pin(first.querySelector('.prediction-entry__claim strong'), 4, 'pre');
        const resolved = document.querySelector('.prediction-entry--hit');
        if (resolved) M.pin(resolved.querySelector('.prediction-entry__facts dd'), 5, 'pre');
        const unres = document.querySelector('.prediction-entry--unresolved .prediction-entry__reason');
        if (unres) M.pin(unres, 6, 'pre');
        const link = document.querySelector('.prediction-entry .research-entry__meta a');
        if (link) M.pin(link, 7, 'after');
      }
    }
    if (a.openTip) {
      // Opened below its ⓘ and kept 16 px inside the frame (the #1336 hook's
      // placement), set after the hook's own toggle handler has run.
      const d = document.querySelector('[data-role="predictions-basis"] details');
      d.open = true;
      return new Promise((done) => setTimeout(() => {
        d.dataset.place = 'below';
        d.style.setProperty('--tip-shift', '0px');
        const left = document.querySelector('#security-detail-pane').getBoundingClientRect().left - 12;
        const r = d.querySelector('p').getBoundingClientRect();
        let shift = 0;
        if (r.right - left > a.frame - 16) shift = (a.frame - 16) - (r.right - left);
        if (r.left - left + shift < 16) shift = 16 - (r.left - left);
        d.style.setProperty('--tip-shift', Math.round(shift) + 'px');
        done();
      }, 300));
    }
    return null;
  }

  // ------------------------------------------------- the report
  const resolvedP = P.filter((p) => p.st === 'hit' || p.st === 'miss');
  function stats(rows) {
    const n = rows.length;
    const e = rows.map((p) => (p.p - (p.st === 'hit' ? 1 : 0)) ** 2);
    const se = e.reduce((s, x) => s + x, 0); const se2 = e.reduce((s, x) => s + x * x, 0);
    const h = rows.filter((p) => p.st === 'hit').length;
    return {
      n,
      brier: se / n,
      brierSe: n > 1 ? Math.sqrt((n * se2 - se * se) / (n * n * (n - 1))) : null,
      sharp: rows.reduce((s, p) => s + p.p - 0.5, 0) / n,
      hit: h / n,
      hitSe: n > 1 ? Math.sqrt((h * (n - h)) / (n * n * (n - 1))) : null,
      mean: rows.reduce((s, p) => s + p.p, 0) / n
    };
  }
  const ALL = stats(resolvedP);
  const counts = { resolved: resolvedP.length, open: P.filter((p) => p.st === 'open' || p.st === 'waiting').length, unresolved: P.filter((p) => p.st === 'unresolved').length };
  const f3 = (x) => dec(x, 3);
  const f2 = (x) => dec(x, 2);
  const p1 = (x) => dec(x * 100, 1);

  function kpis() {
    return `<div class="kpi-band__support prediction-kpis mock-synth-cards">` +
      `<article class="stat stat--compact mock-synth" data-role="prediction-brier"><span>${NEW.brier}</span><strong>${f3(ALL.brier)}<small class="value-suffix"> ± ${f3(ALL.brierSe)}</small></strong><small class="stat__sub">${fill(NEW.brierSub, { se: f3(ALL.brierSe) })}</small></article>` +
      `<article class="stat stat--compact mock-synth" data-role="prediction-sharpness"><span>${NEW.sharpness}</span><strong>${f2(ALL.sharp)}</strong><small class="stat__sub">${NEW.sharpnessSub}</small></article>` +
      `<article class="stat stat--compact mock-synth" data-role="prediction-hit-rate"><span>${S.hitRate}</span><strong>${p1(ALL.hit)}<small class="value-suffix">%</small></strong><small class="stat__sub">${fill(NEW.hitSub, { se: p1(ALL.hitSe), mean: p1(ALL.mean) + NB + '%' })}</small></article>` +
      `<article class="stat stat--compact mock-synth" data-role="prediction-counts"><span>${NEW.resolved}</span><strong>${counts.resolved}</strong><small class="stat__sub">${fill(NEW.resolvedSub, counts)}</small></article>` +
      `</div>`;
  }
  const BANDS = [[0.5, '0,50–0,59'], [0.6, '0,60–0,69'], [0.7, '0,70–0,79'], [0.8, '0,80–0,89'], [0.9, '0,90–0,99']];
  const bandRows = BANDS.map(([lo, label]) => { const r = resolvedP.filter((p) => p.p >= lo && p.p < lo + 0.1 - 1e-9); return { label, n: r.length, mean: r.length ? r.reduce((s, p) => s + p.p, 0) / r.length : null }; });
  function bandsFew() {
    return `<div class="prediction-bands" data-role="prediction-bands" data-state="too_few">` +
      `<div class="section-title"><h3>${NEW.bandsTitle}</h3></div>` +
      `<p class="prediction-bands__why">${NEW.bandsFew}</p>` +
      `<p class="summary-basis prediction-bands__counts mock-synth">${NEW.bandsLine} ${bandRows.map((b) => `${b.label}: <span class="num">${b.n}</span>`).join(' · ')}</p></div>`;
  }
  // The later state (a year on, invented): two bands past 20.
  const LATER = [
    { label: '0,50–0,59', n: 14, mean: 0.55 },
    { label: '0,60–0,69', n: 31, mean: 0.64, hit: 0.613 },
    { label: '0,70–0,79', n: 24, mean: 0.74, hit: 0.667 },
    { label: '0,80–0,89', n: 13, mean: 0.83 },
    { label: '0,90–0,99', n: 4, mean: 0.93 }
  ];
  function bandsTable() {
    return `<div class="prediction-bands" data-role="prediction-bands">` +
      `<div class="section-title"><h3>${NEW.bandsTitle}</h3></div>` +
      `<div class="data-table-wrapper"><table class="data-table prediction-bands-table"><thead><tr><th>${NEW.band}</th><th class="num">${NEW.resolved}</th><th class="num">${NEW.meanStated}</th><th class="num">${S.hitRate}</th></tr></thead><tbody>` +
      LATER.map((b) => `<tr class="mock-synth"><td>${b.label}</td><td class="num">${b.n}</td><td class="num">${p1(b.mean)}${NB}%</td><td class="num">${b.hit !== undefined ? p1(b.hit) + NB + '%' : `<span class="prediction-too-few">${fill(NEW.tooFew, { n: b.n })}</span>`}</td></tr>`).join('') +
      `</tbody></table></div></div>`;
  }
  function groups() {
    const rows = [
      [S.operator, '—', resolvedP.filter((p) => p.a === 'operator')],
      [S.agent, NEW.allModels, resolvedP.filter((p) => p.a === 'agent')],
      [S.agent, 'model-alpha-2', resolvedP.filter((p) => p.m === 'model-alpha-2')],
      [S.agent, 'model-alpha-3', resolvedP.filter((p) => p.m === 'model-alpha-3')]
    ];
    return `<div class="prediction-groups" data-role="prediction-groups"><div class="section-title"><h3>${NEW.groupsTitle}</h3></div>` +
      `<div class="data-table-wrapper" id="prediction-groups-table-wrap"><table class="data-table prediction-groups-table"><thead><tr><th>${NEW.author}</th><th>${NEW.model}</th><th class="num">${NEW.resolved}</th><th class="num">${NEW.brier}</th><th class="num">${NEW.sharpness}</th><th class="num">${S.hitRate}</th><th class="num">${NEW.meanStated}</th></tr></thead><tbody>` +
      rows.map(([a, m, r]) => { const s = stats(r); return `<tr class="mock-synth${m.startsWith('model') ? ' prediction-groups__model' : ''}"><td>${a}</td><td>${m}</td><td class="num">${s.n}</td><td class="num">${f3(s.brier)} ± ${f3(s.brierSe)}</td><td class="num">${f2(s.sharp)}</td><td class="num">${p1(s.hit)}${NB}% ± ${p1(s.hitSe)}</td><td class="num">${p1(s.mean)}${NB}%</td></tr>`; }).join('') +
      `</tbody></table></div>` +
      `<ul class="phone-rows" id="prediction-groups-phone-rows">` +
      rows.map(([a, m, r]) => { const s = stats(r); return `<li class="phone-row mock-synth"><span class="phone-row__body"><span class="phone-row__name">${m === '—' ? a : `${a} · ${m}`}</span><span class="phone-row__ids">${s.n} ${NEW.resolved.toLowerCase()} · ${NEW.sharpness} ${f2(s.sharp)} · ${NEW.meanStated} ${p1(s.mean)}${NB}%</span></span><span class="phone-row__figures"><span class="phone-row__figure">${f3(s.brier)} ± ${f3(s.brierSe)}</span><span class="phone-row__figure2">${S.hitRate} ${p1(s.hit)}${NB}% ± ${p1(s.hitSe)}</span></span></li>`; }).join('') +
      `</ul></div>`;
  }
  function statusCell(p) {
    const b = badge(p);
    if (p.st === 'unresolved') return `${b}<span class="policy-rule__reason">${NEW.reason[p.why]}</span>`;
    return b;
  }
  function listRows(n) {
    const list = [...P].sort((x, y) => y.id - x.id);
    const shown = list.slice(0, n);
    const row = (p) => {
      const x = (p.st === 'hit' || p.st === 'miss') ? excessOf(p) : null;
      return `<tr class="mock-synth" data-role="prediction-row"><td>${dmy(p.made)}<span class="policy-rule__words">${authorWords(p)}</span></td><td class="cell-name"><a href="/securities/${p.sid}?tab=predictions">${p.sec}</a><span class="policy-rule__words">${claim(p)}</span></td><td class="num">${pct(p.p)}</td><td>${statusCell(p)}</td><td class="num">${x === null ? '—' : `<span class="${sign(x)}">${signed(x, 1)}${NB}Pp</span>`}</td></tr>`;
    };
    // Under 560 px the rows (UX-DR27): the figure is the excess once
    // resolved, else the days left; its second line names the status.
    const phone = (p) => {
      const x = (p.st === 'hit' || p.st === 'miss') ? excessOf(p) : null;
      const fig = x !== null ? `<span class="${sign(x)}">${signed(x, 1)}${NB}Pp</span>`
        : p.st === 'open' ? NEW.daysLeft(days(TODAY, p.on)) : '—';
      const fig2 = p.st === 'hit' ? NEW.hit : p.st === 'miss' ? NEW.miss : p.st === 'unresolved' ? NEW.reason[p.why] : p.st === 'waiting' ? NEW.waitingShort : NEW.statusOpen.toLowerCase();
      return `<li class="phone-row mock-synth" data-role="phone-row"><span class="phone-row__body"><span class="phone-row__name">${p.sec}</span><span class="phone-row__ids"><span>${claim(p)} · ${pct(p.p)}</span></span><span class="phone-row__ids">${dmy(p.made)} · ${authorWords(p)}</span></span><span class="phone-row__figures"><span class="phone-row__figure">${fig}</span><span class="phone-row__figure2">${fig2}</span></span></li>`;
    };
    const more = list.length - n;
    const chips = [[S.all, P.length, true], [NEW.statusOpen, counts.open], [S.due, 1], [NEW.statusResolved, counts.resolved], [NEW.statusUnresolved, counts.unresolved]];
    return `<section class="workspace-section prediction-list" id="prediction-list" aria-labelledby="prediction-list-title">` +
      `<header class="section-head"><div class="section-title"><h2 id="prediction-list-title">${NEW.listTitle}</h2></div></header>` +
      `<div class="filter-chips" role="group">${chips.map(([l, c, on]) => `<button type="button" class="filter-chip${on ? ' is-active' : ''}" aria-pressed="${on ? 'true' : 'false'}">${l}<span class="filter-chip__count">${c}</span></button>`).join('')}</div>` +
      `<div class="data-table-wrapper" id="prediction-list-table-wrap"><table class="data-table prediction-list-table" id="prediction-list-table"><thead><tr><th>${NEW.made} · ${NEW.author}</th><th class="cell-name">${S.security} · ${NEW.claim}</th><th class="num">${NEW.probShort}</th><th>${NEW.state}</th><th class="num">${NEW.excess}</th></tr></thead><tbody>` +
      shown.map(row).join('') + `<tr class="mock-elided"><td colspan="5">${fill(NEW.more, { n: more })}</td></tr></tbody></table></div>` +
      `<ul class="phone-rows" id="prediction-list-phone-rows">${shown.slice(0, 5).map(phone).join('')}<li class="mock-elided">${fill(NEW.more, { n: list.length - 5 })}</li></ul>` +
      `</section>`;
  }
  function filterBar() {
    return `<div class="filter-chips prediction-filters" role="group" aria-label="${NEW.author}, ${NEW.model}">` +
      `<span class="filter-chips__family">${NEW.author}</span>` +
      `<button type="button" class="filter-chip is-active" aria-pressed="true">${S.all}</button><button type="button" class="filter-chip" aria-pressed="false">${S.operator}</button><button type="button" class="filter-chip" aria-pressed="false">${S.agent}</button>` +
      `<span class="filter-chips__family">${NEW.model}</span>` +
      `<button type="button" class="filter-chip" aria-pressed="false">model-alpha-2</button><button type="button" class="filter-chip" aria-pressed="false">model-alpha-3</button></div>`;
  }
  // The later state: only the bands block, with the counts it would have.
  function laterSection() {
    const n = LATER.reduce((t, b) => t + b.n, 0);
    return `<section class="workspace-section prediction-calibration" aria-label="${NEW.calibration}">` +
      `<header class="section-head"><div class="section-title"><h2>${NEW.calibration} <span class="section-head__meta">${fill(NEW.countsMeta, { resolved: n, open: 9, unresolved: 5 })}</span></h2>${tipHtml(NEW.reportTip)}</div></header>` +
      `<p class="mock-elided">Kennzahlen wie oben, mit den Zahlen dieses späteren Stands — für das Board gekürzt</p>` + bandsTable() + `</section>`;
  }
  function calibrationSection(later) {
    return `<section class="workspace-section kpi-band prediction-calibration" id="prediction-calibration" aria-labelledby="prediction-calibration-title">` +
      `<header class="section-head"><div class="section-title"><h2 id="prediction-calibration-title">${NEW.calibration} <span class="section-head__meta">${fill(NEW.countsMeta, counts)}</span></h2>${tipHtml(NEW.reportTip)}</div></header>` +
      kpis() + `<p class="summary-basis">${NEW.reportBasis}</p>` + (later ? bandsTable() : bandsFew()) + (later ? '' : groups()) + `</section>`;
  }
  // Runs in the page (option A): Wealth's seventh tab, the page's sections
  // replaced by the report and the list.
  function reportA(a) {
    document.querySelector('#app-topbar-title').textContent = a.title;
    document.querySelector('#app-topbar-subtitle').textContent = a.subtitle;
    const tabs = document.querySelector('#area-tabs');
    tabs.querySelectorAll('.area-tab').forEach((t) => { t.classList.remove('is-active'); t.removeAttribute('aria-current'); });
    const tab = M.el(`<a href="/predictions" class="area-tab is-active mock-new" aria-current="page"><span class="area-tab__icon" aria-hidden="true"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"></circle><circle cx="12" cy="12" r="4.5"></circle><circle cx="12" cy="12" r="0.6"></circle></svg></span><span class="area-tab__label" data-label="${a.tab}">${a.tab}</span></a>`);
    tabs.appendChild(tab);
    // As on the security's tabs: a static frame keeps no scroll position.
    tabs.scrollLeft = 0;
    const r = tab.getBoundingClientRect(); const rr = tabs.getBoundingClientRect();
    if (r.right > rr.right - 8) {
      tabs.querySelector('.area-tab').style.marginLeft = -Math.ceil(r.right - rr.right + 40) + 'px';
      tabs.removeAttribute('data-scroll-start');
    }
    const page = document.querySelector('.workspace-page');
    [...page.children].forEach((c) => { if (c !== tabs) c.remove(); });
    const wrap = M.el(`<div class="mock-new mock-report">${a.html}</div>`);
    page.appendChild(wrap);
    if (a.pins) {
      M.pin(tab, 1, 'pre');
      M.pin('.prediction-filters', 2, 'pre');
      M.pin('[data-role="prediction-brier"] > span', 3, 'pre');
      M.pin('[data-role="prediction-sharpness"] > span', 4, 'pre');
      M.pin('[data-role="prediction-bands"] h3', 5, 'pre');
      M.pin('[data-role="prediction-groups"] h3', 6, 'pre');
      M.pin('#prediction-list-title', 7, 'pre');
    }
    if (a.pinLater) M.pin('[data-role="prediction-bands"] h3', 5, 'pre');
  }
  // Runs in the page (option B): a block on Risk after the policy rules.
  function reportB(a) {
    const rules = document.querySelector('#policy-rules');
    rules.querySelectorAll('#policy-findings tbody tr').forEach((tr, i) => { if (i >= 3) tr.remove(); });
    const tb = rules.querySelector('#policy-findings tbody');
    tb.appendChild(M.el('<table><tbody><tr class="mock-elided"><td colspan="4">… 4 weitere Regeln, für das Board gekürzt</td></tr></tbody></table>').querySelector('tr'));
    rules.querySelectorAll('details:not([data-role="section-info"])').forEach((d) => d.remove());
    rules.after(M.el(a.html));
    // what follows the block: the metrics' head only, the rest cut
    const metrics = document.querySelector('#risk-metrics');
    [...document.querySelectorAll('.workspace-page > section')].forEach((s) => { if (s !== rules && s !== metrics && !s.classList.contains('mock-new')) s.remove(); });
    metrics.querySelectorAll('.kpi-band__support, .summary-basis').forEach((e) => e.remove());
    metrics.appendChild(M.el('<p class="mock-elided">Kennzahlen, Größte Einzelpositionen, Klumpenrisiko, Anlageklassen-Obergrenzen — unverändert, für das Board gekürzt</p>'));
    if (a.pins) {
      M.pin('#prediction-risk-block h2', 1, 'pre');
      M.pin('[data-role="prediction-bands"] h3', 5, 'pre');
      M.pin('.prediction-risk-block__link', 7, 'pre');
    }
  }
  function riskBlock() {
    return `<section class="workspace-section kpi-band prediction-calibration mock-new" id="prediction-risk-block" aria-labelledby="prediction-risk-title">` +
      `<header class="section-head"><div class="section-title"><h2 id="prediction-risk-title">${NEW.riskBlockTitle} <span class="section-head__meta">${fill(NEW.countsMeta, counts)}</span></h2>${tipHtml(NEW.reportTip)}</div></header>` +
      kpis() + bandsFew() + groups() + `<p class="summary-basis prediction-risk-block__link">${NEW.riskBlockLink}</p></section>`;
  }

  // ------------------------------------------------- #1365's two lines
  // Runs in the page: the list cut to the rows around the security the
  // action is on (Apple for the delete, the seed's benchmark for the flag).
  function cutList(a) {
    const rows = [...document.querySelectorAll('#securities-table tbody > tr')];
    const at = rows.findIndex((r) => r.id === 'security-row-' + a.sid);
    rows.forEach((r, i) => { if (i < at - 1 || i > at + 1) r.remove(); });
    document.querySelectorAll('#securities-filter-chips, .securities-toolbar, #security-detail-pane, .split-handle').forEach((e) => e.remove());
  }
  function deleteConfirm(a) {
    const box = M.el(`<div class="native-confirm${a.after ? ' mock-new' : ''}"><p class="origin">Diese Seite meldet</p><p>${a.text}</p><div class="btns"><span>Abbrechen</span><span class="ok">OK</span></div></div>`);
    const list = document.querySelector('#securities-table');
    (list.closest('.securities-workspace') || list).before(box);
    if (a.after) M.pin(box.querySelectorAll('p')[1], 1, 'pre');
  }
  function unflagResult(a) {
    const status = document.querySelector('#securities-action-result-status');
    const note = M.el(`<div class="data-note data-note--note${a.after ? ' mock-new' : ''}"><span class="data-note__icon" aria-hidden="true">${M.icons.note}</span><span class="data-note__word">${M.words.note}</span><div class="data-note__body">${a.text}<button type="button" class="inline-result__dismiss" aria-label="Schließen" title="Schließen">×</button></div></div>`);
    status.appendChild(note);
    if (a.after) M.pin(note.querySelector('.mock-added'), 2, 'pre');
  }

  // ---------------------------------------------------------------- frames
  const SEC = (id) => '/securities/' + id + '?tab=events';
  const waitPane = async (page) => { await page.waitForSelector('#detail-tab-panel-events', { state: 'attached', timeout: 30000 }); };
  const DARK = { suffix: '-dark', theme: 'dark' };
  const reportHtml = filterBar() + calibrationSection(false) + listRows(8);
  const A = { title: NEW.title, subtitle: NEW.subtitle, tab: NEW.areaTab };
  const idx = P.filter((p) => p.bm === 'index').length;
  const FRAMES = [
    // ① the security's tab: Apple (four predictions), Harborline (none)
    { id: 'tab', url: SEC(1), act: waitPane, keep: ['#security-detail-pane'], widths: [1200, 390], frameWidths: { 1200: 980 }, proposal: true, prep: { fn: securityTab, args: { label: NEW.tab, panel: tabPanel(1), pins: true } }, looks: [{ suffix: '' }, DARK] },
    { id: 'tab-tip', url: SEC(1), act: waitPane, keep: ['#security-detail-pane'], widths: [1200], frameWidths: { 1200: 980 }, proposal: true, prep: { fn: securityTab, args: { label: NEW.tab, panel: tabPanel(1), openTip: true, frame: 980 } } },
    { id: 'tab-empty', url: SEC(36), act: waitPane, keep: ['#security-detail-pane'], widths: [1200, 390], frameWidths: { 1200: 980 }, proposal: true, prep: { fn: securityTab, args: { label: NEW.tab, panel: tabPanel(36) } } },
    // ② the report: A on its own Wealth tab, B on Risk
    { id: 'report-a', url: '/risk', keep: ['header.topbar', '.workspace-page'], widths: [1200, 390], frameWidths: { 1200: 980 }, proposal: true, prep: { fn: reportA, args: Object.assign({ html: reportHtml, pins: true }, A) }, looks: [{ suffix: '' }, Object.assign({ widths: [1200] }, DARK)] },
    { id: 'report-a-later', url: '/risk', keep: ['.mock-report'], widths: [1200], frameWidths: { 1200: 980 }, proposal: true, prep: { fn: reportA, args: Object.assign({ html: laterSection(), pinLater: true }, A) } },
    { id: 'report-b', url: '/risk', keep: ['header.topbar', '.workspace-page'], widths: [1200], frameWidths: { 1200: 980 }, proposal: true, prep: { fn: reportB, args: { html: riskBlock(), pins: true } } },
    // ③ #1365's two lines, before and after
    { id: 'delete-before', url: '/securities', keep: ['.app-main'], widths: [1200], frameWidths: { 1200: 980 }, prep: [{ fn: cutList, args: { sid: 1 } }, { fn: deleteConfirm, args: { text: S.deleteConfirm } }] },
    { id: 'delete-after', url: '/securities', keep: ['.app-main'], widths: [1200], frameWidths: { 1200: 980 }, proposal: true, prep: [{ fn: cutList, args: { sid: 1 } }, { fn: deleteConfirm, args: { text: NEW.deleteConfirmAfter, after: true } }] },
    { id: 'unflag-before', url: '/securities', keep: ['.app-main'], widths: [1200], frameWidths: { 1200: 980 }, prep: [{ fn: cutList, args: { sid: 29 } }, { fn: unflagResult, args: { text: S.noLongerBenchmark.replace('%{name}', `<bdi>${INDEX}</bdi>`) } }] },
    { id: 'unflag-after', url: '/securities', keep: ['.app-main'], widths: [1200], frameWidths: { 1200: 980 }, proposal: true, prep: [{ fn: cutList, args: { sid: 29 } }, { fn: unflagResult, args: { text: S.noLongerBenchmark.replace('%{name}', `<bdi>${INDEX}</bdi>`) + `.<span class="mock-added"> ${NEW.unflagAfter(idx)}</span>`, after: true } }] }
  ];

  return { FRAMES, S, NEW, P, ALL, counts, bandRows, idx, INDEX };
};
