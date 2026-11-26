// The dashboard by the window's width (ADR-0062 §1, §4, §6; idea board
// ux-design-2026-11-21-idea-i56 03 and 06; planning board
// ux-design-2026-11-21-sprint31/01 ① ④; Sprint 31 D8), driven in a real
// Chromium by test/browser/dashboard_widths_test.exs, which boots the
// endpoint on the review seed and passes the base URL and the mode as JSON
// in the only argument. LiveViewTest applies no CSS, so this is where the
// three width classes are measured on `/`, the template „Überblick“ a fresh
// instance shows:
//
// - compact (375, 393 and 440 px wide, a phone's window): one column of
//   compact forms in reading order, the page never scrolls sideways, every
//   widget's frame inside the viewport, and every visible text inside the
//   dashboard's grid, its bar and the tab bar drawn at 12 px or more (the
//   compact type floor, §6: "nothing under 12 pt"). An SVG text counts at
//   the size it is drawn, its computed font-size times the SVG's scale.
// - medium (760 x 580, the folded-out phone board 06 assumes, and 834 px,
//   an upright tablet): two columns of compact forms, the reading order
//   filled column by column (§6).
// - wide (1200 px): the 12-column grid, every widget at its col and row
//   with its size's span (§4): one row's widgets share a top, a later col
//   stands to the right, the width is the span's on the grid's columns, and
//   no two widgets overlap.
// - the short-wide window (844 x 390, a phone turned sideways): the rail at
//   the side, no bar at the foot; the compact forms keep their type floor.
//
// The text floor, the columns and the place on the page do not depend on
// the font, but whether a frame fits does: every class is measured in the
// page's own Inter and in DejaVu Sans (fonts.js).
//
// mode "walk" measures the page and fails on the first class that breaks
// a rule, naming every break it found there; mode "attack" is the walk's
// own check: it breaks the page on purpose (one label in the grid and one
// in the tab bar drawn at 11 px, one widget moved onto its neighbour's
// place, a line wider than the window) and answers which breaks the checks
// named, so the test can assert each one is caught.
//
// Prints one JSON object on stdout: {"ok": true, "measured": {...}} or
// {"ok": false, "error": "..."}; the exit status is 0 either way unless
// the browser itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { settle, visit, leave } = require("./settle");
const { eachFont } = require("./fonts");

const args = JSON.parse(process.argv[2]);
const base = args.base_url;
const mode = args.mode || "walk";

const COMPACT = [
  { width: 375, height: 667 },
  { width: 393, height: 852 },
  { width: 440, height: 956 }
];
const MEDIUM = [
  { width: 760, height: 580 },
  { width: 834, height: 1112 }
];
const WIDE = { width: 1200, height: 900 };
const SHORT_WIDE = { width: 844, height: 390 };
// ADR-0062 §6: "nothing under 12 pt" (CSS px stand for the ADR's pt).
const FLOOR = 12;
// The grid's 12 columns (§4).
const COLUMNS = 12;
// What a measure may be off by: a subpixel layout, never a column.
const SLACK = 1.5;
// A target a thumb presses in the compact class: 44 px each way (ADR-0062
// §6; DESIGN.md's compact floor; Sprint 31 closing act, Y5). The controls
// the page draws on `/` and, on „Alle Widgets“, „hinzufügen ›“.
const TAP = 44;
const TAP_TARGETS = [
  "[data-role='dashboard-scope'] > summary",
  "[data-role='dashboard-period'] button",
  // Sprint 32 T4: the period menu's button.
  "[data-role='period-menu-toggle']",
  "[data-role='customize']",
  "[data-role='edit-start']",
  "[data-role='edit-reset']",
  ".dashboard-widget [data-role='section-info'] > summary",
  ".dashboard-widget [data-role='widget-menu'] > summary",
  ".widget__foot a"
];
const WIDGETS_TAP_TARGETS = ["[data-role='add-widget']"];

function check(condition, message) {
  if (!condition) throw new Error(message);
}

async function open(page, path) {
  await visit(page, base + path + (path.includes("?") ? "&" : "?") + "locale=de");
  const state = await settle(page);
  check(state.connected && state.settled, path + " did not settle: " + JSON.stringify(state));
}

// A resize starts the shell's transitions (the frame's padding follows the
// sidebar in 180 ms): measure once they ran, not in their first frame.
async function resize(page, size) {
  await page.setViewportSize(size);
  await page.waitForFunction(
    () =>
      document
        .getAnimations()
        .every((a) => a.playState !== "running" || a.effect.getTiming().iterations === Infinity),
    null,
    { timeout: 5000, polling: 50 }
  );
}

// One read of everything a class's rules look at. `roots` are the
// selectors whose visible text the floor holds; `targets` those whose
// drawn controls the tap rule measures.
function measure(page, roots, targets = TAP_TARGETS) {
  return page.evaluate(
    ({ roots, floor, targets }) => {
      const box = (el) => {
        const r = el.getBoundingClientRect();
        return { left: r.left, top: r.top, right: r.right, bottom: r.bottom, width: r.width, height: r.height };
      };
      const shown = (el) => {
        if (!el) return false;
        const r = el.getBoundingClientRect();
        return getComputedStyle(el).display !== "none" && r.width > 0 && r.height > 0;
      };
      // A short path an error can name: the nearest id, then classes.
      const path = (el) => {
        const parts = [];
        for (let e = el; e && e.nodeType === 1 && parts.length < 4; e = e.parentElement) {
          const cls = typeof e.className === "string" && e.className.trim() ? "." + e.className.trim().split(/\s+/).join(".") : "";
          parts.unshift(e.localName + (e.id ? "#" + e.id : "") + cls);
          if (e.id) break;
        }
        return parts.join(" > ");
      };
      // A text is visible when its parent is rendered and not hidden, no
      // ancestor clips it to a screen reader's 1 px box, and it has a box
      // of its own on the page.
      const clipped = (el) => {
        for (let e = el; e && e.nodeType === 1; e = e.parentElement) {
          const cs = getComputedStyle(e);
          const r = e.getBoundingClientRect();
          if (cs.overflow !== "visible" && (r.width <= 1 || r.height <= 1)) return true;
          if (cs.clip && cs.clip !== "auto" && /rect\(\s*0(px)?[ ,]+0(px)?[ ,]+0(px)?[ ,]+0(px)?\s*\)/.test(cs.clip)) return true;
        }
        return false;
      };
      const texts = [];
      for (const selector of roots) {
        for (const root of document.querySelectorAll(selector)) {
          if (!shown(root)) continue;
          const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
          for (let node = walker.nextNode(); node; node = walker.nextNode()) {
            const text = node.textContent.replace(/\s+/g, " ").trim();
            if (!text) continue;
            const el = node.parentElement;
            if (!el || !el.checkVisibility({ opacityProperty: true, visibilityProperty: true })) continue;
            const range = document.createRange();
            range.selectNodeContents(node);
            const rects = [...range.getClientRects()].filter((r) => r.width > 0.5 && r.height > 0.5);
            if (rects.length === 0 || clipped(el)) continue;
            const computed = parseFloat(getComputedStyle(el).fontSize);
            // An SVG text is drawn at its font-size times the SVG's scale.
            let scale = 1;
            if (el instanceof SVGElement && el.getScreenCTM) {
              const m = el.getScreenCTM();
              if (m) scale = Math.sqrt(Math.abs(m.a * m.d - m.b * m.c));
            }
            texts.push({
              root: selector,
              path: path(el),
              text: text.slice(0, 40),
              size: Math.round(computed * scale * 100) / 100
            });
          }
        }
      }
      const grid = document.querySelector("[data-role='dashboard-grid']");
      const gs = grid ? getComputedStyle(grid) : null;
      const widgets = grid
        ? [...grid.children]
            .filter((el) => el.classList.contains("dashboard-widget"))
            .map((el) => {
              const style = getComputedStyle(el);
              const compact = el.querySelector(":scope > .widget__compact");
              const wide = el.querySelector(":scope > .widget__wide");
              return {
                id: el.id,
                kind: el.dataset.widgetKind,
                size: el.dataset.size,
                col: Number(el.dataset.col),
                row: Number(el.dataset.row),
                w: Number(style.getPropertyValue("--widget-w")),
                h: Number(style.getPropertyValue("--widget-h")),
                // A kind of one form (the cycle card) draws its body
                // outside both forms and leaves the wide one empty: it has
                // no form to show or hide (null).
                compact: compact && compact.children.length > 0 ? shown(compact) : null,
                wide: wide && wide.children.length > 0 ? shown(wide) : null,
                // What the frame holds past its own width (the page clips
                // sideways overflow, so a line too wide shows nowhere else).
                overflow: el.scrollWidth - el.clientWidth,
                // How tall it would be on its own: its drawn parts one under
                // the other with the frame's gaps, padding and border, the
                // footer's auto margin left out (DS1's height budget).
                natural: (() => {
                  const parts = [...el.children].filter((c) => {
                    const cs = getComputedStyle(c);
                    return cs.display !== "none" && cs.position !== "absolute" && c.getBoundingClientRect().height > 0;
                  });
                  const gap = parseFloat(style.rowGap) || 0;
                  const sum = parts.reduce((t, c) => t + c.getBoundingClientRect().height, 0);
                  const edges = ["paddingTop", "paddingBottom", "borderTopWidth", "borderBottomWidth"].reduce((t, k) => t + parseFloat(style[k]), 0);
                  return Math.round(sum + Math.max(parts.length - 1, 0) * gap + edges);
                })(),
                // The footer's distance from the frame's foot (inside its
                // padding and border): the footer stands at the foot (DS1).
                footGap: (() => {
                  const foot = el.querySelector(":scope > .widget__foot");
                  if (!foot || !foot.getClientRects().length) return null;
                  const r = el.getBoundingClientRect();
                  const after = [...el.children].filter((c) => c !== foot && getComputedStyle(c).display !== "none" && c.getBoundingClientRect().top >= foot.getBoundingClientRect().bottom - 0.5);
                  const below = after.reduce((t, c) => t + c.getBoundingClientRect().height + (parseFloat(style.rowGap) || 0), 0);
                  return Math.round(r.bottom - parseFloat(style.paddingBottom) - parseFloat(style.borderBottomWidth) - below - foot.getBoundingClientRect().bottom);
                })(),
                // How tall its content is, apart from the row it stretches to.
                content: Math.round(
                  Math.max(...[...el.children].map((c) => c.getBoundingClientRect().bottom), el.getBoundingClientRect().top) -
                    el.getBoundingClientRect().top +
                    parseFloat(style.paddingBottom)
                ),
                // The head: the title's size and box, its ⓘ, its period tag.
                head: (() => {
                  const h2 = el.querySelector(":scope > .widget__head h2");
                  const info = el.querySelector(":scope > .widget__head [data-role='section-info'] > summary");
                  const tag = el.querySelector(":scope > .widget__head [data-role='widget-period']");
                  const b = (e) => (e && e.getClientRects().length ? box(e) : null);
                  return {
                    size: h2 ? parseFloat(getComputedStyle(h2).fontSize) : null,
                    title: b(h2),
                    info: b(info),
                    tag: b(tag),
                    tagText: tag ? tag.textContent.trim() : null,
                    // How far the title's text reaches past its own box.
                    clip: h2 ? h2.scrollWidth - h2.clientWidth : 0
                  };
                })(),
                // The innermost element that reaches past the frame, named.
                past: (() => {
                  if (el.scrollWidth - el.clientWidth <= 1) return null;
                  const edge = el.getBoundingClientRect().right - parseFloat(style.borderRightWidth);
                  let found = null;
                  for (const d of el.querySelectorAll("*")) {
                    const r = d.getBoundingClientRect();
                    if (r.width > 0 && r.right > edge + 1) found = { path: path(d), right: Math.round(r.right - edge), width: Math.round(r.width) };
                  }
                  return found;
                })(),
                ...box(el)
              };
            })
        : [];
      const bar = document.getElementById("app-tabbar");
      const taps = [];
      for (const selector of targets) {
        for (const el of document.querySelectorAll(selector)) {
          const r = el.getBoundingClientRect();
          if (r.width === 0 || r.height === 0 || !el.checkVisibility({ visibilityProperty: true })) continue;
          taps.push({
            selector,
            text: (el.getAttribute("aria-label") || el.textContent || "").replace(/\s+/g, " ").trim().slice(0, 30),
            width: Math.round(r.width * 10) / 10,
            height: Math.round(r.height * 10) / 10
          });
        }
      }
      // A figure drawn on more than one line (DS5: a crash percentage broke
      // as „−3,1“ over „%“): the distinct line tops of its text.
      const broken = [...document.querySelectorAll(".widget-crash-table .num")]
        .filter((el) => el.getClientRects().length > 0)
        .map((el) => {
          const range = document.createRange();
          range.selectNodeContents(el);
          const tops = new Set([...range.getClientRects()].filter((r) => r.width > 0.5).map((r) => Math.round(r.top)));
          return { text: el.textContent.replace(/\s+/g, " ").trim(), lines: tops.size };
        })
        .filter((f) => f.lines > 1);
      // Each tab's label against its tab: how close it comes to an edge.
      const tabLabels = [...document.querySelectorAll("#app-tabbar .app-tab")]
        .filter((t) => t.getClientRects().length > 0)
        .map((t) => {
          const tr = t.getBoundingClientRect();
          const range = document.createRange();
          range.selectNodeContents(t);
          const rects = [...range.getClientRects()].filter((r) => r.width > 0.5);
          const left = Math.min(...rects.map((r) => r.left));
          const right = Math.max(...rects.map((r) => r.right));
          return { text: t.textContent.replace(/\s+/g, " ").trim(), inset: Math.round(Math.min(left - tr.left, tr.right - right) * 10) / 10 };
        });
      const dashBar = document.getElementById("dashboard-bar");
      const lastInBar = dashBar
        ? [...dashBar.children].filter((c) => c.getBoundingClientRect().height > 0 && getComputedStyle(c).position !== "absolute").pop()
        : null;
      return {
        tabLabels,
        broken,
        // The space between the dashboard's bar and its grid: from the
        // bar's last drawn part to the grid's top.
        band: dashBar && grid && lastInBar ? Math.round(grid.getBoundingClientRect().top - lastInBar.getBoundingClientRect().bottom) : null,
        taps,
        vw: window.innerWidth,
        vh: window.innerHeight,
        scrollWidth: Math.max(document.documentElement.scrollWidth, document.body.scrollWidth),
        grid: grid
          ? {
              ...box(grid),
              // Since Sprint 32 L1 the grid is the one surface, framed by
              // a 1 px border: the widgets stand inside it.
              inner: { left: grid.getBoundingClientRect().left + grid.clientLeft, width: grid.clientWidth },
              columns: gs.gridTemplateColumns,
              gap: parseFloat(gs.columnGap) || 0,
              rowGap: parseFloat(gs.rowGap) || 0,
              autoRows: gs.gridAutoRows,
              display: gs.display
            }
          : null,
        widgets,
        texts,
        small: texts.filter((t) => t.size < floor),
        minText: texts.length ? Math.min(...texts.map((t) => t.size)) : null,
        bar: bar ? { ...box(bar), shown: shown(bar) } : null,
        sidebar: (() => {
          const s = document.getElementById("app-sidebar");
          return s ? { ...box(s), shown: shown(s) } : null;
        })()
      };
    },
    { roots, floor: FLOOR, targets }
  );
}

const name = (w) => w.kind + " (" + w.size + " at col " + w.col + ", row " + w.row + ")";

// The rules every class holds: no sideways page scroll, every frame inside
// the window. Answers the breaks, each a sentence.
function pageRules(m, at) {
  const errors = [];
  if (m.scrollWidth > m.vw + 0.5) errors.push(at + ": the page scrolls sideways (" + m.scrollWidth + " > " + m.vw + ")");
  if (m.widgets.length === 0) errors.push(at + ": the dashboard draws no widget");
  for (const w of m.widgets) {
    if (w.left < -0.5 || w.right > m.vw + 0.5) {
      errors.push(at + ": #" + w.id + " leaves the window (" + Math.round(w.left) + " to " + Math.round(w.right) + " of " + m.vw + ")");
    }
    if (w.overflow > 1) {
      errors.push(
        at + ": #" + w.id + " holds a line " + w.overflow + " px wider than its frame" +
          (w.past ? " (" + w.past.path + ", " + w.past.width + " px wide, " + w.past.right + " px past the frame's edge)" : "")
      );
    }
  }
  return errors;
}

// Reading order (§4): by row, then col, as the page draws them.
function inReadingOrder(widgets) {
  for (let i = 1; i < widgets.length; i++) {
    const a = widgets[i - 1];
    const b = widgets[i];
    if (a.row > b.row || (a.row === b.row && a.col > b.col)) return false;
  }
  return true;
}

// Sprint 32 E4 (board ux-design-2026-11-25-sprint32/09): the compact
// class sets the families as a phone's home screen does — two S side by
// side, every other size the full width — in reading order: a widget
// stands under the one before it, or, an S after an S that stands alone on
// the left, beside it on the right.
function compactRules(m, at) {
  const errors = pageRules(m, at);
  if (!inReadingOrder(m.widgets)) errors.push(at + ": the page draws the widgets out of reading order");
  const full = m.grid ? m.grid.inner.width : 0;
  const gap = m.grid ? m.grid.gap : 0;
  const half = (full - gap) / 2;
  const left = m.grid ? m.grid.inner.left : 0;
  let beside = false;
  for (let i = 0; i < m.widgets.length; i++) {
    const w = m.widgets[i];
    const small = w.size === "S";
    const width = small ? half : full;
    if (Math.abs(w.width - width) > SLACK) {
      errors.push(at + ": #" + w.id + " (" + w.size + ") is " + Math.round(w.width) + " px wide, not " + Math.round(width));
    }
    const prev = i > 0 ? m.widgets[i - 1] : null;
    const right = small && prev && prev.size === "S" && !beside && Math.abs(prev.left - left) <= SLACK;
    if (right) {
      if (Math.abs(w.top - prev.top) > SLACK || Math.abs(w.left - (left + half + gap)) > SLACK) {
        errors.push(at + ": #" + w.id + " does not stand beside #" + prev.id);
      }
    } else {
      if (Math.abs(w.left - left) > SLACK) errors.push(at + ": #" + w.id + " does not start its row (left " + Math.round(w.left) + ")");
      if (prev && w.top < Math.max(prev.bottom, i > 1 ? m.widgets[i - 2].bottom : 0) - SLACK) {
        errors.push(at + ": #" + w.id + " does not stand under #" + prev.id);
      }
    }
    beside = right;
    if (w.compact === false) errors.push(at + ": #" + w.id + " does not show its compact form");
    if (w.wide === true) errors.push(at + ": #" + w.id + " shows its wide form");
  }
  return errors.concat(floorRule(m, at), tapRule(m, at));
}

// Every drawn control the tap rule names is at least 44 px each way.
function tapRule(m, at) {
  return m.taps
    .filter((t) => t.width < TAP - 0.5 || t.height < TAP - 0.5)
    .map((t) => at + ": a target under " + TAP + " px, " + t.width + " x " + t.height + ": " + JSON.stringify(t.text) + " (" + t.selector + ")");
}

function floorRule(m, at) {
  return m.small
    .map((t) => at + ": a text under " + FLOOR + " px, " + t.size + " px: " + JSON.stringify(t.text) + " in " + t.path);
}

function mediumRules(m, at) {
  const errors = pageRules(m, at).concat(floorRule(m, at));
  if (!inReadingOrder(m.widgets)) errors.push(at + ": the page draws the widgets out of reading order");
  const lefts = [...new Set(m.widgets.map((w) => Math.round(w.left)))].sort((a, b) => a - b);
  // Two columns: two lefts, within a pixel each.
  const columns = lefts.reduce((acc, x) => (acc.length && x - acc[acc.length - 1] <= SLACK ? acc : [...acc, x]), []);
  if (columns.length !== 2) errors.push(at + ": " + columns.length + " columns of widgets, not 2 (" + lefts.join(", ") + ")");
  // Column by column: a later widget stands in a later column, or lower in
  // the same one.
  for (let i = 1; i < m.widgets.length; i++) {
    const a = m.widgets[i - 1];
    const b = m.widgets[i];
    const later = b.left > a.left + SLACK || (Math.abs(b.left - a.left) <= SLACK && b.top >= a.bottom - SLACK);
    if (!later) errors.push(at + ": #" + b.id + " is not after #" + a.id + " column by column");
  }
  for (const w of m.widgets) {
    if (w.compact === false) errors.push(at + ": #" + w.id + " does not show its compact form");
    if (w.wide === true) errors.push(at + ": #" + w.id + " shows its wide form");
  }
  return errors;
}

// The bar and the grid: no blank band between them, the space is the
// dashboard's own padding (Sprint 31 closing act, DS2: two empty status
// regions each took a gap, 44 px).
const BAND = 20;
// A rail label's least distance from its tab's edge.
const RAIL_INSET = 3;
// The space between the top bar and „Alle Widgets“' search field.
const SEARCH_GAP = 12;
// The wide form's title (DS3).
const TITLE = 15;
// Sprint 32 L2 (board ux-design-2026-11-25-sprint32/07 ② 1): an S tile's
// title is 14 px, so it stays whole beside its ⓘ, mark and ⋯.
const TITLE_S = 14;
// Sprint 32 E4 (ADR-0062's amendment of 2026-11-25, point 3; D-13): every
// row of the wide grid is a fixed 7rem (112 px), so every widget is exactly
// its tile — its rows' tracks and the gaps between them — whatever it
// holds; Sprint 31's height budget (DS1), which a row growing with its
// content needed, is the tile itself now.
const ROW = 112;

// Sprint 31 UAT, finding 9: no title under its ⓘ and none cut. The
// title's box overlaps the ⓘ's nowhere, and its text fits its box.
function headRules(m, at) {
  const errors = [];
  for (const w of m.widgets) {
    const h = w.head;
    if (h.clip > 1) errors.push(at + ": " + name(w) + "'s title is cut by " + h.clip + " px");
    if (h.title && h.info) {
      const a = h.title;
      const b = h.info;
      if (a.left < b.right - 0.5 && b.left < a.right - 0.5 && a.top < b.bottom - 0.5 && b.top < a.bottom - 0.5) {
        errors.push(at + ": " + name(w) + "'s title runs under its ⓘ by " + Math.round(a.right - b.left) + " px");
      }
    }
  }
  return errors;
}

function wideRules(m, at) {
  const errors = pageRules(m, at).concat(headRules(m, at));
  if (m.band !== null && m.band > BAND) errors.push(at + ": " + m.band + " px between the bar and the grid, more than " + BAND);
  for (const f of m.broken) errors.push(at + ": the figure " + JSON.stringify(f.text) + " breaks over " + f.lines + " lines");
  if (!m.grid || m.grid.display !== "grid") return errors.concat([at + ": the dashboard is no grid"]);
  if (m.grid.autoRows !== ROW + "px") errors.push(at + ": the grid's rows are " + m.grid.autoRows + ", not a fixed " + ROW + " px");
  const tracks = m.grid.columns.split(/\s+/).map(parseFloat);
  if (tracks.length !== COLUMNS) errors.push(at + ": the grid has " + tracks.length + " columns, not " + COLUMNS);
  const col = tracks[0];
  const gap = m.grid.gap;
  const step = col + gap;
  for (const w of m.widgets) {
    const left = m.grid.inner.left + (w.col - 1) * step;
    const width = w.w * col + (w.w - 1) * gap;
    if (Math.abs(w.left - left) > SLACK) {
      errors.push(at + ": " + name(w) + " starts at " + Math.round(w.left - m.grid.left) + " px, its col at " + Math.round(left - m.grid.left));
    }
    if (Math.abs(w.width - width) > SLACK) {
      errors.push(at + ": " + name(w) + " is " + Math.round(w.width) + " px wide, its span of " + w.w + " columns " + Math.round(width));
    }
    if (w.wide === false) errors.push(at + ": #" + w.id + " does not show its wide form");
    if (w.compact === true) errors.push(at + ": #" + w.id + " shows its compact form");
    // The head (DS3): the title at 15 px, its ⓘ on the title's line; since
    // Sprint 32 L1 (board ux-design-2026-11-25-sprint32/07 ②, 1) the
    // period mark on the title's line too, after it; no „ohne Zeitraum“.
    const h = w.head;
    const title = w.size === "S" ? TITLE_S : TITLE;
    if (h.size !== null && Math.abs(h.size - title) > 0.1) errors.push(at + ": " + name(w) + "'s title is " + h.size + " px, not " + title);
    // Where the two do not fit on one line, the ⓘ follows the title onto
    // the next, at its left (Sprint 31 UAT, finding 9): never under it.
    if (h.title && h.info) {
      const mid = (h.info.top + h.info.bottom) / 2;
      const onLine = !(mid < h.title.top - SLACK || mid > h.title.top + Math.min(h.title.height, 24) + SLACK);
      const follows = h.info.top >= h.title.bottom - SLACK && h.info.top <= h.title.bottom + 24 && Math.abs(h.info.left - h.title.left) <= 24;
      if (!onLine && !follows) errors.push(at + ": " + name(w) + "'s ⓘ is neither on its title's line nor right under it");
    }
    if (h.title && h.tag) {
      const mid = (h.tag.top + h.tag.bottom) / 2;
      if (mid < h.title.top - SLACK || mid > h.title.bottom + SLACK) errors.push(at + ": " + name(w) + "'s period mark is not on its title's line");
      if (h.tag.left < h.title.right - SLACK) errors.push(at + ": " + name(w) + "'s period mark does not follow its title");
    }
    if (h.tagText === "ohne Zeitraum") errors.push(at + ": " + name(w) + " says „ohne Zeitraum“ on the grid");
    // DS1: the footer at the frame's foot, inside the tile.
    if (w.footGap !== null && Math.abs(w.footGap) > SLACK) errors.push(at + ": " + name(w) + "'s footer stands " + w.footGap + " px above the frame's foot");
    // E4: the widget is its tile, never a row taller.
    const tile = w.h * ROW + (w.h - 1) * m.grid.rowGap;
    if (Math.abs(w.height - tile) > SLACK) {
      errors.push(at + ": " + name(w) + " is " + Math.round(w.height) + " px tall, not its tile's " + tile + " px (" + w.h + " rows)");
    }
  }
  for (let i = 0; i < m.widgets.length; i++) {
    for (let j = i + 1; j < m.widgets.length; j++) {
      const a = m.widgets[i];
      const b = m.widgets[j];
      if (a.row === b.row && Math.abs(a.top - b.top) > SLACK) {
        errors.push(at + ": " + name(a) + " and " + name(b) + " share a row and not a top (" + Math.round(a.top) + ", " + Math.round(b.top) + ")");
      }
      if (a.row === b.row && (a.col < b.col) !== (a.left < b.left)) {
        errors.push(at + ": " + name(a) + " and " + name(b) + " stand in the wrong order");
      }
      if (a.row < b.row && a.top >= b.top + SLACK) errors.push(at + ": " + name(b) + " stands above " + name(a));
      const overlap = a.left < b.right - SLACK && b.left < a.right - SLACK && a.top < b.bottom - SLACK && b.top < a.bottom - SLACK;
      if (overlap) errors.push(at + ": " + name(a) + " and " + name(b) + " overlap");
    }
  }
  return errors;
}

// The classes, each measured in both fonts. Answers {errors, measured}.
async function walkClass(page, sizes, rules, roots) {
  const errors = [];
  const measured = [];
  for (const size of sizes) {
    await resize(page, size);
    const results = await eachFont(page, async (font) => {
      const m = await measure(page, roots);
      const at = size.width + " x " + size.height + " (" + font.name + ")";
      return { at, m, errors: rules(m, at) };
    });
    for (const r of results) {
      errors.push(...r.errors);
      measured.push({
        at: r.at,
        widgets: r.m.widgets.length,
        lefts: [...new Set(r.m.widgets.map((w) => Math.round(w.left)))],
        minText: r.m.minText,
        below_floor: r.m.small.map((t) => ({ size: t.size, text: t.text, path: t.path })),
        overflowing: r.m.widgets
          .filter((w) => w.overflow > 1)
          .map((w) => ({ id: w.id, by: w.overflow, past: w.past })),
        texts: r.m.texts.length,
        taps: r.m.taps.length,
        scrollWidth: r.m.scrollWidth
      });
    }
  }
  return { errors, measured };
}

const COMPACT_ROOTS = ["[data-role='dashboard-grid']", ".dashboard-bar", "#app-tabbar"];

function shortWideRules(m, at) {
  const errors = pageRules(m, at).concat(floorRule(m, at));
  if (!(m.bar && m.bar.shown)) errors.push(at + ": no rail");
  else {
    if (!(m.bar.left === 0 && Math.abs(m.bar.height - m.vh) < 1 && m.bar.width < m.vw / 4)) {
      errors.push(at + ": the menu is no rail at the side: " + JSON.stringify(m.bar));
    }
    if (Math.abs(m.bar.bottom - m.vh) < 1 && Math.abs(m.bar.width - m.vw) < 1) errors.push(at + ": the tab bar sits at the foot");
  }
  for (const w of m.widgets) {
    if (m.bar && m.bar.shown && w.left < m.bar.right - 0.5) errors.push(at + ": #" + w.id + " is under the rail");
  }
  // The rail's labels keep a margin inside the rail (Sprint 31 closing
  // act: „Wertpapiere“ and „Nachrichten“ ran edge to edge).
  for (const t of m.tabLabels) {
    if (t.inset < RAIL_INSET) errors.push(at + ": the rail's label " + JSON.stringify(t.text) + " comes " + t.inset + " px from its tab's edge, under " + RAIL_INSET);
  }
  return errors;
}

async function walk(browser) {
  const errors = [];
  const measured = {};

  const phone = await browser.newContext({ viewport: COMPACT[0], hasTouch: true, isMobile: true });
  const page = await phone.newPage();
  await open(page, "/");
  let r = await walkClass(page, COMPACT, compactRules, COMPACT_ROOTS);
  errors.push(...r.errors);
  measured.compact = r.measured;

  r = await walkClass(page, [SHORT_WIDE], shortWideRules, COMPACT_ROOTS);
  errors.push(...r.errors);
  measured.short_wide = r.measured;

  // „Alle Widgets“: its „hinzufügen ›“ is a target too (Y5).
  await resize(page, COMPACT[0]);
  await open(page, "/widgets");
  measured.widgets_taps = [];
  for (const size of COMPACT) {
    await resize(page, size);
    const m = await measure(page, [], WIDGETS_TAP_TARGETS);
    errors.push(...tapRule(m, "/widgets " + size.width + " x " + size.height));
    const gap = await page.evaluate(() =>
      Math.round(document.querySelector(".widget-catalogue__search").getBoundingClientRect().top - document.querySelector(".topbar").getBoundingClientRect().bottom)
    );
    if (gap < SEARCH_GAP) errors.push("/widgets " + size.width + " x " + size.height + ": the search field stands " + gap + " px under the top bar, under " + SEARCH_GAP);
    measured.widgets_taps.push(m.taps.length);
  }
  await leave(phone);

  const desk = await browser.newContext({ viewport: MEDIUM[0] });
  const wide = await desk.newPage();
  await open(wide, "/");
  // The medium class draws the compact forms: their type floor holds here
  // too.
  r = await walkClass(wide, MEDIUM, mediumRules, COMPACT_ROOTS);
  errors.push(...r.errors);
  measured.medium = r.measured;

  r = await walkClass(wide, [WIDE], wideRules, []);
  errors.push(...r.errors);
  measured.wide = r.measured;
  // The titles in English too (finding 9 measured both languages).
  await visit(wide, base + "/?locale=en");
  await settle(wide);
  r = await walkClass(wide, [WIDE], (mm, at) => headRules(mm, at + " (en)"), []);
  errors.push(...r.errors);
  await open(wide, "/");
  const m = await measure(wide, []);
  measured.wide_items = m.widgets.map((w) => ({
    kind: w.kind,
    size: w.size,
    col: w.col,
    row: w.row,
    left: Math.round(w.left - m.grid.left),
    top: Math.round(w.top - m.grid.top),
    width: Math.round(w.width),
    height: Math.round(w.height),
    content: w.content,
    natural: w.natural
  }));
  await leave(desk);

  const edit = await editMode(browser);
  errors.push(...edit.errors);
  Object.assign(measured, edit.measured);

  return { errors, measured };
}

// The edit mode at 1200 px and at 1440 px (Sprint 31 closing act, DS4;
// board ux-design-2026-11-21-sprint31/02 ④): „Anpassen“ copies the
// template, „Bearbeiten“ opens the edit. Under 1400 px the catalogue is a
// drawer over the page, closed until „Widget hinzufügen“ opens it, so the
// grid keeps the width it has outside the edit and no widget's content
// reaches past its frame; from 1400 px it stands beside the grid.
async function editMode(browser) {
  const errors = [];
  const measured = {};
  const desk = await browser.newContext({ viewport: WIDE });
  const page = await desk.newPage();
  await open(page, "/");
  await page.click("[data-role='customize']");
  await page.waitForURL(/\/dashboards\/\d+/, { timeout: 15000 });
  const state = await settle(page);
  check(state.connected && state.settled, "the copy did not settle: " + JSON.stringify(state));
  const gridWidth = () => page.evaluate(() => Math.round(document.querySelector("[data-role='dashboard-grid']").getBoundingClientRect().width));
  const reading = await gridWidth();
  await page.click("[data-role='edit-start']");
  await page.waitForSelector("[data-role='dashboard-grid'][data-editing='true']");
  await resize(page, WIDE);
  const at = WIDE.width + " x " + WIDE.height + " (edit)";
  let m = await measure(page, []);
  errors.push(...pageRules(m, at));
  for (const font of await eachFont(page, async (f) => headRules(await measure(page, []), at + " (" + f.name + ")"))) errors.push(...font);
  const editing = await gridWidth();
  if (Math.abs(editing - reading) > SLACK) errors.push(at + ": the grid is " + editing + " px wide in the edit, " + reading + " px outside it");
  const drawer = () =>
    page.evaluate(() => {
      const c = document.getElementById("dashboard-catalogue");
      const cs = getComputedStyle(c);
      const r = c.getBoundingClientRect();
      return { display: cs.display, position: cs.position, left: Math.round(r.left), right: Math.round(r.right), width: Math.round(r.width) };
    });
  let d = await drawer();
  if (d.display !== "none") errors.push(at + ": the catalogue is drawn before „Widget hinzufügen“ opens it: " + JSON.stringify(d));
  await page.click("[data-role='edit-catalogue-toggle']");
  await page.waitForSelector("#dashboard-catalogue.is-open");
  d = await drawer();
  if (d.position === "static" || d.left < WIDE.width / 2) errors.push(at + ": the open catalogue is no drawer at the page's right: " + JSON.stringify(d));
  // The drawer covers none of the edit bar's buttons: a click on
  // „Zurücksetzen“ or „Fertig“ lands on it (Sprint 31 UAT, finding 8).
  const covered = await page.evaluate(() =>
    ["edit-catalogue-toggle", "edit-reset", "edit-done"].filter((role) => {
      const el = document.querySelector("[data-role='" + role + "']");
      const r = el.getBoundingClientRect();
      const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
      return !(hit && el.contains(hit));
    })
  );
  if (covered.length) errors.push(at + ": the open drawer covers " + covered.join(", "));
  if (Math.abs((await gridWidth()) - reading) > SLACK) errors.push(at + ": the open drawer narrows the grid");
  measured.edit = { reading, editing, drawer: d };
  const beside = { width: 1440, height: 900 };
  await resize(page, beside);
  d = await drawer();
  const grid = await page.evaluate(() => document.querySelector("[data-role='dashboard-grid']").getBoundingClientRect().right);
  if (d.position === "fixed" || d.left < grid - SLACK) errors.push("1440 x 900 (edit): the catalogue does not stand beside the grid: " + JSON.stringify(d));
  m = await measure(page, []);
  errors.push(...pageRules(m, "1440 x 900 (edit)"));
  measured.edit.beside = d;
  await leave(desk);
  return { errors, measured };
}

// The walk's own check: each break drawn on the page, then the checks run
// on it; answers, per break, the errors the checks named.
async function attack(browser) {
  const caught = {};
  const phone = await browser.newContext({ viewport: COMPACT[1], hasTouch: true, isMobile: true });
  const page = await phone.newPage();
  await open(page, "/");
  const size = COMPACT[1];
  const at = size.width + " x " + size.height;

  // One label in the grid and one tab's label at 11 px.
  for (const [key, selector] of [
    ["grid_label", "[data-role='dashboard-grid'] .widget__compact .widget-total__label, [data-role='dashboard-grid'] .widget__foot span"],
    ["tab_label", "#app-tabbar .app-tab"]
  ]) {
    const marked = await page.evaluate((selector) => {
      const el = [...document.querySelectorAll(selector)].find((e) => e.getClientRects().length > 0 && e.textContent.trim());
      if (!el) return null;
      el.setAttribute("data-walk-attack", "");
      const style = document.createElement("style");
      style.id = "walk-attack";
      style.textContent = "[data-walk-attack] { font-size: 11px !important; }";
      document.head.appendChild(style);
      return el.textContent.replace(/\s+/g, " ").trim().slice(0, 40);
    }, selector);
    check(marked, "attack " + key + ": nothing to shrink under " + selector);
    const m = await measure(page, COMPACT_ROOTS);
    caught[key] = { shrunk: marked, errors: compactRules(m, at).filter((e) => e.includes("under " + FLOOR + " px")) };
    await page.evaluate(() => {
      document.querySelectorAll("[data-walk-attack]").forEach((e) => e.removeAttribute("data-walk-attack"));
      document.getElementById("walk-attack").remove();
    });
  }

  // One target drawn 30 px tall.
  const shrunk = await page.evaluate(() => {
    const el = [...document.querySelectorAll(".widget__foot > a")].find((e) => e.getClientRects().length > 0);
    el.setAttribute("data-walk-attack", "");
    const style = document.createElement("style");
    style.id = "walk-attack";
    style.textContent = "[data-walk-attack] { display: inline-block !important; min-height: 0 !important; height: 30px !important; }";
    document.head.appendChild(style);
    return el.textContent.replace(/\s+/g, " ").trim().slice(0, 30);
  });
  let mt = await measure(page, COMPACT_ROOTS);
  caught.small_target = { shrunk, errors: compactRules(mt, at).filter((e) => e.includes("a target under")) };
  await page.evaluate(() => {
    document.querySelectorAll("[data-walk-attack]").forEach((e) => e.removeAttribute("data-walk-attack"));
    document.getElementById("walk-attack").remove();
  });

  // A line wider than the window.
  await page.evaluate(() => {
    const grid = document.querySelector("[data-role='dashboard-grid'] .dashboard-widget");
    const wide = document.createElement("div");
    wide.id = "walk-attack-wide";
    wide.style.cssText = "width: 600px; height: 4px;";
    grid.appendChild(wide);
  });
  let m = await measure(page, COMPACT_ROOTS);
  caught.sideways = { errors: compactRules(m, at).filter((e) => e.includes("wider than its frame")) };
  await page.evaluate(() => document.getElementById("walk-attack-wide").remove());

  // Sprint 32 E4: an S drawn the full width, where two S stand side by
  // side.
  const widened = await page.evaluate(() => {
    const el = document.querySelector("[data-role='dashboard-grid'] > .dashboard-widget.widget--s");
    el.style.setProperty("grid-column", "span 2");
    return el.id;
  });
  m = await measure(page, COMPACT_ROOTS);
  caught.full_s = { widened, errors: compactRules(m, at).filter((e) => e.includes("(S) is")) };
  await leave(phone);

  // The wide grid: the second widget of the first row moved onto the
  // first's place.
  const desk = await browser.newContext({ viewport: WIDE });
  const wide = await desk.newPage();
  await open(wide, "/");
  await wide.evaluate(() => {
    const [first, second] = document.querySelectorAll("[data-role='dashboard-grid'] > .dashboard-widget");
    second.style.setProperty("--widget-col", first.dataset.col);
  });
  m = await measure(wide, []);
  caught.overlap = { errors: wideRules(m, WIDE.width + " x " + WIDE.height).filter((e) => e.includes("overlap") || e.includes("starts at")) };

  // Sprint 32 E4: a widget a row taller than its tile.
  await open(wide, "/");
  await wide.evaluate(() => {
    const el = document.querySelector("[data-role='dashboard-grid'] > .dashboard-widget");
    const h = Number(getComputedStyle(el).getPropertyValue("--widget-h"));
    el.style.setProperty("grid-row", el.dataset.row + " / span " + (h + 1));
  });
  m = await measure(wide, []);
  caught.taller = { errors: wideRules(m, WIDE.width + " x " + WIDE.height).filter((e) => e.includes("not its tile's")) };

  // The medium class drawn as one column.
  await resize(wide, MEDIUM[0]);
  await wide.evaluate(() => {
    const style = document.createElement("style");
    style.textContent = "[data-role='dashboard-grid'] { columns: 1 !important; }";
    document.head.appendChild(style);
  });
  m = await measure(wide, []);
  caught.one_column = { errors: mediumRules(m, MEDIUM[0].width + " x " + MEDIUM[0].height).filter((e) => e.includes("columns of widgets")) };
  await leave(desk);
  return caught;
}

(async () => {
  const browser = await launchChromium();
  try {
    if (mode === "attack") {
      const caught = await attack(browser);
      process.stdout.write(JSON.stringify({ ok: true, caught }) + "\n");
    } else {
      const { errors, measured } = await walk(browser);
      if (errors.length > 0) {
        process.stdout.write(JSON.stringify({ ok: false, error: errors.join("\n"), measured }) + "\n");
      } else {
        process.stdout.write(JSON.stringify({ ok: true, measured }) + "\n");
      }
    }
  } catch (error) {
    process.stdout.write(JSON.stringify({ ok: false, error: String(error && error.message) }) + "\n");
  } finally {
    await leave(browser);
  }
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
