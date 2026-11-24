#!/usr/bin/env python3
"""Self-tests for scripts/check-commit-authorship.sh.

Run with::

    python3 -B -m unittest discover --start-directory scripts --pattern "test_check_commit_authorship.py"

The pre-commit hook `scripts-self-tests` runs them, with every other
``scripts/test_*.py``, in CI's pre-commit job.

Each test drives the script against a throwaway repository in a temporary
directory, with an allowlist of its own that holds one synthetic address. No
identity of this repository is read.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "check-commit-authorship.sh")

# The variables git sets for a hook. A test that runs git in a throwaway
# repository drops them, or git acts on the repository whose hook runs the
# test (#1364).
HOOK_GIT_VARIABLES = (
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_COMMON_DIR",
    "GIT_AUTHOR_NAME",
    "GIT_AUTHOR_EMAIL",
    "GIT_AUTHOR_DATE",
    "GIT_COMMITTER_NAME",
    "GIT_COMMITTER_EMAIL",
    "GIT_COMMITTER_DATE",
)

HUMAN = ("Synthetic Human", "human@example.invalid")
AGENT = ("Synthetic Agent", "agent@example.invalid")

OK = "commit-authorship: OK"


class CommitAuthorshipTests(unittest.TestCase):
    def setUp(self):
        self.directory = os.path.realpath(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.directory)
        self.repository = os.path.join(self.directory, "repository")
        os.makedirs(self.repository)
        self.allowlist = os.path.join(self.directory, "allowlist.txt")
        with open(self.allowlist, "w", encoding="utf-8") as handle:
            handle.write("# synthetic\n" + HUMAN[1] + "\n")
        self.base_env = {name: value for name, value in os.environ.items() if name not in HOOK_GIT_VARIABLES}
        self.base_env.update(
            GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL=os.devnull,
            ALLOWLIST_FILE=self.allowlist,
        )
        self._git(HUMAN, "init", "-q", "-b", "main")
        self.seed = self._commit(HUMAN, "feat: seed")

    def _env(self, identity: tuple[str, str]) -> dict:
        name, email = identity
        return dict(
            self.base_env,
            GIT_AUTHOR_NAME=name,
            GIT_AUTHOR_EMAIL=email,
            GIT_COMMITTER_NAME=name,
            GIT_COMMITTER_EMAIL=email,
        )

    def _git(self, identity: tuple[str, str], *args: str) -> str:
        completed = subprocess.run(
            ["git", *args], cwd=self.repository, env=self._env(identity), capture_output=True, text=True, check=True
        )
        return completed.stdout.strip()

    def _commit(self, identity: tuple[str, str], subject: str, body: str = "") -> str:
        message = ["-m", subject] + (["-m", body] if body else [])
        self._git(identity, "commit", "-q", "--allow-empty", "--cleanup=verbatim", *message)
        return self._git(identity, "rev-parse", "HEAD")

    def _range(self, commit_range: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["bash", SCRIPT, "--range", commit_range],
            cwd=self.repository,
            env=self._env(HUMAN),
            capture_output=True,
            text=True,
            check=False,
        )

    def _hook(self, message: str, identity: tuple[str, str] = HUMAN) -> subprocess.CompletedProcess:
        path = os.path.join(self.directory, "COMMIT_EDITMSG")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(message)
        return subprocess.run(
            ["bash", SCRIPT, path],
            cwd=self.repository,
            env=self._env(identity),
            capture_output=True,
            text=True,
            check=False,
        )

    def assert_passes(self, completed: subprocess.CompletedProcess) -> None:
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn(OK, completed.stdout)

    def assert_refuses(self, completed: subprocess.CompletedProcess, *expected: str) -> None:
        self.assertNotEqual(completed.returncode, 0, completed.stdout)
        self.assertNotIn(OK, completed.stdout + completed.stderr)
        for text in expected:
            self.assertIn(text, completed.stderr)


class RangeModeTests(CommitAuthorshipTests):
    """Range mode answers OK only for commits it has read."""

    def test_a_range_of_accountable_commits_passes(self):
        self._commit(HUMAN, "feat: a")
        self._commit(HUMAN, "feat: b")
        self.assert_passes(self._range(self.seed + "..HEAD"))

    def test_every_commit_of_the_range_is_read(self):
        self._commit(AGENT, "feat: a")
        self._commit(HUMAN, "feat: b")
        completed = self._range(self.seed + "..HEAD")
        self.assert_refuses(completed, "feat: a: author is not an accountable human", "2 violation(s)")

    def test_a_range_that_does_not_resolve_is_refused(self):
        self._commit(AGENT, "feat: a")
        completed = self._range("1" * 40 + "..HEAD")
        self.assert_refuses(completed, "does not resolve")

    def test_a_range_without_a_commit_is_refused(self):
        completed = self._range("HEAD..HEAD")
        self.assert_refuses(completed, "no commit in")

    def test_range_mode_needs_a_range(self):
        completed = subprocess.run(
            ["bash", SCRIPT, "--range"],
            cwd=self.repository,
            env=self._env(HUMAN),
            capture_output=True,
            text=True,
            check=False,
        )
        self.assert_refuses(completed)


class HookModeTests(CommitAuthorshipTests):
    """The commit-msg hook reads the pending commit's identity and message."""

    def test_an_accountable_identity_and_a_plain_message_pass(self):
        self.assert_passes(self._hook("feat: a\n\nWhy it changes.\n"))

    def test_an_identity_outside_the_allowlist_is_refused(self):
        completed = self._hook("feat: a\n", identity=AGENT)
        self.assert_refuses(completed, "author is not an accountable human", "committer is not an accountable human")


class MessageTests(CommitAuthorshipTests):
    """A credit line is read as git reads a trailer, and as a reader sees it.

    Every case runs in both modes: as the body of a commit read in range
    mode, and as the message file the commit-msg hook is handed.
    """

    HUMAN_LINE = "Co-authored-by: %s <%s>" % HUMAN
    AGENT_LINE = "Co-authored-by: %s <%s>" % AGENT

    def _both(self, body: str) -> list[subprocess.CompletedProcess]:
        self._commit(HUMAN, "feat: case", body)
        return [self._range("HEAD~1..HEAD"), self._hook("feat: case\n\n" + body + "\n")]

    def assert_both_pass(self, body: str) -> None:
        for completed in self._both(body):
            with self.subTest(body=body, command=completed.args[2:3]):
                self.assert_passes(completed)

    def assert_both_refuse(self, body: str, expected: str) -> None:
        for completed in self._both(body):
            with self.subTest(body=body, command=completed.args[2:3]):
                self.assert_refuses(completed, expected)

    def test_a_co_author_on_the_allowlist_passes(self):
        self.assert_both_pass(self.HUMAN_LINE)
        self.assert_both_pass("Why it changes.\n\n" + self.HUMAN_LINE.upper())

    def test_a_co_author_outside_the_allowlist_is_refused(self):
        self.assert_both_refuse(self.AGENT_LINE, "co-author is not an accountable human")
        self.assert_both_refuse("Why it changes.\n\n" + self.AGENT_LINE.upper(), "co-author is not an accountable human")

    def test_a_co_author_line_names_exactly_one_address(self):
        human, agent = "<%s>" % HUMAN[1], "<%s>" % AGENT[1]
        for value in (
            "Synthetic Agent %s %s" % (agent, human),
            "Synthetic Agent %s %s" % (human, agent),
            "Synthetic Human %s %s" % (human, human),
            "Synthetic Agent <%s %s>" % (AGENT[1], human),
            "Synthetic Agent <%s> %s>" % (AGENT[1], HUMAN[1]),
            "Synthetic Agent",
            HUMAN[1],
        ):
            self.assert_both_refuse("Co-authored-by: " + value, "co-author line must name exactly one address")

    def test_a_co_author_key_is_read_with_whitespace_before_its_colon(self):
        self.assert_both_refuse("Co-authored-by : %s <%s>" % AGENT, "co-author is not an accountable human")
        self.assert_both_refuse("Co-authored-by\t: %s <%s>" % AGENT, "co-author is not an accountable human")
        self.assert_both_pass("Co-authored-by : %s <%s>" % HUMAN)

    def test_a_co_author_key_is_read_on_an_indented_line(self):
        self.assert_both_refuse("  " + self.AGENT_LINE, "co-author is not an accountable human")
        self.assert_both_refuse("Reviewed-by: %s <%s>\n\t%s" % (*HUMAN, self.AGENT_LINE), "co-author is not an accountable human")

    def test_an_agent_footer_is_refused(self):
        for line in ("Claude-Session: synthetic", "Model: synthetic", "Thinking level: high", "MODEL: synthetic"):
            self.assert_both_refuse(line, "remove AI-identity footer line")

    def test_an_agent_footer_key_is_read_with_whitespace_before_its_colon(self):
        for line in ("Claude-Session : synthetic", "Model\t: synthetic", "Thinking level : high", "Thinking  level: high"):
            self.assert_both_refuse(line, "remove AI-identity footer line")

    def test_an_agent_footer_key_is_read_on_an_indented_line(self):
        for line in ("  Model: synthetic", "\tClaude-Session: synthetic", " Thinking level: high"):
            self.assert_both_refuse(line, "remove AI-identity footer line")

    def test_a_session_link_is_refused_anywhere_in_a_line(self):
        self.assert_both_refuse("See https://claude.ai/code/session_synthetic for more.", "remove AI session link")

    def test_prose_that_names_the_keys_passes(self):
        self.assert_both_pass(
            "The hook reads Co-authored-by trailers and the Model: footer.\n"
            "A data model: one table. Its co-authored-by handling is unchanged."
        )


if __name__ == "__main__":
    unittest.main()
