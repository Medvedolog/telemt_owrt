# Roadmap / TODO — Telemt 3.5.6 WEB Proxy for OpenWrt

Projects:

- Core/package: `Medvedolog/telemt_owrt`
- LuCI: `Medvedolog/luci-app-telemt`
- Working branches: `telemt-3.5.6-web`
- Target upstream: Telemt `3.5.6 Machtprobe`

Goal:

- keep Classic / DD / FakeTLS working without regression;
- add WEB Proxy support;
- keep one shared Users database for all transports;
- support External / HAProxy / NGINX TLS frontend;
- keep UCI as the only persistent source of truth;
- keep the OpenWrt integration deterministic and router-friendly.

---

## P0 — fix existing package ownership problem

### `luci-app-telemt`

- [ ] Fix `/etc/config/telemt` ownership conflict.
- [ ] Remove `telemt.config` from LuCI package contents.
- [ ] Make `telemt_owrt` the only owner of `/etc/config/telemt`.
- [ ] Verify upgrade with both packages already installed.
- [ ] Verify IPK.
- [ ] Verify APK/OpenWrt 25.12.
- [ ] Close Issue #17 after verification.

Definition of Done:

```text
telemt package owns /etc/config/telemt
luci-app-telemt does not own it
existing user config survives upgrade
apk upgrade exits 0
```

---

## LAB-1 — Telemt 3.5.6 without WEB

### `telemt_owrt` build workflow

File:

```text
.github/workflows/telemt-release-aarch64-upx.yml
```

- [ ] Default build target = `3.5.6`.
- [ ] Checkout upstream tag `3.5.6`.
- [ ] Guarantee Rust `>= 1.88`.
- [ ] Build with upstream `Cargo.lock` / `--locked`.
- [ ] Verify aarch64-musl.
- [ ] Verify x86_64 upstream artifact.
- [ ] Verify upstream SHA256 before packaging modifications.
- [ ] Keep embedded trailer `MTProxy vX.Y.Z`.
- [ ] Append trailer only after build/UPX/extract.
- [ ] Verify IPK/APK/raw binaries.

### `files/telemt.init` — version detection

- [ ] Make bounded embedded-trailer detection the primary path.
- [ ] Read only the last 256–512 bytes of `/usr/bin/telemt`.
- [ ] Parse `MTProxy vX.Y.Z`.
- [ ] Cache version in `/tmp/etc/telemt.version`.
- [ ] Keep full-binary marker search only as legacy fallback.
- [ ] Keep `telemt --version` / `-V` as final compatibility fallback.
- [ ] Remove `strings` from the normal fast path.

### Legacy TOML

- [ ] Do not change Classic/DD/FakeTLS TOML layout without need.
- [ ] Do not add `transport="mtproxy"` merely for cosmetics.
- [ ] Do not rewrite Users generation.
- [ ] Do not rewrite quota/expiration handling.
- [ ] Do not rewrite upstream generation.
- [ ] Do not rewrite Middle-End unless 3.5.6 requires a real compatibility fix.
- [ ] Keep `# --- DYNAMIC CONFIG ---`.
- [ ] Keep current reload architecture for the first migration step.

### LAB-1 regression matrix

- [ ] Start / Stop / Restart / Reload / Reboot.
- [ ] Classic.
- [ ] DD.
- [ ] FakeTLS.
- [ ] IPv4 / IPv6.
- [ ] Direct / SOCKS / HTTP / Shadowsocks upstreams.
- [ ] Middle-End.
- [ ] API / metrics.
- [ ] `client_mss`.
- [ ] `mask_dynamic`.
- [ ] `mask_host` / `mask_port`.
- [ ] Users / quotas / expiration.
- [ ] accumulated traffic stats.
- [ ] dynamic firewall rule.
- [ ] upgrade from existing 3.4.x UCI without manual migration.

Definition of Done:

```text
Telemt 3.5.6 runs with the existing 3.4.x UCI
WEB absent/disabled
legacy functionality unchanged
```

---

## LAB-1B — LuCI compatibility with core 3.5.6

Files:

```text
usr/lib/lua/luci/model/cbi/telemt.lua
nfpm.yaml
scripts/postinst
.github/workflows/luci-app-telemt-release.yml
README.md
STRUCTURE*.md
```

- [ ] Update displayed app/core version requirements.
- [ ] Continue reading core version from `/tmp/etc/telemt.version`.
- [ ] Do not execute the Telemt binary from LuCI merely to display its version.
- [ ] Verify dashboard against Telemt 3.5.6.
- [ ] Verify Users.
- [ ] Verify Upstreams.
- [ ] Verify Diagnostics.
- [ ] Verify service buttons.
- [ ] Verify metrics polling/API requests.
- [ ] Fix release tag trigger so `3.5.*` releases work.
- [ ] Decide separately whether PR #18 / owfeed packaging changes are adopted.
- [ ] Do not mix packaging-system replacement into the first WEB functional commit unless required.

---

## LAB-2 — minimal WEB backend

### `files/telemt.config`

Add UCI sections.

#### WEB global

```uci
config web 'web'
        option enabled '0'
        option carrier 'https'
        option tls_terminator 'external'
        option memory_profile 'standard'
```

#### WEB listener

```uci
config web_listener 'web_listener'
        option ip '127.0.0.1'
        option port '27453'
        option client_ip_source 'x_forwarded_for'
        list trusted_proxy_cidr '127.0.0.1/32'
```

#### VHost

```uci
config web_vhost
        option enabled '1'
        option name 'main'
        option host 'proxy.example.com'
        option public_addr '203.0.113.10:443'
        option decoy_mode 'http_upstream'
        option decoy_upstream 'http://127.0.0.1:27454'
```

#### Profile

```uci
config web_profile
        option enabled '1'
        option vhost 'main'
        option user 'medved'
        option secret_mode 'dd'
```

### `files/telemt.init` WEB generator

- [ ] Add WEB UCI parsing.
- [ ] Validate enums, ports, FQDN, CIDR and user references.
- [ ] Generate WEB listener only when `web.enabled=1`.
- [ ] Generate:

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

- [ ] Never inherit MTProxy-specific `client_mss`, `synlimit`, `announce`, `announce_ip` into the WEB listener.
- [ ] Generate minimal `[web]` first:

```toml
[web]
enabled = true
carrier = "https"
```

- [ ] Rely on upstream defaults for new 3.5.6 knobs unless OpenWrt needs an explicit override.
- [ ] Support `1..N` vhosts from the start.
- [ ] Support `1..N` profiles from the start.
- [ ] Support `http_upstream` decoy first.
- [ ] Keep `plain` and `dd` WEB secret modes.
- [ ] Reject `ee` for WEB.

### Shared Users invariant

`config user` remains the only user entity.

- [ ] Same user can use Classic.
- [ ] Same user can use DD.
- [ ] Same user can use FakeTLS.
- [ ] Same user can be referenced by WEB profiles.
- [ ] Secret stored once.
- [ ] Quota stored once.
- [ ] Expiration stored once.
- [ ] Enabled state stored once.
- [ ] Connection/IP limits stored once.
- [ ] Disabled user is omitted from `[access.users]` and its WEB profiles are not generated.
- [ ] No dangling WEB profile references.

### Reload policy

- [ ] Put all WEB structural TOML before `# --- DYNAMIC CONFIG ---`.
- [ ] Therefore any WEB structural change follows the existing core-diff path and may hard restart Telemt.
- [ ] Do not add a semantic lifecycle classifier.
- [ ] Do not launch a second Telemt process for validation.
- [ ] Do not use Telemt PATCH config API as persistent backend.

### LAB-2 acceptance

Minimum deployment:

```text
Telemt WEB: 127.0.0.1:27453
carrier: https
TLS frontend: external
vhosts: 1+
profiles: 1+
users: existing shared users
decoy: http_upstream
```

Test:

- [ ] current stable Telegram Desktop.
- [ ] `tg://webproxy`.
- [ ] connect/reconnect.
- [ ] text/media.
- [ ] idle/resume.
- [ ] Telemt restart.
- [ ] user disable.
- [ ] secret rotation.
- [ ] quota.
- [ ] expiration.

---

## LAB-3 — HAProxy frontend

Priority: before NGINX because users already ask for it.

Architecture:

```text
Telegram
   ↓ HTTPS/WSS :443
HAProxy
   ↓ HTTP/1.1 + X-Forwarded-For
Telemt WEB 127.0.0.1:27453
```

- [ ] Do not use PROXY protocol for WEB transport.
- [ ] Keep `proxy_protocol=false` in the WEB listener.
- [ ] Pass trusted `X-Forwarded-For`.
- [ ] Trusted immediate proxy defaults to `127.0.0.1/32` for local frontend.
- [ ] Keep classic MTProxy/PROXY-protocol support conceptually separate from WEB/XFF.

### Frontend helper

Preferred separate helper:

```text
/usr/libexec/telemt-web-frontend
```

- [ ] Keep HAProxy/NGINX config generation out of `generate_toml()`.
- [ ] Detect installed HAProxy package/build.
- [ ] Verify SSL support.
- [ ] Detect running state.
- [ ] Generate Telemt-specific frontend/backend config.
- [ ] Never blindly overwrite a user's `/etc/haproxy.cfg`.
- [ ] Support External/Existing mode first.
- [ ] Add Managed mode only after verifying the actual OpenWrt HAProxy config model.
- [ ] Use `haproxy -c` before reload/apply.
- [ ] Reload only after successful validation.

---

## LAB-4 — NGINX frontend

Architecture:

```text
Telegram
   ↓ HTTPS/WSS :443
NGINX
   ↓ HTTP/1.1 + X-Forwarded-For
Telemt WEB
```

- [ ] Detect actual OpenWrt NGINX config layout.
- [ ] Do not assume/hardcode an unverified `/etc/nginx/conf.d` layout.
- [ ] Generate only a Telemt-owned include/fragment.
- [ ] Never overwrite the user's primary NGINX configuration.
- [ ] Support TLS 1.2/1.3.
- [ ] Support public HTTP/2 for `https-lanes`.
- [ ] Support HTTP/1.1 WebSocket Upgrade.
- [ ] Preserve Host.
- [ ] Set trusted X-Forwarded-For correctly.
- [ ] Disable proxy buffering for carrier traffic.
- [ ] Disable unsafe upstream retry.
- [ ] Disable access logging for carrier credentials by default.
- [ ] Use `nginx -t` before reload.
- [ ] Reload only after successful validation.

---

## LAB-5 — full WEB carrier support

- [ ] `https`.
- [ ] `https-lanes`.
- [ ] `websocket`.
- [ ] `websocket-lanes`.

Carrier policy presets:

- [ ] Compatibility = fixed `https`.
- [ ] Auto = ordered carrier list + fallback `https` + learning.
- [ ] Manual = explicit carrier selection.

Auto defaults:

- [ ] fallback `https`.
- [ ] carrier learning on.
- [ ] conservative negotiation aggressiveness.

---

## LAB-6 — OpenWrt resource profiles

Profiles:

```text
low
standard
high
custom
```

- [ ] Test 128 MiB class routers.
- [ ] Test 256 MiB class routers.
- [ ] Test 512 MiB+ routers.
- [ ] Measure idle RSS.
- [ ] Measure active WEB sessions.
- [ ] Measure WebSocket/lane/media pressure.
- [ ] Test overload/recovery.
- [ ] Lock real numeric presets only after LAB measurements.
- [ ] Do not expose the entire upstream WEB limit matrix in normal LuCI mode.

---

## LAB-7 — LuCI WEB page

Create a separate model/module rather than further inflating the existing large CBI:

```text
usr/lib/lua/luci/model/cbi/telemt_web.lua
```

WEB page:

- [ ] Status.
- [ ] Enable.
- [ ] Listener.
- [ ] Public endpoint.
- [ ] Carrier policy.
- [ ] TLS frontend.
- [ ] VHosts.
- [ ] Profiles.
- [ ] Decoy.
- [ ] Resource profile.
- [ ] Advanced.
- [ ] Diagnostics.

### Keep the existing Users page central

- [ ] No separate WEB Users page.
- [ ] Preserve existing secret/enabled/TCP/IP/quota/expiration/stats/CSV UX.
- [ ] Add compact `WEB —` / `WEB N` indicator only.
- [ ] Add WEB links to the existing user link UX.
- [ ] Add WEB QR support.
- [ ] Protect deletion when WEB profiles reference the user.

Deletion UX:

```text
User is used by N WEB profiles.
Delete user and WEB bindings?
```

One meaningful confirmation only.

### Links / QR

Generate WEB links dynamically from UCI:

```text
tg://webproxy?server=<host>&secret=<secret>
tg://webproxy?server=<host>&secret=dd<secret>
```

- [ ] Do not store generated links in UCI.
- [ ] Expand QR whitelist only to `tg://proxy?` and `tg://webproxy?`.
- [ ] Do not allow arbitrary URL QR generation.

---

## LAB-8 — Telemt 3.5.6 operational controls

Advanced only:

- [ ] overload action: `drop` / `wait` / `respond`.
- [ ] default `drop`.
- [ ] decoy fast-track: `off` / `shadow` / `enforce`.
- [ ] default `off`.
- [ ] bridge recovery timeout override.
- [ ] optional per-profile session/stream limits.
- [ ] never enable `decoy_fasttrack=enforce` automatically.

---

## LAB-9 — WEB runtime status / diagnostics

- [ ] lifecycle state.
- [ ] generation/runtime instance.
- [ ] sessions/streams.
- [ ] carrier policy.
- [ ] carrier learning.
- [ ] capacity/overload counters.
- [ ] recovery counters.
- [ ] decoy state.
- [ ] resource pressure.
- [ ] aggregate useful Prometheus WEB metrics into a small number of operational cards.

Optional later controls:

- [ ] Pause WEB.
- [ ] Drain WEB.
- [ ] Resume WEB.

Do not insert automatic drain/pause into every Save & Apply.

---

## LAB-10 — final regression

Verify concurrently on one installation:

```text
Classic
DD
FakeTLS
WEB HTTPS
WEB HTTPS lanes
WEB WebSocket
WEB WebSocket lanes
```

Test:

- [ ] Users remain common.
- [ ] secret rotation affects all transports correctly.
- [ ] user disable affects all transports.
- [ ] expiration/quota accounting behaves correctly with WEB.
- [ ] API/metrics still work.
- [ ] firewall remains correct.
- [ ] no WAN exposure of WEB listener `27453`.
- [ ] no automatic WAN exposure of API `9091`.

---

## RC criteria

- [ ] Issue #17 fixed.
- [ ] Issue #19 functionally satisfied.
- [ ] Telemt 3.5.6 works with existing 3.4.x UCI.
- [ ] shared Users confirmed.
- [ ] External WEB frontend works.
- [ ] HAProxy works.
- [ ] NGINX works.
- [ ] all four WEB carriers work.
- [ ] WEB links + QR work.
- [ ] router-safe resource profiles exist.
- [ ] OpenWrt 24.10 IPK tested.
- [ ] OpenWrt 25.12 APK tested.
- [ ] `/etc/config/telemt` owned only by core package.

---

## Out of scope for the first stable release

- [ ] no own ACME client.
- [ ] no separate WEB user database.
- [ ] no duplicated WEB secrets.
- [ ] no second Telemt daemon for validation.
- [ ] no semantic hot-reload classifier.
- [ ] no PATCH API as persistent source of truth.
- [ ] no WAN exposure of `27453`.
- [ ] no mandatory NGINX dependency.
- [ ] no mandatory HAProxy dependency.
- [ ] no automatic installation of both frontends.
- [ ] no full rewrite of the existing LuCI app.

---

## Suggested commit order

```text
01 luci: stop owning /etc/config/telemt
02 core: bump build target to Telemt 3.5.6
03 core: marker-first binary version detection
04 core: 3.5.6 legacy regression fixes
05 luci: 3.5.6 compatibility/version cleanup

06 core: add WEB UCI schema
07 core: generate WEB listener
08 core: generate WEB vhosts/profiles
09 core: shared-user integrity checks
10 core: external WEB deployment

11 core: HAProxy frontend helper
12 luci: HAProxy frontend controls

13 core: NGINX frontend helper
14 luci: NGINX frontend controls

15 core: all WEB carriers
16 core: router resource profiles

17 luci: separate WEB page
18 luci: Users WEB integration
19 luci: tg://webproxy links + QR
20 luci: WEB status/diagnostics

21 docs: WEB deployment + migration
22 test: full regression matrix
23 release: 3.5.x RC
```

---

## Architectural invariants

```text
UCI = only persistent source of truth
TOML = generated runtime artifact
Users = shared across all transports
WEB = separate transport subsystem
TLS frontend = External OR HAProxy OR NGINX
Save & Apply = deterministic controlled apply/restart
```
