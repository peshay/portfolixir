#!/usr/bin/env bash
# Enforce human accountability for every commit.
#
# Policy: a commit is always attributed to an accountable human (their GitHub
# account), even when the change was produced with an LLM or coding agent. The
# agent is a tool that drafts the change; a person owns the result and commits
# under their own Git identity. Agents must commit AS the human, never under a
# bot identity, and must not credit themselves through co-author or session
# trailers.
#
# Two modes:
#   * commit-msg hook (default): the only argument is the commit message file.
#     Validates the pending commit's author/committer identity and message.
#   * range mode (--range A..B): validates every commit in a range. Used by CI.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
ALLOWLIST_FILE="${ALLOWLIST_FILE:-$ROOT/.github/commit-authorship-allowlist.txt}"

if [ ! -f "$ALLOWLIST_FILE" ]; then
  echo "commit-authorship: allowlist file not found: $ALLOWLIST_FILE" >&2
  exit 1
fi

# Allowed emails, lower-cased, with comments (# ...) and whitespace stripped.
# Read into an array with a portable loop instead of `mapfile` (a bash 4+
# builtin) so the hook also runs under macOS' default /bin/bash 3.2.
ALLOWED=()
while IFS= read -r line; do
  ALLOWED+=("$line")
done < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$ALLOWLIST_FILE" \
  | grep -v '^$' | tr 'A-Z' 'a-z')

if [ "${#ALLOWED[@]}" -eq 0 ]; then
  echo "commit-authorship: allowlist is empty: $ALLOWLIST_FILE" >&2
  exit 1
fi

# Identity matching is case-insensitive throughout.
to_lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

is_allowed() {
  local email a
  email="$(to_lower "$1")"
  for a in "${ALLOWED[@]}"; do
    [ "$email" = "$a" ] && return 0
  done
  return 1
}

# GitHub's web UI performs squash/rebase/merge commits with itself as the
# committer (web-flow, `GitHub <noreply@github.com>`). ADR-0026 prescribes that
# the owner squash-merges through that UI, so this committer cannot be a
# human's identity by construction. It is accepted for the COMMITTER role only,
# and only when the commit's AUTHOR is an accountable human -- authorship stays
# the accountable record. It is never accepted as an author or co-author.
PLATFORM_MERGE_COMMITTER="noreply@github.com"

is_platform_merge_committer() {
  [ "$(to_lower "$1")" = "$PLATFORM_MERGE_COMMITTER" ]
}

violations=0
report() { echo "  - $1" >&2; violations=$((violations + 1)); }

email_of() { printf '%s' "$1" | sed -n 's/.*<\(.*\)>.*/\1/p'; }

check_identity() {
  # $1 = ref, $2 = role, $3 = name, $4 = email
  if [ -z "$4" ] || ! is_allowed "$4"; then
    report "$1: $2 is not an accountable human: ${3:-?} <${4:-?}>"
  fi
}

check_committer() {
  # $1 = ref, $2 = name, $3 = email, $4 = author email
  if is_platform_merge_committer "$3" && [ -n "$4" ] && is_allowed "$4"; then
    return 0
  fi
  check_identity "$1" committer "$2" "$3"
}

check_message() {
  # $1 = ref, $2 = full commit message
  local ref="$1" line low email
  while IFS= read -r line; do
    low="$(to_lower "$line")"
    case "$low" in
      co-authored-by:*)
        email="$(email_of "$line")"
        if [ -z "$email" ] || ! is_allowed "$email"; then
          report "$ref: co-author is not an accountable human: ${line#*: }"
        fi
        ;;
      claude-session:*|model:*|"thinking level:"*)
        report "$ref: remove AI-identity footer line: $line"
        ;;
    esac
    # Match real AI session links (always carry a "session_<id>" segment), not
    # prose that merely mentions the pattern while documenting this policy.
    case "$low" in
      *claude.ai/code/session_*) report "$ref: remove AI session link: $line" ;;
    esac
  done <<EOF
$2
EOF
}

if [ "${1:-}" = "--range" ]; then
  range="${2:?usage: check-commit-authorship.sh --range <git-range>}"
  for sha in $(git rev-list "$range"); do
    ref="$(git log -1 --format='%h %s' "$sha")"
    author_email="$(git log -1 --format='%ae' "$sha")"
    check_identity "$ref" author "$(git log -1 --format='%an' "$sha")" "$author_email"
    check_committer "$ref" "$(git log -1 --format='%cn' "$sha")" "$(git log -1 --format='%ce' "$sha")" "$author_email"
    check_message  "$ref" "$(git log -1 --format='%B' "$sha")"
  done
else
  # commit-msg hook mode: $1 is the message file (may be absent in ad-hoc runs).
  msg_file="${1:-}"
  author_ident="$(git var GIT_AUTHOR_IDENT)"
  committer_ident="$(git var GIT_COMMITTER_IDENT)"
  check_identity "pending commit" author \
    "$(printf '%s' "$author_ident" | sed 's/ <.*//')" "$(email_of "$author_ident")"
  check_committer "pending commit" \
    "$(printf '%s' "$committer_ident" | sed 's/ <.*//')" \
    "$(email_of "$committer_ident")" "$(email_of "$author_ident")"
  if [ -n "$msg_file" ] && [ -f "$msg_file" ]; then
    check_message "pending commit" "$(cat "$msg_file")"
  fi
fi

if [ "$violations" -gt 0 ]; then
  {
    echo ""
    echo "commit-authorship: $violations violation(s)."
    echo "Every commit must be authored by an accountable human listed in"
    echo "  ${ALLOWLIST_FILE#"$ROOT"/}"
    echo "Configure Git to commit under your own GitHub identity, for example:"
    echo "  git config user.name  \"Your Name\""
    echo "  git config user.email \"you@users.noreply.github.com\""
  } >&2
  exit 1
fi

echo "commit-authorship: OK"
