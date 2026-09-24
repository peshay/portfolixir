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
grep -m1 "^FROM " Dockerfile
grep "^FROM " Dockerfile.release
grep -m1 "image: postgres" docker-compose.yml | sed 's/^ *//'

# The tag is not the runtime: the release bundles whatever ERTS its build
# image contains, and a frozen tag once shipped an OTP with published
# TLS-client advisories while CI tested a patched one (the 2026-09-24 runtime
# hotfix). So the report reads the OTP inside that image, next to CI's pin.
section "OTP inside the release's build image (what every instance runs)"
build_image=$(awk '/^FROM .* AS build$/ {print $2; exit}' Dockerfile.release)
echo "image: ${build_image}"
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  docker run --rm --entrypoint sh "${build_image}" -c \
    'printf "OTP_VERSION inside the image: "; cat "$(erl -noshell -eval "io:format(\"~s\", [code:root_dir()]), halt().")"/releases/*/OTP_VERSION' \
    || echo "could not read the OTP inside the image"
else
  echo "docker is not available: the OTP inside the image was NOT read; run this report where docker runs"
fi

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
