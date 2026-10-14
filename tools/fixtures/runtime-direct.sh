#!/bin/sh
# Isolated OpenWrt-only fixture; never use on a real router.
set -eu
uci -q set telemt.general.enabled=1
uci -q set telemt.general.port=18443
uci -q set telemt.general.mode=tls
uci -q set telemt.general.domain=google.com
uci -q set telemt.general.metrics_port=19092
uci -q set telemt.general.api_port=19091
uci -q set telemt.general.auto_fw=0
uci -q set telemt.general.use_middle_proxy=0
uci -q set telemt.ci_runtime=user
uci -q set telemt.ci_runtime.secret=0123456789abcdef0123456789abcdef
uci -q set telemt.ci_runtime.enabled=1
uci -q set telemt.web.enabled=0
uci -q commit telemt
/etc/init.d/telemt restart
sleep 3
test -s /tmp/etc/telemt.toml
pidof telemt >/dev/null
