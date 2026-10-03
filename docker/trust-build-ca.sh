#!/bin/sh
# Trusts the build secret `build_ca` for the step that sources it (#1026): the
# CA of a proxy that re-signs TLS, passed to the build as
#   docker build --secret id=build_ca,src=proxy-ca.crt -f Dockerfile.release .
# Every step of Dockerfile.release that downloads sources it first, because
# BuildKit keeps no secret in its cache key: a step cached from a build without
# the secret would otherwise go on without the CA. With the secret, the CA lands
# in the build stage's system store, which Mix reads, and the step's Hex is
# pointed at that store through HEX_CACERTS_PATH. Without it the script does
# nothing, and Hex keeps its own bundle. The runtime stage never sees the CA.
set -eu

if [ -s /run/secrets/build_ca ]; then
  cp /run/secrets/build_ca /usr/local/share/ca-certificates/build-ca.crt
  update-ca-certificates >/dev/null
  export HEX_CACERTS_PATH=/etc/ssl/certs/ca-certificates.crt
fi
