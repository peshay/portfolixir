#!/bin/sh
# Trusts the build secret `build_ca` for the step that sources it, and for
# that step alone (#1026, #1136): the CA of a proxy that re-signs TLS, passed
# to the build as
#   docker build --secret id=build_ca,src=proxy-ca.crt -f Dockerfile.release .
# Every step of Dockerfile.release that downloads sources it first, because
# BuildKit keeps no secret in its cache key: a step cached from a build without
# the secret would otherwise go on without the CA. With the secret, the CA lands
# in the build stage's system store, which Mix reads, and the step's Hex is
# pointed at that store through HEX_CACERTS_PATH. Without it the script does
# nothing, and Hex keeps its own bundle. The apt steps of both stages, the
# runtime stage's included, read the CA through docker/apt-install.sh where it
# is mounted, and nothing of it stays in a layer of theirs.
#
# The CA leaves the store again when the step's shell exits (#1136): a trap,
# armed before the CA is added, removes it and rebuilds the store fresh before
# BuildKit writes the step's layer. No later step of the stage trusts it, and
# no layer, build cache entry or `--target build` image carries it. The step
# keeps its own exit status; if the CA cannot be taken out, a step that would
# have passed fails, so no layer is written with the CA in it.
set -eu

build_ca=/usr/local/share/ca-certificates/build-ca.crt

untrust_build_ca() {
  build_ca_status=$?
  if ! rm -f "$build_ca" || ! update-ca-certificates --fresh >/dev/null; then
    echo "trust-build-ca: the build CA could not be taken out of the store; the step fails" >&2
    if [ "$build_ca_status" -eq 0 ]; then
      build_ca_status=1
    fi
  fi
  exit "$build_ca_status"
}

if [ -s /run/secrets/build_ca ]; then
  trap untrust_build_ca EXIT
  cp /run/secrets/build_ca "$build_ca"
  update-ca-certificates >/dev/null
  export HEX_CACERTS_PATH=/etc/ssl/certs/ca-certificates.crt
fi
