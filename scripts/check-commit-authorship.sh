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
mapfile -t ALLOWED < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$ALLOWLIST_FILE" \
  | grep -v '^$' | tr 'A-Z' 'a-z')

if [ "${#ALLOWED[@]}" -eq 0 ]; then
  echo "commit-authorship: allowlist is empty: $ALLOWLIST_FILE" >&2
  exit 1
fi

is_allowed() {
  local email a
  email="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
  for a in "${ALLOWED[@]}"; do
    [ "$email" = "$a" ] && return 0
  done
  return 1
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

check_message() {
  # $1 = ref, $2 = full commit message
  local ref="$1" line low email
  while IFS= read -r line; do
    low="$(printf '%s' "$line" | tr 'A-Z' 'a-z')"
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
    check_identity "$ref" author    "$(git log -1 --format='%an' "$sha")" "$(git log -1 --format='%ae' "$sha")"
    check_identity "$ref" committer "$(git log -1 --format='%cn' "$sha")" "$(git log -1 --format='%ce' "$sha")"
    check_message  "$ref" "$(git log -1 --format='%B' "$sha")"
  done
else
  # commit-msg hook mode: $1 is the message file (may be absent in ad-hoc runs).
  msg_file="${1:-}"
  author_ident="$(git var GIT_AUTHOR_IDENT)"
  committer_ident="$(git var GIT_COMMITTER_IDENT)"
  check_identity "pending commit" author \
    "$(printf '%s' "$author_ident" | sed 's/ <.*//')" "$(email_of "$author_ident")"
  check_identity "pending commit" committer \
    "$(printf '%s' "$committer_ident" | sed 's/ <.*//')" "$(email_of "$committer_ident")"
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
