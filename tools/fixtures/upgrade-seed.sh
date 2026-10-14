#!/bin/sh
# Synthetic old installation, provisioned with real UCI inside isolated OpenWrt.
set -eu
uci -q set telemt.general=telemt
uci -q set telemt.general.enabled=0
uci -q set telemt.general.mode=tls
uci -q set telemt.general.port=18443
uci -q set telemt.general.metrics_port=9091
uci -q set telemt.general.api_port=9191
uci -q set telemt.general.domain=example.org
uci -q set telemt.general.auto_fw=0
uci -q set telemt.ci_alice=user
uci -q set telemt.ci_alice.secret=0123456789abcdef0123456789abcdef
uci -q set telemt.ci_alice.max_connections=9
uci -q set telemt.ci_socks=upstream
uci -q set telemt.ci_socks.type=socks5
uci -q set telemt.ci_socks.address=127.0.0.1:1080
uci -q set telemt.web=web
uci -q set telemt.web.enabled=0
uci -q set telemt.web.carrier=websocket
uci -q delete telemt.web.carrier_candidate || true
uci -q add_list telemt.web.carrier_candidate=https
uci -q set telemt.web_listener=web_listener
uci -q set telemt.web_listener.port=28653
uci -q set telemt.web_listener.ip=127.0.0.1
uci -q delete telemt.web_listener.trusted_proxy_cidr || true
uci -q add_list telemt.web_listener.trusted_proxy_cidr=10.10.0.0/16
uci -q set telemt.ci_vhost=web_vhost
uci -q set telemt.ci_vhost.hostname=proxy.example.invalid
uci -q set telemt.ci_profile=web_profile
uci -q set telemt.ci_profile.user=ci_alice
uci -q set telemt.ci_profile.vhost=ci_vhost
uci -q commit telemt
