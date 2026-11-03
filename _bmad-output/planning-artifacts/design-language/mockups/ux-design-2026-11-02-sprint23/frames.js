// The frames of the three boards: where each is captured, the read-only
// steps that put the page into its state, and the prep that applies the
// proposal (or a synthetic row) to the live markup. build.js runs them.
//
// German: every existing string comes from the catalogue through de();
// the strings written out below are the NEW ones (README.md lists each
// with its English msgid draft). Synthetic data only.
module.exports = function ({ de, trigger }) {
  // ---------------------------------------------------------------- texts
  const NEW = {
    // 01 ①a, the Overview's data-quality line (one each; ngettext in the story)
    dqCash: 'eine Buchung, deren Betrag nicht zu Menge × Preis, Gebühren und Steuern passt',
    dqCashEffect: '— Kontostand und Einstand lesen daher verschiedene Beträge',
    dqRate: 'ein Kauf oder Verkauf in Fremdwährung mit Wechselkurs, aber ohne Betrag',
    dqRateEffect: '— er bucht Menge × Preis ohne Umrechnung aufs Konto',
    dqSplit: 'ein Split, dem ein Portfolio fehlt, das das Wertpapier hielt',
    dqSplitEffect: '— dort sind die Lots geteilt, der Bestand nicht',
    // 01 ①a, the filtered history's note
    histAll: 'Alle Buchungen zeigen',
    histCash: 'Gefiltert: 1 Kauf oder Verkauf, dessen Betrag nicht zu Menge × Preis, Gebühren und Steuern passt — Kontostand und Einstand lesen daher verschiedene Beträge. Den Betrag im Buchungsformular angeben (Bearbeiten): den abgerechneten, oder den, den die Zahlen ergeben. Nichts wird automatisch geändert.',
    histCashCell: 'aus den Zahlen: 816,00',
    histRate: 'Gefiltert: 1 Kauf oder Verkauf in Fremdwährung mit Wechselkurs, aber ohne Betrag — das Hauptbuch bucht Menge × Preis mit Gebühren und Steuern in der Währung des Wertpapiers als Bargeld des Kontos und wendet den Kurs nie an. Den Abrechnungsbetrag im Buchungsformular eintragen (Bearbeiten): den Betrag vor Gebühren und Steuern, aus dem das Formular das Bargeld bucht; das Nachladen der Wechselkurse ändert diese Buchungen nicht. Nichts wird automatisch geändert.',
    histRateCell: 'Abrechnungsbetrag zum eigenen Kurs 0,9300: 930,00 EUR',
    histSplit: 'Gefiltert: 1 Split, dem ein Portfolio fehlt — Wexmoor Instruments AG · 2:1 · 16.04.2026: es fehlt „Family Depot“, das vorher 12 Stück hielt. Dort sind die FIFO-Lots geteilt, der Bestand nicht. Den Split mit demselben Datum und Verhältnis erneut erfassen („Split erfassen“ beim Wertpapier): Er ergänzt nur die fehlenden Zeilen. Ist der Split falsch, den ganzen Split löschen. Nichts wird automatisch geändert.',
    // 01 ①b, the merge previews
    flowsHead: 'Externe Zu- und Abflüsse',
    flowsWhen: 'bei „als Duplikate entfernen“',
    flowsBasis: 'Je Eintrag ein Fluss der zeitgewichteten Rendite, der beim Entfernen der Duplikate entfällt oder wandert · Beträge in der Währung des Kontos',
    flowsInfo: [
      'Entfällt: eine zusammengeführte Ein- oder Auslieferung, ein externer Fluss ihres Portfolios an ihrem Tag. Stück: die Veränderung der Stücke dieses Flusses; der Betrag zum gebuchten Preis, ohne Preis zum Tageskurs.',
      'Ansichtsgrenze: eine Umbuchung, ein Kauf oder Verkauf mit genau einem Bein in der Ansicht, ein Fluss über deren Grenze und keiner des Portfolios; ein Eintrag je Ansicht.',
      'Gesetzter Saldo: der Geldbetrag einer entfernten Buchung, den der nächste gesetzte Saldo ihres Kontos als Rest aufnimmt.',
      'Der Fluss jedes genannten Tages ändert sich nur um diese Einträge; die Rendite ab diesem Tag liest zudem die entfernten Stücke nicht mehr. Die Vorschau nennt daher die Flüsse, keine neu gerechnete Rendite.',
      'Die Zugehörigkeit zu Ansichten gilt, wie sie steht; das Zusammenführen ändert sie nicht.'
    ],
    flowsCols: ['Datum', 'Wirkung', 'Buchung · wo', 'Stück', 'Fluss'],
    flowRemoved: 'entfällt',
    flowBoundary: 'entfällt an der Ansichtsgrenze',
    flowAbsorbed: 'vom gesetzten Saldo aufgenommen',
    atBooked: 'zum gebuchten Preis',
    atValue: 'zum gebuchten Wert',
    flowsNone: 'Externe Zu- und Abflüsse: Keiner entfällt oder wandert; die Rendite liest dieselben Flüsse.',
    // 02 ①a, the booking drawer
    drawerHead: 'Typ Kauf · Datum 2026-04-16 · Depot Round Trip Depot · Wertpapier Arbolia Inc. — unverändert, für das Board gekürzt',
    cashHelp: 'Das Geld, das das Konto bewegt. Gespeichert: 806,00 (wie importiert).',
    cashNote: 'Menge, Preis, Gebühren oder Steuern geändert: Der Betrag folgt nicht von selbst. Vorgeschlagen sind 816,00 = 10 × 81,00 + 5,00 + 1,00. Speichern übernimmt, was im Feld steht — den abgerechneten Betrag eintragen, wenn er abweicht.',
    cashError: 'passt nicht zu Menge × Preis, Gebühren und Steuern — erwartet 816,00',
    cashDerivedA: 'Betrag aus den neuen Zahlen abgeleitet: 816,00 statt 806,00 (wie importiert).',
    // 02 ①b / ①c, the trade-price rule (Sprint 22's existing strings do the rest)
    sellHint: 'Bepreist zum letzten eigenen Handelspreis: 19,20 (14.03.2025).',
    catBasis: 'Kurse: der neueste, ohne Kurs der letzte eigene Handelspreis',
    // 03, the journal
    journal: 'Audit-Journal',
    journalSub: 'Jede gespeicherte Änderung, wer sie machte und was vorher stand',
    entries: 'Einträge',
    actor: 'Akteur',
    operation: 'Vorgang',
    entity: 'Eintrag',
    change: 'Änderung',
    whenUtc: 'Zeit (UTC)',
    all: 'Alle',
    allKinds: 'Alle Arten',
    ops: { create: 'Angelegt', update: 'Geändert', delete: 'Gelöscht', upsert: 'Angelegt oder ersetzt' },
    actors: { owner_ui: 'Operator', api_token_rw: 'Agent', import_session: 'Import', system_job: 'System' },
    scenarios: 'Was-wäre-wenn-Szenarien einbeziehen',
    journalBasis: 'Neueste zuerst · 7 Einträge · Akteur Agent · ohne Was-wäre-wenn-Szenarien · Zeiten in UTC',
    values: 'Gespeicherte Werte',
    field: 'Feld',
    before: 'Vorher',
    deletedWith: 'gelöscht, mit allen Werten',
    entityHistory: 'Nur dieser Eintrag',
    history: 'Verlauf'
  };

  // ---------------------------------------------------------------- preps
  // Each prep runs in the page (no closure): its data comes in `a`.

  // 01 ①a: three more findings on the data-quality line.
  function dqAdd(a) {
    const actions = document.querySelector('#dashboard-dq-line .data-note__actions');
    a.findings.forEach((f, i) => {
      const sep = M.el('<span aria-hidden="true"> · </span>');
      const wrap = M.el('<span class="mock-new"><a href="' + f.href + '" data-role="' + f.role + '">' + f.text + '</a> <span data-effect-of="' + f.role + '">' + f.effect + '</span></span>');
      actions.appendChild(sep);
      actions.appendChild(wrap);
      if (i === 0) M.pin(wrap, 1, 'pre');
    });
  }

  // 01 ①a: the history filtered to one report's rows. Keeps the given real
  // rows, rewrites their figures where the seed has no such row, and puts
  // the report's note above the summary.
  function histFilter(a) {
    const keep = new Set(a.rows.map(r => String(r.id)));
    document.querySelectorAll('#transaction-list tbody tr[data-transaction], #transaction-phone-rows li[data-transaction]').forEach(tr => { if (!keep.has(tr.dataset.transaction)) tr.remove(); });
    // Month heads with no row left go.
    document.querySelectorAll('#transaction-list tbody tr.tx-group-head').forEach(h => { const n = h.nextElementSibling; if (!n || n.classList.contains('tx-group-head')) h.remove(); else { const s = h.querySelector('.tx-group-subtotal'); if (s) s.textContent = '1 Transaktion'; } });
    document.querySelectorAll('#transaction-phone-rows li.phone-rows__group').forEach(h => { const n = h.nextElementSibling; if (!n || n.classList.contains('phone-rows__group')) h.remove(); else { const s = h.querySelector('.tx-group-subtotal'); if (s) s.textContent = '1 Transaktion'; } });
    for (const r of a.rows) {
      document.querySelectorAll('[data-transaction="' + r.id + '"]').forEach(row => {
        for (const [from, to] of r.swap || []) row.innerHTML = row.innerHTML.split(from).join(to);
        if (r.synthetic) row.classList.add('mock-synth');
        const amt = row.querySelector('td[data-role="amount"]');
        if (amt && r.cellNote) { amt.insertAdjacentHTML('beforeend', '<small class="cell-note mock-new">' + r.cellNote + '</small>'); }
        const pamt = row.querySelector('[data-role="phone-amount"]');
        if (pamt && r.cellNote) pamt.insertAdjacentHTML('afterend', '<span class="phone-row__figure2 mock-new">' + r.cellNote + '</span>');
      });
    }
    // The summary counts what is left.
    const sum = document.querySelector('#transaction-summary');
    if (sum) {
      sum.querySelector('[data-role="summary-total"]').textContent = '1';
      sum.querySelectorAll('.summary-type').forEach(s => { if (s.dataset.type !== a.kind) s.remove(); else s.innerHTML = s.innerHTML.replace(/<strong data-role="summary-count">\d+<\/strong>/, '<strong data-role="summary-count">1</strong>').replace(/·[\s\S]*$/, '· ' + a.sum); });
    }
    const note = M.note('problem', a.note, { id: 'transaction-dq-note', role: 'dq-filter-note', clamp: true, isNew: true, actions: a.actions });
    const anchor = document.querySelector('#transaction-more-filters') || document.querySelector('#transaction-summary');
    anchor.before(note);
    M.pin(note, 1, 'abs');
    // The chips stand as they are; the dq filter is URL-driven, like `since`.
  }

  // 01 ①a, variant B: a data-quality section on the Imports page.
  function importsB(a) {
    const tabs = document.querySelector('#area-tabs');
    const rows = (list) => list.map(r => '<tr><td>' + r[0] + '</td><td>' + r[1] + '</td><td>' + r[2] + '</td><td class="num">' + r[3] + '</td><td class="row-actions"><button type="button" class="button-mini">Bearbeiten</button></td></tr>').join('');
    const block = (title, remedy, list) => '<h3 class="merge-block-head">' + title + '</h3><p class="summary-basis">' + remedy + '</p><div class="data-table-wrapper"><table class="data-table"><thead><tr><th>Datum</th><th>Art</th><th>Wertpapier</th><th class="num">Zahlen</th><th></th></tr></thead><tbody>' + rows(list) + '</tbody></table></div>';
    const sec = M.el('<section id="imports-data-quality" class="workspace-section mock-new"><h2>Datenqualität</h2>' +
      block('Betrag passt nicht zu den Zahlen (1)', 'Den Betrag im Buchungsformular angeben. Nichts wird automatisch geändert.', [['16.04.2026', 'Kauf', 'Arbolia Inc.', '10 × 81,00 · Betrag 806,00 · aus den Zahlen 816,00']]) +
      block('Fremdwährung ohne Betrag (1)', 'Den Abrechnungsbetrag eintragen; das Nachladen der Wechselkurse ändert diese Buchungen nicht.', [['05.06.2026', 'Kauf', 'Larkspur Robotics Inc', '40 × 25,00 USD · Kurs 0,9300 · kein Betrag']]) +
      block('Split ohne alle Portfolios (1)', 'Den Split erneut erfassen; er ergänzt nur die fehlenden Zeilen.', [['16.04.2026', 'Split', 'Wexmoor Instruments AG', '2:1 · fehlt in „Family Depot“ (12 Stück)']]) +
      '</section>');
    tabs.after(sec);
    M.pin(sec.querySelector('h2'), 'B', 'in');
    const drop = document.querySelector('#pp-import-drop');
    if (drop) M.elide(drop, 'Die Ablage für den Portfolio-Performance-Export — unverändert, für das Board gekürzt');
  }

  // 01 ①b: synthetic equal bookings in a merge preview (the seed's pairs
  // have none), in pair_choice/1's markup; with a.flows the new section.
  function mergePairs(a) {
    const dlg = document.querySelector('dialog[open]');
    const counts = dlg.querySelector('[data-role="merge-counts"]');
    if (counts && a.kind === 'depot') {
      const dts = counts.querySelectorAll('dt');
      const last = dts[dts.length - 1];
      last.textContent = String(a.pairs.length);
      last.nextElementSibling.textContent = a.equalWord;
    }
    const head = '<tr><th>Datum</th><th>Art</th><th>Wertpapier</th><th class="num">Betrag</th><th>Steht in</th></tr>';
    const trs = a.pairs.map(p => '<tr class="mock-synth"><td>' + p.date + '</td><td>' + p.kind + '</td><td>' + p.security + '</td><td class="num">' + p.amount + '</td><td>' + a.standsIn + '</td></tr>').join('');
    const lis = a.pairs.map(p => '<li class="mock-synth"><span class="merge-lines__head">' + p.date + ' · ' + p.kind + ' · ' + p.security + '</span><span class="merge-lines__figure num">' + p.amount + '<small>' + a.inBoth + '</small></span></li>').join('');
    const form = M.el('<form id="merge-choice-form" data-role="merge-choice-form"><fieldset class="merge-choice" data-role="merge-pairs"><legend>' + a.legend + '</legend>' +
      '<div class="data-table-wrapper merge-wide"><table class="data-table"><thead>' + head + '</thead><tbody>' + trs + '</tbody></table></div>' +
      '<ul class="merge-lines merge-narrow">' + lis + '</ul>' +
      '<label class="merge-option" data-role="collapse-true"><input type="radio" name="merge[collapse]" value="true"><span>' + a.remove + '<small>' + a.removeSub + '</small>' + (a.extra ? '<small class="merge-option__extra">' + a.extra + '</small>' : '') + '</span></label>' +
      '<label class="merge-option" data-role="collapse-false"><input type="radio" name="merge[collapse]" value="false"><span>' + a.keep + '<small>' + a.keepSub + '</small></span></label>' +
      '<p class="merge-basis">' + a.equalMeans + '</p></fieldset></form>');
    const notes = [...dlg.querySelectorAll('.data-note--note')].filter(n => !n.closest('.merge-region'));
    notes[0].before(form);
    if (a.flows) {
      const rows = a.flows.map(f => '<tr><td>' + f.date + '</td><td>' + f.effect + '</td><td>' + f.booking + '<small class="cell-note">' + f.where + '</small></td><td class="num">' + f.qty + '</td><td class="num">' + f.amount + '<small class="cell-note">' + f.valued + '</small></td></tr>').join('');
      const lines = a.flows.map(f => '<li><span class="merge-lines__head">' + f.date + ' · ' + f.effect + '</span><span class="merge-lines__figure num">' + f.amount + '<small>' + f.booking + ' · ' + f.where + (f.qty !== '—' ? ' · ' + f.qty + ' Stück' : '') + ' · ' + f.valued + '</small></span></li>').join('');
      const sec = M.el('<section class="merge-flows mock-new" data-role="merge-flows"><div class="section-title"><h3 class="merge-block-head">' + a.flowsHead + ' <small>' + a.flowsWhen + '</small></h3><details class="metric-tooltip metric-tooltip--inline metric-tooltip--section" data-role="section-info"' + (a.openInfo ? ' open' : '') + '><summary aria-label="Zu diesem Abschnitt">ⓘ</summary><p role="tooltip">' + a.flowsInfo.join('<br>') + '</p></details></div>' +
        '<div class="data-table-wrapper merge-wide"><table class="data-table merge-flows-table"><thead><tr>' + a.cols.map((c, i) => '<th' + (i >= 3 ? ' class="num"' : '') + '>' + c + '</th>').join('') + '</tr></thead><tbody>' + rows + '</tbody></table></div>' +
        '<ul class="merge-lines merge-narrow">' + lines + '</ul>' +
        '<p class="merge-basis">' + a.flowsBasis + '</p></section>');
      form.after(sec);
      M.pin(sec.querySelector('h3'), 1, 'in');
    }
  }

  // 01 ①b: the security preview's one line where nothing moves.
  function flowsNone(a) {
    const fifo = document.querySelector('dialog[open] [data-role="merge-fifo"]');
    const p = M.el('<p class="merge-basis mock-new" data-role="merge-flows-none">' + a.text + '</p>');
    fifo.after(p);
    M.pin(p, 1, 'pre');
  }

  // 02 ①a: the drawer's first four fields do not change; one elided line.
  function drawerHead(a) {
    const labels = [...document.querySelectorAll('#transaction-form .form-grid > label')].slice(0, 4);
    const first = labels[0];
    labels.slice(1).forEach(l => l.remove());
    const d = M.elide(first, a.text, 'div');
    d.style.gridColumn = '1 / -1';
  }

  // Opens a <details> (client-side).
  function openDetails(a) { document.querySelectorAll(a.sel).forEach(d => { d.open = true; }); }

  // 02 ①a: the drawer's new cash field and its note (b); or (a): derived.
  function drawerCash(a) {
    const grid = document.querySelector('#transaction-form .form-grid');
    const errId = 'tx-error-gross_amount';
    const field = M.el('<label class="mock-new"><span>' + a.label + '</span><input name="transaction[gross_amount]" value="' + a.value + '" inputmode="decimal" class="num"' + (a.readonly ? ' readonly aria-readonly="true"' : '') + (a.error ? ' aria-invalid="true" aria-describedby="' + errId + '"' : '') + '>' + (a.error ? '<p id="' + errId + '" class="field-error" role="alert">' + a.error + '</p>' : '') + (a.help ? '<p class="form-help">' + a.help + '</p>' : '') + '</label>');
    grid.appendChild(field);
    M.pin(field.querySelector('span'), a.pin, 'in');
    if (a.note) {
      const n = M.note(a.noteSev, a.note, { isNew: true, role: 'cash-restate' });
      grid.after(n);
    }
  }

  // 02 ①b: the open lots priced at the last own trade price.
  function lotsTrade(a) {
    const rows = document.querySelectorAll('#detail-tab-panel-trades .detail-trades-table tbody tr');
    a.lots.forEach((l, i) => {
      const tds = rows[i].querySelectorAll('td');
      tds[3].innerHTML = '19,20<small class="cell-note mock-new">' + a.source + '</small>';
      const set = (td, v, cls) => { td.textContent = v; td.className = 'num ' + (cls || ''); };
      set(tds[4], l.pnl, l.cls); set(tds[5], l.pct, l.cls); set(tds[6], l.pnl, l.cls); set(tds[7], '0,00', 'is-flat');
      tds[8].innerHTML = l.pnl + ' <small>EUR</small>'; tds[8].className = 'num ' + (l.cls || ''); tds[8].removeAttribute('title');
      [4, 5, 6, 7, 8].forEach(j => tds[j].classList.add('mock-new'));
    });
    M.pin(rows[0].querySelectorAll('td')[3], 1, 'abs');
  }

  // 02 ①b: the sell preview priced at the last own trade price.
  function sellTrade(a) {
    const sec = document.querySelector('#sell-lot-preview');
    const tds = sec.querySelectorAll('tbody tr td');
    tds[3].innerHTML = '+6,00 <small>EUR</small>'; tds[3].className = 'is-positive mock-new'; tds[3].removeAttribute('title');
    const tot = sec.querySelector('[data-role="preview-total"]');
    tot.innerHTML = '+6,00 <small>EUR</small>'; tot.className = 'is-positive mock-new';
    const old = sec.querySelector('[data-role="preview-price-hint"]');
    const hint = M.el('<p class="form-help mock-new" data-role="preview-price-hint">' + a.hint + '</p>');
    if (old) old.replaceWith(hint); else sec.querySelector('.data-table-wrapper').before(hint);
    M.pin(hint, 1, 'pre');
  }

  // 02 ①b / ①c and 01 ①b: keep only some of a page.
  function catTrim(a) {
    document.querySelectorAll('details.cat-node').forEach(d => {
      const name = d.querySelector('.cat-name__text');
      if (!name || !a.keepCats.includes(name.textContent.trim())) d.remove(); else d.open = true;
    });
    const list = document.querySelector('[data-role="category-result-excluded-list"]');
    if (list && a.openList) list.open = true;
    // Members cut to the trade-priced ones first and a few others.
    document.querySelectorAll('details.cat-node').forEach(d => {
      const lis = [...d.querySelectorAll('li[data-role="security-row"]')];
      if (lis.length > a.maxRows) { lis.slice(a.maxRows + 1).forEach(x => x.remove()); M.elide(lis[a.maxRows], '… ' + (lis.length - a.maxRows) + ' weitere Positionen, für das Board gekürzt', 'li'); }
    });
  }

  function catAfter(a) {
    const node = (name) => [...document.querySelectorAll('details.cat-node')].find(d => d.querySelector('.cat-name__text').textContent.trim() === name);
    for (const c of a.cats) {
      const d = node(c.name);
      const inv = d.querySelector('summary [data-role="category-invested"]');
      inv.textContent = c.invested; inv.classList.add('mock-new');
      const res = d.querySelector('summary [data-role="category-result"]');
      res.className = 'cat-result ' + c.tone + ' mock-new';
      res.innerHTML = '<b>' + c.result + '</b> <small>' + c.pct + '</small>';
      d.querySelectorAll('li[data-role="security-row"]').forEach(li => {
        const n = li.querySelector('.row-name').textContent.trim();
        if (a.tradePriced.includes(n)) li.querySelector('.row-value').insertAdjacentHTML('afterbegin', '<small class="cell-note mock-new">' + a.source + '</small>');
      });
    }
    M.pin(node(a.cats[0].name).querySelector('summary [data-role="category-result"]'), 1, 'abs');
    // The excluded note names what is still left out.
    const note = document.querySelector('[data-role="category-result-excluded"]');
    note.classList.add('mock-new');
    const body = note.querySelector('.data-note__body');
    const details = body.querySelector('details');
    body.innerHTML = a.lead + ' ';
    body.appendChild(details);
    details.querySelector('summary').lastChild.textContent = ' ' + a.summary;
    details.querySelectorAll('li').forEach(li => { if (!a.stillOut.includes(li.querySelector('bdi').textContent.trim())) li.remove(); });
    // The basis line names the price rule.
    const basis = document.querySelector('[data-role="category-result-basis"] > span');
    basis.insertAdjacentHTML('beforeend', '<span class="mock-new">&nbsp;· ' + a.basis + '</span>');
  }

  // 02 ①d: R5's sentences as built, into a live exclusion note.
  function r5(a) {
    const n = document.querySelector(a.note);
    const text = n.querySelector('.data-note__text') || n.querySelector('.data-note__body');
    const counts = text.querySelector('[data-role$="-excluded-counts"]');
    if (counts) { counts.textContent = a.counts + ' '; M.pin(counts, 1, 'pre'); }
    const anchor = text.querySelector('[data-role="fx-backfill-reason"]');
    a.spans.forEach((s, i) => {
      const sp = M.el('<span data-role="' + s.role + '" class="mock-synth">' + s.text + '</span>');
      if (anchor) anchor.before(sp); else text.appendChild(sp);
      text.insertBefore(document.createTextNode(' '), sp);
      M.pin(sp, i + 2, 'pre');
    });
    n.classList.remove('data-note--clamped');
    const t = n.querySelector('.data-note__text'); if (t) t.style.display = 'block';
  }

  // 03: the journal page, built into the shell of a shipped page.
  function journalA(a) {
    document.getElementById('app-topbar-title').textContent = a.title;
    document.getElementById('app-topbar-subtitle').textContent = a.sub;
    const ws = document.querySelector('main .workspace-page');
    const chips = (family, list, on) => '<span><span class="filter-chips__family">' + family + '</span>' + list.map(c => '<button type="button" class="filter-chip' + (c === on ? ' is-active' : '') + '" aria-pressed="' + (c === on) + '">' + c + '</button>').join('') + '</span>';
    const rows = a.entries.map(e => '<tr data-entry="' + e.id + '"><td class="cell-date">' + e.when + '</td><td>' + e.actor + (e.label ? '<small class="cell-note">' + e.label + '</small>' : '') + '</td><td class="cell-kind">' + e.op + '</td><td class="cell-name">' + (e.href ? '<a href="' + e.href + '">' + e.entity + '</a>' : e.entity) + '<small class="cell-note"><a href="/journal?resource_type=' + e.type + '&amp;resource_id=' + e.rid + '">' + a.only + '</a></small></td><td class="journal-change">' + e.change.map(c => '<span class="journal-change__line">' + c + '</span>').join('') + (e.values ? '<details class="journal-values"' + (e.open ? ' open' : '') + '><summary class="disclosure-summary">' + a.chev + a.valuesLabel + '</summary><table><thead><tr><th>' + a.field + '</th><th>' + a.before + '</th><th>' + a.after + '</th></tr></thead><tbody>' + e.values.map(v => '<tr><td>' + v[0] + '</td><td>' + v[1] + '</td><td>' + v[2] + '</td></tr>').join('') + '</tbody></table></details>' : '') + '</td></tr>').join('');
    const phone = a.entries.map(e => '<li class="phone-row" data-role="phone-row"><span class="phone-row__body"><span class="phone-row__name">' + e.when + ' · ' + e.op + ' · ' + e.actor + (e.label ? ' (' + e.label + ')' : '') + '</span><span class="phone-row__ids"><span>' + (e.href ? '<a href="' + e.href + '">' + e.entity + '</a>' : e.entity) + '</span></span><span class="phone-row__ids">' + e.change.join(' · ') + '</span></span></li>').join('');
    ws.innerHTML = '<section id="journal-panel" class="workspace-section mock-new"><header class="section-head"><h2>' + a.entriesLabel + '</h2></header>' +
      '<div class="filter-chips" role="group">' + chips(a.actorLabel, a.actorChips, a.actorOn) + chips(a.opLabel, a.opChips, null) + '</div>' +
      '<div class="journal-filters" style="display:flex;gap:16px;align-items:center;flex-wrap:wrap;margin:8px 0"><label class="journal-kind"><span class="visually-hidden">' + a.entityLabel + '</span><select><option>' + a.allKinds + '</option>' + a.kinds.map(k => '<option>' + k + '</option>').join('') + '</select></label><label style="display:inline-flex;gap:6px;align-items:center;font-size:13px"><input type="checkbox"> ' + a.scenarios + '</label></div>' +
      '<p class="summary-basis" data-role="journal-basis">' + a.basis + '</p>' +
      '<div class="data-table-wrapper journal-table-wrap"><table class="data-table journal-table"><thead><tr><th>' + a.cols.join('</th><th>') + '</th></tr></thead><tbody>' + rows + '</tbody></table></div>' +
      '<ul class="phone-rows" aria-label="' + a.entriesLabel + '">' + phone + '</ul></section>';
    M.pin(document.querySelector('#journal-panel h2'), 1, 'in');
    M.pin(document.querySelector('#journal-panel .filter-chips'), 2, 'pre');
    M.pin(document.querySelector('#journal-panel tr[data-entry="353"] .journal-values summary'), 3, 'in');
  }

  // 03: the navigation entry.
  function journalNav(a) {
    const groups = [...document.querySelectorAll('#app-sidebar .nav-group')];
    const admin = groups[groups.length - 1];
    const link = M.el('<a id="nav-journal" class="nav-link is-active mock-new" href="/journal" aria-current="page"><span class="nav-marker" aria-hidden="true"></span><span class="nav-ico" aria-hidden="true">' + a.icon + '</span><span class="nav-label">' + a.label + '</span></a>');
    admin.appendChild(link);
    document.querySelectorAll('#app-sidebar .nav-link.is-active').forEach(l => { if (l !== link) { l.classList.remove('is-active'); l.removeAttribute('aria-current'); } });
    M.pin(link, 1, 'abs');
  }

  // 03 B: a history fold on the security's own page.
  function journalB(a) {
    const pane = document.querySelector('.detail-pane');
    const panel = pane.querySelector('[role="tabpanel"]');
    if (panel) M.elide(panel, 'Der Überblick des Wertpapiers — unverändert, für das Board gekürzt');
    const items = a.entries.map(e => '<li class="phone-row"><span class="phone-row__body"><span class="phone-row__name">' + e.when + ' · ' + e.op + '</span><span class="phone-row__ids">' + e.change + '</span></span><span class="phone-row__figures"><span class="phone-row__figure">' + e.actor + '</span></span></li>').join('');
    const fold = M.el('<details class="perf-table-disclosure mock-new" open style="margin:12px"><summary class="disclosure-summary">' + a.chev + a.label + '</summary><ul class="phone-rows" style="display:block">' + items + '</ul><p class="summary-basis">' + a.basis + '</p></details>');
    pane.appendChild(fold);
    M.pin(fold.querySelector('summary'), 'B', 'in');
  }

  // ---------------------------------------------------------------- data
  const chev = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" class="disclosure-chevron" aria-hidden="true"><path d="m9 6 6 6-6 6"></path></svg>';
  const clock = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9"></circle><path d="M12 7v5l3 2"></path></svg>';

  const dqFindings = [
    { role: 'dq-cash-mismatch', href: '/transactions?dq=cash_mismatch', text: NEW.dqCash, effect: NEW.dqCashEffect },
    { role: 'dq-rate-only', href: '/transactions?dq=rate_only', text: NEW.dqRate, effect: NEW.dqRateEffect },
    { role: 'dq-incomplete-split', href: '/transactions?dq=incomplete_split', text: NEW.dqSplit, effect: NEW.dqSplitEffect }
  ];
  const allLink = '<a href="/transactions">' + NEW.histAll + '</a>';

  const depotPairs = {
    kind: 'depot',
    equalWord: de('equal booking', 2),
    legend: de('%{count} equal booking in both accounts', 2),
    standsIn: de('%{source} and %{target}', null, { source: 'Depot 1', target: 'Depot Nord' }),
    inBoth: de('in %{source} and %{target}', null, { source: 'Depot 1', target: 'Depot Nord' }),
    remove: de('remove as duplicates'),
    removeSub: de('The booking from %{source} is deleted.', 2, { source: 'Depot 1' }),
    extra: de('Also changes: %{changes}', null, { changes: de('a set balance of %{name} on %{date} absorbs %{amount}', null, { name: 'Broker Verrechnung 1', date: '31.03.2025', amount: '-1.225,00' }) }),
    keep: de('keep both'),
    keepSub: de('Every booking stands in %{target} afterwards.', null, { target: 'Depot Nord' }),
    equalMeans: de('Equal means: same day, same kind, same amounts.'),
    pairs: [
      { date: '12.03.2025', kind: de('Buy'), security: 'Cobalt Ridge Logistics SE', amount: '1.225,00' },
      { date: '14.03.2025', kind: de('Inbound delivery'), security: 'Helios Solar Systems SE', amount: de('%{quantity} shares', null, { quantity: '5' }) }
    ]
  };
  const depotFlows = Object.assign({}, depotPairs, {
    flowsHead: NEW.flowsHead, flowsWhen: NEW.flowsWhen, flowsInfo: NEW.flowsInfo, flowsBasis: NEW.flowsBasis, cols: NEW.flowsCols,
    flows: [
      { date: '12.03.2025', effect: NEW.flowBoundary, booking: de('Buy') + ' · Cobalt Ridge Logistics SE', where: de('View') + ' „Nur Neuzugang“', qty: '—', amount: '-1.225,00 EUR', valued: NEW.atValue },
      { date: '14.03.2025', effect: NEW.flowRemoved, booking: de('Inbound delivery') + ' · Helios Solar Systems SE', where: 'Depot 1', qty: '-5', amount: '-96,00 EUR', valued: NEW.atBooked },
      { date: '31.03.2025', effect: NEW.flowAbsorbed, booking: de('Buy') + ' · Cobalt Ridge Logistics SE', where: 'Broker Verrechnung 1', qty: '—', amount: '-1.225,00 EUR', valued: NEW.atValue }
    ]
  });

  async function openDepotMerge(page) {
    await trigger(page, { 'phx-click': 'row_merge', 'phx-value-kind': 'depot', 'phx-value-id': '2' });
    await page.check('#merge-target-4');
    await page.waitForTimeout(500);
    await page.click('[data-role="merge-continue"]');
    await page.waitForTimeout(1500);
  }
  async function openSecurityMerge(page) {
    await trigger(page, { 'phx-click': 'row_action', 'phx-value-action': 'merge', 'phx-value-id': '44' });
    await page.fill('[data-role="merge-search"] input', 'Thornbury');
    await page.waitForTimeout(1200);
    await page.check('#merge-target-45');
    await page.waitForTimeout(500);
    await page.click('[data-role="merge-continue"]');
    await page.waitForTimeout(1500);
  }
  // The imported Arbolia buy (10 at 80,00, fees 5,00, taxes 1,00, cash
  // 806,00) opened for editing, its price typed as 81 — never saved.
  async function editArbolia(page) {
    await trigger(page, { 'phx-click': 'edit_transaction', 'phx-value-id': '96' });
    await page.evaluate(() => { const d = document.querySelector('#transaction-costs'); if (d) d.open = true; });
    await page.fill('#transaction-form input[name="transaction[price]"]', '81');
    await page.waitForTimeout(1200);
    await page.evaluate(() => { const d = document.querySelector('#transaction-costs'); if (d) d.open = true; });
  }
  // A sell of 5 Helios from Depot Nord, typed into the drawer — never saved.
  async function sellHelios(page) {
    await page.click('#open-booking');
    await page.waitForTimeout(900);
    await page.selectOption('#transaction-form select[name="transaction[type]"]', 'sell');
    await page.waitForTimeout(700);
    await page.selectOption('#transaction-form select[name="transaction[securities_account_id]"]', '4');
    await page.waitForTimeout(700);
    await page.selectOption('#transaction-form select[name="transaction[security_id]"]', '23');
    await page.waitForTimeout(700);
    await page.fill('#transaction-form input[name="transaction[quantity]"]', '5');
    await page.waitForTimeout(1400);
  }

  const lots = { source: de('Trade price · %{date}', null, { date: '14.03.2025' }), lots: [{ pnl: '+18,00', pct: '+6,7%', cls: 'is-positive' }, { pnl: '0,00', pct: '0,0%', cls: 'is-flat' }] };

  const etfTrade = ['Cobalt Ridge Logistics SE', 'Meridian Global Equity ETF', 'Orchid Bay Pharmaceuticals plc', 'Pinecrest Utilities SA', 'Quarry Lane Materials AG', 'Helios Solar Systems SE', 'Juniper Rail AG', 'Thornbury Water Fund', 'Alder Creek Timber Fund', 'Alder Creek Timber Fund Class B', 'Birchwood Global Savings Fund'];
  const catPrep = { keepCats: ['ETF', 'Fund'], maxRows: 7, openList: true };
  const catAfterArgs = {
    source: de('at trade price'),
    tradePriced: etfTrade,
    cats: [
      { name: 'ETF', invested: '21.749,40', result: '-256,20', pct: '-1,2%', tone: 'is-negative' },
      { name: 'Fund', invested: '451,11', result: '0,00', pct: '0,0%', tone: '' }
    ],
    lead: de('%{count} position is not included in “Cost” and “Result”.', 3),
    summary: de('The position', 3),
    stillOut: ['Harborline Freight Inc', 'Larkspur Robotics Inc', 'Placeholder Anleihe 2031 3,25%'],
    basis: NEW.catBasis
  };

  const R5 = (kind) => {
    const realized = kind === 'realized';
    const msg = realized
      ? {
          third: '%{count} sale is not convertible — it or a buy it closes is priced in a currency that is neither the security\'s nor its account\'s — and is excluded from every total: %{securities}.',
          other: '%{count} sale is not convertible — a buy it closes was paid in another currency than the sale\'s, which no stored figure bridges — and is excluded from every total: %{securities}.',
          zero: '%{count} sale is not convertible — a buy it closes has an amount of zero, which the rate backfill does not complete — and is excluded from every total: %{securities}.',
          lead: 'Excluded from every total: %{counts}.'
        }
      : {
          third: '%{count} sale not convertible — it or a buy it closes is priced in a currency that is neither the security\'s nor its account\'s — is left out of the trades: %{securities}.',
          other: '%{count} sale not convertible — a buy it closes was paid in another currency than the sale\'s, which no stored figure bridges — is left out of the trades: %{securities}.',
          zero: '%{count} sale not convertible — a buy it closes has an amount of zero, which the rate backfill does not complete — is left out of the trades: %{securities}.',
          lead: 'Left out of the trades: %{counts}.'
        };
    const labels = [
      de('%{count} sale with no stored rate', 1),
      de('%{count} sale whose buy has no figure in its currency', 1),
      de('%{count} sale priced in a third currency', 1),
      de('%{count} sale whose buy was paid in another currency', 1),
      de('%{count} sale whose buy has an amount of zero', 1)
    ].join('; ');
    const p = realized ? 'realized-excluded' : 'trades-card-excluded';
    return {
      note: '#' + p,
      counts: de(msg.lead, null, { counts: labels }),
      spans: [
        { role: p + '-third-currency', text: de(msg.third, 1, { securities: 'Saltmarsh Mining plc' }) },
        { role: p + '-other-account', text: de(msg.other, 1, { securities: 'Brightwater Tools AG' }) },
        { role: p + '-zero-amount', text: de(msg.zero, 1, { securities: 'Fernhill Bonus AG' }) }
      ]
    };
  };

  // The seed's journal (synthetic): the seven writes of the API token named
  // "review seed", read from audit_journal, newest first.
  const W = '02.11.2026 18:00:23';
  const agentEntries = [
    { id: 354, type: 'tax_statement_snapshot', rid: 2, when: W, actor: 'Agent', label: 'review seed', op: NEW.ops.create, entity: 'Erfasste Abrechnung 2 · Beispiel Direktbank', href: '/tax', change: ['Steuerjahr 2025 · Stand 31.12.2025 · steuerpflichtige Erträge 380,00 · Kapitalertragsteuer 95,00'] },
    { id: 353, type: 'policy_rule', rid: 9, when: W, actor: 'Agent', label: 'review seed', op: NEW.ops.update, entity: 'Regel 9 · Barreserve höchstens 30 %', href: '/risk', open: true, change: ['Name: <span class="journal-change__from">Barobergrenze</span> → Barreserve höchstens 30 %'], values: [['name', 'Barobergrenze', 'Barreserve höchstens 30 %'], ['name_author', 'operator', 'agent']] },
    { id: 314, type: 'merge_record', rid: 5, when: W, actor: 'Agent', label: 'review seed', op: NEW.ops.create, entity: 'Zusammenführung 5 · Verrechnungskonten', href: '/portfolios', change: ['Festgeld → Festgeld Plus · 2 Buchungen verschoben · frühere Namen Festgeld, Festgeld (alt)'] },
    { id: 313, type: 'cash_account', rid: 15, when: W, actor: 'Agent', label: 'review seed', op: NEW.ops.update, entity: 'Verrechnungskonto 15 · Festgeld Plus', href: '/portfolios', change: ['Frühere Namen: <span class="journal-change__from">—</span> → Festgeld, Festgeld (alt)'], values: [['former_names', '[]', '["Festgeld", "Festgeld (alt)"]']] },
    { id: 312, type: 'cash_account', rid: 14, when: W, actor: 'Agent', label: 'review seed', op: NEW.ops.delete, entity: 'Verrechnungskonto 14 · Festgeld', href: null, change: [NEW.deletedWith], values: [['name', 'Festgeld', '—'], ['currency_code', 'EUR', '—'], ['former_names', '["Festgeld (alt)"]', '—'], ['liquidity_role', 'free_cash', '—']] },
    { id: 311, type: 'transaction', rid: 67, when: W, actor: 'Agent', label: 'review seed', op: NEW.ops.update, entity: 'Transaktion 67 · Einlage 05.05.2025 · 600,00 EUR', href: '/transactions', change: ['Verrechnungskonto: <span class="journal-change__from">Festgeld</span> → Festgeld Plus'], values: [['cash_account_id', '14', '15']] },
    { id: 310, type: 'transaction', rid: 66, when: W, actor: 'Agent', label: 'review seed', op: NEW.ops.update, entity: 'Transaktion 66 · Einlage 02.05.2025 · 400,00 EUR', href: '/transactions', change: ['Verrechnungskonto: <span class="journal-change__from">Festgeld</span> → Festgeld Plus'], values: [['cash_account_id', '14', '15']] }
  ];
  const journalArgs = {
    title: NEW.journal, sub: NEW.journalSub, entriesLabel: NEW.entries, actorLabel: NEW.actor, opLabel: NEW.operation, entityLabel: NEW.entity,
    actorChips: [NEW.all, NEW.actors.owner_ui, NEW.actors.api_token_rw, NEW.actors.import_session, NEW.actors.system_job], actorOn: NEW.actors.api_token_rw,
    opChips: [NEW.ops.create, NEW.ops.update, NEW.ops.delete, NEW.ops.upsert],
    allKinds: NEW.allKinds, kinds: [de('Transaction'), de('Security'), de('Cash account'), de('Depot'), de('Rule'), de('Classification'), de('Category')],
    scenarios: NEW.scenarios, basis: NEW.journalBasis, cols: [NEW.whenUtc, NEW.actor, NEW.operation, NEW.entity, NEW.change],
    entries: agentEntries, valuesLabel: NEW.values, field: NEW.field, before: NEW.before, after: de('After'), only: NEW.entityHistory, chev
  };
  const journalBArgs = {
    chev, label: NEW.history + ' · 2 Einträge', basis: 'Neueste zuerst · Zeiten in UTC',
    entries: [
      { when: '02.11.2026 18:00:22', op: NEW.ops.update, actor: 'Operator', change: 'ISIN: XS0000000017 → XS0000000025' },
      { when: '02.11.2026 18:00:22', op: NEW.ops.create, actor: 'Operator', change: 'Meridian Global Equity ETF · ETF · EUR' }
    ]
  };

  // 04: Wealth trimmed to the tabs, the lead KPI row and four positions
  // (two gains, two losses), the value columns on.
  function wealthTrim() {
    const support = document.querySelector('#portfolio-kpis .kpi-band__support');
    if (support) support.remove();
    const rows = [...document.querySelectorAll('#holdings-positions-table tbody tr')];
    const pos = rows.filter(r => r.querySelector('td.is-positive')).slice(0, 2);
    const neg = rows.filter(r => r.querySelector('td.is-negative')).slice(0, 2);
    const keep = new Set([...pos, ...neg]);
    rows.forEach(r => { if (!keep.has(r)) r.remove(); });
    const tb = document.querySelector('#holdings-positions-table tbody');
    [...pos, ...neg].forEach(r => tb.appendChild(r));
    const tr = document.createElement('tr');
    tr.className = 'mock-elided';
    tr.innerHTML = '<td colspan="12">… weitere Positionen, für das Board gekürzt</td>';
    tb.appendChild(tr);
  }

  // 04: the variants, as stylesheets over the same markup.
  const SIGN_POS = '.is-positive, .data-table td.is-positive, .stat .is-positive, .overview-metric dd.is-positive, .decimal-positive, .perf-badge.is-positive, .kpi-summary strong.is-positive, .kpi-strip__cell strong.is-positive, .phone-row__figure2 .decimal-positive';
  const SIGN_NEG = '.is-negative, .data-table td.is-negative, .stat .is-negative, .stat strong .is-negative, .overview-metric dd.is-negative, .decimal-negative, .perf-badge.is-negative, .kpi-summary strong.is-negative, .kpi-strip__cell strong.is-negative, .phone-row__figure2 .decimal-negative';
  const VARIANT_CSS = {
    today: '',
    a: `/* Variant A: gains always brand teal, losses always brand coral, whatever
   the accent; unsigned KPI values keep the active accent (today's rule). */
${SIGN_POS} { color: var(--color-accent-teal); }
${SIGN_NEG} { color: var(--color-accent-coral); }`,
    b: `/* Variant B: every figure in the active accent; the sign by its glyph only. */
${SIGN_POS}, ${SIGN_NEG} { color: var(--color-accent); }
.kpi-strip__cell strong { color: var(--color-accent); }`,
    c: `/* Variant C: the accent is for controls. Unsigned figures in the text
   colour; --color-positive and --color-danger become aliases of brand teal
   and brand coral (light #0f766e / #ce1b42, dark #2dd4bf / #fb7185), so the
   app has one green and one red, whatever the accent. */
html[data-theme] { --color-positive: var(--color-accent-teal); --color-danger: var(--color-accent-coral); }
.stat strong { color: var(--color-text); }`
  };
  const LOOKS = [];
  for (const [v, accents] of [['today', ['violet', 'teal', 'coral']], ['a', ['violet', 'teal', 'coral']], ['b', ['violet', 'teal', 'coral']], ['c', ['violet', 'teal', 'coral']]]) {
    for (const accent of accents) LOOKS.push({ suffix: '-' + v + '-' + accent, accent, theme: 'light', css: VARIANT_CSS[v], widths: v === 'c' || (v === 'today' && accent === 'teal') ? [1280, 390] : [1280] });
  }
  LOOKS.push({ suffix: '-today-teal-dark', accent: 'teal', theme: 'dark', css: '', widths: [1280, 390] });
  LOOKS.push({ suffix: '-c-teal-dark', accent: 'teal', theme: 'dark', css: VARIANT_CSS.c, widths: [1280, 390] });
  LOOKS.push({ suffix: '-c-coral-dark', accent: 'coral', theme: 'dark', css: VARIANT_CSS.c, widths: [1280] });
  const holdingsColumns = "try { localStorage.setItem('wealth.holdings.columns', JSON.stringify(['depot', 'security', 'quantity', 'currency', 'latest_price', 'market_value', 'unrealized_pnl_abs', 'unrealized_pnl_pct'])); } catch (e) {}";

  // ---------------------------------------------------------------- frames
  const FRAMES = [
    // Board 01 ①a
    { id: '01a-dq-today', url: '/', keep: ['#dashboard-data-quality'] },
    { id: '01a-dq-after', url: '/', keep: ['#dashboard-data-quality'], proposal: true, prep: { fn: dqAdd, args: { findings: dqFindings } } },
    { id: '01a-hist-cash', url: '/transactions', keep: ['#transaction-list-panel'], proposal: true,
      prep: { fn: histFilter, args: { kind: 'buy', sum: '-806,00 EUR', note: NEW.histCash, actions: allLink, rows: [{ id: 96, synthetic: true, swap: [['80,00', '81,00'], ['10 × 80,00', '10 × 81,00']], cellNote: NEW.histCashCell }] } } },
    { id: '01a-hist-rate', url: '/transactions', keep: ['#transaction-dq-note', '#transaction-table-wrapper'], proposal: true, widths: [1280],
      prep: { fn: histFilter, args: { kind: 'buy', sum: '-1.010,00 USD', note: NEW.histRate, actions: allLink, rows: [{ id: 69, synthetic: true, swap: [['-940,00', '-1.010,00'], ['>EUR<', '>USD<']], cellNote: NEW.histRateCell }] } } },
    { id: '01a-hist-split', url: '/transactions', keep: ['#transaction-dq-note', '#transaction-table-wrapper'], proposal: true, widths: [1280],
      prep: { fn: histFilter, args: { kind: 'split', sum: '', note: NEW.histSplit, actions: '<a href="/securities/46">' + de('Record split') + '</a><span aria-hidden="true"> · </span>' + allLink, rows: [{ id: 85, synthetic: true }] } } },
    { id: '01a-imports-b', url: '/imports', keep: ['#imports-workspace'], widths: [1280], prep: { fn: importsB } },
    // Board 01 ①b
    { id: '01b-depot-today', url: '/portfolios', act: openDepotMerge, keep: ['dialog[open]'], frameWidth: 760, prep: { fn: mergePairs, args: depotPairs } },
    { id: '01b-depot-after', url: '/portfolios', act: openDepotMerge, keep: ['dialog[open]'], frameWidth: 760, proposal: true, widths: [1280], prep: { fn: mergePairs, args: Object.assign({ openInfo: false }, depotFlows) } },
    { id: '01b-depot-info', url: '/portfolios', act: openDepotMerge, keep: ['dialog[open]'], frameWidth: 760, proposal: true, widths: [390], prep: { fn: mergePairs, args: Object.assign({ openInfo: true }, depotFlows) } },
    { id: '01b-security-today', url: '/securities/44', act: openSecurityMerge, keep: ['dialog[open]'], frameWidth: 760, widths: [1280] },
    { id: '01b-security-after', url: '/securities/44', act: openSecurityMerge, keep: ['dialog[open]'], frameWidth: 760, proposal: true, widths: [1280], prep: { fn: flowsNone, args: { text: NEW.flowsNone } } },
    // Board 02 ①a
    { id: '02a-drawer-today', url: '/transactions', act: editArbolia, keep: ['#booking-drawer'], frameWidth: 760, prep: { fn: drawerHead, args: { text: NEW.drawerHead } } },
    { id: '02a-drawer-b', url: '/transactions', act: editArbolia, keep: ['#booking-drawer'], frameWidth: 760, proposal: true,
      prep: [{ fn: drawerHead, args: { text: NEW.drawerHead } }, { fn: drawerCash, args: { label: de('Amount (%{currency})', null, { currency: 'EUR' }), value: '816,00', help: NEW.cashHelp, note: NEW.cashNote, noteSev: 'attention', pin: 1 } }] },
    { id: '02a-drawer-b-refused', url: '/transactions', act: editArbolia, keep: ['#booking-drawer'], frameWidth: 760, proposal: true, widths: [1280],
      prep: [{ fn: drawerHead, args: { text: NEW.drawerHead } }, { fn: drawerCash, args: { label: de('Amount (%{currency})', null, { currency: 'EUR' }), value: '806,00', error: NEW.cashError, help: NEW.cashHelp, pin: 1 } }] },
    { id: '02a-drawer-a', url: '/transactions', act: editArbolia, keep: ['#booking-drawer'], frameWidth: 760, proposal: true, widths: [1280],
      prep: [{ fn: drawerHead, args: { text: NEW.drawerHead } }, { fn: drawerCash, args: { label: de('Amount (%{currency})', null, { currency: 'EUR' }), value: '816,00', readonly: true, note: NEW.cashDerivedA, noteSev: 'note', pin: 'a' } }] },
    // Board 02 ①b
    { id: '02b-lots-today', url: '/securities/23?tab=trades', keep: ['.detail-pane-head', '#detail-tab-panel-trades'] },
    { id: '02b-lots-after', url: '/securities/23?tab=trades', keep: ['.detail-pane-head', '#detail-tab-panel-trades'], proposal: true, prep: { fn: lotsTrade, args: lots } },
    { id: '02b-sell-today', url: '/transactions', act: sellHelios, keep: ['#booking-drawer'], frameWidth: 760, widths: [1280] },
    { id: '02b-sell-after', url: '/transactions', act: sellHelios, keep: ['#booking-drawer'], frameWidth: 760, proposal: true, widths: [1280], prep: { fn: sellTrade, args: { hint: NEW.sellHint } } },
    // Board 02 ①c
    { id: '02c-cat-today', url: '/classifications/1', keep: ['[data-role="category-result-basis"]', '[data-role="category-result-excluded-region"]', '[data-role="tree-head"]', 'details.cat-node'], prep: { fn: catTrim, args: catPrep } },
    { id: '02c-cat-after', url: '/classifications/1', keep: ['[data-role="category-result-basis"]', '[data-role="category-result-excluded-region"]', '[data-role="tree-head"]', 'details.cat-node'], proposal: true, prep: [{ fn: catTrim, args: catPrep }, { fn: catAfter, args: catAfterArgs }] },
    // Board 02 ①d (as built)
    { id: '02d-realized-built', url: '/cashflow?tab=realized', keep: ['#realized-excluded'], prep: { fn: r5, args: R5('realized') } },
    { id: '02d-overview-built', url: '/', keep: ['#trades-card-excluded'], prep: { fn: r5, args: R5('overview') } },
    // Board 03
    { id: '03-journal-a', url: '/transactions', keep: ['header.topbar', 'main .workspace-page'], proposal: true, prep: { fn: journalA, args: journalArgs } },
    { id: '03-journal-nav', url: '/', keep: ['#app-sidebar'], widths: [1280], frameWidth: 760, prep: { fn: journalNav, args: { icon: clock, label: NEW.journal } }, css: '#app-sidebar{position:static!important;height:auto!important;transform:none!important}' },
    { id: '03-journal-b', url: '/securities/14', keep: ['.detail-pane'], proposal: true, prep: { fn: journalB, args: journalBArgs } },
    // Board 04: one capture each, written under every look
    { id: '04-strip', url: '/', keep: ['#dashboard-kpi-strip'], looks: LOOKS },
    { id: '04-wealth', url: '/portfolio', init: holdingsColumns, keep: ['#area-tabs', '#portfolio-kpis', '#holdings-positions-wrapper'], prep: { fn: wealthTrim }, looks: LOOKS }
  ];

  return { FRAMES, NEW, VARIANT_CSS };
};
