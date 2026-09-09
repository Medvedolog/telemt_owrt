# Telemt 3.5.6 WEB Proxy — External TLS frontend на OpenWrt

Этот документ описывает первый поддерживаемый LAB-2 сценарий: Telemt работает как приватный WEB backend, а TLS завершается внешним NGINX или HAProxy.

> В этой ветке `tls_terminator=external` означает: `telemt_owrt` генерирует и запускает только Telemt WEB backend. Он не изменяет конфигурацию NGINX/HAProxy и не управляет сертификатами.

## Топология

```text
Telegram Desktop
    -> HTTPS/WSS :443
    -> NGINX или HAProxy (TLS termination)
    -> plain HTTP/1.1
    -> Telemt WEB backend 127.0.0.1:18080
```

Telemt не должен получать публичный TLS напрямую. Порт `18080` не открывается в WAN firewall.

## Минимальный UCI

Пример с одним общим пользователем, одним WEB vhost и DD-профилем:

```uci
config user 'webuser'
        option enabled '1'
        option secret '0123456789abcdef0123456789abcdef'

config web 'web'
        option enabled '1'
        option carrier_policy 'fixed'
        option carrier 'https'
        option memory_profile 'standard'
        option tls_terminator 'external'
        option debug_enabled '0'

config web_listener 'web_listener'
        option enabled '1'
        option ip '127.0.0.1'
        option port '18080'
        option client_ip_source 'x_forwarded_for'
        list trusted_proxy_cidr '127.0.0.1/32'

config web_vhost 'web_main'
        option enabled '1'
        option name 'main'
        option host 'proxy.example.com'
        option public_addr '203.0.113.10:443'
        option decoy_mode 'http_upstream'
        option decoy_upstream 'http://127.0.0.1:18081'

config web_profile 'web_main_user'
        option enabled '1'
        option vhost 'main'
        option user 'webuser'
        option secret_mode 'dd'
```

`config user` остаётся единственной базой пользователей. В `web_profile` нет собственного secret, quota или expiration.

`public_addr` — конкретный публичный IP с портом `443`, а не hostname.

На текущем LAB поддерживаются:

- carrier: `https`;
- secret modes: `plain`, `dd`;
- decoy: `http_upstream`;
- один или несколько `web_vhost`/`web_profile`.

## Где размещён TLS frontend

### На том же OpenWrt

Оставьте:

```uci
option ip '127.0.0.1'
list trusted_proxy_cidr '127.0.0.1/32'
```

NGINX/HAProxy должен подключаться к `127.0.0.1:18080`.

Учтите, что штатный `uhttpd` OpenWrt часто уже занимает TCP/443 для LuCI. Перед запуском NGINX/HAProxy на `:443` конфликт нужно решить явно. `telemt_owrt` в External mode не перенастраивает `uhttpd` автоматически.

### На отдельном VPS/хосте в LAN

WEB listener должен быть доступен только этому frontend-хосту. Укажите точный private/LAN address backend и доверяйте непосредственному адресу frontend, например:

```uci
option ip '192.168.1.1'
list trusted_proxy_cidr '192.168.1.10/32'
```

Не открывайте backend `18080` в WAN и не используйте `/0` в `trusted_proxy_cidr`.

## NGINX

Минимальная конфигурация по upstream Telemt 3.5.6:

```nginx
map $http_upgrade $telemt_connection_upgrade {
    default upgrade;
    ''      '';
}

upstream telemt_web {
    server 127.0.0.1:18080;
    keepalive 64;
}

server {
    listen 443 ssl;
    http2 on;
    server_name proxy.example.com;
    access_log off;

    ssl_certificate     /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;

    client_max_body_size 2m;

    location / {
        proxy_pass http://telemt_web;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $telemt_connection_upgrade;

        proxy_connect_timeout 5s;
        proxy_send_timeout 65s;
        proxy_read_timeout 65s;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_next_upstream off;
    }
}
```

Требования:

- `map` находится в `http` context;
- `X-Forwarded-For` перезаписывается одним `$remote_addr`, а не дополняется;
- upstream retries выключены;
- Host, Upgrade и Connection сохраняются;
- private hop NGINX -> Telemt остаётся HTTP/1.1;
- для будущего `https-lanes` публичный endpoint должен поддерживать HTTP/2;
- access log лучше выключить, чтобы carrier credentials не попали в журналы.

Синтаксис включения HTTP/2 зависит от версии NGINX; используйте эквивалент, поддерживаемый установленным пакетом.

## HAProxy

Минимальная конфигурация по upstream Telemt 3.5.6:

```haproxy
frontend public_https
    mode http
    no log
    bind :443 ssl crt /etc/haproxy/certs/proxy.example.com.pem alpn h2,http/1.1
    acl telemt_web_host hdr(host) -i proxy.example.com proxy.example.com:443
    use_backend telemt_web if telemt_web_host
    timeout client 65s

backend telemt_web
    mode http
    option http-keep-alive
    retries 0
    timeout connect 5s
    timeout server 65s
    http-request set-header Host proxy.example.com
    http-request del-header X-Forwarded-For
    http-request set-header X-Forwarded-For %[src]
    server telemt_web_1 127.0.0.1:18080 check
```

HAProxy также не должен переписывать path, raw query, body, `Connection`, `Upgrade`, `Sec-WebSocket-*` и carrier headers.

## Decoy

В LAB-2 используется только `http_upstream`:

```uci
option decoy_mode 'http_upstream'
option decoy_upstream 'http://127.0.0.1:18081'
```

Origin должен быть `http://` на loopback/link-local/private IP literal, без credentials, path, query и fragment.

Frontend должен передавать в Telemt весь vhost, а не только известные WEB carrier paths. Иначе обычный decoy path Telemt обходится и внешний профиль становится отличимым.

## Применение

После изменения UCI:

```sh
uci commit telemt
/etc/init.d/telemt reload
```

WEB structure находится в CORE части сгенерированного TOML, поэтому существующий reload classifier выполнит controlled hard restart при изменении listener/vhost/profile.

Проверка состояния:

```sh
/usr/libexec/telemt-web-check
```

Ожидаемый результат при рабочем backend содержит примерно:

```text
configured: enabled
tls_frontend: external
backend: 127.0.0.1:18080
runtime_toml: active
process: running
backend_socket: listening
```

Дополнительно:

```sh
logread -e telemt
```

## Ссылка Telegram

Plain:

```text
tg://webproxy?server=proxy.example.com&secret=0123456789abcdef0123456789abcdef
```

DD:

```text
tg://webproxy?server=proxy.example.com&secret=dd0123456789abcdef0123456789abcdef
```

Порт в WEB link не указывается: публичный endpoint использует `443`.

## Acceptance checklist LAB-2

- [ ] Telemt 3.5.6 установлен.
- [ ] `web.enabled=1`.
- [ ] Есть минимум один enabled vhost.
- [ ] Есть минимум один enabled profile с enabled shared user.
- [ ] `public_addr` указывает точный публичный IP `:443`.
- [ ] WEB backend не открыт в WAN.
- [ ] TLS frontend имеет валидный сертификат на `host`.
- [ ] Frontend передаёт весь vhost в Telemt.
- [ ] Frontend перезаписывает `X-Forwarded-For` реальным client IP.
- [ ] Reverse-proxy retries выключены.
- [ ] `/usr/libexec/telemt-web-check` показывает active/listening.
- [ ] Обычный HTTPS-запрос к vhost получает decoy response.
- [ ] `tg://webproxy` подключается в целевом Telegram Desktop.
- [ ] Secret rotation отключает старую ссылку и включает новую после apply.
- [ ] Disable общего `config user` выключает его WEB profile.

## Что пока не делает External mode

- не устанавливает NGINX/HAProxy;
- не создаёт сертификаты и не управляет ACME;
- не редактирует `/etc/haproxy.cfg`;
- не редактирует NGINX/UCI конфигурацию;
- не освобождает порт 443 от `uhttpd`;
- не включает остальные WEB carriers автоматически.

Managed HAProxy и Managed NGINX идут отдельными следующими LAB-этапами.

Upstream reference: `telemt/telemt`, `docs/WEB/WEB_PROXY.ru.md`, tag `3.5.6`.
