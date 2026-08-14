#!/usr/bin/env bash
# Version report for the per-batch maintenance lane (#676).
#
# Prints a readable point-in-time picture of dependency and toolchain
# state: outdated Hex and npm packages, security-advisory status, unused
# lockfile entries, and the toolchain pins CI is authoritative for.
# Read-only; never modifies the tree. Non-zero exit codes from the
# individual tools are expected (they signal "updates exist" or
# "advisories exist") and do not abort the report.
#
# Usage: scripts/version-report.sh   (run from the repository root)

set -u

section() {
  printf '\n== %s ==\n' "$1"
}

section "Toolchain pins (CI is authoritative)"
grep -m1 "elixir-version" .github/workflows/ci.yml | sed 's/^ *//'
grep -m1 "otp-version" .github/workflows/ci.yml | sed 's/^ *//'
grep -m1 "FROM elixir" Dockerfile
grep -m1 "image: postgres" docker-compose.yml | sed 's/^ *//'

section "Hex: outdated packages"
mix hex.outdated || true

section "Hex: security advisories and retirements (mix hex.audit)"
mix hex.audit || true

section "Hex: advisory scan (mix deps.audit, CI runs this with a documented ignore list)"
mix deps.audit || true

section "Hex: unused lockfile entries (requires deps fetched)"
mix deps.unlock --check-unused || true

section "npm (mcp-server): outdated packages"
npm outdated --prefix mcp-server || true

section "npm (mcp-server): audit (CI gates at --audit-level=high)"
npm audit --audit-level=high --prefix mcp-server || true

section "BMAD install (manifest)"
grep -E "^\s+(version|- name|channel|sha):" _bmad/_config/manifest.yaml

printf '\nReport complete. Decisions and reasons belong in the maintenance-lane commit(s) and the PR briefing.\n'
