// Photographs every widget kind in every grid size, light and dark, from the
// throwaway dashboard all_sizes.exs stores on a local review-seed instance.
const { chromium } = require('playwright');
const id = process.argv[2];
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 2, locale: 'de-DE' });
  for (const theme of ['light', 'dark']) {
    await p.goto(`http://127.0.0.1:4003/dashboards/${id}?locale=de`, { waitUntil: 'networkidle' });
    await p.evaluate((t) => document.documentElement.setAttribute('data-theme', t), theme);
    await p.waitForTimeout(3500);
    const items = await p.evaluate(() => [...document.querySelectorAll('.dashboard-widget')].map((e, i) => { e.setAttribute('data-shot', i); return { i, kind: e.dataset.widgetKind, size: e.dataset.size, w: Math.round(e.getBoundingClientRect().width), h: Math.round(e.getBoundingClientRect().height) }; }));
    for (const it of items) {
      await (await p.$(`[data-shot="${it.i}"]`)).screenshot({ path: `gallery/${it.kind}-${it.size}-${theme}.png` });
    }
    if (theme === 'light') console.log(JSON.stringify(items));
  }
  await b.close();
})();
