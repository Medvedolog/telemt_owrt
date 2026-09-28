#!/bin/sh
# Resolve the release version. Prints two shell assignments:
#
#   BASE_VERSION=3.5.8      upstream Telemt version (the tag of telemt/telemt to build)
#   PKG_VERSION=3.5.8-r1    package version handed to owfeed
#
# Source: an explicit argument, else the git tag being built, else version.txt.
#   X.Y.Z    -> X.Y.Z-r1        X.Y.Z-N  -> X.Y.Z-rN        X.Y.Z-rN -> as given
# The base version must equal version.txt, so a tag can never build a different
# Telemt than the one the repository was validated against.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$#" -gt 0 ]; then
    VERSION="$1"
elif [ "${GITHUB_REF_TYPE:-}" = "tag" ] && [ -n "${GITHUB_REF_NAME:-}" ]; then
    VERSION="$GITHUB_REF_NAME"
else
    VERSION="$(tr -d '[:space:]' < "$ROOT/version.txt")"
fi
VERSION="${VERSION#v}"

case "$VERSION" in
    [0-9]*.[0-9]*.[0-9]*-r[0-9]*) BASE="${VERSION%-r*}"; REV="${VERSION##*-r}" ;;
    [0-9]*.[0-9]*.[0-9]*-[0-9]*)  BASE="${VERSION%-*}";  REV="${VERSION##*-}" ;;
    [0-9]*.[0-9]*.[0-9]*)         BASE="$VERSION";       REV=1 ;;
    *) echo "unsupported version/tag: $VERSION" >&2; exit 1 ;;
esac
echo "$BASE" | grep -qxE '[0-9]+\.[0-9]+\.[0-9]+' || { echo "bad base version: $BASE" >&2; exit 1; }
echo "$REV" | grep -qxE '[0-9]+' || { echo "bad revision: $REV" >&2; exit 1; }

TXT="$(tr -d '[:space:]' < "$ROOT/version.txt")"
[ "$TXT" = "$BASE" ] || { echo "version mismatch: release=$BASE, version.txt=$TXT" >&2; exit 1; }

printf 'BASE_VERSION=%s\nPKG_VERSION=%s-r%s\n' "$BASE" "$BASE" "$REV"
