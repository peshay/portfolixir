#!/usr/bin/env bash
#
# SessionStart hook for Claude Code on the web.
#
# The environment's filesystem cache preserves files (the toolchain installed by
# the Setup script) but NOT running processes, so every session must start
# PostgreSQL itself and export the toolchain onto PATH. This hook:
#   1. (cold-cache safety net) installs the toolchain if it is missing,
#   2. exports PATH / locale / Hex CA env for the whole session,
#   3. starts PostgreSQL with the credentials config/test.exs expects,
#   4. fetches deps and prepares the test database.
#
# It is a no-op outside the web environment, so it never affects local
# `claude` terminal sessions.
set -euo pipefail

# Web only — local terminal sessions already have the developer's toolchain.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
OTP_DIR=/opt/otp
ELIXIR_DIR=/opt/elixir

# 1. Cold-cache safety net: install the toolchain if the cached Setup script
#    snapshot is not present yet.
if [ ! -x "${ELIXIR_DIR}/bin/elixir" ]; then
  bash "${ROOT}/.claude/scripts/install-elixir-toolchain.sh"
fi

# 2. Persist environment for the whole session.
ENV_FILE="${CLAUDE_ENV_FILE:-/dev/null}"
{
  echo "export PATH=\"${OTP_DIR}/bin:${ELIXIR_DIR}/bin:\$PATH\""
  echo "export HEX_CACERTS_PATH=/etc/ssl/certs/ca-certificates.crt"
  echo "export LANG=C.UTF-8"
  echo "export LC_ALL=C.UTF-8"
  echo "export ELIXIR_ERL_OPTIONS=\"+fnu\""
} >> "${ENV_FILE}"

export PATH="${OTP_DIR}/bin:${ELIXIR_DIR}/bin:${PATH}"
export HEX_CACERTS_PATH=/etc/ssl/certs/ca-certificates.crt
export LANG=C.UTF-8 LC_ALL=C.UTF-8 ELIXIR_ERL_OPTIONS="+fnu"

# 3. Start PostgreSQL (not preserved by the cache) and align credentials with
#    config/test.exs (postgres / postgres).
PG_VER="$(ls /etc/postgresql 2>/dev/null | sort -V | tail -1 || true)"
if [ -n "${PG_VER}" ]; then
  pg_ctlcluster "${PG_VER}" main start 2>/dev/null || service postgresql start 2>/dev/null || true
  for _ in $(seq 1 15); do pg_isready -q && break; sleep 1; done
  su - postgres -c "psql -tAc \"ALTER USER postgres WITH PASSWORD 'postgres';\"" >/dev/null 2>&1 || true
fi

# 4. Fetch deps and prepare the test DB so tests and linters are ready to run.
cd "${ROOT}"
mix local.hex --force >/dev/null 2>&1 || true
mix local.rebar --force >/dev/null 2>&1 || true
mix deps.get >/dev/null 2>&1 || true
MIX_ENV=test mix ecto.create >/dev/null 2>&1 || true
MIX_ENV=test mix ecto.migrate >/dev/null 2>&1 || true

echo "portfolixir web session ready: $(elixir --version 2>/dev/null | tail -1)"
