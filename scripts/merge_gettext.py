#!/usr/bin/env python3
"""Read and write gettext catalogues (.po/.pot) without changing a byte.

Sprint 22 integrated several stories' German catalogues by hand: a
fuzzy-matched msgid kept an old German text and the merge dropped the file's
final newline (Sprint 22 retrospective, carry-forward 2). This module is the
ground the merge tool stands on: it parses a catalogue into entries and renders
them back exactly as `mix gettext.extract` / `mix gettext.merge` write them, so
that a catalogue nobody changed comes out of the tool byte-identical.

The model follows Expo, the library Elixir's gettext writes with:

  * an entry is its comment lines, then ``msgctxt``, ``msgid``,
    ``msgid_plural`` and ``msgstr`` (or ``msgstr[N]``);
  * every string keeps the segments it was written in (``msgid ""`` followed
    by ``"line\\n"`` continuation lines is two segments), so a multi-line
    string renders the way it was read;
  * an obsolete entry (``#~`` lines) is parsed and rendered with its marker;
  * entries are separated by exactly one blank line, and the output ends with
    exactly one newline.

Standard library only.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

KEYWORD_LINE = re.compile(r'^(msgctxt|msgid_plural|msgid|msgstr(?:\[(\d+)\])?)[ \t]+"(.*)"$')
CONTINUATION_LINE = re.compile(r'^"(.*)"$')
OBSOLETE_PREFIX = "#~ "

UNESCAPES = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\"}
ESCAPES = {value: "\\" + key for key, value in UNESCAPES.items()}


class ParseError(ValueError):
    """The text is not a catalogue this tool can read back unchanged."""


def unescape(literal: str, line_number: int) -> str:
    out = []
    index = 0
    while index < len(literal):
        char = literal[index]
        if char == "\\":
            if index + 1 >= len(literal) or literal[index + 1] not in UNESCAPES:
                raise ParseError(f"line {line_number}: unsupported escape in {literal!r}")
            out.append(UNESCAPES[literal[index + 1]])
            index += 2
            continue
        if char == '"':
            raise ParseError(f"line {line_number}: unescaped quote in {literal!r}")
        out.append(char)
        index += 1
    return "".join(out)


def escape(text: str) -> str:
    return "".join(ESCAPES.get(char, char) for char in text)


@dataclass
class Entry:
    """One catalogue entry. Strings are lists of their written segments."""

    comments: list[str] = field(default_factory=list)
    msgctxt: list[str] | None = None
    msgid: list[str] = field(default_factory=list)
    msgid_plural: list[str] | None = None
    # (index, segments) in written order; index is None for a plain msgstr.
    msgstr: list[tuple[int | None, list[str]]] = field(default_factory=list)
    obsolete: bool = False

    @property
    def key(self) -> tuple[str | None, str, str | None]:
        """The identity gettext uses: msgctxt, msgid and msgid_plural."""
        return (
            None if self.msgctxt is None else "".join(self.msgctxt),
            "".join(self.msgid),
            None if self.msgid_plural is None else "".join(self.msgid_plural),
        )

    @property
    def is_header(self) -> bool:
        return self.msgctxt is None and self.key[1] == "" and not self.obsolete

    def msgstr_text(self) -> dict[int | None, str]:
        return {index: "".join(segments) for index, segments in self.msgstr}

    def references(self) -> list[str]:
        return [line for line in self.comments if line.startswith("#:")]

    def flags(self) -> list[str]:
        tokens: list[str] = []
        for line in self.comments:
            if line.startswith("#,"):
                tokens.extend(token.strip() for token in line[2:].split(",") if token.strip())
        return tokens

    @property
    def is_fuzzy(self) -> bool:
        return "fuzzy" in self.flags()

    def describe(self) -> str:
        context, msgid, _plural = self.key
        if context is None:
            return f"msgid {msgid!r}"
        return f"msgctxt {context!r} msgid {msgid!r}"


def _blocks(text: str) -> list[list[tuple[int, str]]]:
    blocks: list[list[tuple[int, str]]] = []
    current: list[tuple[int, str]] = []
    for number, line in enumerate(text.split("\n"), start=1):
        if line.strip() == "":
            if current:
                blocks.append(current)
                current = []
            continue
        current.append((number, line))
    if current:
        blocks.append(current)
    return blocks


def _parse_block(block: list[tuple[int, str]]) -> Entry:
    entry = Entry()
    target: list[str] | None = None
    seen_keyword = False
    for number, raw in block:
        line = raw
        if raw.startswith("#~"):
            if not raw.startswith(OBSOLETE_PREFIX):
                raise ParseError(f"line {number}: unsupported obsolete line {raw!r}")
            entry.obsolete = True
            line = raw[len(OBSOLETE_PREFIX):]
        elif raw.startswith("#"):
            if seen_keyword:
                raise ParseError(f"line {number}: a comment after the entry's strings")
            entry.comments.append(raw)
            continue
        keyword = KEYWORD_LINE.match(line)
        if keyword:
            seen_keyword = True
            name, index, literal = keyword.group(1), keyword.group(2), keyword.group(3)
            segments = [unescape(literal, number)]
            if name == "msgctxt":
                entry.msgctxt = segments
            elif name == "msgid":
                entry.msgid = segments
            elif name == "msgid_plural":
                entry.msgid_plural = segments
            else:
                entry.msgstr.append((None if index is None else int(index), segments))
            target = segments
            continue
        continuation = CONTINUATION_LINE.match(line)
        if continuation and target is not None:
            target.append(unescape(continuation.group(1), number))
            continue
        raise ParseError(f"line {number}: cannot read {raw!r}")
    if not seen_keyword:
        raise ParseError(f"line {block[0][0]}: a comment block without an entry")
    if not entry.msgstr:
        raise ParseError(f"line {block[0][0]}: an entry without msgstr")
    return entry


def parse(text: str) -> list[Entry]:
    """Parse a catalogue into its entries, header first when it has one."""
    return [_parse_block(block) for block in _blocks(text)]


def _render_string(keyword: str, segments: list[str], prefix: str) -> list[str]:
    lines = [f'{prefix}{keyword} "{escape(segments[0])}"']
    lines.extend(f'{prefix}"{escape(segment)}"' for segment in segments[1:])
    return lines


def render_entry(entry: Entry) -> str:
    prefix = OBSOLETE_PREFIX if entry.obsolete else ""
    lines = list(entry.comments)
    if entry.msgctxt is not None:
        lines.extend(_render_string("msgctxt", entry.msgctxt, prefix))
    lines.extend(_render_string("msgid", entry.msgid, prefix))
    if entry.msgid_plural is not None:
        lines.extend(_render_string("msgid_plural", entry.msgid_plural, prefix))
    for index, segments in entry.msgstr:
        keyword = "msgstr" if index is None else f"msgstr[{index}]"
        lines.extend(_render_string(keyword, segments, prefix))
    return "\n".join(lines)


def render(entries: list[Entry]) -> str:
    """Render entries one blank line apart, ending with exactly one newline."""
    return "\n\n".join(render_entry(entry) for entry in entries) + "\n"
