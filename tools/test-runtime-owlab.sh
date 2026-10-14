#!/bin/sh
# Full packaged-binary/procd/generator smoke on OpenWrt 24.10 and 25.12.
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
    [ "$#" -eq 1 ] && [ -f "$1" ] || exit 2
    owlab --config "$config" install "$router" "$1"
    echo "Test $router: packaged daemon, direct TOML and procd"
    owlab --config "$config" exec "$router" -- sh -s < tools/fixtures/runtime-direct.sh
    python3 tools/test-runtime-toml.py "$router" direct
    echo "Test $router: WEB TOML, profile binding and local listener"
    owlab --config "$config" exec "$router" -- sh -s < tools/fixtures/runtime-web.sh
    python3 tools/test-runtime-toml.py "$router" web
    echo "Test $router: Middle Proxy TOML (network-independent)"
    owlab --config "$config" exec "$router" -- sh -s < tools/fixtures/runtime-me.sh
    python3 tools/test-runtime-toml.py "$router" me
done
