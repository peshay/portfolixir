// Captures what boards 03 to 06 start from, from the review instance on the
// synthetic review seed (priv/demo/finding_surfaces_seed.exs), GET requests
// and in-page clicks that only switch a mode; nothing is written:
//
//   shell-b.html          the app's shell (sidebar with „Nachrichten“ after
//                         Wertpapiere, top bar), the main element emptied;
//   research-b.html       the Research tab's basis line and thesis block;
//   dq-b.html, kpi-b.html the Overview's data-quality line and the KPI
//                         strip's cell „Bewertung“ with its stale count;
//   counts-b.json         per data-quality set, the catalog count and the
//                         held count, read from the securities list;
//   bars-b.json           the bars board 06 shows, before (as served) and
//                         after (the same controls regrouped, label beside
//                         its controls, as the shared component would
//                         render them), each inside empty copies of its
//                         ancestors so app.css's descendant rules still hold.
//
// Usage: BASE=http://localhost:4012 node capture-b.js
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const BASE = process.env.BASE || 'http://localhost:4012';
const strip = (s) => s.replace(/ data-phx-[a-z-]+="[^"]*"/g, '').replace(/ phx-[a-z-]+="[^"]*"/g, '').replace(/ id="phx-[^"]*"/g, '');
const tidy = (s) => s.replace(/[ \t]+\n/g, '\n').trim() + '\n';
const write = (f, s) => fs.writeFileSync(path.join(__dirname, f), s);

// In the page: the element's HTML inside empty copies of its ancestors up
// to <main>, and, when `regroup` is set, the same element with each visible
// label and the controls after it wrapped into one group.
function grab(sel, regroup) {
  const el = document.querySelector(sel);
  if (!el) return null;
  const wrap = (html) => {
    let out = html;
    for (let a = el.parentElement; a && a.tagName !== 'MAIN' && a.tagName !== 'BODY'; a = a.parentElement) {
      const t = a.tagName.toLowerCase();
      out = `<${t}${a.className ? ` class="${a.className}"` : ''}>${out}</${t}>`;
    }
    return out;
  };
  const before = wrap(el.outerHTML);
  if (!regroup) return { before };
  const c = el.cloneNode(true);
  c.querySelectorAll('.visually-hidden').forEach((v) => v.classList.remove('visually-hidden'));
  c.querySelectorAll('.filter-chips__group').forEach((g) => g.replaceWith(...g.childNodes));
  const isLabel = (n) => n.nodeType === 1 && n.matches('.filter-chips__family, .hs-controls__label, .control-bar__label');
  const groups = [];
  let cur = null;
  for (const n of [...c.childNodes]) {
    if (n.nodeType === 3 && !n.textContent.trim()) continue;
    if (isLabel(n) || !cur) { cur = { label: isLabel(n) ? n : null, items: [] }; groups.push(cur); if (isLabel(n)) continue; }
    cur.items.push(n);
  }
  c.innerHTML = '';
  c.classList.add('control-bar', 'mock-new');
  for (const g of groups) {
    const row = document.createElement('div');
    row.className = 'control-bar__group';
    const lab = document.createElement('span');
    lab.className = 'control-bar__label';
    lab.textContent = g.label ? g.label.textContent.trim() : (regroup[groups.indexOf(g)] || '');
    const ctl = document.createElement('div');
    ctl.className = 'control-bar__control';
    g.items.forEach((i) => ctl.appendChild(i));
    row.append(lab, ctl);
    c.appendChild(row);
  }
  return { before, after: wrap(c.outerHTML) };
}

(async () => {
  const launch = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {};
  const b = await chromium.launch(launch);
  const p = await b.newPage({ viewport: { width: 1280, height: 900 }, locale: 'de-DE' });

  // 1. The shell.
  await p.goto(BASE + '/securities/1', { waitUntil: 'networkidle' });
  const shell = await p.evaluate(() => {
    const body = document.body.cloneNode(true);
    body.querySelectorAll('script').forEach((s) => s.remove());
    body.querySelector('main').innerHTML = '%%MAIN%%';
    return body.innerHTML;
  });
  // The version at the menu's foot names the checkout; the board shows a neutral one.
  write('shell-b.html', tidy(strip(shell)).replace(/(<a class="sidebar-version__text" href=")[^"]*("[^>]*>)[^<]*/, '$1https://github.com/peshay/portfolixir$2main · 0000000 · 12.11.2026'));

  // 2. The Research tab: its basis line and the thesis block.
  await p.goto(BASE + '/securities/1?tab=research', { waitUntil: 'networkidle' });
  const research = await p.evaluate(() => {
    const panel = document.querySelector('#detail-tab-panel-research');
    return [panel.querySelector('[data-role="research-basis"]').outerHTML, panel.querySelector('[data-role="thesis-state"]').outerHTML].join('\n');
  });
  write('research-b.html', tidy(strip(research)));

  // 3. The Overview's data-quality line and the KPI strip's valuation cell.
  await p.goto(BASE + '/', { waitUntil: 'networkidle' });
  await p.waitForSelector('#dashboard-data-quality', { timeout: 20000 });
  write('dq-b.html', tidy(strip(await p.$eval('#dashboard-data-quality', (e) => e.outerHTML))));
  const kpi = await p.evaluate(() => { const s = document.querySelector('.kpi-strip__sub--attention'); return s ? s.closest('a, .kpi-strip__cell, div').outerHTML : ''; });
  write('kpi-b.html', tidy(strip(kpi)));

  // 4. Per set, the catalog count and the held count, as the list reads them.
  const counts = {};
  for (const id of ['stale_quote', 'missing_logo', 'missing_fx', 'two_scales', 'implausible_quote', 'currency_mismatch']) {
    counts[id] = {};
    for (const [k, q] of [['catalog', ''], ['held', '&holding=held']]) {
      await p.goto(`${BASE}/securities?dq=${id}${q}`, { waitUntil: 'networkidle' });
      await p.waitForTimeout(300);
      counts[id][k] = await p.evaluate(() => document.querySelectorAll('tr.security-row').length);
    }
  }
  write('counts-b.json', JSON.stringify(counts, null, 1) + '\n');

  // 5. The bars of board 06, at the width each breaks.
  const bars = {};
  const grabWith = async (w, url, key, sel, names) => {
    await p.setViewportSize({ width: w, height: 900 });
    await p.goto(BASE + url, { waitUntil: 'networkidle' });
    await p.waitForTimeout(400);
    const res = await p.evaluate(([s, n]) => window.__grab(s, n), [sel, names]);
    bars[key] = { width: w, url, barWidth: Math.round(await p.$eval(sel, (e) => e.getBoundingClientRect().width)), ...res };
  };
  await p.addInitScript(`window.__grab = ${grab.toString()};`);
  await grabWith(390, '/journal', 'journal-chips', '#journal-chips', ['']);
  await grabWith(390, '/journal', 'journal-filters', '#journal-filters', null);
  await grabWith(390, '/cashflow?tab=realized&hindsight=rate', 'hindsight-rate', '[data-role="hindsight-compare"]', null);
  await grabWith(1200, '/securities', 'securities-chips', '#securities-filter-chips', ['Bestand', 'Datenqualität']);
  await grabWith(1200, '/transactions', 'transaction-chips', '#transaction-chips', ['']);
  for (const k of Object.keys(bars)) { bars[k].before = strip(bars[k].before); if (bars[k].after) bars[k].after = strip(bars[k].after); }
  write('bars-b.json', JSON.stringify(bars, null, 1) + '\n');
  console.log('captured', Object.keys(bars).join(', '), JSON.stringify(counts));
  await b.close();
})();
