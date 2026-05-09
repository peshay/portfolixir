#!/usr/bin/env python3
"""Focused regression tests for public_artifact_guard commit metadata scanning."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import public_artifact_guard


COMMIT = "abcdef1234567890"


class CommitMetadataScanTest(unittest.TestCase):
    def test_whitespace_prefixed_private_metadata_keys_are_blocked(self) -> None:
        cases = [
            " AI-Agent: hidden",
            "\tAI-Agent: hidden",
            " Runtime: hidden",
            "\tWorkspace: secret",
            " Host: hidden",
            "\tPath: secret",
            " Runtime-Model: hidden",
            "\tReview-Id: secret",
            " Worker-Host: hidden",
            "\tWorker-Runtime: hidden",
        ]

        for body in cases:
            with self.subTest(body=body):
                violations = public_artifact_guard.check_commit_metadata_text(COMMIT, body)
                self.assertTrue(violations)

    def test_whitespace_prefixed_allowed_worker_footers_pass(self) -> None:
        body = "\n".join(
            [
                " Worker-Model: codex/gpt-5.3-codex-spark",
                "\tWorker-Thinking: high",
            ]
        )

        self.assertEqual(public_artifact_guard.check_commit_metadata_text(COMMIT, body), [])

    def test_normal_worker_footer_regressions_still_apply(self) -> None:
        self.assertEqual(
            public_artifact_guard.check_commit_metadata_text(
                COMMIT,
                "Worker-Model: codex/gpt-5.3-codex-spark\nWorker-Thinking: high",
            ),
            [],
        )

        violations = public_artifact_guard.check_commit_metadata_text(
            COMMIT,
            " Worker-Model: openai-codex/gpt-5.4-mini",
        )
        self.assertIn("Worker-Model cannot use orchestrator model", "\n".join(violations))

    def test_private_board_and_card_identifiers_are_blocked_in_commit_metadata(self) -> None:
        body = "cardId: 12345\nboardId=abcde\nprojectManagerId: pm-1"
        violations = public_artifact_guard.check_commit_metadata_text(COMMIT, body)
        joined = "\n".join(violations)
        self.assertIn("private board/object identifier leak", joined)

    def test_trace_metadata_markers_are_blocked_in_commit_metadata(self) -> None:
        body = "[Subagent Context]\nRequester session: agent:monkey:main\nRuntime: agent=monkey"
        violations = public_artifact_guard.check_commit_metadata_text(COMMIT, body)
        joined = "\n".join(violations)
        self.assertIn("subagent transcript marker leak", joined)
        self.assertIn("requester session metadata leak", joined)
        self.assertIn("runtime trace metadata leak", joined)


class TextArtifactScanTest(unittest.TestCase):
    def test_text_artifact_blocks_trace_and_private_object_metadata(self) -> None:
        text = "PR body\ncardId: 123\nRequester session: agent:monkey:main"
        violations = public_artifact_guard.check_text_artifact("pr-body", text)
        joined = "\n".join(violations)
        self.assertIn("private board/object identifier leak", joined)
        self.assertIn("requester session metadata leak", joined)

    def test_text_artifact_blocks_commit_metadata_markers(self) -> None:
        text = "PR body\nAI-Agent: internal\nRuntime-Model: codex/gpt-5.3-codex"
        violations = public_artifact_guard.check_text_artifact("pr-body", text)
        joined = "\n".join(violations)
        self.assertIn("internal agent metadata footer", joined)
        self.assertIn("private runtime metadata footer", joined)

    def test_text_artifact_blocks_escaped_newline_markers(self) -> None:
        text = "Heading\\nBody that should have used real line breaks"
        violations = public_artifact_guard.check_text_artifact("pr-body", text)
        self.assertIn("literal escaped newline", "\n".join(violations))

    def test_text_artifact_blocks_extreme_average_line_length(self) -> None:
        text = "This public artifact is an unreadable blob. " * 20
        violations = public_artifact_guard.check_text_artifact("pr-body", text)
        self.assertIn("average line length", "\n".join(violations))

    def test_text_artifact_allows_long_url_lines(self) -> None:
        text = "https://example.com/" + "a" * 260
        self.assertEqual(public_artifact_guard.check_text_artifact("pr-body", text), [])

    def test_text_artifact_blocks_local_user_paths(self) -> None:
        text = "Prototype was read from /Users/example/Downloads/archive.zip"
        violations = public_artifact_guard.check_text_artifact("pr-body", text)
        self.assertIn("local user path leak", "\n".join(violations))

    def test_text_artifact_accepts_sanitized_text(self) -> None:
        text = "Story: PFX-DEV-004\nSummary: harden metadata leak guard"
        self.assertEqual(public_artifact_guard.check_text_artifact("pr-body", text), [])


if __name__ == "__main__":
    unittest.main()
