# Техническое задание — Telemt 3.5.6 WEB Proxy для OpenWrt

Версия ТЗ: 2026-09-09

## 1. Назначение

Добавить в `telemt_owrt` и `luci-app-telemt` полноценную поддержку Telemt `3.5.6 Machtprobe` WEB Proxy для Telegram Desktop, не ломая существующие Classic/DD/FakeTLS сценарии и не создавая второй слой конфигурации поверх UCI.

Проекты:

- core/package: `Medvedolog/telemt_owrt`
- LuCI: `Medvedolog/luci-app-telemt`
- development branches: `telemt-3.5.6-web`
- upstream target: `telemt/telemt` tag `3.5.6`, commit `3693d1e2a87af0074598104338b5a4bb5bee202d`

Upstream references:

- https://github.com/telemt/telemt/releases/tag/3.5.6
- https://github.com/telemt/telemt/blob/3.5.6/docs/WEB/WEB_PROXY.ru.md

## 2. Главные архитектурные правила

### 2.1. UCI — единственный source of truth

```text
/etc/config/telemt
       │
       ├── LuCI / uci CLI
       │
       └── /etc/init.d/telemt
                │
                └── /tmp/etc/telemt.toml
                         │
                         └── Telemt
```

Обязательно:

- persistent конфигурация существует только в `/etc/config/telemt`;
- runtime TOML полностью регенерируется из UCI;
- Telemt не модифицирует UCI;
- LuCI не пишет TOML напрямую;
- Telemt config PATCH API не используется как второй persistent backend;
- runtime TOML считается disposable artifact.

### 2.2. Одна база пользователей

`config user` — единственная сущность пользователя для:

- Classic;
- DD;
- FakeTLS;
- WEB plain;
- WEB dd.

WEB profile обязан содержать ссылку на существующего user, но не копию:

- secret;
- enabled;
- quota;
- expiration;
- max TCP connections;
- max unique IPs.

Пример:

```uci
config user 'medved'
        option secret '0123456789abcdef0123456789abcdef'
        option enabled '1'
        option data_quota '50'

config web_profile
        option enabled '1'
        option vhost 'main'
        option user 'medved'
        option secret_mode 'dd'
```

Если shared user выключен, его WEB profile не должен попадать в runtime TOML.

### 2.3. WEB ingress

Canonical topology:

```text
Telegram Desktop
      │ HTTPS/WSS :443
      ▼
External TLS frontend / HAProxy / NGINX
      │ plain HTTP/1.1
      │ X-Forwarded-For
      ▼
Telemt WEB 127.0.0.1:27453
```

Правила:

- Telemt сам TLS для WEB не терминирует;
- WEB backend по умолчанию loopback-only;
- backend порт по умолчанию `27453`;
- `proxy_protocol=false`;
- `reuse_allow=false`;
- `web_client_ip_source="x_forwarded_for"`;
- trusted CIDR описывает только непосредственный TLS frontend peer;
- `/0` в trusted proxy CIDR запрещён;
- WEB listener не наследует MTProxy-only `client_mss`, `synlimit`, `announce`, `announce_ip`.

## 3. Совместимость со старым core

Миграция на 3.5.6 не должна требовать ручного переписывания существующего 3.4.x UCI.

Не переписывать без реальной необходимости:

- Users generation;
- quota/expiration;
- accumulated stats;
- Upstreams;
- Middle-End;
- classic firewall path;
- API/metrics path;
- `# --- DYNAMIC CONFIG ---` reload marker.

WEB по умолчанию выключен и не должен менять legacy ingress после package upgrade.

## 4. Version detection

Основной путь обязан быть пассивным и дешёвым:

1. `tail -c 512 /usr/bin/telemt`;
2. поиск embedded trailer `MTProxy vX.Y.Z`;
3. cache `/tmp/etc/telemt.version`;
4. legacy full-binary embedded marker fallback;
5. только затем `telemt --version`;
6. затем `telemt -V`;
7. иначе version unknown.

`strings` не использовать в normal path.

## 5. UCI WEB schema

### 5.1. Global WEB

```uci
config web 'web'
        option enabled '0'
        option carrier_policy 'fixed'
        option carrier 'https'
        option memory_profile 'standard'
        option tls_terminator 'external'
        option debug_enabled '0'
```

Дополнительные frontend options могут находиться в том же section, но должны иметь явный namespace `haproxy_*` / `nginx_*`.

### 5.2. Listener

```uci
config web_listener 'web_listener'
        option enabled '1'
        option ip '127.0.0.1'
        option port '27453'
        option client_ip_source 'x_forwarded_for'
        list trusted_proxy_cidr '127.0.0.1/32'
```

### 5.3. VHost

```uci
config web_vhost
        option enabled '1'
        option name 'main'
        option host 'proxy.example.com'
        option public_addr '203.0.113.10:443'
        option decoy_mode 'http_upstream'
        option decoy_upstream 'http://127.0.0.1:27454'
```

Требования:

- `1..N` vhosts;
- уникальный logical name;
- уникальный FQDN;
- `public_addr` — concrete IP `:443`;
- первый stable scope: `http_upstream` decoy;
- decoy origin — `http://IP[:port]`, без credential/query/fragment.

### 5.4. WEB profile

```uci
config web_profile
        option enabled '1'
        option vhost 'main'
        option user 'medved'
        option secret_mode 'dd'
        option max_sessions ''
        option max_streams ''
        option max_streams_per_session ''
```

Требования:

- `1..N` profiles;
- `user` ссылается на `config user`;
- secret modes только `plain|dd`;
- FakeTLS `ee` запрещён для WEB;
- optional limits только positive integer;
- profile на missing/disabled vhost считается configuration error;
- disabled shared user не делает dangling runtime profile.

## 6. TOML generation

При активном WEB должен появляться отдельный listener:

```toml
[[server.listeners]]
ip = "127.0.0.1"
port = 27453
transport = "web"
proxy_protocol = false
reuse_allow = false
web_client_ip_source = "x_forwarded_for"
web_trusted_proxy_cidrs = ["127.0.0.1/32"]
```

Минимальный WEB block:

```toml
[web]
enabled = true
carrier = "https"
```

WEB structural TOML обязан находиться до:

```text
# --- DYNAMIC CONFIG ---
```

Это позволяет сохранить текущую политику:

- users/upstreams-only change — существующий reload path;
- WEB structure/core change — controlled hard restart.

Не реализовывать отдельный semantic reload classifier в first stable.

## 7. WEB carriers

Upstream 3.5.6 поддерживает точные enum:

```text
https
https-lanes
websocket
websocket-lanes
```

### 7.1. Fixed carrier

Сначала реализуется fixed mode для всех четырёх значений.

`web.carrier` выбирает единственный carrier.

### 7.2. Auto negotiation

Реализуется отдельным этапом после fixed matrix.

Upstream contract:

```toml
[web]
carrier = "https"
carriers = ["websocket-lanes", "websocket", "https-lanes"]
carrier_learning = true
carrier_negotiation_aggressiveness = "conservative"
```

OpenWrt UCI contract:

```uci
option carrier_policy 'auto'
option carrier 'https'
list carrier_candidate 'websocket-lanes'
list carrier_candidate 'websocket'
list carrier_candidate 'https-lanes'
option carrier_learning '1'
option carrier_negotiation_aggressiveness 'conservative'
```

Rules:

- fixed mode не должен случайно включать negotiation;
- auto candidate list должен быть ordered и non-empty;
- `carrier` остаётся fallback;
- safe fallback default — `https`;
- learning default для Auto preset — enabled;
- aggressiveness default — `conservative`;
- `balanced` и `aggressive` доступны только как advanced/manual choice.

## 8. TLS frontend modes

Допускается ровно один mode:

```text
external
haproxy
nginx
```

Нельзя автоматически поднимать одновременно HAProxy и NGINX.

### 8.1. External

Telemt только генерирует backend/runtime; пользователь сам обеспечивает public TLS terminator.

### 8.2. HAProxy managed

Helper:

```text
/usr/libexec/telemt-web-frontend
```

Обязательно:

- SSL-capable HAProxy;
- reject `haproxy-nossl`;
- fixed commands `status|render|check|apply|restore`;
- `haproxy -c` до replacement/reload;
- backup pre-Telemt `/etc/haproxy.cfg`;
- rollback on activation failure;
- ALPN `h2,http/1.1`;
- XFF overwrite from source address;
- no backend retry;
- no carrier credential access logging;
- managed WAN TCP/443 rule только после успешного apply;
- private Telemt port никогда не открывать WAN rule.

### 8.3. NGINX managed

Helper:

```text
/usr/libexec/telemt-web-nginx
```

Telemt-owned artifact:

```text
/etc/nginx/conf.d/telemt-web.conf
```

Обязательно:

- не перезаписывать `/etc/config/nginx`;
- не перезаписывать primary NGINX configuration;
- использовать OpenWrt `conf.d` include contract;
- config test до reload;
- rollback fragment/firewall;
- TLS 1.2/1.3;
- public HTTP/2 для `https-lanes`;
- HTTP/1.1 WebSocket Upgrade;
- private NGINX→Telemt hop HTTP/1.1;
- preserve Host;
- overwrite XFF `$remote_addr`;
- `proxy_buffering off`;
- `proxy_next_upstream off`;
- carrier access log off.

## 9. LuCI

WEB должен быть отдельной страницей:

```text
usr/lib/lua/luci/model/cbi/telemt_web.lua
```

Не раздувать старый монолитный `telemt.lua` WEB-настройками.

Минимальные секции страницы:

- WEB status;
- Enable;
- Carrier policy;
- TLS frontend;
- Private backend;
- VHosts;
- Profiles;
- Dynamic links / QR;
- Frontend helper status/actions;
- Resource profile;
- Advanced;
- Diagnostics.

### 9.1. Links

WEB link генерируется динамически из UCI:

```text
tg://webproxy?server=<host>&secret=<secret>
tg://webproxy?server=<host>&secret=dd<secret>
```

Link не хранить отдельно в UCI.

### 9.2. QR

Server-side QR endpoint должен принимать только validated WEB profile section ID и сам строить link из UCI.

Запрещено принимать arbitrary URL для qrencode.

### 9.3. Frontend actions

Controller допускает только fixed whitelist:

```text
check
apply
restore
```

Frontend helper выбирается сервером по committed UCI `tls_terminator`, а не по user-controlled executable path.

Actions работают только с уже сохранённым UCI, чтобы CBI unsaved fields не могли неожиданно изменить managed service.

### 9.4. Users page

Старая Users page остаётся центральной.

Добавить позже:

- compact `WEB: — / N profiles`;
- WEB links рядом с существующими links без широкой новой таблицы;
- deletion protection для users с WEB bindings.

При удалении user с bindings достаточно одного осмысленного confirmation и атомарного удаления user + bindings.

## 10. Security constraints

Запрещено:

- WAN expose `27453`;
- auto WAN expose API `9091`;
- trust arbitrary inbound X-Forwarded-For;
- `web_trusted_proxy_cidrs = ["0.0.0.0/0"]`;
- arbitrary shell command из LuCI request;
- duplicate WEB secrets;
- FakeTLS `ee` WEB capability;
- automatic `decoy_fasttrack_mode=enforce`;
- credential-bearing frontend access logs.

API/metrics safe default — loopback.

## 11. Telemt 3.5.6 advanced settings

В first stable normal UI не обязаны быть полностью exposed.

После carrier/resource LAB разрешить advanced controls:

- `http_connection_capacity_action = drop|wait|respond`, default `drop`;
- `decoy_fasttrack_mode = off|shadow|enforce`, default `off`;
- `web.timeouts.bridge_recovery_secs`, upstream default 15;
- `web.timeouts.http_overload_timeout_ms`, upstream default 250;
- `web.limits.max_http_overload_connections`, upstream default 64;
- per-profile max sessions/streams.

## 12. Resource profiles

LuCI normal mode должен показывать presets:

```text
low
standard
high
custom
```

Числа нельзя фиксировать по догадке. Сначала hardware measurements:

- ~128 MiB devices;
- ~256 MiB devices;
- 512 MiB+ devices;
- idle RSS;
- active sessions;
- lanes;
- WebSocket;
- media load;
- overload/recovery.

Не выводить все upstream limits в normal UI.

## 13. Packaging

### Core

Обязательно:

- aarch64-musl build from source with upstream lockfile;
- x86_64 upstream artifact SHA verification;
- OpenWrt 24.10 IPK;
- OpenWrt 25.12 real APKv3 via owfeed;
- `/etc/config/telemt` conffile belongs only to core package;
- frontend helpers packaged with core.

### LuCI

- package не владеет `/etc/config/telemt`;
- noarch/all;
- tag trigger поддерживает `3.5.*`;
- текущий nFPM `.apk` release path требуется заменить настоящим OpenWrt APKv3/owfeed либо другим подтверждённым OpenWrt-native path до RC для 25.12.

## 14. CI requirements

Core branch CI минимум проверяет:

- POSIX shell syntax;
- exact default backend port;
- package helper references;
- upstream 3.5.6 version/MSRV/lockfile;
- aarch64 locked build;
- x86_64 SHA + embedded trailer;
- IPK payload;
- APKv3 payload/magic;
- WEB frontend helper invariants.

LuCI CI минимум проверяет:

- Lua 5.1 syntax;
- menu/ACL JSON;
- WEB CBI/controller presence;
- no duplicate `/etc/config/telemt` ownership;
- fixed action whitelist;
- no duplicate secret field;
- frontend selector/actions.

## 15. Hardware acceptance

CI не закрывает LAB.

До RC на реальном OpenWrt проверить:

- upgrade from 3.4.x;
- Classic/DD/FakeTLS regression;
- current stable Telegram Desktop;
- `tg://webproxy`;
- all four fixed carriers;
- auto negotiation;
- External frontend;
- HAProxy;
- NGINX;
- secret rotation;
- disable/expiration/quota;
- reconnect/idle/media;
- no backend/API accidental WAN exposure;
- router memory pressure.

Carrier-specific acceptance:

- `https-lanes`: public HTTP/2 + минимум два simultaneous logical streams;
- `websocket`: HTTP 101 + binary relay + Ping/Pong;
- `websocket-lanes`: минимум две independent lane sockets; failure одной lane не закрывает sibling/parent.

## 16. Issue/release criteria

Issue #17 закрывать только после real OpenWrt 25.12 upgrade verification.

Issue #19 закрывать только после functional LuCI WEB acceptance на реальном клиенте.

RC требует:

- legacy regression clean;
- shared users confirmed;
- External/HAProxy/NGINX verified;
- all four WEB carriers verified;
- links/QR verified;
- router-safe resource profiles;
- OpenWrt 24.10 IPK verified;
- OpenWrt 25.12 APKv3 verified;
- LuCI 25.12 packaging fixed;
- no WAN exposure regressions.

## 17. Не входит в first stable

- собственный ACME client;
- отдельная WEB user database;
- второй Telemt validation process;
- semantic hot-reload classifier;
- PATCH config API как source of truth;
- automatic installation of both TLS frontends;
- полный rewrite старого LuCI;
- `decoy_fasttrack=enforce` по умолчанию.
