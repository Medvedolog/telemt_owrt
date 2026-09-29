# Telemt 3.5.6 WEB — LAB-5 hardware/client acceptance

Дата: 2026-09-09

Цель: воспроизводимо проверить fixed carriers и auto-negotiation Telemt 3.5.6 WEB на реальном OpenWrt-устройстве с текущим stable Telegram Desktop. Этот документ не заменяет CI: он закрывает именно public TLS / frontend / client / hardware path.

## 1. Scope

Проверяем:

- `https`
- `https-lanes`
- `websocket`
- `websocket-lanes`
- `carrier_policy=auto`
- External TLS frontend
- managed HAProxy
- managed NGINX

Не считаем LAB-5 закрытым только по факту `Connected` в Telegram. Для каждого carrier фиксируем transport evidence, reconnect/media/idle и отсутствие regressions в legacy ingress.

## 2. Test bench

Зафиксировать перед началом:

```text
Router model:
SoC:
RAM:
OpenWrt release:
Kernel:
telemt package version/hash:
luci-app-telemt version/hash:
Telegram Desktop version:
Frontend: external | haproxy | nginx
Public FQDN:
Public IP:
WAN type:
IPv4/IPv6:
```

Не публиковать реальные WEB/MTProxy secrets в issue, CI log или paste.

## 3. Preflight

На роутере:

```sh
uci show telemt.web
uci show telemt.web_listener
/etc/init.d/telemt restart
/usr/libexec/telemt-web-check
ss -lntp | grep -E '(:443|:27453)'
logread -e telemt
```

Ожидается:

- Telemt WEB backend слушает только ожидаемый private/loopback address, по умолчанию `127.0.0.1:27453`;
- WAN не имеет прямого правила на 27453;
- public `:443` принадлежит только выбранному TLS frontend;
- runtime `/tmp/etc/telemt.toml` содержит выбранный WEB listener и `[web]` до `# --- DYNAMIC CONFIG ---`;
- `web_trusted_proxy_cidrs` доверяет только непосредственному frontend peer;
- `/0` отсутствует.

Для managed frontend дополнительно:

```sh
/usr/libexec/telemt-web-frontend status   # HAProxy
/usr/libexec/telemt-web-nginx status      # NGINX
```

## 4. Fixed carrier matrix

Каждый fixed carrier проверяется отдельно. После смены carrier выполнить Save & Apply / restart и убедиться, что effective runtime соответствует выбранному exact token.

| ID | Carrier | Public transport evidence | Telegram Desktop acceptance | Pass criteria |
|---|---|---|---|---|
| F1 | `https` | HTTPS HTTP requests, без WebSocket Upgrade | connect, messages, media, reconnect, idle/resume | стабильная session; после reconnect новая session поднимается без ручного вмешательства |
| F2 | `https-lanes` | public HTTP/2; минимум два concurrent logical streams/lane activity | параллельные сообщения + media/download | медленный/нагруженный stream не блокирует другой на WEB application layer |
| F3 | `websocket` | HTTP/1.1 `101 Switching Protocols`; binary WS traffic; Ping/Pong | connect, messages, media, reconnect | один ordered WebSocket переживает normal traffic; reconnect создаёт новый рабочий transport |
| F4 | `websocket-lanes` | несколько lane WebSocket connections при нескольких logical streams | параллельные сообщения + media | минимум две lane sockets при соответствующей нагрузке; отказ/закрытие одной lane не должен валить независимую lane/session целиком |

### Обязательный user-flow для каждого F1..F4

1. Подключить WEB proxy в Telegram Desktop.
2. Отправить несколько текстовых сообщений.
3. Получить входящие сообщения.
4. Открыть/скачать media.
5. Запустить одновременную активность минимум в двух диалогах/потоках.
6. Оставить клиент idle не менее нескольких минут.
7. Вернуть окно клиента и снова отправить сообщение.
8. Кратко разорвать WAN или клиентскую сеть и восстановить.
9. Проверить, что reconnect не требует удаления/повторного добавления proxy.
10. Проверить `logread -e telemt` и frontend errors.

## 5. Frontend matrix

Минимум один полный F1..F4 pass обязателен на frontend, который планируется как default deployment. Остальные frontend paths допускается проверять сокращённо до RC, но carrier-specific prerequisites должны быть подтверждены.

| Frontend | HTTPS | HTTPS lanes | WebSocket | WebSocket lanes | Что фиксировать |
|---|---:|---:|---:|---:|---|
| External | ☐ | ☐ | ☐ | ☐ | TLS config, Host, XFF overwrite, HTTP/2, Upgrade |
| HAProxy | ☐ | ☐ | ☐ | ☐ | ALPN `h2,http/1.1`, `retries 0`, backend HTTP/1.1 |
| NGINX | ☐ | ☐ | ☐ | ☐ | public HTTP/2, `proxy_http_version 1.1`, Upgrade/Connection, `proxy_next_upstream off` |

Frontend не должен маршрутизировать только известные WEB paths: весь public vhost должен доходить до Telemt, иначе decoy behavior становится отличимым.

## 6. Auto-negotiation

UCI baseline:

```uci
option carrier_policy 'auto'
option carrier 'https'
list carrier_candidate 'websocket-lanes'
list carrier_candidate 'websocket'
list carrier_candidate 'https-lanes'
option carrier_learning '1'
option carrier_negotiation_aggressiveness 'conservative'
```

Runtime должен содержать ordered array без reorder со стороны OpenWrt layer:

```toml
[web]
enabled = true
carrier = "https"
carriers = ["websocket-lanes", "websocket", "https-lanes"]
carrier_learning = true
carrier_negotiation_aggressiveness = "conservative"
```

### A1 — negotiation happy path

- Telegram Desktop подключается в Auto;
- наблюдается последовательный выбор только из configured candidates + final fallback;
- response metadata соответствует upstream negotiation contract: `X-Carrier-Mode`, `X-Carrier-Attempt`, `X-Carrier-Candidate-Count`, `X-Carrier-Deadline`, `X-Carrier-State`;
- состояние проходит `provisional -> committed`; при достаточном health evidence — `healthy`;
- уже committed session не мигрирует между carriers динамически.

### A2 — candidate failure / successor

Создать контролируемый отказ первого candidate на frontend/network path, не меняя UCI order.

Pass:

- попытки остаются последовательными;
- после transport failure до commit клиент может перейти к successor;
- committed chain не заменяется новым carrier;
- terminal committed conflict не воспринимается как разрешение на replacement.

### A3 — fallback

Сделать candidates недоступными так, чтобы оставался рабочий final fallback `https`.

Pass: Telegram Desktop подключается через fallback без изменения UCI и без бесконечного negotiation loop.

### A4 — learning

Оставить `carrier_learning=1`, `conservative`.

Pass:

- learning не считается по одному факту выбора carrier;
- evidence появляется только после transport-specific healthy interval;
- раннее закрытие transport не должно давать positive learning result;
- restart Telemt очищает process-local learning state;
- configured fallback остаётся последним.

### A5 — learning off

```sh
uci set telemt.web.carrier_learning='0'
uci commit telemt
/etc/init.d/telemt restart
```

Pass: auto negotiation продолжает работать, но bounded learning не влияет на ordering.

## 7. Negative configuration tests

Эти тесты выполняются сначала при включённом WEB.

### N1 — empty Auto candidate list

Ожидается: generator reject; Telemt не должен стартовать с неполной auto-конфигурацией.

### N2 — duplicate candidate

Ожидается: generator reject.

### N3 — invalid carrier token

Ожидается: candidate reject; invalid fixed/fallback carrier безопасно нормализуется в `https` согласно OpenWrt policy.

### N4 — invalid aggressiveness

Ожидается: OpenWrt layer использует `conservative`.

### N5 — disabled WEB isolation

При `telemt.web.enabled=0` WEB-specific malformed/unfinished settings не должны ломать legacy Classic/DD/FakeTLS startup. Если этот тест падает, это blocking regression safe-upgrade invariant и его надо исправить до RC.

## 8. Legacy regression minimum

После LAB-5 carrier tests выключить WEB и проверить:

- Classic connect;
- DD connect;
- FakeTLS connect, если он используется на стенде;
- existing users/quota/expiration UCI не изменены;
- accumulated stats не обнулены из-за carrier test;
- API/metrics safe bind unchanged;
- firewall не содержит WAN rule для 27453.

## 9. Resource measurements для следующего LAB

Во время carrier matrix собрать измерения, но пока не превращать их в hardcoded presets.

Минимум записывать:

```sh
free -m
cat /proc/$(pidof telemt | awk '{print $1}')/status | grep -E 'VmRSS|VmHWM|Threads'
top -b -n1 | grep telemt
ss -s
```

Снять точки:

- WEB disabled baseline;
- WEB enabled idle;
- one active session;
- media transfer;
- `https-lanes` multi-stream;
- `websocket`;
- `websocket-lanes` multi-lane;
- reconnect/recovery;
- overload test только после отдельного согласованного LAB.

Это станет входными данными для `low / standard / high / custom`; численные limits заранее не придумывать.

## 10. Result sheet

```text
Date:
Router / RAM:
OpenWrt:
Telegram Desktop:
Core head:
LuCI head:
Frontend:

F1 https: PASS / FAIL
F2 https-lanes: PASS / FAIL
F3 websocket: PASS / FAIL
F4 websocket-lanes: PASS / FAIL
A1 auto happy path: PASS / FAIL
A2 successor: PASS / FAIL
A3 fallback: PASS / FAIL
A4 learning: PASS / FAIL
A5 learning off: PASS / FAIL
N1 empty list reject: PASS / FAIL
N2 duplicate reject: PASS / FAIL
N3 invalid enum handling: PASS / FAIL
N4 invalid aggressiveness fallback: PASS / FAIL
N5 disabled WEB isolation: PASS / FAIL
Legacy regression: PASS / FAIL

Idle RSS:
Peak RSS:
Notes:
Blocking bugs:
```

## 11. LAB-5 exit criteria

LAB-5 можно считать закрытым только когда:

- branch CI green в core и LuCI;
- F1..F4 пройдены на реальном Telegram Desktop;
- Auto A1/A3 пройдены; A2/A4 должны быть либо пройдены, либо иметь зафиксированную воспроизводимую причину блокировки;
- backend 27453 не exposed to WAN;
- trusted XFF chain корректен;
- legacy regression minimum green;
- N5 green;
- собраны хотя бы базовые RSS measurements для следующего resource-profile LAB.
