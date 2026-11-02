#!/usr/bin/env python3
"""Self-tests for scripts/check_no_symlinks.py.

Run with::

    python3 -B -m unittest discover --start-directory scripts --pattern "test_check_no_symlinks.py"

The pre-commit hook `scripts-self-tests` runs them, with every other
``scripts/test_*.py``, in CI's pre-commit job. Each test runs the check in a
throwaway repository.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "check_no_symlinks.py")

# The variables git sets for a hook. A test that runs git in a throwaway
# repository drops them, or git acts on the repository whose hook runs the
# test (#1364).
HOOK_GIT_VARIABLES = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR")


class NoSymlinkCheckTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.directory)
        self.repository = os.path.join(self.directory, "repository")
        os.makedirs(os.path.join(self.repository, "lib"))
        self.env = {name: value for name, value in os.environ.items() if name not in HOOK_GIT_VARIABLES}
        self.env.update(
            GIT_AUTHOR_NAME="Test",
            GIT_AUTHOR_EMAIL="test@example.invalid",
            GIT_COMMITTER_NAME="Test",
            GIT_COMMITTER_EMAIL="test@example.invalid",
            GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL=os.devnull,
        )
        self._git("init", "-q", "-b", "main")
        with open(os.path.join(self.repository, "lib", "app.ex"), "w", encoding="utf-8") as handle:
            handle.write("defmodule App do\nend\n")
        self.shared = os.path.join(self.directory, "shared-deps")
        os.makedirs(self.shared)

    def _git(self, *args: str) -> None:
        subprocess.run(["git", *args], cwd=self.repository, env=self.env, capture_output=True, check=True)

    def _check(self) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, "-B", SCRIPT],
            cwd=self.repository,
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_a_repository_without_symlinks_passes(self):
        self._git("add", "-A")
        completed = self._check()
        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_a_staged_symlink_is_refused_by_name(self):
        os.symlink(self.shared, os.path.join(self.repository, "deps"))
        os.symlink("app.ex", os.path.join(self.repository, "lib", "alias.ex"))
        self._git("add", "-A")
        completed = self._check()
        self.assertEqual(completed.returncode, 1)
        self.assertIn("deps", completed.stderr)
        self.assertIn("lib/alias.ex", completed.stderr)
        self.assertNotIn("lib/app.ex", completed.stderr)

    def test_a_committed_symlink_is_refused(self):
        os.symlink(self.shared, os.path.join(self.repository, "deps"))
        self._git("add", "-A")
        self._git("commit", "-q", "-m", "tracks a symlink")
        self.assertEqual(self._check().returncode, 1)

    def test_an_untracked_or_ignored_symlink_passes(self):
        with open(os.path.join(self.repository, ".gitignore"), "w", encoding="utf-8") as handle:
            handle.write("/deps\n")
        os.symlink(self.shared, os.path.join(self.repository, "deps"))
        os.symlink("app.ex", os.path.join(self.repository, "lib", "untracked.ex"))
        self._git("add", ".gitignore", "lib/app.ex")
        completed = self._check()
        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_a_path_with_spaces_and_unicode_is_named_exactly(self):
        os.symlink("app.ex", os.path.join(self.repository, "lib", "Übersicht link.ex"))
        self._git("add", "-A")
        completed = self._check()
        self.assertEqual(completed.returncode, 1)
        self.assertIn("lib/Übersicht link.ex", completed.stderr)


if __name__ == "__main__":
    unittest.main()
