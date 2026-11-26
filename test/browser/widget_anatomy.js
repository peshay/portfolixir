// The widget anatomy in a real browser (Sprint 32 L1; board
// ux-design-2026-11-25-sprint32/07 ② and 10 D; DESIGN.md → "The widget
// anatomy and the one surface"), driven by
// test/browser/widget_anatomy_test.exs, which boots the endpoint, seeds the
// review seed and stores one dashboard holding every kind in every grid
// size it takes, and passes its base URL and the dashboard's id.
//
// At 1200 px (the wide grid), 834 px (the medium class, two columns) and
// 393 px (a phone held upright, the compact forms), in the page's own
// Inter and in DejaVu Sans (fonts.js), every widget is measured for the
// anatomy's three rules (board 07 ②, 1, 2 and 6):
//
// - its head: in the wide grid one line — the title, its ⓘ, the period
//   mark, the widget's switch and ⋯ share the title's line, the title one
//   line (cut with an ellipsis where its tile is too narrow, as board 07 ②
//   draws it); in the compact forms (834 and 393 px) the title never cut,
//   the rest following under it where the line does not hold it, as board
//   07's phone draws it;
// - no figure clipped: a headline figure or a list row's figure is never
//   cut sideways — it is as wide as its text, and inside the widget's
//   frame and every box between them;
// - no warning box: a widget carries a warning as one line (the anatomy's
//   warning line, or a data note drawn as a line: its glyph, word and
//   colour), never a data note framed or filled as a box.
//
// And the one surface (board 10 D, D-14), in every class: the grid one
// frame (1 px border, radius 16 px), each widget without a card border, a
// corner radius or a shadow; in the wide grid two neighbours 1 px apart
// (the hairline), never a gap. The edit mode (at 1200 px): each widget's
// handle, × and size switch inside its own cell, its dashed outline too.
//
// Mode "attack" checks the check: on the walked page it draws a head's
// title over several lines in the wide grid and cut in the compact forms,
// another head's period mark on a line of its own (wide), a fourth
// title too long for its tile and a list's body cut through a row (wide), a row's figure 400 px wide inside a 40 px box, a framed and filled
// data note into a widget, a card border on one widget and a 12 px gap in
// the grid, and the handle above its cell; each must be named.
//
// Prints one JSON object on stdout: {"ok": true, ...} or {"ok": false,
// "error": "..."}; the exit status is 0 either way unless the browser
// itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { settle, visit, leave } = require("./settle");
const { eachFont } = require("./fonts");

const { base_url: base, id, mode } = JSON.parse(process.argv[2]);
// With WIDGET_ANATOMY_SHOTS naming a directory, a walk also saves each
// width's page, light and dark, and the edit mode at 1200 px.
const shots = process.env.WIDGET_ANATOMY_SHOTS || null;
const path = require("path");
const WIDTHS = [
  { width: 1200, height: 900 },
  { width: 834, height: 1112 },
  { width: 393, height: 852 }
];

// Every widget's anatomy, measured on the page as it stands.
function measure(page) {
  return page.evaluate(() => {
    const shown = (el) => {
      if (!el) return false;
      const s = getComputedStyle(el);
      return s.display !== "none" && s.visibility !== "hidden" && el.getClientRects().length > 0;
    };
    const rect = (el) => el.getBoundingClientRect();
    const grid = document.querySelector("#dashboard-grid");
    const gs = getComputedStyle(grid);
    const widgets = Array.from(grid.querySelectorAll(":scope > .dashboard-widget"));

    return {
      grid: {
        radius: gs.borderTopLeftRadius,
        border: gs.borderTopWidth + " " + gs.borderTopStyle,
        width: grid.getBoundingClientRect().width,
        editing: grid.dataset.editing === "true"
      },
      widgets: widgets.map((w) => {
        const name = w.dataset.widgetKind + " " + w.dataset.size;
        const ws = getComputedStyle(w);
        const frame = rect(w);
        const head = w.querySelector(":scope > .widget__head");
        const title = head && head.querySelector("h2");
        // The head's parts that share the title's line: the switch only
        // where the wide form is drawn (the compact forms set it under the
        // head, board 07's phone).
        const wide = shown(w.querySelector(":scope > .widget__wide"));
        const parts = head
          ? Array.from(
              head.querySelectorAll(
                "[data-role='section-info'] > summary, [data-role='widget-period'], .widget__menu > summary" +
                  (wide ? ", [data-anatomy='switch']" : "")
              )
            ).filter(shown)
          : [];
        const t = title && rect(title);
        const lineHeight = title ? parseFloat(getComputedStyle(title).lineHeight) || 0 : 0;
        // The wide grid holds the head on one line; the compact forms
        // keep the title whole and let the rest follow under it.
        const wideGrid = window.innerWidth >= 1000;
        const offLine = t && wideGrid
          ? parts
              .filter((p) => {
                const r = rect(p);
                const mid = (r.top + r.bottom) / 2;
                return mid < t.top - 1 || mid > t.bottom + 1;
              })
              .map((p) => p.dataset.role || p.dataset.anatomy || p.parentElement.className)
          : [];

        // A figure is cut where it is wider than its box, or where its
        // right or left edge passes the frame or a box between them that
        // cuts what overflows.
        // A table's figure cell is a figure too (the S32 closing act: the
        // walk missed „≈ zum Soll“ cut by the drift table's 437 px in a
        // 425 px body, and the lowest return of „Crashes im Vergleich“
        // behind its name's ellipsis): a cell of figures (`td.num`) and a
        // figure inside a cell; a table that scrolls sideways keeps its
        // cells reachable, so only a box that clips cuts one.
        const figures = Array.from(
          w.querySelectorAll(".widget-figure__value, .widget-row__figure, td.num, td .num")
        ).filter(shown);
        const cut = [];
        for (const f of figures) {
          const r = rect(f);
          const cell = !f.matches(".widget-figure__value, .widget-row__figure");
          if (f.scrollWidth > f.clientWidth + 1) {
            cut.push(f.textContent.replace(/\s+/g, " ").trim() + " is " + f.scrollWidth + " px wide in " + f.clientWidth);
            continue;
          }
          for (let box = f.parentElement; box && box !== w.parentElement; box = box.parentElement) {
            const bs = getComputedStyle(box);
            if (box !== w && bs.overflowX === "visible") continue;
            if (cell && box !== w && (bs.overflowX === "auto" || bs.overflowX === "scroll")) break;
            const b = rect(box);
            if (r.right > b.right + 1 || r.left < b.left - 1) {
              cut.push(
                f.textContent.replace(/\s+/g, " ").trim() + " passes the edge of " + (box === w ? "its frame" : box.className || box.tagName)
              );
              break;
            }
          }
        }

        // A warning box: a data note drawn with a frame or a fill. Inside
        // a widget the note is a line (its glyph, word and colour), never
        // a box.
        const boxes = Array.from(w.querySelectorAll(".data-note, .data-note-group"))
          .filter(shown)
          .filter((n) => {
            const ns = getComputedStyle(n);
            const framed = ["Top", "Right", "Bottom", "Left"].some(
              (side) => parseFloat(ns["border" + side + "Width"]) > 0 && ns["border" + side + "Style"] !== "none"
            );
            const filled = ns.backgroundColor !== "rgba(0, 0, 0, 0)" && ns.backgroundColor !== "transparent";
            return framed || filled;
          })
          .map((n) => n.className);

        // A card inside the widget (the S32 closing act; board 10 D „Eine
        // Fläche“, board 07 ② 3 "no card inside the card, no colour
        // strip"): a part of the body that casts a shadow, carries a
        // colour strip (a ::before laid over its edge with a gradient) or
        // is framed on all four sides and filled or rounded. Controls,
        // badges, tracks, a table's cells (the pinned column's seam is an
        // inset shadow) and charts are not cards.
        const cards = [];
        for (const el of w.querySelectorAll("*")) {
          if (
            el.closest(
              ".widget__head, .widget__edit, .widget__sizes, .widget__note, button, a, input, select, textarea, summary, label, svg, td, th, .segmented-control, .badge, .drift-bar, .widget-bar, .risk-hhi__track, .key-figures__bar"
            ) ||
            !shown(el)
          ) {
            continue;
          }
          const r = rect(el);
          if (r.width < 60 || r.height < 24) continue;
          const cs = getComputedStyle(el);
          const before = getComputedStyle(el, "::before");
          const strip =
            before.content !== "none" &&
            before.content !== "normal" &&
            before.position === "absolute" &&
            before.backgroundImage !== "none";
          const framed = ["Top", "Right", "Bottom", "Left"].every(
            (side) => parseFloat(cs["border" + side + "Width"]) > 0 && cs["border" + side + "Style"] !== "none"
          );
          const filled = cs.backgroundColor !== "rgba(0, 0, 0, 0)" && cs.backgroundColor !== "transparent";
          const rounded = parseFloat(cs.borderTopLeftRadius) > 0;
          const why = cs.boxShadow !== "none" ? "a shadow" : strip ? "a colour strip" : framed && (filled || rounded) ? "a frame" : null;
          if (why) cards.push((el.className || el.tagName) + " with " + why);
        }

        // The figures of a card the tabs share (`.stat`) are set in the
        // anatomy's sizes inside a widget: 34, 28 or 24 px, 30 or 22 in a
        // compact form, at the figure's weight.
        const offSizes = [];
        for (const f of w.querySelectorAll(".stat strong")) {
          if (!shown(f) || f.classList.contains("stat-empty")) continue;
          const fs = getComputedStyle(f);
          const px = parseFloat(fs.fontSize);
          if (![34, 30, 28, 24, 22].includes(px) || parseInt(fs.fontWeight, 10) < 750) {
            offSizes.push(f.textContent.replace(/\s+/g, " ").trim() + " at " + px + " px/" + fs.fontWeight);
          }
        }

        // The cycle chart in a widget (the S32 closing act: its labels
        // stood at 10.4 units, 9 CSS px, in „Krypto Lover“'s XL): every
        // text it draws at 12 CSS px or more, its size in the viewBox's
        // units times the units' CSS pixels.
        const smallText = [];
        for (const svg of w.querySelectorAll("[data-role='cycle-widget-chart'] svg")) {
          if (!shown(svg) || !svg.viewBox || !svg.viewBox.baseVal || !svg.viewBox.baseVal.width) continue;
          const px = rect(svg).width / svg.viewBox.baseVal.width;
          for (const t of svg.querySelectorAll("text, tspan")) {
            if (!shown(t) || !t.textContent.trim()) continue;
            const size = parseFloat(getComputedStyle(t).fontSize) * px;
            if (size < 11.95) smallText.push(t.textContent.replace(/\s+/g, " ").trim().slice(0, 30) + " at " + size.toFixed(1) + " px");
          }
        }

        // A table's head whole (the S32 closing act's coverage pass:
        // „BENCH…“ and „RECO…“ over „Crashes im Vergleich“ L; board 09
        // draws them whole): a head cell's words wider than the cell are
        // named, whether the cell cuts them with an ellipsis or not.
        const headCut = [];
        for (const th of w.querySelectorAll("thead th")) {
          if (shown(th) && th.textContent.trim() && th.scrollWidth > th.clientWidth + 1) {
            headCut.push(th.textContent.replace(/\s+/g, " ").trim().slice(0, 30));
          }
        }

        // The S32 closing act's UAT (findings 3, 4, 6), in the compact
        // and medium classes: a warning line's sentence at the line's
        // whole width, not wrapped in a narrow column beside its link
        // (finding 3); no text under 12 px, HTML or a chart's SVG drawn to
        // its CSS pixels (finding 4); no table running past its widget
        // unless a box scrolls it (finding 6).
        const narrowWarning = [];
        const tinyText = [];
        const tableOver = [];
        if (!wideGrid) {
          for (const line of w.querySelectorAll(".widget-warning")) {
            const text = line.querySelector(".widget-warning__text");
            if (!shown(line) || !text || !shown(text)) continue;
            const lh = parseFloat(getComputedStyle(text).lineHeight) || 16;
            if (rect(text).height > lh * 1.5 && rect(text).width < rect(line).width * 0.8) {
              narrowWarning.push(text.textContent.replace(/\s+/g, " ").trim().slice(0, 30));
            }
          }
          const walker = document.createTreeWalker(w, NodeFilter.SHOW_TEXT);
          for (let node = walker.nextNode(); node; node = walker.nextNode()) {
            if (!node.textContent.trim()) continue;
            const el = node.parentElement;
            if (!el || !shown(el) || el.closest(".visually-hidden, .widget__head .section-info, [hidden]")) continue;
            const r = el.getBoundingClientRect();
            if (r.width < 2 || r.height < 2) continue;
            let size = parseFloat(getComputedStyle(el).fontSize);
            const svg = el.closest("svg");
            if (svg) {
              const vb = svg.viewBox && svg.viewBox.baseVal;
              if (vb && vb.width) size = size * (rect(svg).width / vb.width);
            }
            if (size < 11.95) {
              const cls = typeof el.className === "string" ? el.className : el.getAttribute("class") || "";
              tinyText.push(
                node.textContent.replace(/\s+/g, " ").trim().slice(0, 24) + " at " + size.toFixed(1) + " px (" +
                  el.tagName.toLowerCase() + (cls ? "." + cls.trim().split(/\s+/).join(".") : "") +
                  (el.parentElement ? " in " + el.parentElement.tagName.toLowerCase() + "." + (typeof el.parentElement.className === "string" ? el.parentElement.className.trim().split(/\s+/).join(".") : "") : "") +
                  ")"
              );
            }
          }
          const frame = rect(w);
          for (const cell of w.querySelectorAll("th, td")) {
            if (!shown(cell)) continue;
            let scrolled = false;
            for (let box = cell.parentElement; box && box !== w; box = box.parentElement) {
              const ox = getComputedStyle(box).overflowX;
              if (ox === "auto" || ox === "scroll") {
                scrolled = true;
                break;
              }
            }
            if (!scrolled && rect(cell).right > frame.right + 1) {
              tableOver.push(cell.textContent.replace(/\s+/g, " ").trim().slice(0, 24));
              break;
            }
          }
          // A table meant to fit (`.risk-fit-table`, the Risk tab's: „these
          // tables are meant to fit, not to scroll“) never scrolls
          // sideways in a widget either (finding 6).
          for (const table of w.querySelectorAll(".risk-fit-table")) {
            const box = table.parentElement;
            if (shown(table) && box && box.scrollWidth > box.clientWidth + 1) {
              tableOver.push(table.className + " scrolls by " + (box.scrollWidth - box.clientWidth) + " px");
            }
          }
        }

        // The footer whole or wrapped, never cut, in the compact forms
        // (the S32 closing act: „Ans…“ and „Nicht i…“ at 393 px).
        const footCut = [];
        if (!wideGrid) {
          for (const el of w.querySelectorAll(":scope > .widget__foot > span, :scope > .widget__foot .widget-warning__text")) {
            if (shown(el) && el.scrollWidth > el.clientWidth + 1) {
              footCut.push(el.textContent.replace(/\s+/g, " ").trim().slice(0, 40));
            }
          }
        }

        const edit = (sel) => {
          const el = w.querySelector(sel);
          return shown(el) ? rect(el).toJSON() : null;
        };

        // A fixed tile shows what fits (Sprint 32 E4, L3): a row the tile
        // cuts — part of it drawn, part of it under the edge of the box
        // that clips it — is named; a row wholly past the edge is not
        // drawn and not named.
        const rowsCut = [];
        if (wideGrid && !w.classList.contains("widget--row")) {
          const rows = w.querySelectorAll(
            ".widget__wide tr, .widget__wide li, .widget__wide .widget-row, .widget__wide .attention-item, .widget__foot > *"
          );
          for (const row of rows) {
            if (!shown(row)) continue;
            const r = rect(row);
            if (r.height < 2) continue;
            let edge = null;
            for (let box = row.parentElement; box && box !== w.parentElement; box = box.parentElement) {
              if (getComputedStyle(box).overflowY !== "visible") {
                const b = rect(box);
                edge = edge === null ? b.bottom : Math.min(edge, b.bottom);
              }
            }
            if (edge !== null && r.top < edge - 1 && r.bottom > edge + 1) {
              rowsCut.push((row.textContent || "").replace(/\s+/g, " ").trim().slice(0, 40) || row.tagName);
            }
          }
        }

        return {
          name,
          kind: w.dataset.widgetKind,
          size: w.dataset.size,
          frame: frame.toJSON(),
          titleLines: t && lineHeight ? Math.round(t.height / lineHeight) : null,
          // The wide head cuts a title too long for its tile with an
          // ellipsis, as board 07 ② draws it; the compact forms never.
          // Board 07 ② draws a too-long title cut with an ellipsis, but no
          // kind's title is cut on its own tile: a title too long for its
          // S is the kind's to shorten (L2), so every class is checked.
          titleCut: title ? title.scrollWidth - title.clientWidth : 0,
          rowsCut,
          wideGrid,
          offLine,
          cut,
          boxes,
          cards,
          offSizes,
          footCut,
          smallText,
          headCut,
          narrowWarning,
          tinyText,
          tableOver,
          border: ws.borderTopWidth,
          radius: ws.borderTopLeftRadius,
          shadow: ws.boxShadow,
          outline: ws.outlineStyle,
          handle: edit("[data-role='edit-handle']"),
          remove: edit("[data-role='edit-remove']"),
          sizes: edit(".widget__sizes")
        };
      })
    };
  });
}

const inside = (part, f) =>
  part.left >= f.left - 0.5 && part.right <= f.right + 0.5 && part.top >= f.top - 0.5 && part.bottom <= f.bottom + 0.5;

function check(tag, viewport, m, errors) {
  if (m.widgets.length === 0) return errors.push(tag + ": no widget on the grid");
  if (m.grid.radius !== "16px") errors.push(tag + ": the surface's corner is " + m.grid.radius + ", not 16px");
  if (m.grid.border !== "1px solid") errors.push(tag + ": the surface's frame is " + m.grid.border + ", not 1px solid");

  for (const w of m.widgets) {
    if (w.wideGrid && w.titleLines !== 1) errors.push(tag + ": " + w.name + "'s title wraps over " + w.titleLines + " lines");
    if (w.titleCut > 1) errors.push(tag + ": " + w.name + "'s title is cut by " + w.titleCut + " px");
    for (const row of w.rowsCut) errors.push(tag + ": " + w.name + "'s tile cuts a row: " + row);
    if (w.offLine.length > 0) errors.push(tag + ": " + w.name + "'s head wraps: " + w.offLine.join(", ") + " off the title's line");
    for (const c of w.cut) errors.push(tag + ": " + w.name + " clips a figure: " + c);
    if (w.boxes.length > 0) errors.push(tag + ": " + w.name + " carries a warning box (" + w.boxes[0] + ")");
    for (const c of w.cards) errors.push(tag + ": " + w.name + " carries a card: " + c);
    for (const s of w.offSizes) errors.push(tag + ": " + w.name + " sets a figure off the anatomy's sizes: " + s);
    for (const f of w.footCut) errors.push(tag + ": " + w.name + "'s footer is cut: " + f);
    for (const n of w.narrowWarning) errors.push(tag + ": " + w.name + " wraps its warning in a narrow column: " + n);
    for (const t of w.tinyText) errors.push(tag + ": " + w.name + " draws text under 12 px: " + t);
    for (const c of w.tableOver) errors.push(tag + ": " + w.name + "'s table runs past the widget: " + c);
    for (const h of w.headCut) errors.push(tag + ": " + w.name + " cuts a table head: " + h);
    for (const t of w.smallText) errors.push(tag + ": " + w.name + " draws chart text under 12 px: " + t);
    if (w.border !== "0px") errors.push(tag + ": " + w.name + " draws a card border of " + w.border);
    if (w.radius !== "0px") errors.push(tag + ": " + w.name + " rounds its own corner, " + w.radius);
    if (w.shadow !== "none" && !/^rgb[a]?\([^)]*\) 0px 0px 0px 1px$/.test(w.shadow)) {
      errors.push(tag + ": " + w.name + " casts a shadow, " + w.shadow);
    }
    if (m.grid.editing) {
      if (w.outline !== "dashed") errors.push(tag + ": " + w.name + " has no dashed outline in the edit mode");
      for (const [part, box] of [["handle", w.handle], ["×", w.remove], ["size switch", w.sizes]]) {
        if (box && !inside(box, w.frame)) errors.push(tag + ": " + w.name + "'s " + part + " stands outside its cell");
      }
    }
  }

  // A lone S in the compact class (the S32 closing act's UAT, finding
  // 11): an S with no widget beside it spans the grid's width, never half
  // of it with the other half empty.
  if (viewport.width < 600) {
    for (const a of m.widgets) {
      if (a.size !== "S" || a.frame.width > m.grid.width * 0.6) continue;
      const beside = m.widgets.some(
        (b) => b !== a && Math.min(a.frame.bottom, b.frame.bottom) - Math.max(a.frame.top, b.frame.top) > 2
      );
      if (!beside) errors.push(tag + ": " + a.name + " stands alone at half the width");
    }
  }

  // The hairline: in the wide grid two widgets side by side or one under
  // the other stand 1 px apart, never more.
  if (viewport.width >= 1000) {
    for (const a of m.widgets) {
      for (const b of m.widgets) {
        if (a === b) continue;
        const overlapY = Math.min(a.frame.bottom, b.frame.bottom) - Math.max(a.frame.top, b.frame.top);
        const overlapX = Math.min(a.frame.right, b.frame.right) - Math.max(a.frame.left, b.frame.left);
        const gapX = b.frame.left - a.frame.right;
        const gapY = b.frame.top - a.frame.bottom;
        if (overlapY > 2 && gapX > 1.5 && gapX < 40) {
          errors.push(tag + ": " + a.name + " and " + b.name + " stand " + gapX.toFixed(1) + " px apart, not the hairline");
        }
        if (overlapX > 2 && gapY > 1.5 && gapY < 40) {
          errors.push(tag + ": " + a.name + " and " + b.name + " stand " + gapY.toFixed(1) + " px apart, not the hairline");
        }
      }
    }
  }
}

// The attack: each rule broken once on the walked page.
function breakEach(page, viewport) {
  return page.evaluate((wide) => {
    const widgets = Array.from(document.querySelectorAll("#dashboard-grid > .dashboard-widget"));
    const first = widgets[0];
    const second = widgets[1];
    const title = first.querySelector(".widget__head h2");
    title.textContent = "Ein Titel aus vielen Worten";
    title.style.width = "6ch";
    title.style.minWidth = "6ch";
    // The wide grid: over several lines; the compact forms: cut.
    title.style.whiteSpace = wide ? "normal" : "nowrap";
    title.style.overflow = "hidden";
    // The third widget's period mark set on a line of its own.
    const head = widgets[2].querySelector(".widget__head > .section-title");
    const mark = head.querySelector("[data-role='widget-period']");
    head.style.flexWrap = "wrap";
    mark.style.flexBasis = "100%";
    const figure = document.createElement("span");
    figure.className = "widget-row__figure num";
    figure.textContent = "1.234.567.890.123.456.789.012.345.678,90 EUR";
    figure.style.display = "block";
    figure.style.width = "40px";
    figure.style.overflow = "hidden";
    second.appendChild(figure);
    const note = document.createElement("div");
    note.className = "data-note data-note--attention";
    note.textContent = "ACHTUNG";
    note.style.border = "1px solid currentColor";
    note.style.background = "var(--color-warning-soft)";
    second.appendChild(note);
    // A table's figure cut by its cell (the S32 closing act), wider than
    // any widget, so a stylesheet that widens the table cannot hide it.
    const table = document.createElement("table");
    table.style.display = "table";
    table.style.tableLayout = "fixed";
    table.style.width = "60px";
    table.innerHTML =
      "<thead><tr><th style='width: 40px; overflow: hidden; white-space: nowrap; text-overflow: ellipsis'>Benchmark und noch mehr</th></tr></thead>" +
      "<tbody><tr><td style='width: 40px; overflow: hidden; white-space: nowrap'><span class='num'>Zelle −98,76 % · 1.234.567.890.123.456.789,01 EUR · 9.876.543.210,98 EUR</span></td></tr></tbody>";
    second.appendChild(table);
    // A card inside the widget, its figure off the anatomy's sizes.
    const card = document.createElement("article");
    card.className = "stat";
    card.style.cssText =
      "display: block; padding: 18px; border: 1px solid #ccc; border-radius: 12px; box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2)";
    card.innerHTML = "<span>Karte</span> <strong style='font-size: 31px; font-weight: 700'>+1,0 %</strong>";
    second.appendChild(card);
    // A footer cut with an ellipsis (the compact forms, at 393 px).
    const foot = document.createElement("footer");
    foot.className = "widget__foot";
    foot.innerHTML =
      "<span style='display: block; flex: none; width: 50px; overflow: hidden; white-space: nowrap; text-overflow: ellipsis'>Ansicht Alles · ein langer Fuß</span>";
    second.appendChild(foot);
    // A chart in a widget whose label is drawn at 9 CSS px: a 960-unit
    // viewBox drawn 480 px wide, its text 18 units.
    const chart = document.createElement("div");
    chart.dataset.role = "cycle-widget-chart";
    // The compact classes (the S32 closing act's UAT, findings 3, 4, 6,
    // 11): a warning wrapped in a 60 px column, an 11 px line, a table
    // wider than the widget, and an S set at half the width alone.
    if (!wide) {
      const warning = document.createElement("p");
      warning.className = "widget-warning";
      warning.innerHTML =
        "<span class='widget-warning__text' style='display: block; flex: none; width: 60px; white-space: normal'>Nicht in der Summe: drei Konten</span>";
      second.appendChild(warning);
      const tiny = document.createElement("span");
      tiny.textContent = "Elf Pixel";
      tiny.style.fontSize = "11px";
      second.appendChild(tiny);
      const over = document.createElement("table");
      over.style.cssText = "display: table; width: 900px";
      over.innerHTML = "<tbody><tr><td>Breite Tabelle</td></tr></tbody>";
      second.appendChild(over);
      const fit = document.createElement("div");
      fit.className = "data-table-wrapper";
      fit.style.cssText = "overflow-x: auto; width: 100px";
      fit.innerHTML =
        "<table class='risk-fit-table' style='display: table; width: 600px'><tbody><tr><td>Passt nicht</td></tr></tbody></table>";
      second.appendChild(fit);
      const lone = widgets.filter((x) => x.dataset.size === "S").pop();
      if (lone) {
        const others = widgets.filter((x) => x !== lone);
        lone.style.gridColumn = "span 1";
        lone.style.gridRow = "999";
        others.forEach((x) => x.style.gridRow === "999" && (x.style.gridRow = ""));
      }
    }
    chart.innerHTML =
      "<svg viewBox='0 0 960 320' style='display: block; width: 480px; height: 160px'><text x='10' y='40' style='font-size: 18px'>Top-Band 4.500 USD</text></svg>";
    second.appendChild(chart);
    second.style.border = "1px solid red";
    if (wide) {
      document.querySelector("#dashboard-grid").style.gap = "12px";
      // A fourth widget's title cut, a list's wide form cut mid-row.
      const cutTitle = widgets[3].querySelector(".widget__head h2");
      cutTitle.textContent = "Ein Titel, der in keine Kachel passt, auch nicht in die breiteste";
      const listed = widgets.find((w) => w.querySelector(".widget__wide li"));
      const body = listed.querySelector(".widget__wide");
      const row = body.querySelector("li").getBoundingClientRect();
      body.style.flex = "none";
      body.style.height = row.top - body.getBoundingClientRect().top + row.height / 2 + "px";
    }
  }, viewport.width >= 1000);
}

async function walk(browser, viewport, errors, attack) {
  const tag = viewport.width + " px";
  const context = await browser.newContext({ viewport, locale: "de-DE" });
  const page = await context.newPage();
  await visit(page, base + "/dashboards/" + id + "?locale=de");
  await settle(page);

  if (attack) await breakEach(page, viewport);

  const measured = await eachFont(page, async (font) => {
    const m = await measure(page);
    check(tag + " " + font.name, viewport, m, errors);
    return m.widgets.length;
  });

  if (shots && !attack) {
    for (const theme of ["light", "dark"]) {
      await page.evaluate((t) => document.documentElement.setAttribute("data-theme", t), theme);
      await page.screenshot({ path: path.join(shots, "anatomy-" + id + "-" + viewport.width + "-" + theme + ".png"), fullPage: true });
    }
    await page.evaluate(() => document.documentElement.setAttribute("data-theme", "light"));
  }

  // The edit mode at the wide grid: the controls inside each cell.
  if (viewport.width >= 1000) {
    await page.click("[data-role='edit-start']");
    await page.waitForSelector("[data-role='dashboard-grid'][data-editing='true'] [data-role='edit-handle']", {
      state: "attached",
      timeout: 10000
    });
    await settle(page);
    if (attack) {
      await page.evaluate(() => {
        const handle = document.querySelector("[data-role='edit-handle']");
        handle.style.position = "absolute";
        handle.style.top = "-20px";
      });
    }
    const m = await measure(page);
    check(tag + " edit", viewport, m, errors);
    if (shots && !attack) {
      await page.screenshot({ path: path.join(shots, "anatomy-" + id + "-" + viewport.width + "-edit.png"), fullPage: true });
    }
  }

  await leave(context);
  return measured[0];
}

(async () => {
  const browser = await launchChromium();
  const errors = [];
  const measured = {};
  try {
    for (const viewport of WIDTHS) {
      const caught = [];
      const count = await walk(browser, viewport, mode === "attack" ? caught : errors, mode === "attack");
      measured[viewport.width] = mode === "attack" ? { caught } : { widgets: count };
    }
    process.stdout.write(
      JSON.stringify(errors.length === 0 ? { ok: true, measured } : { ok: false, error: errors.join("; ") }) + "\n"
    );
  } catch (error) {
    process.stdout.write(JSON.stringify({ ok: false, error: String(error && error.message), before: errors }) + "\n");
  } finally {
    await leave(browser);
  }
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
