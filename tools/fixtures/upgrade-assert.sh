#!/bin/sh
# Deliberately do not print the full config: it contains synthetic secrets.
set -eu
check() {
    got="$(uci -q get "telemt.$1" || true)"
    [ "$got" = "$2" ] || {
        echo "UCI preservation failed at $1" >&2
        exit 1
    }
}
check general telemt
check general.enabled 0
check general.port 18443
check general.metrics_port 9091
check general.api_port 9191
check general.domain example.org
check ci_alice user
check ci_alice.secret 0123456789abcdef0123456789abcdef
check ci_alice.max_connections 9
check ci_socks upstream
check ci_socks.type socks5
check ci_socks.address 127.0.0.1:1080
check web web
check web.enabled 0
check web.carrier websocket
check web.carrier_candidate https
check web.nginx_managed 0
check web_listener web_listener
check web_listener.port 28653
check web_listener.trusted_proxy_cidr 10.10.0.0/16
check ci_vhost web_vhost
check ci_vhost.hostname proxy.example.invalid
check ci_profile web_profile
check ci_profile.user ci_alice
check ci_profile.vhost ci_vhost
echo "UCI old config, users, upstream, WEB bindings and operator lists preserved"
