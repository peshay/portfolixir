#!/bin/sh
# Installs Debian packages in a step of Dockerfile.release (#1092):
#   sh /run/apt-install.sh <package>...
# runs apt-get update, apt-get install -y --no-install-recommends and removes
# the package lists, the three commands both stages used to run inline.
#
# The step mounts this script and the optional build secret `build_ca` rather
# than copying them, so neither lands in a layer. Three inputs change where apt
# fetches from:
# - `build_ca`, the CA apt verifies HTTPS against (Acquire::https::CAInfo),
#   read where BuildKit mounts it and copied nowhere. The sources that name
#   deb.debian.org move to https. CAInfo replaces every other trust, so the
#   secret may be a bundle: a re-signing proxy's CA with the system's. The
#   step mounts it readable by all (mode=0444), because apt downloads as its
#   unprivileged `_apt` user.
# - the build argument DEBIAN_MIRROR, a base URL (http://mirror.example/) that
#   replaces http://deb.debian.org for the debian archive, in the scheme it is
#   written in;
# - the build argument DEBIAN_SECURITY_MIRROR, the same for the
#   debian-security archive; empty, it is DEBIAN_MIRROR.
# A mirror is a base, not an archive path, and carries no credentials: a build
# argument a step uses is recorded in the image's build history.
# With any input, apt reads a rewritten copy of the sources through
# APT_CONFIG, from a temporary directory removed when the step ends; the
# image's own sources are never changed. With none, the three commands run
# exactly as before, on the image's own http://deb.debian.org sources.
set -eu

refuse() {
  echo "apt-install.sh: $*" >&2
  exit 2
}

# Prints the base URL a mirror variable names, without trailing slashes, or
# refuses it with one line.
mirror_base() {
  name=$1
  url=$2
  case "$url" in
    http://[A-Za-z0-9]* | https://[A-Za-z0-9]*) ;;
    *) refuse "$name is not an http:// or https:// base URL: $url" ;;
  esac
  case "$url" in
    *[!A-Za-z0-9._~:/@%+=,-]*) refuse "$name holds a character a base URL does not need: $url" ;;
  esac
  rest=${url#*://}
  case "${rest%%/*}" in
    *@*) refuse "$name carries credentials, and the image's build history records it: name a mirror that needs none" ;;
  esac
  while [ "${url%/}" != "$url" ]; do
    url=${url%/}
  done
  case "$url" in
    *://*/debian | *://*/debian-security)
      refuse "$name names an archive path; give its base, such as http://ftp.example.org/ for http://ftp.example.org/debian/: $2"
      ;;
  esac
  printf '%s\n' "$url"
}

if [ "$#" -eq 0 ]; then
  refuse "name the packages to install"
fi

ca=/run/secrets/build_ca
debian=${DEBIAN_MIRROR:-}
security=${DEBIAN_SECURITY_MIRROR:-$debian}

if [ -s "$ca" ] || [ -n "$debian" ] || [ -n "$security" ]; then
  if [ -s "$ca" ]; then
    default=https://deb.debian.org
  else
    default=http://deb.debian.org
  fi

  if [ -n "$debian" ]; then
    debian=$(mirror_base DEBIAN_MIRROR "$debian")
  else
    debian=$default
  fi
  if [ -n "${DEBIAN_SECURITY_MIRROR:-}" ]; then
    security=$(mirror_base DEBIAN_SECURITY_MIRROR "$security")
  else
    security=$debian
  fi

  if [ ! -s "$ca" ] && [ ! -s /etc/ssl/certs/ca-certificates.crt ]; then
    case "$debian $security" in
      *https://*) refuse "an https:// mirror needs a CA to verify it, and this stage has none: pass the build secret build_ca, or name the mirror with http://" ;;
    esac
  fi

  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  mkdir "$work/sources.list.d"
  : >"$work/sources.list"

  # The two archives' URIs go to placeholders no base URL can hold first, so
  # a mirror keeps the scheme written for it; whatever still names
  # deb.debian.org then takes the default scheme.
  for source in /etc/apt/sources.list \
    /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [ -f "$source" ] || continue
    sed -e 's|http://deb\.debian\.org/debian-security\([[:space:]]\)|<security>/debian-security\1|g' \
      -e 's|http://deb\.debian\.org/debian-security$|<security>/debian-security|' \
      -e 's|http://deb\.debian\.org/debian\([[:space:]]\)|<debian>/debian\1|g' \
      -e 's|http://deb\.debian\.org/debian$|<debian>/debian|' \
      -e "s|http://deb\.debian\.org/|$default/|g" \
      -e "s|<security>|$security|g" \
      -e "s|<debian>|$debian|g" \
      "$source" >"$work/${source#/etc/apt/}"
  done

  {
    echo "Dir::Etc::SourceList \"$work/sources.list\";"
    echo "Dir::Etc::SourceParts \"$work/sources.list.d\";"
    if [ -s "$ca" ]; then
      echo "Acquire::https::CAInfo \"$ca\";"
    fi
  } >"$work/apt.conf"
  export APT_CONFIG="$work/apt.conf"

  # apt reads the proxy only from the lower-case variables, and Docker's
  # predefined proxy build arguments come in either case. A lower-case value
  # already set is kept.
  if [ -z "${http_proxy:-}" ] && [ -n "${HTTP_PROXY:-}" ]; then
    export http_proxy="$HTTP_PROXY"
  fi
  if [ -z "${https_proxy:-}" ] && [ -n "${HTTPS_PROXY:-}" ]; then
    export https_proxy="$HTTPS_PROXY"
  fi
  if [ -z "${no_proxy:-}" ] && [ -n "${NO_PROXY:-}" ]; then
    export no_proxy="$NO_PROXY"
  fi
fi

apt-get update
apt-get install -y --no-install-recommends "$@"
rm -rf /var/lib/apt/lists/*
