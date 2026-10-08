# Changelog / История изменений

Формат версии пакета / package version: `X.Y.Z-rN`, где `X.Y.Z` — версия upstream Telemt, `rN` — ревизия упаковки.
`X.Y.Z-rN`: `X.Y.Z` is the upstream Telemt version, `rN` is the packaging revision.

## 3.5.14-r1 — RC preparation (unreleased, 2026-10-08)

- Pin upstream Telemt **3.5.14** (six point releases / 31 upstream commits after 3.5.8). Binary sources are still taken directly from the upstream tag; no Rust fork.
- Includes upstream ME pool convergence/recovery, conntrack recovery, and WEB transport improvements.
- Preserve conservative OpenWrt policy: procd service, full TOML generated from UCI by init.d, existing restart decisions, and the existing forced shutdown on package upgrade.
- On upgrade, restore an **absent** named `telemt.general` UCI section (disabled by default) without modifying existing user settings. Warn rather than silently rewriting an unexpected section type.
- New WEB parameters are intentionally left to upstream defaults until separate UI/generator validation; no `base_path` link generation is enabled.

## 3.5.8-r2 — 2026-09-29

**RU**
- Нейтральное техническое описание пакета (требование приёма в сообщественный feed). Содержимое пакета не менялось относительно 3.5.8-r1.

**EN**
- Neutral, technical package description (required for community-feed intake). Payload unchanged from 3.5.8-r1.

## 3.5.8-r1 — 2026-09-29

**RU**
- Telemt **3.5.8** (Rust MSRV 1.88 проверяется по `Cargo.toml` upstream).
- **WEB Proxy** (`transport = "web"`, carrier `https` / `https-lanes` / `websocket` / `websocket-lanes`, режим `auto`, vhosts и профили с общими пользователями, managed HAProxy/NGINX). По умолчанию выключен (`web.enabled=0`): поведение Classic/DD/FakeTLS не меняется.
- `init.d`: проверка версии бинарника — WEB не генерируется для известного бинарника старше 3.5.6.
- **`[web.debug]`**: `sideband` и `capture_lifecycle` (диагностика WEB Bridge через аутентифицированный same-origin HTTPS sideband), всё выключено по умолчанию; секция пишется только для бинарника ≥ 3.5.8. UCI: `web.debug_enabled`, `web.debug_sideband`, `web.debug_capture_lifecycle`.
- `direct_relay_buffer_budget_max_mib` (лимит буфера direct-relay, 0 = Auto).
- Пакеты собираются через **owfeed**: IPK (OpenWrt 24.10) и APKv3 (25.12) для `aarch64_generic`, `aarch64_cortex-a53`, `x86_64`; проверка установки на реальном OpenWrt (`owlab`); подписанный релиз с `manifest.txt`. nFPM больше не используется. См. [RELEASING.md](RELEASING.md).
- Реальные maintainer-скрипты: `postinst` (миграция портов и UCI-секций WEB без перезаписи значений оператора, включение и перезапуск сервиса), `prerm`, `postrm`.
- Лицензии: обвязка — MIT; бинарник — TELEMT License 3.3. Текст лицензии upstream и `NOTICE` ставятся в `/usr/share/licenses/telemt/`.
- В релизы больше не публикуются сырые бинарники и копия release notes upstream: только подписанные пакеты, `manifest.txt` и подписи.

**Перед обновлением**
- Старые конфиги без `base_path` продолжают работать. Поддержка `base_path` для WEB vhost в этой версии обвязки ещё не добавлена.
- Изменения `server.max_connections`, `server.conntrack_control`, `general.direct_relay_buffer_budget_max_bytes` в самом Telemt применяются только после рестарта процесса.
- Не удаляйте `*.lock` рядом с управляемыми Telemt файлами, конфиги и includes на Unix должны быть обычными файлами (без symlink/hard-link).

**EN**
- Telemt **3.5.8** (Rust MSRV 1.88 is checked against the upstream `Cargo.toml`).
- **WEB Proxy** (`transport = "web"`, carriers `https` / `https-lanes` / `websocket` / `websocket-lanes`, `auto` policy, vhosts and profiles with shared users, managed HAProxy/NGINX). Off by default (`web.enabled=0`): Classic/DD/FakeTLS behaviour is unchanged.
- `init.d` checks the binary version: WEB is not generated for a known binary older than 3.5.6.
- **`[web.debug]`**: `sideband` and `capture_lifecycle` (WEB Bridge diagnostics over an authenticated same-origin HTTPS sideband), all off by default; the section is written only for binaries >= 3.5.8. UCI: `web.debug_enabled`, `web.debug_sideband`, `web.debug_capture_lifecycle`.
- `direct_relay_buffer_budget_max_mib` (direct-relay buffer ceiling, 0 = Auto).
- Packages are built with **owfeed**: IPK (OpenWrt 24.10) and APKv3 (25.12) for `aarch64_generic`, `aarch64_cortex-a53`, `x86_64`; install verified on real OpenWrt (`owlab`); signed release with `manifest.txt`. nFPM is no longer used. See [RELEASING.md](RELEASING.md).
- Real maintainer scripts: `postinst` (port and WEB UCI migration that never overwrites operator values, service enable and restart), `prerm`, `postrm`.
- Licences: the integration is MIT; the binary is under the TELEMT License 3.3. The upstream licence text and a `NOTICE` are installed in `/usr/share/licenses/telemt/`.
- Releases no longer carry raw binaries or a copy of the upstream release notes: only signed packages, `manifest.txt` and signatures.

**Before upgrading**
- Older configs without `base_path` keep working. `base_path` support for WEB vhosts is not part of this packaging release yet.
- Changes to Telemt's own `server.max_connections`, `server.conntrack_control` and `general.direct_relay_buffer_budget_max_bytes` apply only after a process restart.
- Do not delete `*.lock` files next to Telemt-managed files; on Unix, configs and includes must be regular files (no symlinks or hard links).
