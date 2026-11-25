// Photographs every widget of the throwaway dashboard that all_sizes.exs stores
// (every kind in every grid size) on a local review-seed instance, one PNG each.
const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 2, locale: 'de-DE' });
  await p.goto('http://127.0.0.1:4003/dashboards/1?locale=de', { waitUntil: 'networkidle' });
  await p.waitForTimeout(4000);
  const info = await p.evaluate(() => {
    const els = [...document.querySelectorAll('.dashboard-widget')];
    return els.slice(0, 40).map((e, i) => { e.setAttribute('data-shot', i); return `${i} kind=${e.dataset.widgetKind} size=${e.dataset.size} ${Math.round(e.getBoundingClientRect().width)}x${Math.round(e.getBoundingClientRect().height)}`; });
  });
  console.log(info.join('\n'));
  await p.screenshot({ path: 'alle-groessen.png', fullPage: true });
  const n = info.length;
  for (let i = 0; i < n; i++) {
    const el = await p.$(`[data-shot="${i}"]`);
    try { await el.screenshot({ path: `w-${String(i).padStart(2, '0')}.png` }); } catch (e) { console.log('skip', i, e.message.slice(0, 60)); }
  }
  await b.close();
})();
