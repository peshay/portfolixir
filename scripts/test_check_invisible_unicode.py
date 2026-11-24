#!/usr/bin/env python3
"""Self-tests for scripts/check_invisible_unicode.py.

Run with::

    python3 -m unittest scripts.test_check_invisible_unicode
    # or
    python3 scripts/test_check_invisible_unicode.py

The pre-commit hook `scripts-self-tests` runs them, with every other
``scripts/test_*.py``, in CI's pre-commit job.

These tests exercise the scanner in isolation against temporary files and the
committed negative-test fixtures, without touching the repo-wide gate.
"""

from __future__ import annotations

import collections
import contextlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_invisible_unicode as scanner  # noqa: E402


# The variables git sets for a hook. A test that runs git in a throwaway
# repository drops them, or git acts on the repository whose hook runs the
# test (#1364).
HOOK_GIT_VARIABLES = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR")


def scan(text: str, path: str = "sample.txt", allowlist=None):
    return scanner.scan_text(path, text, allowlist or [])


class ClassifyTests(unittest.TestCase):
    def test_flags_bidi_override(self):
        self.assertIsNotNone(scanner.classify(0x202E))

    def test_flags_zero_width_space(self):
        self.assertIsNotNone(scanner.classify(0x200B))

    def test_flags_tag_character(self):
        self.assertIsNotNone(scanner.classify(0xE0041))

    def test_allows_plain_text_and_whitespace(self):
        for cp in (ord("a"), ord("Z"), ord("9"), 0x09, 0x0A, 0x0D, 0x20):
            self.assertIsNone(scanner.classify(cp))

    def test_allows_emoji_and_accents(self):
        for ch in ("é", "你", "🚀"):
            self.assertIsNone(scanner.classify(ord(ch)))

    # Both ends of every range of default-ignorable code points the gate
    # writes out: none of them belongs to the general category Cf in every
    # Unicode version, so the category alone does not name them (N-84).
    DEFAULT_IGNORABLE_RANGE_ENDS = (
        0x00AD,
        0x034F,
        0x061C,
        0x115F,
        0x1160,
        0x17B4,
        0x17B5,
        0x180B,
        0x180F,
        0x200B,
        0x200F,
        0x2060,
        0x2065,
        0x206F,
        0x3164,
        0xFE00,
        0xFE0E,
        0xFE0F,
        0xFFA0,
        0xFFF0,
        0xFFF8,
        0xFFFB,
        0x1BCA0,
        0x1BCA3,
        0x1D173,
        0x1D17A,
        0xE0000,
        0xE007F,
        0xE0080,
        0xE00FF,
        0xE0100,
        0xE01EF,
        0xE01F0,
        0xE0FFF,
    )

    def test_flags_every_default_ignorable_code_point(self):
        for cp in self.DEFAULT_IGNORABLE_RANGE_ENDS:
            with self.subTest(codepoint=f"U+{cp:04X}"):
                self.assertIsNotNone(scanner.classify(cp))

    def test_the_neighbours_of_the_ranges_stay_allowed(self):
        for cp in (0x00AC, 0x00AE, 0x1161, 0x3163, 0x3165, 0xFE10, 0xFFA1, 0xFFFC, 0xFFFD, 0xE1000):
            with self.subTest(codepoint=f"U+{cp:04X}"):
                self.assertIsNone(scanner.classify(cp))


class ScanTextTests(unittest.TestCase):
    def test_clean_text_has_no_violations(self):
        self.assertEqual(scan("normal ascii\nwith tabs\tand é unicode\n"), [])

    # NOTE: forbidden characters are constructed with chr() rather than written
    # as literals so that this test source file itself stays clean and does not
    # trip the repo-wide gate.
    RLO = chr(0x202E)  # RIGHT-TO-LEFT OVERRIDE
    ZWSP = chr(0x200B)  # ZERO WIDTH SPACE
    FEFF = chr(0xFEFF)  # ZERO WIDTH NO-BREAK SPACE / BOM

    def test_detects_bidi_override_with_position(self):
        violations = scan("ab" + self.RLO + "cd")
        self.assertEqual(len(violations), 1)
        self.assertEqual(violations[0].codepoint, 0x202E)
        self.assertEqual(violations[0].line, 1)
        self.assertEqual(violations[0].col, 3)

    def test_detects_zero_width_space(self):
        violations = scan("a" + self.ZWSP + "b")
        self.assertEqual(len(violations), 1)
        self.assertEqual(violations[0].codepoint, 0x200B)

    def test_leading_bom_is_allowed(self):
        self.assertEqual(scan(self.FEFF + "hello"), [])

    def test_non_leading_bom_is_flagged(self):
        violations = scan("hello" + self.FEFF + "world")
        self.assertEqual(len(violations), 1)
        self.assertEqual(violations[0].codepoint, 0xFEFF)

    def test_line_and_column_tracking(self):
        violations = scan("line one\nline" + self.RLO + "two")
        self.assertEqual(len(violations), 1)
        self.assertEqual(violations[0].line, 2)
        self.assertEqual(violations[0].col, 5)

    def test_allowlist_suppresses_match(self):
        entry = scanner.AllowlistEntry(glob="sample.txt", codepoint=0x202E, reason="x")
        self.assertEqual(scan("a" + self.RLO + "b", allowlist=[entry]), [])

    def test_allowlist_does_not_suppress_other_paths(self):
        entry = scanner.AllowlistEntry(glob="other.txt", codepoint=0x202E, reason="x")
        self.assertEqual(len(scan("a" + self.RLO + "b", allowlist=[entry])), 1)

    WARNING_SIGN = chr(0x26A0)
    VS15 = chr(0xFE0E)  # VARIATION SELECTOR-15, text presentation
    VS16 = chr(0xFE0F)  # VARIATION SELECTOR-16, emoji presentation

    def test_an_emoji_presentation_selector_after_a_pictograph_passes(self):
        for base in (0x26A0, 0x2139, 0x23F8, 0x2702, 0x00A9, 0x1F3D7, 0x1F6E0):
            with self.subTest(base=f"U+{base:04X}"):
                self.assertEqual(scan("note " + chr(base) + self.VS16 + " text\n"), [])

    def test_a_variation_selector_anywhere_else_is_flagged(self):
        cases = {
            "after a letter": "a" + self.VS16 + "b",
            "after a digit": "1" + self.VS16,
            "first in the file": self.VS16 + "a",
            "first on a line": self.WARNING_SIGN + "\n" + self.VS16,
            "after a space": self.WARNING_SIGN + " " + self.VS16,
            "text presentation": self.WARNING_SIGN + self.VS15,
            "another selector": self.WARNING_SIGN + chr(0xFE00),
            "an ideographic selector": chr(0x845B) + chr(0xE0100),
        }
        for label, text in cases.items():
            with self.subTest(label):
                violations = scan(text)
                self.assertEqual(len(violations), 1)
                self.assertIn(violations[0].codepoint, (0xFE0F, 0xFE0E, 0xFE00, 0xE0100))

    def test_a_run_of_variation_selectors_is_flagged_selector_by_selector(self):
        # One selector per byte: sixteen in U+FE00..U+FE0F, 240 in
        # U+E0100..U+E01EF.
        run = "".join(chr(0xFE00 + byte) if byte < 16 else chr(0xE0100 + byte - 16) for byte in range(256))
        for prefix in ("word", self.WARNING_SIGN, self.WARNING_SIGN + self.VS16):
            with self.subTest(prefix=ascii(prefix)):
                expected = len(run) + prefix.count(self.VS16)
                self.assertEqual(len(scan(prefix + run + " end\n")), expected)


class SharedCasesTests(unittest.TestCase):
    """The gate refuses every character the application's writers refuse.

    ``mcp-server/test/fixtures/invisible-text.json`` holds the cases
    ``Portfolixir.Input.Text`` and the MCP companion's escape are pinned to:
    an input, and the same text with every refused character spelled
    ``[U+XXXX]``. The gate reports each of those characters. It may report
    more: it allows no zero-width joiner, and a variation selector only as the
    emoji presentation selector after a pictograph.
    """

    FIXTURE = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "mcp-server",
        "test",
        "fixtures",
        "invisible-text.json",
    )

    SPELLED = re.compile(r"\[U\+([0-9A-F]{4,6})\]")

    def _spelled(self, text: str) -> collections.Counter:
        return collections.Counter(int(match, 16) for match in self.SPELLED.findall(text))

    def test_every_character_the_application_refuses_is_reported(self):
        with open(self.FIXTURE, encoding="utf-8") as handle:
            cases = json.load(handle)["cases"]

        refused_cases = 0
        for case in cases:
            refused = self._spelled(case["escaped"]) - self._spelled(case["input"])
            self.assertEqual(sum(refused.values()), case["count"], ascii(case["input"]))
            # A line of its own: the input does not open the file, where a
            # byte-order mark is allowed.
            reported = collections.Counter(v.codepoint for v in scan("case\n" + case["input"] + "\n"))
            with self.subTest(input=ascii(case["input"])):
                self.assertEqual(refused - reported, collections.Counter())
            refused_cases += 1 if refused else 0

        self.assertGreaterEqual(refused_cases, 20)


class AllowlistParseTests(unittest.TestCase):
    def _write(self, content: str) -> str:
        handle = tempfile.NamedTemporaryFile(
            "w", suffix=".txt", delete=False, encoding="utf-8"
        )
        handle.write(content)
        handle.close()
        self.addCleanup(os.unlink, handle.name)
        return handle.name

    def test_parses_valid_entry(self):
        path = self._write("docs/*.md U+200B # legit reason\n")
        entries = scanner.parse_allowlist(path)
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0].codepoint, 0x200B)
        self.assertEqual(entries[0].reason, "legit reason")

    def test_rejects_entry_without_reason(self):
        path = self._write("docs/*.md U+200B\n")
        with self.assertRaises(ValueError):
            scanner.parse_allowlist(path)

    def test_rejects_empty_reason(self):
        path = self._write("docs/*.md U+200B #\n")
        with self.assertRaises(ValueError):
            scanner.parse_allowlist(path)

    def test_rejects_missing_codepoint(self):
        path = self._write("docs/*.md # reason\n")
        with self.assertRaises(ValueError):
            scanner.parse_allowlist(path)

    def test_ignores_comments_and_blank_lines(self):
        path = self._write("# header\n\ndocs/*.md U+200B # ok\n")
        self.assertEqual(len(scanner.parse_allowlist(path)), 1)


class FixtureTests(unittest.TestCase):
    """The committed fixtures must actually contain the forbidden chars."""

    def _fixture(self, name: str) -> str:
        return os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "test",
            "fixtures",
            "unicode",
            name,
        )

    def test_bidi_fixture_is_flagged_without_allowlist(self):
        path = self._fixture("bidi_sample.txt")
        text = scanner.read_text(path)
        self.assertIsNotNone(text)
        violations = scanner.scan_text(path, text, [])
        self.assertTrue(any(v.codepoint == 0x202E for v in violations))

    def test_zero_width_fixture_is_flagged_without_allowlist(self):
        path = self._fixture("zero_width_sample.txt")
        text = scanner.read_text(path)
        self.assertIsNotNone(text)
        violations = scanner.scan_text(path, text, [])
        self.assertTrue(any(v.codepoint == 0x200B for v in violations))


class ScratchRepositoryCase(unittest.TestCase):
    """Runs the gate's ``main`` in a throwaway directory or repository."""

    def setUp(self):
        # Inside a hook, git and the scanner's own `git check-attr` would
        # otherwise act on the repository whose hook runs the test (#1364).
        saved = {name: os.environ.pop(name) for name in HOOK_GIT_VARIABLES if name in os.environ}
        self.addCleanup(os.environ.update, saved)

    def _repo(self) -> str:
        directory = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, directory)
        env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
        subprocess.run(["git", "init", "-q", directory], check=True, env=env)
        return directory

    def _write(self, directory: str, name: str, data: bytes) -> str:
        path = os.path.join(directory, name)
        with open(path, "wb") as handle:
            handle.write(data)
        return name

    def _track(self, directory: str) -> None:
        env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
        subprocess.run(["git", "add", "--all"], cwd=directory, check=True, env=env)

    def _run(self, directory: str, names: list[str]) -> tuple[int, str]:
        previous = os.getcwd()
        os.chdir(directory)
        try:
            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                status = scanner.main(["check_invisible_unicode.py", *names])
        finally:
            os.chdir(previous)
        return status, stderr.getvalue()


class BinaryDetectionTests(ScratchRepositoryCase):
    """Only a file the binary list or .gitattributes names is skipped (H64).

    Every other file that holds a NUL or does not decode as UTF-8 is reported,
    and the characters around the offending byte are still scanned.
    """

    TAG_A = chr(0xE0041)  # TAG LATIN CAPITAL LETTER A
    RLO = chr(0x202E)  # RIGHT-TO-LEFT OVERRIDE

    def test_nul_byte_in_a_text_file_is_a_violation(self):
        directory = self._repo()
        data = ("# rules" + self.TAG_A + "\n").encode("utf-8") + b"\x00\n"
        name = self._write(directory, "notes.md", data)
        status, output = self._run(directory, [name])
        self.assertEqual(status, 1)
        self.assertIn("notes.md:2:1: not valid UTF-8 text", output)
        self.assertIn("U+E0041", output)

    def test_invalid_utf8_in_a_text_file_is_a_violation(self):
        directory = self._repo()
        data = ("a" + self.RLO + "b\n// ").encode("utf-8") + b"\xff\n"
        name = self._write(directory, "trojan.ts", data)
        status, output = self._run(directory, [name])
        self.assertEqual(status, 1)
        self.assertIn("trojan.ts:2:4: not valid UTF-8 text", output)
        self.assertIn("trojan.ts:1:2: U+202E", output)

    def test_a_listed_binary_extension_is_skipped(self):
        directory = self._repo()
        name = self._write(directory, "logo.png", b"\x89PNG\r\n\x1a\n\x00\xff")
        self.assertEqual(self._run(directory, [name]), (0, ""))

    def test_a_file_gitattributes_marks_binary_is_skipped(self):
        directory = self._repo()
        self._write(directory, ".gitattributes", b"*.dat binary\n*.raw -text\n")
        dat = self._write(directory, "blob.dat", b"\x00\x01\xff")
        raw = self._write(directory, "blob.raw", b"\xff\xfe")
        self.assertEqual(self._run(directory, [dat, raw]), (0, ""))

    def test_gitattributes_skips_nothing_it_does_not_name(self):
        directory = self._repo()
        self._write(directory, ".gitattributes", b"*.dat binary\n")
        name = self._write(directory, "notes.txt", b"text\x00")
        status, output = self._run(directory, [name])
        self.assertEqual(status, 1)
        self.assertIn("notes.txt:1:5: not valid UTF-8 text", output)

    def test_outside_a_git_repository_only_the_list_skips(self):
        directory = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, directory)
        name = self._write(directory, "notes.txt", b"\xff")
        status, output = self._run(directory, [name])
        self.assertEqual(status, 1)
        self.assertIn("notes.txt:1:1: not valid UTF-8 text", output)


class PathNameTests(ScratchRepositoryCase):
    """A file's name is read like its content, and no entry exempts it (N-84)."""

    RLO = chr(0x202E)  # RIGHT-TO-LEFT OVERRIDE
    ZWSP = chr(0x200B)  # ZERO WIDTH SPACE
    FILLER = chr(0x3164)  # HANGUL FILLER
    VS16 = chr(0xFE0F)  # VARIATION SELECTOR-16

    def _tracked(self, name: str, data: bytes = b"plain ASCII content\n") -> tuple[int, str]:
        directory = self._repo()
        os.makedirs(os.path.dirname(os.path.join(directory, name)), exist_ok=True)
        self._write(directory, name, data)
        self._track(directory)
        return self._run(directory, [])

    def test_a_tracked_file_name_with_a_forbidden_character_is_refused(self):
        status, output = self._tracked("notes" + self.RLO + "txt.sh" + self.ZWSP + ".md")
        self.assertEqual(status, 1)
        self.assertIn("notes[U+202E]txt.sh[U+200B].md: file name, character 6: U+202E", output)
        self.assertIn("notes[U+202E]txt.sh[U+200B].md: file name, character 13: U+200B", output)
        # The report spells the characters; it does not print them.
        self.assertNotIn(self.RLO, output)
        self.assertNotIn(self.ZWSP, output)

    def test_a_default_ignorable_character_in_a_name_is_refused(self):
        for name in ("Config" + self.FILLER + ".md", "warning" + chr(0x26A0) + self.VS16 + ".md"):
            with self.subTest(name=ascii(name)):
                status, output = self._tracked(name)
                self.assertEqual(status, 1)
                self.assertIn("file name, character", output)

    def test_a_directory_name_is_read(self):
        status, output = self._tracked("docs" + self.ZWSP + "/readme.md")
        self.assertEqual(status, 1)
        self.assertIn("docs[U+200B]/readme.md: file name, character 5: U+200B", output)

    def test_the_name_of_a_file_whose_content_is_skipped_is_read(self):
        status, output = self._tracked("logo" + self.RLO + ".png", b"\x89PNG\r\n\x1a\n\x00\xff")
        self.assertEqual(status, 1)
        self.assertIn("logo[U+202E].png: file name, character 5: U+202E", output)

    def test_a_path_given_on_the_command_line_is_read(self):
        directory = self._repo()
        name = self._write(directory, "notes" + self.RLO + ".md", b"plain ASCII content\n")
        status, output = self._run(directory, [name])
        self.assertEqual(status, 1)
        self.assertIn("notes[U+202E].md: file name, character 6: U+202E", output)

    def test_no_allowlist_entry_exempts_a_name(self):
        directory = self._repo()
        self._write(directory, ".unicode-allowlist.txt", b"* U+202E # synthetic: every path\n")
        self._write(directory, "notes" + self.RLO + ".md", ("a" + self.RLO + "b\n").encode("utf-8"))
        self._track(directory)
        status, output = self._run(directory, [])
        self.assertEqual(status, 1)
        self.assertIn("file name, character 6: U+202E", output)
        # The entry exempts the character in the content, as before.
        self.assertNotIn(".md:1:2:", output)

    def test_a_visible_name_passes(self):
        for name in ("\u00dcbersicht.md", "docs/\u682a\u5f0f.md", "a b/c-d_e.f.txt"):
            with self.subTest(name=ascii(name)):
                self.assertEqual(self._tracked(name), (0, ""))


class ListingTests(ScratchRepositoryCase):
    """Without file names the gate scans what git tracks, or fails (N-84)."""

    def test_a_repository_without_tracked_files_passes(self):
        self.assertEqual(self._run(self._repo(), []), (0, ""))

    def test_a_listing_that_fails_is_an_error(self):
        directory = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, directory)
        with open(os.path.join(directory, "notes.md"), "w", encoding="utf-8") as handle:
            handle.write("a" + chr(0x202E) + "b\n")
        status, output = self._run(directory, [])
        self.assertEqual(status, 1)
        self.assertIn("cannot list the tracked files", output)

    def test_a_missing_git_is_an_error(self):
        directory = self._repo()
        with mock.patch.object(scanner.subprocess, "run", side_effect=FileNotFoundError("git")):
            status, output = self._run(directory, [])
        self.assertEqual(status, 1)
        self.assertIn("cannot list the tracked files", output)

    def test_a_tracked_name_that_is_not_utf8_is_an_error(self):
        directory = self._repo()
        listing = subprocess.CompletedProcess(["git", "ls-files", "-z"], 0, b"caf\xe9.txt\0", b"")
        with mock.patch.object(scanner.subprocess, "run", return_value=listing):
            status, output = self._run(directory, [])
        self.assertEqual(status, 1)
        self.assertIn("cannot list the tracked files", output)


class HookEnvironmentTests(unittest.TestCase):
    """The tests leave the repository whose hook runs them alone (#1364).

    A hook in a linked worktree runs with GIT_DIR pointing at
    ``.git/worktrees/<name>`` and GIT_INDEX_FILE beside it. A ``git init``
    that inherits them re-initialises that repository instead of the
    throwaway one, and writes ``core.bare`` into the shared ``.git/config``
    (Sprint 22 retrospective).
    """

    def _git(self, *args: str, cwd: str, env: dict | None = None) -> str:
        return subprocess.run(
            ["git", *args], cwd=cwd, env=env, check=True, capture_output=True, text=True
        ).stdout

    def test_running_inside_a_linked_worktree_hook_leaves_core_bare_alone(self):
        root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, root)
        base = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
        for name in HOOK_GIT_VARIABLES:
            base.pop(name, None)
        main = os.path.join(root, "main")
        self._git("init", "-q", main, cwd=root, env=base)
        self._git(
            "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
            "commit", "-q", "--allow-empty", "-m", "base", cwd=main, env=base,
        )
        linked = os.path.join(root, "linked")
        self._git("worktree", "add", "-q", linked, cwd=main, env=base)
        before = self._git("config", "--list", "--local", cwd=main, env=base)

        git_dir = os.path.join(main, ".git", "worktrees", "linked")
        hook_env = dict(
            base,
            GIT_DIR=git_dir,
            GIT_INDEX_FILE=os.path.join(git_dir, "index"),
            GIT_WORK_TREE=linked,
            GIT_COMMON_DIR=os.path.join(main, ".git"),
        )
        result = subprocess.run(
            [
                sys.executable, "-B", "-m", "unittest",
                "test_check_invisible_unicode.BinaryDetectionTests",
            ],
            cwd=os.path.dirname(os.path.abspath(__file__)),
            env=hook_env,
            capture_output=True,
            text=True,
        )

        after = self._git("config", "--list", "--local", cwd=main, env=base)
        self.assertNotIn("core.bare=true", after)
        self.assertEqual(after, before)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
