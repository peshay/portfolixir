---
layout: docs
title: "ADR-0014: Bilingual docs site (EN baseline, DE alongside) without a custom Pages build"
description: Decision to ship the Jekyll docs site in English and German with a manual front-matter + parallel-folder structure served by the default GitHub Pages build, instead of Jekyll-Polyglot behind a custom GitHub Actions build, keeping the default Pages pipeline and the Elixir DocsTest paths intact.
---

# ADR-0014: Bilingual docs site (EN baseline, DE alongside) without a custom Pages build

- **Status:** Accepted
- **Date:** 2026-06-13

## Context

The `docs/` Jekyll site published to GitHub Pages (the `portfolixir.app`
domain, see `docs/CNAME`) is English-only. We want it bilingual: the existing
English pages stay the source baseline, German lives alongside, and a reader
can switch languages with the choice remembered.

Two constraints shape the choice:

1. **GitHub Pages' default build does not allow arbitrary Jekyll plugins.**
   [Jekyll-Polyglot](https://github.com/untra/polyglot) is the obvious
   multilingual plugin, but it is not on the Pages safelist, so using it
   requires replacing the default Pages build with a **custom GitHub Actions
   Pages workflow** that runs `jekyll build` with the plugin and uploads the
   artifact. That is a new piece of CI infrastructure to own, secure, and keep
   green for a site that is otherwise built automatically.
2. **The Elixir `DocsTest` (`test/portfolixir/docs_test.exs`) reads specific
   doc paths** with `File.read!` — `docs/product-documentation.md`,
   `docs/integration/api-and-mcp.md`, `docs/index.md`, and others — and asserts
   their content. Any mechanism that **moves** the English files (e.g. into an
   `/en` folder) breaks that test and forces a parallel rewrite of the test's
   path list. CI is the source of truth here (the Jekyll build is not run in
   CI; `mix test` is), so keeping `DocsTest` green is non-negotiable.

The realistic options were:

- **A. Jekyll-Polyglot + a custom GitHub Actions Pages build.** One source file
  per page with inline translations; the plugin generates `/` and `/de/`
  outputs. Cost: a bespoke Pages workflow (plugin install, Ruby/Jekyll pinning,
  artifact upload) that CI does not exercise, plus a moving target whenever
  Pages or the plugin changes.
- **B. A manual `/en` `/de` split.** Move every English page under `/en` and add
  `/de`. Clean URLs, but it relocates every file `DocsTest` reads, so the test's
  path list and the navigation must change in lockstep — more churn and more
  risk for the same outcome.
- **C. A front-matter + parallel-folder approach on the default Pages build.**
  Keep the English files exactly where they are (so `DocsTest`'s `File.read!`
  paths are untouched) and add German counterparts under `docs/de/` mirroring
  the English tree. Each page declares its language and the URLs of its
  counterparts in front matter (`lang`, `lang_en`, `lang_de`); the shared layout
  renders a language switcher from those fields, with dependency-free inline JS
  for the browser-language default and `localStorage` persistence.

## Decision

Adopt **option C**: a manual **front-matter + parallel `docs/de/` folder**
structure served by the **default GitHub Pages build**. No Jekyll plugins, no
custom Actions Pages workflow.

- **English stays the baseline, in place.** `docs/product-documentation.md`,
  `docs/integration/api-and-mcp.md`, `docs/index.md`, and the rest keep their
  current paths and content, so the existing `DocsTest` assertions and the
  navigation URLs do not move.
- **German lives under `docs/de/`** mirroring the English tree
  (`docs/de/product-documentation.md`,
  `docs/de/integration/api-and-mcp.md`), with the same Jekyll `layout: docs`
  front matter plus `lang: de` and the `lang_en`/`lang_de` counterpart URLs.
- **The language switcher lives in the shared layout** (`docs/_layouts/docs.html`):
  EN/DE links built from each page's `lang_en`/`lang_de` front matter (falling
  back to the current URL on pages with no counterpart, so untranslated pages
  still render). A small inline script defaults a first-time visitor to the
  browser language (German only; English is the baseline), persists an explicit
  click in `localStorage` (`portfolixir-docs-lang`), and redirects once to the
  stored/preferred counterpart when it differs from the current page.
- **English remains the source of record.** Per `AGENTS.md`, every repository
  artifact is written in English; translated end-user documentation is the
  explicit exception, and German tracks the English baseline rather than
  diverging from it. Code, identifiers, endpoints, and tool names stay
  untranslated because they are API surface.
- **Translation coverage is pragmatic.** The two core pages — the product
  handbook and the API/MCP reference — are translated in full. Deeper/secondary
  pages (architecture, ADRs, development guides, home deployment) stay English
  for now with a translation backlog noted; the switcher degrades gracefully on
  them.

## Consequences

- The **default GitHub Pages build keeps working** unchanged — no plugin
  safelist fight, no custom Actions Pages workflow to own or secure, no Pages
  pipeline that CI cannot verify.
- **`DocsTest` stays green** because no English file moves; the test is extended
  to also assert the German core pages exist and carry the key documented
  surface (the income endpoint/tool, the cash/allocation flags, the switcher
  front matter) in both languages.
- **Trade-off: translations are maintained by hand.** Adding a documented route
  or tool means updating the English page and its German counterpart (or
  consciously deferring the German one to the backlog). There is no plugin
  enforcing structural parity; the extended `DocsTest` is the guard that the
  German core pages exist and cover the key surface.
- **Trade-off: some duplication and a flat URL convention.** German pages live
  under `/de/...` rather than a plugin-managed locale routing; counterpart URLs
  are wired explicitly in front matter. This is more verbose than Polyglot but
  fully transparent and plugin-free.
- Switching to Polyglot later remains possible: it would mean adding a custom
  Pages Actions build and collapsing each EN/DE pair into one source file. This
  ADR would then be superseded. Until the page count or translation burden
  justifies that infrastructure, the manual approach is the lower-risk choice.
