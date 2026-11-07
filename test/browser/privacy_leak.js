// The privacy mode's leak test (Sprint 26 P3, I22, FR-51; plan D-1 exit
// criterion 3): with the mode switched on through its own switch, every page
// of the shell — each live route the router lists, each area tab it links,
// each detail tab it offers and each view it links in place (Cash flow's
// facets, "After the sale"'s comparison modes, any link naming a tab) — is
// walked in both themes at 1200 and 390 px, and the walk fails on any
// figure in a currency or quantity it finds: in the visible text, in the
// live document (attributes, hidden text, a chart's JSON payload) and in
// the page source the server sent. It fails as well on any step that did
// not render: an error status, a crashed LiveView, a click that did not
// arrive (fix round of the Sprint 26 closing act). After the pages it opens
// the declared open states — a dialog, a drawer, a flow's preview — each by
// its own clicks, and reads each the same way, an enabled form control's
// value excepted where the state is a form that edits a stored figure
// (DESIGN.md → Privacy mode, "Forms keep their values"; the privacy lens of
// the closing act).
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
// a decimal comma, thousands grouped by dots: "88.307,02", "-19,50", "0,00";
// one written without its dots ("4250,00", a form's example) is one too.
// What stays in the mode is told apart by what follows or precedes it: a
// percentage ("9,0 %", "+9,0%"), percentage points ("1,2 pp"), a ratio
// ("×1,09"), and the first two items of a JSON array of whole numbers
// ("[36,37]", a stored record's ids in the journal's stored values: a
// comma there separates items and is no decimal comma; the walk flagged it
// only while the ids had at most three digits). The other figures that stay (a correlation, a rate, a
// risk-adjusted return) sit in the elements `plainSelectors` lists, each
// with the reason it stays. A quantity is also any number its unit names,
// a whole one included: "30 Stück", "12 shares".
// In a table cell a raw decimal as stored is an amount too ("123.45",
// "1234.5": the journal's stored values; closing act of Sprint 26, finding
// S2): a point and one to four digits, not part of a word, a time, a German
// date ("06.11.2026", "06.11."), a version ("0.1.14") or a German amount;
// three digits after at most three are a German thousands group ("1.250")
// and a month and a year a German month ("11.2025"), neither a decimal.
function scan(args) {
  const AMOUNT = /(^|[^\d.,])([+\-−]?(?:\d{1,3}(?:\.\d{3})+|\d+),\d+)(?![\d,])/g;
  const QUANTITY = /(^|[^\d.,])(\d[\d.,]*)\s*(Stück|shares?|units?)(?![\p{L}])/gu;
  const RAW = /(^|[^\p{L}\d.,:\/_])([+\-−]?\d+\.\d{1,4})(?![\d.])(?!,\d)/gu;
  const NOT_DECIMAL = [/^[+\-−]?\d{1,3}\.\d{3}$/, /^(0?[1-9]|1[0-2])\.(19|20)\d\d$/];
  const findings = [];
  const plainBefore = /(×|x|\[)\s*$/;
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

  const rawIn = (text) => {
    const out = [];
    RAW.lastIndex = 0;
    let m;
    while ((m = RAW.exec(text)) !== null) {
      const start = m.index + m[1].length;
      const after = text.slice(start + m[2].length, start + m[2].length + 16);
      if (plainAfter.test(after) || NOT_DECIMAL.some((re) => re.test(m[2]))) continue;
      out.push(m[2]);
    }
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
    const hits = amountsIn(node.nodeValue);
    if (el.closest("td, th")) hits.push(...rawIn(node.nodeValue));
    for (const hit of hits) {
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
  // A form that edits a stored figure opens with the real value (DESIGN.md
  // → Privacy mode, "Forms keep their values"): in a state declared so, an
  // enabled control's value is the operator's to edit and is not read. A
  // disabled or read-only control's value is a fact shown, and is.
  const editable = (el) =>
    args.allowFormValues === true &&
    /^(INPUT|TEXTAREA|SELECT|OPTION)$/.test(el.tagName) &&
    !el.disabled &&
    !el.readOnly &&
    !(el.closest && el.closest("select:disabled, fieldset:disabled"));
  for (const el of document.querySelectorAll("*")) {
    if (inPlain(el)) continue;
    for (const attr of el.attributes) {
      const value = attr.value;
      if (/class=pf-mask/.test(value)) {
        findings.push({ where: "attribute " + attr.name, hit: "a hidden figure's markup inside an attribute", context: describe(el) });
        continue;
      }
      if (attr.name === "value" && editable(el)) continue;
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
    if (inPlain(input) || editable(input)) continue;
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
  if (response.status() >= 400) return [{ where: "HTTP status", hit: String(response.status()), context: url }];
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
// False when it never connects: a page that crashed, an error page.
async function settle(page) {
  const connected = await page
    .waitForFunction(() => document.querySelector("[data-phx-main].phx-connected") !== null, null, { timeout: 15000 })
    .then(() => true)
    .catch(() => false);
  await page
    .waitForFunction(() => document.querySelector("[aria-busy='true'], .phx-loading, .value-slot-pending") === null, null, { timeout: 8000 })
    .catch(() => {});
  await page.waitForTimeout(250);
  return connected;
}

// A walk that reads a crashed page checks nothing (the closing act of
// Sprint 26 found one that passed on two pages that answered 500 or
// crashed on a tab): every step is also checked for a failure. An error
// status of any document the page loaded, a page that never connected, a
// LiveView that crashed (LiveView announces it with
// `phx:page-loading-start` of kind "error", counted per document by the
// init script below: the document a navigation leaves announces one as
// its socket closes, and goes with it) or still shows its error class, and
// a step that did not arrive where it was sent, which is how a crashed tab
// looks once LiveView has re-joined at the address before the click.
function watchErrors(context) {
  return context.addInitScript(() => {
    window.__privacyLeakCrashes = 0;
    window.addEventListener("phx:page-loading-start", (event) => {
      if (event.detail && event.detail.kind === "error") window.__privacyLeakCrashes++;
    });
  });
}

async function failures(page, statuses, connected) {
  const out = statuses.splice(0).map((s) => ({ where: "HTTP status", hit: String(s.status), context: s.url }));
  if (!connected) out.push({ where: "LiveView", hit: "the page never connected", context: page.url() });
  const state = await page
    .evaluate(() => {
      const crashes = window.__privacyLeakCrashes || 0;
      window.__privacyLeakCrashes = 0;
      return { crashes, error: document.querySelector("[data-phx-main].phx-error, .phx-error") !== null };
    })
    .catch(() => ({ crashes: 0, error: false }));
  if (state.crashes > 0) out.push({ where: "LiveView", hit: "the LiveView crashed (" + state.crashes + "x)", context: page.url() });
  if (state.error) out.push({ where: "LiveView", hit: "the page shows its error state", context: page.url() });
  return out;
}

// The address of a link relative to the walk's base: path and query.
function address(href, current) {
  const url = new URL(href, current);
  return url.pathname + url.search;
}

// The in-page links a page offers to another view of itself: Cash flow's
// facets, "After the sale"'s comparison modes, Wealth's stacked chart (its
// levels and one drilled category, I23), and any link to the same path that
// names a tab. Each is followed by a click (a patch) and later opened as an
// address of its own.
async function inPageLinks(page) {
  return page.$$eval(
    "main a[href]",
    (as) =>
      as
        .filter((a) => {
          const url = new URL(a.getAttribute("href"), location.href);
          if (url.origin !== location.origin || url.pathname !== location.pathname) return false;
          if (a.closest("[data-role='cashflow-facets'], [data-role='hindsight-compare']")) return true;
          // Wealth's stack (I23): its levels, the breadcrumb and one drilled
          // category, each state once; every band and sort is the same
          // markup, and each click runs a walk of its own.
          if (/(^|[?&])level=/.test(url.search.slice(1))) {
            return !!a.closest("[data-role='stack-level'], [data-role='stack-crumbs']") || a === document.querySelector("#stack-legend a");
          }
          return /(^|[?&])(tab|hindsight)=/.test(url.search.slice(1));
        })
        .map((a) => a.getAttribute("href"))
  );
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
  const read = (page, allowFormValues = false) =>
    page.evaluate(scan, { plainSelectors, amountData, amountName, allowFormValues });
  // PRIVACY_LEAK_ONLY=states walks the open states alone.
  const statesOnly = only === "states";
  try {
    for (const theme of THEMES) {
      for (const viewport of WIDTHS) {
        const context = await browser.newContext({ viewport, locale: "de-DE" });
        await context.addInitScript((th) => {
          try {
            localStorage.setItem("portfolixir-theme", th);
          } catch (_) {}
        }, theme);
        await watchErrors(context);
        const page = await context.newPage();
        // Every document the page loads, a reload after a failed join too.
        const statuses = [];
        page.on("response", (response) => {
          if (response.request().resourceType() === "document" && response.status() >= 400) {
            statuses.push({ status: response.status(), url: response.url() });
          }
        });

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
        const enqueue = (next) => {
          if (!queued.has(next)) {
            queued.add(next);
            queue.push(next);
          }
        };

        // Reads the page as it stands after a step, its failures first.
        const check = async (label, connected, allowFormValues = false) => {
          visited++;
          for (const f of await failures(page, statuses, connected)) findings.push({ page: label, ...f });
          for (const f of await read(page, allowFormValues)) findings.push({ page: label, ...f });
        };

        // Clicks each in-page link to another view of the page (a patch),
        // checks it arrived there, and queues its address for a visit of
        // its own; the views a click opens are followed the same way.
        const followInPage = async (tag, clicked) => {
          for (let round = 0; round < 4; round++) {
            const hrefs = (await inPageLinks(page)).filter((href) => !clicked.has(address(href, page.url())));
            if (!hrefs.length) return;
            for (const href of hrefs) {
              const target = address(href, page.url());
              if (clicked.has(target)) continue;
              clicked.add(target);
              enqueue(target);
              const link = await page.$(`main a[href="${href.replace(/"/g, '\\"')}"]`);
              if (!link) continue;
              await link.click();
              await page.waitForURL((u) => u.pathname + u.search === target, { timeout: 5000 }).catch(() => {});
              const connected = await settle(page);
              const at = address(page.url(), page.url());
              if (at !== target) {
                findings.push({ page: tag + " → " + target, where: "LiveView", hit: "the click did not arrive (a crash re-joins at the address before it)", context: at });
              }
              await check(tag + " → " + target, connected);
            }
          }
        };

        while (queue.length) {
          const path = queue.shift();
          if (statesOnly || (only && !path.startsWith(only))) continue;
          const tag = theme + " " + viewport.width + " " + path;
          const response = await page.goto(base + path).catch((error) => {
            findings.push({ page: tag, where: "navigation", hit: String(error && error.message), context: path });
            return null;
          });
          if (response && response.status() >= 400 && !statuses.length) {
            statuses.push({ status: response.status(), url: response.url() });
          }
          await check(tag, await settle(page));

          if (!sourceChecked.has(path)) {
            sourceChecked.add(path);
            const source = await sourceFindings(context, base + path, plainSelectors, amountData, amountName);
            for (const f of source) findings.push({ page: "source " + path, ...f });
          }

          // The area tabs the page links: each is a page of the shell.
          const links = await page.$$eval("#area-tabs a[href]", (as) => as.map((a) => a.getAttribute("href")));
          for (const href of links) {
            const url = new URL(href, base);
            if (url.origin !== new URL(base).origin) continue;
            enqueue(url.pathname + url.search);
          }

          // The page's other views it links in place (a patch).
          const clicked = new Set([address(page.url(), page.url())]);
          await followInPage(tag, clicked);
          if (address(page.url(), page.url()) !== path) {
            await page.goto(base + path).catch(() => null);
            await settle(page);
          }

          // The detail tabs it offers (buttons): each is pressed, checked
          // to be the selected one afterwards, and read; the views a tab
          // links in place are followed too.
          const tabs = await page.$$eval("[data-tab-level='2'] [role='tab']", (bs) => bs.map((b) => b.id).filter(Boolean));
          for (const id of tabs) {
            const button = await page.$("#" + id);
            if (!button) {
              findings.push({ page: tag + " #" + id, where: "LiveView", hit: "the tab is gone (a crash re-join?)", context: page.url() });
              continue;
            }
            await button.click();
            const connected = await settle(page);
            const selected = await page.getAttribute("#" + id, "aria-selected").catch(() => null);
            if (selected !== "true") {
              findings.push({ page: tag + " #" + id, where: "LiveView", hit: "the pressed tab is not selected (a crash re-joins without it)", context: page.url() });
            }
            await check(tag + " #" + id, connected);
            await followInPage(tag + " #" + id, clicked);
          }

          // The page's own extra views the mode changes (P2): each pressed
          // and read, e.g. Wealth's "Value" series.
          for (const sel of pages.extraClicks) {
            const handle = await page.$(sel);
            if (!handle) continue;
            await handle.click();
            await check(tag + " " + sel, await settle(page));
          }
        }

        // The declared open states (the privacy lens of the closing act):
        // each opened from its page by its own steps, checked to be open,
        // and read; a state that does not open fails the walk.
        for (const state of pages.openStates || []) {
          if (only && !statesOnly && !state.url.startsWith(only)) continue;
          const tag = theme + " " + viewport.width + " " + state.url + " [" + state.name + "]";
          await page.goto(base + state.url).catch((error) => {
            findings.push({ page: tag, where: "navigation", hit: String(error && error.message), context: state.url });
          });
          let connected = await settle(page);
          let opened = true;
          for (const step of state.steps) {
            try {
              if (step.click) await page.locator(step.click).locator("visible=true").first().click({ timeout: 5000 });
              if (step.upload) await page.setInputFiles(step.upload[0], step.upload[1]);
              connected = (await settle(page)) && connected;
            } catch (error) {
              opened = false;
              findings.push({ page: tag, where: "open state", hit: "a step did not run: " + String(error && error.message).split("\n")[0], context: JSON.stringify(step) });
              break;
            }
          }
          if (opened) {
            const open = await page
              .locator(state.open)
              .locator("visible=true")
              .first()
              .waitFor({ timeout: 8000 })
              .then(() => true)
              .catch(() => false);
            if (!open) findings.push({ page: tag, where: "open state", hit: "the state did not open", context: state.open });
          }
          await check(tag, connected, state.allowFormValues === true);
        }
        await context.close();
      }
    }

    const unique = short(findings);
    if (unique.length) {
      process.stdout.write(JSON.stringify({ ok: false, error: unique.length + " finding(s): a figure leaked or a page failed", visited, findings: unique.slice(0, 2000) }) + "\n");
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
