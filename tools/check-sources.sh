#!/bin/bash
# Source-level contract checks for the telemt core package. Needs no OpenWrt:
# shell syntax of every shipped script plus the generator/UCI/WEB contracts the
# rest of the stack (LuCI, frontends) relies on.
set -euo pipefail
cd "$(dirname "$0")/.."

for f in files/telemt.init files/telemt-web-check files/telemt-web-frontend \
         files/telemt-web-nginx files/telemt-web-haproxy.hotplug \
         scripts/postinst scripts/prerm scripts/postrm; do
    sh -n "$f"
done

# One base version in version.txt: bare X.Y.Z.
grep -qxE '[0-9]+\.[0-9]+\.[0-9]+' version.txt

# Legacy LuCI needs the named 'general' section even on upgraded installations.
# Only recreate an absent section; never overwrite an existing section or its options.
grep -q 'if ! has_section general; then' scripts/postinst
grep -q 'ensure_section general telemt' scripts/postinst
grep -q 'ensure_option general enabled 0' scripts/postinst
grep -q 'unexpected UCI type' scripts/postinst

grep -q 'ensure_section web web' scripts/postinst
grep -q 'ensure_option web enabled 0' scripts/postinst
grep -q 'ensure_section web_listener web_listener' scripts/postinst
grep -q 'uci -q commit telemt' scripts/postinst

grep -q "option port '27453'" files/telemt.config
grep -q "option nginx_managed '0'" files/telemt.config
grep -q "option nginx_bind '443'" files/telemt.config
grep -q "option direct_relay_buffer_budget_max_mib '0'" files/telemt.config
grep -q 'direct_relay_buffer_budget_max_bytes = $direct_relay_buffer_budget_max_bytes' files/telemt.init
grep -q 'config_get web_port web_listener port "27453"' files/telemt.init

# 3.5.8: WEB version gate and [web.debug] sideband (default off)
grep -q 'telemt_ver_ge 3 5 6' files/telemt.init
grep -q 'telemt_ver_ge 3 5 8' files/telemt.init
grep -q '^\[web.debug\]' files/telemt.init
grep -q 'sideband = ' files/telemt.init
grep -q 'capture_lifecycle = ' files/telemt.init
grep -q "option debug_sideband '0'" files/telemt.config
grep -q "option debug_capture_lifecycle '0'" files/telemt.config
grep -q 'ensure_option web debug_sideband 0' scripts/postinst

grep -q 'https|https-lanes|websocket|websocket-lanes) ;;' files/telemt.init
grep -q 'web_carrier="https"' files/telemt.init
grep -q 'carrier = "$web_carrier"' files/telemt.init
grep -q "option carrier_policy 'fixed'" files/telemt.config
grep -q "list carrier_candidate 'websocket-lanes'" files/telemt.config
grep -q "list carrier_candidate 'websocket'" files/telemt.config
grep -q "list carrier_candidate 'https-lanes'" files/telemt.config
grep -q "option carrier_learning '1'" files/telemt.config
grep -q "option carrier_negotiation_aggressiveness 'conservative'" files/telemt.config
grep -q 'WEB auto carrier policy requires at least one carrier_candidate' files/telemt.init
grep -q 'duplicate WEB auto carrier candidate' files/telemt.init

grep -q 'alpn h2,http/1.1' files/telemt-web-frontend
grep -q 'retries 0' files/telemt-web-frontend
grep -q 'http2 on;' files/telemt-web-nginx
grep -q 'proxy_http_version 1.1;' files/telemt-web-nginx
grep -q 'proxy_set_header Upgrade $http_upgrade;' files/telemt-web-nginx
grep -q 'proxy_set_header Connection $telemt_connection_upgrade;' files/telemt-web-nginx
grep -q 'proxy_next_upstream off;' files/telemt-web-nginx

if grep -R -n -E "option port '18080'|port = 18080|127\\.0\\.0\\.1:18080|127\\.0\\.0\\.1:18081" \
  ROADMAP_3.5_WEB.md docs/WEB_EXTERNAL_FRONTEND.ru.md docs/WEB_HAPROXY_MANAGED.ru.md \
  files/telemt.config files/telemt.init files/telemt-web-check files/telemt-web-frontend files/telemt-web-nginx; then
  echo 'ERROR: stale 1808x WEB endpoint found' >&2
  exit 1
fi

# Disabled WEB must stay isolated: strict carrier_candidate validation runs only
# when WEB itself is enabled.
grep -Fq 'if [ "$web_enabled" -eq 1 ] && [ "$web_carrier_policy" = "auto" ]; then' files/telemt.init

# A second policy-only guard is expected only for TOML emission after
# web_runtime_enabled has already gated the whole [web] block.
test "$(grep -Fc 'if [ "$web_carrier_policy" = "auto" ]; then' files/telemt.init)" -eq 1

# Keep the strict enabled-WEB behaviour intact.
grep -Fq 'WEB auto carrier policy requires at least one carrier_candidate' files/telemt.init
grep -Fq 'invalid WEB auto carrier candidate' files/telemt.init
grep -Fq 'duplicate WEB auto carrier candidate' files/telemt.init

echo 'source contracts ok'
