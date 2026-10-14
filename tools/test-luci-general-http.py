#!/usr/bin/env python3
"""Authenticated LuCI CBI render checks on a deliberately broken UCI config.

Avoid printing HTML, credentials or secret UCI values to GitHub Actions logs.
"""
import http.cookiejar
import sys
import urllib.error
import urllib.parse
import urllib.request

scenario = sys.argv[1]
if scenario not in ("missing", "wrong"):
    raise SystemExit("Expected missing or wrong")
expected_reason = "missing" if scenario == "missing" else "wrong UCI type"
for release, port in (("24.10.8", 18480), ("25.12.5", 18481)):
    base = f"http://127.0.0.1:{port}"
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(jar),
        # Intentionally keep redirects and cookies as the real web browser does.
    )
    form = urllib.parse.urlencode(
        {"luci_username": "root", "luci_password": ""}
    ).encode("utf-8")
    req = urllib.request.Request(
        base + "/cgi-bin/luci/", data=form,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    with opener.open(req, timeout=30) as response:
        response.read(1 << 20)
    if not any(c.name.startswith("sysauth") and c.value for c in jar):
        raise SystemExit(f"{release}: LuCI authentication failed")
    with opener.open(base + "/cgi-bin/luci/admin/services/telemt", timeout=30) as response:
        body = response.read(4 << 20).decode("utf-8", errors="replace")
        status = response.status
    if status != 200:
        raise SystemExit(f"{release}: LuCI page returned HTTP {status}")
    for marker in ("A runtime exception was caught", "stack traceback:",
                   "Uncaught exception", "/usr/lib/lua/luci/dispatcher.lua"):
        if marker in body:
            raise SystemExit(f"{release}: LuCI dispatcher error ({marker})")
    if "Telemt configuration error:" not in body or expected_reason not in body:
        raise SystemExit(f"{release}: missing visible UCI diagnostic ({scenario})")
    print(f"{release}: authenticated LuCI renders {scenario} general warning (HTTP 200)")
