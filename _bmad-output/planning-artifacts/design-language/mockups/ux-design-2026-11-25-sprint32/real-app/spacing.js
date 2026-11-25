// Spacing variants on the template „Überblick“ (throwaway dashboard 3 of
// templates.exs), on Apple's fixed tiles as board 09 simulates them.
// CSS overrides in the browser only: nothing is stored.
const { chromium } = require('playwright');
const MAP = { S: [3, 2], W: [6, 2], M: [6, 4], T: [6, 4], L: [12, 4] };
const V = {
  heute: ``,
  luftig: `.dashboard{padding-left:32px!important;padding-right:32px!important}.dashboard-grid{gap:20px!important}.dashboard-widget{padding:18px 20px!important;border-radius:16px!important;border-color:color-mix(in oklab,var(--color-border) 60%,transparent)!important;box-shadow:0 1px 2px rgb(15 23 42/.04),0 6px 20px rgb(15 23 42/.05)!important}`,
  apple: `.dashboard{padding-left:36px!important;padding-right:36px!important}.dashboard-grid{gap:24px!important}.dashboard-widget{padding:20px 22px!important;border-radius:22px!important;border:0!important;box-shadow:0 1px 3px rgb(15 23 42/.06),0 10px 28px rgb(15 23 42/.06)!important}main,.dashboard{background:color-mix(in oklab,var(--color-bg-muted) 70%,var(--color-bg))}`,
  flaeche: `.dashboard-grid{gap:1px!important;background:var(--color-border);border:1px solid var(--color-border);border-radius:16px;overflow:hidden}.dashboard-widget{border:0!important;border-radius:0!important;box-shadow:none!important;padding:16px 18px!important}`,
};
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 1250 }, deviceScaleFactor: 1, locale: 'de-DE' });
  const jobs = (process.argv[2] ? [[process.argv[2], process.argv[3]]] : Object.keys(V).map((k) => [k, 'light']).concat([['luftig', 'dark'], ['apple', 'dark']]));
  for (const [name, theme] of jobs) {
    await p.goto('http://127.0.0.1:4003/dashboards/3?locale=de', { waitUntil: 'networkidle' });
    await p.evaluate((t) => document.documentElement.setAttribute('data-theme', t), theme);
    await p.waitForTimeout(3500);
    await p.evaluate(({ MAP, css }) => {
      window.liveSocket && window.liveSocket.disconnect();
      const st = document.createElement('style');
      st.textContent = `.dashboard-grid{grid-auto-rows:7rem!important}.dashboard-widget{overflow:hidden;position:relative}.dashboard-widget::after{content:"";position:absolute;left:0;right:0;bottom:0;height:24px;background:linear-gradient(transparent,var(--color-bg-elevated));pointer-events:none}` + css;
      document.head.appendChild(st);
      const ws = [...document.querySelectorAll('.dashboard-widget')].sort((a, b) => (+a.dataset.row - +b.dataset.row) || (+a.dataset.col - +b.dataset.col));
      const taken = new Set();
      const free = (c, r, w, h) => { for (let x = c; x < c + w; x++) for (let y = r; y < r + h; y++) if (taken.has(x + ',' + y)) return false; return true; };
      for (const el of ws) {
        const [w, h] = MAP[el.dataset.size]; let done = false;
        for (let r = 1; !done && r < 200; r++) for (let c = 1; !done && c <= 13 - w; c++) if (free(c, r, w, h)) {
          for (let x = c; x < c + w; x++) for (let y = r; y < r + h; y++) taken.add(x + ',' + y);
          el.style.setProperty('--widget-col', c); el.style.setProperty('--widget-row', r); el.style.setProperty('--widget-w', w); el.style.setProperty('--widget-h', h); done = true;
        }
      }
    }, { MAP, css: V[name] });
    await p.waitForTimeout(400);
    await p.screenshot({ path: `space-${name}-${theme}.png`, clip: { x: 0, y: 0, width: 1280, height: 1250 } });
  }
  await b.close();
})();
