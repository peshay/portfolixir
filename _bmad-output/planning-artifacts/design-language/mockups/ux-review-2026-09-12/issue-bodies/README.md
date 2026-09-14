# Issue bodies with their pictures

The GitHub MCP tool that filed issues #784–#809 neutralises every URL that
points at an image (it wraps the URL in backticks) and, as observed, every
URL beyond roughly 150 characters, so the issues cannot carry the pictures
themselves. These files are the intended bodies, pictures embedded, one per
issue (#809, filed 2026-09-14, has no pictures) — and they double as the
per-issue picture pages: each issue links to
its file here under `blob/<short sha>/…/NNN.md` (and the same path on `main`
for after the merge), which GitHub renders with the pictures. The picture
lines in the issue bodies name what the page shows.

To put the pictures into the issue bodies themselves, run once with the
GitHub CLI logged in as the owner:

```bash
cd _bmad-output/planning-artifacts/design-language/mockups/ux-review-2026-09-12/issue-bodies
for f in [0-9]*.md; do gh issue edit "${f%.md}" --repo peshay/portfolixir --body-file "$f"; done
```

The image URLs are pinned to the commit that carries the PNGs, so they stay
valid after the branch is deleted.
