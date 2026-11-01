const { chromium } = require('playwright');
const fs = require('fs');
const S = __dirname + '/out/';
fs.mkdirSync(S, { recursive: true });
const proposal = fs.readFileSync(__dirname + '/proposal.js', 'utf8');
const pages = [['uebersicht', '/'], ['vermoegen', '/portfolio'], ['steuern', '/tax'], ['snapshots', '/snapshots'], ['cashflow', '/cashflow'], ['risiko', '/risk']];
const W = +(process.env.W || 1280);
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: W, height: 900 } });
  for (const [name, path] of pages) {
    for (const v of ['heute', 'A', 'B', 'C']) {
      await p.goto('http://localhost:4003' + path + '?locale=de', { waitUntil: 'networkidle' });
      await p.waitForTimeout(500);
      if (v !== 'heute') await p.evaluate(([v, js]) => { window.__I1 = v; eval(js); }, [v, proposal]);
      // Wealth: stop before the long positions table.
      let clip = null;
      if (path === '/portfolio') {
        const y = await p.evaluate(() => { const h = [...document.querySelectorAll('h2')].find(x => /^Positionen/.test(x.innerText)); return h ? h.getBoundingClientRect().top + window.scrollY - 20 : null; });
        if (y) clip = { x: 0, y: 0, width: W, height: y };
      }
      // A viewport as tall as the page, so the sticky header and the sidebar stay where they belong.
      const full = await p.evaluate(() => document.documentElement.scrollHeight);
      await p.setViewportSize({ width: W, height: clip ? Math.ceil(clip.height) : full });
      await p.evaluate(() => window.scrollTo(0, 0));
      await p.waitForTimeout(300);
      await p.screenshot({ path: `${S}${name}-${W}-${v}.png` });
      await p.setViewportSize({ width: W, height: 900 });
      if (v === 'A' && name === 'vermoegen') {
        // one ⓘ opened, to show what it holds
        await p.evaluate(() => { const d = [...document.querySelectorAll('.i1-info')].find(x => /Beitrag/.test(x.parentElement.innerText)) || document.querySelector('.i1-info'); d.open = true; d.scrollIntoView({block:'center'}); });
        await p.screenshot({ path: `${S}${name}-${W}-A-open.png` });
      }
    }
  }
  await b.close();
})();
