#!/usr/bin/env python3
"""Three-way merge of gettext catalogues (.po/.pot), usable as a git merge driver.

Usage::

    python3 scripts/merge_gettext.py BASE OURS THEIRS [-o OUT]

BASE is the common ancestor, OURS and THEIRS the two sides. The result goes to
OUT, or into OURS when no OUT is given: git's merge-driver convention, so
``merge.gettext.driver = python3 scripts/merge_gettext.py %O %A %B`` works.
Exit status 0 is a clean merge, 1 a refusal (a conflict or a fuzzy entry, each
named on stderr), 2 an unreadable catalogue or bad arguments. On 1 and 2
nothing is written.

Why it exists: Sprint 22 integrated several stories' German catalogues by
hand; a fuzzy-matched msgid kept an old German text and the merge dropped the
file's final newline, the sprint's one red CI run (Sprint 22 retrospective,
carry-forward 2). The rules, each against that:

  * The msgids of both sides are united. An entry's identity is msgctxt,
    msgid and msgid_plural, as gettext's. The result keeps OURS' order, and
    entries only THEIRS added follow at the end in THEIRS' order, which is
    where the stories' blocks were appended by hand.
  * Every changed msgstr is kept: a msgstr only one side changed against BASE
    comes from that side; two different changes are a conflict.
  * An entry one side deleted is deleted when the other side left its msgstr
    alone (a moved ``#:`` reference does not keep it); when the other side
    changed its msgstr, that is a conflict.
  * ``#:`` references and other comments come from the side that changed
    them; when both did, they are united (OURS' lines first). The flags of
    ``#,`` merge three ways token by token, so a side that removed ``fuzzy``
    removes it.
  * The header entry (msgid "") is OURS', unless only THEIRS changed it.
  * Any entry flagged ``fuzzy`` in the result is refused: a fuzzy match is an
    old translation of a different text.
  * Obsolete ``#~`` entries are dropped, as ``mix gettext.merge`` drops
    obsolete entries by default.
  * The output ends with exactly one newline.

After a merge, run ``mix gettext.extract --check-up-to-date``: references the
two sides moved are united here and only the extractor knows which still hold.

The reader and writer below round-trip every committed catalogue
byte-identically, so a catalogue nobody changed comes out unchanged.

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

import argparse
import re
import sys
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


class MergeRefused(Exception):
    """The merge would lose a change or land a fuzzy translation."""

    def __init__(self, problems: list[str]):
        super().__init__("\n".join(problems))
        self.problems = problems


REFERENCE = "#:"
FLAGS = "#,"
PREVIOUS = "#|"


def _comment_parts(entry: Entry) -> tuple[list[str], list[str], list[str], list[str]]:
    """Split comments into leading notes, references, flag tokens and previous-msgid lines."""
    notes = [line for line in entry.comments if not line.startswith((REFERENCE, FLAGS, PREVIOUS))]
    previous = [line for line in entry.comments if line.startswith(PREVIOUS)]
    return notes, entry.references(), entry.flags(), previous


def _merge_lines(base: list[str] | None, ours: list[str], theirs: list[str]) -> list[str]:
    """Take the side that changed; when both did, unite them, minus lines a side removed."""
    if base is not None and ours == base:
        return list(theirs)
    if base is not None and theirs == base:
        return list(ours)
    removed = set() if base is None else {line for line in base if line not in ours or line not in theirs}
    united = [line for line in ours if line not in removed]
    united += [line for line in theirs if line not in united and line not in removed]
    return united


def _merge_flags(base: list[str] | None, ours: list[str], theirs: list[str]) -> list[str]:
    base_set = set(base or [])
    kept = [flag for flag in ours if flag in theirs or flag not in base_set]
    kept += [flag for flag in theirs if flag not in kept and flag not in ours and flag not in base_set]
    return kept


def _merge_comments(base: Entry | None, ours: Entry, theirs: Entry) -> list[str]:
    base_parts = None if base is None else _comment_parts(base)
    ours_parts = _comment_parts(ours)
    theirs_parts = _comment_parts(theirs)
    notes = _merge_lines(base_parts and base_parts[0], ours_parts[0], theirs_parts[0])
    references = _merge_lines(base_parts and base_parts[1], ours_parts[1], theirs_parts[1])
    flags = _merge_flags(base_parts and base_parts[2], ours_parts[2], theirs_parts[2])
    previous = _merge_lines(base_parts and base_parts[3], ours_parts[3], theirs_parts[3])
    if (notes, references, flags, previous) == ours_parts:
        return list(ours.comments)
    if (notes, references, flags, previous) == theirs_parts:
        return list(theirs.comments)
    flag_lines = [FLAGS + " " + ", ".join(flags)] if flags else []
    return notes + references + flag_lines + previous


def _merge_entry(base: Entry | None, ours: Entry, theirs: Entry, problems: list[str]) -> Entry:
    if ours.is_header:
        changed_only_theirs = (
            base is not None and render_entry(ours) == render_entry(base) and render_entry(theirs) != render_entry(base)
        )
        return theirs if changed_only_theirs else ours
    base_msgstr = None if base is None else base.msgstr_text()
    if ours.msgstr_text() == theirs.msgstr_text() or theirs.msgstr_text() == base_msgstr:
        msgstr = ours.msgstr
    elif ours.msgstr_text() == base_msgstr:
        msgstr = theirs.msgstr
    else:
        problems.append(f"conflict: both sides changed the msgstr of {ours.describe()} differently")
        msgstr = ours.msgstr
    return Entry(
        comments=_merge_comments(base, ours, theirs),
        msgctxt=ours.msgctxt,
        msgid=ours.msgid,
        msgid_plural=ours.msgid_plural,
        msgstr=msgstr,
    )


def _by_key(entries: list[Entry]) -> dict:
    return {entry.key: entry for entry in entries if not entry.obsolete}


def merge(base_text: str, ours_text: str, theirs_text: str) -> str:
    """Merge three catalogue texts; raise MergeRefused naming every problem."""
    base = _by_key(parse(base_text))
    ours_entries = [entry for entry in parse(ours_text) if not entry.obsolete]
    theirs_entries = [entry for entry in parse(theirs_text) if not entry.obsolete]
    ours = _by_key(ours_entries)
    theirs = _by_key(theirs_entries)
    problems: list[str] = []
    result: list[Entry] = []

    def one_sided(kept: Entry, other_side: str) -> None:
        original = base.get(kept.key)
        if original is None:
            result.append(kept)
        elif kept.msgstr_text() != original.msgstr_text():
            problems.append(
                f"conflict: {other_side} deleted {kept.describe()}, the other side changed its msgstr"
            )

    for entry in ours_entries:
        if entry.key in theirs:
            result.append(_merge_entry(base.get(entry.key), entry, theirs[entry.key], problems))
        else:
            one_sided(entry, "theirs")
    for entry in theirs_entries:
        if entry.key not in ours:
            one_sided(entry, "ours")

    result.sort(key=lambda entry: not entry.is_header)
    problems.extend(
        f"fuzzy: {entry.describe()} is flagged fuzzy; confirm its msgstr and remove the flag first"
        for entry in result
        if entry.is_fuzzy
    )
    if problems:
        raise MergeRefused(problems)
    return render(result)


def _read(path: str) -> str:
    with open(path, encoding="utf-8", newline="") as handle:
        return handle.read()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Three-way merge of a gettext catalogue (git merge driver: %%O %%A %%B).",
    )
    parser.add_argument("base", help="the common ancestor (%%O)")
    parser.add_argument("ours", help="our side (%%A); the result goes here unless -o is given")
    parser.add_argument("theirs", help="their side (%%B)")
    parser.add_argument("-o", "--output", help="write the result here instead of into OURS")
    try:
        args = parser.parse_args(argv)
    except SystemExit as exit_:
        return 2 if exit_.code else 0

    texts = []
    for path in (args.base, args.ours, args.theirs):
        try:
            texts.append(_read(path))
            parse(texts[-1])
        except (OSError, UnicodeDecodeError, ParseError) as error:
            print(f"merge_gettext: {path}: {error}", file=sys.stderr)
            return 2
    try:
        merged = merge(*texts)
    except MergeRefused as refused:
        for problem in refused.problems:
            print(f"merge_gettext: {args.ours}: {problem}", file=sys.stderr)
        print("merge_gettext: refused; nothing was written", file=sys.stderr)
        return 1
    with open(args.output or args.ours, "w", encoding="utf-8", newline="") as handle:
        handle.write(merged)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
