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


if __name__ == "__main__":
    unittest.main()
