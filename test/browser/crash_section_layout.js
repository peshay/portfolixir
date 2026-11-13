// The Crashes section on Wealth › Risk at 1200 and 390 px (Sprint 29 C6;
// board ux-design-2026-11-12-sprint29/01 ① and ⑨, plan D-5 P2 and P5),
// driven in a real Chromium by test/browser/crash_section_layout_test.exs,
// which boots the endpoint and passes the section's URL as one JSON
// argument. At each width it measures the bar of labelled controls (one
// line at 1200 px; the controls from one edge once it wraps at 390 px),
// the list's rows (one line each at 1200 px; two lines, the bar under the
// name, at 390 px), the benchmark's dashed line inside each bar's track,
// and that the page never scrolls sideways, each in Inter and in the
// fallback font, DejaVu Sans (fonts.js). The closing act adds: the bar
// one line at 1200 px with a long manual window in the select; the list's
// columns, the rebounders' six included, inside the section at 1200 px;
// the windows table's actions inside it at 1200 px; and at 390 px the
// dashed lines under each row's name line, never across it.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "error":
// "...", "seen": {...}}; the exit status is 0 either way unless the browser
// itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { visit, leave } = require("./settle");
const { FONTS, eachFont } = require("./fonts");

const args = JSON.parse(process.argv[2]);

async function measure(page) {
  return page.evaluate(() => {
    const round = (value) => Math.round(value * 10) / 10;
    const box = (node) => {
      if (!node) return null;
      const b = node.getBoundingClientRect();
      return { top: round(b.top), bottom: round(b.bottom), left: round(b.left), right: round(b.right) };
    };
    const section = document.getElementById("risk-crashes");
    if (!section) return null;
    const controls = ["#crash-window", "[data-role=crash-list]", "[data-role=crash-universe]"].map((selector) =>
      box(section.querySelector(selector))
    );
    const rows = Array.from(section.querySelectorAll("table.crash-table tbody tr")).map((row) => ({
      row: box(row),
      name: box(row.querySelector(".crash-name")),
      figure: box(row.querySelector(".crash-fig")),
      track: box(row.querySelector(".crash-track")),
      ref: box(row.querySelector(".crash-track__ref")),
      zero: box(row.querySelector(".crash-track__zero")),
      bar: box(row.querySelector(".crash-track__bar"))
    }));
    // A table fits when its wrapper scrolls nothing sideways.
    const fit = (table) => {
      if (!table) return null;
      const wrapper = table.closest(".data-table-wrapper");
      return {
        wrapper: box(wrapper),
        scroll: wrapper.scrollWidth,
        client: wrapper.clientWidth,
        heads: Array.from(table.querySelectorAll("thead th")).map(box),
        actions: Array.from(table.querySelectorAll("td.crash-actions button")).map(box)
      };
    };
    // The width each window's option needs in the select, measured in a
    // copy of the select that holds it alone, with no cap (PR 2's closing
    // act, board 06 ⑫).
    const select = section.querySelector("#crash-window");
    const options = select
      ? Array.from(select.options).map((option) => {
          const probe = select.cloneNode(false);
          probe.removeAttribute("id");
          probe.style.cssText = "max-width: none; width: auto; position: absolute; visibility: hidden;";
          probe.appendChild(new Option(option.text));
          select.parentElement.appendChild(probe);
          const needed = probe.getBoundingClientRect().width;
          probe.remove();
          return { text: option.text, needed: round(needed), width: round(select.getBoundingClientRect().width) };
        })
      : [];
    return {
      viewport: window.innerWidth,
      scrollWidth: document.documentElement.scrollWidth,
      section: box(section),
      line: box(section.querySelector("[data-role=crash-bar] .control-bar__controls")),
      options,
      controls,
      rows,
      list: fit(section.querySelector("table.crash-table")),
      windows: fit(section.querySelector("#crash-windows-table"))
    };
  });
}

// `font` is the font the page was measured in (fonts.js): the first is the
// page's own, Inter.
function check(seen, width, font) {
  const errors = [];
  if (!seen) return ["no Crashes section"];
  if (seen.scrollWidth > seen.viewport) errors.push(width + " px: the page scrolls sideways: " + seen.scrollWidth);
  if (seen.controls.some((control) => !control)) errors.push(width + " px: a control of the bar is missing");
  if (seen.rows.length < 2) errors.push(width + " px: fewer than two rows, so the case is not measured");
  if (errors.length > 0) return errors;

  const [select, list, universe] = seen.controls;
  if (width >= 1000) {
    // One line while it fits.
    const middles = seen.controls.map((c) => (c.top + c.bottom) / 2);
    if (Math.max(...middles) - Math.min(...middles) > 4) errors.push("1200 px: the bar is not one line");
    if (!(select.right <= list.left && list.right <= universe.left))
      errors.push("1200 px: the window's select is not the bar's first control");
    // A manual window of a short name, as the review seed's, reads whole
    // in the select at 1200 px in Inter (board 06 ⑫); a long one is cut at
    // the cap. In the fallback font the line needs more than the 924 px
    // bar with the select at its cap, so the select takes the room the
    // line leaves (board 06 ⑮): a window is cut there only while the line
    // is full, its last control at the bar's end.
    const full = universe.right >= seen.line.right - 1;
    for (const option of seen.options.filter((o) => o.text.startsWith("Synthetic dip"))) {
      if (option.needed > option.width + 0.5 && (font === FONTS[0] || !full))
        errors.push(
          "1200 px: the window „" + option.text + "“ is cut: it needs " + option.needed + " px in a " + option.width +
            " px select" + (full ? "" : ", and the line ends " + Math.round(seen.line.right - universe.right) + " px before the bar")
        );
    }
    if (!seen.options.some((o) => o.text.startsWith("Synthetic dip"))) errors.push("1200 px: no short manual window in the select");
  } else {
    // Wrapped: every control starts on one edge.
    const lefts = seen.controls.map((c) => c.left);
    if (Math.max(...lefts) - Math.min(...lefts) > 1) errors.push(width + " px: the controls start on " + lefts.join(", "));
    if (!(select.top < list.top && list.top < universe.top)) errors.push(width + " px: the controls are not stacked");
  }

  if (width >= 1000) {
    for (const [name, table] of [["the list", seen.list], ["the windows table", seen.windows]]) {
      if (!table) continue;
      if (table.scroll > table.client + 0.5)
        errors.push("1200 px: " + name + " scrolls sideways: " + table.scroll + " in " + table.client);
      const right = table.wrapper.right + 0.5;
      if (table.heads.some((h) => h.right > right)) errors.push("1200 px: a column of " + name + " is cut off");
      if (table.actions.some((a) => a.right > right)) errors.push("1200 px: an action of " + name + " is cut off");
    }
  }

  for (const [index, r] of seen.rows.entries()) {
    const inside = [r.name, r.figure, r.track].every((b) => b && b.right <= seen.section.right + 0.5);
    if (!inside) errors.push(width + " px: row " + (index + 1) + " runs past the section");
    if (!r.track || r.track.right - r.track.left < 60) errors.push(width + " px: row " + (index + 1) + "'s bar has no room");
    if (r.ref && (r.ref.left < r.track.left - 0.5 || r.ref.left > r.track.right + 0.5))
      errors.push(width + " px: row " + (index + 1) + "'s dashed line is outside its track");
    if (!r.bar || r.bar.right - r.bar.left <= 0) errors.push(width + " px: row " + (index + 1) + " draws no bar");
    if (width >= 1000) {
      if (r.track.top > r.name.bottom || r.track.bottom < r.name.top) errors.push("1200 px: row " + (index + 1) + " is not one line");
    } else {
      if (r.track.top < r.name.bottom - 0.5) errors.push(width + " px: row " + (index + 1) + "'s bar is not under its name");
      for (const [what, line] of [["dashed line", r.ref], ["zero line", r.zero]]) {
        if (line && line.top < r.name.bottom - 0.5)
          errors.push(width + " px: row " + (index + 1) + "'s " + what + " crosses its name line");
      }
      if (Math.abs((r.figure.top + r.figure.bottom) / 2 - (r.name.top + r.name.bottom) / 2) > 4)
        errors.push(width + " px: row " + (index + 1) + "'s figure is not beside its name");
    }
  }
  return errors;
}

async function run(browser) {
  const errors = [];
  const seenAll = {};
  for (const width of [1200, 390]) {
    const phone = width < 600;
    const context = await browser.newContext({
      viewport: { width, height: phone ? 844 : 900 },
      hasTouch: phone,
      isMobile: phone,
      locale: "de-DE"
    });
    const page = await context.newPage();
    for (const [list, url] of [["losers", args.url], ["rebounders", args.rebounders]]) {
      if (!url) continue;
      await visit(page, url);
      await page.waitForSelector("[data-phx-main].phx-connected");
      await page.waitForSelector("#risk-crashes table.crash-table tbody tr");
      await page.evaluate(() => {
        const windows = document.getElementById("crash-windows");
        if (windows) windows.open = true;
      });
      // In Inter and in the fallback font (fonts.js).
      await eachFont(page, async (font) => {
        const seen = await measure(page);
        seenAll[width + " " + list + " " + font.name] = seen;
        errors.push(...check(seen, width, font).map((error) => list + " in " + font.name + ": " + error));
      });
    }
    await leave(context);
  }
  return { errors, seen: seenAll };
}

(async () => {
  const browser = await launchChromium();
  try {
    const { errors, seen } = await run(browser);
    process.stdout.write(
      JSON.stringify(errors.length === 0 ? { ok: true } : { ok: false, error: errors.join("; "), seen }) + "\n"
    );
  } catch (error) {
    process.stdout.write(JSON.stringify({ ok: false, error: String(error && error.message) }) + "\n");
  } finally {
    await leave(browser);
  }
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
