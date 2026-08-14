#!/usr/bin/env bash
# Local test-run capture (issue #682).
#
# Both observed multi-test failure bursts scrolled away before the failing
# test names or the ExUnit seed were saved, so the issue could only report a
# symptom. CI already persists the full run log as an artifact on every
# outcome (issue #654); this wrapper is the local half: it tees the complete
# `mix test` output into tmp/test-runs/ and names the seed on exit, so the
# next burst is inspectable after the fact and replayable with
# `mix test --seed <seed>`.
#
# Usage: scripts/capture-test-run.sh [mix test args...]
#   TEST_RUN_LOG_DIR   log directory (default tmp/test-runs)
#   TEST_RUN_LOG_KEEP  how many logs to keep, newest first (default 20)
#   MIX_TEST_CMD       command to run instead of `mix test` (used by the test)
set -uo pipefail

run_dir="${TEST_RUN_LOG_DIR:-tmp/test-runs}"
keep="${TEST_RUN_LOG_KEEP:-20}"
mkdir -p "$run_dir"
log="$run_dir/mix-test-$(date +%Y%m%d-%H%M%S%N).log"

cmd=${MIX_TEST_CMD:-mix test}
# shellcheck disable=SC2086 # intentional word-splitting of the command string
$cmd "$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

# Prune old logs beyond the keep window, newest first.
ls -1t "$run_dir"/mix-test-*.log 2>/dev/null | tail -n +$((keep + 1)) | xargs -r rm --

seed=$(grep -Eo 'seed [0-9]+' "$log" | tail -1 || true)
echo "captured: $log (${seed:-seed not found}; exit $status)"
exit "$status"
