#!/usr/bin/env python3
"""Refuse a repository index that tracks a symlink (git mode 120000).

Run by the pre-commit hook `no-symlinks` on every commit, and by CI's
`pre-commit run --all-files`, so CI holds it too. It reads the index with
``git ls-files -s``, so it sees what the commit would record, staged or
already committed, and ignores untracked or ignored links such as a linked
worktree's ``deps``.

Why: in Sprint 22 a worktree commit tracked the shared ``deps`` symlink, and
cherry-picking it replaced the main checkout's ``deps`` with a self-symlink
(Sprint 22 retrospective). Portfolixir tracks no symlink, and none is needed:
a link's target is a path on one machine. Exit status 0 is clean, 1 names
each symlink on stderr.

Standard library only.
"""

from __future__ import annotations

import subprocess
import sys

SYMLINK_MODE = "120000"


def tracked_symlinks() -> list[str]:
    listing = subprocess.run(
        ["git", "ls-files", "--stage", "-z"], capture_output=True, check=True
    ).stdout.decode("utf-8", errors="surrogateescape")
    found = []
    for record in listing.split("\0"):
        if not record:
            continue
        metadata, _tab, path = record.partition("\t")
        if metadata.split(" ", 1)[0] == SYMLINK_MODE and path not in found:
            found.append(path)
    return found


def main() -> int:
    symlinks = tracked_symlinks()
    for path in symlinks:
        print(f"check_no_symlinks: {path} is tracked as a symlink (git mode {SYMLINK_MODE})", file=sys.stderr)
    if symlinks:
        print(
            "check_no_symlinks: unstage it with `git rm --cached <path>` and keep it out with an exclude line;"
            " scripts/worktree.sh writes those for a worktree's deps and node_modules",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
