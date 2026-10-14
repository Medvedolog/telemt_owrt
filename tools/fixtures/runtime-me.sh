#!/bin/sh
set -eu
uci -q set telemt.web.enabled=0
uci -q set telemt.general.use_middle_proxy=1
uci -q commit telemt
/etc/init.d/telemt restart
sleep 2
test -s /tmp/etc/telemt.toml
# Middle Proxy needs the Telegram network for useful live sessions. Only
# validate the generated TOML here, not external connectivity.
