# GitHub Pages setup

Portfolixir includes a minimal static landing page foundation under `docs/`.

## Included files

- `docs/index.html`
- `docs/styles.css`
- `docs/.nojekyll`
- `docs/CNAME` (required when publishing from the `docs/` folder on a branch)

The page is intentionally static and does not change Phoenix runtime behavior.

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

## Follow-up domain strategy

- Keep `portfolixir.app`, `portfolixir.com`, `portfolixir.cloud`, and `portfolixir.de` reserved for later redirect/canonical work.
- If the Pages publishing mode changes to GitHub Actions later, re-check whether `docs/CNAME` is still needed.

## Scope boundaries

- Static site only (no generator/toolchain required).
- No analytics or tracking scripts.
- No write-capable broker/trading/payment actions.
