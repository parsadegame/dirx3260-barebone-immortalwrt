# DIR-X3260 A1 — barebone ImmortalWrt (all kmods baked in, apps via `apk`)

A deliberately minimal ImmortalWrt image for the **D-Link DIR-X3260 A1**
(MediaTek MT7622, `mediatek/mt7622`, `aarch64_cortex-a53`) that still carries **every kernel
module** OpenClash, PassWall 1/2, mwan3, SQM/cake and Wake-on-LAN need — and nothing else.
The applications themselves are installed later, on the running router, with `apk`.

**Why that split.** `kmod-*` packages are locked to the exact kernel build
(`vermagic 6.18.44 SMP mod_unload aarch64`). A module offered by the snapshot feed was compiled
against a different kernel and `modprobe` will refuse it. So every module an app might ever need
has to be inside the squashfs at build time. Everything else those apps need is plain
user space, is architecture-independent, and `apk add` handles it on a live router.

---

## Release v1.0.0 (2026-11-04)

| | |
|---|---|
| device | D-Link DIR-X3260 A1 — DTS `mt7622-dlink-dir-x3260-a1` |
| base | ImmortalWrt, target `mediatek/mt7622`, kernel **6.18.44**, apk-tools (`CONFIG_USE_APK=y`) |
| built | 2026-11-04T05:42:15Z on WSL2 Ubuntu 24.04, 6 cores / 7 GB, `JOBS=4` |
| packages | **210** installed, **76** of them `kmod-*`; 1,268 files in the rootfs (29,019,048 B uncompressed) |
| gate | `scripts/verify-image.sh` → **`RESULT: PASS -- safe to flash`** (140 modules, single vermagic, no zero-byte boot files) |

| artefact | size | sha256 |
|---|---|---|
| `immortalwrt-mediatek-mt7622-dlink_dir-x3260-a1-squashfs-sysupgrade.bin` | 14,029,071 B | `62c98acbd4396ab349664f5f64c7c37a610a98d46612e97baa9c29091474feca` |
| `immortalwrt-mediatek-mt7622-dlink_dir-x3260-a1-initramfs-kernel.bin` | 13,392,224 B | `087a7c5daffed922a7b8fb47de472a0531d99c74da84d9673e196f9ef0a0f61f` |
| `immortalwrt-mediatek-mt7622-dlink_dir-x3260-a1.manifest` | 6,636 B | `b895d36e3a2c08d970f01f803e8a491af6eebe62236284e962014e6dc281d98e` |

Download the images from the [v1.0.0 release](https://github.com/parsadegame/dirx3260-barebone-immortalwrt/releases/tag/v1.0.0)
and check them against `SHA256SUMS` before they come near the router.

### ⚠️ Read before flashing

1. **This exact build has not been flashed to hardware by the author of this repo.** It is
   gate-verified *structurally*: the boot chain (busybox, init, procd, ubusd, netifd, uhttpd,
   libc, libubox/ubus/uci/blobmsg) and all 140 kernel modules are byte-identical to the v4 image
   that *is* running on the router, and the image is a strict file-level subset of it. That is
   strong evidence, not a boot test. Keep a recovery path ready — see [docs/INSTALL.md](docs/INSTALL.md).
2. **The first boot sets the root password to `root`.** Log in over SSH, run `passwd`, change it
   immediately. Details: `files/etc/uci-defaults/91-barebone-rootpw`.
3. **`sysupgrade -n` discards the overlay**, and every later sysupgrade does too. Anything
   installed with `apk` is gone after an upgrade — see [docs/WHATS-INSIDE.md](docs/WHATS-INSIDE.md).

---

## Quick start

```sh
# on your computer: verify what you downloaded
sha256sum -c SHA256SUMS

# copy to the router and flash (settings discarded — recommended for a changed package set)
scp immortalwrt-mediatek-mt7622-dlink_dir-x3260-a1-squashfs-sysupgrade.bin root@192.168.1.1:/tmp/
ssh root@192.168.1.1
  sysupgrade -T /tmp/immortalwrt-mediatek-mt7622-dlink_dir-x3260-a1-squashfs-sysupgrade.bin
  sysupgrade -n /tmp/immortalwrt-mediatek-mt7622-dlink_dir-x3260-a1-squashfs-sysupgrade.bin
```

After the reboot: `http://192.168.1.1` (LuCI, Argon theme) / `ssh root@192.168.1.1`
(password `root` → change it). Full procedure, including the D-Link recovery GUI at
`http://192.168.0.1`, in [docs/INSTALL.md](docs/INSTALL.md).

## Install the apps later

```sh
apk update
apk add luci-app-openclash                  # OpenClash
apk add luci-app-passwall xray-core         # PassWall 1 + a core
apk add mwan3 luci-app-mwan3                # multi-WAN
apk add sqm-scripts luci-app-sqm tc         # SQM (cake)
apk add luci-app-wol etherwake              # Wake-on-LAN
```

Every module those packages need is already in the image, so no rebuild is required for them.
Check the cost first: `apk add --simulate <pkgs>` and `df -h /overlay`.

---

## What is in the image, and what is not

```
in   base router system (procd, ubus, netifd, fw4, dnsmasq, dropbear, uhttpd, odhcpd)
     LuCI (light + firewall + package manager) with luci-theme-argon as default
     apk package manager
     76 kmod-* packages — the entire kmod set of the hardware-validated v4 image
     Wi-Fi: mt76 / mt7615e (2.4 GHz) + mt7915e (5 GHz)
not  openclash, passwall 1/2, mwan3, sqm, wol, upnp, rclone, argon-only extras
     and the user-space packages only they need (bash, coreutils, curl, ruby, unzip,
     iptables/ipset userland, tc, miniupnpd-nftables, ...)
```

The full breakdown, per app, with the exact modules each one needs and the size of every
package you would install, is [docs/WHATS-INSIDE.md](docs/WHATS-INSIDE.md).

## Documentation

| file | contents |
|---|---|
| [docs/INSTALL.md](docs/INSTALL.md) | flash, first boot, initial hardening, recovery via the D-Link GUI, troubleshooting |
| [docs/BUILD.md](docs/BUILD.md) | rebuild from source: tree + commit, feeds, patch, stage order, timings, how to bake an app in |
| [docs/WHATS-INSIDE.md](docs/WHATS-INSIDE.md) | package set, the 76 kmods by purpose, what was dropped and why, overlay budget |
| [docs/VERIFICATION.md](docs/VERIFICATION.md) | gate output, hashes, cross-checks against the v4 image, what was and was not verified |
| [docs/PROVENANCE.md](docs/PROVENANCE.md) | **credits and references to the original work** this builds on |
| [docs/CHANGELOG.md](docs/CHANGELOG.md) | release notes |

## Repository layout

```
config/barebone.config              the .config this image was built from (v4 minus 56 feature packages)
config/barebone.resolved.config     what `make defconfig` produced from it
config/kmods.txt                    the 76 kernel modules, grouped by reason
config/dropped-packages.txt         every package turned off, grouped by why
files/etc/uci-defaults/90-92        first-boot: SSH listener, root password, Argon theme
patches/0001-...-no-sparse.patch    the one source patch (WSL1/mksquashfs zero-byte bug)
scripts/build-barebone.sh           build + self-check + gate + package
scripts/verify-image.sh             standalone pre-flash gate (works on any image)
release/v1.0.0/                     manifest, config, kmod list, gate logs, checksums
```

## Provenance in one paragraph

This is not a fork of ImmortalWrt and it patches nothing in the kernel, DTS or bootloader.
It is a **package selection** — `config/barebone.config` is the hardware-validated v4
configuration with 56 user-space packages flipped to `is not set` — plus three first-boot
`uci-defaults` scripts and a build script that refuses to produce an image when the kmods,
the device recipe or the flash layout drift. The device port itself comes from the
`mimiyang518-alt/DIR-X3260-ImmortalWrt` tree at commit `4571a75`, on top of
[ImmortalWrt](https://github.com/immortalwrt/immortalwrt) and
[OpenWrt](https://github.com/openwrt/openwrt). Full attribution, including what is *not*
redistributed here, in [docs/PROVENANCE.md](docs/PROVENANCE.md).

## License

GPL-2.0-only, as inherited from OpenWrt/ImmortalWrt — see [LICENSE](LICENSE). Firmware binaries
in the release are distributed under the same terms; the complete corresponding source is the
upstream tree at commit `4571a7569d88c7c814df6c0f903fe5bef07c05d9` plus the config, patch and
scripts in this repository.
