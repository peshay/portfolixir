#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# ///
"""Unit tests for init-sanctum.py pure functions. Standard library only."""

import importlib.util
import tempfile
import unittest
from pathlib import Path

_MODULE_PATH = Path(__file__).resolve().parent.parent / "init-sanctum.py"
_spec = importlib.util.spec_from_file_location("init_sanctum", _MODULE_PATH)
init_sanctum = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(init_sanctum)


class SubstituteVarsTest(unittest.TestCase):
    def test_replaces_known_placeholders(self):
        out = init_sanctum.substitute_vars(
            "Hi {user_name}, born {birth_date}.",
            {"user_name": "Andi", "birth_date": "2026-06-20"},
        )
        self.assertEqual(out, "Hi Andi, born 2026-06-20.")

    def test_leaves_unknown_placeholders_untouched(self):
        out = init_sanctum.substitute_vars("Keep {unknown}.", {"user_name": "Andi"})
        self.assertEqual(out, "Keep {unknown}.")


class ParseFrontmatterTest(unittest.TestCase):
    def test_extracts_name_and_code(self):
        with tempfile.TemporaryDirectory() as tmp:
            md = Path(tmp) / "cap.md"
            md.write_text("---\nname: Flow-Critique\ncode: FC\n---\n\n# Body\n")
            meta = init_sanctum.parse_frontmatter(md)
        self.assertEqual(meta["name"], "Flow-Critique")
        self.assertEqual(meta["code"], "FC")

    def test_returns_empty_without_frontmatter(self):
        with tempfile.TemporaryDirectory() as tmp:
            md = Path(tmp) / "plain.md"
            md.write_text("# No frontmatter here\n")
            self.assertEqual(init_sanctum.parse_frontmatter(md), {})


class ParseYamlConfigTest(unittest.TestCase):
    def test_reads_scalars_and_skips_comments(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / "config.yaml"
            cfg.write_text("# comment\nuser_name: Andi\ncommunication_language: Deutsch\n")
            parsed = init_sanctum.parse_yaml_config(cfg)
        self.assertEqual(parsed["user_name"], "Andi")
        self.assertEqual(parsed["communication_language"], "Deutsch")

    def test_missing_file_returns_empty(self):
        self.assertEqual(init_sanctum.parse_yaml_config(Path("/no/such/file.yaml")), {})


class GenerateCapabilitiesTest(unittest.TestCase):
    def _caps(self):
        return [
            {"code": "FC", "name": "Flow-Critique", "description": "Review.", "source": "./references/flow-critique.md"},
            {"code": "DL", "name": "Design-Language", "description": "Capture.", "source": "./references/design-language.md"},
        ]

    def test_lists_built_in_capabilities(self):
        out = init_sanctum.generate_capabilities_md(self._caps(), evolvable=False)
        self.assertIn("| [FC] | Flow-Critique | Review. |", out)
        self.assertIn("| [DL] | Design-Language | Capture. |", out)
        self.assertIn("## Tools", out)

    def test_non_evolvable_omits_learned_section(self):
        out = init_sanctum.generate_capabilities_md(self._caps(), evolvable=False)
        self.assertNotIn("## Learned", out)

    def test_evolvable_includes_learned_section(self):
        out = init_sanctum.generate_capabilities_md(self._caps(), evolvable=True)
        self.assertIn("## Learned", out)


if __name__ == "__main__":
    unittest.main()
