// Renders priv/static/apple-touch-icon.png, the iPhone home-screen icon
// (Sprint 25 W1; board 01, pick A; plan D-6), from the shipped
// priv/static/images/logo-app-icon.svg.
//
// The SVG switches its colours with prefers-color-scheme; a home-screen icon
// is one fixed picture, so this pins the light palette (the icon's own light
// surface, as the favicon draws in light mode) and drops the media query. The
// drawing itself is untouched.
//
// The PNG is 180 × 180 and opaque: iOS fills transparent pixels black and
// rounds the corners itself, so the drawing is flattened onto the surface
// colour and written as colour type 2 (RGB, no alpha channel). Chromium
// rasterises the SVG onto a canvas; this script encodes the pixels itself,
// with no filter and fixed zlib settings, so a re-run on the same Chromium
// writes the same bytes.
//
// Usage: node scripts/render-apple-touch-icon.js
// Playwright and its Chromium: npm ci --prefix test/browser, then
// npx --prefix test/browser playwright install chromium (or name a Chromium
// in PLAYWRIGHT_CHROMIUM_EXECUTABLE).
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const ROOT = path.join(__dirname, '..');
const SOURCE = path.join(ROOT, 'priv/static/images/logo-app-icon.svg');
const TARGET = path.join(ROOT, 'priv/static/apple-touch-icon.png');
const SIZE = 180;
const LIGHT = { surface: '#FCFBFF', outline: '#201631', separator: '#FCFBFF' };

function loadPlaywright() {
  try {
    return require('playwright');
  } catch (_error) {
    return require(path.join(ROOT, 'test/browser/node_modules/playwright'));
  }
}

function pinnedSvg() {
  const svg = fs.readFileSync(SOURCE, 'utf8');
  const withoutStyle = svg.replace(/\n\s*<style>[\s\S]*?<\/style>/, '');
  if (withoutStyle === svg) throw new Error('logo-app-icon.svg has no <style> block to pin');
  const pinned = withoutStyle
    .replace(/var\(--surface\)/g, LIGHT.surface)
    .replace(/var\(--outline\)/g, LIGHT.outline)
    .replace(/var\(--separator\)/g, LIGHT.separator);
  if (/var\(--/.test(pinned)) throw new Error('logo-app-icon.svg uses a colour this script does not pin');
  return pinned;
}

// Draws the SVG onto a canvas filled with the surface colour first, so no
// pixel stays transparent, and returns the RGBA bytes.
async function rasterise(svg) {
  const { chromium } = loadPlaywright();
  const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE;
  const browser = await chromium.launch(executablePath ? { executablePath } : {});
  try {
    const page = await browser.newPage({ viewport: { width: SIZE, height: SIZE }, deviceScaleFactor: 1 });
    const rgba = await page.evaluate(
      async ({ svg, size, surface }) => {
        const image = new Image();
        image.src = 'data:image/svg+xml;base64,' + btoa(unescape(encodeURIComponent(svg)));
        await image.decode();
        const canvas = document.createElement('canvas');
        canvas.width = size;
        canvas.height = size;
        const context = canvas.getContext('2d');
        context.fillStyle = surface;
        context.fillRect(0, 0, size, size);
        context.drawImage(image, 0, 0, size, size);
        return Array.from(context.getImageData(0, 0, size, size).data);
      },
      { svg, size: SIZE, surface: LIGHT.surface }
    );
    return Buffer.from(rgba);
  } finally {
    await browser.close();
  }
}

const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});

function crc32(buffer) {
  let c = 0xffffffff;
  for (const byte of buffer) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
}

// An RGB PNG: IHDR (8-bit, colour type 2), one IDAT, IEND.
function encodeRgbPng(rgba, size) {
  const rows = [];
  for (let y = 0; y < size; y++) {
    const row = Buffer.alloc(1 + size * 3); // filter byte 0, then R G B per pixel
    for (let x = 0; x < size; x++) {
      const i = (y * size + x) * 4;
      if (rgba[i + 3] !== 255) throw new Error(`pixel ${x},${y} is not opaque`);
      rgba.copy(row, 1 + x * 3, i, i + 3);
    }
    rows.push(row);
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(size, 0);
  header.writeUInt32BE(size, 4);
  header[8] = 8; // bit depth
  header[9] = 2; // colour type: RGB, no alpha
  header[10] = 0; // compression
  header[11] = 0; // filter method
  header[12] = 0; // no interlace
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', header),
    chunk('IDAT', zlib.deflateSync(Buffer.concat(rows), { level: 9 })),
    chunk('IEND', Buffer.alloc(0))
  ]);
}

(async () => {
  const rgba = await rasterise(pinnedSvg());
  fs.writeFileSync(TARGET, encodeRgbPng(rgba, SIZE));
  console.log('wrote', path.relative(ROOT, TARGET));
})().catch(error => {
  console.error(error);
  process.exit(1);
});
