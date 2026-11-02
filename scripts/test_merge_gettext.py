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

import contextlib
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import merge_gettext  # noqa: E402

# The variables git sets for a hook. A test that runs git in a throwaway
# repository drops them, or git acts on the repository whose hook runs the
# test (#1364).
HOOK_GIT_VARIABLES = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR")

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


def catalogue(*entries: str, header: str = HEADER) -> str:
    """A catalogue of the header and the given entries, one blank line apart."""
    return "\n".join([header, *(entry.rstrip("\n") + "\n" for entry in entries)])


def entry(msgid: str, msgstr: str, refs: str = "lib/a.ex:1", flags: str = "elixir-autogen, elixir-format") -> str:
    lines = [f"#: {ref}" for ref in refs.split()] if refs else []
    if flags:
        lines.append(f"#, {flags}")
    lines += [f'msgid "{msgid}"', f'msgstr "{msgstr}"']
    return "\n".join(lines) + "\n"


ACCOUNTS = entry("Cash accounts", "Verrechnungskonten")
NAVIGATION = entry("Application navigation", "App-Navigation", refs="lib/shell.ex:26")


class MergeTests(unittest.TestCase):
    def merge(self, base: str, ours: str, theirs: str) -> str:
        return merge_gettext.merge(base, ours, theirs)

    def refused(self, base: str, ours: str, theirs: str) -> str:
        with self.assertRaises(merge_gettext.MergeRefused) as raised:
            merge_gettext.merge(base, ours, theirs)
        return str(raised.exception)

    def test_msgids_of_both_sides_are_united_theirs_new_ones_appended_in_order(self):
        base = catalogue(NAVIGATION, ACCOUNTS)
        ours = catalogue(NAVIGATION, entry("Ours new", "Unser neu"), ACCOUNTS)
        theirs = catalogue(NAVIGATION, ACCOUNTS, entry("Theirs one", "Ihr eins"), entry("Theirs two", "Ihr zwei"))
        self.assertEqual(
            self.merge(base, ours, theirs),
            catalogue(
                NAVIGATION,
                entry("Ours new", "Unser neu"),
                ACCOUNTS,
                entry("Theirs one", "Ihr eins"),
                entry("Theirs two", "Ihr zwei"),
            ),
        )

    def test_nothing_changed_gives_ours_byte_identically(self):
        text = catalogue(NAVIGATION, ACCOUNTS)
        self.assertEqual(self.merge(text, text, text), text)

    def test_a_msgstr_only_theirs_changed_is_taken_from_theirs(self):
        base = catalogue(ACCOUNTS)
        theirs = catalogue(entry("Cash accounts", "Konten"))
        self.assertEqual(self.merge(base, base, theirs), theirs)

    def test_a_msgstr_only_ours_changed_is_kept(self):
        base = catalogue(ACCOUNTS)
        ours = catalogue(entry("Cash accounts", "Konten"))
        self.assertEqual(self.merge(base, ours, base), ours)

    def test_the_same_change_on_both_sides_is_no_conflict(self):
        base = catalogue(ACCOUNTS)
        both = catalogue(entry("Cash accounts", "Konten"))
        self.assertEqual(self.merge(base, both, both), both)

    def test_two_different_msgstr_changes_are_a_conflict_naming_the_msgid(self):
        base = catalogue(ACCOUNTS)
        ours = catalogue(entry("Cash accounts", "Konten"))
        theirs = catalogue(entry("Cash accounts", "Geldkonten"))
        message = self.refused(base, ours, theirs)
        self.assertIn("conflict", message)
        self.assertIn("'Cash accounts'", message)

    def test_both_sides_adding_one_msgid_with_different_msgstr_is_a_conflict(self):
        base = catalogue(NAVIGATION)
        ours = catalogue(NAVIGATION, entry("Fresh", "Frisch"))
        theirs = catalogue(NAVIGATION, entry("Fresh", "Neu"))
        self.assertIn("'Fresh'", self.refused(base, ours, theirs))

    def test_an_entry_deleted_on_one_side_and_unchanged_on_the_other_is_deleted(self):
        base = catalogue(NAVIGATION, ACCOUNTS)
        deleted = catalogue(NAVIGATION)
        self.assertEqual(self.merge(base, base, deleted), deleted)
        self.assertEqual(self.merge(base, deleted, base), deleted)

    def test_a_moved_reference_does_not_keep_a_deleted_entry(self):
        base = catalogue(NAVIGATION, ACCOUNTS)
        ours = catalogue(NAVIGATION, entry("Cash accounts", "Verrechnungskonten", refs="lib/a.ex:9"))
        theirs = catalogue(NAVIGATION)
        self.assertEqual(self.merge(base, ours, theirs), theirs)

    def test_a_deleted_entry_whose_msgstr_the_other_side_changed_is_a_conflict(self):
        base = catalogue(NAVIGATION, ACCOUNTS)
        ours = catalogue(NAVIGATION)
        theirs = catalogue(NAVIGATION, entry("Cash accounts", "Konten"))
        self.assertIn("'Cash accounts'", self.refused(base, ours, theirs))

    def test_references_come_from_the_side_that_changed_them(self):
        base = catalogue(ACCOUNTS)
        theirs = catalogue(entry("Cash accounts", "Verrechnungskonten", refs="lib/a.ex:1 lib/c.ex:7"))
        self.assertEqual(self.merge(base, base, theirs), theirs)

    def test_references_both_sides_changed_are_united(self):
        base = catalogue(entry("Cash accounts", "Verrechnungskonten", refs="lib/a.ex:1 lib/b.ex:2"))
        ours = catalogue(entry("Cash accounts", "Verrechnungskonten", refs="lib/a.ex:1 lib/b.ex:2 lib/o.ex:3"))
        theirs = catalogue(entry("Cash accounts", "Verrechnungskonten", refs="lib/b.ex:2 lib/t.ex:4"))
        self.assertEqual(
            self.merge(base, ours, theirs),
            catalogue(entry("Cash accounts", "Verrechnungskonten", refs="lib/b.ex:2 lib/o.ex:3 lib/t.ex:4")),
        )

    def test_a_fuzzy_entry_from_theirs_is_refused_naming_it(self):
        base = catalogue(ACCOUNTS)
        theirs = catalogue(entry("Cash accounts", "Verrechnungskonten", flags="fuzzy, elixir-autogen, elixir-format"))
        message = self.refused(base, base, theirs)
        self.assertIn("fuzzy", message)
        self.assertIn("'Cash accounts'", message)

    def test_a_new_fuzzy_entry_is_refused(self):
        base = catalogue(NAVIGATION)
        ours = catalogue(NAVIGATION, entry("Cash account", "Verrechnungskonten", flags="fuzzy, elixir-format"))
        self.assertIn("'Cash account'", self.refused(base, ours, base))

    def test_a_fuzzy_flag_one_side_removed_is_gone(self):
        base = catalogue(entry("Cash accounts", "Konten", flags="fuzzy, elixir-format"))
        theirs = catalogue(entry("Cash accounts", "Verrechnungskonten", flags="elixir-format"))
        self.assertEqual(self.merge(base, base, theirs), theirs)

    def test_the_header_only_theirs_changed_is_taken_from_theirs(self):
        base = catalogue(ACCOUNTS)
        header = HEADER + '"Plural-Forms: nplurals=2; plural=(n != 1);\\n"\n'
        theirs = catalogue(ACCOUNTS, header=header)
        self.assertEqual(self.merge(base, base, theirs), theirs)

    def test_the_header_both_sides_changed_is_ours(self):
        base = catalogue(ACCOUNTS)
        ours = catalogue(ACCOUNTS, header=HEADER.replace("Synthetic", "Our"))
        theirs = catalogue(ACCOUNTS, header=HEADER.replace("Synthetic", "Their"))
        self.assertEqual(self.merge(base, ours, theirs), ours)

    def test_a_plural_form_only_theirs_changed_is_taken(self):
        base = PLURAL
        theirs = PLURAL.replace("Wertpapiere verschoben", "Wertpapiere umgehängt")
        ours = PLURAL.replace("lib/a.ex:3", "lib/a.ex:4")
        self.assertEqual(
            self.merge(base, ours, theirs),
            PLURAL.replace("Wertpapiere verschoben", "Wertpapiere umgehängt").replace("lib/a.ex:3", "lib/a.ex:4"),
        )

    def test_a_multiline_msgstr_keeps_the_changing_sides_lines(self):
        theirs = MULTILINE.replace('"Erste Zeile\\n"', '"Die erste Zeile\\n"')
        self.assertEqual(self.merge(MULTILINE, MULTILINE, theirs), theirs)

    def test_obsolete_entries_are_dropped(self):
        self.assertEqual(self.merge(OBSOLETE, OBSOLETE, OBSOLETE), catalogue('msgid "Kept"\nmsgstr "Behalten"\n'))

    def test_the_result_ends_with_exactly_one_newline(self):
        base = catalogue(ACCOUNTS)
        theirs = catalogue(ACCOUNTS, NAVIGATION)
        self.assertEqual(self.merge(base, base.rstrip("\n"), theirs + "\n\n"), theirs)


class CommandLineTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.directory)

    def _write(self, name: str, text: str) -> str:
        path = os.path.join(self.directory, name)
        with open(path, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        return path

    def _read(self, path: str) -> str:
        with open(path, encoding="utf-8", newline="") as handle:
            return handle.read()

    def _main(self, *argv: str) -> tuple[int, str]:
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            status = merge_gettext.main(list(argv))
        return status, stderr.getvalue()

    def test_by_default_the_result_is_written_into_ours(self):
        base = self._write("base.po", catalogue(ACCOUNTS))
        ours = self._write("ours.po", catalogue(ACCOUNTS))
        theirs = self._write("theirs.po", catalogue(ACCOUNTS, NAVIGATION))
        self.assertEqual(self._main(base, ours, theirs)[0], 0)
        self.assertEqual(self._read(ours), catalogue(ACCOUNTS, NAVIGATION))

    def test_dash_o_writes_elsewhere_and_leaves_ours_alone(self):
        base = self._write("base.po", catalogue(ACCOUNTS))
        ours = self._write("ours.po", catalogue(ACCOUNTS))
        theirs = self._write("theirs.po", catalogue(ACCOUNTS, NAVIGATION))
        out = os.path.join(self.directory, "out.po")
        self.assertEqual(self._main(base, ours, theirs, "-o", out)[0], 0)
        self.assertEqual(self._read(out), catalogue(ACCOUNTS, NAVIGATION))
        self.assertEqual(self._read(ours), catalogue(ACCOUNTS))

    def test_a_refusal_exits_non_zero_names_the_msgid_and_writes_nothing(self):
        base = self._write("base.po", catalogue(ACCOUNTS))
        ours_text = catalogue(entry("Cash accounts", "Konten"))
        ours = self._write("ours.po", ours_text)
        theirs = self._write("theirs.po", catalogue(entry("Cash accounts", "Geldkonten")))
        out = os.path.join(self.directory, "out.po")
        status, stderr = self._main(base, ours, theirs, "-o", out)
        self.assertEqual(status, 1)
        self.assertIn("'Cash accounts'", stderr)
        self.assertFalse(os.path.exists(out))
        self.assertEqual(self._read(ours), ours_text)

    def test_an_unreadable_catalogue_exits_two_naming_the_file(self):
        base = self._write("base.po", catalogue(ACCOUNTS))
        broken = self._write("broken.po", "nonsense\n")
        status, stderr = self._main(base, base, broken)
        self.assertEqual(status, 2)
        self.assertIn("broken.po", stderr)


class GitMergeDriverTests(unittest.TestCase):
    """The tool works as a git merge driver (`%O %A %B`) in a throwaway repository."""

    def setUp(self):
        self.directory = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.directory)
        # Drop the variables git sets for a hook, or git acts on the
        # repository whose hook runs this test (#1364).
        self.env = {name: value for name, value in os.environ.items() if name not in HOOK_GIT_VARIABLES}
        self.env.update(
            GIT_AUTHOR_NAME="Test",
            GIT_AUTHOR_EMAIL="test@example.invalid",
            GIT_COMMITTER_NAME="Test",
            GIT_COMMITTER_EMAIL="test@example.invalid",
            GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL=os.devnull,
        )

    def _git(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["git", *args], cwd=self.directory, env=self.env, capture_output=True, text=True, check=False
        )

    def _commit_catalogue(self, text: str, message: str) -> None:
        with open(os.path.join(self.directory, "de.po"), "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        self.assertEqual(self._git("add", "de.po").returncode, 0)
        self.assertEqual(self._git("commit", "-q", "-m", message).returncode, 0)

    def test_two_branches_adding_entries_merge_into_their_union(self):
        self._git("init", "-q", "-b", "main")
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "merge_gettext.py")
        self._git("config", "merge.gettext.name", "gettext catalogue merge")
        self._git("config", "merge.gettext.driver", f'"{sys.executable}" "{script}" %O %A %B')
        with open(os.path.join(self.directory, ".git", "info", "attributes"), "w", encoding="utf-8") as handle:
            handle.write("*.po merge=gettext\n")
        self._commit_catalogue(catalogue(ACCOUNTS), "base")
        self._git("checkout", "-q", "-b", "story")
        self._commit_catalogue(catalogue(ACCOUNTS, entry("Theirs", "Ihres")), "story")
        self._git("checkout", "-q", "main")
        self._commit_catalogue(catalogue(ACCOUNTS, entry("Ours", "Unseres")), "main")
        merged = self._git("merge", "-q", "--no-edit", "story")
        self.assertEqual(merged.returncode, 0, merged.stdout + merged.stderr)
        with open(os.path.join(self.directory, "de.po"), encoding="utf-8", newline="") as handle:
            self.assertEqual(
                handle.read(), catalogue(ACCOUNTS, entry("Ours", "Unseres"), entry("Theirs", "Ihres"))
            )


if __name__ == "__main__":
    unittest.main()
