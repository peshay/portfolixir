# GitHub Pages setup

Portfolixir includes a minimal static landing page foundation under `docs/`.

## Included files

- `docs/index.html`
- `docs/styles.css`
- `docs/.nojekyll`

The page is intentionally static and does not change Phoenix runtime behavior.

## Enable GitHub Pages

1. Open the repository on GitHub.
2. Go to **Settings → Pages**.
3. Under **Build and deployment**, choose **Deploy from a branch**.
4. Select branch **main** and folder **/docs**.
5. Save and wait for deployment.

## Scope boundaries

- Static site only (no generator/toolchain required).
- No analytics or tracking scripts.
- No write-capable broker/trading/payment actions.
