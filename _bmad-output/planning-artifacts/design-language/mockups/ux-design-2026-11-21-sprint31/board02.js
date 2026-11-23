// Board 02 of Sprint 31: the closing act's accessibility and design
// findings on the dashboard (Y1 to Y5, DS1 to DS5 and the smaller ones),
// each visible change drawn before and after. Two frames (⑧) were drawn
// after the code: fix batch 1 had already built them. ⑩ draws the UAT
// persona's findings of 2026-11-23, before and after, before the code.
// Synthetic names and figures only. Called by build.js with the idea board's helpers.
'use strict';

const CSS = `<style>
.cl-pair { display: grid; grid-template-columns: 1fr 1fr; gap: 18px; align-items: start; }
.cl-pair.wide { grid-template-columns: 1fr; }
.cl-col > .mock-tag { margin-bottom: 6px; }
.cl-row { display: flex; gap: 12px; align-items: stretch; flex-wrap: wrap; }
.cl-w { position: relative; display: flex; flex-direction: column; gap: 8px; box-sizing: border-box; min-width: 0; padding: 12px 16px; border: 1px solid var(--color-border); border-radius: var(--radius-lg); background: var(--color-bg-elevated); box-shadow: var(--shadow-sm); font-size: 13px; }
.cl-w.s { width: 222px; }
.cl-w.m { width: 456px; }
.cl-w.t { width: 300px; }
.cl-w.budget-s { min-height: 112px; }
.cl-w.budget-m { min-height: 236px; }
.cl-w.edit { outline: 1.5px dashed var(--color-accent); outline-offset: -1px; }
.cl-h { display: flex; align-items: flex-start; gap: 6px; }
.cl-h .t { display: flex; flex-wrap: wrap; align-items: center; gap: 2px 6px; flex: 1; }
.cl-h h4 { margin: 0; font-size: 15px; font-weight: 700; line-height: 1.2; }
.cl-h.before h4 { font-size: 17px; }
.cl-i { display: inline-grid; place-items: center; width: 16px; height: 16px; border-radius: 50%; border: 1px solid var(--color-border-strong); color: var(--color-text-muted); font-size: 10px; font-weight: 700; }
.cl-tag { padding: 1px 8px; border: 1px solid var(--color-border); border-radius: 999px; color: var(--color-text-muted); font-size: 12px; font-weight: 600; white-space: nowrap; }
.cl-tag.none { border-style: dashed; border-color: var(--color-border-strong); }
.cl-tag.right { margin-left: auto; }
.cl-tag.under { flex-basis: 100%; width: max-content; max-width: max-content; }
.cl-more { color: var(--color-text-muted); font-weight: 700; letter-spacing: 1px; }
.cl-foot { display: flex; justify-content: space-between; gap: 8px; margin-top: auto; padding-top: 6px; border-top: 1px solid var(--color-border); color: var(--color-text-muted); font-size: 13px; }
.cl-foot.float { margin-top: 0; }
.cl-foot a { margin-left: auto; color: var(--color-accent); font-weight: 600; }
.cl-fig { font-size: 26px; font-weight: 760; font-variant-numeric: tabular-nums; letter-spacing: -.015em; line-height: 1.1; }
.cl-fig small { margin-left: 4px; font-size: 14px; font-weight: 600; color: var(--color-text-muted); }
.cl-sub { color: var(--color-text-muted); font-size: 12.5px; line-height: 1.4; }
.cl-warn { color: var(--color-warning); font-size: 12.5px; line-height: 1.4; }
.cl-stat { padding: 10px 12px; border: 1px solid var(--color-border); border-radius: 10px; box-shadow: var(--shadow-sm); }
.cl-stat .k { font-size: 11px; font-weight: 700; letter-spacing: .06em; text-transform: uppercase; color: var(--color-text-muted); }
.cl-list { margin: 0; padding: 0; list-style: none; }
.cl-list li { display: flex; justify-content: space-between; gap: 8px; padding: 4px 0; border-bottom: 1px solid var(--color-border); }
.cl-list li:last-child { border-bottom: 0; }
.cl-seg { display: inline-flex; padding: 2px; border-radius: var(--radius-md); background: var(--color-bg-muted); font-size: 12.5px; font-weight: 600; }
.cl-seg span { padding: 3px 10px; border-radius: var(--radius-sm); color: var(--color-text-muted); }
.cl-seg span.on { background: var(--color-bg-elevated); color: var(--color-text); box-shadow: var(--shadow-sm); }
.cl-two { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
.cl-two h5, .cl-col5 h5 { margin: 0 0 2px; font-size: 11px; letter-spacing: .06em; text-transform: uppercase; color: var(--color-text-muted); }
.pos { color: var(--color-positive); }
.neg { color: var(--color-danger); }
.cl-note { margin: 6px 0 0; font-size: 12px; color: var(--color-text-muted); }
.cl-band { height: 44px; margin: 0 0 4px; border: 1px dashed var(--color-danger); border-radius: 6px; display: grid; place-items: center; color: var(--color-danger); font-size: 12px; }
.cl-bar { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; font-size: 13px; }
.cl-btn { display: inline-flex; align-items: center; padding: 0 12px; height: 34px; border: 1px solid var(--color-border-strong); border-radius: var(--radius-md); background: var(--color-bg-elevated); font-weight: 600; }
.cl-btn.acc { background: var(--color-accent); border-color: var(--color-accent); color: var(--color-on-accent); }
.cl-btn.t44 { height: 44px; }
.cl-chips { display: inline-flex; border: 1px solid var(--color-border); border-radius: var(--radius-md); overflow: hidden; }
.cl-chips span { padding: 0 9px; height: 30px; display: grid; place-items: center; border-right: 1px solid var(--color-border); font-size: 12.5px; color: var(--color-text-muted); }
.cl-chips span:last-child { border-right: 0; }
.cl-chips span.on { background: var(--color-accent); color: var(--color-on-accent); }
.cl-chips.t44 span { height: 44px; min-width: 44px; box-sizing: border-box; font-size: 15px; }
.cl-dim { font-size: 11px; font-weight: 700; color: var(--color-accent); }
.cl-phone { position: relative; width: 393px; border: 1px solid var(--color-border-strong); border-radius: 18px; overflow: hidden; background: var(--color-bg); }
.cl-phone .in { padding: 12px 16px; display: grid; gap: 10px; }
.cl-shadow { position: absolute; top: 0; bottom: 0; left: 0; width: 18px; background: linear-gradient(to right, rgb(15 23 42 / .16), transparent); }
.cl-page { position: relative; display: flex; gap: 12px; padding: 12px; border: 1px solid var(--color-border-strong); border-radius: 10px; background: var(--color-bg); overflow: hidden; }
.cl-grid { flex: 1; display: grid; grid-template-columns: repeat(12, minmax(0, 1fr)); gap: 8px; min-width: 0; }
.cl-grid > div { min-height: 56px; border: 1.5px dashed var(--color-accent); border-radius: 8px; background: var(--color-bg-elevated); padding: 6px 8px; font-size: 11.5px; font-weight: 700; overflow: hidden; }
.cl-grid .clip { color: var(--color-danger); }
.cl-cat { width: 176px; flex: none; padding: 8px 10px; border: 1px solid var(--color-border-strong); border-radius: 10px; background: var(--color-bg-elevated); font-size: 12px; }
.cl-cat.drawer { position: absolute; top: 0; right: 0; bottom: 0; border-radius: 10px 0 0 10px; box-shadow: -10px 0 30px rgb(15 23 42 / .2); }
.cl-cat b { display: block; margin-bottom: 4px; font-size: 13px; }
.cl-cat div { display: flex; justify-content: space-between; align-items: center; padding: 3px 0; }
.cl-sz { display: inline-flex; gap: 3px; }
.cl-sz i { font-style: normal; padding: 0 5px; border: 1px solid var(--color-border-strong); border-radius: 4px; font-size: 10.5px; font-weight: 700; color: var(--color-text-muted); }
.cl-bare { font-size: 10.5px; font-weight: 700; color: var(--color-text-muted); }
.cl-table { width: 100%; border-collapse: collapse; font-size: 12.5px; }
.cl-table th, .cl-table td { padding: 4px 6px; border-bottom: 1px solid var(--color-border); text-align: left; vertical-align: top; }
.cl-table th { font-size: 11px; color: var(--color-text-muted); text-transform: uppercase; letter-spacing: .05em; }
.cl-table .num { text-align: right; font-variant-numeric: tabular-nums; }
.cl-table .nw { white-space: nowrap; }
.cl-narrow { width: 50px; display: inline-block; }
.cl-rail { width: 72px; flex: none; border-right: 1px solid var(--color-border); padding: 8px 0; display: grid; gap: 10px; justify-items: center; font-size: 12px; text-align: center; }
.cl-rail span { display: block; width: 72px; overflow: hidden; }
.cl-rail.after span { width: 64px; font-size: 12px; line-height: 1.15; overflow-wrap: anywhere; hyphens: auto; }
.cl-top { display: flex; align-items: center; gap: 12px; padding: 8px 12px; border-bottom: 1px solid var(--color-border); font-weight: 700; }
.cl-search { padding: 6px 10px; border: 1px solid var(--color-border-strong); border-radius: var(--radius-md); color: var(--color-text-muted); font-size: 12.5px; min-width: 180px; font-weight: 400; }
.cl-choice { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; font-size: 13px; }
.cl-choice > div { border: 1px solid var(--color-border); border-radius: 10px; padding: 10px; background: var(--color-bg-elevated); }
.cl-choice > div.on { border-color: var(--color-accent); box-shadow: 0 0 0 1px var(--color-accent); }
.cl-arrow { font-size: 20px; color: var(--color-accent); align-self: center; }
.cl-drawn-after { border-left: 4px solid var(--color-warning); padding-left: 10px; }
.u-sheet { position: relative; border: 1px solid var(--color-border-strong); border-radius: 14px; overflow: hidden; background: var(--color-bg); }
.u-sheet .sh { padding: 10px 14px; background: var(--color-bg-elevated); border-radius: 14px 14px 0 0; box-shadow: 0 -8px 24px rgb(15 23 42 / .14); font-size: 15px; }
.u-sheet .sh b.t { display: block; font-size: 17px; margin-bottom: 2px; }
.u-sheet .sh h5 { margin: 8px 0 2px; font-size: 12px; letter-spacing: .06em; text-transform: uppercase; color: var(--color-text-muted); }
.u-sheet .sh div.it { display: flex; align-items: center; min-height: 40px; border-bottom: 1px solid var(--color-border); }
.u-sheet .sh div.it.out { color: var(--color-danger); font-weight: 600; border-bottom: 0; }
.u-tabs { display: grid; grid-template-columns: repeat(4, 1fr); border-top: 1px solid var(--color-border); background: var(--color-bg-elevated); font-size: 12px; text-align: center; padding: 6px 0; }
.u-tabs span.on { color: var(--color-accent); font-weight: 700; }
.u-win { position: relative; width: 422px; height: 195px; border: 1px solid var(--color-border-strong); border-radius: 10px; overflow: hidden; background: var(--color-bg); font-size: 12px; }
.u-win .rail { position: absolute; top: 0; bottom: 0; left: 0; border-right: 1px solid var(--color-border); background: var(--color-bg-elevated); display: grid; align-content: start; gap: 6px; padding-top: 6px; text-align: center; }
.u-win .more { position: absolute; top: 0; left: 0; width: 180px; background: var(--color-bg-elevated); box-shadow: 8px 0 24px rgb(15 23 42 / .16); padding: 6px 10px; font-size: 12px; }
.u-win .more div { padding: 3px 0; border-bottom: 1px solid var(--color-border); }
.u-win .more h6 { margin: 4px 0 0; font-size: 9.5px; letter-spacing: .06em; text-transform: uppercase; color: var(--color-text-muted); }
.u-cut { position: absolute; left: 0; right: 0; bottom: 0; height: 2px; background: var(--color-danger); }
.u-scroll { position: absolute; top: 6px; bottom: 6px; right: 2px; width: 4px; border-radius: 2px; background: var(--color-border-strong); }
.u-scroll::after { content: ""; position: absolute; left: 0; right: 0; top: 0; height: 55%; border-radius: 2px; background: var(--color-text-muted); }
.u-plot { height: 120px; border: 1px dashed var(--color-border-strong); border-radius: 6px; position: relative; color: var(--color-text-muted); font-size: 11px; }
.u-plot span { position: absolute; }
.u-quiet { color: var(--color-text-muted); font-size: 12.5px; font-style: normal; }
.u-bar { display: flex; align-items: center; gap: 8px; padding: 8px 10px; border-bottom: 1px solid var(--color-border); background: var(--color-bg); font-size: 13px; }
.u-drawer { position: absolute; right: 0; width: 190px; padding: 8px 10px; border: 1px solid var(--color-border-strong); border-radius: 10px 0 0 10px; background: var(--color-bg-elevated); box-shadow: -10px 0 30px rgb(15 23 42 / .2); font-size: 12px; }
.u-drawer div { padding: 3px 0; display: flex; justify-content: space-between; }
.u-hidden { color: var(--color-danger); text-decoration: line-through; }
.u-top { display: flex; align-items: center; gap: 10px; padding: 0 10px; height: 44px; border-bottom: 1px solid var(--color-border); background: var(--color-bg-elevated); }
.u-top .pg { display: grid; line-height: 1.15; }
.u-top .pg b { font-size: 15px; }
.u-top .pg small { font-size: 11px; color: var(--color-text-muted); }
</style>`;

module.exports.board02 = function board02(I) {
  const { page, SYN, spark, total } = I;
  const sp = (w = 190, h = 28) => spark(total.slice(-60), w, h);
  const tagBefore = (t, none) => `<span class="cl-tag right${none ? ' none' : ''}">${t}</span>`;
  // The head before (17 px, the tag at the title's end) and after (15 px,
  // the ⓘ on the title's line, the tag under it; no tag without a period).
  const headBefore = (t, tag, none) => `<div class="cl-h before"><div class="t"><h4>${t}</h4><span class="cl-i">i</span>${tag ? tagBefore(tag, none) : ''}</div><span class="cl-more">⋯</span></div>`;
  const headAfter = (t, tag) => `<div class="cl-h"><div class="t"><h4>${t}</h4><span class="cl-i">i</span>${tag ? `<span class="cl-tag under">${tag}</span>` : ''}</div><span class="cl-more">⋯</span></div>`;
  const pair = (before, after, wide) => `<div class="cl-pair${wide ? ' wide' : ''}"><div class="cl-col"><span class="mock-tag mock-tag--before">vorher</span>${before}</div><div class="cl-col"><span class="mock-tag mock-tag--rec">nachher</span>${after}</div></div>`;

  // ---- DS1 / DS2 / DS3: the S row ----
  const totalBefore = `<div class="cl-w s">${headBefore('Gesamtwert', 'folgt · 1J')}<div class="cl-warn">⚠ Nicht in der Summe: 2 Verrechnungskonten, 1 Position ohne Preis. <b style="color:var(--color-accent)">Details in Vermögen →</b></div><div class="cl-stat"><div class="k">Alles</div><div class="cl-fig">124.310,55</div><div class="cl-sub">EUR</div><div class="cl-sub"><span class="pos">+6,4 %</span> TTWROR · 1J</div></div>${sp()}<div class="cl-foot float"><span>Ansicht Alles</span></div><div style="text-align:right"><a style="color:var(--color-accent);font-weight:600;font-size:13px">In Vermögen ansehen →</a></div><div style="height:90px"></div></div>`;
  const totalAfter = `<div class="cl-w s budget-s">${headAfter('Gesamtwert', 'folgt · 1J')}<div class="cl-fig">124.310,55<small>EUR</small></div><div class="cl-sub"><span class="pos">+6,4 %</span> TTWROR · 1J</div>${sp(190, 26)}<div class="cl-warn">⚠ Nicht in der Summe: 2 Verrechnungskonten, 1 Position ohne Preis. <b style="color:var(--color-accent)">Details →</b></div><div class="cl-foot"><span>Ansicht Alles</span><a>In Vermögen →</a></div></div>`;
  const offBefore = `<div class="cl-w s">${headBefore('Abseits des Ziels', 'ohne Zeitraum', true)}<div class="cl-sub">Ansicht Alles · Plan „Basis“ auf Strategie · Kategorien, die mehr als ±5 Pkt. von ihrem Soll-Gewicht abweichen.</div><ul class="cl-list">${[['Wachstum', '−21,4'], ['Kern', '−12,0'], ['Stabil', '−6,8'], ['Rohstoffe', '−5,2']].map(([n, d]) => `<li style="display:block">${n}<div class="neg">${d} Pkt. unter dem Soll · −9.120,00 EUR</div></li>`).join('')}</ul><div class="cl-foot"><span>Ansicht Alles</span><a>In Vermögen →</a></div></div>`;
  const offAfter = `<div class="cl-w s budget-s">${headAfter('Abseits des Ziels')}<div class="cl-fig">4<small>Kategorien</small></div><div class="cl-sub">außerhalb ±5 Pkt. · Plan „Basis“ auf Strategie</div><div class="cl-foot"><span>Ansicht Alles</span><a>In Vermögen →</a></div></div>`;
  const offM = `<div class="cl-w m budget-m">${headAfter('Abseits des Ziels')}<div class="cl-sub">Ansicht Alles · Plan „Basis“ auf Strategie · Kategorien ±5 Pkt. oder mehr neben ihrem Soll, auf jeder Ebene des Baums.</div><ul class="cl-list">${[['Wachstum', '−21,4', '−9.120,00'], ['Kern', '−12,0', '−5.110,40'], ['Stabil', '−6,8', '−2.896,10'], ['Rohstoffe', '+5,2', '+2.214,70']].map(([n, d, e]) => `<li><span>${n}</span><span class="${d[0] === '+' ? '' : 'neg'}">${d} Pkt. · ${e} EUR</span></li>`).join('')}</ul><div class="cl-foot"><span>Ansicht Alles</span><a>In Vermögen →</a></div></div>`;
  const dqBefore = `<div class="cl-w s">${headBefore('Datenqualität', 'ohne Zeitraum', true)}<ul class="cl-list"><li>● 4 Kurse älter als 7 Tage</li><li>● 2 Wertpapiere ohne Logo</li></ul><div style="text-align:right"><a style="color:var(--color-accent);font-weight:600">Prüfen →</a></div><div style="height:60px"></div></div>`;
  const dqAfter = `<div class="cl-w s budget-s">${headAfter('Datenqualität')}<ul class="cl-list"><li>● 4 Kurse älter als 7 Tage</li><li>● 2 Wertpapiere ohne Logo</li></ul><div class="cl-foot"><span></span><a>Prüfen →</a></div></div>`;

  // ---- DS1: Tops und Flops at M ----
  const names = [['Halbleiter Nord', '+18,2 %', '+1.204,10'], ['Welt-ETF Alpha', '+9,6 %', '+980,40'], ['Netz Versorger', '+7,1 %', '+412,00'], ['Pharma Süd', '+4,3 %', '+220,15'], ['Bank West', '+2,0 %', '+101,30']];
  const lows = [['Krypto-Münze', '−11,2 %', '−860,00'], ['Autobauer Ost', '−6,4 %', '−390,20'], ['Rohstoff-ETC', '−3,9 %', '−170,05'], ['Bau Mitte', '−1,8 %', '−61,90'], ['Reederei Kap', '−0,4 %', '−12,30']];
  const col5 = (h, rows, i) => `<div class="cl-col5"><h5>${h}</h5><ul class="cl-list">${rows.map((r) => `<li><span>${r[0]}</span><span class="${r[i][0] === '+' ? 'pos' : 'neg'}">${r[i]}${i === 2 ? ' EUR' : ''}</span></li>`).join('')}</ul></div>`;
  const moversBefore = `<div class="cl-w m">${headBefore('Tops und Flops', 'folgt · 1J')}<div class="cl-sub">Ansicht Alles · 1J: Schlusskurs 22.11.2025 bis 22.11.2026 · in EUR</div><b>Kursrendite</b>${col5('Höchste', names, 1)}${col5('Niedrigste', lows, 1)}<div class="cl-sub">3 ohne Kursrendite: 3 ohne Kurs zu Beginn</div><b>Beitrag</b>${col5('Höchste', names, 2)}${col5('Niedrigste', lows, 2)}<div class="cl-sub">2 Positionen ohne Beitrag im Zeitraum</div><div class="cl-foot"><span>Ansicht Alles</span><a>In Vermögen ansehen →</a></div></div>`;
  const moversAfter = `<div class="cl-w m budget-m">${headAfter('Tops und Flops', 'folgt · 1J')}<div class="cl-sub">Ansicht Alles · 1J: Schlusskurs 22.11.2025 bis 22.11.2026 · in EUR</div><div><span class="cl-seg"><span class="on">Kursrendite</span><span>Beitrag</span></span></div><div class="cl-two">${col5('Höchste', names.slice(0, 4), 1)}${col5('Niedrigste', lows.slice(0, 4), 1)}</div><div class="cl-sub">3 ohne Kursrendite: 3 ohne Kurs zu Beginn</div><div class="cl-foot"><span>Ansicht Alles</span><a>In Vermögen →</a></div></div>`;

  // ---- DS2: the blank band ----
  const bandBefore = `<div class="mock-frame"><div class="cl-bar"><span class="cl-btn">Alles ▾</span><span style="flex:1"></span><span class="cl-chips"><span>1M</span><span>YTD</span><span class="on">1J</span><span>Max</span></span><span class="cl-btn">Bearbeiten</span></div><div class="cl-band">≈ 44 px leer: zwei leere Statusbereiche nehmen je einen Abstand</div><div class="cl-row"><div class="cl-w s" style="min-height:60px">${headBefore('Gesamtwert')}</div><div class="cl-w s" style="min-height:60px">${headBefore('Fällig')}</div></div></div>`;
  const bandAfter = `<div class="mock-frame"><div class="cl-bar"><span class="cl-btn">Alles ▾</span><span style="flex:1"></span><span class="cl-chips"><span>1M</span><span>YTD</span><span class="on">1J</span><span>Max</span></span><span class="cl-btn">Bearbeiten</span></div><div style="height:12px"></div><div class="cl-row"><div class="cl-w s" style="min-height:60px">${headAfter('Gesamtwert', 'folgt · 1J')}</div><div class="cl-w s" style="min-height:60px">${headAfter('Fällig')}</div></div><p class="cl-note">Ein leerer Statusbereich steht außerhalb des Flusses, wie schon „#dashboard-edit-status“; sein Text erscheint dort, wo er heute erscheint.</p></div>`;

  // ---- DS4: the edit mode at 1200 ----
  const cells = (clip) => `<div style="grid-column:span 3">Gesamtwert</div><div style="grid-column:span 3">Datenqualität</div><div style="grid-column:span 3">Fällig</div><div style="grid-column:span 3"${clip ? ' class="clip"' : ''}>Abseits d…${clip ? ' ✂' : ''}</div><div style="grid-column:span 8;min-height:120px">Wertentwicklung</div><div style="grid-column:span 4;min-height:120px"${clip ? ' class="clip"' : ''}>Allokation und Drift${clip ? ' ✂ Tabelle abgeschnitten' : ''}</div>`;
  const catalogue = (drawer, chips) => `<div class="cl-cat${drawer ? ' drawer' : ''}"><b>Widget hinzufügen${drawer ? ' <span style="float:right;color:var(--color-text-muted)">×</span>' : ''}</b>${[['Gesamtwert', 'S M'], ['Datenqualität', 'S M'], ['Abseits des Ziels', 'S M'], ['Wertentwicklung', 'S M L'], ['Tops und Flops', 'S M']].map(([n, z]) => `<div><span>${n}</span>${chips ? `<span class="cl-sz">${z.split(' ').map((x) => `<i>${x}</i>`).join('')}</span>` : `<span class="cl-bare">${z}</span>`}</div>`).join('')}</div>`;
  const editBefore = `<div class="cl-page"><div class="cl-grid">${cells(true)}</div>${catalogue(false, false)}</div><p class="cl-note">Die Katalog-Spalte drückt das Raster von 924 auf 668 px: Inhalte laufen aus dem Rahmen.</p>`;
  const editAfter = `<div class="cl-page" style="min-height:250px"><div style="flex:1;display:grid;gap:8px;align-content:start"><div class="cl-bar"><span style="flex:1"></span><span class="cl-btn">+ Widget hinzufügen</span><span class="cl-btn">Zurücksetzen</span><span class="cl-btn acc">Fertig</span></div><div class="cl-grid">${cells(false)}</div></div>${catalogue(true, true)}</div><p class="cl-note">Unter 1400 px öffnet „+ Widget hinzufügen“ den Katalog als Schublade über der Seite (× oder Esc schließt sie, der Fokus kehrt zum Knopf zurück); die Widgets behalten ihre Breite. Ab 1400 px steht er wie bisher neben dem Raster. Die Größen stehen als Chips wie auf „Alle Widgets“.</p>`;

  // ---- DS5: crashes and the cycle ----
  const crashBefore = `<div class="cl-w m">${headBefore('Crashes im Vergleich', 'ohne Zeitraum', true)}<table class="cl-table"><tr><th>Fenster</th><th class="num">Benchmark</th><th>Niedrigste im Depot</th></tr><tr><td>Herbst-Dip</td><td class="num neg">−2,4 %</td><td>Welt-ETF Alpha <span class="cl-narrow neg">−3,1<br>%</span></td></tr><tr><td>Zinsschock</td><td class="num neg">−11,5 %</td><td>Bank West <span class="neg">−4,0%</span></td></tr></table></div>`;
  const crashAfter = `<div class="cl-w m">${headAfter('Crashes im Vergleich')}<table class="cl-table"><tr><th>Fenster</th><th class="num">Benchmark</th><th>Niedrigste im Depot</th></tr><tr><td>Herbst-Dip</td><td class="num neg nw">−2,4 %</td><td>Welt-ETF Alpha <span class="neg nw">−3,1 %</span></td></tr><tr><td>Zinsschock</td><td class="num neg nw">−11,5 %</td><td>Bank West <span class="neg nw">−4,0 %</span></td></tr></table><div class="cl-sub">Eine Zahl bricht nie um; jedes Prozent wie in den anderen Widgets („−3,1 %“).</div></div>`;
  const cycleBefore = `<div class="cl-w m">${headBefore('Bitcoin-Zyklus', 'ohne Zeitraum', true)}<div style="display:flex;justify-content:space-between;align-items:baseline"><h3 style="margin:0;font-size:20px">Ferncoin-Zyklus</h3><a style="color:var(--color-accent);font-weight:600">Im Chart öffnen →</a></div><div class="cl-sub"><b>Nächstes Tief</b> 21.06.2026 – 24.06.2027 · 300 – 383 USD · n = 3</div><div class="cl-sub"><b>Nächstes Top</b> 24.08.2027 – 22.12.2028 · 4.500 – 5.600 USD · n = 4</div></div>`;
  const cycleAfter = `<div class="cl-w m">${headAfter('Bitcoin-Zyklus')}<div class="cl-sub" style="font-size:13px;color:var(--color-text)">Ferncoin</div><div class="cl-sub"><b>Nächstes Tief</b> 21.06.2026 – 24.06.2027 · 300 – 383 USD · n = 3</div><div class="cl-sub"><b>Nächstes Top</b> 24.08.2027 – 22.12.2028 · 4.500 – 5.600 USD · n = 4</div><div class="cl-foot"><span></span><a>Ganze Ansicht →</a></div></div><p class="cl-note">Die Überschriften folgen h1 → h2 (Titel des Rahmens); der Name ist eine Unterzeile.</p>`;

  // ---- Y5 / Y2: compact 393 ----
  const phoneBefore = `<div class="cl-phone"><div class="cl-shadow"></div><div class="in"><div class="cl-bar"><span class="cl-btn" style="height:32px">Alles ▾</span><span class="cl-dim">32</span><span style="flex:1"></span><span class="cl-btn">Bearbeiten</span><span class="cl-dim">34</span></div><div class="cl-bar"><span class="cl-chips t44"><span style="min-width:41px">1T</span><span style="min-width:41px">1W</span><span style="min-width:41px">1M</span><span style="min-width:41px">3M</span><span>YTD</span><span class="on">1J</span><span>3J</span></span><span class="cl-dim">41 breit</span></div><div class="cl-w" style="width:auto"><div class="cl-h before"><div class="t"><h4>Wertentwicklung</h4><span class="cl-i" style="width:28px;height:28px">i</span><span class="cl-dim">28</span></div></div><div class="cl-foot float"><span>Ansicht Alles</span><a style="line-height:18px">Ganze Ansicht →</a><span class="cl-dim">18</span></div></div><p class="cl-note">Links: der Schatten der versteckten Seitenleiste blutet ins Bild; 13 unsichtbare Tab-Stopps (Seitenleiste und ihr Schalter) kommen vor dem ersten sichtbaren.</p></div></div>`;
  const phoneAfter = `<div class="cl-phone"><div class="in"><div class="cl-bar"><span class="cl-btn t44">Alles ▾</span><span style="flex:1"></span><span class="cl-btn t44">Bearbeiten</span></div><div class="cl-bar"><span class="cl-chips t44"><span>1T</span><span>1W</span><span>1M</span><span>3M</span><span>YTD</span><span class="on">1J</span><span>3J</span></span></div><div class="cl-w" style="width:auto"><div class="cl-h"><div class="t"><h4 style="font-size:17px">Wertentwicklung</h4><span class="cl-i" style="width:44px;height:44px;border:0"><span class="cl-i">i</span></span></div><span class="cl-more" style="width:44px;text-align:center">⋯</span></div><div class="cl-foot"><span style="line-height:44px">Ansicht Alles</span><a style="line-height:44px">Ganze Ansicht →</a></div></div><p class="cl-note">Jedes Ziel mindestens 44 × 44 px: Bereich, Bearbeiten, Zurücksetzen, die Chips, ⓘ, ⋯ und die Fußlinks; „hinzufügen ›“ auf „Alle Widgets“ ebenso. Kein Schatten, keine unsichtbaren Tab-Stopps: wo die Tab-Leiste oder die Seitenschiene das Menü ist, sind Seitenleiste und Schalter verborgen (<code>display: none</code>, solange die Schublade zu ist). Der fokussierte Chip rollt in die Leiste. Die kompakten Schriftgrößen bleiben (Entscheidung des Owners).</p></div></div>`;

  // ---- also: /widgets search, the rail, the empty catalogue, „Leer beginnen“ ----
  const widgetsBefore = `<div class="cl-page" style="display:block;padding:0"><div class="cl-top">Alle Widgets</div><div style="padding:0 12px"><span class="cl-search" style="display:inline-block;border-top-left-radius:0;border-top-right-radius:0">Suchen …</span></div><div style="padding:10px 12px" class="cl-sub">ÜBERBLICK …</div></div>`;
  const widgetsAfter = `<div class="cl-page" style="display:block;padding:0"><div class="cl-top">Alle Widgets</div><div style="display:flex;align-items:center;gap:12px;padding:12px"><span style="flex:1" class="cl-sub">Jedes Widget, das ein Dashboard aufnehmen kann, nach Thema</span><span class="cl-search">Suchen …</span></div><div style="padding:0 12px 10px" class="cl-sub">ÜBERBLICK …</div></div>`;
  const rail = (after) => `<div class="cl-page" style="height:170px;padding:0"><div class="cl-rail${after ? ' after' : ''}">${['▦<span>Dashboards</span>', '◎<span>Wertpapiere</span>', '☰<span>Nachrichten</span>', '⋯<span>Mehr</span>'].map((x) => `<div>${x}</div>`).join('')}</div><div style="padding:10px" class="cl-sub">844 × 390: die Schiene ist 72 px breit${after ? '; die Beschriftung bricht innerhalb von 64 px um, nie unter 12 px' : '; „Wertpapiere“ und „Nachrichten“ stoßen an beide Ränder'}.</div></div>`;
  const leerBefore = `<div class="mock-frame"><div class="cl-choice"><div class="on"><b>Leer beginnen</b></div><div><b>Aus Vorlage</b></div></div><p class="cl-note">„Anlegen“ öffnet das leere Dashboard mit „Dieses Dashboard ist leer …“; „Bearbeiten“ ist ein zweiter Schritt.</p></div>`;
  const leerAfter = `<div class="mock-frame"><div class="cl-choice"><div class="on"><b>Leer beginnen</b><div class="cl-sub">öffnet den Bearbeitungsmodus mit dem Katalog</div></div><div><b>Aus Vorlage</b></div></div><p class="cl-note">„Anlegen“ öffnet das neue Dashboard im Bearbeitungsmodus, der Katalog offen (Board 01 ③); der Fokus steht auf „Widget hinzufügen“.</p></div>`;

  // ---- ⑨ the S forms of three list widgets (the coordinator's follow-up) ----
  const totalS1 = `<div class="cl-w s">${headAfter('Gesamtwert', 'folgt · 1J')}<div class="cl-fig">124.310,55<small>EUR</small></div><div class="cl-sub"><span class="pos">+6,4 %</span> TTWROR · 1J</div>${sp(190, 26)}<div class="cl-warn">⚠ Nicht in der Summe: 3 Verrechnungskonten, 1 Position ohne Preis, 2 Positionen ohne Wechselkurs. <b style="color:var(--color-accent)">Details in Vermögen →</b></div><div class="cl-foot"><span>Ansicht Alles</span><a>In Vermögen ansehen →</a></div></div>`;
  const totalS2 = `<div class="cl-w s budget-s">${headAfter('Gesamtwert', 'folgt · 1J')}<div class="cl-fig">124.310,55<small>EUR</small></div><div class="cl-sub"><span class="pos">+6,4 %</span> TTWROR · 1J</div>${sp(190, 22)}<div class="cl-warn" style="display:flex;gap:4px;white-space:nowrap"><span style="overflow:hidden;text-overflow:ellipsis">⚠ Nicht in der Summe: 3 Verrechnungskonten, 1 Position …</span><b style="color:var(--color-accent)">Details →</b></div><div class="cl-foot"><span>Ansicht Alles</span><a>In Vermögen →</a></div></div>`;
  const dqS1 = `<div class="cl-w s">${headAfter('Datenqualität')}<ul class="cl-list">${['19 Kurse älter als 7 Tage', '1 Wertpapier ohne Anlageklasse', '35 Wertpapiere ohne Logo', '3 Anleihen auf zwei Preisskalen', '1 Kursreihe gegen ihre Buchungen'].map((t) => `<li>● ${t}</li>`).join('')}</ul><div class="cl-foot"><span></span><a>Prüfen →</a></div></div>`;
  const dqS2 = `<div class="cl-w s budget-s">${headAfter('Datenqualität')}<ul class="cl-list">${['1 Kursreihe gegen ihre Buchungen', '3 Anleihen auf zwei Preisskalen', '19 Kurse älter als 7 Tage'].map((t) => `<li style="display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">● ${t}</li>`).join('')}</ul><div class="cl-foot"><span>+2 weitere</span><a>Prüfen →</a></div></div>`;
  const dueS1 = `<div class="cl-w s">${headAfter('Fällig')}<div class="cl-sub">Datierte Fakten zu jedem Wertpapier im Katalog — gehalten oder nicht —, die in den nächsten 30 Tagen anstehen.</div><ul class="cl-list">${[['Helios Solar AG', 'Ende der Haltefrist', '27.11.2026'], ['Nordlicht Shares', 'Geschäftszahlen', '01.12.2026'], ['Nordlicht Shares', 'Ex-Dividenden-Tag', '15.12.2026']].map(([n, k, d]) => `<li style="display:block">${n}<div class="cl-sub">${k}</div><div>${d}</div></li>`).join('')}</ul></div>`;
  const dueS2 = `<div class="cl-w s budget-s">${headAfter('Fällig')}<div class="cl-sub">Ganzer Katalog · nächste 30 Tage</div><ul class="cl-list">${[['27.11.', 'Helios Solar AG'], ['01.12.', 'Nordlicht Shares Registered …']].map(([d, n]) => `<li style="justify-content:flex-start;white-space:nowrap"><b style="font-variant-numeric:tabular-nums">${d}</b><span style="overflow:hidden;text-overflow:ellipsis">${n}</span></li>`).join('')}</ul><div class="cl-foot"><span></span><a>+1 weiterer ▾</a></div></div>`;

  // ---- drawn after the code: fix batch 1 ----
  const driftAfter = `<div class="cl-w t">${headAfter('Allokation und Drift')}<div class="cl-sub">Plan „Basis“ auf Strategie · Σ Soll oberste Ebene: 80,0 %, Soll und Drift darauf umgerechnet</div><table class="cl-table"><tr><th>Kategorie</th><th class="num">Ist</th><th class="num">Soll</th><th class="num">Drift</th></tr>${[['Kern', '35,1', '37,5', '−2,4'], ['Wachstum', '9,3', '18,8', '−9,5'], ['Stabil', '21,6', '25,0', '−3,4'], ['Rohstoffe', '34,0', '18,8', '+15,2']].map((r) => `<tr><td>${r[0]}</td><td class="num">${r[1]} %</td><td class="num">${r[2]} %</td><td class="num">${r[3]}</td></tr>`).join('')}</table></div>`;
  const totalM = `<div class="cl-w m">${headAfter('Gesamtwert', 'folgt · 3M')}<div class="cl-fig">124.310,55<small>EUR</small></div><div class="cl-sub"><span class="pos">+2,1 %</span> TTWROR · 3M</div><div class="cl-two" style="grid-template-columns:repeat(4,1fr);font-size:12px"><div><b>+2,1 %</b><div class="cl-sub">TTWROR · 3M</div></div><div><b>8,4 %</b><div class="cl-sub">Cash-Quote</div></div><div><b>20.11.</b><div class="cl-sub">letzte Buchung</div></div><div><b>2</b><div class="cl-sub">Kurse alt</div></div></div></div>`;


  // ---- ⑩ the UAT's findings (2026-11-23), before and after ----
  const sheetItems = ['Vermögen', 'Alle Widgets'];
  const careItems = ['Transaktionen', 'Konten & Depots', 'Ansichten', 'Klassifizierungen', 'Audit-Journal'];
  const mehr = (logout) => `<div class="u-sheet" style="width:300px"><div style="height:40px" class="cl-sub">&nbsp;Überblick ▾</div><div class="sh"><b class="t">Mehr</b><h5>Entdecken</h5>${sheetItems.map((t) => `<div class="it">${t}</div>`).join('')}<h5>Pflege</h5>${careItems.map((t) => `<div class="it">${t}</div>`).join('')}${logout ? '<div class="it" style="border-bottom:0;margin-top:6px;border-top:1px solid var(--color-border-strong)">⎋&nbsp; Abmelden</div>' : ''}</div><div class="u-tabs"><span>Dashboards</span><span>Wertpapiere</span><span>Nachrichten</span><span class="on">Mehr</span></div></div>${logout ? '<p class="cl-note">„Abmelden“ am Fuß von „Mehr“, nur wenn ein UI-Passwort gesetzt ist — dieselbe Bedingung wie in der Seitenleiste. Gilt auch für die Schiene (844 × 390), deren „Mehr“ dieselbe Liste ist.</p>' : '<p class="cl-note">393 × 852 und 844 × 390: weder die Tab-Leiste noch „Mehr“ nennt „Abmelden“. Mit UI-Passwort kann man sich am Telefon nicht abmelden.</p>'}`;
  const railItems = (w, after) => ['▦<br>Dashboards', '◎<br>' + (after ? 'Wertpapiere' : 'Wertpa-<br>piere'), '☰<br>' + (after ? 'Nachrichten' : 'Nachrich-<br>ten'), '⋯<br>Mehr'].map((t, i) => `<div style="${i === 3 ? 'color:var(--color-accent);font-weight:700' : ''}">${t}</div>`).join('');
  const shortMehr = (after) => `<div class="u-win"><div class="rail" style="width:${after ? 48 : 36}px;font-size:9px">${railItems(36, after)}</div><div class="more" style="left:${after ? 48 : 36}px;${after ? 'bottom:0;overflow:hidden' : 'height:216px'}"><b>Mehr</b><h6>Entdecken</h6>${sheetItems.map((t) => `<div>${t}</div>`).join('')}<h6>Pflege</h6>${careItems.map((t) => `<div${!after && t === 'Audit-Journal' ? ' style="color:var(--color-danger)"' : ''}>${t}</div>`).join('')}${after ? '<div>⎋ Abmelden</div><span class="u-scroll"></span>' : ''}</div>${after ? '' : '<span class="u-cut"></span>'}</div><p class="cl-note">${after ? '„Mehr“ ist nie höher als das Fenster und rollt in sich; jeder Eintrag ist erreichbar.' : 'Halbe Größe. „Mehr“ ist 431 px hoch in einem 390 px hohen Fenster und rollt nicht: „Audit-Journal“ endet unter der Fensterkante.'}</p>`;
  const crashCompact = (after) => `<div class="cl-phone" style="width:393px"><div class="in"><div class="cl-w" style="width:auto"><div class="cl-h"><div class="t"><h4 style="font-size:17px">Crashes im Vergleich</h4><span class="cl-i">i</span></div></div><div style="display:flex;justify-content:space-between;gap:8px;font-size:16px"><span>Herbst-Dip<br><small class="cl-sub">14.10. → 03.11.2026</small></span><span style="text-align:right"><span class="neg">−2,4 %</span><br><small class="cl-sub">${after ? 'Niedrigste im Depot: Welt-ETF Alpha <span class="neg">−3,1 %</span>' : '<span style="color:var(--color-danger)">Depot</span> −3,1 %'}</small></span></div></div><p class="cl-note">${after ? 'Die kompakte Form nennt, was die Zahl ist: das niedrigste einzelne Wertpapier im Depot, mit Namen — wie die Spalte „Niedrigste im Depot“ der breiten Form. „Katalog“: „Niedrigste im Katalog: …“.' : '„Depot −3,1 %“ liest sich als Rendite des Depots neben der des Benchmarks; −3,1 % ist aber das niedrigste einzelne Wertpapier.'}</p></div></div>`;
  const perfDay = (after) => `<div class="cl-w m">${headAfter('Wertentwicklung nach Kategorien', 'folgt · 1T')}<div class="cl-sub">Wert · Ebene Kategorien · <span class="pos">+0,1 %</span> TTWROR in 1T</div>${after ? '<p class="u-quiet">Ein Tag: keine Linie. Die Zahl oben ist die Veränderung zum Schlusskurs davor.</p>' : '<div class="u-plot"><span style="left:4px;top:4px">80.000</span><span style="left:4px;bottom:4px">0</span><span style="left:40px;bottom:-16px">23.11.2026</span><span style="right:4px;bottom:-16px">23.11.2026</span></div><div style="height:12px"></div>'}<div class="cl-foot"><span>Ansicht Alles</span><a>Ganze Ansicht →</a></div></div>`;
  const moverRows = (rows) => `<ul class="cl-list">${rows.map((r) => `<li><span>${r[0]}</span><span class="${r[1][0] === '+' ? 'pos' : 'neg'}">${r[1]}</span></li>`).join('')}</ul>`;
  const moversM = (after) => `<div class="cl-w m budget-m">${headAfter('Tops und Flops', 'folgt · 1W')}<div><span class="cl-seg"><span class="on">Kursrendite</span><span>Beitrag</span></span></div><div class="cl-two"><div><h5>Höchste</h5>${moverRows(names.slice(0, 4).map((r) => [r[0], r[1]]))}${after ? '<div class="cl-sub" style="margin-top:4px"><a style="color:var(--color-accent);font-weight:600">+1 weiterer</a></div>' : `<div class="cl-sub u-hidden">${names[4][0]} ${names[4][1]}</div>`}</div><div><h5>Niedrigste</h5>${moverRows(lows.slice(0, 4).map((r) => [r[0], r[1]]))}${after ? '<div class="cl-sub" style="margin-top:4px"><a style="color:var(--color-accent);font-weight:600">+1 weiterer</a></div>' : `<div class="cl-sub u-hidden">${lows[4][0]} ${lows[4][1]}</div>`}</div></div><div class="cl-foot"><span>Ansicht Alles</span><a>In Vermögen →</a></div></div><p class="cl-note">${after ? 'Die Lesung antwortet fünf je Hälfte; M zeigt vier und sagt den Rest: „+1 weiterer“, verlinkt auf Vermögen wie der Fuß.' : 'Durchgestrichen: die fünfte Zeile, die das CSS ohne ein Wort verbirgt.'}</p>`;
  const editBar = (after) => `<div class="cl-page" style="display:block;padding:0;height:210px"><div class="u-bar"><span class="cl-btn">Alles ▾</span><span class="cl-chips"><span>1M</span><span class="on">1J</span><span>Max</span></span><span style="flex:1"></span><span class="cl-sub">${after ? 'Bearbeitungsmodus' : 'bearbeiten'}</span><span class="cl-btn">Widget hinzufügen</span><span class="cl-btn">Zurücksetzen</span><span class="cl-btn acc">Fertig</span></div><div class="u-drawer" style="top:${after ? 52 : 0}px;bottom:0"><b>Widget hinzufügen <span style="float:right;color:var(--color-text-muted)">×</span></b><div>Gesamtwert <span class="cl-sz"><i>S</i><i>M</i></span></div><div>Datenqualität <span class="cl-sz"><i>S</i><i>M</i></span></div><div>Fällig <span class="cl-sz"><i>S</i></span></div><div>Wertentwicklung <span class="cl-sz"><i>S</i><i>M</i><i>L</i></span></div></div><div style="padding:10px" class="cl-grid"><div style="grid-column:span 3">Gesamtwert</div><div style="grid-column:span 3">Datenqualität</div><div style="grid-column:span 3">Fällig</div></div></div><p class="cl-note">${after ? '„Bearbeitungsmodus“ nennt den Zustand. Die Schublade beginnt unter der Leiste und bleibt beim Rollen unter der Kopfleiste stehen; „Zurücksetzen“ und „Fertig“ bleiben klickbar, das Raster behält seine Breite.' : '„bearbeiten“ ist ein nackter Infinitiv. Die offene Schublade liegt über „Zurücksetzen“ und „Fertig“: ein Klick trifft die Schublade.'}</p>`;
  const titleHead = (after, t) => `<div class="cl-w" style="width:150px"><div class="cl-h"><div class="t" style="${after ? '' : 'flex-wrap:nowrap'}"><h4 style="${after ? '' : 'width:72px;overflow:hidden;white-space:nowrap'}">${t}</h4><span class="cl-i" style="${after ? '' : 'margin-left:-6px'}">i</span>${after ? '' : ''}</div><span class="cl-more">⋯</span></div><div class="cl-fig" style="font-size:20px">88.307,02<small>EUR</small></div></div>`;
  const topbar = (after) => `<div class="u-win" style="height:150px"><div class="rail" style="width:${after ? 48 : 36}px;font-size:9px">${railItems(36, after)}</div><div style="position:absolute;left:${after ? 48 : 36}px;right:0;top:0"><div class="u-top" style="${after ? '' : 'height:52px;align-items:flex-start;padding-top:6px'}"><div class="pg"><b>Überblick ▾</b>${after ? '' : '<small style="color:var(--color-danger)">Lokales Portfolio-Tracking</small>'}</div><span style="flex:1"></span><span class="cl-sub">◐ ⚙</span></div><div style="padding:8px" class="cl-sub">Alles ▾ · 1T 1W 1M 3M YTD <b>1J</b> 3J Max</div></div></div><p class="cl-note">Halbe Größe, 844 × 390. ${after ? 'Der Untertitel (11 px) entfällt in der Schiene und in der kompakten Klasse; die Schiene ist 96 px breit, jede Beschriftung eine Zeile in 12 px, ohne Trennstrich, auch fett in DejaVu Sans (84 px).' : 'Der Untertitel (11 px) rutscht unter „Überblick ▾“, weg von der Marke, zu der er gehört; die 72-px-Schiene trennt „Wertpa-piere“, „Nachrich-ten“.'}</p>`;

  return page('Sprint 31 — Schlussakt', `${CSS}
<header class="mock-board mock-head"><h1>Sprint 31 · Board 02 — die Funde des Schlussakts, vorher und nachher ${SYN}</h1>
<p class="mock-note">Die Linsen Barrierefreiheit (Y1 bis Y5) und Gestaltung (DS1 bis DS5) haben das Dashboard des Sprints gelesen. Dieses Board zeichnet jede sichtbare Änderung ihrer Behebung, vorher und nachher, bevor der Code sie baut. Fokus-Wege (Y1, Y3) ändern kein Bild und stehen nur im Text. Die zwei Rahmen am Ende hat Fix-Runde 1 schon gebaut; sie sind <b>nach dem Code gezeichnet</b>. Alle Namen und Zahlen sind erfunden.</p>
<div class="mock-pickbar"><p><b>Empfohlen:</b> alles wie gezeichnet. <b>Umdrehen mit:</b> „Katalog immer daneben“ (DS4 ohne Schublade; dann scrollt das Raster unter 1400 px seitwärts) · „Tops und Flops M zeigt beide Rankings“ (DS1 ohne Umschalter, doppelt so hoch).</p></div></header>

<section class="mock-board"><span class="mock-tag mock-tag--rec">① Rahmen und S-Größe</span><h2>Titel 15 px, Marke unter dem Titel, Fuß am Fuß, Höhen je Größe <small>DS1, DS2, DS3 · breit, 1200 px</small></h2>
<p class="mock-note">Der Rahmen wird eine Flex-Spalte: der Fuß steht am Fuß des Rahmens. Der Titel ist in der breiten Form 15 px (kompakt bleibt er, wie er ist). Das ⓘ steht auf der Zeile des Titels, die Zeitraum-Marke links darunter; „ohne Zeitraum“ steht nur noch im Bearbeitungsmodus und im ⋯-Menü, „folgt …“ und „📌 eigener …“ bleiben. Höhenbudget je Größe wie die Reihen des Boards: S ≈ 112, M ≈ 236, T und L ≈ 360 px. „Gesamtwert“ in S zeichnet seine Zahl selbst, ohne innere Karte; „Abseits des Ziels“ in S nennt die Zahl der Kategorien, die Liste steht in der neuen Größe M.</p>
${pair(`<div class="cl-row">${totalBefore}${offBefore}${dqBefore}</div>`, `<div class="cl-row">${totalAfter}${offAfter}${dqAfter}</div><div style="margin-top:12px">${offM}</div>`)}</section>

<section class="mock-board"><span class="mock-tag mock-tag--rec">② Tops und Flops, M</span><h2>Ein Ranking zur Zeit, Höchste und Niedrigste nebeneinander <small>DS1</small></h2>
<p class="mock-note">Ein Umschalter Kursrendite · Beitrag (der Browser hält ihn, wie die kompakte Form ihre Hälften); darunter zwei Spalten mit je vier Zeilen. Der Rest steht hinter „In Vermögen →“. Die Zählzeilen bleiben unter der gewählten Seite.</p>
${pair(moversBefore, moversAfter)}</section>

<section class="mock-board"><span class="mock-tag mock-tag--rec">③ Das leere Band</span><h2>Kein Leerraum zwischen Leiste und Raster <small>DS2</small></h2>
${pair(bandBefore, bandAfter)}</section>

<section class="mock-board"><span class="mock-tag mock-tag--rec">④ Bearbeiten bei 1200 px</span><h2>Der Katalog als Schublade über der Seite <small>DS4 · und die Größen als Chips</small></h2>
${pair(editBefore, editAfter, true)}</section>

<section class="mock-board"><span class="mock-tag mock-tag--rec">⑤ Crashes und Zyklus</span><h2>Zahlen brechen nicht um; der Zyklus mit Unterzeile und Fußlink <small>DS5</small></h2>
${pair(crashBefore, crashAfter)}<div style="height:14px"></div>${pair(cycleBefore, cycleAfter)}</section>

<section class="mock-board"><span class="mock-tag mock-tag--rec">⑥ Kompakt, 393 px</span><h2>Ziele ab 44 px, keine verborgenen Tab-Stopps <small>Y2, Y4, Y5 · 1 : 1</small></h2>
<p class="mock-note">Nur die Ziele wachsen, nicht die Schrift. Unsichtbar, aber gebaut: nach ↑, ↓ und × im kompakten Bearbeiten bleibt der Fokus auf demselben Knopf des verschobenen Widgets (oder dem nächsten Widget), nach „Bearbeiten“ auf dem ersten Griff bzw. „Fertig“, nach dem Schließen auf „Bearbeiten“ (Y1, Y3); ⓘ und ⋯ nennen ihr Widget („Zu „Wertentwicklung““, „Menü für „Wertentwicklung““); eine wiederholte Ablehnung wird erneut angesagt; die Gruppen der Seitenleiste sind Überschriften.</p>
${pair(phoneBefore, phoneAfter)}</section>

<section class="mock-board"><span class="mock-tag mock-tag--rec">⑦ Kleinere Funde</span><h2>„Alle Widgets“, die Schiene, „Leer beginnen“</h2>
${pair(widgetsBefore, widgetsAfter)}<div style="height:14px"></div>${pair(rail(false), rail(true))}<div style="height:14px"></div>${pair(leerBefore, leerAfter)}</section>

<section class="mock-board"><span class="mock-tag mock-tag--rec">⑨ Drei S-Formen</span><h2>„Gesamtwert“, „Datenqualität“ und „Fällig“ in S <small>DS1, Nachtrag · breit, 1200 px</small></h2>
<p class="mock-note">Die drei Listen-Widgets halten das S-Budget (≈ 112 px, höchstens das Doppelte auf dem Review-Seed). <b>Gesamtwert</b>: Zahl, Veränderung, Sparkline und der Hinweis „nicht in der Summe“ als <b>eine</b> Zeile mit Link, gekürzt mit Auslassungspunkten (der ganze Satz bleibt für den Screenreader und im Tooltip). <b>Datenqualität</b>: höchstens drei gezählte Zeilen, die schwersten zuerst, dann „+2 weitere · Prüfen →“. <b>Fällig</b>: die Basis kurz („Ganzer Katalog · nächste 30 Tage“, der ganze Satz bleibt die Basis der kompakten Form; das ⓘ behält die Regel für Spannen), höchstens zwei Termine (Datum und Name, je eine Zeile, der Name gekürzt), dann „+1 weiterer“: eine Liste der Termine als Seite gibt es nicht, also klappt der Rest im Widget auf. M behält jeweils den vollen Inhalt.</p>
${pair(`<div class="cl-row">${totalS1}${dqS1}${dueS1}</div>`, `<div class="cl-row">${totalS2}${dqS2}${dueS2}</div>`)}</section>

<section class="mock-board cl-drawn-after"><span class="mock-tag mock-tag--alt">⑧ Nach dem Code gezeichnet</span><h2>Was Fix-Runde 1 schon gebaut hat <small>MO2, F1</small></h2>
<p class="mock-note">„Allokation und Drift“ zeigt in der Soll-Spalte das wirksame Soll, mit der Basiszeile „Σ Soll oberste Ebene …“; „Gesamtwert“ in M folgt dem Zeitraum und sagt ihn: „TTWROR · 3M“. Beide Rahmen sind nach dem Code gezeichnet, nicht davor.</p>
<div class="cl-row">${driftAfter}${totalM}</div></section>

<section class="mock-board"><span class="mock-tag mock-tag--rec">⑩ UAT</span><h2>Die Funde der UAT-Persona, vorher und nachher <small>Funde 1, 2, 3, 5, 7, 8, 9, 10 · uat-sprint31-2026-11-23</small></h2>
<p class="mock-note">Die UAT-Persona hat das Dashboard auf dem Review-Seed in jeder Breitenklasse gelesen. Dieses Board zeichnet jede sichtbare Änderung ihrer Behebung, bevor der Code sie baut. Ohne Bild, nur im Code: Fund 11 („eins ohne Anlageklasse“ wird „1 ohne Anlageklasse“, ebenso „1 ohne Logo“). Nicht behoben, nur festgehalten: Fund 4 (die Kurskurve zeichnet eine gespeicherte 0, Polierliste Wertpapiere) und Fund 6 („→ Woche“ ist die Kalenderwoche nach ADR-0062 §5, die Marke sagt es).</p>
<h3 style="margin:12px 0 6px;font-size:14px">1 · „Abmelden“ in „Mehr“ <small class="cl-sub">S2, 393 × 852</small></h3>
${pair(mehr(false), mehr(true))}
<h3 style="margin:16px 0 6px;font-size:14px">2 · „Mehr“ rollt im Fenster <small class="cl-sub">S2, 844 × 390</small></h3>
${pair(shortMehr(false), shortMehr(true))}
<h3 style="margin:16px 0 6px;font-size:14px">3 · Crashes, kompakt: die Zahl heißt, was sie ist <small class="cl-sub">S2, 393 px</small></h3>
${pair(crashCompact(false), crashCompact(true))}
<h3 style="margin:16px 0 6px;font-size:14px">5 · Wertentwicklung bei 1T: keine leere Fläche <small class="cl-sub">S3, L, 1200 px</small></h3>
${pair(perfDay(false), perfDay(true))}
<p class="cl-note">Mit weniger als zwei Punkten zeichnet das Widget keine Fläche (L) und keine Linie (M) und sagt es leise; die Zahl bleibt. S und kompakt zeichnen ihre Sparkline schon heute nur ab zwei Punkten.</p>
<h3 style="margin:16px 0 6px;font-size:14px">7 · Tops und Flops, M: die fünfte Zeile wird gesagt <small class="cl-sub">S3, 1200 px</small></h3>
${pair(moversM(false), moversM(true))}
<h3 style="margin:16px 0 6px;font-size:14px">8 · Die Bearbeitungsleiste und die Schublade <small class="cl-sub">S3, 1200 px</small></h3>
${pair(editBar(false), editBar(true), true)}
<h3 style="margin:16px 0 6px;font-size:14px">9 · Der Titel nie unter seinem ⓘ <small class="cl-sub">S3, 1200 px, Deutsch</small></h3>
${pair(`<div class="cl-row">${titleHead(false, 'Gesamtwert')}</div><p class="cl-note">Die Titelspalte schrumpft unter ihr längstes Wort: „Gesamtwert“ läuft 2 px unter das ⓘ und wird abgeschnitten (ebenso „Datenqualität“ im Bearbeitungsmodus).</p>`, `<div class="cl-row">${titleHead(true, 'Gesamtwert')}</div><p class="cl-note">Der Titel ist nie schmaler als sein längstes Wort; passt das ⓘ nicht mehr daneben, folgt es dem Titel in die nächste Zeile. Der Width-Walk prüft bei 1200 px in beiden Sprachen: kein Titel überlappt sein ⓘ, keiner ist abgeschnitten.</p>`)}
<h3 style="margin:16px 0 6px;font-size:14px">10 · Die kurze breite Kopfleiste und die Schiene <small class="cl-sub">S3, 844 × 390</small></h3>
${pair(topbar(false), topbar(true))}</section>`);
};
