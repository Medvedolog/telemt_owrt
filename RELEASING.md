# Релизы telemt (ядро) через owfeed

Репозиторий собирает пакеты `telemt` для трёх архитектур (`aarch64_generic`, `aarch64_cortex-a53`, `x86_64`) в два нативных формата из одного staged tree:

- OpenWrt 25.12+ — APKv3 (`dist/<arch>/telemt-X.Y.Z-rN.apk`);
- OpenWrt 24.10 — IPK (`dist/<arch>/telemt_X.Y.Z-rN_<arch>.ipk`).

Схема та же, что у `luci-app-telemt` и `luci-app-podkop-bot`. nFPM для ядра больше не используется.

## Откуда берётся бинарник

- **aarch64** — собирается из исходников `telemt/telemt` по тегу `X.Y.Z` (`cross build --release --locked`, `opt-level=z`, LTO, UPX);
- **x86_64** — официальный релизный архив upstream, проверяется по `.sha256`;
- в оба бинарника дописывается трейлер `MTProxy vX.Y.Z`: по нему `init.d` определяет версию, а `tools/stage.sh` и `tools/check-package.sh` отказываются работать без него.

Версия upstream = базовая версия пакета. Она хранится в `version.txt`; тег с другой базовой версией не соберётся (`tools/version.sh`).

`/etc/config/telemt` — conffile: правки оператора при обновлении сохраняются, а `scripts/postinst` только добавляет недостающие секции и опции.

## Однократная настройка подписей

Нужны два постоянных ключа. Их нельзя генерировать в CI на каждый релиз: feed один раз закрепляет публичный ключ автора.

На доверенной машине с `gh`:

```sh
./tools/setup-keys.sh
```

Скрипт загрузит в GitHub Secrets `TELEMT_SIGN_KEY` (EC prime256v1, подпись пакетов) и `TELEMT_USIGN_KEY` (usign, подпись `manifest.txt` и assets), а публичные половины положит в `keys/telemt-sign.pub.pem` и `keys/telemt-release.pub`. Их нужно **закоммитить до первого тега** — без них `release-preflight` не даст выпустить релиз. Приватные файлы из `keys-setup/` сохраните вне git и удалите каталог. Ключи не вращают ради обычного релиза.

## Pipeline

```text
sources -> build -> verify -> release
```

- `sources` — `tools/check-sources.sh`: синтаксис shell и контракты генератора/UCI/WEB;
- `build` — сборка бинарников, `tools/stage.sh`, `owfeed plan/check/build`, затем `tools/check-package.sh` разбирает IPK каждой архитектуры;
- `verify` — `owlab`: ставит x86_64-пакет на OpenWrt 25.12.5 (APK) и 24.10.8 (IPK), проверяет файлы, версию бинарника и миграцию UCI (`postinst`). aarch64-пакеты проверяются структурно в `build`;
- `release` — только для тега, после build+verify: reusable workflow owfeed подписывает пакеты и manifest и публикует GitHub Release.

В build/verify секретов нет; они доступны только job `release`.

## Создание релиза

1. Обновите `version.txt` до версии upstream Telemt и убедитесь, что тег `X.Y.Z` есть в `telemt/telemt`.
2. Поставьте тег. Голый `X.Y.Z` даёт `X.Y.Z-r1`; `X.Y.Z-N` — `X.Y.Z-rN` (пересборка того же upstream).

```sh
git tag 3.5.8
git push origin 3.5.8
```

Теги вида `3.5.6-web-alpha1` pipeline не запускают.

Сырые бинарники (`telemt-aarch64-musl`, `telemt-x86_64-musl`) и копия release notes upstream в релиз больше не публикуются: он состоит из подписанных пакетов, `manifest.txt` и подписей.

## Добавление в owfeed-packages

Intake — signed upstream manifest: feed забирает опубликованные пакеты, проверяет manifest и подпись автора и включает те же байты в индекс. После первого подписанного релиза в PR в `owfeed/owfeed-packages` кладутся публичный ключ и `packages/telemt/upstream.sh`:

```sh
KIND="manifest"
REPO="Medvedolog/telemt_owrt"
VERSION="3.5.8-r1"
TAG="3.5.8"
SIG_KEY="keys/telemt-release.pub"
SIG_KEY_ID="<id usign-ключа>"
AUTO_MERGE="yes"
```

Формат intake — внешний контракт: перед PR сверьтесь с актуальным `CONTRIBUTING.md` в owfeed-packages. Лицензия пакета в `owfeed.yml` не указана намеренно — задайте её по лицензии upstream, прежде чем подавать пакет в feed.

## Локальная проверка

Нужны `owfeed`, доступ к `downloads.openwrt.org` и `OWFEED_SIGN_KEY` в окружении:

```sh
bash tools/check-sources.sh
AARCH64_BIN=... X86_64_BIN=... ./tools/stage.sh 3.5.8
owfeed plan && owfeed check && owfeed build
./tools/check-package.sh 3.5.8
```

`dist/` — build output, в git не коммитится. `owfeed.lock` коммитится; обновлять: `owfeed lock --update`.
