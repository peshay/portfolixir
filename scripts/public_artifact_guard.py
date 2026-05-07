#!/usr/bin/env python3
"""Guard against accidental publication of internal artifacts in repo-facing text."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

PUBLIC_EXTENSIONS = {
    ".md",
    ".markdown",
    ".txt",
    ".adoc",
    ".rst",
    ".yaml",
    ".yml",
    ".tmpl",
    ".template",
    ".j2",
    ".sh",
    ".bash",
    ".zsh",
}

PUBLIC_PREFIXES = (
    ".github/",
    "docs/",
    "prompts/",
)

PUBLIC_BASENAMES = (
    "README",
    "CONTRIBUTING",
    "SECURITY",
    "CODE_OF_CONDUCT",
)

EXCLUDED_FILES = {
    "scripts/public_artifact_guard.py",
}

LEAK_PATTERNS = [
    (re.compile(r"/home/openclaw/", re.IGNORECASE), "internal path leak: /home/openclaw/"),
    (re.compile(r"\.openclaw", re.IGNORECASE), "internal runtime marker leak: .openclaw"),
    (re.compile(r"agent:[A-Za-z0-9:_-]+"), "internal session identifier leak"),
    (re.compile(r"\bclaw-code\d+\b", re.IGNORECASE), "private host metadata leak"),
]

TRACE_METADATA_PATTERNS = [
    (re.compile(r"\[Subagent Context\]", re.IGNORECASE), "subagent transcript marker leak"),
    (re.compile(r"Requester session:\s*", re.IGNORECASE), "requester session metadata leak"),
    (re.compile(r"Session Context\s*", re.IGNORECASE), "session context metadata leak"),
    (re.compile(r"\bRuntime:\s*agent=", re.IGNORECASE), "runtime trace metadata leak"),
    (re.compile(r"\bcapabilities=", re.IGNORECASE), "runtime capability trace metadata leak"),
    (re.compile(r"\bos=Linux\s+\d+\.\d+", re.IGNORECASE), "private runtime host metadata leak"),
]

PRIVATE_OBJECT_ID_PATTERNS = [
    (
        re.compile(
            r"(?i)\b(?:boardId|boardMembershipId|listId|cardId|projectId|projectManagerId|"
            r"taskId|taskListId|commentId|attachmentId|notificationId|actionId|userId)\b\s*[:=]",
        ),
        "private board/object identifier leak",
    ),
]

SECRET_PATTERNS = [
    (re.compile(r"-----BEGIN (?:RSA|OPENSSH|EC|DSA|PGP) PRIVATE KEY-----"), "private key material"),
    (re.compile(r"\bghp_[A-Za-z0-9]{20,}\b"), "GitHub personal access token"),
    (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b"), "GitHub fine-grained token"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "AWS access key id"),
    (re.compile(r"\bxox(?:b|p|a|r|s)-[A-Za-z0-9-]{10,}\b"), "Slack token"),
]

COMMIT_METADATA_PATTERNS = [
    (re.compile(r"(?im)^[ \t]*AI-Agent\s*:"), "internal agent metadata footer"),
    (re.compile(r"(?im)^[ \t]*Worker-(?!Model\s*:|Thinking\s*:)[A-Za-z0-9-]*\s*:"), "unsupported worker metadata footer"),
    (
        re.compile(
            r"(?im)^[ \t]*(?:Orchestrator|Review|Runtime|Host|Workspace|Prompt|Rule|Session)-(?:Model|Thinking|Id|Path|Name)?\s*:",
        ),
        "private runtime metadata footer",
    ),
    (re.compile(r"(?im)^[ \t]*(?:Runtime|Host|Workspace|Path)\s*:"), "private metadata key"),
    (re.compile(r"(?i)OpenClaw Code Agent"), "private agent identity"),
    (re.compile(r"(?i)openclaw-code@[^>\s]+"), "private agent email address"),
    (re.compile(r"(?i)@[A-Za-z0-9._%+-]+\.local\b"), "local-only email domain"),
    (re.compile(r"(?i)@localhost\b"), "local-only email domain"),
]

MODEL_IDENTIFIER_PATTERN = re.compile(r"(?i)(?:openai-codex|codex)/[A-Za-z0-9._-]+")
WORKER_MODEL_PATTERN = re.compile(r"^(?:openai-codex|codex)/[A-Za-z0-9._-]+$")
WORKER_THINKING_VALUES = {"low", "medium", "high"}
DISALLOWED_WORKER_MODELS = {
    "openai-codex/gpt-5.4-mini",
}
WORKER_FOOTER_PATTERN = re.compile(r"(?im)^[ \t]*Worker-(Model|Thinking)\s*:\s*(.+?)\s*$")


def git_tracked_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    raw = result.stdout.decode("utf-8", errors="ignore")
    return [ROOT / part for part in raw.split("\0") if part]


def is_binary(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            chunk = handle.read(4096)
    except OSError:
        return False
    return b"\0" in chunk


def is_public_artifact_file(relative_path: str) -> bool:
    if relative_path in EXCLUDED_FILES:
        return False

    if any(relative_path.startswith(prefix) for prefix in PUBLIC_PREFIXES):
        return True

    name = Path(relative_path).name
    if any(name.startswith(prefix) for prefix in PUBLIC_BASENAMES):
        return True

    return Path(relative_path).suffix.lower() in PUBLIC_EXTENSIONS


def normalize_files(candidate_files: list[str]) -> list[Path]:
    files: list[Path] = []
    for candidate in candidate_files:
        path = (ROOT / candidate).resolve() if not Path(candidate).is_absolute() else Path(candidate)
        try:
            rel = path.relative_to(ROOT)
        except ValueError:
            continue
        if rel.as_posix() in EXCLUDED_FILES:
            continue
        if path.is_file():
            files.append(path)
    return files


def git_commit_metadata(commit_range: str) -> list[tuple[str, str]]:
    try:
        rev_list = subprocess.run(
            ["git", "rev-list", "--reverse", commit_range],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.strip() or exc.stdout.strip() or "unknown git rev-list failure"
        raise SystemExit(f"cannot inspect commit range {commit_range!r}: {detail}") from exc
    commits = [line.strip() for line in rev_list.stdout.splitlines() if line.strip()]

    metadata: list[tuple[str, str]] = []
    for commit in commits:
        show = subprocess.run(
            [
                "git",
                "show",
                "-s",
                "--format=commit %H%nAuthor: %an <%ae>%nCommitter: %cn <%ce>%nSubject: %s%nBody:%n%b",
                commit,
            ],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        metadata.append((commit, show.stdout))

    return metadata


def validate_worker_footer_values(commit: str, text: str) -> list[str]:
    violations: list[str] = []

    for field, raw_value in WORKER_FOOTER_PATTERN.findall(text):
        value = raw_value.strip()
        if field.lower() == "model":
            if not WORKER_MODEL_PATTERN.fullmatch(value):
                violations.append(f"commit {commit[:12]}: invalid Worker-Model footer value")
                continue
            if value.lower() in DISALLOWED_WORKER_MODELS:
                violations.append(f"commit {commit[:12]}: Worker-Model cannot use orchestrator model")
        elif field.lower() == "thinking" and value.lower() not in WORKER_THINKING_VALUES:
            violations.append(f"commit {commit[:12]}: invalid Worker-Thinking footer value")

    return violations


def check_commit_metadata_text(commit: str, text: str) -> list[str]:
    violations: list[str] = []
    short = commit[:12]

    text_without_allowed_worker_footers = WORKER_FOOTER_PATTERN.sub("", text)
    if MODEL_IDENTIFIER_PATTERN.search(text_without_allowed_worker_footers):
        violations.append(f"commit {short}: internal model identifier outside allowed Worker-Model footer")

    for regex, reason in [
        *LEAK_PATTERNS,
        *TRACE_METADATA_PATTERNS,
        *PRIVATE_OBJECT_ID_PATTERNS,
        *SECRET_PATTERNS,
        *COMMIT_METADATA_PATTERNS,
    ]:
        if regex.search(text):
            violations.append(f"commit {short}: {reason}")

    violations.extend(validate_worker_footer_values(commit, text))
    return violations


def check_commit_metadata(commit_range: str) -> list[str]:
    violations: list[str] = []

    for commit, text in git_commit_metadata(commit_range):
        violations.extend(check_commit_metadata_text(commit, text))

    return violations


def check_text_artifact(label: str, text: str) -> list[str]:
    violations: list[str] = []

    if "\\n" in text:
        violations.append(f"{label}: contains literal escaped newline \\n in public artifact text; use real line breaks")

    for regex, reason in [*LEAK_PATTERNS, *TRACE_METADATA_PATTERNS, *PRIVATE_OBJECT_ID_PATTERNS, *SECRET_PATTERNS]:
        if regex.search(text):
            violations.append(f"{label}: {reason}")

    return violations


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--commit-range", help="Optional git commit range to scan for public metadata leaks")
    parser.add_argument("--stdin", action="store_true", help="Scan stdin as public artifact text")
    parser.add_argument("--text", help="Direct text to scan as public artifact text")
    parser.add_argument("--label", default="text-artifact", help="Label used for stdin/text findings")
    parser.add_argument("files", nargs="*", help="Optional file list from pre-commit")
    args = parser.parse_args()

    files = normalize_files(args.files) if args.files else git_tracked_files()

    violations: list[str] = []

    for file_path in files:
        if is_binary(file_path):
            continue

        relative = file_path.relative_to(ROOT).as_posix()
        try:
            content = file_path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            content = file_path.read_text(encoding="utf-8", errors="ignore")

        if is_public_artifact_file(relative) and "\\n" in content:
            violations.append(
                f"{relative}: contains literal escaped newline \\n in public artifact text; use real line breaks"
            )

        if is_public_artifact_file(relative):
            for regex, reason in [*LEAK_PATTERNS, *TRACE_METADATA_PATTERNS, *PRIVATE_OBJECT_ID_PATTERNS]:
                if regex.search(content):
                    violations.append(f"{relative}: {reason}")

        for regex, reason in SECRET_PATTERNS:
            if regex.search(content):
                violations.append(f"{relative}: possible {reason}")

    if args.commit_range:
        violations.extend(check_commit_metadata(args.commit_range))

    if args.stdin:
        violations.extend(check_text_artifact(args.label, sys.stdin.read()))

    if args.text is not None:
        violations.extend(check_text_artifact(args.label, args.text))

    if violations:
        print("public-artifact-guard failed:")
        for item in sorted(set(violations)):
            print(f"- {item}")
        print("\nFix files, then rerun: pre-commit run --all-files")
        return 1

    print("public-artifact-guard passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
