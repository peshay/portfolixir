// Photographs three throwaway dashboards as they render today, then the same
// widgets on fixed tiles in Apple's families (small 1x1, medium 2x1, large
// 2x2, extra large 4x2 of a square unit of 3 columns x 2 rows), packed in
// reading order. A simulation in the browser: nothing is stored.
const { chromium } = require('playwright');
const MAP = { S: [3, 2], W: [6, 2], M: [6, 4], T: [6, 4], L: [12, 4] };
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1, locale: 'de-DE' });
  for (const [id, slug] of [[3, 'ueberblick'], [4, 'krypto'], [5, 'ruecksetzer']]) {
    for (const mode of ['heute', 'apple']) {
      await p.goto(`http://127.0.0.1:4003/dashboards/${id}?locale=de`, { waitUntil: 'networkidle' });
      await p.waitForTimeout(3500);
      if (mode === 'apple') await p.evaluate((MAP) => {
        window.liveSocket && window.liveSocket.disconnect();
        const st = document.createElement('style');
        st.textContent = `.dashboard-grid{grid-auto-rows:7rem!important}.dashboard-widget{overflow:hidden;position:relative}.dashboard-widget::after{content:"";position:absolute;left:0;right:0;bottom:0;height:28px;background:linear-gradient(transparent,var(--color-bg-elevated));pointer-events:none}`;
        document.head.appendChild(st);
        const ws = [...document.querySelectorAll('.dashboard-widget')].sort((a, b) => (+a.dataset.row - +b.dataset.row) || (+a.dataset.col - +b.dataset.col));
        const taken = new Set();
        const free = (c, r, w, h) => { for (let x = c; x < c + w; x++) for (let y = r; y < r + h; y++) if (taken.has(x + ',' + y)) return false; return true; };
        for (const el of ws) {
          const [w, h] = MAP[el.dataset.size];
          let done = false;
          for (let r = 1; !done && r < 200; r++) for (let c = 1; !done && c <= 13 - w; c++) if (free(c, r, w, h)) {
            for (let x = c; x < c + w; x++) for (let y = r; y < r + h; y++) taken.add(x + ',' + y);
            el.style.setProperty('--widget-col', c); el.style.setProperty('--widget-row', r); el.style.setProperty('--widget-w', w); el.style.setProperty('--widget-h', h);
            done = true;
          }
        }
      }, MAP);
      await p.waitForTimeout(400);
      await p.screenshot({ path: `tpl-${slug}-${mode}.png`, fullPage: true });
    }
  }
  await b.close();
})();
