#!/bin/sh
# Package-specific assertions against every built IPK (one per architecture). APK
# and IPK come from the same staged tree; owfeed itself validates both containers.
set -eu
cd "$(dirname "$0")/.."

eval "$(tools/version.sh "$@")"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

n=0
for ipk in dist/*/telemt_*.ipk; do
    [ -f "$ipk" ] || continue
    n=$((n + 1))
    d="$work/$n"
    mkdir -p "$d/control" "$d/data"
    tar xzf "$ipk" -C "$d"
    tar xzf "$d/control.tar.gz" -C "$d/control"
    tar xzf "$d/data.tar.gz" -C "$d/data"
    echo "--- $ipk ---"
    sed -n '/^\(Package\|Version\|Architecture\|Depends\):/p' "$d/control/control"

    grep -qx "Version: $PKG_VERSION" "$d/control/control" || { echo "wrong Version in $ipk" >&2; exit 1; }

    for f in ./usr/bin/telemt ./etc/init.d/telemt ./usr/libexec/telemt-web-check \
             ./usr/libexec/telemt-web-frontend ./usr/libexec/telemt-web-nginx \
             ./etc/hotplug.d/acme/95-telemt-web-haproxy; do
        [ -f "$d/data/$f" ] || { echo "missing from $ipk: $f" >&2; exit 1; }
        [ -x "$d/data/$f" ] || { echo "not executable in $ipk: $f" >&2; exit 1; }
    done
    [ -f "$d/data/etc/config/telemt" ] || { echo "missing /etc/config/telemt in $ipk" >&2; exit 1; }
    grep -qx '/etc/config/telemt' "$d/control/conffiles" 2>/dev/null || {
        echo "/etc/config/telemt is not a conffile in $ipk" >&2; exit 1
    }
    tail -c 512 "$d/data/usr/bin/telemt" | grep -a -q "MTProxy v${BASE_VERSION}" || {
        echo "telemt binary in $ipk lacks the MTProxy v${BASE_VERSION} trailer" >&2; exit 1
    }
    for s in postinst prerm postrm; do
        [ -f "$d/control/$s" ] || { echo "maintainer script missing in $ipk: $s" >&2; exit 1; }
    done
done
[ "$n" -eq 3 ] || { echo "expected 3 architecture IPKs, found $n" >&2; exit 1; }

echo "package checks passed ($n architectures, $PKG_VERSION)"
