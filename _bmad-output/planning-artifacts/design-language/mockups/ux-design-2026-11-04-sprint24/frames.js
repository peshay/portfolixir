// The frames of the Sprint 24 boards: where each is captured and the prep
// that applies the proposal (or a synthetic figure) to the live markup.
// build.js runs them.
//
// German: every existing string comes from the live page; the strings
// written out below are the NEW ones (README.md lists each with its
// English msgid draft). Synthetic data only.
module.exports = function () {
  // ---------------------------------------------------------------- texts
  const NEW = {
    // 01, the journal's time filter (I16)
    since: 'Seit',
    sinceValue: '2026-10-28',
    basisA: 'Neueste zuerst · seit 28.10.2026 (UTC) · die neuesten 100 Einträge · ohne Was-wäre-wenn-Szenarien · Zeiten in UTC',
    family: 'Zeitraum',
    chips: ['Alle', 'Heute', '7 Tage', '30 Tage'],
    // 02, the costs beside the benchmark gap (I17)
    costs: 'Im Zeitraum gezahlt: Gebühren <span class="benchmark-costs__fig">84,20 EUR</span> · Steuern <span class="benchmark-costs__fig">312,55 EUR</span> — die Benchmark zahlt keine.',
    costsInfo: 'Gezahlt im Zeitraum: die Gebühren und Steuern, die dieses Portfolio (diese Ansicht) im selben Zeitraum gebucht hat, umgerechnet zum Kurs ihres Buchungstags; Erstattungen mindern die Steuern. Nicht enthalten ist der Ertrag, den das gezahlte Geld sonst erwirtschaftet hätte.',
    splitB: 'davon Gebühren und Steuern −396,75 · Rest +3.830,15 (Auswahl und Timing)'
  };

  // ------------------------------------------------------------- the preps
  // Every list is cut to its first rows; the board says so.
  function cutRows(a) {
    for (const sel of ['table.journal-table > tbody > tr', '#journal-panel .phone-rows > li']) M.cut(sel, a.keep, '… %n weitere Einträge, für das Board gekürzt');
  }
  function sinceA(a) {
    const kind = document.querySelector('#journal-filters .journal-filters__kind');
    const label = M.el('<label class="journal-filters__since mock-new">' + a.since + ' <input type="date" name="since" value="' + a.value + '"></label>');
    kind.after(label);
    M.pin(label, 1, 'abs');
    const basis = document.querySelector('[data-role="journal-basis"]');
    basis.textContent = a.basis;
    M.neu(basis);
    M.pin(basis, 2, 'pre');
  }
  function sinceB(a) {
    const chips = document.querySelector('#journal-chips');
    const fam = M.el('<span class="mock-new"><span class="filter-chips__family">' + a.family + '</span>' + a.chips.map((c, i) => '<button type="button" class="filter-chip' + (i === 2 ? ' is-active' : '') + '" aria-pressed="' + (i === 2) + '">' + c + '</button>').join('') + '</span>');
    chips.appendChild(fam);
    M.pin(fam, 1, 'pre');
    const basis = document.querySelector('[data-role="journal-basis"]');
    basis.textContent = a.basis;
    M.neu(basis);
  }
  function costsA(a) {
    const rows = document.querySelector('#kpi-benchmark .benchmark-rows');
    const p = M.el('<p class="benchmark-costs mock-new mock-synth" data-role="benchmark-costs">' + a.costs + '</p>');
    rows.after(p);
    M.pin(p, 1, 'pre');
    const tip = document.querySelector('#tip-benchmark');
    tip.appendChild(M.el('<span class="mock-new" style="display:block;margin-top:6px">' + a.info + '</span>'));
    if (a.open) document.querySelector('#kpi-benchmark details.metric-tooltip').setAttribute('open', '');
  }
  function costsB(a) {
    const delta = document.querySelector('#kpi-benchmark [data-role="benchmark-delta"]');
    const s = M.el('<span class="benchmark-row__split mock-new mock-synth">' + a.split + '</span>');
    delta.after(s);
    M.pin(s, 'B', 'pre');
  }

  const J = '/journal';
  const BM = '/portfolio?benchmark_rate=5';
  const jKeep = ['header.topbar', 'main .workspace-page'];
  const FRAMES = [
    // Board 01
    { id: '01-today', url: J, keep: jKeep, prep: { fn: cutRows, args: { keep: 5 } } },
    { id: '01-a', url: J, keep: jKeep, proposal: true, prep: [{ fn: cutRows, args: { keep: 5 } }, { fn: sinceA, args: { since: NEW.since, value: NEW.sinceValue, basis: NEW.basisA } }] },
    { id: '01-b', url: J, keep: jKeep, proposal: true, prep: [{ fn: cutRows, args: { keep: 5 } }, { fn: sinceB, args: { family: NEW.family, chips: NEW.chips, basis: NEW.basisA } }] },
    // Board 02
    { id: '02-today', url: BM, keep: ['#kpi-benchmark'] },
    { id: '02-a', url: BM, keep: ['#kpi-benchmark'], proposal: true, prep: { fn: costsA, args: { costs: NEW.costs, info: NEW.costsInfo, open: false } } },
    { id: '02-a-info', url: BM, keep: ['#kpi-benchmark'], proposal: true, widths: [390], padTop: 230, prep: { fn: costsA, args: { costs: NEW.costs, info: NEW.costsInfo, open: true } } },
    { id: '02-b', url: BM, keep: ['#kpi-benchmark'], proposal: true, prep: { fn: costsB, args: { split: NEW.splitB } } }
  ];

  return { FRAMES, NEW };
};
