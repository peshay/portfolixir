// The frames of the Sprint 24 P1 board: where each is captured, at which
// viewport, and the prep that applies the story's markup to the live page.
// build.js runs them; the story's CSS is build.js's PROPOSAL_CSS.
//
// German: every string on a frame comes from the live page; the board adds
// none (README.md, "Strings"). Synthetic data only: the rows are the
// synthetic review seed's.
module.exports = function () {
  // #1322 names "all eight columns": Wealth's picker without its three
  // identifier columns (ISIN, WKN, Currency). The ColumnPrefs hook restores
  // the pick from the browser's storage, as a reader's earlier pick would.
  const EIGHT = ['depot', 'security', 'quantity', 'avg_cost', 'latest_price', 'market_value', 'unrealized_pnl_abs', 'unrealized_pnl_pct'];
  const pickEight = `try { localStorage.setItem('wealth.holdings.columns', ${JSON.stringify(JSON.stringify(EIGHT))}); } catch (_) {}`;

  // The rows a frame keeps: the longest names, the twelve-digit quantity
  // and both kinds of cell note; the rest become one elided line.
  const KEEP_NAMES = [
    'Larkspur Rail AG 4,00 % Anleihe 2031',
    'Microsoft Corporation Registered Shares DL-,00000625',
    'Orchid Bay Pharmaceuticals plc ISIN XS0000000066',
    'Vanguard FTSE All-World UCITS ETF USD Acc',
    'Harborline Freight Inc',
    'Birchwood Global Savings Fund'
  ];
  function keepRows(a) {
    for (const sel of ['#holdings-positions-table > tbody > tr', '#holdings-phone-rows > li']) {
      const rows = [...document.querySelectorAll(sel)];
      const keep = (r) => a.names.some((n) => r.textContent.replace(/\s+/g, ' ').includes(n));
      const gone = rows.filter((r) => !keep(r));
      if (!gone.length) continue;
      const last = rows.filter(keep).pop();
      gone.forEach((r) => r.remove());
      const line = M.el(sel.startsWith('#holdings-positions') ? '<tr class="mock-elided"><td colspan="12"></td></tr>' : '<li class="mock-elided"></li>');
      (line.querySelector('td') || line).textContent = '… ' + gone.length + ' weitere Positionen, für das Board gekürzt';
      last.after(line);
    }
  }
  // The story's markup: the Security column's head and cells carry
  // `cell-name`, the class the floor and the break key on.
  function nameColumn() {
    const first = document.querySelector('#holdings-positions-table td[data-column="security"]');
    if (!first) return;
    const index = [...first.parentElement.children].indexOf(first);
    const th = document.querySelectorAll('#holdings-positions-table thead th')[index];
    th.classList.add('cell-name');
    M.neu(th);
    document.querySelectorAll('#holdings-positions-table td[data-column="security"]').forEach((td) => td.classList.add('cell-name'));
    M.pin(th, 3, 'pre');
  }
  // The contribution table keeps its first five positions; the remainder,
  // the sum and the basis line stay.
  function cutContribution() {
    M.cut('#contribution-table > tbody > tr[data-role="contribution-row"]', 5, '… %n weitere Positionen, für das Board gekürzt');
    M.cut('#contribution-phone-rows > li[data-role="contribution-row"]', 5, '… %n weitere Positionen, für das Board gekürzt');
  }
  // Dashed only where the rows are the change (above 560 px); on a phone
  // they showed before.
  function markRows(a) {
    if (a.vw <= 560) return;
    const ul = document.querySelector('#contribution-phone-rows');
    if (ul) { M.neu(ul); M.pin(ul.querySelector('.phone-row__name'), 2, 'pre'); }
  }

  // In the static frame: the scroller's width and what it scrolls, and
  // whether the last column (G&V % / Beitrag) ends inside it.
  function probe() {
    const out = {};
    const hold = document.querySelector('#holdings-positions-wrapper');
    if (hold) {
      const ths = [...hold.querySelectorAll('thead th')];
      const pnl = ths.find((th) => th.textContent.trim() === 'G&V');
      const right = hold.getBoundingClientRect().right;
      out.holdings = { wrapper: hold.clientWidth, scroll: hold.scrollWidth, pnlInView: !!pnl && pnl.getBoundingClientRect().right <= right + 0.5 };
      const name = hold.querySelector('td[data-column="security"]');
      out.holdings.nameColumn = name ? Math.round(name.getBoundingClientRect().width) : null;
    }
    const block = document.querySelector('#performance-contribution');
    if (block) {
      const wrap = block.querySelector('#contribution-table-wrap');
      const rows = block.querySelector('#contribution-phone-rows');
      out.contribution = {
        block: Math.round(block.getBoundingClientRect().width),
        table: getComputedStyle(wrap).display !== 'none',
        wrapper: wrap.clientWidth,
        scroll: wrap.scrollWidth,
        rows: getComputedStyle(rows).display !== 'none'
      };
    }
    return out;
  }

  const WEALTH = '/portfolio';
  const waitContribution = async (page) => { await page.waitForSelector('#contribution-table', { state: 'attached', timeout: 30000 }); await page.waitForTimeout(800); };
  const waitHoldings = async (page) => { await page.waitForSelector('#holdings-positions-table td[data-column="unrealized_pnl_pct"]', { state: 'attached', timeout: 30000 }); };

  // At 1200 px the sidebar is open (220 px), so a frame without it is the
  // main column the live page leaves beside it and its scrollbar: 971 px,
  // whose scroller is the live 922 px; at 1024 px it is 795 px (a 751 px
  // block, as live). Under 880 px the sidebar leaves the layout, so a
  // 600 px phone's frame is the whole viewport.
  const DARK = { suffix: '-dark', theme: 'dark' };
  const FRAMES = [
    // (3) #1322, the holdings table with #1322's eight columns
    { id: 'h-before', url: WEALTH, init: pickEight, act: waitHoldings, keep: ['#portfolio-positions'], widths: [1200, 390], frameWidths: { 1200: 971 }, prep: { fn: keepRows, args: { names: KEEP_NAMES } }, probe },
    { id: 'h-after', url: WEALTH, init: pickEight, act: waitHoldings, keep: ['#portfolio-positions'], widths: [1200, 390], frameWidths: { 1200: 971 }, proposal: true, prep: [{ fn: keepRows, args: { names: KEEP_NAMES } }, { fn: nameColumn }], looks: [{ suffix: '' }, Object.assign({ widths: [1200] }, DARK)], probe },
    // (2) "Beitrag je Position": at 1024 px with the sidebar open, at a
    // 600 px phone held upright, at 1200 px and at 390 px
    { id: 'c-before', url: WEALTH, act: waitContribution, keep: ['#performance-contribution'], widths: [1024, 600, 1200, 390], frameWidths: { 1024: 795, 1200: 971 }, prep: { fn: cutContribution }, probe },
    { id: 'c-after', url: WEALTH, act: waitContribution, keep: ['#performance-contribution'], widths: [1024, 600, 1200, 390], frameWidths: { 1024: 795, 1200: 971 }, proposal: true, prep: [{ fn: cutContribution }, { fn: markRows }], looks: [{ suffix: '' }, Object.assign({ widths: [1024] }, DARK)], probe }
  ];

  return { FRAMES, EIGHT, KEEP_NAMES };
};
