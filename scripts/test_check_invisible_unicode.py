#!/usr/bin/env python3
"""Self-tests for scripts/check_invisible_unicode.py.

Run with::

    python3 -m unittest scripts.test_check_invisible_unicode
    # or
    python3 scripts/test_check_invisible_unicode.py

These tests exercise the scanner in isolation against temporary files and the
committed negative-test fixtures, without touching the repo-wide gate.
"""

from __future__ import annotations

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_invisible_unicode as scanner  # noqa: E402


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


class BinaryDetectionTests(unittest.TestCase):
    def test_nul_byte_file_is_skipped(self):
        handle = tempfile.NamedTemporaryFile(suffix=".bin", delete=False)
        handle.write(b"\x00\x01\x02\xff")
        handle.close()
        self.addCleanup(os.unlink, handle.name)
        self.assertIsNone(scanner.read_text(handle.name))


if __name__ == "__main__":
    unittest.main()
