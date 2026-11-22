// Builds the Sprint 31 planning board: the first slice of ADR-0062 (I56),
// the transitional menu, the template „Überblick“ read-only, the widget
// catalogue page, a new dashboard and the compact tab bar. It reuses the
// widgets and the page shell of the I56 idea board. Synthetic data only.
// Usage: node build.js (then node render.js)
const fs = require('fs');
const path = require('path');
const I = require('../ux-design-2026-11-21-idea-i56/build.js');
const { W, page, head, foot, wd, SYN, eur, pchips } = I;

const extra = `<style>
.s31-banner { display: flex; align-items: center; gap: 10px; margin: 0 0 10px; padding: 8px 12px; border: 1px solid var(--color-border); border-radius: var(--radius-md); background: var(--color-bg-muted); font-size: 12.5px; }
.s31-banner b { color: var(--color-text); }
.s31-cat { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; }
.s31-card { border: 1px solid var(--color-border); border-radius: 10px; background: var(--color-bg-elevated); padding: 10px 12px; font-size: 12px; }
.s31-card b { display: block; font-size: 13px; margin-bottom: 2px; }
.s31-card.later { opacity: .55; border-style: dashed; }
.s31-card .wd-sz { display: inline-block; margin: 4px 3px 0 0; padding: 0 5px; border-radius: 4px; background: var(--color-bg-muted); font-size: 10px; font-weight: 700; color: var(--color-text-muted); }
.s31-sheet { position: absolute; left: 0; right: 0; bottom: 0; border-radius: 16px 16px 0 0; background: var(--color-bg-elevated); box-shadow: 0 -10px 30px rgb(15 23 42 / .18); padding: 10px 16px 90px; font-size: 16px; }
.s31-sheet h5 { margin: 12px 0 4px; font-size: 12px; letter-spacing: .06em; text-transform: uppercase; color: var(--color-text-muted); }
.s31-sheet div.it { padding: 10px 0; border-bottom: 1px solid var(--color-border); }
.s31-form { max-width: 520px; display: grid; gap: 10px; font-size: 13px; }
.s31-form .inp { padding: 7px 10px; border: 1px solid var(--color-border-strong); border-radius: var(--radius-md); background: var(--color-bg); }
.s31-choice { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
.s31-choice div { border: 1px solid var(--color-border); border-radius: 10px; padding: 10px; background: var(--color-bg-elevated); }
.s31-choice div.on { border-color: var(--color-accent); box-shadow: 0 0 0 1px var(--color-accent); }
</style>`;

function side(on, stored) {
  const dash = stored
    ? `<a class="${on === 'Mein Überblick' ? 'on' : ''}"><span class="wd-ico">▦</span>Mein Überblick</a>`
    : `<a class="${on === 'Überblick' ? 'on' : ''}"><span class="wd-ico">▦</span>Überblick <span class="wd-muted" style="font-size:10.5px;margin-left:auto">Vorlage</span></a>`;
  const e = (n, ico) => `<a class="${on === n ? 'on' : ''}"><span class="wd-ico">${ico}</span>${n}</a>`;
  const q = (n) => `<a class="quiet${on === n ? ' on' : ''}"><span class="wd-ico">·</span>${n}</a>`;
  return `<aside class="wd-side"><div class="wd-brand">Portfolixir</div><h5>Dashboards</h5>${dash}<a class="add${on === 'Neues Dashboard' ? ' on' : ''}"><span class="wd-ico">+</span>Neues Dashboard</a><h5>Entdecken</h5>${e('Vermögen', '◔')}${e('Wertpapiere', '◎')}${e('Nachrichten', '☰')}${e('Alle Widgets', '⊞')}<h5>Pflege</h5>${q('Transaktionen')}${q('Konten & Depots')}${q('Ansichten')}${q('Klassifizierungen')}${q('Audit-Journal')}</aside>`;
}

const offTarget = () => wd('s', `${head('Abseits des Ziels')}<div class="wd-kpi">2<small class="wd-muted">Kategorien</small></div><div class="wd-sub">außerhalb ±3 Punkte · Zielplan „Basis“</div>`);
const closed = () => wd('m', `${head('Verkaufsrückblick')}<table class="wd-tab"><tr><th>Verkauft</th><th class="num">seit Verkauf</th><th class="num">ggü. Welt-Index</th></tr>${[['Bank West', 8.2, 3.1], ['Pharma Nord', -4.5, -6.0], ['Rohstoff-ETC', 12.9, 9.4]].map(([n, a, b]) => `<tr><td>${n}</td><td class="num ${a > 0 ? 'pos' : 'neg'}">${I.pct(a)}</td><td class="num ${b > 0 ? 'pos' : 'neg'}">${I.pct(b)}</td></tr>`).join('')}</table><div class="wd-sub" style="margin-top:6px">Kurs nach dem Verkauf, Preis ohne Urteil</div>${foot('3 Verkäufe der letzten 12 Monate', 'Alle')}`);

function board01() {
  const tplGrid = [W.total(), W.quality(), W.due(), offTarget(), W.perfL(), W.drift(), W.movers(), W.crashes(), W.cycle(), closed(), W.snapshots()].join('')
    .replace(/<span class="wd-chips">.*?<\/span><\/span>/g, (m) => (m.includes('Alle') || m.includes('Im Depot') ? m : m.includes('Tag') ? '<span class="pd-follow">folgt · 1J</span>' : '<span class="pd-follow">folgt · 1J</span>'));
  const catalog = [
    ['Überblick', [['Gesamtwert', 'S M'], ['Datenqualität', 'S M'], ['Fällig', 'S M'], ['Abseits des Ziels', 'S']], []],
    ['Performance', [['Wertentwicklung', 'S M L Voll'], ['Tops und Flops', 'S M'], ['Snapshots', 'S W']], [['Beiträge je Position', 'M L']]],
    ['Allokation', [['Allokation und Drift', 'M T']], [['Allokation', 'M']]],
    ['Risiko', [['Crashes im Vergleich', 'M L']], [['Kennzahlen', 'S M'], ['Konzentration', 'S'], ['Anlageklassen-Grenzen', 'M']]],
    ['Analysen', [['Bitcoin-Zyklus', 'M L Voll'], ['Verkaufsrückblick', 'M']], [['Prognosen', 'S M']]],
    ['Einkommen und Steuer', [], [['Einkommen', 'W M'], ['Gebühren und Steuern', 'M'], ['Freibetrag', 'S']]],
  ];
  const card = (n, sz, later) => `<div class="s31-card${later ? ' later' : ''}"><b>${n}</b>${sz.split(' ').map((z) => `<span class="wd-sz">${z}</span>`).join('')}${later ? '<div class="wd-sub" style="margin-top:4px">kommt mit dem Umbau seines Screens</div>' : '<div class="wd-sub" style="margin-top:4px">hinzufügen ›</div>'}</div>`;
  const catHtml = catalog.map(([g, now, later]) => `<h4 style="margin:12px 0 6px;font-size:11px;letter-spacing:.06em;text-transform:uppercase;color:var(--color-text-muted)">${g}</h4><div class="s31-cat">${now.map(([n, z]) => card(n, z, false)).join('')}${later.map(([n, z]) => card(n, z, true)).join('')}</div>`).join('');
  const phoneTab = `<div class="cp-dev" style="width:393px;height:700px"><div class="cp-status">9:41</div><div class="cp-appbar"><h3>Überblick ▾</h3><span class="cp-sel">Gesamt</span></div><div class="cp-period">${I.PERIODS.map((p) => `<span${p === '1J' ? ' class="on"' : ''}>${p}</span>`).join('')}</div><div class="s31-sheet"><div style="width:40px;height:5px;border-radius:3px;background:var(--color-border-strong);margin:0 auto 6px"></div><b style="font-size:17px">Mehr</b><h5>Entdecken</h5><div class="it">Vermögen</div><div class="it">Alle Widgets</div><h5>Pflege</h5><div class="it">Transaktionen</div><div class="it">Konten &amp; Depots</div><div class="it">Ansichten · Klassifizierungen · Audit-Journal</div></div><div class="cp-tabbar"><span><b>▦</b>Dashboards</span><span><b>◎</b>Wertpapiere</span><span><b>☰</b>Nachrichten</span><span class="on"><b>⋯</b>Mehr</span></div></div>`;
  return page('Sprint 31 — erster Schnitt', `${extra}
<header class="mock-board mock-head"><h1>Sprint 31 · Board 01 — der erste Schnitt von ADR-0062 ${SYN}</h1>
<p class="mock-note">Das Planungs-Board des Sprints. Die Idee-Boards 01 bis 06 von I56 (<code>ux-design-2026-11-21-idea-i56</code>) gelten mit diesem Plan als angenommen. Dieses Board zeigt nur, was Sprint 31 davon baut und was dabei vorläufig ist. Alle Namen und Zahlen sind erfunden. Farben und Karten sind wie heute (I48 ist eine eigene Frage).</p>
<div class="mock-pickbar"><p><b>Empfohlen:</b> ① bis ④ wie gezeichnet. <b>Umdrehen mit:</b> „Vermögen sofort auflösen“ (① ohne „Entdecken › Vermögen“; dann zieht der Sprint alle Vermögen-Tabs als Widgets mit und wird zwei Sprints groß) · „Pflege oben“ (die Pflege-Gruppe vor „Entdecken“).</p></div></header>

<section class="mock-board"><span class="mock-tag mock-tag--rec">① Frische Instanz</span><h2>Die Vorlage „Überblick“, nur lesend, im Übergangsmenü <small>wide, 1120 px</small></h2>
<p class="mock-note">Ohne gespeichertes Dashboard zeigt der erste Menüeintrag die Vorlage, schreibgeschützt. „Anpassen“ kopiert sie zu „Mein Überblick“; das ist der erste Schreibvorgang (ADR-0062 §3). Unter <b>Entdecken</b> bleibt <b>Vermögen</b>, bis seine Abschnitte Widgets sind, und verlässt das Menü dann. <b>Pflege</b> steht ruhig am Fuß. Wertentwicklung, Tops und Flops und Allokation folgen dem Zeitraum oben (1J, Board 05); die Chips am Zyklus („Alle · Aktueller“) und an den Crashes („Im Depot · Katalog“) sind Ansichten, keine Zeiträume.</p>
<div class="wd-shell">${side('Überblick', false)}<div class="wd-main"><div class="pd-bar" style="margin:0 0 10px"><h3 style="margin:0;font-size:16px">Überblick</h3><span class="mock-select">Gesamt ▾</span><span style="flex:1"></span>${pchips('1J')}</div><div class="s31-banner"><span><b>Vorlage</b> · mitgeliefert, nur lesend</span><span style="flex:1"></span><span class="wd-btn wd-btn--acc">Anpassen</span></div><div class="wd-grid">${tplGrid}</div></div></div></section>

<section class="mock-board"><span class="mock-tag mock-tag--rec">② Alle Widgets</span><h2>Der Katalog als Seite <small>unter „Entdecken“</small></h2>
<p class="mock-note">Jedes registrierte Widget mit seinen Größen. Was Sprint 31 noch nicht baut, steht gestrichelt mit dem Hinweis, wann es kommt. So verspricht der Katalog nichts, was nicht da ist, und zeigt doch den Weg. Hinzufügen öffnet die Wahl des Dashboards.</p>
<div class="wd-shell">${side('Alle Widgets', true)}<div class="wd-main"><div class="wd-top"><h3>Alle Widgets</h3><span class="wd-sp"></span><span class="wd-search" style="min-width:200px">Suchen …</span></div>${catHtml}</div></div></section>

<section class="mock-board"><span class="mock-tag mock-tag--rec">③ Neues Dashboard</span><h2>Leer beginnen oder aus einer Vorlage</h2>
<div class="wd-shell" style="min-height:300px">${side('Neues Dashboard', true)}<div class="wd-main"><div class="wd-top"><h3>Neues Dashboard</h3></div><div class="s31-form"><label>Name<div class="inp">Kurzfristig</div></label><div class="s31-choice"><div class="on"><b>Leer beginnen</b><div class="wd-sub">öffnet den Bearbeitungsmodus mit dem Katalog</div></div><div><b>Aus Vorlage</b><div class="wd-sub">Überblick · weitere Vorlagen kommen mit ihren Widgets</div></div></div><div><span class="wd-btn wd-btn--acc">Anlegen</span></div></div></div></div></section>

<section class="mock-board"><span class="mock-tag mock-tag--rec">④ Kompakt</span><h2>Die Tab-Leiste und „Mehr“ <small>393 pt, 1 : 1</small></h2>
<p class="mock-note">Auf schmalem Bildschirm werden die drei Gruppen zur Tab-Leiste (ADR-0022, Amendment 2026-11-21, Punkt 5). „Dashboards“ wechselt über den Titel („Überblick ▾“), „Mehr“ öffnet den Rest von „Entdecken“ und die Pflege. Ist das Fenster breiter als hoch und niedrig, wird die Tab-Leiste zur Seitenleiste (ADR-0062 §6).</p>
${phoneTab}</section>`);
}

fs.writeFileSync(path.join(__dirname, '01-first-slice.html'), board01());
console.log('wrote 01-first-slice.html');
fs.writeFileSync(path.join(__dirname, '02-closing-act.html'), require('./board02.js').board02(I));
console.log('wrote 02-closing-act.html');
