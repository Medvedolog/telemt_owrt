---
name: Test report
about: Report the result of testing this release on a real router
title: "[test] <router model> / OpenWrt <version> / <package version>"
labels: testing
---

**Router**
- Model:
- Architecture (`apk --print-arch` or `opkg print-architecture`):
- OpenWrt version and package manager (apk / opkg):

**Packages**
- telemt version (`cat /tmp/etc/telemt.version`):
- luci-app-telemt version:
- Installed how (file / feed) and over which previous version (none / 3.4.x / other):

**What was tested**
- [ ] Fresh install starts, service is running (`/etc/init.d/telemt status`)
- [ ] Upgrade over an older version kept `/etc/config/telemt`
- [ ] Classic / DD / FakeTLS clients connect (WEB off)
- [ ] LuCI page opens and saves settings
- [ ] WEB Proxy enabled (which frontend: external / HAProxy / NGINX, which carrier)

**Result**
What worked, what did not, and how to reproduce.

**Logs**
```
logread | grep telemt
```
