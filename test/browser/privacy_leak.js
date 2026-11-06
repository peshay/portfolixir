// The privacy mode's leak test (Sprint 26 P3, I22, FR-51; plan D-1 exit
// criterion 3): with the mode switched on through its own switch, every page
// of the shell — each live route the router lists, each area tab it links
// and each detail tab it offers — is walked in both themes at 1200 and
// 390 px, and the walk fails on any figure in a currency or quantity it
// finds: in the visible text, in the live document (attributes, hidden
// text, a chart's JSON payload) and in the page source the server sent.
// Driven by test/browser/privacy_leak_test.exs, which boots the endpoint on
// the review seed and passes its base URL and a JSON file of the pages to
// walk.
//
// Prints one JSON object on stdout: {"ok": true, "visited": n} or
// {"ok": false, "error": "...", "findings": [...]}; the exit status is 0
// either way unless the browser itself fails.
"use strict";

const fs = require("fs");
const { launchChromium } = require("./launch");

const base = process.argv[2];
const pages = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
const only = process.env.PRIVACY_LEAK_ONLY || null;

const WIDTHS = [
  { width: 1200, height: 900 },
  { width: 390, height: 844 }
];
const THEMES = ["light", "dark"];

// Runs in the page: every figure in a currency or quantity it can find.
// The pages render in German (`locale: de-DE`), so an amount is digits with
// a decimal comma, thousands grouped by dots: "88.307,02", "-19,50", "0,00".
// What stays in the mode is told apart by what follows or precedes it: a
// percentage ("9,0 %", "+9,0%"), percentage points ("1,2 pp"), a ratio
// ("×1,09"). The other figures that stay (a correlation, a rate, a
// risk-adjusted return) sit in the elements `plainSelectors` lists, each
// with the reason it stays. A quantity is also any number its unit names,
// a whole one included: "30 Stück", "12 shares".
function scan(args) {
  const AMOUNT = /(^|[^\d.,])([+\-−]?\d{1,3}(?:\.\d{3})*,\d+)(?![\d,])/g;
  const QUANTITY = /(^|[^\d.,])(\d[\d.,]*)\s*(Stück|shares?|units?)(?![\p{L}])/gu;
  const findings = [];
  const plainBefore = /(×|x)\s*$/;
  const plainAfter = /^\s*(%|pp\b|Pp\b|PP\b|Prozentpunkte|Jahre|years|MB\b|-Fache|times\b)/;

  // Elements whose figures are not amounts and stay in the mode, by the
  // rule (plan D-5: percentages, dates, counts and ratios stay).
  const plainSelectors = args.plainSelectors;

  const inPlain = (el) => {
    for (const sel of plainSelectors) {
      if (el && el.closest && el.closest(sel)) return true;
    }
    return false;
  };

  const amountsIn = (text) => {
    const out = [];
    AMOUNT.lastIndex = 0;
    let m;
    while ((m = AMOUNT.exec(text)) !== null) {
      const start = m.index + m[1].length;
      const before = text.slice(Math.max(0, start - 3), start);
      const after = text.slice(start + m[2].length, start + m[2].length + 16);
      if (plainBefore.test(before) || plainAfter.test(after)) continue;
      out.push(m[2]);
    }
    QUANTITY.lastIndex = 0;
    while ((m = QUANTITY.exec(text)) !== null) out.push(m[2] + " " + m[3]);
    return out;
  };

  // 1. The visible text, node by node, so a hit names its element.
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  while (walker.nextNode()) {
    const node = walker.currentNode;
    const el = node.parentElement;
    if (!el || el.closest("script, style, template")) continue;
    if (inPlain(el)) continue;
    const rect = el.getBoundingClientRect();
    const style = getComputedStyle(el);
    const visible = rect.width > 0 && rect.height > 0 && style.visibility !== "hidden" && style.display !== "none";
    for (const hit of amountsIn(node.nodeValue)) {
      findings.push({ where: visible ? "visible text" : "hidden text", hit, context: describe(el) });
    }
    // Board 01, look C: a hidden figure on the screen is the bar, never its
    // stand-in text (which a string carries where no markup can go).
    if (visible && node.nodeValue.includes("••••")) {
      findings.push({ where: "visible text", hit: "a hidden figure drawn as text, not as the bar", context: describe(el) });
    }
  }

  // 2. Every attribute of every element. One a reader meets (a native
  // tooltip, an accessible name, an input's value) is read like text; one
  // written for a script (`data-*`, `phx-value-*`) is an amount when its
  // name says so and it holds a digit, whatever its form ("1263.00").
  // A chart's geometry is ratios and coordinates (board 02) and is not read.
  const READ = /^(title|aria-label|aria-description|aria-valuetext|alt|placeholder|value|label|content)$/;
  for (const el of document.querySelectorAll("*")) {
    if (inPlain(el)) continue;
    for (const attr of el.attributes) {
      const value = attr.value;
      if (/class=pf-mask/.test(value)) {
        findings.push({ where: "attribute " + attr.name, hit: "a hidden figure's markup inside an attribute", context: describe(el) });
        continue;
      }
      if (READ.test(attr.name)) {
        for (const hit of amountsIn(value)) {
          findings.push({ where: "attribute " + attr.name, hit, context: describe(el) });
        }
      } else if (new RegExp(args.amountData).test(attr.name) && /\d/.test(value)) {
        findings.push({ where: "attribute " + attr.name, hit: value, context: describe(el) });
      }
    }
  }

  // An input that holds a figure for editing: its value is in the page
  // source whatever its form ("1234.5"). An identifier or a count is not
  // a figure: only a value with a decimal separator, or an input whose
  // name says amount, is read.
  for (const input of document.querySelectorAll("input, textarea")) {
    if (inPlain(input)) continue;
    const value = input.value || input.getAttribute("value") || "";
    const name = (input.getAttribute("name") || "") + " " + (input.id || "");
    if (!/\d/.test(value)) continue;
    if (/^-?\d+[.,]\d+$/.test(value.trim()) || new RegExp(args.amountName, "i").test(name)) {
      findings.push({ where: "input value", hit: value, context: describe(input) + " [" + name.trim() + "]" });
    }
  }

  // 3. A chart's payload: its display strings and its trades.
  for (const node of document.querySelectorAll("script[data-chart-payload]")) {
    let payload = null;
    try {
      payload = JSON.parse(node.textContent);
    } catch (_) {
      findings.push({ where: "chart payload", hit: "unreadable", context: describe(node.parentElement) });
      continue;
    }
    for (const point of payload.points || []) {
      for (const hit of amountsIn(String(point[1]))) {
        findings.push({ where: "chart payload point", hit, context: describe(node.parentElement) });
      }
    }
    for (const tx of payload.txs || []) {
      for (const key of ["quantity", "price"]) {
        if (tx[key] !== undefined && tx[key] !== null && /\d/.test(String(tx[key]))) {
          findings.push({ where: "chart payload trade " + key, hit: String(tx[key]), context: describe(node.parentElement) });
        }
      }
      for (const hit of amountsIn(String(tx.label || ""))) {
        findings.push({ where: "chart payload trade label", hit, context: describe(node.parentElement) });
      }
    }
  }

  function describe(el) {
    if (!el) return "";
    const parts = [];
    let n = el;
    for (let i = 0; n && n !== document.body && i < 4; i++) {
      let s = n.tagName.toLowerCase();
      if (n.id) s += "#" + n.id;
      else if (n.classList.length) s += "." + [...n.classList].slice(0, 2).join(".");
      parts.unshift(s);
      n = n.parentElement;
    }
    return parts.join(" > ");
  }

  return findings;
}

// The page source the server sent for `url`, with the browser's cookies:
// every figure in it is one the page carried before any script ran.
async function sourceFindings(context, url, plainSelectors, amountData, amountName) {
  const response = await context.request.get(url, { headers: { "accept-language": "de-DE" } });
  const html = await response.text();
  const page = await context.newPage();
  try {
    await page.setContent(html.replace(/<script(?![^>]*data-chart-payload)[\s\S]*?<\/script>/g, ""), { waitUntil: "domcontentloaded" });
    return await page.evaluate(scan, { plainSelectors, amountData, amountName });
  } finally {
    await page.close();
  }
}

// Waits until the page at `url` is connected and its loads have landed.
async function settle(page) {
  await page.waitForFunction(() => document.querySelector("[data-phx-main].phx-connected") !== null, null, { timeout: 15000 });
  await page
    .waitForFunction(() => document.querySelector("[aria-busy='true'], .phx-loading, .value-slot-pending") === null, null, { timeout: 8000 })
    .catch(() => {});
  await page.waitForTimeout(250);
}

function short(findings) {
  const seen = new Set();
  const out = [];
  for (const f of findings) {
    const key = f.where + "|" + f.context + "|" + f.hit;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(f);
  }
  return out;
}

(async () => {
  const browser = await launchChromium();
  const findings = [];
  let visited = 0;
  const amountData = pages.amountData;
  const amountName = pages.amountName;
  const plainSelectors = pages.plainSelectors;
  const sourceChecked = new Set();
  try {
    for (const theme of THEMES) {
      for (const viewport of WIDTHS) {
        const context = await browser.newContext({ viewport, locale: "de-DE" });
        await context.addInitScript((th) => {
          try {
            localStorage.setItem("portfolixir-theme", th);
          } catch (_) {}
        }, theme);
        const page = await context.newPage();

        // The switch itself: off on a first visit, on after one press, and
        // the address carries no choice afterwards.
        await page.goto(base + "/");
        await settle(page);
        const before = await page.getAttribute("#privacy-mode", "aria-pressed");
        if (before !== "false") throw new Error("the switch was pressed on a first visit: " + before);
        await Promise.all([page.waitForURL((u) => !u.search.includes("privacy=")), page.click("#privacy-mode")]);
        await settle(page);
        const after = await page.getAttribute("#privacy-mode", "aria-pressed");
        if (after !== "true") throw new Error("the switch did not turn the mode on: " + after);

        const queue = pages.urls.slice();
        const queued = new Set(queue);
        while (queue.length) {
          const path = queue.shift();
          if (only && !path.startsWith(only)) continue;
          const tag = theme + " " + viewport.width + " " + path;
          await page.goto(base + path);
          await settle(page);
          visited++;
          for (const f of await page.evaluate(scan, { plainSelectors, amountData, amountName })) {
            findings.push({ page: tag, ...f });
          }

          if (!sourceChecked.has(path)) {
            sourceChecked.add(path);
            for (const f of await sourceFindings(context, base + path, plainSelectors, amountData, amountName)) {
              findings.push({ page: "source " + path, ...f });
            }
          }

          // The area tabs the page links: each is a page of the shell.
          const links = await page.$$eval("#area-tabs a[href]", (as) => as.map((a) => a.getAttribute("href")));
          for (const href of links) {
            const url = new URL(href, base);
            if (url.origin !== new URL(base).origin) continue;
            const next = url.pathname + url.search;
            if (!queued.has(next)) {
              queued.add(next);
              queue.push(next);
            }
          }

          // The detail tabs it offers (buttons): each is pressed and read.
          const tabs = await page.$$eval("[data-tab-level='2'] [role='tab']", (bs) => bs.map((b) => b.id).filter(Boolean));
          for (const id of tabs) {
            await page.click("#" + id);
            await settle(page);
            visited++;
            for (const f of await page.evaluate(scan, { plainSelectors, amountData, amountName })) {
              findings.push({ page: tag + " #" + id, ...f });
            }
          }

          // The page's own extra views the mode changes (P2): each pressed
          // and read, e.g. Wealth's "Value" series.
          for (const sel of pages.extraClicks) {
            const handle = await page.$(sel);
            if (!handle) continue;
            await handle.click();
            await settle(page);
            for (const f of await page.evaluate(scan, { plainSelectors, amountData, amountName })) {
              findings.push({ page: tag + " " + sel, ...f });
            }
          }
        }
        await context.close();
      }
    }

    const unique = short(findings);
    if (unique.length) {
      process.stdout.write(JSON.stringify({ ok: false, error: unique.length + " figure(s) leaked", visited, findings: unique.slice(0, 2000) }) + "\n");
    } else {
      process.stdout.write(JSON.stringify({ ok: true, visited }) + "\n");
    }
  } catch (error) {
    process.stdout.write(JSON.stringify({ ok: false, error: String(error && error.message), findings: short(findings).slice(0, 2000) }) + "\n");
  } finally {
    await browser.close();
  }
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
