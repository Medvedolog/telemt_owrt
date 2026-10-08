#!/bin/sh
# Execute the *actual* general-section migration fragment from postinst with
# stub UCI functions. Never touches /etc/config or any router service.
set -eu
cd "$(dirname "$0")/.."

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT HUP INT TERM
awk '
  /^# BEGIN_TESTABLE_GENERAL_MIGRATION$/ { copying=1; next }
  /^# END_TESTABLE_GENERAL_MIGRATION$/ { copying=0; next }
  copying { print }
' scripts/postinst > "$tmp"
[ -s "$tmp" ] || { echo "missing migration fixture" >&2; exit 1; }
grep -q '^if ! has_section general; then' "$tmp"
grep -q '^if \[ "\$(uci -q get telemt.general' "$tmp"

run_case() (
    general_exists="$1"
    general_type="$2"
    enabled="$3"
    expected_exists="$4"
    expected_type="$5"
    expected_enabled="$6"
    expected_creates="$7"
    expected_options="$8"
    created=0
    options=0

    has_section() {
        [ "$1" = general ] && [ "$general_exists" = 1 ]
    }
    ensure_section() {
        [ "$1" = general ] && [ "$2" = telemt ] || exit 80
        general_exists=1
        general_type=telemt
        created=$((created + 1))
    }
    ensure_option() {
        [ "$1" = general ] && [ "$2" = enabled ] || exit 81
        options=$((options + 1))
        if [ "$enabled" = '<unset>' ]; then enabled="$3"; fi
    }
    uci() {
        [ "$1" = '-q' ] && [ "$2" = get ] &&
          [ "$3" = telemt.general ] || return 82
        [ "$general_exists" = 1 ] || return 1
        printf '%s\n' "$general_type"
    }
    logger() { :; }

    . "$tmp"
    [ "$general_exists" = "$expected_exists" ]
    [ "$general_type" = "$expected_type" ]
    [ "$enabled" = "$expected_enabled" ]
    [ "$created" = "$expected_creates" ]
    [ "$options" = "$expected_options" ]
)

# Fresh/missing section: safe disabled default is created.
run_case 0 missing '<unset>' 1 telemt 0 1 1
# Existing operator-managed config must not be changed or reinitialized.
run_case 1 telemt 1 1 telemt 1 0 0
# Wrong-type section is logged for review, never silently overwritten.
run_case 1 wrong_type 1 1 wrong_type 1 0 0

echo "general migration: missing/existing/wrong-type cases passed"
