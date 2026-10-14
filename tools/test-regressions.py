#!/usr/bin/env python3
"""Regression checks for core UCI and WEB safety contracts."""
from pathlib import Path
import re

post = Path("scripts/postinst").read_text()
init = Path("files/telemt.init").read_text()
defaults = Path("files/telemt.config").read_text()
start = post.index("# BEGIN_TESTABLE_GENERAL_MIGRATION")
end = post.index("# END_TESTABLE_GENERAL_MIGRATION")
migration = post[start:end]
assert "if ! has_section general; then" in migration
assert "ensure_section general telemt" in migration
assert "ensure_option general enabled 0" in migration
assert "unexpected UCI type" in migration
assert "ensure_section web web" in post[end:]
assert "ensure_option web enabled 0" in post
assert "ensure_option web_listener ip 127.0.0.1" in post
assert 'config_get_bool enabled general enabled 0' in init
assert 'config_get api_listen_addr     general api_listen_addr     "127.0.0.1"' in init
assert 'config_get metrics_listen_addr general metrics_listen_addr "127.0.0.1"' in init
assert "option enabled '0'" in defaults
assert re.fullmatch(r"\d+\.\d+\.\d+\s*", Path("version.txt").read_text())
print("core regression contracts: OK")
