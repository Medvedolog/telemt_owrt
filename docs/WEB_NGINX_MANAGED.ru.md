# Telemt 3.5.6 WEB Proxy: managed NGINX on OpenWrt

Этот режим предназначен для случая, когда TLS-терминатор работает на том же OpenWrt-роутере, что и Telemt.

Топология:

```text
Telegram Desktop
        |
        | HTTPS/WSS :443
        v
OpenWrt NGINX
        |
        | private HTTP/1.1
        v
Telemt WEB 127.0.0.1:27453
```

## Что именно управляется

Managed NGINX сознательно не захватывает основной конфиг OpenWrt NGINX.

Telemt владеет только одним fragment:

```text
/etc/nginx/conf.d/telemt-web.conf
```

Не изменяются:

```text
/etc/config/nginx
/etc/nginx/nginx.conf
/etc/nginx/uci.conf.template
/etc/nginx/conf.d/_lan.conf
```

Стандартный OpenWrt NGINX включает `conf.d/*.conf` внутрь своего `http {}`. Поэтому для NGINX не нужен HAProxy-подобный takeover всего основного конфигурационного файла.

Если `/etc/nginx/conf.d/telemt-web.conf` уже существовал до первого managed apply, он один раз сохраняется как:

```text
/etc/nginx/conf.d/telemt-web.conf.telemt-backup
```

## Требования

Нужен стандартный SSL-capable OpenWrt NGINX с `nginx-util`, например `nginx-ssl` или `nginx-full`.

Core Telemt не имеет hard dependency на NGINX: пакет можно использовать без него в режимах External или HAProxy.

Helper проверяет:

- `/usr/sbin/nginx`;
- `/usr/bin/nginx-util`;
- `/etc/init.d/nginx`;
- наличие HTTP SSL module;
- наличие HTTP proxy module;
- что TCP/443 не занят другим процессом вроде uhttpd или HAProxy;
- сертификат и private key;
- включённый WEB listener на `127.0.0.1`;
- trusted frontend `127.0.0.1/32`;
- хотя бы один корректный enabled WEB vhost.

## UCI

Пример минимальной конфигурации frontend:

```sh
uci set telemt.web.enabled='1'
uci set telemt.web.tls_terminator='nginx'
uci set telemt.web.nginx_managed='1'
uci set telemt.web.nginx_bind='443'
uci set telemt.web.nginx_ipv6='0'
uci set telemt.web.nginx_cert='/etc/acme/example/fullchain.cer'
uci set telemt.web.nginx_key='/etc/acme/example/example.key'
uci set telemt.web.nginx_auto_fw='1'

uci set telemt.web_listener.enabled='1'
uci set telemt.web_listener.ip='127.0.0.1'
uci set telemt.web_listener.port='27453'
uci -q delete telemt.web_listener.trusted_proxy_cidr
uci add_list telemt.web_listener.trusted_proxy_cidr='127.0.0.1/32'

uci commit telemt
```

`nginx_bind` поддерживает:

```text
443
0.0.0.0:443
192.0.2.10:443
```

Для IPv6 используется отдельный switch:

```uci
option nginx_ipv6 '1'
```

Он добавляет `[::]:443`.

## Проверка и применение

Helper:

```sh
/usr/libexec/telemt-web-nginx status
/usr/libexec/telemt-web-nginx render
/usr/libexec/telemt-web-nginx check
/usr/libexec/telemt-web-nginx apply
/usr/libexec/telemt-web-nginx restore
```

Рекомендуемый порядок:

```sh
/etc/init.d/telemt restart
/usr/libexec/telemt-web-check
/usr/libexec/telemt-web-nginx check
/usr/libexec/telemt-web-nginx apply
/usr/libexec/telemt-web-nginx status
```

`check` временно подставляет candidate fragment, прогоняет его через активный OpenWrt NGINX config и затем возвращает прежнее состояние без reload.

`apply`:

1. создаёт candidate fragment;
2. проверяет его через NGINX;
3. устанавливает только `telemt-web.conf`;
4. при необходимости открывает WAN TCP/443;
5. делает reload/start NGINX;
6. при ошибке возвращает предыдущий fragment и firewall state, насколько это возможно.

`restore` возвращает сохранённый pre-Telemt fragment либо удаляет Telemt-managed fragment, если до Telemt файла на этом пути не было.

## Генерируемая proxy-семантика

Managed fragment содержит примерно следующую логику:

```nginx
map $http_upgrade $telemt_connection_upgrade {
    default upgrade;
    ''      '';
}

upstream telemt_web_managed {
    server 127.0.0.1:27453;
    keepalive 64;
}

server {
    listen 443 ssl;
    server_name proxy.example.com;

    ssl_certificate /etc/acme/example/fullchain.cer;
    ssl_certificate_key /etc/acme/example/example.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    access_log off;
    client_max_body_size 2m;

    location / {
        proxy_pass http://telemt_web_managed;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $telemt_connection_upgrade;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_next_upstream off;
    }
}
```

Ключевые свойства:

- X-Forwarded-For перезаписывается реальным peer IP, а не дополняется недоверенной цепочкой;
- Host сохраняется;
- Upgrade/Connection уже готовы для последующего WebSocket carrier;
- retries отключены;
- request/response buffering отключены;
- отдельный WEB access log не создаётся;
- private Telemt backend `27453` не открывается firewall rule в WAN.

## HTTP/2 и будущие carriers

Первый стабильный managed NGINX path ориентирован на carrier `https`.

Для будущего `https-lanes` потребуется публичный HTTP/2. Поддержку carriers и соответствующую генерацию frontend-конфига лучше включать отдельным патчем после проверки базового HTTPS path на железе.

WebSocket headers уже сохраняются, но выбор `websocket`/`websocket-lanes` пока не является частью этого LAB.

## ACME

Стандартный OpenWrt NGINX имеет собственный reload trigger при `acme.renew`, поэтому отдельный Telemt ACME hotplug для NGINX не нужен.

После обновления файлов сертификата NGINX перечитает их при штатном reload.

## Конфликт порта 443

Основной практический конфликт на OpenWrt — `uhttpd`, HAProxy или другой процесс, уже слушающий TCP/443.

Helper разрешает уже работающий NGINX, поскольку Telemt добавляет server block в тот же NGINX process. Любой другой процесс на 443 блокирует managed apply до явного разрешения конфликта администратором.

Telemt сам не переносит LuCI/uhttpd на другой порт автоматически.

## Удаление пакета

`prerm` пакета Telemt пытается выполнить `telemt-web-nginx restore`, если обнаруживает активный managed fragment.

Это нужно, чтобы удаление Telemt не оставляло NGINX с конфигурацией, указывающей на уже отсутствующий backend.

Backup pre-existing fragment намеренно не удаляется автоматически как аварийная копия конфигурации администратора.

## Что не делает managed NGINX

- не устанавливает NGINX автоматически;
- не выпускает TLS-сертификаты;
- не управляет `/etc/config/nginx`;
- не переписывает LuCI NGINX `_lan` server;
- не открывает `27453` в WAN;
- не включает все WEB carriers до их отдельной проверки;
- не превращает NGINX в обязательную зависимость Telemt.
