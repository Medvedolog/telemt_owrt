#!/bin/sh
# End-to-end CBI render with missing/wrong-type telemt.general after core install.
set -eu
cd "$(dirname "$0")/.."
for scenario in missing wrong; do
    config="tools/owlab-luci-general-$scenario.yaml"
    cleanup() { owlab --config "$config" down --purge || true; }
    trap cleanup EXIT HUP INT TERM
    owlab --config "$config" test \
        --install "$PWD/dist/x86_64/telemt*" \
        --install "$PWD/luci_src/dist/*/luci-app-telemt*" \
        --sync --keep \
        --assert 'package telemt' \
        --assert 'package luci-app-telemt' \
        --assert 'http 200 /cgi-bin/luci/admin/services/telemt' \
        --assert 'exec test "$(uci -q get telemt.ci_probe.secret)" = 0123456789abcdef0123456789abcdef'
    python3 tools/test-luci-general-http.py "$scenario"
    for router in general-2410 general-2512; do
        if [ "$scenario" = missing ]; then
            owlab --config "$config" exec "$router" -- 'test -z "$(uci -q get telemt.general 2>/dev/null || true)"'
        else
            owlab --config "$config" exec "$router" -- 'test "$(uci -q get telemt.general)" = incorrect_type'
        fi
        owlab --config "$config" exec "$router" -- 'test "$(uci -q get telemt.ci_probe.secret)" = 0123456789abcdef0123456789abcdef'
    done
    cleanup
    trap - EXIT HUP INT TERM
done
