#!/bin/sh
# Stage the telemt core package as per-architecture router filesystems for owfeed/mkpkg.
#
#   AARCH64_BIN=... X86_64_BIN=... tools/stage.sh [VERSION]
#
# Both binaries must already carry the "MTProxy vX.Y.Z" trailer the init script
# uses to detect the version. Output: dist/stage/<arch>/, dist/scripts/, dist/VERSION.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/dist}"

eval "$("$ROOT/tools/version.sh" "$@")"

: "${AARCH64_BIN:?AARCH64_BIN is required}"
: "${X86_64_BIN:?X86_64_BIN is required}"
# The TELEMT License requires the license text and notices to travel with every
# redistributed binary, so the upstream LICENSE is a required input.
: "${UPSTREAM_LICENSE:?UPSTREAM_LICENSE (upstream LICENSE file) is required}"
[ -s "$UPSTREAM_LICENSE" ] || { echo "upstream license missing or empty: $UPSTREAM_LICENSE" >&2; exit 1; }
grep -qi 'TELEMT LICENSE' "$UPSTREAM_LICENSE" || { echo "unexpected upstream license: $UPSTREAM_LICENSE" >&2; exit 1; }
for b in "$AARCH64_BIN" "$X86_64_BIN"; do
    [ -s "$b" ] || { echo "binary missing or empty: $b" >&2; exit 1; }
    tail -c 512 "$b" | grep -a -q "MTProxy v${BASE_VERSION}" || {
        echo "binary lacks the MTProxy v${BASE_VERSION} trailer: $b" >&2; exit 1
    }
done

# Normalise line endings: shipped shell must be LF-only.
norm() { sed -e '1s/^\xef\xbb\xbf//' -e 's/\r$//' "$1"; }

rm -rf "$OUT/stage" "$OUT/scripts"
mkdir -p "$OUT/stage" "$OUT/scripts"
printf '%s\n' "$PKG_VERSION" > "$OUT/VERSION"

for arch in aarch64_generic aarch64_cortex-a53 x86_64; do
    root="$OUT/stage/$arch"
    mkdir -p "$root/usr/bin" "$root/usr/libexec" "$root/etc/init.d" "$root/etc/config" "$root/etc/hotplug.d/acme"

    if [ "$arch" = x86_64 ]; then bin="$X86_64_BIN"; else bin="$AARCH64_BIN"; fi
    install -m 0755 "$bin" "$root/usr/bin/telemt"

    norm "$ROOT/files/telemt.init"                 > "$root/etc/init.d/telemt"
    norm "$ROOT/files/telemt-web-check"            > "$root/usr/libexec/telemt-web-check"
    norm "$ROOT/files/telemt-web-frontend"         > "$root/usr/libexec/telemt-web-frontend"
    norm "$ROOT/files/telemt-web-nginx"            > "$root/usr/libexec/telemt-web-nginx"
    norm "$ROOT/files/telemt-web-haproxy.hotplug"  > "$root/etc/hotplug.d/acme/95-telemt-web-haproxy"
    norm "$ROOT/files/telemt.config"               > "$root/etc/config/telemt"
    chmod 0755 "$root/etc/init.d/telemt" "$root/usr/libexec/telemt-web-check" \
        "$root/usr/libexec/telemt-web-frontend" "$root/usr/libexec/telemt-web-nginx" \
        "$root/etc/hotplug.d/acme/95-telemt-web-haproxy"
    chmod 0644 "$root/etc/config/telemt"

    lic="$root/usr/share/licenses/telemt"
    mkdir -p "$lic"
    install -m 0644 "$UPSTREAM_LICENSE" "$lic/TELEMT-LICENSE"
    install -m 0644 "$ROOT/LICENSE" "$lic/LICENSE-openwrt-integration"
    cat > "$lic/NOTICE" <<NOTICE
telemt ${BASE_VERSION} — OpenWrt package

The telemt binary is the work of the Telemt authors (https://github.com/telemt/telemt),
distributed under the TELEMT License; its full text is TELEMT-LICENSE in this directory.

This package is an unofficial OpenWrt redistribution by Medvedolog, not an official
Telemt release. The binary differs from the upstream artifact: it carries an appended
"MTProxy v${BASE_VERSION}" version marker, and the aarch64 build is compiled from the
unmodified upstream source with size-oriented release settings and UPX compression.

The init script, UCI defaults, WEB frontend helpers and maintainer scripts are
distributed under the MIT License (LICENSE-openwrt-integration).
NOTICE
    chmod 0644 "$lic/NOTICE"
done

for s in postinst prerm postrm; do
    norm "$ROOT/scripts/$s" > "$OUT/scripts/$s"
    chmod 0755 "$OUT/scripts/$s"
done

echo "staged telemt $PKG_VERSION (upstream $BASE_VERSION)"
