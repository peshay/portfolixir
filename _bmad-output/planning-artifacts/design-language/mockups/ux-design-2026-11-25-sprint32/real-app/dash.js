// Mockup only: loads the real Wealth tabs from a local instance on the
// synthetic review seed and rearranges the DOM into the Sprint 32 dashboard
// shape (planning board 02). Nothing is stored; the LiveView socket is cut first.
const { chromium } = require('playwright');
const CSS = `
.workspace-page{background:var(--color-bg)!important}
.mk-w{position:relative;margin-left:24px!important;margin-right:24px!important;background:var(--color-bg-elevated);border:1px solid var(--color-border);border-radius:12px;box-shadow:0 1px 2px rgb(15 23 42/.05),0 4px 14px rgb(15 23 42/.04);padding:14px 20px 12px!important;margin-top:0!important;margin-bottom:16px!important}
.mk-w>.section-head,.mk-wh{display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin:0 0 10px!important}
.mk-w h2,.mk-wh h2{font-size:16px!important;margin:0!important}
.mk-i{display:inline-grid;place-items:center;width:17px;height:17px;border-radius:50%;border:1px solid var(--color-border-strong);color:var(--color-text-muted);font-size:10.5px;font-weight:700}
.mk-sp{flex:1}
.mk-more{color:var(--color-text-muted);font-weight:800;letter-spacing:1px;padding:0 4px;font-size:15px}
.mk-follow{font-size:11px;font-weight:600;color:var(--color-text-muted);padding:2px 8px;border-radius:999px;border:1px solid var(--color-border)}
.mk-foot{display:flex;justify-content:space-between;gap:10px;margin-top:10px;padding-top:8px;border-top:1px solid var(--color-border);font-size:12px;color:var(--color-text-muted)}
.mk-foot a{color:var(--color-accent);font-weight:600;text-decoration:none}
.mk-w .stat{box-shadow:none!important;border:0!important;background:transparent!important;padding-left:0!important}
.mk-w .stat::before{display:none!important}
.mk-w .kpi-band{gap:6px 20px!important}
.mk-bar{display:flex;align-items:center;gap:10px;flex-wrap:wrap;padding:14px 24px 12px}
.mk-row{display:grid;grid-template-columns:2fr 1fr;gap:16px;margin:0 24px 16px;align-items:start}
.mk-row>.mk-w{margin:0!important;min-width:0}
.mk-row #portfolio-cash .data-table-wrapper{overflow:visible}
.mk-row #portfolio-cash table{width:100%!important;min-width:0!important;font-size:12.5px}\n.mk-row #portfolio-cash td,.mk-row #portfolio-cash th{white-space:normal!important}
.mk-dq li{display:flex;gap:8px;align-items:baseline;padding:7px 0;border-bottom:1px solid var(--color-border);font-size:13.5px}
.mk-dq li:last-child{border-bottom:0}
.mk-dq b{min-width:22px;text-align:right}
.mk-bar .mk-sel{display:inline-flex;align-items:center;gap:6px;padding:6px 12px;border:1px solid var(--color-border-strong);border-radius:8px;background:var(--color-bg-elevated);font-size:13px;font-weight:600}
.mk-chips{display:inline-flex;gap:2px;padding:3px;border-radius:999px;background:var(--color-bg-muted)}
.mk-chips span{padding:4px 12px;border-radius:999px;font-size:12.5px;font-weight:600;color:var(--color-text-muted)}
.mk-chips span.on{background:var(--color-accent);color:var(--color-on-accent,#fff)}
.mk-btn{display:inline-flex;align-items:center;gap:6px;padding:6px 12px;border:1px solid var(--color-border-strong);border-radius:8px;background:var(--color-bg-elevated);font-size:13px;font-weight:600;color:var(--color-text)}
.mk-btn.acc{background:var(--color-accent);border-color:var(--color-accent);color:var(--color-on-accent,#fff)}
.mk-badge{margin-left:auto;font-size:10px;font-weight:700;color:var(--color-text-muted);border:1px solid var(--color-border);border-radius:999px;padding:0 6px}
.mk-edit .mk-w{outline:1.5px dashed var(--color-accent);outline-offset:-1px}
.mk-edit .mk-more{display:none}
.mk-handle{position:absolute;top:6px;left:50%;transform:translateX(-50%);width:30px;height:4px;border-radius:2px;background:var(--color-text-subtle,#94a3b8)}
.mk-x{position:absolute;right:12px;top:10px;color:var(--color-text-muted);font-weight:700}
.mk-sizes{display:inline-flex;gap:2px;padding:2px;border-radius:6px;background:var(--color-bg-muted);font-size:11px;font-weight:700;margin-right:22px}
.mk-sizes span{padding:2px 7px;border-radius:4px;color:var(--color-text-muted)}
.mk-sizes span.on{background:var(--color-accent);color:var(--color-on-accent,#fff)}
`;
const BASE = 'http://127.0.0.1:4003';

async function common(p, title, sub, active, edit) {
  await p.evaluate(({ CSS, title, sub, active, edit }) => {
    window.liveSocket && window.liveSocket.disconnect();
    const st = document.createElement('style'); st.textContent = CSS; document.head.appendChild(st);
    // Sidebar: the starter dashboards where the tabs were.
    const ov = document.getElementById('nav-dashboard');
    ov.querySelectorAll('span').forEach((s) => { if (s.textContent.trim() === 'Vorlage') s.remove(); });
    const group = ov.parentElement, neu = document.getElementById('nav-new-dashboard');
    for (const name of ['Bestände', 'Allokation & Ziele', 'Snapshots', 'Risiko']) {
      const a = ov.cloneNode(true); a.id = '';
      const label = [...a.querySelectorAll('span')].find((s) => s.textContent.trim() === 'Überblick');
      label.textContent = name;
      if (name === active) { a.classList.add('is-active'); }
      group.insertBefore(a, neu);
    }
    const w = document.getElementById('nav-portfolio'); w.classList.remove('is-active');
    // Top bar title.
    document.getElementById('app-topbar-title').textContent = title;
    const subEl = document.getElementById('app-topbar-title').parentElement.querySelector('p, .topbar-subtitle, small');
    if (subEl) subEl.textContent = sub;
    document.getElementById('area-tabs')?.remove();
    // The dashboard's bar replaces the view chips.
    const ctr = document.querySelector('.workspace-section--controls');
    const bar = document.createElement('div'); bar.className = 'mk-bar';
    bar.innerHTML = `<span class="mk-sel">Alles ▾</span><span class="mk-chips"><span>1W</span><span>lfd. Monat</span><span>YTD</span><span class="on">1J</span><span>Max</span></span><span class="mk-btn">Zeitraum ▾</span><span class="mk-sp"></span>` +
      (edit ? `<span class="mk-btn">＋ Widget hinzufügen</span><span class="mk-btn">Zurücksetzen</span><span class="mk-btn acc">Fertig</span>` : `<span class="mk-btn">Bearbeiten</span>`);
    ctr.replaceWith(bar);
    if (edit) document.querySelector('.workspace-page').classList.add('mk-edit');
  }, { CSS, title, sub, active, edit });
}

// Turn an element into a widget card with a header.
const widgetize = `
window.mkW = (el, title, opts = {}) => {
  el.classList.add('mk-w');
  let head = el.querySelector(':scope > .section-head');
  if (!head) {
    head = document.createElement('header'); head.className = 'mk-wh';
    const old = el.querySelector(':scope > h2, :scope > h3, :scope > header h3');
    head.innerHTML = '<h2>' + title + '</h2>';
    if (old) { const oh = old.closest('header') && old.closest('header') !== el ? old.closest('header') : old; const ctrls = oh !== old ? [...oh.children].filter(c => c !== old) : []; ctrls.forEach(c => head.appendChild(c)); oh.remove(); }
    el.prepend(head);
  } else { const h = head.querySelector('h2,h3'); if (h && h.tagName === 'H3') { const n = document.createElement('h2'); n.textContent = title; h.replaceWith(n); } if (opts.rename) head.querySelector('h2').textContent = title; }
  const h2 = head.querySelector('h2');
  if (!head.querySelector('.mk-i') && !head.querySelector('.info-button, [aria-label*="Erkl"], .info-toggle')) { const i = document.createElement('span'); i.className = 'mk-i'; i.textContent = 'i'; h2.after(i); }
  if (opts.follow) { const f = document.createElement('span'); f.className = 'mk-follow'; f.textContent = opts.follow; (head.querySelector('.mk-i') || h2).after(f); }
  const sp = document.createElement('span'); sp.className = 'mk-sp';
  const ctrl = head.querySelector('.section-head-controls, .popover-container');
  if (ctrl) ctrl.before(sp); else head.appendChild(sp);
  const more = document.createElement('span'); more.className = 'mk-more'; more.textContent = '⋯'; head.appendChild(more);
  if (opts.sizes) { const s = document.createElement('span'); s.className = 'mk-sizes'; s.innerHTML = opts.sizes.map(z => '<span' + (z === 'Zeile' ? ' class="on"' : '') + '>' + z + '</span>').join(''); head.appendChild(s); const h = document.createElement('span'); h.className = 'mk-handle'; el.appendChild(h); const x = document.createElement('span'); x.className = 'mk-x'; x.textContent = '×'; el.appendChild(x); }
  if (opts.foot) { const f = document.createElement('div'); f.className = 'mk-foot'; f.innerHTML = opts.foot; el.appendChild(f); }
};`;

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1, locale: 'de-DE' });
  for (const mode of ['plain', 'edit', 'tidy']) {
    const edit = mode === 'edit';
    await p.goto(BASE + '/portfolio?locale=de', { waitUntil: 'networkidle' });
    await p.waitForTimeout(2000);
    await common(p, 'Bestände', 'Dashboard · Start-Dashboard, wie Vermögen › Bestände', 'Bestände', edit);
    await p.evaluate(({ widgetize, edit }) => {
      eval(widgetize);
      const S = edit ? { sizes: ['S', 'W', 'Zeile'] } : {};
      // Kennzahlen
      mkW(document.getElementById('portfolio-kpis'), 'Kennzahlen', { ...S, follow: 'folgt · 1J' });
      // Datenqualität
      mkW(document.getElementById('portfolio-data-quality'), 'Datenhinweise', { ...(edit ? { sizes: ['M', 'Zeile'] } : {}), rename: true });
      // Performance: its own period chips move to the bar; the contribution table becomes its own widget.
      const perf = document.getElementById('portfolio-performance');
      perf.querySelector('[data-role="period-tokens"]')?.remove();
      perf.querySelectorAll('details').forEach((d) => { if (/Benutzerdefiniert/.test(d.textContent)) d.remove(); });
      [...perf.querySelectorAll('summary, button, a')].forEach((d) => { if (/Benutzerdefinierter Zeitraum/.test(d.textContent)) (d.closest('details') || d.parentElement).remove(); });
      const contrib = document.getElementById('performance-contribution');
      const sec = document.createElement('section'); sec.className = 'workspace-section'; perf.after(sec); sec.appendChild(contrib);
      mkW(perf, 'Performance', { ...(edit ? { sizes: ['S', 'M', 'L', 'Zeile'] } : {}), follow: 'folgt · 1J', foot: '<span>Ansicht Alles · TTWROR, Basis im ⓘ</span><a>Ganze Ansicht →</a>' });
      const ch3 = contrib.querySelector('h3'); const chead = ch3 ? ch3.parentElement : null;
      const head = document.createElement('header'); head.className = 'section-head'; head.innerHTML = '<h2>Beitrag je Position</h2>';
      if (chead && chead !== contrib) { [...chead.children].filter(c => c !== ch3).forEach(c => { if (!/ⓘ|^\s*$/.test(c.textContent) || c.tagName !== 'BUTTON') head.appendChild(c); }); chead.remove(); } else if (ch3) ch3.remove();
      sec.prepend(head);
      mkW(sec, 'Beitrag je Position', { ...(edit ? { sizes: ['M', 'L', 'Zeile'] } : {}), follow: 'folgt · 1J' });
      [...sec.querySelector('.section-head, .mk-wh').querySelectorAll('button, span')].forEach((b) => { if (b.textContent.trim() === 'ⓘ') b.remove(); });
      // Positionen: the first 12 rows, the rest behind „Alle anzeigen“.
      const pos = document.getElementById('portfolio-positions');
      const prow = [...pos.querySelectorAll('tbody tr')]; prow.slice(12).forEach((r) => (r.style.display = 'none'));
      pos.querySelectorAll(':scope > p').forEach((x) => x.remove());
      mkW(pos, 'Positionen', { ...(edit ? { sizes: ['M', 'L', 'Zeile'] } : {}), foot: `<span>${prow.length - 12} weitere Positionen ausgeblendet</span><a>Alle ${prow.length} anzeigen →</a>` });
      // Verrechnungskonten: the first 8.
      const cash = document.getElementById('portfolio-cash');
      const crow = [...cash.querySelectorAll('tbody tr')]; crow.slice(8).forEach((r) => (r.style.display = 'none'));
      cash.querySelectorAll(':scope > p').forEach((x) => x.remove());
      mkW(cash, 'Verrechnungskonten', { ...(edit ? { sizes: ['S', 'M', 'Zeile'] } : {}), foot: `<span>${crow.length - 8} weitere Konten</span><a>Alle anzeigen →</a>` });
    }, { widgetize, edit });
    if (mode === 'tidy') await p.evaluate(() => {
      const page = document.querySelector('.workspace-page');
      const kpis = document.getElementById('portfolio-kpis'), dq = document.getElementById('portfolio-data-quality');
      kpis.querySelectorAll('.stat--compact').forEach((e) => e.remove());
      const n = (sel) => dq.querySelectorAll(sel).length;
      const pr = n('.data-note--problem'), at = n('.data-note--attention'), no = n('.data-note--note');
      [...dq.children].forEach((c) => { if (!c.classList.contains('mk-wh') && !c.classList.contains('section-head')) c.remove(); });
      const ul = document.createElement('ul'); ul.className = 'mk-dq'; ul.style.cssText = 'list-style:none;margin:0;padding:0';
      ul.innerHTML = `<li><b class="neg" style="color:var(--color-danger)">${pr}</b> Probleme: Kurse auf zwei Skalen, ein Kurs passt nicht zur Buchung</li><li><b style="color:var(--color-warning)">${at}</b> Achtung: fehlende Kurse und Wechselkurse</li><li><b>${no}</b> Hinweis</li>`;
      dq.appendChild(ul);
      const f = document.createElement('div'); f.className = 'mk-foot'; f.innerHTML = '<span>Größe M</span><a>Prüfen →</a>'; dq.appendChild(f);
      const r1 = document.createElement('div'); r1.className = 'mk-row'; kpis.before(r1); r1.append(kpis, dq);
      const pos = document.getElementById('portfolio-positions'), cash = document.getElementById('portfolio-cash');
      const r2 = document.createElement('div'); r2.className = 'mk-row'; r2.style.gridTemplateColumns = '3fr 2fr'; pos.before(r2); r2.append(pos, cash);
      document.getElementById('app-topbar-title').parentElement.querySelector('p, .topbar-subtitle, small').textContent = 'Dashboard · dasselbe, nach einer Minute „Bearbeiten“';
    });
    await p.waitForTimeout(300);
    await p.screenshot({ path: `dashboard-bestaende${mode === 'plain' ? '' : mode === 'edit' ? '-bearbeiten' : '-angepasst'}.png`, fullPage: !edit });
  }
  // Allocation
  await p.goto(BASE + '/portfolio?tab=allocation&locale=de', { waitUntil: 'networkidle' });
  await p.waitForTimeout(2000);
  await common(p, 'Allokation & Ziele', 'Dashboard · Start-Dashboard, wie Vermögen › Allokation & Ziele', 'Allokation & Ziele', false);
  await p.evaluate(({ widgetize }) => {
    eval(widgetize);
    const k = document.querySelector('.kpi-summary');
    [...k.querySelectorAll('a')].forEach((a) => { if (/Alle Kennzahlen/.test(a.textContent)) a.textContent = 'Alle Kennzahlen → Bestände'; });
    k.classList.add('mk-w'); k.style.display = 'flex';
    const al = document.getElementById('portfolio-allocation');
    mkW(al, 'Allokation', { foot: '<span>Plan „Plan“ auf Strategies · nur Anzeige, kein Auftrag</span><a>Ziele bearbeiten →</a>' });
  }, { widgetize });
  await p.waitForTimeout(300);
  await p.screenshot({ path: 'dashboard-allokation.png', fullPage: true });
  await b.close();
})();
