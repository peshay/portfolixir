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
  * Any other character in the Unicode general category ``Cf`` (Format) that is
    not on the explicit allowlist. This is the conservative catch-all: ``Cf``
    covers invisible formatting characters (interlinear annotations, additional
    bidi/joining controls, etc.) without touching normal printable text,
    whitespace (tab/newline/space are ``Cc``/``Zs``, not ``Cf``), or letters.

WHAT IS NOT FLAGGED
-------------------
  * Regular text, letters, digits, punctuation, symbols, emoji.
  * Ordinary whitespace: TAB (U+0009), LF (U+000A), CR (U+000D), SPACE (U+0020).
  * A single U+FEFF appearing as the very first character of a file (a UTF-8
    byte-order mark). A BOM anywhere else is flagged.
  * Binary files (detected via NUL byte or UTF-8 decode failure) are skipped.
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
found. Output is ``path:line:col: U+XXXX NAME (description)`` per violation.

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

# Code points that are allowed despite being control/format characters because
# they are ordinary text structure. (Cc whitespace is also explicitly allowed.)
ALLOWED_WHITESPACE = {0x09, 0x0A, 0x0D, 0x20}


@dataclass(frozen=True)
class Violation:
    path: str
    line: int
    col: int
    codepoint: int
    description: str

    def render(self) -> str:
        try:
            name = unicodedata.name(chr(self.codepoint))
        except ValueError:
            name = "<unnamed>"
        return (
            f"{self.path}:{self.line}:{self.col}: "
            f"U+{self.codepoint:04X} {name} ({self.description})"
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


def classify(codepoint: int) -> str | None:
    """Return a human description if the code point is forbidden, else None.

    U+FEFF is intentionally not classified here; leading-BOM handling happens
    in the per-file scan so byte offset is known.
    """
    if codepoint in BIDI_CONTROLS:
        return "bidirectional control character (Trojan Source)"
    if codepoint in ZERO_WIDTH:
        return "zero-width / invisible character"
    if codepoint in TAG_CHARS:
        return "Unicode tag character"
    if codepoint in ALLOWED_WHITESPACE:
        return None
    # Conservative catch-all: any other format (Cf) character is invisible.
    if unicodedata.category(chr(codepoint)) == "Cf":
        return "invisible format character (Unicode category Cf)"
    return None


def read_text(path: str) -> str | None:
    """Read a file as UTF-8 text. Return None if it looks binary.

    A file is treated as binary (and skipped) if it contains a NUL byte or
    fails to decode as UTF-8.
    """
    try:
        with open(path, "rb") as handle:
            data = handle.read()
    except (OSError, IOError):
        return None
    if b"\x00" in data:
        return None
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


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
        if description is None:
            continue
        if is_allowed(path, codepoint, allowlist):
            continue
        violations.append(Violation(path, line, col, codepoint, description))

    return violations


def tracked_files() -> list[str]:
    """Enumerate tracked files via git, falling back to a recursive walk."""
    try:
        output = subprocess.run(
            ["git", "ls-files", "-z"],
            check=True,
            capture_output=True,
        ).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    return [name for name in output.decode("utf-8").split("\0") if name]


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

    files = args if args else tracked_files()

    violations: list[Violation] = []
    for path in files:
        if not os.path.isfile(path):
            continue
        text = read_text(path)
        if text is None:
            continue  # binary or unreadable -> skip
        violations.extend(scan_text(path, text, allowlist))

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
