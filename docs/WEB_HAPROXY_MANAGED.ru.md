# Telemt 3.5.6 WEB — managed HAProxy на OpenWrt

Этот режим предназначен для случая, когда TLS-терминатор HAProxy работает **на том же OpenWrt-роутере**, что и Telemt.

Трафик:

```text
Telegram Desktop
  -> HTTPS/WSS :443
  -> HAProxy (TLS termination)
  -> HTTP/1.1 127.0.0.1:27453
  -> Telemt WEB listener
```

## Важная модель владения

OpenWrt HAProxy запускается штатным `/etc/init.d/haproxy` и читает `/etc/haproxy.cfg`.
HAProxy не имеет NGINX-подобного `include` для добавления нашего fragment в этот файл, поэтому managed mode является **явным takeover** штатного HAProxy config.

Telemt не меняет `/etc/haproxy.cfg`, пока одновременно не выполнены условия:

```uci
option tls_terminator 'haproxy'
option haproxy_managed '1'
```

При первом `apply` существующий `/etc/haproxy.cfg` сохраняется как:

```text
/etc/haproxy.cfg.telemt-backup
```

Backup не перезаписывается последующими apply.

## Пакет HAProxy

Нужен именно SSL-вариант:

OpenWrt 25.12+:

```sh
apk add haproxy
```

OpenWrt 24.10:

```sh
opkg update
opkg install haproxy
```

`haproxy-nossl` не подходит. Helper проверяет `haproxy -vv` и наличие OpenSSL support до любых изменений live config.

## UCI

Минимальный пример:

```uci
config web 'web'
        option enabled '1'
        option carrier 'https'
        option tls_terminator 'haproxy'
        option haproxy_managed '1'
        option haproxy_bind ':443'
        option haproxy_cert '/etc/acme/proxy.example.com/fullchain.pem'
        option haproxy_key '/etc/acme/proxy.example.com/key.pem'
        option haproxy_auto_fw '1'

config web_listener 'web_listener'
        option enabled '1'
        option ip '127.0.0.1'
        option port '27453'
        option client_ip_source 'x_forwarded_for'
        list trusted_proxy_cidr '127.0.0.1/32'
```

Пути certificate/key приведены только как пример. Используйте реальные пути вашей ACME/certificate setup.

Если `haproxy_key` пуст, файл `haproxy_cert` должен уже содержать certificate chain и private key в PEM.
Если certificate и key лежат раздельно, helper собирает private runtime bundle:

```text
/var/etc/telemt-haproxy.pem
```

с mode `0600`.

## Команды helper

```sh
/usr/libexec/telemt-web-frontend status
/usr/libexec/telemt-web-frontend render
/usr/libexec/telemt-web-frontend check
/usr/libexec/telemt-web-frontend apply
/usr/libexec/telemt-web-frontend restore
```

### `status`

Только читает UCI/HAProxy state.

### `render`

Показывает конфиг, который будет сгенерирован. Live config не меняет.

### `check`

Создаёт временный PEM/config и запускает:

```sh
haproxy -c -q -V -f <temporary-config>
```

Live `/etc/haproxy.cfg` не меняется.

### `apply`

Порядок:

1. Проверяет `web.enabled`, `tls_terminator`, `haproxy_managed`.
2. Проверяет SSL support HAProxy.
3. Требует private Telemt backend `127.0.0.1`.
4. Проверяет `127.0.0.1/32` в trusted proxy list.
5. Проверяет certificate/key и enabled WEB vhosts.
6. Проверяет конфликт TCP/443 с uhttpd/NGINX/другим listener.
7. Собирает временный PEM/config.
8. Выполняет `haproxy -c`.
9. Сохраняет старый `/etc/haproxy.cfg`, если это первый takeover.
10. Атомарно устанавливает managed config.
11. При `haproxy_auto_fw=1` создаёт firewall rule `firewall.telemt_web_https` для WAN TCP/443.
12. Запускает или `force_reload` HAProxy.
13. При ошибке откатывает предыдущий config/runtime PEM и firewall rule.

### `restore`

Проверяет сохранённый backup через `haproxy -c`, возвращает его в `/etc/haproxy.cfg`, удаляет Telemt firewall rule и reload'ит HAProxy.

## Что генерируется

Схематично:

```haproxy
global
    maxconn 4096

defaults
    mode http
    timeout connect 5s
    timeout client 65s
    timeout server 65s
    timeout tunnel 65s

frontend telemt_web_https
    mode http
    bind :443 ssl crt /var/etc/telemt-haproxy.pem alpn h2,http/1.1 ssl-min-ver TLSv1.2
    acl telemt_web_host hdr(host) -i proxy.example.com proxy.example.com:443
    use_backend telemt_web if telemt_web_host

backend telemt_web
    mode http
    option http-keep-alive
    retries 0
    http-request del-header X-Forwarded-For
    http-request set-header X-Forwarded-For %[src]
    server telemt_web_1 127.0.0.1:27453 check
```

Принципы:

- HAProxy сохраняет исходный `Host`;
- входной `X-Forwarded-For` удаляется и заменяется реальным source IP;
- upstream retries выключены;
- `h2,http/1.1` оставляет возможность `https-lanes` и WebSocket Upgrade в следующих LAB;
- приватный hop HAProxy -> Telemt остаётся HTTP/1.1;
- access logging carrier requests не включается.

## Несколько WEB vhosts

Helper собирает все enabled `config web_vhost` и разрешает их `Host`/`Host:443` одним ACL.
Один TLS certificate bundle должен покрывать все эти имена (SAN/wildcard), пока в managed mode используется один certificate source.

## ACME renewal

Пакет устанавливает hotplug:

```text
/etc/hotplug.d/acme/95-telemt-web-haproxy
```

На `issued`/`renewed`, если активны:

```text
web.enabled=1
tls_terminator=haproxy
haproxy_managed=1
```

он повторно выполняет безопасный `telemt-web-frontend apply`: пересобирает runtime PEM, выполняет `haproxy -c` и делает `force_reload`.

## Конфликт LuCI/uhttpd на :443

Managed helper **не останавливает uhttpd автоматически**.
Если TCP/443 занят не HAProxy, `check/apply` завершаются ошибкой до изменения `/etc/haproxy.cfg`.

Варианты:

- перенести HTTPS LuCI/uhttpd на другой port;
- bind HAProxy на конкретный публичный IP `x.x.x.x:443`, если topology позволяет;
- оставить `tls_terminator=external` и терминировать TLS на другом узле.

## Firewall

`haproxy_auto_fw=1` создаёт только публичное правило WAN TCP/443:

```text
firewall.telemt_web_https
```

Порт Telemt `27453` в WAN firewall никогда не открывается.

При `restore` правило удаляется.

## Диагностика

```sh
/usr/libexec/telemt-web-frontend status
/usr/libexec/telemt-web-check
/etc/init.d/haproxy check
logread -e haproxy
logread -e telemt
ss -lntp | grep -E ':443|:27453'
```

Ожидаемая схема:

```text
HAProxy :443       LISTEN
Telemt 127.0.0.1:27453 LISTEN
```

## Acceptance для LAB-3

- existing non-managed `/etc/haproxy.cfg` сохраняется перед takeover;
- `haproxy-nossl` отклоняется;
- invalid certificate/config не заменяет live config;
- занятый другим daemon `:443` отклоняется до apply;
- WEB backend остаётся loopback-only;
- XFF содержит ровно client source IP;
- `retries 0`;
- HTTPS/WSS frontend предлагает ALPN `h2,http/1.1`;
- WAN открыт только `:443`, не `:27453`;
- ACME renewal пересобирает PEM и reload'ит HAProxy;
- `restore` возвращает pre-Telemt HAProxy config.
