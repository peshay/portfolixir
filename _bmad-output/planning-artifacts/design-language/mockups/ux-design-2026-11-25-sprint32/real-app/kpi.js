// Mockup only (kpi.js: the Kennzahlen variants, dash.js: the dashboards): loads the real Wealth tabs from a local instance on the
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


const KCSS = `
.kx{display:grid;gap:18px}
.kx .lab{font-size:11px;font-weight:700;letter-spacing:.05em;text-transform:uppercase;color:var(--color-text-muted);margin:0 0 4px}
.kx .big{font-size:34px;font-weight:760;letter-spacing:-.015em;font-variant-numeric:tabular-nums;line-height:1.1}
.kx .big small{font-size:15px;font-weight:600;color:var(--color-text-muted);margin-left:4px}
.kx .val{font-size:24px;font-weight:740;font-variant-numeric:tabular-nums;line-height:1.15}
.kx .sub{font-size:12.5px;color:var(--color-text-muted);margin-top:3px}
.kx .pos{color:var(--color-positive)}
.kx .val small{font-size:13px;font-weight:600;color:var(--color-text-muted);margin-left:4px}
.kx-a{grid-template-columns:minmax(0,1fr) minmax(0,1.35fr)}
.kx-bar{display:flex;height:8px;border-radius:4px;overflow:hidden;margin:12px 0 6px;background:var(--color-bg-muted)}
.kx-bar i{display:block}
.kx-leg{display:flex;gap:16px;font-size:12.5px;color:var(--color-text-muted)}
.kx-leg b{color:var(--color-text);font-weight:650;font-variant-numeric:tabular-nums}
.kx-leg span::before{content:"";display:inline-block;width:8px;height:8px;border-radius:2px;margin-right:6px;background:var(--c)}
.kx-three{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:0;border-left:1px solid var(--color-border)}
.kx-three>div{padding:2px 18px;border-right:1px solid var(--color-border)}
.kx-three>div:last-child{border-right:0}
.kx-bridge{grid-column:1 / -1;display:flex;align-items:center;gap:10px;flex-wrap:wrap;padding:10px 14px;border-radius:10px;background:var(--color-bg-muted);font-size:13px;color:var(--color-text-muted)}
.kx-bridge b{color:var(--color-text);font-variant-numeric:tabular-nums;font-weight:650}
.kx-bridge .op{font-weight:700;color:var(--color-text-subtle,#94a3b8)}
.kx-bridge .end{margin-left:auto}
.kx-b{grid-template-columns:1.4fr repeat(4,minmax(0,1fr));gap:0}
.kx-b>div{padding:2px 18px;border-left:1px solid var(--color-border)}
.kx-b>div:first-child{padding-left:0;border-left:0}
.kx-more{margin-top:12px;font-size:12.5px;color:var(--color-text-muted)}
.kx-more a{color:var(--color-accent);font-weight:600}
`;
const A = `<div class="kx kx-a">
 <div><div class="lab">Gesamtwert</div><div class="big">88.307,02<small>EUR</small></div>
  <div class="kx-bar"><i style="width:78.3%;background:var(--color-accent)"></i><i style="width:21.7%;background:#0ea5e9"></i></div>
  <div class="kx-leg"><span style="--c:var(--color-accent)">Wertpapiere <b>69.128,26</b></span><span style="--c:#0ea5e9">Cash <b>19.178,75</b> · 21,7 %</span></div></div>
 <div class="kx-three">
  <div><div class="lab">Ergebnis · 1J</div><div class="val pos">+7.348,65<small>EUR</small></div><div class="sub">nach Zu- und Abflüssen</div></div>
  <div><div class="lab">TTWROR · 1J</div><div class="val pos">+8,0 %</div><div class="sub">zeitgewichtet</div></div>
  <div><div class="lab">IRR · 1J</div><div class="val pos">+9,4 %</div><div class="sub">geldgewichtet, p. a.</div></div>
 </div>
 <div class="kx-bridge"><span>Anfang 25.11.2025 <b>76.617,17</b></span><span class="op">+</span><span>Nettoflüsse <b>4.341,20</b></span><span class="op">+</span><span>Ergebnis <b class="pos" style="color:var(--color-positive)">7.348,65</b></span><span class="op">=</span><span>heute <b>88.307,02 EUR</b></span><span class="end">Multiplikator <b>×1,09</b></span></div>
</div>`;
const B = `<div class="kx kx-b">
 <div><div class="lab">Gesamtwert</div><div class="big">88.307,02<small>EUR</small></div><div class="sub">Wertpapiere 69.128,26 · Cash 19.178,75</div></div>
 <div><div class="lab">Ergebnis · 1J</div><div class="val pos">+7.348,65</div><div class="sub">EUR, nach Flüssen</div></div>
 <div><div class="lab">TTWROR · 1J</div><div class="val pos">+8,0 %</div><div class="sub">zeitgewichtet</div></div>
 <div><div class="lab">IRR · 1J</div><div class="val pos">+9,4 %</div><div class="sub">p. a.</div></div>
 <div><div class="lab">Cashquote</div><div class="val">21,7 %</div><div class="sub">19.178,75 EUR</div></div>
</div><div class="kx-more">Anfangswert, Nettoflüsse und Multiplikator: <a>weitere Kennzahlen ▾</a></div>`;

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 2, locale: 'de-DE' });
  for (const [name, html] of [['heute', null], ['A', A], ['B', B]]) {
    for (const theme of ['light', 'dark']) {
      if (name === 'heute' && theme === 'dark') continue;
      await p.goto(BASE + '/portfolio?locale=de', { waitUntil: 'networkidle' });
      await p.waitForTimeout(1500);
      await common(p, 'Bestände', 'Dashboard · Start-Dashboard, wie Vermögen › Bestände', 'Bestände', false);
      const box = await p.evaluate(({ widgetize, html, KCSS, theme }) => {
        eval(widgetize);
        document.documentElement.setAttribute('data-theme', theme);
        const st = document.createElement('style'); st.textContent = KCSS; document.head.appendChild(st);
        const k = document.getElementById('portfolio-kpis');
        mkW(k, 'Kennzahlen', { follow: 'folgt · 1J' });
        if (html) { [...k.children].forEach((c) => { if (!c.classList.contains('mk-wh')) c.remove(); }); k.insertAdjacentHTML('beforeend', html); k.style.display = 'block'; }
        const r = k.getBoundingClientRect();
        return { y: 0, h: r.bottom + 14 };
      }, { widgetize, html, KCSS, theme });
      await p.screenshot({ path: `kpi-${name}${theme === 'dark' ? '-dark' : ''}.png`, clip: { x: 0, y: 0, width: 1280, height: box.h } });
    }
  }
  await b.close();
})();
