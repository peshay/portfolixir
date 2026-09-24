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
# Elixir 1.18.5 / OTP 27.3.4.18, the exact patch the images ship (see
# _bmad-output/project-context.md: "Do not use language features beyond the CI
# version"). ci_test pins the defaults below to CI's `elixir-version` /
# `otp-version` and to both Dockerfiles, so a bump moves all of them at once.
set -euo pipefail

ELIXIR_VERSION="${ELIXIR_VERSION:-1.18.5}"
# The exact OTP patch CI and the images run, precompiled for ubuntu-24.04 on
# builds.hex.pm (the same build source CI's setup-beam uses). List options:
# builds.hex.pm/builds/otp/ubuntu-24.04/builds.txt
OTP_VERSION="${OTP_VERSION:-27.3.4.18}"
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

# 2. Erlang/OTP — precompiled build from builds.hex.pm. An install of another
# patch (a cached snapshot from before a bump) is replaced, not kept: a
# presence check alone left the old runtime in place after the pin moved.
installed_otp() {
  cat "${OTP_DIR}"/releases/*/OTP_VERSION 2>/dev/null | head -n1
}
if [ ! -x "${OTP_DIR}/bin/erl" ] || ! "${OTP_DIR}/bin/erl" -noshell -eval 'halt()' 2>/dev/null \
  || [ "$(installed_otp)" != "${OTP_VERSION}" ]; then
  # Download before removing, so a failed fetch leaves the old toolchain usable.
  curl -fsSL "https://builds.hex.pm/builds/otp/${UBUNTU}/OTP-${OTP_VERSION}.tar.gz" -o /tmp/otp.tar.gz
  rm -rf "${OTP_DIR}"
  mkdir -p "${OTP_DIR}"
  tar -xzf /tmp/otp.tar.gz -C "${OTP_DIR}" --strip-components=1
  "${OTP_DIR}/Install" -minimal "${OTP_DIR}" >/dev/null
  rm -f /tmp/otp.tar.gz
fi

# 3. Elixir — precompiled release matching the OTP major version, replaced
# when the installed one is another version.
if [ ! -x "${ELIXIR_DIR}/bin/elixir" ] || [ "$(cat "${ELIXIR_DIR}/VERSION" 2>/dev/null)" != "${ELIXIR_VERSION}" ]; then
  curl -fsSL "https://github.com/elixir-lang/elixir/releases/download/v${ELIXIR_VERSION}/elixir-otp-${OTP_MAJOR}.zip" -o /tmp/elixir.zip
  rm -rf "${ELIXIR_DIR}"
  mkdir -p "${ELIXIR_DIR}"
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
