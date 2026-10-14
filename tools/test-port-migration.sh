#!/bin/sh
# Exercise the production port-migration fragment with a mocked UCI.
set -eu
cd "$(dirname "$0")/.."
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT HUP INT TERM
awk '
  /^# BEGIN_TESTABLE_PORT_MIGRATION$/ { capture=1; next }
  /^# END_TESTABLE_PORT_MIGRATION$/ { capture=0; next }
  capture { print }
' scripts/postinst > "$tmp"
[ -s "$tmp" ] || exit 1
run_case() (
    metrics="$1"
    api="$2"
    want_warning="$3"
    warnings=0
    uci() {
        case "$1 $2 $3" in
            "-q get telemt.general.metrics_port") [ -n "$metrics" ] || return 1; printf '%s\n' "$metrics" ;;
            "-q get telemt.general.api_port") [ -n "$api" ] || return 1; printf '%s\n' "$api" ;;
            *) echo "unexpected UCI mutation or access: $*" >&2; exit 90 ;;
        esac
    }
    logger() { warnings=$((warnings+1)); }
    . "$tmp"
    [ "$warnings" -eq "$want_warning" ] || exit 91
)
run_case 9090 9091 0
run_case 9091 9092 0
run_case 9091 9091 1
run_case 9091 '' 1
run_case 9001 9002 0
run_case 9001 9001 1
run_case '' '' 0
echo "port migration: operator values preserved; conflicts flagged"
