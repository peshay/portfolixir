#!/usr/bin/env python3
"""Self-tests for scripts/merge_gettext.py.

Run with::

    python3 -B -m unittest discover --start-directory scripts --pattern "test_merge_gettext.py"

The pre-commit hook `scripts-self-tests` runs them, with every other
``scripts/test_*.py``, in CI's pre-commit job.

The fixtures are small synthetic catalogues written inline; the round-trip
tests also read the committed catalogues under ``priv/gettext``, without
writing to them.
"""

from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import merge_gettext  # noqa: E402

REPOSITORY_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

HEADER = '## Synthetic catalogue.\nmsgid ""\nmsgstr ""\n"Language: de\\n"\n'

SIMPLE = (
    HEADER
    + "\n"
    + "#: lib/a.ex:1\n"
    + "#: lib/b.ex:2\n"
    + "#, elixir-autogen, elixir-format\n"
    + 'msgid "Cash accounts"\n'
    + 'msgstr "Verrechnungskonten"\n'
)

PLURAL = (
    HEADER
    + "\n"
    + "#: lib/a.ex:3\n"
    + "#, elixir-autogen, elixir-format\n"
    + 'msgid "Moved %{count} security"\n'
    + 'msgid_plural "Moved %{count} securities"\n'
    + 'msgstr[0] "%{count} Wertpapier verschoben"\n'
    + 'msgstr[1] "%{count} Wertpapiere verschoben"\n'
)

CONTEXT = (
    HEADER
    + "\n"
    + "#, elixir-autogen, elixir-format\n"
    + 'msgctxt "data-note severity"\n'
    + 'msgid "Note"\n'
    + 'msgstr "Hinweis"\n'
    + "\n"
    + 'msgid "Note"\n'
    + 'msgstr "Notiz"\n'
)

MULTILINE = (
    HEADER
    + "\n"
    + 'msgid ""\n'
    + '"First line\\n"\n'
    + '"second \\"quoted\\" line"\n'
    + 'msgstr ""\n'
    + '"Erste Zeile\\n"\n'
    + '"zweite \\"zitierte\\" Zeile\\twith a tab \\\\ and a backslash"\n'
)

OBSOLETE = (
    HEADER
    + "\n"
    + 'msgid "Kept"\n'
    + 'msgstr "Behalten"\n'
    + "\n"
    + "#~ msgid \"Gone\"\n"
    + "#~ msgstr \"Weg\"\n"
)


class ParseTests(unittest.TestCase):
    def test_header_is_the_first_entry_with_its_leading_comment(self):
        entries = merge_gettext.parse(SIMPLE)
        header = entries[0]
        self.assertTrue(header.is_header)
        self.assertEqual(header.comments, ["## Synthetic catalogue."])
        self.assertEqual(header.msgstr_text(), {None: "Language: de\n"})

    def test_an_entry_keeps_its_references_flags_and_strings(self):
        entry = merge_gettext.parse(SIMPLE)[1]
        self.assertEqual(entry.references(), ["#: lib/a.ex:1", "#: lib/b.ex:2"])
        self.assertEqual(entry.flags(), ["elixir-autogen", "elixir-format"])
        self.assertEqual(entry.key, (None, "Cash accounts", None))
        self.assertEqual(entry.msgstr_text(), {None: "Verrechnungskonten"})

    def test_plural_forms_are_indexed(self):
        entry = merge_gettext.parse(PLURAL)[1]
        self.assertEqual(
            entry.key,
            (None, "Moved %{count} security", "Moved %{count} securities"),
        )
        self.assertEqual(
            entry.msgstr_text(),
            {0: "%{count} Wertpapier verschoben", 1: "%{count} Wertpapiere verschoben"},
        )

    def test_msgctxt_is_part_of_the_identity(self):
        entries = merge_gettext.parse(CONTEXT)
        self.assertEqual(entries[1].key, ("data-note severity", "Note", None))
        self.assertEqual(entries[2].key, (None, "Note", None))

    def test_multiline_strings_are_joined_and_unescaped(self):
        entry = merge_gettext.parse(MULTILINE)[1]
        self.assertEqual(entry.key, (None, 'First line\nsecond "quoted" line', None))
        self.assertEqual(
            entry.msgstr_text(),
            {None: 'Erste Zeile\nzweite "zitierte" Zeile\twith a tab \\ and a backslash'},
        )

    def test_obsolete_entries_are_marked(self):
        entries = merge_gettext.parse(OBSOLETE)
        self.assertFalse(entries[1].obsolete)
        self.assertTrue(entries[2].obsolete)
        self.assertEqual(entries[2].key, (None, "Gone", None))

    def test_fuzzy_flag_is_detected(self):
        text = HEADER + "\n#, fuzzy, elixir-format\nmsgid \"A\"\nmsgstr \"B\"\n"
        self.assertTrue(merge_gettext.parse(text)[1].is_fuzzy)
        self.assertFalse(merge_gettext.parse(SIMPLE)[1].is_fuzzy)

    def test_an_unknown_line_is_a_parse_error_naming_the_line(self):
        with self.assertRaises(merge_gettext.ParseError) as raised:
            merge_gettext.parse(HEADER + "\nmsgid \"A\"\nnonsense\n")
        self.assertIn("line 7", str(raised.exception))


class RenderTests(unittest.TestCase):
    def test_each_fixture_round_trips_byte_identically(self):
        for text in (SIMPLE, PLURAL, CONTEXT, MULTILINE, OBSOLETE):
            with self.subTest(text=text.splitlines()[-1]):
                self.assertEqual(merge_gettext.render(merge_gettext.parse(text)), text)

    def test_output_ends_with_exactly_one_newline(self):
        self.assertTrue(merge_gettext.render(merge_gettext.parse(SIMPLE.rstrip("\n"))).endswith('"\n'))
        rendered = merge_gettext.render(merge_gettext.parse(SIMPLE + "\n\n\n"))
        self.assertEqual(rendered, SIMPLE)

    def test_entries_are_separated_by_exactly_one_blank_line(self):
        loose = SIMPLE.replace("\n\n", "\n\n\n\n")
        self.assertEqual(merge_gettext.render(merge_gettext.parse(loose)), SIMPLE)


class CommittedCatalogueTests(unittest.TestCase):
    """Parsing and rendering every committed catalogue changes no byte."""

    def _catalogues(self) -> list[str]:
        found = []
        for directory, _subdirectories, names in os.walk(os.path.join(REPOSITORY_ROOT, "priv", "gettext")):
            found.extend(os.path.join(directory, name) for name in names if name.endswith((".po", ".pot")))
        return sorted(found)

    def test_the_german_default_catalogue_is_among_them(self):
        expected = os.path.join(REPOSITORY_ROOT, "priv", "gettext", "de", "LC_MESSAGES", "default.po")
        self.assertIn(expected, self._catalogues())

    def test_every_committed_catalogue_round_trips_byte_identically(self):
        for path in self._catalogues():
            with self.subTest(path=os.path.relpath(path, REPOSITORY_ROOT)):
                with open(path, "rb") as handle:
                    original = handle.read()
                rendered = merge_gettext.render(merge_gettext.parse(original.decode("utf-8")))
                self.assertEqual(rendered.encode("utf-8"), original)


if __name__ == "__main__":
    unittest.main()
