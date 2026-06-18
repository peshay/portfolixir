#!/usr/bin/env bash
#
# Install the full Elixir toolchain (Erlang/OTP + Elixir) and PostgreSQL for
# Claude Code on the web, so portfolixir can run mix test, credo, dialyzer,
# sobelow and deps.audit in cloud sessions.
#
# Idempotent and non-interactive: safe to run repeatedly. Invoked from the
# environment's "Setup script" field (its result is cached as a filesystem
# snapshot) and, as a cold-cache safety net, from the SessionStart hook.
#
# VERSIONS TRACK CI. CI (.github/workflows/ci.yml) is authoritative and runs
# Elixir 1.18.3 / OTP 27 (see _bmad-output/project-context.md: "Do not use
# language features beyond the CI version"). Keep the versions below in sync
# with the `elixir-version` / `otp-version` used by setup-beam in CI. Bumping
# the toolchain is a deliberate change that should move CI at the same time.
set -euo pipefail

ELIXIR_VERSION="${ELIXIR_VERSION:-1.18.3}"
# Latest OTP-27.x precompiled for ubuntu-24.04 on builds.hex.pm (the same build
# source CI's setup-beam uses). List options: builds.hex.pm/builds/otp/ubuntu-24.04/builds.txt
OTP_VERSION="${OTP_VERSION:-27.3.4.13}"
OTP_MAJOR="27"
UBUNTU="ubuntu-24.04"

OTP_DIR=/opt/otp
ELIXIR_DIR=/opt/elixir

export DEBIAN_FRONTEND=noninteractive

# 1. System packages: PostgreSQL, fetch tools, CA bundle, UTF-8 locale.
# The base web image preconfigures unrelated third-party PPAs (deadsnakes,
# ondrej/php) on ppa.launchpadcontent.net that the network policy blocks (403).
# A single failing source makes `apt-get update` exit non-zero, which would
# abort this script under `set -e` even though the Ubuntu archives we actually
# need refreshed fine. Tolerate that: the install step below still fails loudly
# if a package genuinely cannot be resolved.
apt-get update -y || true
apt-get install -y --no-install-recommends \
  postgresql postgresql-contrib curl unzip ca-certificates locales git
# Elixir warns and can malfunction under a latin1 locale; ensure C.UTF-8 exists.
locale-gen C.UTF-8 || true

# 2. Erlang/OTP — precompiled build from builds.hex.pm.
if [ ! -x "${OTP_DIR}/bin/erl" ] || ! "${OTP_DIR}/bin/erl" -noshell -eval 'halt()' 2>/dev/null; then
  mkdir -p "${OTP_DIR}"
  curl -fsSL "https://builds.hex.pm/builds/otp/${UBUNTU}/OTP-${OTP_VERSION}.tar.gz" -o /tmp/otp.tar.gz
  tar -xzf /tmp/otp.tar.gz -C "${OTP_DIR}" --strip-components=1
  "${OTP_DIR}/Install" -minimal "${OTP_DIR}" >/dev/null
  rm -f /tmp/otp.tar.gz
fi

# 3. Elixir — precompiled release matching the OTP major version.
if [ ! -x "${ELIXIR_DIR}/bin/elixir" ]; then
  mkdir -p "${ELIXIR_DIR}"
  curl -fsSL "https://github.com/elixir-lang/elixir/releases/download/v${ELIXIR_VERSION}/elixir-otp-${OTP_MAJOR}.zip" -o /tmp/elixir.zip
  unzip -q -o /tmp/elixir.zip -d "${ELIXIR_DIR}"
  rm -f /tmp/elixir.zip
fi

# 4. Hex + rebar3 (Erlang's TLS uses its own CA store; point it at the system bundle).
export PATH="${OTP_DIR}/bin:${ELIXIR_DIR}/bin:${PATH}"
export HEX_CACERTS_PATH="${HEX_CACERTS_PATH:-/etc/ssl/certs/ca-certificates.crt}"
export LANG=C.UTF-8 LC_ALL=C.UTF-8 ELIXIR_ERL_OPTIONS="+fnu"
mix local.hex --force >/dev/null 2>&1 || true
mix local.rebar --force >/dev/null 2>&1 || true

echo "Elixir toolchain ready: $("${ELIXIR_DIR}/bin/elixir" --version 2>/dev/null | tail -1)"
