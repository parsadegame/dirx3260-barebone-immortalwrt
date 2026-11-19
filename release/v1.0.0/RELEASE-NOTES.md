# v1.0.0 — barebone ImmortalWrt for the D-Link DIR-X3260 A1

The smallest ImmortalWrt image that still gives you everything OpenClash, PassWall 1/2, mwan3,
SQM/cake and Wake-on-LAN need: the base system, LuCI, `apk`, and **all 76 kernel modules** those
apps require baked into the squashfs. The apps themselves install later with `apk` — no rebuild.

| | |
|---|---|
| device | D-Link DIR-X3260 **A1** (`mt7622-dlink-dir-x3260-a1`, MediaTek MT7622, aarch64) |
| base | ImmortalWrt `mediatek/mt7622`, kernel 6.18.44, apk-tools |
| packages | 210 (76 × `kmod-*`), 1,268 files, 29,019,048 B uncompressed |
| gate | `RESULT: PASS -- safe to flash` — 140 modules, one vermagic, no zero-byte boot files |

## Downloads

| file | size | sha256 |
|---|---|---|
| `immortalwrt-mediatek-mt7622-dlink_dir-x3260-a1-squashfs-sysupgrade.bin` | 14,029,071 B | `62c98acbd4396ab349664f5f64c7c37a610a98d46612e97baa9c29091474feca` |
| `immortalwrt-mediatek-mt7622-dlink_dir-x3260-a1-initramfs-kernel.bin` | 13,392,224 B | `087a7c5daffed922a7b8fb47de472a0531d99c74da84d9673e196f9ef0a0f61f` |
| `SHA256SUMS` | — | checksums for the two images above |
| `immortalwrt-mediatek-mt7622-dlink_dir-x3260-a1.manifest` | 6,636 B | the exact package list of the image |
| `config.txt` | 297,811 B | the resolved `.config` it was built from |
| `kmods.txt` | 2,477 B | the 76 modules, grouped by reason |
| `gate.log` | 830 B | the pre-flash gate transcript |

```sh
sha256sum -c SHA256SUMS
sysupgrade -T immortalwrt-...-squashfs-sysupgrade.bin   # accepted for this device?
sysupgrade -n  immortalwrt-...-squashfs-sysupgrade.bin   # flash, settings discarded
```

## Read this before flashing

- **Not boot-tested on hardware for this exact build.** It is verified structurally: boot chain
  and all 140 kernel modules are byte-identical to the hardware-validated v4 image, and the file
  list is a strict subset of it. Keep the D-Link recovery GUI path (`http://192.168.0.1` with a
  stock D-Link image) ready — see `docs/INSTALL.md`.
- **The first boot sets the root password to `root`.** Run `passwd` immediately.
- **`sysupgrade -n` discards the overlay**, and so does every later sysupgrade. `apk` installs do
  not survive an upgrade; bake anything permanent into the image.

## Installing your apps

```sh
apk update
apk add luci-app-openclash
apk add luci-app-passwall xray-core
apk add mwan3 luci-app-mwan3
apk add sqm-scripts luci-app-sqm tc
apk add luci-app-wol etherwake
```

~30 MB of overlay is free; OpenClash, mwan3, SQM and WOL fit, PassWall + `xray-core` is tight,
`passwall2` + `sing-box` needs a rebuild. Details: `docs/WHATS-INSIDE.md`.

## Credits

Device support, DTS and the Dire-X3260 image recipe come from
[mimiyang518-alt/DIR-X3260-ImmortalWrt](https://github.com/mimiyang518-alt/DIR-X3260-ImmortalWrt)
(commit `4571a75`) on top of [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) and
[OpenWrt](https://github.com/openwrt/openwrt). Full attribution, including what is deliberately
not redistributed here, is in `docs/PROVENANCE.md`.

GPL-2.0-only. Full documentation: `README.md`, `docs/INSTALL.md`, `docs/BUILD.md`,
`docs/VERIFICATION.md`.
