#!/usr/bin/env python3
"""Reject invisible / bidirectional Unicode characters in tracked text files.

This is a CI + pre-commit gate that defends against two related classes of
supply-chain / prompt-injection attacks:

  * "Trojan Source" (CVE-2021-42574): bidirectional control characters reorder
    how source code renders versus how a compiler/interpreter reads it, hiding
    malicious logic in plain sight during code review.
  * Prompt-injection / homoglyph smuggling: zero-width characters and Unicode
    "tag" characters can carry instructions or payloads that are invisible to a
    human reviewer but still read by tooling (and by LLMs).

WHAT IS FLAGGED
---------------
The scanner walks every tracked text file (via ``git ls-files``) and flags any
occurrence of the following code points:

  * Bidirectional controls (Trojan Source):
        U+202A LEFT-TO-RIGHT EMBEDDING
        U+202B RIGHT-TO-LEFT EMBEDDING
        U+202C POP DIRECTIONAL FORMATTING
        U+202D LEFT-TO-RIGHT OVERRIDE
        U+202E RIGHT-TO-LEFT OVERRIDE
        U+2066 LEFT-TO-RIGHT ISOLATE
        U+2067 RIGHT-TO-LEFT ISOLATE
        U+2068 FIRST STRONG ISOLATE
        U+2069 POP DIRECTIONAL ISOLATE
  * Zero-width / invisible characters:
        U+200B ZERO WIDTH SPACE
        U+200C ZERO WIDTH NON-JOINER
        U+200D ZERO WIDTH JOINER
        U+2060 WORD JOINER
        U+FEFF ZERO WIDTH NO-BREAK SPACE (only when NOT a leading BOM)
  * Unicode tag characters (used to hide payloads in modern smuggling attacks):
        U+E0000 .. U+E007F (entire Tags block)
  * Every other default-ignorable code point: a character that renders as
    nothing, or as a blank, and still reaches whatever reads the file. The
    ranges are written out in ``DEFAULT_IGNORABLE`` below, because most of
    them are not format characters and some are not assigned at all: the
    combining grapheme joiner, the Hangul fillers, the Khmer inherent vowels,
    the Mongolian selectors, the variation selectors U+FE00 .. U+FE0F and
    U+E0100 .. U+E01EF, and the reserved ranges. They are the ranges the
    application's own rule for stored text refuses (``@ignorable`` in
    lib/portfolixir/input/text.ex); invisible_unicode_gate_test.exs runs
    every character that rule refuses through this gate, so the gate is never
    the narrower of the two (N-84, #1286).
  * Any other character in the Unicode general category ``Cf`` (Format) that is
    not on the explicit allowlist. This is the conservative catch-all: ``Cf``
    covers invisible formatting characters (interlinear annotations, additional
    bidi/joining controls, etc.) without touching normal printable text,
    whitespace (tab/newline/space are ``Cc``/``Zs``, not ``Cf``), or letters.

The same characters are flagged in a file's NAME, for every path the scan is
given, whether or not the file's content is read: a tracked binary's or a
deleted file's name is read like any other. No allowlist entry exempts a
name. The report spells such a name with ``[U+XXXX]`` in place of each
flagged character.

WHAT IS NOT FLAGGED
-------------------
  * Regular text, letters, digits, punctuation, symbols, emoji.
  * Ordinary whitespace: TAB (U+0009), LF (U+000A), CR (U+000D), SPACE (U+0020).
  * A single U+FEFF appearing as the very first character of a file (a UTF-8
    byte-order mark). A BOM anywhere else is flagged.
  * U+FE0F, the emoji presentation selector, directly after a pictograph
    (``PICTOGRAPHS`` below) and not followed by another variation selector:
    there it only chooses the glyph of the character before it. Every other
    variation selector is flagged, wherever it stands.
  * Binary files, and only those: a file whose extension is on the explicit
    list ``BINARY_EXTENSIONS`` below, or one ``.gitattributes`` marks binary
    (``binary`` or ``-text``) that also holds a NUL or does not decode as
    UTF-8. Every other file that holds a NUL or a byte sequence that is not
    UTF-8 is a violation of its own ("not valid UTF-8 text"), and the
    characters around the offending byte are still scanned: one such byte
    must not carry a bidi control or a tag character past the gate (H64, the
    2026-10-12 security review).
  * Entries pinned in the allowlist file (see ALLOWLIST below).

ALLOWLIST
---------
Legitimate uses are pinned in ``.unicode-allowlist.txt`` (repo root). Each
non-comment line is::

    <path-glob> <U+XXXX> # reason text

Both a path glob and a code point are required, and a non-empty reason after
``#`` is mandatory. An entry without a reason is a configuration error and
fails the run. See that file for the exact format.

USAGE
-----
    python3 scripts/check_invisible_unicode.py            # scan tracked files
    python3 scripts/check_invisible_unicode.py FILE...    # scan given files

Exit code is 0 when clean, 1 when violations (or a malformed allowlist) are
found, and 1 when no file is named and the tracked files cannot be listed:
a scan that could read nothing is not a clean one. Output is
``path:line:col: U+XXXX NAME (description)`` per violation in a file's
content, and ``path: file name, character N: U+XXXX NAME (description)`` per
violation in its name.

The script is pure Python 3 standard library, deterministic, and fast.
"""

from __future__ import annotations

import fnmatch
import os
import subprocess
import sys
import unicodedata
from dataclasses import dataclass

# --- Forbidden code point definitions ---------------------------------------

# Bidirectional formatting / override / isolate controls (Trojan Source).
BIDI_CONTROLS = set(range(0x202A, 0x202E + 1)) | set(range(0x2066, 0x2069 + 1))

# Zero-width and word-joining invisible characters. U+FEFF is handled specially
# (allowed only as a leading BOM) and is intentionally NOT in this set.
ZERO_WIDTH = {0x200B, 0x200C, 0x200D, 0x2060}

# Unicode Tags block, abused to smuggle hidden instructions/payloads.
TAG_CHARS = set(range(0xE0000, 0xE007F + 1))

# U+FEFF: forbidden unless it is the first character of the file (BOM).
BOM = 0xFEFF

# Unicode's default-ignorable code points and the interlinear annotation
# characters, as inclusive ranges. Written out, not read from the Unicode
# tables: most are not in the general category Cf (the grapheme joiner, the
# Khmer vowels and the selectors are Mn, the Hangul fillers Lo, the reserved
# ranges unassigned), and a written-out set does not shrink with the Unicode
# version of the Python that runs the gate. These are the ranges of
# `@ignorable` in lib/portfolixir/input/text.ex.
DEFAULT_IGNORABLE = (
    (0x00AD, 0x00AD),  # soft hyphen
    (0x034F, 0x034F),  # combining grapheme joiner
    (0x061C, 0x061C),  # Arabic letter mark
    (0x115F, 0x1160),  # Hangul choseong and jungseong fillers
    (0x17B4, 0x17B5),  # Khmer inherent vowels
    (0x180B, 0x180F),  # Mongolian free variation selectors, vowel separator
    (0x200B, 0x200F),  # zero-width space and joiners, directional marks
    (0x202A, 0x202E),  # bidirectional embeddings and overrides
    (0x2060, 0x206F),  # word joiner, invisible operators, isolates, reserved
    (0x3164, 0x3164),  # Hangul filler
    (0xFE00, 0xFE0F),  # variation selectors 1 to 16
    (0xFEFF, 0xFEFF),  # zero-width no-break space
    (0xFFA0, 0xFFA0),  # halfwidth Hangul filler
    (0xFFF0, 0xFFFB),  # reserved, interlinear annotation characters
    (0x1BCA0, 0x1BCA3),  # shorthand format controls
    (0x1D173, 0x1D17A),  # musical symbol format controls
    (0xE0000, 0xE0FFF),  # tags, variation selectors 17 to 256, reserved
)

# U+FE00 .. U+FE0F and U+E0100 .. U+E01EF.
VARIATION_SELECTORS = ((0xFE00, 0xFE0F), (0xE0100, 0xE01EF))

# U+FE0F, the emoji presentation selector: the one variation selector the
# gate lets stand, and only directly after a pictograph.
EMOJI_PRESENTATION_SELECTOR = 0xFE0F

# The characters an emoji presentation selector may follow: the application's
# written-out superset of Unicode's Extended_Pictographic below U+1FB00
# (`@pictograph` in lib/portfolixir/input/text.ex).
PICTOGRAPHS = (
    (0x00A9, 0x00A9),
    (0x00AE, 0x00AE),
    (0x203C, 0x203C),
    (0x2049, 0x2049),
    (0x2122, 0x2122),
    (0x2139, 0x2139),
    (0x2190, 0x21FF),
    (0x2300, 0x23FF),
    (0x24C2, 0x24C2),
    (0x25A0, 0x27BF),
    (0x2934, 0x2935),
    (0x2B00, 0x2BFF),
    (0x3030, 0x3030),
    (0x303D, 0x303D),
    (0x3297, 0x3297),
    (0x3299, 0x3299),
    (0x1F000, 0x1FAFF),
)

# The binary files the gate skips, by extension. A tracked binary of another
# kind joins this list, or is marked `binary` in .gitattributes; any other file
# must be UTF-8 text without a NUL.
BINARY_EXTENSIONS = frozenset(
    {".gif", ".ico", ".jpeg", ".jpg", ".pdf", ".png", ".webp", ".woff", ".woff2"}
)

# Code points that are allowed despite being control/format characters because
# they are ordinary text structure. (Cc whitespace is also explicitly allowed.)
ALLOWED_WHITESPACE = {0x09, 0x0A, 0x0D, 0x20}


@dataclass(frozen=True)
class Violation:
    path: str
    line: int
    col: int
    codepoint: int | None
    description: str
    # True for a character of the path itself: `col` then counts the path's
    # characters and `line` is unused.
    in_name: bool = False

    def render(self) -> str:
        path = spell_path(self.path)
        if self.codepoint is None:
            return f"{path}:{self.line}:{self.col}: {self.description}"
        try:
            name = unicodedata.name(chr(self.codepoint))
        except ValueError:
            name = "<unnamed>"
        where = f" file name, character {self.col}" if self.in_name else f"{self.line}:{self.col}"
        return f"{path}:{where}: U+{self.codepoint:04X} {name} ({self.description})"


def spell_path(path: str) -> str:
    """The path as a report prints it: every flagged character spelled
    ``[U+XXXX]``, so a report line shows what the name holds and is not
    itself reordered or shortened by it."""
    return "".join(
        f"[U+{ord(char):04X}]" if classify(ord(char)) is not None else char for char in path
    )


@dataclass(frozen=True)
class AllowlistEntry:
    glob: str
    codepoint: int
    reason: str


def parse_allowlist(path: str) -> list[AllowlistEntry]:
    """Parse the allowlist file.

    Format per line: ``<path-glob> <U+XXXX> # reason``.
    Blank lines and full-line comments (starting with ``#``) are ignored.
    Raises ValueError on any malformed entry (missing glob, codepoint, or
    reason) so misconfiguration fails loudly rather than silently widening the
    gate.
    """
    entries: list[AllowlistEntry] = []
    if not os.path.exists(path):
        return entries

    with open(path, "r", encoding="utf-8") as handle:
        for lineno, raw in enumerate(handle, start=1):
            line = raw.rstrip("\n")
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue

            if "#" not in line:
                raise ValueError(
                    f"{path}:{lineno}: allowlist entry requires a '# reason' "
                    f"explaining the exception: {stripped!r}"
                )

            spec, reason = line.split("#", 1)
            reason = reason.strip()
            if not reason:
                raise ValueError(
                    f"{path}:{lineno}: allowlist entry has an empty reason; a "
                    f"written justification is mandatory: {stripped!r}"
                )

            parts = spec.split()
            if len(parts) != 2:
                raise ValueError(
                    f"{path}:{lineno}: allowlist entry must be "
                    f"'<path-glob> <U+XXXX> # reason': {stripped!r}"
                )

            glob, cp_text = parts
            cp_text = cp_text.upper()
            if not cp_text.startswith("U+"):
                raise ValueError(
                    f"{path}:{lineno}: code point must be written as 'U+XXXX': "
                    f"{cp_text!r}"
                )
            try:
                codepoint = int(cp_text[2:], 16)
            except ValueError as exc:
                raise ValueError(
                    f"{path}:{lineno}: invalid hex code point {cp_text!r}"
                ) from exc

            entries.append(AllowlistEntry(glob=glob, codepoint=codepoint, reason=reason))

    return entries


def is_allowed(path: str, codepoint: int, allowlist: list[AllowlistEntry]) -> bool:
    """Return True if (path, codepoint) is explicitly allowlisted."""
    normalized = path.replace(os.sep, "/")
    for entry in allowlist:
        if entry.codepoint == codepoint and fnmatch.fnmatch(normalized, entry.glob):
            return True
    return False


def in_ranges(codepoint: int, ranges: tuple[tuple[int, int], ...]) -> bool:
    """True if the code point lies in one of the inclusive ranges."""
    return any(first <= codepoint <= last for first, last in ranges)


def classify(codepoint: int) -> str | None:
    """Return a human description if the code point is forbidden, else None.

    The verdict is for the character by itself, and it is the verdict for a
    character of a file name. In a file's content two characters depend on
    where they stand, and the per-file scan decides them before it asks
    here: U+FEFF as the file's first character (a BOM), and U+FE0F after a
    pictograph (``is_emoji_presentation``).
    """
    if codepoint in BIDI_CONTROLS:
        return "bidirectional control character (Trojan Source)"
    if codepoint in ZERO_WIDTH:
        return "zero-width / invisible character"
    if codepoint in TAG_CHARS:
        return "Unicode tag character"
    if codepoint in ALLOWED_WHITESPACE:
        return None
    if in_ranges(codepoint, VARIATION_SELECTORS):
        return "variation selector with nothing it may vary"
    if in_ranges(codepoint, DEFAULT_IGNORABLE):
        return "default-ignorable character (renders as nothing)"
    # Conservative catch-all: any other format (Cf) character is invisible.
    if unicodedata.category(chr(codepoint)) == "Cf":
        return "invisible format character (Unicode category Cf)"
    return None


def is_emoji_presentation(text: str, index: int) -> bool:
    """True if ``text[index]`` is U+FE0F directly after a pictograph and is
    not followed by another variation selector."""
    if ord(text[index]) != EMOJI_PRESENTATION_SELECTOR or index == 0:
        return False
    if not in_ranges(ord(text[index - 1]), PICTOGRAPHS):
        return False
    following = index + 1
    return following == len(text) or not in_ranges(ord(text[following]), VARIATION_SELECTORS)


def read_bytes(path: str) -> bytes | None:
    """Read a file's bytes; None if it cannot be read."""
    try:
        with open(path, "rb") as handle:
            return handle.read()
    except OSError:
        return None


def decode(data: bytes) -> str:
    """Decode as UTF-8, keeping every byte that is not UTF-8 as a lone
    surrogate (``surrogateescape``), so the characters around it still scan."""
    return data.decode("utf-8", errors="surrogateescape")


def read_text(path: str) -> str | None:
    """Read a file as text (see ``decode``). Return None if it cannot be read."""
    data = read_bytes(path)
    return None if data is None else decode(data)


def is_listed_binary(path: str) -> bool:
    """True if the file's extension is on the explicit binary list."""
    return os.path.splitext(path)[1].lower() in BINARY_EXTENSIONS


def encoding_violation(path: str, data: bytes) -> Violation | None:
    """The first NUL or byte sequence that is not UTF-8, as a violation."""
    offset = data.find(b"\x00")
    what = "a NUL byte"
    try:
        data.decode("utf-8")
    except UnicodeDecodeError as exc:
        if offset == -1 or exc.start < offset:
            offset, what = exc.start, "a byte sequence that is not UTF-8"
    if offset == -1:
        return None
    line = data.count(b"\n", 0, offset) + 1
    col = offset - (data.rfind(b"\n", 0, offset) + 1) + 1
    return Violation(
        path,
        line,
        col,
        None,
        f"not valid UTF-8 text: {what} at byte {offset}; only a file "
        f"BINARY_EXTENSIONS or .gitattributes names as binary is skipped",
    )


def gitattributes_binary(paths: list[str]) -> set[str]:
    """The paths .gitattributes marks binary (``binary``, or ``-text``).

    Outside a git repository nothing is marked, so only the extension list
    skips a file.
    """
    if not paths:
        return set()
    try:
        output = subprocess.run(
            ["git", "check-attr", "-z", "--stdin", "binary", "text"],
            input=b"".join(p.encode("utf-8") + b"\0" for p in paths),
            check=True,
            capture_output=True,
        ).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        return set()
    fields = output.decode("utf-8", errors="surrogateescape").split("\0")
    marked = set()
    for index in range(0, len(fields) - 2, 3):
        path, attribute, value = fields[index : index + 3]
        if (attribute, value) in (("binary", "set"), ("text", "unset")):
            marked.add(path)
    return marked


def scan_text(path: str, text: str, allowlist: list[AllowlistEntry]) -> list[Violation]:
    """Scan decoded text for forbidden code points."""
    violations: list[Violation] = []
    line = 1
    col = 0
    for index, char in enumerate(text):
        if char == "\n":
            line += 1
            col = 0
            continue
        col += 1
        codepoint = ord(char)

        if codepoint == BOM:
            # Allowed only as the very first character (leading BOM).
            if index == 0:
                continue
            if is_allowed(path, codepoint, allowlist):
                continue
            violations.append(
                Violation(path, line, col, codepoint, "U+FEFF not a leading BOM")
            )
            continue

        description = classify(codepoint)
        if description is None or is_emoji_presentation(text, index):
            continue
        if is_allowed(path, codepoint, allowlist):
            continue
        violations.append(Violation(path, line, col, codepoint, description))

    return violations


def scan_path(path: str) -> list[Violation]:
    """Scan a path's own characters: every directory and the file name.

    A name has no place for a byte-order mark or an emoji presentation
    selector, and no allowlist entry exempts one, so ``classify`` alone
    decides.
    """
    violations: list[Violation] = []
    for position, char in enumerate(path, start=1):
        description = classify(ord(char))
        if description is not None:
            violations.append(Violation(path, 0, position, ord(char), description, in_name=True))
    return violations


class ListingError(Exception):
    """The tracked files could not be listed."""


def tracked_files() -> list[str]:
    """The files git tracks. Raises ListingError when git cannot list them
    or a name is not UTF-8: there is no fallback, and an empty list would
    read as a clean scan."""
    try:
        output = subprocess.run(
            ["git", "ls-files", "-z"],
            check=True,
            capture_output=True,
        ).stdout
    except subprocess.CalledProcessError as exc:
        reason = exc.stderr.decode("utf-8", errors="replace").strip() if exc.stderr else ""
        raise ListingError(f"git ls-files exited {exc.returncode}: {reason}") from exc
    except FileNotFoundError as exc:
        raise ListingError("git was not found") from exc
    try:
        names = output.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ListingError("a tracked file's name is not valid UTF-8") from exc
    return [name for name in names.split("\0") if name]


def main(argv: list[str]) -> int:
    args = argv[1:]

    allowlist_path = os.environ.get(
        "UNICODE_ALLOWLIST", ".unicode-allowlist.txt"
    )
    try:
        allowlist = parse_allowlist(allowlist_path)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if args:
        files = args
    else:
        try:
            files = tracked_files()
        except ListingError as exc:
            print(f"error: cannot list the tracked files: {exc}", file=sys.stderr)
            return 1

    violations: list[Violation] = []
    # Files that hold a NUL or are not UTF-8: reported unless .gitattributes
    # marks them binary, which git answers for all of them at once.
    not_text: list[tuple[str, Violation, list[Violation]]] = []
    for path in files:
        # The name first: it is read for every path, also where the content
        # is skipped below.
        violations.extend(scan_path(path))
        if not os.path.isfile(path) or is_listed_binary(path):
            continue
        data = read_bytes(path)
        if data is None:
            print(f"error: {path}: cannot be read", file=sys.stderr)
            return 1
        found = scan_text(path, decode(data), allowlist)
        problem = encoding_violation(path, data)
        if problem is None:
            violations.extend(found)
        else:
            not_text.append((path, problem, found))

    marked = gitattributes_binary([path for path, _, _ in not_text])
    for path, problem, found in not_text:
        if path not in marked:
            violations.append(problem)
            violations.extend(found)

    if violations:
        print(
            "Forbidden invisible / bidirectional Unicode characters detected:",
            file=sys.stderr,
        )
        for violation in violations:
            print(violation.render(), file=sys.stderr)
        print(
            f"\n{len(violations)} violation(s) found. If an occurrence is "
            f"legitimate, add it to {allowlist_path} with a written reason.",
            file=sys.stderr,
        )
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
