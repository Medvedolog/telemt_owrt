#!/bin/sh
# A valid local WEB frontend fixture; real client connectivity is not tested.
set -eu
uci -q set telemt.web.enabled=1
uci -q set telemt.web.carrier=https
uci -q set telemt.web.carrier_policy=fixed
uci -q set telemt.web_listener.enabled=1
uci -q set telemt.web_listener.ip=127.0.0.1
uci -q set telemt.web_listener.port=27453
uci -q set telemt.ci_web_vhost=web_vhost
uci -q set telemt.ci_web_vhost.enabled=1
uci -q set telemt.ci_web_vhost.name=ci_front
uci -q set telemt.ci_web_vhost.host=proxy.example.org
uci -q set telemt.ci_web_vhost.public_addr=127.0.0.1:443
uci -q set telemt.ci_web_vhost.decoy_mode=http_upstream
uci -q set telemt.ci_web_vhost.decoy_upstream=http://127.0.0.1:8080
uci -q set telemt.ci_web_profile=web_profile
uci -q set telemt.ci_web_profile.enabled=1
uci -q set telemt.ci_web_profile.vhost=ci_front
uci -q set telemt.ci_web_profile.user=ci_runtime
uci -q set telemt.ci_web_profile.secret_mode=dd
uci -q commit telemt
/etc/init.d/telemt restart
sleep 3
test -s /tmp/etc/telemt.toml
pidof telemt >/dev/null
