#!/bin/sh
set -eu
[ "$(uci -q get telemt.general)" = telemt ]
[ "$(uci -q get telemt.general.enabled)" = 0 ]
[ "$(uci -q get telemt.web.carrier_candidate)" = https ]
[ "$(uci -q get telemt.web_listener.trusted_proxy_cidr)" = 10.10.0.0/16 ]
[ "$(uci -q get telemt.ci_alice.secret)" = 0123456789abcdef0123456789abcdef ]
[ "$(uci -q get telemt.ci_socks.address)" = 127.0.0.1:1080 ]
[ "$(uci -q get telemt.ci_profile.vhost)" = ci_vhost ]
echo "Missing general repaired without destroying independent sections"
