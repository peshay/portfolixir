#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: validate-llm-commit-footer.sh <commit-msg-file>"
  exit 1
fi

COMMIT_MSG_FILE=$1
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)

if [ "$BRANCH_NAME" != "HEAD" ] && [[ "$BRANCH_NAME" == codex/* ]]; then
  echo "LLM commit metadata is required on codex/* branches."

  if ! grep -Eq "^Model:[[:space:]]+.+$" "$COMMIT_MSG_FILE"; then
    echo "Missing commit footer line: 'Model: <model-name>'"
    exit 1
  fi

  if ! grep -Ei -Eq "^Thinking level:[[:space:]]+(none|minimal|low|medium|high|xhigh)$" "$COMMIT_MSG_FILE"; then
    echo "Missing commit footer line: 'Thinking level: <none|minimal|low|medium|high|xhigh>'"
    exit 1
  fi

  echo "Found commit metadata footer:"
  grep -E "^Model:[[:space:]]+.+$|^Thinking level:[[:space:]]+(none|minimal|low|medium|high|xhigh)$" "$COMMIT_MSG_FILE"
fi

exit 0
