#!/usr/bin/env python3
"""Parse actual runtime TOML from an isolated OpenWrt router, without leaking secrets."""
import subprocess
import sys
import tomllib

router, mode = sys.argv[1:3]
proc = subprocess.run(
    ["owlab", "--config", "tools/owlab-upgrade.yaml", "exec", router, "--", "cat", "/tmp/etc/telemt.toml"],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, text=True,
)
if proc.returncode:
    raise SystemExit(f"Unable to fetch generated TOML from {router}; exit={proc.returncode}")
try:
    doc = tomllib.loads(proc.stdout)
except tomllib.TOMLDecodeError as exc:
    raise SystemExit(f"{router}: invalid generated TOML: {exc}") from None
assert doc["server"]["port"] == 18443, "proxy listen port drift"
assert doc["server"]["metrics_port"] == 19092, "metrics port drift"
assert doc["server"]["api"]["listen"] == "127.0.0.1:19091", "API listen address drift"
assert doc["access"]["users"]["ci_runtime"] == "0123456789abcdef0123456789abcdef", "user secret drift"
assert doc["upstreams"][0]["type"] == "direct", "direct upstream fallback drift"
assert doc["general"]["use_middle_proxy"] == (mode == "me"), "ME flag drift"
if mode == "web":
    assert doc["web"]["enabled"] is True, "WEB enabled in UCI but absent in TOML"
    assert doc["web"]["carrier"] == "https", "WEB carrier drift"
    assert doc["web"]["vhosts"][0]["host"] == "proxy.example.org", "vhost host drift"
    assert doc["web"]["vhosts"][0]["profiles"][0]["user"] == "ci_runtime", "WEB binding drift"
    assert any(x.get("transport") == "web" and x.get("port") == 27453
               for x in doc["server"]["listeners"]), "missing WEB listener"
else:
    assert "web" not in doc, "WEB emitted despite disabled UCI"
    assert all(x.get("transport") != "web" for x in doc["server"]["listeners"]), "unexpected WEB listener"
print(f"{router}: runtime TOML parsed and verified in {mode} mode")
