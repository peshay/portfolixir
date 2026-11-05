# Sprint 25 board 01: the home-screen icon on an iPhone (W1)

The board of the Sprint 25 plan's Lane W (D-6), drawn on 2026-11-05 on
the planning PR. The owner added Portfolixir to an iPhone's home screen and
got a letter tile, a „P“, instead of the logo: the root layout links only
`favicon.svg` and a 64 × 64 PNG named `favicon.ico`, and iOS takes neither
for a home-screen icon.

| File | What it is |
|---|---|
| `01-home-screen-icon.html` → `01-home-screen-icon--1200.png` | The board at 1200 px: today's letter tile, then A and B, each on a light and a dark wallpaper. |
| `build.js` | Writes `frames/icon-light.svg` and `frames/icon-dark.svg`: the shipped `priv/static/images/logo-app-icon.svg` with one palette pinned and its colour-scheme media query dropped. The drawing is untouched. |
| `render.js` | Renders the board to PNG at full colour (the icon's gradients band when reduced to 256 colours; `QUANTIZE=1` reduces anyway). |
| `frames/` | The two icon variants the board draws. |

**No data.** The board shows icons and placeholder tiles labelled „App“;
no figure, name or machine detail appears. Today's tile is drawn after the
letter tile iOS builds when a page offers no icon; the exact glyph and grey
vary with the iOS version.

## The pick

- **A, the light palette (recommended):** the icon's own light surface
  `#FCFBFF`, as the favicon draws in light mode and the docs' home page
  shows the logo. It reads on both wallpapers.
- **B, the dark palette:** the same drawing on `#12101A`. On a dark
  wallpaper the tile's edge disappears.

Silence adopts A; a review comment "W1 B" changes it.

## What W1 builds, and what it does not

- `priv/static/apple-touch-icon.png`, 180 × 180, **opaque** (iOS fills
  transparent pixels black and rounds the corners itself), rendered from
  the pinned light variant; a `<link rel="apple-touch-icon">` in the root
  layout's head; the file in `Plug.Static`'s `only` list, so iOS fetches it
  before any login.
- The label under the icon is the page title, which is already
  „Portfolixir“, so no `apple-mobile-web-app-title` is needed.
- **No web manifest and no standalone mode.** Both make the site an
  installable app, which is idea U1 and not worked out.
- **After the release:** the shortcut on the home screen has to be removed
  and added again. iOS stores the icon when the shortcut is made.
