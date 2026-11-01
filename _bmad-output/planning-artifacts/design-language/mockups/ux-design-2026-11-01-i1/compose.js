const { chromium } = require('playwright');
const S = __dirname + '/out/';
const label = { heute: 'Heute', A: 'A · ⓘ an der Überschrift + Hinweise einzeilig', B: 'B · ⓘ + Hinweise gesammelt (Probleme bleiben offen)', C: 'C · Schalter „Erklärungen“ (aus) + Hinweise einzeilig', R: 'Nachher · beschlossen: ⓘ für Methodensätze, Basis sichtbar, Hinweise gesammelt' };
const make = async (b, name, cols, out, colW) => {
  const p = await b.newPage({ viewport: { width: cols.length * (colW + 24) + 24, height: 400 } });
  const html = `<html><body style="margin:0;padding:12px;background:#e9ebf1;font:600 22px Inter,system-ui,sans-serif;display:flex;gap:24px;align-items:flex-start">
  ${cols.map(c => `<div style="width:${colW}px"><div style="padding:8px 4px 12px;color:#1d2030">${label[c]}</div><img src="${name}-${c}.png" style="width:${colW}px;display:block;box-shadow:0 2px 12px rgba(0,0,0,.15)"></div>`).join('')}
  </body></html>`;
  require('fs').writeFileSync(S + '_c.html', html); await p.goto('file://' + S + '_c.html'); await p.waitForLoadState('load'); await p.waitForTimeout(300);
  await p.screenshot({ path: S + out, fullPage: true }); await p.close();
};
(async () => {
  const b = await chromium.launch();
  const mode = process.env.MODE || 'all';
  for (const n of ['uebersicht', 'vermoegen', 'steuern', 'snapshots', 'cashflow', 'risiko']) {
    if (mode !== 'final') await make(b, n + '-1280', ['heute', 'A', 'B', 'C'], `vergleich-${n}.png`, 640);
    await make(b, n + '-1280', ['heute', 'R'], `final-${n}.png`, 900);
  }
  for (const n of ['uebersicht', 'vermoegen'])
    await make(b, n + '-390', ['heute', 'R'], `final-${n}-handy.png`, 390);
  await b.close();
})();
