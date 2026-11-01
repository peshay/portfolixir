// I1 prototype: applied to the live page by Playwright. Variant in window.__I1.
(() => {
  const V = window.__I1;
  const css = `
  .i1-info { position: relative; display: inline-block; margin-left: 8px; vertical-align: middle; }
  .i1-info > summary { display:inline-flex; align-items:center; justify-content:center; width:1.25rem; height:1.25rem;
    border-radius:50%; border:1px solid var(--color-border); background:var(--color-bg-muted); color:var(--color-text-muted);
    font-size:.75rem; font-weight:400; cursor:pointer; list-style:none; }
  .i1-info > summary::-webkit-details-marker { display:none; }
  .i1-info[open] > summary { background: var(--color-accent); color:#fff; border-color: var(--color-accent); }
  .i1-info > .i1-pop { position:absolute; z-index:20; left:0; top:1.7rem; width:min(420px, 80vw); padding:10px 12px;
    background:var(--color-surface, #fff); border:1px solid var(--color-border); border-radius:8px;
    box-shadow:0 8px 24px rgba(0,0,0,.12); font-size:13px; font-weight:400; line-height:1.45; color:var(--color-text); letter-spacing:0; text-transform:none; }
  .i1-info > .i1-pop p { margin:0 0 6px; } .i1-info > .i1-pop p:last-child{margin:0}
  .i1-info > .i1-pop .metric-tooltip > summary { display:none; }
  .i1-info > .i1-pop .metric-tooltip p { position:static; display:block; width:auto; box-shadow:none; border:0; padding:0; margin-top:6px; background:none; }
  .i1-clamp .data-note__body { display:-webkit-box; -webkit-line-clamp:1; -webkit-box-orient:vertical; overflow:hidden; }
  .i1-r .i1-clamp .data-note__body { -webkit-line-clamp:2; }
  @media (max-width: 600px) { .i1-r .i1-clamp .data-note__body { -webkit-line-clamp:3; } }
  .i1-basis-kept { }
  .i1-more { margin-left:auto; flex:none; align-self:center; font-size:12px; white-space:nowrap; color:inherit; text-decoration:underline; background:none; border:0; cursor:pointer; padding:0 0 0 8px; }
  .i1-group { border:1px solid var(--color-border); border-radius:8px; margin: 8px 0; }
  .i1-group > summary { display:flex; gap:10px; align-items:center; padding:10px 12px; cursor:pointer; list-style:none; font-size:13px; }
  .i1-group > summary::-webkit-details-marker { display:none; }
  .i1-group > .i1-group__body { padding: 0 12px 10px; }
  .i1-chip { display:inline-flex; align-items:center; gap:4px; padding:2px 8px; border-radius:999px; font-size:12px; font-weight:600; }
  .i1-chip--problem { background:#fde2e2; color:#a61b1b; } .i1-chip--attention { background:#fdf0d5; color:#9a5b00; } .i1-chip--note { background:#e8eaf0; color:#3d4458; }
  .i1-group--problem { border-color:#e9a3a3; background:#fff6f6; } .i1-group--attention { border-color:#eccb85; background:#fffaf0; }
  .i1-group__lead { color: var(--color-text); }
  .i1-group__toggle { margin-left:auto; color:var(--color-text-muted); }
  .i1-explain-toggle { display:inline-flex; align-items:center; gap:8px; font-size:13px; padding:6px 10px; border:1px solid var(--color-border); border-radius:8px; background:var(--color-bg-muted); margin-right:8px; }
  .i1-switch { width:28px; height:16px; border-radius:999px; background:#c9ccd6; position:relative; } .i1-switch::after{content:''; position:absolute; left:2px; top:2px; width:12px; height:12px; border-radius:50%; background:#fff;}
  body.i1-explain-off .i1-explain { display:none !important; }
  `;
  const st = document.createElement('style'); st.textContent = css; document.head.appendChild(st);

  // Explanations: .hint and .summary-basis lines outside tables and notes.
  const expl = [...document.querySelectorAll('.hint, .summary-basis')]
    .filter(e => !e.closest('table') && !e.closest('.data-note') && !e.closest('form') && e.innerText.trim().length > 0);

  // The nearest heading before the line, inside its section.
  const headingFor = (el) => {
    const sec = el.closest('section, .workspace-section');
    if (!sec) return null;
    const hs = [...sec.querySelectorAll('h2, h3')].filter(h => h.compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING);
    return hs.length ? hs[hs.length - 1] : sec.querySelector('h2, h3');
  };

  if (V === 'A' || V === 'B') {
    const groups = new Map();
    expl.forEach(e => {
      const h = headingFor(e);
      if (!h) return;
      if (!groups.has(h)) groups.set(h, []);
      groups.get(h).push(e);
    });
    groups.forEach((els, h) => {
      const d = document.createElement('details'); d.className = 'i1-info';
      d.innerHTML = '<summary aria-label="Zu diesem Abschnitt">ⓘ</summary><div class="i1-pop"></div>';
      const pop = d.querySelector('.i1-pop');
      els.forEach(e => { const p = document.createElement('p'); p.innerHTML = e.innerHTML; pop.appendChild(p); e.remove(); });
      h.appendChild(d);
    });
  }
  // R, the adopted recommendation (owner, 2026-11-01): A for explanations,
  // B for notes, with two corrections. The short basis clauses (view, period,
  // currency, as-of) stay visible; only the method sentences move into the
  // section's ⓘ. A line that already carries its own ⓘ stays as it is, and a
  // hint inside a card or with a link is data, not an explanation.
  if (V === 'R') {
    document.body.classList.add('i1-r');
    const LONG = 42;
    const cands = [...document.querySelectorAll('p.summary-basis, div.summary-basis, p.hint')]
      .filter(e => !e.closest('table') && !e.closest('.data-note') && !e.closest('form') && !e.closest('.stat, .metric-card, .kpi-strip__cell')
        && !e.querySelector('details, a, button') && e.innerText.trim().length > 0);
    const groups = new Map();
    cands.forEach(e => {
      const h = headingFor(e);
      if (!h) return;
      const clauses = e.innerText.trim().split(/\s+·\s+/);
      const keep = clauses.filter(c => c.length <= LONG && !/[.;:]\s/.test(c));
      const move = clauses.filter(c => !keep.includes(c));
      if (move.length === 0) return;
      if (!groups.has(h)) groups.set(h, []);
      groups.get(h).push(move.join(' · '));
      if (keep.length) { e.textContent = keep.join(' · '); e.classList.add('i1-basis-kept'); } else e.remove();
    });
    groups.forEach((texts, h) => {
      const d = document.createElement('details'); d.className = 'i1-info';
      d.innerHTML = '<summary aria-label="Zu diesem Abschnitt">ⓘ</summary><div class="i1-pop"></div>';
      const pop = d.querySelector('.i1-pop');
      texts.forEach(t => { const p = document.createElement('p'); p.textContent = t; pop.appendChild(p); });
      h.appendChild(d);
    });
  }
  if (V === 'C') {
    expl.forEach(e => e.classList.add('i1-explain'));
    document.body.classList.add('i1-explain-off');
    const bar = document.querySelector('.topbar-actions, header .actions, header');
    const t = document.createElement('span'); t.className = 'i1-explain-toggle';
    t.innerHTML = '<span class="i1-switch"></span> Erklärungen';
    const ctl = document.querySelector('.topbar-controls');
    if (ctl) ctl.prepend(t); else document.body.prepend(t);
  }

  const sev = n => n.classList.contains('data-note--problem') ? 'problem' : n.classList.contains('data-note--attention') ? 'attention' : 'note';
  const clamp = n => {
    n.classList.add('i1-clamp');
    const b = document.createElement('button'); b.className = 'i1-more'; b.type = 'button'; b.textContent = 'mehr ▾';
    n.appendChild(b);
  };

  const notes = [...document.querySelectorAll('.data-note')].filter(n => !n.closest('table'));
  if (V === 'A' || V === 'C') notes.forEach(clamp);
  if (V === 'B' || V === 'R') {
    // Group notes that share a parent; Problems stay visible (clamped), the rest fold into one line.
    const byParent = new Map();
    notes.forEach(n => { const p = n.parentElement; if (!byParent.has(p)) byParent.set(p, []); byParent.get(p).push(n); });
    byParent.forEach((ns, parent) => {
      const problems = ns.filter(n => sev(n) === 'problem');
      const rest = ns.filter(n => sev(n) !== 'problem');
      problems.forEach(clamp);
      if (rest.length === 0) return;
      if (rest.length === 1 && (ns.length === 1 || V === 'R')) { clamp(rest[0]); return; }
      const cnt = { attention: 0, note: 0 }; rest.forEach(n => cnt[sev(n)]++);
      const worst = cnt.attention ? 'attention' : 'note';
      const d = document.createElement('details'); d.className = 'i1-group i1-group--' + worst;
      const chips = [];
      if (cnt.attention) chips.push(`<span class="i1-chip i1-chip--attention">⚠ ${cnt.attention} Achtung</span>`);
      if (cnt.note) chips.push(`<span class="i1-chip i1-chip--note">✳ ${cnt.note} Hinweis${cnt.note>1?'e':''}</span>`);
      const lead = rest.length === 1 ? rest[0].querySelector('.data-note__body').innerText.trim().split(/[:.(—]/)[0] : 'Nicht alles in den Summen ist aktuell oder vollständig';
      const leadHtml = V === 'R' ? '' : `<span class="i1-group__lead">${lead}</span>`;
      d.innerHTML = `<summary>${chips.join('')}${leadHtml}<span class="i1-group__toggle">${V === 'R' ? 'Details anzeigen' : 'anzeigen'} ▸</span></summary><div class="i1-group__body"></div>`;
      const body = d.querySelector('.i1-group__body');
      rest[0].before(d);
      rest.forEach(n => body.appendChild(n));
      // Problems first, then the folded line.
      problems.forEach(p => d.before(p));
    });
  }
  if (V === 'R') {
    // "mehr" only where the clamp actually cuts the text.
    document.querySelectorAll('.i1-clamp').forEach(n => {
      const b = n.querySelector('.data-note__body'), m = n.querySelector('.i1-more');
      if (b && m && b.scrollHeight <= b.clientHeight + 1) m.remove();
    });
  }
})();
