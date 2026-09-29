# Roadmap / TODO — Telemt 3.5.6 WEB Proxy for OpenWrt

Актуально: 2026-09-09

Проекты:

- core/package: `Medvedolog/telemt_owrt`
- LuCI: `Medvedolog/luci-app-telemt`
- рабочие ветки обоих репозиториев: `telemt-3.5.6-web`
- upstream: Telemt `3.5.6 Machtprobe`, tag `3.5.6`, commit `3693d1e2a87af0074598104338b5a4bb5bee202d`

Upstream references:

- https://github.com/telemt/telemt/releases/tag/3.5.6
- https://github.com/telemt/telemt/blob/3.5.6/docs/WEB/WEB_PROXY.ru.md

## Обязательные инварианты

- `/etc/config/telemt` — единственный persistent source of truth.
- runtime TOML `/tmp/etc/telemt.toml` — disposable generated artifact.
- Telemt не пишет UCI, LuCI не пишет TOML напрямую.
- `config user` — единственная база пользователей для Classic/DD/FakeTLS/WEB.
- WEB profile только ссылается на существующего пользователя и не хранит копию секрета/квоты/expiration.
- WEB listener по умолчанию приватный: `127.0.0.1:27453`.
- WEB transport использует HTTP/X-Forwarded-For trust model; `proxy_protocol=false`.
- TLS frontend ровно один: External, HAProxy или NGINX.
- WEB structural config находится до `# --- DYNAMIC CONFIG ---`, поэтому текущий core-diff корректно приводит к restart при структурных изменениях.
- Не добавлять второй Telemt-процесс для validation, semantic hot-reload classifier или PATCH API как второй источник конфигурации.
- Не расширять старый монолитный `telemt.lua` WEB-логикой: WEB живёт в отдельном `telemt_web.lua`.

## Статус CI на момент обновления

Core `telemt_owrt`:

- branch head до этого docs update: `4b199062e4be66ca4d47e7a790cf7a6b54d48a72`
- `Validate Telemt 3.5.6 WEB branch` Run #13: SUCCESS
- проверены locked aarch64 build Telemt 3.5.6, upstream x86_64 SHA, IPK, настоящий OpenWrt APKv3 через owfeed, package payload и shell syntax.

LuCI `luci-app-telemt`:

- branch head: `a54dfe0e391032eb9efab861a60c96f874f1bfaa`
- `Validate LuCI Telemt 3.5 WEB branch` Run #12: SUCCESS
- проверены Lua 5.1 syntax, menu/ACL JSON, ownership invariant, WEB controller endpoints и NGINX controls.

CI не заменяет проверку на реальном OpenWrt/router hardware и Telegram Desktop.

---

## P0 — package ownership / OpenWrt packaging

### Сделано

- [x] LuCI package больше не содержит `/etc/config/telemt`.
- [x] `telemt_owrt` остаётся единственным владельцем `/etc/config/telemt`.
- [x] LuCI CI запрещает повторное появление этого файла в package contents.
- [x] Core release path собирает OpenWrt 24.10 IPK.
- [x] Core release path собирает OpenWrt 25.12 APKv3 через owfeed.
- [x] Core CI проверяет ADB/APKv3 magic и package payload.

### Осталось

- [ ] Проверить upgrade на реальном OpenWrt 25.12.x при уже установленных `telemt` + `luci-app-telemt`.
- [ ] Подтвердить сохранение существующего `/etc/config/telemt` и `apk upgrade` exit code 0.
- [ ] После этого закрыть Issue #17.
- [ ] Перевести LuCI release workflow с nFPM APK на настоящий OpenWrt APKv3/owfeed либо принять эквивалентное решение; текущий LuCI release workflow всё ещё использует nFPM для `.apk`.
- [ ] Отдельно решить судьбу PR #18; не смешивать packaging refactor с carrier implementation без необходимости.

---

## LAB-1 — core Telemt 3.5.6 / legacy compatibility

### Сделано в коде/CI

- [x] Default upstream target `3.5.6`.
- [x] Checkout upstream tag `3.5.6`.
- [x] Проверка upstream MSRV и `Cargo.lock`.
- [x] `cross build --release --locked` для aarch64-musl.
- [x] Проверка upstream x86_64 archive SHA256 до локальной модификации.
- [x] Embedded trailer `MTProxy vX.Y.Z` сохраняется после build/extract.
- [x] Version detection: bounded `tail -c 512` marker first.
- [x] Legacy full-binary marker search остаётся fallback.
- [x] `telemt --version` / `-V` остаются последним compatibility fallback.
- [x] `strings` убран из нормального fast path.
- [x] Старый `# --- DYNAMIC CONFIG ---` сохранён.
- [x] Users/quotas/expiration/upstreams/ME не переписаны ради WEB.
- [x] WEB disabled by default, то есть upgrade сам по себе не включает новый ingress.

### Осталось на железе

- [ ] Start / Stop / Restart / Reload / Reboot.
- [ ] Classic.
- [ ] DD.
- [ ] FakeTLS.
- [ ] IPv4 / IPv6.
- [ ] Direct / SOCKS / HTTP / Shadowsocks upstreams.
- [ ] Middle-End.
- [ ] API / metrics.
- [ ] `client_mss`, `mask_dynamic`, `mask_host`, `mask_port`.
- [ ] Users / quotas / expiration / accumulated stats.
- [ ] Firewall behaviour.
- [ ] Upgrade from existing 3.4.x UCI without manual migration.

---

## LAB-1B — LuCI compatibility with 3.5.6

### Сделано

- [x] Release tag trigger принимает `3.*`, включая `3.5.*`.
- [x] LuCI продолжает читать cached core version и не обязан запускать Telemt для UI.
- [x] WEB вынесен в отдельный `telemt_web.lua`.
- [x] Branch CI проверяет Lua 5.1 syntax и package ownership.

### Осталось

- [ ] Обновить старые metadata/version strings в `nfpm.yaml`, `telemt.lua`, `postinst`, README/STRUCTURE, где всё ещё встречается 3.4.0 / core >=3.4.15.
- [ ] Проверить старую Dashboard/Users/Upstreams/Diagnostics часть с core 3.5.6 на живом роутере.
- [ ] Проверить service buttons, metrics/API polling и темы LuCI 21.02–25.x.
- [ ] Решить LuCI APKv3 packaging отдельно от WEB feature work.

---

## LAB-2 — minimal WEB backend

### Сделано

- [x] UCI sections `web`, `web_listener`, `web_vhost`, `web_profile`.
- [x] Safe default: WEB disabled.
- [x] Default private listener `127.0.0.1:27453`.
- [x] `web_client_ip_source=x_forwarded_for`.
- [x] `trusted_proxy_cidr`, `/0` запрещён.
- [x] WEB listener генерируется отдельно с `transport="web"`, `proxy_protocol=false`, `reuse_allow=false`.
- [x] Classic listener не загрязняется WEB-specific fields и наоборот.
- [x] 1..N vhosts и 1..N profiles.
- [x] `http_upstream` decoy.
- [x] `plain` и `dd`; `ee` для WEB не допускается.
- [x] VHost/profile/user references проверяются при generation.
- [x] Disabled shared user удаляет его WEB profile из runtime generation.
- [x] Structural WEB TOML находится до DYNAMIC marker.
- [x] Read-only helper `/usr/libexec/telemt-web-check`.

### Shared Users invariant

- [x] WEB profile хранит только ссылку на `config user`.
- [x] Secret хранится один раз.
- [x] Enabled state хранится один раз.
- [x] Quota/expiration/TCP/IP limits остаются в общем user section.
- [x] LuCI WEB links/QR собираются из shared user secret динамически.

### Осталось на железе

- [ ] Stable Telegram Desktop acceptance.
- [ ] `tg://webproxy` import/connect.
- [ ] connect/reconnect, text/media, idle/resume.
- [ ] restart/secret rotation/user disable/quota/expiration.

---

## LAB-3 — HAProxy managed frontend

### Сделано

- [x] Отдельный helper `/usr/libexec/telemt-web-frontend`.
- [x] Проверка SSL-capable HAProxy; `haproxy-nossl` не принимается.
- [x] `status`, `render`, `check`, `apply`, `restore`.
- [x] `haproxy -c` до установки/reload.
- [x] Backup существующего `/etc/haproxy.cfg` до managed takeover.
- [x] Rollback при failed activation.
- [x] Backend `127.0.0.1:27453`.
- [x] XFF overwrite через реальный source address.
- [x] `retries 0`, no access-log path для carrier traffic.
- [x] ALPN `h2,http/1.1`.
- [x] Опциональный managed WAN TCP/443 firewall rule.
- [x] ACME hotplug helper для managed HAProxy certificate refresh.
- [x] LuCI controls `Check / Apply / Restore` через fixed action whitelist.

### Осталось

- [ ] Проверить на реальном OpenWrt с package `haproxy`.
- [ ] Проверить конфликт TCP/443 с uhttpd/NGINX и recovery UX.
- [ ] Проверить certificate rotation.
- [ ] Проверить carrier-specific traffic после LAB-5.

---

## LAB-4 — NGINX managed frontend

### Сделано

- [x] Проверен OpenWrt layout с include `/etc/nginx/conf.d/*.conf` внутри `http {}`.
- [x] Отдельный helper `/usr/libexec/telemt-web-nginx`.
- [x] Telemt владеет только `/etc/nginx/conf.d/telemt-web.conf`.
- [x] `/etc/config/nginx` и основной NGINX config не перезаписываются.
- [x] `status`, `render`, `check`, `apply`, `restore`.
- [x] Config test до reload и rollback fragment/firewall.
- [x] TLS 1.2/1.3.
- [x] Public HTTP/2 path предусмотрен для lanes.
- [x] HTTP/1.1 private hop к Telemt.
- [x] WebSocket Upgrade headers сохранены.
- [x] Host сохранён.
- [x] X-Forwarded-For перезаписывается `$remote_addr`, а не доверяет входному XFF.
- [x] `proxy_buffering off`.
- [x] `proxy_next_upstream off`.
- [x] carrier access logging отключён.
- [x] LuCI NGINX fields + common fixed frontend action endpoint.
- [x] Core package включает NGINX helper в IPK/APKv3.
- [x] Uninstall пытается вернуть Telemt-owned NGINX fragment.
- [x] Документация `docs/WEB_NGINX_MANAGED.ru.md`.
- [x] Core Run #13 и LuCI Run #12 — SUCCESS.

### Осталось

- [ ] Реальный OpenWrt test `nginx-ssl`/`nginx-full`.
- [ ] Проверка существующих `_lan`/user server blocks и TCP/443 collision.
- [ ] Проверка cert/key reload и uninstall/restore.
- [ ] Проверка `https-lanes` HTTP/2 и WebSocket carriers после LAB-5.

---

## LAB-5 — все WEB carriers — NEXT

Upstream 3.5.6 поддерживает ровно:

```text
https
https-lanes
websocket
websocket-lanes
```

Upstream contract:

- `web.carrier` — fixed carrier или финальный fallback при negotiation;
- `web.carriers` — optional ordered candidate list, `false` либо непустой array;
- `carrier_learning` — bounded process-local learning;
- `carrier_negotiation_aggressiveness`: `conservative|balanced|aggressive`.

### LAB-5A — fixed carriers, делать первым

- [x] `https` уже работает как единственный разрешённый generator value.
- [ ] Разрешить в `telemt.init`: `https-lanes`.
- [ ] Разрешить в `telemt.init`: `websocket`.
- [ ] Разрешить в `telemt.init`: `websocket-lanes`.
- [ ] Расширить carrier dropdown в `telemt_web.lua` до четырёх enum.
- [ ] Не менять shared Users/VHost/Profile schema.
- [ ] Не включать auto-negotiation в тот же commit.
- [ ] Добавить CI assertions на четыре exact tokens.
- [ ] HAProxy: подтвердить `h2,http/1.1` contract.
- [ ] NGINX: подтвердить HTTP/2 для lanes и Upgrade для WebSocket.

### LAB-5B — auto negotiation отдельным commit

Предлагаемая UCI модель:

```uci
config web 'web'
        option carrier_policy 'fixed'   # fixed | auto
        option carrier 'https'          # fixed or fallback
        list carrier_candidate 'websocket-lanes'
        list carrier_candidate 'websocket'
        list carrier_candidate 'https-lanes'
        option carrier_learning '1'
        option carrier_negotiation_aggressiveness 'conservative'
```

- [ ] `fixed`: генерировать `carriers = false` либо не задавать поле.
- [ ] `auto`: генерировать ordered non-empty `carriers=[...]`.
- [ ] Fallback `carrier=https` по умолчанию.
- [ ] Не дублировать fallback в candidate array без необходимости; upstream всё равно append-ит его один раз.
- [ ] Learning default ON только для Auto UI preset.
- [ ] Aggressiveness default `conservative`.
- [ ] Manual/fixed carrier selection остаётся доступным.

### LAB-5 hardware acceptance

- [ ] `https`: connect/reconnect/media.
- [ ] `https-lanes`: public HTTP/2 и минимум два simultaneous logical streams.
- [ ] `websocket`: HTTP 101, binary relay, Ping/Pong, reconnect.
- [ ] `websocket-lanes`: минимум два stream sockets; failure одной lane не убивает sibling/parent.
- [ ] HAProxy для всех четырёх.
- [ ] NGINX для всех четырёх.
- [ ] External frontend reference config для всех четырёх.
- [ ] Telegram Desktop stable, не beta как primary acceptance target.

---

## LAB-6 — router resource profiles

Профили:

```text
low
standard
high
custom
```

- [ ] Снять реальные measurements на 128 MiB class.
- [ ] 256 MiB class.
- [ ] 512 MiB+ class.
- [ ] idle RSS.
- [ ] active sessions/streams.
- [ ] HTTPS lanes pressure.
- [ ] WebSocket/lane/media pressure.
- [ ] overload/recovery.
- [ ] Только после измерений зафиксировать численные presets.
- [ ] Не показывать весь upstream limit matrix в обычном LuCI режиме.

---

## LAB-7 — LuCI WEB page

### Уже сделано

- [x] Отдельный `usr/lib/lua/luci/model/cbi/telemt_web.lua`.
- [x] Menu entry `WEB Proxy`.
- [x] WEB enable.
- [x] Private listener.
- [x] VHosts.
- [x] Shared-user WEB profiles.
- [x] DD/plain secret mode.
- [x] Per-profile session/stream optional limits.
- [x] Dynamic `tg://webproxy` links.
- [x] Server-side QR endpoint с whitelist-by-construction.
- [x] External / HAProxy / NGINX frontend selector.
- [x] Managed frontend status/check/apply/restore.
- [x] Actions используют только committed UCI state, а не несохранённые CBI values.

### Осталось

- [ ] Все четыре carrier values + auto policy UI.
- [ ] Resource profile UI после LAB-6.
- [ ] Advanced 3.5.6 operational knobs после LAB-8.
- [ ] Более полный runtime diagnostics после LAB-9.
- [ ] В существующем Users page добавить компактный `WEB: — / N profiles` indicator.
- [ ] Защитить удаление user, если на него ссылаются WEB profiles; одно meaningful confirmation удаляет user + bindings.
- [ ] По возможности встроить WEB links в существующий Users link UX без раздувания таблицы.

---

## LAB-8 — 3.5.6 advanced controls

После LAB-5/6:

- [ ] `http_connection_capacity_action`: `drop|wait|respond`, default `drop`.
- [ ] `decoy_fasttrack_mode`: `off|shadow|enforce`, default `off`.
- [ ] `bridge_recovery_secs`, upstream default 15.
- [ ] `http_overload_timeout_ms`, upstream default 250.
- [ ] `max_http_overload_connections`, upstream default 64.
- [ ] Optional per-profile limits уже поддержаны backend/LuCI, проверить hardware semantics.
- [ ] Никогда не включать `enforce` автоматически.

---

## LAB-9 — runtime status / diagnostics

- [ ] lifecycle state.
- [ ] generation/runtime instance.
- [ ] sessions/streams.
- [ ] current carrier / negotiation / learning.
- [ ] overload/capacity.
- [ ] recovery.
- [ ] decoy.
- [ ] pressure/resource counters.
- [ ] Малое число полезных LuCI cards вместо полного dump Prometheus.
- [ ] Опционально кнопки Pause/Drain/Resume через loopback API.

Не вставлять Pause/Drain автоматически в Save & Apply.

---

## LAB-10 — full regression / RC

Совместно на одной установке:

```text
Classic
DD
FakeTLS
WEB https
WEB https-lanes
WEB websocket
WEB websocket-lanes
```

- [ ] Shared user secrets работают во всех transports.
- [ ] Secret rotation влияет на все transports ожидаемо.
- [ ] Disable/expiration/quota работают ожидаемо.
- [ ] API/metrics/ME/upstreams не регрессировали.
- [ ] WEB backend `27453` не торчит в WAN.
- [ ] API `9091` не открывается автоматически в WAN.
- [ ] External frontend работает.
- [ ] HAProxy работает.
- [ ] NGINX работает.
- [ ] 128/256/512+ MiB resource profiles не приводят к OOM.
- [ ] OpenWrt 24.10 IPK verified on router.
- [ ] OpenWrt 25.12 APKv3 verified on router.
- [ ] LuCI package OpenWrt 25.12 packaging решён корректно.
- [ ] Issue #17 закрыт после real upgrade verification.
- [ ] Issue #19 закрыт только после functional LuCI WEB acceptance.

## Не делать в first stable

- собственный ACME client;
- отдельную WEB user database;
- duplicate secrets;
- второй Telemt validator process;
- semantic hot-reload classifier;
- PATCH API как source of truth;
- WAN exposure backend `27453`;
- hard dependency одновременно на HAProxy и NGINX;
- автоматическую установку обоих frontends;
- полный rewrite старого LuCI;
- `decoy_fasttrack=enforce` default.

## Ближайший порядок commits

```text
NEXT-1 core: allow all four fixed WEB carriers
NEXT-2 luci: expose all four fixed WEB carriers
NEXT-3 ci/docs: fixed carrier matrix + frontend requirements
NEXT-4 core: add auto carrier candidate list + learning/aggressiveness
NEXT-5 luci: add auto carrier policy controls
NEXT-6 test: Telegram Desktop fixed/auto carrier matrix

then:
resource profiles -> advanced controls -> runtime diagnostics -> Users integration -> full regression -> RC
```
