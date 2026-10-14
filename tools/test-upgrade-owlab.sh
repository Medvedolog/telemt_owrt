#!/bin/sh
# Full-package upgrade test on real OpenWrt UCI: 24.10 IPK + 25.12 APK.
# Requires owlab v0.6.5 and built packages in dist/x86_64.
set -eu
cd "$(dirname "$0")/.."
config=tools/owlab-upgrade.yaml
cleanup() { owlab --config "$config" down --purge || true; }
trap cleanup EXIT HUP INT TERM
owlab --config "$config" up

for router in upgrade-ipk upgrade-apk; do
    case "$router" in
        upgrade-ipk) set -- dist/x86_64/telemt_*.ipk ;;
        upgrade-apk) set -- dist/x86_64/telemt-*.apk ;;
    esac
    [ "$#" -eq 1 ] && [ -f "$1" ] || {
        echo "Expected exactly one built core package for $router" >&2
        exit 1
    }
    package="$1"
    echo "Testing $router: seed old config -> package install -> postinst twice"
    owlab --config "$config" exec "$router" -- sh -s < tools/fixtures/upgrade-seed.sh
    owlab --config "$config" install "$router" "$package"
    owlab --config "$config" exec "$router" -- sh -s < tools/fixtures/upgrade-assert.sh
    owlab --config "$config" exec "$router" -- 'uci -q export telemt > /tmp/telemt-first.uci'
    # Execute the entire real maintainer script, not a copied migration snippet.
    owlab --config "$config" exec "$router" -- sh -s < scripts/postinst
    owlab --config "$config" exec "$router" -- sh -s < scripts/postinst
    owlab --config "$config" exec "$router" -- sh -s < tools/fixtures/upgrade-assert.sh
    owlab --config "$config" exec "$router" -- 'uci -q export telemt > /tmp/telemt-repeated.uci; cmp -s /tmp/telemt-first.uci /tmp/telemt-repeated.uci'

    echo "Testing $router: recover missing named general without losing other sections"
    owlab --config "$config" exec "$router" -- 'uci -q delete telemt.general; uci -q commit telemt'
    owlab --config "$config" exec "$router" -- sh -s < scripts/postinst
    owlab --config "$config" exec "$router" -- sh -s < tools/fixtures/upgrade-missing.sh

    echo "Testing $router: wrong-type general must not be overwritten"
    owlab --config "$config" exec "$router" -- 'uci -q set telemt.general=other; uci -q commit telemt'
    owlab --config "$config" exec "$router" -- sh -s < scripts/postinst
    owlab --config "$config" exec "$router" -- '[ "$(uci -q get telemt.general)" = other ] && [ "$(uci -q get telemt.ci_alice.secret)" = 0123456789abcdef0123456789abcdef ]'
    echo "$router upgrade integration: OK"
done
