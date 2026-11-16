#!/bin/sh
# Verify the KCD:MP server archive before uploading it to the panel node.
#
# The pinned hash is the one the download page published for the release that
# shipped windows/ and linux/ as of 2026-11-16. A new release has a new hash:
# update EXPECTED here (or export KCDMP_SHA256) before trusting this check.
#
# Usage: scripts/verify-server.sh <path to the downloaded archive>
set -eu

EXPECTED="${KCDMP_SHA256:-d17d5242d1cd1db20742edfd35c43a80ca784ad21ef06fb959217d3b60289287}"

if [ $# -ne 1 ]; then
  echo "usage: $0 <archive>" >&2
  exit 2
fi

if [ ! -f "$1" ]; then
  echo "no such file: $1" >&2
  exit 2
fi

actual=$(sha256sum "$1" | cut -d' ' -f1)

echo "expected: $EXPECTED"
echo "actual:   $actual"

if [ "$actual" = "$EXPECTED" ]; then
  echo "OK - the archive matches the pinned hash"
else
  echo "MISMATCH - do not upload this archive: either it was truncated in transit or it is a different release" >&2
  exit 1
fi
