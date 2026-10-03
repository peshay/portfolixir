#!/bin/sh
# Trusts the build secret `build_ca` for the step that runs it (#1026): the CA
# of a proxy that re-signs TLS, passed to the build as
#   docker build --secret id=build_ca,src=proxy-ca.crt -f Dockerfile.release .
# Without the secret it does nothing. Every step of Dockerfile.release that
# downloads runs it first, because BuildKit keeps no secret in its cache key:
# a step cached from a build without the secret would otherwise go on without
# the CA. The CA lands in the build stage's system store, which Mix reads and
# Hex reads through HEX_CACERTS_PATH; the runtime stage never sees it.
set -eu

if [ -s /run/secrets/build_ca ]; then
  cp /run/secrets/build_ca /usr/local/share/ca-certificates/build-ca.crt
  update-ca-certificates >/dev/null
fi
