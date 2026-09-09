# Telemt 3.5.6 WEB — установка на роутер и smoke test

Этот чеклист предназначен для ветки `telemt-3.5.6-web`. Он не является release-инструкцией.

## 1. Перед установкой

Сохранить текущий UCI и сведения о пакетах:

```sh
uci export telemt > /tmp/telemt-before-web-test.uci
cp -a /etc/config/telemt /tmp/telemt.config.before-web-test
opkg list-installed | grep -E '^(telemt|luci-app-telemt) ' || true
apk info 2>/dev/null | grep -E '^(telemt|luci-app-telemt)$' || true
/etc/init.d/telemt status || true
```

Не удалять `/etc/config/telemt` перед upgrade: проверяется именно сохранение существующей конфигурации.

## 2. Установка test packages

Использовать core artifact из последнего успешного `Validate Telemt 3.5.6 WEB branch` для нужной версии OpenWrt/архитектуры и LuCI artifact `luci-app-telemt-web-test-ipk` из branch CI.

OpenWrt 24.10/IPK:

```sh
opkg install /tmp/telemt-ci.ipk
opkg install /tmp/luci-app-telemt-web-test.ipk
```

Если пакет уже установлен и package manager требует явного переустановочного режима, использовать штатный force-reinstall конкретной версии, не удаляя UCI вручную.

OpenWrt 25.12/APKv3: core брать только из настоящего APKv3 artifact core CI. LuCI APKv3 пока не является частью этого test path; не подменять его nFPM APKv2.

## 3. Сразу после установки — WEB должен оставаться выключен

```sh
uci -q get telemt.web.enabled
/etc/init.d/telemt restart
sleep 2
/etc/init.d/telemt status || true
logread -e telemt | tail -n 100
```

Ожидание: существующий Classic/DD/FakeTLS сервис стартует как раньше; новый WEB ingress сам не включается.

## 4. N5 negative test — malformed WEB при WEB=0 не ломает legacy

Сначала сохранить текущие WEB options:

```sh
uci export telemt > /tmp/telemt-before-n5.uci
```

Затем намеренно оставить WEB выключенным и записать плохой Auto candidate:

```sh
uci set telemt.web.enabled='0'
uci set telemt.web.carrier_policy='auto'
uci -q delete telemt.web.carrier_candidate
uci add_list telemt.web.carrier_candidate='definitely-invalid-carrier'
uci commit telemt
/etc/init.d/telemt restart
```

Ожидание:

- Telemt стартует;
- legacy listener работает;
- в runtime TOML отсутствует активный `[web]`;
- malformed WEB candidate не abort-ит генерацию TOML.

Проверка:

```sh
/etc/init.d/telemt status || true
pgrep -a telemt
if grep -q '^\[web\]' /tmp/etc/telemt.toml; then echo 'FAIL: WEB block active while disabled'; else echo 'OK: WEB isolated'; fi
```

После теста вернуть конфигурацию из backup либо через LuCI.

## 5. Legacy smoke до включения WEB

Проверить минимум:

- Telegram подключается через существующий Classic/DD/FakeTLS link;
- restart/reload работает;
- Users видны в LuCI;
- quota/expiration отображаются;
- Upstreams не исчезли;
- metrics/API доступны на прежних адресах;
- существующий public proxy port не изменился;
- `/etc/config/telemt` не был заменён дефолтным файлом.

Полезные команды:

```sh
uci show telemt
ss -lntp | grep telemt || netstat -lntp 2>/dev/null | grep telemt || true
logread -e telemt | tail -n 150
grep -nE '^\[web\]|transport = "web"|^\[access.users\]|^\[general.links\]' /tmp/etc/telemt.toml
```

## 6. Проверка LuCI Users integration

На основной странице Users для пользователя без WEB binding должно отображаться `WEB: —`.

После создания WEB profile для существующего user должны появиться:

- `WEB: N profiles`;
- hostname/VHost;
- `PLAIN` или `DD`;
- `tg://webproxy` link;
- Copy WEB;
- QR.

Secret при этом остаётся только в общем `config user`.

Удаление user с WEB bindings должно потребовать одно подтверждение и удалить user вместе со ссылающимися `web_profile`, но не удалять общий VHost.

## 7. Только после legacy smoke — включение WEB

Первый hardware pass выполнять с carrier `https` и одним VHost/profile. После успешного connect/reconnect/media перейти к:

1. `https-lanes`;
2. `websocket`;
3. `websocket-lanes`;
4. `carrier_policy=auto`.

Полный acceptance matrix находится в `docs/WEB_LAB5_HARDWARE_ACCEPTANCE.ru.md`.

## 8. Что сохранить после теста

```sh
uci export telemt > /tmp/telemt-after-web-test.uci
logread -e telemt > /tmp/telemt-web-test.log
cp -a /tmp/etc/telemt.toml /tmp/telemt-web-test.toml
ps w | grep '[t]elemt' > /tmp/telemt-web-test.ps
cat /proc/meminfo > /tmp/telemt-web-test.meminfo
```

Для LAB-6 дополнительно фиксировать RSS/peak RSS при idle, обычной сессии, lanes и media pressure. Численные resource presets до этих измерений не задавать.
