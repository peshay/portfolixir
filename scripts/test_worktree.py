#!/usr/bin/env python3
"""Self-tests for scripts/worktree.sh.

Run with::

    python3 -B -m unittest discover --start-directory scripts --pattern "test_worktree.py"

The pre-commit hook `scripts-self-tests` runs them, with every other
``scripts/test_*.py``, in CI's pre-commit job.

Each test drives the script against a throwaway repository in a temporary
directory, with a fake ``deps`` and ``mcp-server/node_modules`` like the main
checkout's, and a fake ``mix`` on PATH, so no test compiles or touches a
database.
"""

from __future__ import annotations

import os
import shlex
import shutil
import stat
import subprocess
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "worktree.sh")

# The variables git sets for a hook. A test that runs git in a throwaway
# repository drops them, or git acts on the repository whose hook runs the
# test (#1364).
HOOK_GIT_VARIABLES = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR")

EXCLUDE_LINES = ("/deps", "/_build", "node_modules", "/mcp-server/node_modules")

MERGE_GETTEXT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "merge_gettext.py")

# The merge driver docs/development/guide.md ("Integrating gettext
# catalogues") registers, and the two attribute lines that route the
# catalogues to it.
GETTEXT_DRIVER = "python3 scripts/merge_gettext.py %O %A %B"
GETTEXT_ATTRIBUTES = ("priv/gettext/**/*.po merge=gettext", "priv/gettext/*.pot merge=gettext")

PO_HEADER = 'msgid ""\nmsgstr ""\n"Language: de\\n"\n'

FAKE_MIX = """#!/bin/sh
echo "$PWD DATABASE_NAME=$DATABASE_NAME MIX_ENV=$MIX_ENV mix $*" >> "$FAKE_MIX_LOG"
"""


class WorktreeHelperTests(unittest.TestCase):
    def setUp(self):
        self.directory = os.path.realpath(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.directory)
        self.main = os.path.join(self.directory, "main")
        os.makedirs(os.path.join(self.main, "mcp-server"))
        bin_directory = os.path.join(self.directory, "bin")
        os.makedirs(bin_directory)
        fake_mix = os.path.join(bin_directory, "mix")
        with open(fake_mix, "w", encoding="utf-8") as handle:
            handle.write(FAKE_MIX)
        os.chmod(fake_mix, os.stat(fake_mix).st_mode | stat.S_IXUSR)
        self.mix_log = os.path.join(self.directory, "mix.log")

        self.env = {name: value for name, value in os.environ.items() if name not in HOOK_GIT_VARIABLES}
        self.env.update(
            GIT_AUTHOR_NAME="Test",
            GIT_AUTHOR_EMAIL="test@example.invalid",
            GIT_COMMITTER_NAME="Test",
            GIT_COMMITTER_EMAIL="test@example.invalid",
            GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL=os.devnull,
            PATH=bin_directory + os.pathsep + os.environ.get("PATH", ""),
            FAKE_MIX_LOG=self.mix_log,
        )

        self._git("init", "-q", "-b", "main")
        # The repository's own ignore rules: directories only, as in the
        # real .gitignore, so they do not match a symlink.
        self._write(".gitignore", "/_build/\n/deps/\n/mcp-server/node_modules/\n")
        self._write("mcp-server/package.json", "{}\n")
        self._write("README.md", "base\n")
        self._git("add", "-A")
        self._git("commit", "-q", "-m", "base")
        self.base = self._git("rev-parse", "HEAD").strip()
        self._write("README.md", "main moved on\n")
        self._git("commit", "-q", "-am", "main moves on")
        self._write("deps/decimal/mix.exs", "# a dependency\n")
        self._write("mcp-server/node_modules/zod/package.json", "{}\n")

    def _write(self, relative: str, text: str) -> None:
        path = os.path.join(self.main, relative)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def _git(self, *args: str, cwd: str | None = None) -> str:
        completed = subprocess.run(
            ["git", *args], cwd=cwd or self.main, env=self.env, capture_output=True, text=True, check=True
        )
        return completed.stdout

    def _helper(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["bash", SCRIPT, *args], cwd=self.main, env=self.env, capture_output=True, text=True, check=False
        )

    def _add(self, name: str, *args: str) -> str:
        path = os.path.join(self.directory, name)
        completed = self._helper("add", path, *args)
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        return path

    def _exclude_lines(self) -> list[str]:
        with open(os.path.join(self.main, ".git", "info", "exclude"), encoding="utf-8") as handle:
            return handle.read().splitlines()

    def _attribute_lines(self) -> list[str]:
        path = os.path.join(self.main, ".git", "info", "attributes")
        if not os.path.exists(path):
            return []
        with open(path, encoding="utf-8") as handle:
            return handle.read().splitlines()

    def _config(self, *args: str, cwd: str | None = None) -> list[str]:
        completed = subprocess.run(
            ["git", "config", *args], cwd=cwd or self.main, env=self.env, capture_output=True, text=True, check=False
        )
        return completed.stdout.splitlines()

    def test_the_worktree_starts_at_the_given_base_on_the_given_branch(self):
        path = self._add("story", self.base, "agent/test/story")
        self.assertEqual(self._git("rev-parse", "HEAD", cwd=path).strip(), self.base)
        self.assertEqual(self._git("branch", "--show-current", cwd=path).strip(), "agent/test/story")

    def test_without_a_branch_the_worktree_is_detached_at_the_base(self):
        path = self._add("detached", self.base)
        self.assertEqual(self._git("rev-parse", "HEAD", cwd=path).strip(), self.base)
        self.assertEqual(self._git("branch", "--show-current", cwd=path).strip(), "")

    def test_a_missing_base_ref_is_refused_and_creates_nothing(self):
        path = os.path.join(self.directory, "nobase")
        completed = self._helper("add", path)
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("base", completed.stderr)
        self.assertFalse(os.path.exists(path))

    def test_an_unknown_base_ref_is_refused(self):
        completed = self._helper("add", os.path.join(self.directory, "bad"), "no-such-ref")
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("no-such-ref", completed.stderr)

    def test_deps_and_node_modules_are_links_to_the_main_checkout_and_build_is_not(self):
        path = self._add("story", self.base)
        for relative in ("deps", os.path.join("mcp-server", "node_modules")):
            with self.subTest(relative=relative):
                link = os.path.join(path, relative)
                self.assertTrue(os.path.islink(link))
                self.assertEqual(os.readlink(link), os.path.join(self.main, relative))
        self.assertFalse(os.path.lexists(os.path.join(path, "_build")))

    def test_the_links_leave_the_worktree_clean(self):
        path = self._add("story", self.base)
        os.makedirs(os.path.join(path, "_build", "test"))
        self.assertEqual(self._git("status", "--porcelain", "--untracked-files=all", cwd=path), "")

    def test_the_exclude_lines_are_written_once_however_often_it_runs(self):
        self._add("first", self.base)
        self._add("second", self.base, "agent/test/second")
        lines = self._exclude_lines()
        for line in EXCLUDE_LINES:
            with self.subTest(line=line):
                self.assertEqual(lines.count(line), 1)

    def test_it_prints_how_to_create_a_test_database_and_runs_nothing(self):
        completed = self._helper("add", os.path.join(self.directory, "story"), self.base)
        self.assertIn("MIX_ENV=test mix ecto.create", completed.stdout)
        self.assertIn("MIX_ENV=test mix ecto.migrate", completed.stdout)
        self.assertFalse(os.path.exists(self.mix_log))

    def test_the_printed_cd_line_is_a_valid_command_for_a_path_with_a_space(self):
        path = os.path.join(self.directory, "a story")
        completed = self._helper("add", path, self.base)
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        cd_lines = [line.strip() for line in completed.stdout.splitlines() if line.strip().startswith("cd ")]
        self.assertEqual(len(cd_lines), 1, completed.stdout)
        self.assertEqual(shlex.split(cd_lines[0]), ["cd", path])

    def test_db_creates_and_migrates_that_test_database_in_the_worktree(self):
        path = self._add("story", self.base, "--db", "portfolixir_test_7")
        with open(self.mix_log, encoding="utf-8") as handle:
            calls = handle.read().splitlines()
        self.assertEqual(
            calls,
            [
                f"{path} DATABASE_NAME=portfolixir_test_7 MIX_ENV=test mix ecto.create",
                f"{path} DATABASE_NAME=portfolixir_test_7 MIX_ENV=test mix ecto.migrate",
            ],
        )

    # Sprint 30 plan M3 (Sprint 29 retrospective, carry-forward 3): the
    # resolver existed since Sprint 22, but nothing registered it, so a
    # session wrote a second one.
    def test_the_gettext_merge_driver_is_registered_in_the_local_config(self):
        path = self._add("story", self.base)
        for cwd in (self.main, path):
            with self.subTest(cwd=cwd):
                driver = self._config("--local", "--get-all", "merge.gettext.driver", cwd=cwd)
                self.assertEqual(driver, [GETTEXT_DRIVER])
                self.assertEqual(len(self._config("--local", "--get-all", "merge.gettext.name", cwd=cwd)), 1)
        for relative in ("priv/gettext/de/LC_MESSAGES/default.po", "priv/gettext/default.pot"):
            with self.subTest(relative=relative):
                answer = self._git("check-attr", "merge", "--", relative, cwd=path).strip()
                self.assertEqual(answer, f"{relative}: merge: gettext")
        readme = self._git("check-attr", "merge", "--", "README.md", cwd=path).strip()
        self.assertEqual(readme, "README.md: merge: unspecified")
        # Local only: no committed .gitattributes, the worktree stays clean.
        self.assertFalse(os.path.lexists(os.path.join(path, ".gitattributes")))
        self.assertEqual(self._git("status", "--porcelain", "--untracked-files=all", cwd=path), "")

    def test_the_driver_and_the_attribute_lines_are_written_once_however_often_it_runs(self):
        self._add("first", self.base)
        self._add("second", self.base, "agent/test/second")
        self.assertEqual(self._config("--local", "--get-all", "merge.gettext.driver"), [GETTEXT_DRIVER])
        self.assertEqual(len(self._config("--local", "--get-all", "merge.gettext.name")), 1)
        lines = self._attribute_lines()
        for line in GETTEXT_ATTRIBUTES:
            with self.subTest(line=line):
                self.assertEqual(lines.count(line), 1)

    def test_a_driver_and_attributes_already_registered_are_kept(self):
        self._git("config", "merge.gettext.name", "the owner's name")
        self._git("config", "merge.gettext.driver", "python3 scripts/merge_gettext.py %O %A %B -o %A")
        attributes = os.path.join(self.main, ".git", "info", "attributes")
        with open(attributes, "w", encoding="utf-8") as handle:
            # The last line without its final newline, as a hand edit leaves it.
            handle.write("*.png binary\n" + GETTEXT_ATTRIBUTES[1])
        self._add("story", self.base)
        self.assertEqual(self._config("--local", "--get-all", "merge.gettext.name"), ["the owner's name"])
        self.assertEqual(
            self._config("--local", "--get-all", "merge.gettext.driver"),
            ["python3 scripts/merge_gettext.py %O %A %B -o %A"],
        )
        self.assertEqual(self._attribute_lines(), ["*.png binary", GETTEXT_ATTRIBUTES[1], GETTEXT_ATTRIBUTES[0]])

    def test_a_cherry_pick_in_a_new_worktree_merges_two_stories_catalogues(self):
        # Two stories append a msgid each at the catalogue's end: a plain
        # text merge conflicts there; the registered driver unites them.
        catalogue = "priv/gettext/de/LC_MESSAGES/default.po"
        os.makedirs(os.path.join(self.main, "scripts"), exist_ok=True)
        shutil.copy(MERGE_GETTEXT, os.path.join(self.main, "scripts", "merge_gettext.py"))
        self._write(catalogue, PO_HEADER + '\nmsgid "Base"\nmsgstr "Basis"\n')
        self._git("add", "-A")
        self._git("commit", "-q", "-m", "catalogue")
        start = self._git("rev-parse", "HEAD").strip()
        self._write(catalogue, PO_HEADER + '\nmsgid "Base"\nmsgstr "Basis"\n\nmsgid "Theirs"\nmsgstr "Ihres"\n')
        self._git("commit", "-q", "-am", "theirs")
        theirs = self._git("rev-parse", "HEAD").strip()

        path = self._add("story", start, "agent/test/story")
        with open(os.path.join(path, catalogue), "a", encoding="utf-8") as handle:
            handle.write('\nmsgid "Ours"\nmsgstr "Unseres"\n')
        self._git("commit", "-q", "-am", "ours", cwd=path)

        completed = subprocess.run(
            ["git", "cherry-pick", theirs], cwd=path, env=self.env, capture_output=True, text=True, check=False
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        with open(os.path.join(path, catalogue), encoding="utf-8") as handle:
            merged = handle.read()
        self.assertIn('msgid "Ours"', merged)
        self.assertIn('msgid "Theirs"', merged)
        self.assertNotIn("<<<<<<<", merged)


if __name__ == "__main__":
    unittest.main()
