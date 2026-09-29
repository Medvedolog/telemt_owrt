# HANDOFF — Telemt 3.5.6 WEB Proxy / OpenWrt

Дата: 2026-09-09

Этот файл — canonical handoff для продолжения разработки в новом чате.

## 1. С чего продолжать

Следующая задача: **LAB-5A — включить все четыре fixed WEB carriers**, не добавляя auto-negotiation в тот же commit.

Порядок:

1. `telemt_owrt/files/telemt.init`: разрешить exact enum `https|https-lanes|websocket|websocket-lanes` вместо текущего фактического whitelist только `https`.
2. Не менять UCI Users/VHost/Profile schema.
3. Не менять shared user logic.
4. Не менять reload architecture.
5. `luci-app-telemt/usr/lib/lua/luci/model/cbi/telemt_web.lua`: расширить fixed carrier dropdown до четырёх exact tokens.
6. Core/LuCI CI: assertions на четыре enum.
7. Проверить frontend prerequisites:
   - HAProxy: ALPN `h2,http/1.1` уже генерируется;
   - NGINX: public HTTP/2 нужен для `https-lanes`, HTTP/1.1 Upgrade нужен для WebSocket carriers;
   - private frontend→Telemt hop остаётся HTTP/1.1.
8. Отдельным следующим commit сделать LAB-5B auto-negotiation.

Не объединять LAB-5A и LAB-5B: это ухудшит bisect carrier failures.

## 2. Репозитории и ветки

Core/package:

```text
https://github.com/Medvedolog/telemt_owrt
branch: telemt-3.5.6-web
```

LuCI:

```text
https://github.com/Medvedolog/luci-app-telemt
branch: telemt-3.5.6-web
```

`main` обоих репозиториев не использовать для текущей разработки до завершения LAB/RC.

### Baseline heads перед handoff document

Core branch после обновлённого Roadmap + ТЗ:

```text
dc08fdf9cf6b83b8f42b7b80b18e136d38697b0d
```

LuCI branch:

```text
a54dfe0e391032eb9efab861a60c96f874f1bfaa
```

Сам handoff commit будет следующим commit после core baseline выше.

## 3. Canonical project docs

В core branch читать в таком порядке:

```text
HANDOFF_TELEMT_3.5.6_WEB_2026-09-09.ru.md
TZ_TELEMT_3.5.6_WEB_OPENWRT.ru.md
ROADMAP_3.5_WEB.md
```

Frontend docs:

```text
docs/WEB_EXTERNAL_FRONTEND.ru.md
docs/WEB_HAPROXY_MANAGED.ru.md
docs/WEB_NGINX_MANAGED.ru.md
```

## 4. Upstream target

Telemt:

```text
release: 3.5.6 Machtprobe
tag: 3.5.6
commit: 3693d1e2a87af0074598104338b5a4bb5bee202d
release date: 2026-09-06
```

References:

- https://github.com/telemt/telemt/releases/tag/3.5.6
- https://github.com/telemt/telemt/blob/3.5.6/docs/WEB/WEB_PROXY.ru.md
- `src/config/types/web.rs`
- `src/config/types/web_carrier.rs`

Important exact upstream carrier enum:

```text
https
https-lanes
websocket
websocket-lanes
```

Upstream semantics:

- `web.carrier` = fixed carrier when negotiation disabled;
- with negotiation enabled, `web.carrier` = final fallback;
- `web.carriers` = `false` or ordered non-empty carrier array;
- `carrier_learning` controls bounded learning;
- `carrier_negotiation_aggressiveness` = `conservative|balanced|aggressive`.

Upstream frontend requirements:

- Telemt WEB itself does not terminate public TLS;
- public endpoint = HTTPS/WSS :443;
- `https-lanes` requires public HTTP/2;
- WebSocket carriers require HTTP/1.1 Upgrade support;
- private TLS-frontend→Telemt hop remains HTTP/1.1;
- `plain` and `dd` secrets supported;
- FakeTLS `ee` is not a WEB secret mode.

## 5. Hard architectural invariants

### UCI single source of truth

```text
/etc/config/telemt -> telemt.init -> /tmp/etc/telemt.toml -> Telemt
```

Never introduce:

- LuCI direct TOML writes;
- Telemt writing UCI;
- config PATCH API as persistent source;
- second config database.

### Shared Users

`config user` is the only user entity for Classic/DD/FakeTLS/WEB.

WEB profile stores only:

```text
vhost
user reference
secret_mode
optional WEB session/stream limits
```

Do not add:

- WEB-specific secret;
- duplicate quota;
- duplicate expiration;
- duplicate enabled state.

Disabled shared user means its WEB profile is omitted from generated runtime.

### Reload policy

Keep current existing architecture:

- WEB structural config is before `# --- DYNAMIC CONFIG ---`;
- core diff therefore causes controlled hard restart;
- users/upstreams-only may use current reload path.

Do not implement semantic hot-reload classifier now.

Do not launch a second Telemt instance as validator.

### Minimal operator ceremony

Normal Save & Apply should remain simple. Do not add multi-step confirmations or codewords.

Managed frontend destructive actions use one meaningful confirmation where appropriate.

## 6. Core — what is already done

Repository: `Medvedolog/telemt_owrt`, branch `telemt-3.5.6-web`.

### Build / packaging

Done:

- upstream target 3.5.6;
- Rust MSRV checked from upstream;
- build uses `Cargo.lock` / `--locked`;
- aarch64-musl built from source;
- x86_64 upstream release archive SHA256 verified before local modification;
- embedded trailer appended:

```text
MTProxy vX.Y.Z
```

- OpenWrt 24.10 IPK path;
- OpenWrt 25.12 true APKv3 via `owfeed`;
- package contains core WEB helpers;
- CI validates APKv3 ADB magic.

### Version detection

`files/telemt.init` normal path:

1. bounded `tail -c 512` marker search;
2. legacy full-binary marker search;
3. `--version`;
4. `-V`.

No `strings` in normal path.

Version cache:

```text
/tmp/etc/telemt.version
```

### WEB UCI/TOML backend

Implemented UCI sections:

```text
config web
config web_listener
config web_vhost
config web_profile
```

Default WEB listener:

```text
127.0.0.1:27453
```

Current generated WEB listener includes:

```toml
transport = "web"
proxy_protocol = false
reuse_allow = false
web_client_ip_source = "x_forwarded_for"
```

Trusted proxy CIDRs validated; `/0` rejected/ignored.

Implemented:

- `1..N` vhosts;
- `1..N` profiles;
- `http_upstream` decoy;
- WEB `plain|dd` only;
- shared-user references;
- disabled shared user suppression;
- duplicate/missing vhost/profile validation;
- optional per-profile max sessions/streams.

Current deliberate limitation in `telemt.init`:

```text
carrier effectively only https
```

That is exactly what LAB-5A must change next.

### WEB status

Read-only helper:

```text
/usr/libexec/telemt-web-check
```

Reports UCI/runtime/process/backend socket/frontend state.

## 7. Frontend — what is already done

### External

Supported by architecture/docs. Telemt does not manage TLS service.

### HAProxy managed

Helper:

```text
/usr/libexec/telemt-web-frontend
```

Commands:

```text
status
render
check
apply
restore
```

Key properties:

- SSL-capable HAProxy required;
- `haproxy-nossl` rejected;
- backup `/etc/haproxy.cfg.telemt-backup`;
- generated config syntax-checked before apply;
- rollback on failed activation;
- XFF overwritten from source address;
- ALPN `h2,http/1.1`;
- `retries 0`;
- managed WAN TCP/443 firewall rule optional;
- backend 27453 never auto-opened to WAN;
- ACME hotplug helper packaged.

Managed HAProxy does take ownership of `/etc/haproxy.cfg` only after explicit opt-in and backup.

### NGINX managed

Helper:

```text
/usr/libexec/telemt-web-nginx
```

Telemt owns only:

```text
/etc/nginx/conf.d/telemt-web.conf
```

Does not overwrite:

```text
/etc/config/nginx
primary nginx configuration
```

Key properties:

- OpenWrt `conf.d/*.conf` include model used;
- `status/render/check/apply/restore`;
- config test before reload;
- rollback fragment/firewall;
- TLS 1.2/1.3;
- public HTTP/2 support path;
- HTTP/1.1 private proxy;
- WebSocket Upgrade headers;
- Host preserved;
- XFF overwritten `$remote_addr`;
- `proxy_buffering off`;
- `proxy_next_upstream off`;
- carrier access logging off.

## 8. LuCI — what is already done

Repository: `Medvedolog/luci-app-telemt`, branch `telemt-3.5.6-web`.

New separate page:

```text
usr/lib/lua/luci/model/cbi/telemt_web.lua
```

Implemented:

- WEB menu entry;
- status;
- enable;
- private backend listener;
- vhosts;
- profiles referencing shared user;
- DD/plain mode;
- optional per-profile max limits;
- dynamic WEB links;
- server-side WEB QR;
- External / HAProxy / NGINX selector;
- HAProxy fields;
- NGINX fields;
- managed frontend status;
- Check / Apply / Restore actions.

Controller endpoint uses fixed action whitelist and fixed helper routing. Arbitrary command/executable cannot be supplied by request.

Frontend actions operate on committed UCI, not unsaved CBI values.

Dynamic link format:

```text
tg://webproxy?server=<host>&secret=<secret>
tg://webproxy?server=<host>&secret=dd<secret>
```

QR endpoint accepts profile section ID, loads all link data from UCI server-side, validates, then invokes `qrencode`.

## 9. Packaging issue status

### Issue #17

`luci-app-telemt` previously also owned `/etc/config/telemt`, causing OpenWrt 25.12 `apk` overwrite conflict.

Branch fix is implemented:

- LuCI package no longer packages `/etc/config/telemt`;
- core is sole owner;
- LuCI CI guards this invariant.

Issue #17 is still OPEN deliberately.

Do not close until real OpenWrt 25.12.x upgrade test confirms:

```text
existing UCI survives
both packages install/upgrade cleanly
apk upgrade exit code == 0
```

### LuCI APK caveat

Core uses true OpenWrt APKv3 via owfeed.

LuCI release workflow still uses nFPM `--packager apk`. This needs a separate decision/fix before 25.12 RC.

Open PR #18 proposes owfeed packaging; evaluate separately, especially because ownership conflict must remain fixed regardless of packaging tool.

## 10. Issues

### #17 — package ownership

Status: open, branch code fix done, hardware upgrade verification pending.

### #19 — LuCI WEB request

Status: open.

Do not close yet. Branch has substantial WEB LuCI already, but functional Telegram/OpenWrt acceptance is not finished.

## 11. CI baseline

### Core

Last fully verified pre-handoff run:

```text
workflow: Validate Telemt 3.5.6 WEB branch
Run #13
head: 4b199062e4be66ca4d47e7a790cf7a6b54d48a72
result: SUCCESS
```

It covered:

- upstream 3.5.6 checkout/MSRV/lockfile;
- aarch64 locked build;
- x86_64 SHA verification;
- embedded trailer;
- OpenWrt 24.10 IPK;
- OpenWrt 25.12 APKv3;
- helper payload/shell checks.

Docs commits after this run will naturally trigger additional branch CI; inspect latest Actions before coding, but Run #13 is the known green functional baseline.

### LuCI

```text
workflow: Validate LuCI Telemt 3.5 WEB branch
Run #12
head: a54dfe0e391032eb9efab861a60c96f874f1bfaa
result: SUCCESS
```

Covers Lua 5.1 syntax, JSON, ownership, controller/action invariants and NGINX UI assertions.

## 12. Known incomplete items before RC

### Immediate

- all four fixed carriers;
- auto carrier negotiation;
- hardware/client testing.

### Then

- resource profiles low/standard/high/custom based on measurements;
- advanced 3.5.6 overload/fasttrack/recovery controls;
- richer runtime diagnostics;
- Users page WEB indicator/integration;
- user deletion protection;
- LuCI native OpenWrt 25.12 package path;
- full legacy regression.

## 13. LAB-5A exact implementation guidance

### Core patch

Current code has logic equivalent to:

```sh
config_get web_carrier web carrier "https"
case "$web_carrier" in
    https) ;;
    *) web_carrier="https" ;;
esac
```

Change only enum acceptance to:

```text
https|https-lanes|websocket|websocket-lanes
```

Do not add `web.carriers` in this patch.

Generated fixed TOML remains conceptually:

```toml
[web]
enabled = true
carrier = "<selected exact enum>"
```

### LuCI patch

Current page intentionally exposes only HTTPS.

Add exact ListValue options for:

```text
HTTPS -> https
HTTPS lanes -> https-lanes
WebSocket -> websocket
WebSocket lanes -> websocket-lanes
```

Default remains `https`.

### CI patch

Add explicit assertions that:

- core whitelist contains all four exact tokens;
- LuCI contains all four exact tokens;
- invalid values still fail/fallback safely;
- auto negotiation fields are not accidentally generated yet.

### Frontend review in same LAB

No architectural rewrite.

Check that generated config actually satisfies upstream requirements:

- HAProxy ALPN has `h2,http/1.1`;
- NGINX public server enables HTTP/2 in a syntax compatible with supported OpenWrt nginx version;
- Upgrade/Connection headers survive WebSocket paths;
- `Sec-WebSocket-*`, Authorization, Content-Type and lane/cursor headers are not stripped/rewritten incorrectly;
- `proxy_next_upstream off` / HAProxy retries 0 remain.

## 14. LAB-5B exact follow-up

Only after LAB-5A is committed and CI green.

Suggested UCI:

```uci
option carrier_policy 'fixed' # fixed|auto
option carrier 'https'
list carrier_candidate 'websocket-lanes'
list carrier_candidate 'websocket'
list carrier_candidate 'https-lanes'
option carrier_learning '1'
option carrier_negotiation_aggressiveness 'conservative'
```

Rules:

- fixed = no negotiation candidate array;
- auto = ordered non-empty candidates;
- fallback `carrier=https` default;
- `carrier_learning=1` default for auto preset;
- conservative default;
- validate exact enums;
- reject duplicate/empty nonsense in OpenWrt layer without cloning Rust semantic validator.

## 15. Hardware acceptance notes

Primary client: current stable Telegram Desktop.

Test fixed carriers individually.

`https`:

- basic connect/reconnect;
- text/media;
- idle/resume.

`https-lanes`:

- confirm public HTTP/2;
- at least two simultaneous logical streams;
- no application-level HOL between streams.

`websocket`:

- HTTP 101;
- binary relay traffic;
- Ping/Pong liveness;
- reconnect.

`websocket-lanes`:

- at least two stream sockets;
- closing/corrupting one lane must not kill siblings or parent session.

Repeat on:

- External frontend;
- HAProxy;
- NGINX.

Also test shared user disable/secret rotation/quota/expiration.

## 16. Do not do

During next chat do not:

- push current work to `main` unless explicitly requested;
- create a new WEB user database;
- copy user secrets into `web_profile`;
- replace UCI with Telemt API;
- launch a second Telemt validation process;
- invent complex Save&Apply lifecycle classification;
- expose port 27453 to WAN;
- use PROXY protocol for WEB;
- automatically enable NGINX and HAProxy together;
- make `decoy_fasttrack=enforce` default;
- close #17/#19 merely because branch CI is green.

## 17. Suggested first prompt for the new chat

```text
Продолжаем Telemt 3.5.6 WEB по HANDOFF_TELEMT_3.5.6_WEB_2026-09-09.ru.md и TZ_TELEMT_3.5.6_WEB_OPENWRT.ru.md в ветках telemt-3.5.6-web обоих репозиториев. Сначала проверь актуальные branch heads и CI, затем делай LAB-5A: все четыре fixed carriers в core + LuCI отдельными небольшими commits, без auto-negotiation. Не трогай main.
```
