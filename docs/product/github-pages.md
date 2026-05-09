# GitHub Pages setup

Portfolixir includes a minimal static product page under `docs/`. GitHub Pages
publishes that folder without a docs generator, analytics, or tracking scripts.

## Page responsibilities

- Keep the public product overview short and static.
- Link readers back to repository documentation for setup, contribution, and
  deeper product notes.
- Avoid claims that Portfolixir is production-ready or safe for real-money use.
- Leave screenshots as placeholders until real, sanitized product images are
  committed.

## Included files

- `docs/index.html`
- `docs/styles.css`
- `docs/.nojekyll`
- `docs/CNAME`
- `docs/assets/logo-wordmark.svg`

The page is intentionally static and does not change Phoenix runtime behavior.

## Domains and canonical behavior

| Purpose | Domain | Status | Notes |
| --- | --- | --- | --- |
| Current GitHub Pages custom domain | `portfolixir.dev` | Active target | Must match `docs/CNAME` exactly. |
| Preferred product/docs domain | `portfolixir.dev` | Preferred canonical | Keep product overview and docs links canonical here unless a later product decision changes it. |
| Future aliases | `www.portfolixir.dev`, `portfolixir.app`, `portfolixir.com`, `portfolixir.cloud`, `portfolixir.de` | Reserved / optional | If used later, redirect to the canonical product domain instead of serving divergent content. |

Canonical rules:

- Public copy should link to `https://portfolixir.dev/` for the product page.
- Repository docs should link to source files on GitHub when pointing outside the
  static page bundle.
- Future alias domains should use HTTP redirects to the canonical product domain.
- Do not publish duplicate independent landing pages with different canonical
  product claims.

## Manual GitHub + DNS checklist

1. Open the repository on GitHub.
2. Go to **Settings → Pages**.
3. Under **Build and deployment**, choose **Deploy from a branch**.
4. Select branch **main** and folder **/docs**.
5. Set **Custom domain** to `portfolixir.dev`.
6. Commit `docs/CNAME` with exactly `portfolixir.dev`.
7. Add the apex DNS record(s) required by GitHub Pages for `portfolixir.dev`.
8. Optionally add `www.portfolixir.dev` as a CNAME alias per GitHub Pages guidance.
9. Do **not** use wildcard DNS records.
10. After certificate provisioning, enable **Enforce HTTPS** in GitHub Pages.

## CNAME requirements

- `docs/CNAME` must contain only the active custom domain.
- Keep the file in `docs/` while Pages publishes from the branch `/docs` folder.
- Re-check this requirement if publishing moves to a GitHub Actions workflow.

## Scope boundaries

- Static site only; no generator or build toolchain.
- No analytics or tracking scripts.
- No legal, tax, or financial advice copy.
- No write-capable broker, trading, banking, payment, order, or rebalance
  behavior.
