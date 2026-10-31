/**
 * The MCP boundary's escape of the characters an operator cannot see (E25
 * S7, G20). The application refuses them on every write
 * (`Portfolixir.Input.Text`), but a row stored before that rule may still
 * carry them, and they render as nothing on the operator's screen while
 * reaching an agent intact. So every string the API answers — a value or a
 * key, at any depth — reaches the agent with each such character spelled as
 * `[U+XXXX]`: the spelling the operator's screen shows for the same row.
 *
 * The set is written out as code-point ranges rather than read from the
 * runtime's Unicode tables, so this module and `Portfolixir.Input.Text` name
 * the same characters whatever Unicode version Node or Erlang ships; the
 * shared cases in `test/fixtures/invisible-text.json` pin both:
 *
 * - Unicode's whole Default_Ignorable_Code_Point set (security review
 *   2026-10-12, H12): the tag characters and the rest of their block,
 *   U+E0000-U+E00FF and U+E01F0-U+E0FFF; the bidirectional controls and the
 *   other invisible format characters, U+00AD, U+061C, U+200B-U+200F,
 *   U+202A-U+202E, U+2060-U+206F, U+FEFF, U+FFF9-U+FFFB, U+1BCA0-U+1BCA3,
 *   U+1D173-U+1D17A; the combining grapheme joiner U+034F, the Hangul
 *   fillers U+115F, U+1160, U+3164, U+FFA0, the Khmer inherent vowels
 *   U+17B4-U+17B5, the Mongolian selectors U+180B-U+180F and the reserved
 *   U+FFF0-U+FFF8;
 * - a variation selector with no base it can vary: one of U+FE00-U+FE0F
 *   after no character in VARIANT_BASES, one of U+E0100-U+E01EF after no
 *   CJK ideograph, and any selector next to another one.
 *
 * The zero-width joiner U+200D is left as it is where it joins two
 * pictographs (E25 S7 review round, S7E-3): the character before it is a
 * pictograph, or a VS16 (U+FE0F) right after one, and the character after
 * it is one. There it renders as the one glyph it builds — a person at a
 * laptop, a family, the rainbow flag — and the application stores it. The
 * pictographs are written out in PICTOGRAPHS, the same ranges as the
 * application's. The tag characters, and with them the subdivision flags,
 * and the zero-width non-joiner U+200C stay escaped.
 *
 * The escape happens here, at the boundary, and nowhere upstream: the JSON
 * API answers stored text as stored. A text the agent writes back carries
 * the escapes as the visible letters they are.
 */

type Range = readonly [number, number];

const INVISIBLE: readonly Range[] = [
  [0x00ad, 0x00ad],
  [0x034f, 0x034f],
  [0x061c, 0x061c],
  [0x115f, 0x1160],
  [0x17b4, 0x17b5],
  [0x180b, 0x180f],
  [0x200b, 0x200c],
  [0x200e, 0x200f],
  [0x202a, 0x202e],
  [0x2060, 0x206f],
  [0x3164, 0x3164],
  [0xfeff, 0xfeff],
  [0xffa0, 0xffa0],
  [0xfff0, 0xfffb],
  [0x1bca0, 0x1bca3],
  [0x1d173, 0x1d17a],
  [0xe0000, 0xe00ff],
  [0xe01f0, 0xe0fff]
];

const STANDARD_SELECTORS: readonly Range[] = [[0xfe00, 0xfe0f]];
const IDEOGRAPHIC_SELECTORS: readonly Range[] = [[0xe0100, 0xe01ef]];
const SELECTORS: readonly Range[] = [...STANDARD_SELECTORS, ...IDEOGRAPHIC_SELECTORS];

const ZERO_WIDTH_JOINER = 0x200d;
const VS16 = 0xfe0f;

// A written-out superset of Unicode's Extended_Pictographic below U+1FB00,
// skin tones included; Portfolixir.Input.Text names the same ranges.
const PICTOGRAPHS: readonly Range[] = [
  [0x00a9, 0x00a9],
  [0x00ae, 0x00ae],
  [0x203c, 0x203c],
  [0x2049, 0x2049],
  [0x2122, 0x2122],
  [0x2139, 0x2139],
  [0x2190, 0x21ff],
  [0x2300, 0x23ff],
  [0x24c2, 0x24c2],
  [0x25a0, 0x27bf],
  [0x2934, 0x2935],
  [0x2b00, 0x2bff],
  [0x3030, 0x3030],
  [0x303d, 0x303d],
  [0x3297, 0x3297],
  [0x3299, 0x3299],
  [0x1f000, 0x1faff]
];

// The CJK ideographs: the only base of an ideographic variation selector.
const IDEOGRAPHS: readonly Range[] = [
  [0x3400, 0x4dbf],
  [0x4e00, 0x9fff],
  [0xf900, 0xfaff],
  [0x20000, 0x3ffff]
];

// The bases a selector of U+FE00-U+FE0F can vary (H12): a written-out
// superset of the bases in StandardizedVariants.txt and
// emoji-variation-sequences.txt — the pictographs, a keycap's digit, # or *,
// the CJK ideographs, the mathematical operators, the CJK fullwidth
// punctuation, the curly quotation marks, Myanmar, Phags-pa, Manichaean and
// the Egyptian hieroglyphs. Portfolixir.Input.Text names the same ranges.
const VARIANT_BASES: readonly Range[] = [
  ...PICTOGRAPHS,
  ...IDEOGRAPHS,
  [0x23, 0x23],
  [0x2a, 0x2a],
  [0x30, 0x39],
  [0x1000, 0x109f],
  [0x2200, 0x22ff],
  [0x2a00, 0x2aff],
  [0xa840, 0xa87f],
  [0xa9e0, 0xa9ff],
  [0xaa60, 0xaa7f],
  [0x10ac0, 0x10aff],
  [0x13000, 0x143ff],
  [0x2018, 0x2019],
  [0x201c, 0x201d],
  [0x3001, 0x3002],
  [0xff01, 0xff01],
  [0xff0c, 0xff0c],
  [0xff0e, 0xff0e],
  [0xff1a, 0xff1b],
  [0xff1f, 0xff1f]
];

function within(codePoint: number | undefined, ranges: readonly Range[]): boolean {
  return (
    codePoint !== undefined && ranges.some(([first, last]) => codePoint >= first && codePoint <= last)
  );
}

function spell(codePoint: number): string {
  return `[U+${codePoint.toString(16).toUpperCase().padStart(4, "0")}]`;
}

// A zero-width joiner between two pictographs, a VS16 after the first allowed.
function joinsPictographs(points: readonly number[], index: number): boolean {
  const before = points[index - 1];
  const afterPictograph =
    within(before, PICTOGRAPHS) || (before === VS16 && within(points[index - 2], PICTOGRAPHS));

  return afterPictograph && within(points[index + 1], PICTOGRAPHS);
}

// A variation selector with no base it can vary, or next to another one.
function strandedSelector(points: readonly number[], index: number): boolean {
  const codePoint = points[index];
  const before = points[index - 1];

  if (within(points[index + 1], SELECTORS)) {
    return within(codePoint, SELECTORS);
  }

  return (
    (within(codePoint, STANDARD_SELECTORS) && !within(before, VARIANT_BASES)) ||
    (within(codePoint, IDEOGRAPHIC_SELECTORS) && !within(before, IDEOGRAPHS))
  );
}

/** `text` with every invisible character spelled `[U+XXXX]`. */
export function escapeInvisibleText(text: string): string {
  const points = Array.from(text, (character) => character.codePointAt(0) as number);
  let escaped = "";

  points.forEach((codePoint, index) => {
    const invisible =
      within(codePoint, INVISIBLE) ||
      (codePoint === ZERO_WIDTH_JOINER && !joinsPictographs(points, index)) ||
      strandedSelector(points, index);

    escaped += invisible ? spell(codePoint) : String.fromCodePoint(codePoint);
  });

  return escaped;
}

/**
 * A parsed API answer with every string, keys included, escaped; numbers,
 * booleans and null as they are.
 */
export function escapeInvisible(value: unknown): unknown {
  if (typeof value === "string") {
    return escapeInvisibleText(value);
  }

  if (Array.isArray(value)) {
    return value.map(escapeInvisible);
  }

  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, nested]) => [escapeInvisibleText(key), escapeInvisible(nested)])
    );
  }

  return value;
}
