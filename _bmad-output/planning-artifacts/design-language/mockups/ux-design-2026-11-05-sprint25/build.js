// Writes the two fixed-colour copies of the app icon the board draws.
// The shipped priv/static/images/logo-app-icon.svg switches its colours
// with prefers-color-scheme; a home-screen icon is a PNG with one fixed
// background, so each variant pins one of the two palettes and drops the
// media query. The drawing itself is untouched.
// Usage: node build.js
const fs = require('fs');
const path = require('path');

const SOURCE = path.join(__dirname, '../../../../../priv/static/images/logo-app-icon.svg');
const PALETTES = {
  light: { surface: '#FCFBFF', outline: '#201631', separator: '#FCFBFF' },
  dark: { surface: '#12101A', outline: '#F5F3FF', separator: '#12101A' }
};

const svg = fs.readFileSync(SOURCE, 'utf8');
const withoutStyle = svg.replace(/\n\s*<style>[\s\S]*?<\/style>/, '');

for (const [name, p] of Object.entries(PALETTES)) {
  const fixed = withoutStyle
    .replace(/var\(--surface\)/g, p.surface)
    .replace(/var\(--outline\)/g, p.outline)
    .replace(/var\(--separator\)/g, p.separator);
  const out = path.join(__dirname, 'frames', `icon-${name}.svg`);
  fs.writeFileSync(out, fixed);
  console.log('wrote', path.relative(__dirname, out));
}
