# Issue bodies with their pictures

The GitHub MCP tool that filed issues #784–#808 neutralises every URL that
points at an image (it wraps the URL in backticks), so the issues carry a
pointer to the rendered gallery in `ux-review-2026-09-12.md` → Part 7 instead
of the pictures themselves. These files are the intended bodies, pictures
embedded, one per issue. To put them on the issues, run once with the
GitHub CLI logged in as the owner:

```bash
cd _bmad-output/planning-artifacts/design-language/mockups/ux-review-2026-09-12/issue-bodies
for f in [0-9]*.md; do gh issue edit "${f%.md}" --repo peshay/portfolixir --body-file "$f"; done
```

The image URLs are pinned to the commit that carries the PNGs, so they stay
valid after the branch is deleted.
