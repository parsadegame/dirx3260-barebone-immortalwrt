# Provenance, credits and references

This repository is a **package selection plus first-boot defaults and build guardrails** on top of
other people's work. Nothing in it modifies the kernel, the device tree, the bootloader, or the
bootloader environment. Everything below is the original work this image exists because of.

## 1. Upstream projects

| project | reference | used here for |
|---|---|---|
| **ImmortalWrt** | <https://github.com/immortalwrt/immortalwrt> · <https://immortalwrt.org> | the entire firmware: `mediatek/mt7622` target, Linux 6.18, apk-tools, LuCI, package build system |
| **OpenWrt** | <https://github.com/openwrt/openwrt> · <https://openwrt.org> | ImmortalWrt's upstream: procd, ubus, netifd, firewall4, the image/squashfs tooling, the `kmod-*` packaging model |
| **luci-theme-argon** | <https://github.com/jerrykuku/luci-theme-argon> | the default LuCI theme in this image |
| **mwan3 / sqm-scripts** | <https://github.com/openwrt/packages> (`net/mwan3`, `net/sqm-scripts`) | dependency information used to decide which modules to bake in |
| **OpenClash** | `immortalwrt/luci` → `applications/luci-app-openclash` | dependency information only — the package is **not** shipped |
| **PassWall / PassWall 2** | `immortalwrt/luci` → `applications/luci-app-passwall`, <https://github.com/Openwrt-Passwall/openwrt-passwall2> | dependency information only — not shipped |

## 2. DIR-X3260 device support (the important one)

The D-Link DIR-X3260 A1 is not a device with mainline OpenWrt support that you can just select;
the port, its device tree, its image recipe and the flash-layout knowledge come from these:

| work | reference | what this build takes from it |
|---|---|---|
| **DIR-X3260 ImmortalWrt tree** | <https://github.com/mimiyang518-alt/DIR-X3260-ImmortalWrt> — commit **`4571a7569d88c7c814df6c0f903fe5bef07c05d9`** | the exact source tree these images are built from: `target/linux/mediatek/dts/mt7622-dlink-dir-x3260-a1.dts`, the `mt7622.mk` device stanza (`KERNEL_SIZE := 8192k`, `append-squashfs4-fakeroot`), MT7622/MT7915 Wi-Fi fixes |
| **DIR-X3260 OpenWrt — v1.0.0 "hardware-validated"** | <https://github.com/mimiyang518-alt/DIR-X3260-OpenWrt> (release `v1.0.0`) | the hardware validation of the device support: 2.4 GHz `OpenWRT`, 5 GHz `OpenWRT-5G`, internet, cold boot, LuCI 5 GHz toggling, OEM-style MT7915 5 GHz LED lifecycle. Their released sysupgrade is 10,752,278 B, sha256 `1598fbe2d5c62516abde2fb520e480a721f261e740e6dbf04de15cb8c4a84a71` |
| **hsj79/openwrt** | <https://github.com/hsj79/openwrt> | earlier DIR-X3260 board/port work that the build kit's invariants were derived from |
| **OpenWrt forum — "Support D-Link DIR X3260"** | <https://forum.openwrt.org/t/support-d-link-dir-x3260/111695> | device support discussion, recovery procedure, the reason the D-Link recovery GUI at `192.168.0.1` is the guaranteed unbrick path |

The **v4 build** referenced throughout these docs is the last image from this tree that is running
on the router: 24,228,120 B,
sha256 `1c2d2c11ed5fc38a500e1289bcb74704d882e05df765100f3a8601964265d2df`.
It is the baseline this image is compared against in [VERIFICATION.md](VERIFICATION.md).

## 3. Predecessor working notes ("BUILD-KIT")

The build guardrails in this repository — the `-no-sparse` patch, the `verify-image.sh` gate, the
fixed stage order, the flash-layout invariants, the overlay arithmetic — come from a local build
kit written while getting the v4 image to boot. It documents, among other things:

- the WSL1 `mksquashfs` sparse-file bug that silently writes 0-byte files and bricks the image
  (hence `patches/0001-buildhost-mksquashfs-no-sparse.patch`, the only source patch here);
- why the stage order must be `tools/install → toolchain/install → target/compile →
  package/compile → package/install → target/install`;
- the flash layout this image must keep: kernel `@0x300000` 8 MiB, `fwconcat0` `@0xB00000` 24 MiB,
  `fwconcat1` `@0x2B00000` 24 MiB;
- the rule that the `Factory` partition (Wi-Fi calibration + MAC addresses) is never written.

`scripts/verify-image.sh` is that kit's gate, published unchanged so anyone can run it.

## 4. What is original in this repository

| file | what it is |
|---|---|
| `config/barebone.config` | the v4 `.config` with **56** user-space package symbols flipped to `is not set`; not a hand-written seed |
| `config/kmods.txt` | the 76 modules that must stay, grouped by why, each traced to a feed dependency |
| `config/dropped-packages.txt` | every package removed, grouped by why |
| `files/etc/uci-defaults/90-barebone-ssh` | guarantees a dropbear listener on a fresh flash |
| `files/etc/uci-defaults/91-barebone-rootpw` | sets a known root password only when it is empty — see the warning in [INSTALL.md](INSTALL.md) |
| `files/etc/uci-defaults/92-barebone-theme` | selects Argon as the LuCI theme |
| `scripts/build-barebone.sh` | build + self-check + gate + packaging driver |
| `docs/` | this documentation |

## 5. What is **not** redistributed here

- D-Link's stock firmware / recovery image (proprietary, and the only guaranteed unbrick path —
  download it from D-Link's support page for the DIR-X3260 and keep it).
- The v4 image and other builds from the upstream forks; get them from their own releases.
- The upstream source tree itself (~2 GB). It is public, at the commit named above.

## 6. Licensing

- Firmware and source in this repository: **GPL-2.0-only**, inherited from OpenWrt/ImmortalWrt
  (see [LICENSE](../LICENSE), and the upstream `COPYING` files).
- The released images are binaries of GPL-2.0 software. The complete corresponding source is the
  upstream tree at commit `4571a7569d88c7c814df6c0f903fe5bef07c05d9` plus the configuration, patch
  and scripts in this repository — everything needed to rebuild the image is published here or at
  the links above.
- `luci-theme-argon` is distributed under its own license (Apache-2.0) by its authors.
- D-Link, DIR-X3260 are trademarks of their owner; this project is not affiliated with D-Link or
  with the ImmortalWrt project.

## 7. If you flash this and it misbehaves

The bug is far more likely to be in the device port than in a package selection that only removed
things. Report it upstream:
[ImmortalWrt issue tracker](https://github.com/immortalwrt/immortalwrt/issues) for base
system issues, the DIR-X3260 fork's issues for device-specific behaviour, and this repository's
issues for anything about the package set, the scripts or the docs.
