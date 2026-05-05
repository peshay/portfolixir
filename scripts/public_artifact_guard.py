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

SECRET_PATTERNS = [
    (re.compile(r"-----BEGIN (?:RSA|OPENSSH|EC|DSA|PGP) PRIVATE KEY-----"), "private key material"),
    (re.compile(r"\bghp_[A-Za-z0-9]{20,}\b"), "GitHub personal access token"),
    (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b"), "GitHub fine-grained token"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "AWS access key id"),
    (re.compile(r"\bxox(?:b|p|a|r|s)-[A-Za-z0-9-]{10,}\b"), "Slack token"),
]


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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
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
            for regex, reason in LEAK_PATTERNS:
                if regex.search(content):
                    violations.append(f"{relative}: {reason}")

        for regex, reason in SECRET_PATTERNS:
            if regex.search(content):
                violations.append(f"{relative}: possible {reason}")

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
