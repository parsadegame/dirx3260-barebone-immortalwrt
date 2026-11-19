# Verification

Two different things are called "verified" in firmware projects. This page keeps them apart.

## 1. Gate result for v1.0.0

`scripts/verify-image.sh` (same script you can run yourself) on the released sysupgrade image:

```
== image ==
  file   immortalwrt-mediatek-mt7622-dlink_dir-x3260-a1-squashfs-sysupgrade.bin
  size   14029071 bytes
  sha256 62c98acbd4396ab349664f5f64c7c37a610a98d46612e97baa9c29091474feca
  ..   sysupgrade tar, member: sysupgrade-dlink_dir-x3260-a1/root
== contents ==
  files  1268
  bytes  29019048 (uncompressed)
== boot gate ==
  ok   /etc/inittab present, 106 bytes
  ok   18 preinit scripts, all non-empty
  ok   sbin/init 16649 bytes
  ok   sbin/procd 97697 bytes
  ok   sbin/ubusd 32962 bytes
  ok   sbin/netifd 241075 bytes
  ok   bin/busybox 425997 bytes
  ok   /lib/ld-musl-aarch64.so.1 -> libc.so, 590852 bytes
  ok   no unexpected zero-byte files (12 expected empties)
== modules ==
  ok   140 modules, single vermagic: 6.18.44 SMP mod_unload aarch64
== RESULT: PASS -- safe to flash ==
```

The same script returns PASS on the hardware-proven v4 image, so the checker itself is not
lying. Raw logs are in [`release/v1.0.0/gate.log`](../release/v1.0.0/gate.log) and
[`kit-gate.log`](../release/v1.0.0/kit-gate.log).

## 2. Hashes of the released artefacts

| file | size | sha256 |
|---|---|---|
| `...-squashfs-sysupgrade.bin` | 14,029,071 B | `62c98acbd4396ab349664f5f64c7c37a610a98d46612e97baa9c29091474feca` |
| `...-initramfs-kernel.bin` | 13,392,224 B | `087a7c5daffed922a7b8fb47de472a0531d99c74da84d9673e196f9ef0a0f61f` |
| `....manifest` | 6,636 B | `b895d36e3a2c08d970f01f803e8a491af6eebe62236284e962014e6dc281d98e` |
| `config.txt` (resolved `.config`) | 297,811 B | `371fec29b3a9bb1863d3545b7a38f79853912e7bcef57c783dd128f14aa8d2b1` |
| `gate.log` | 830 B | `e8c3988a2db2d1b0dd52b4821084572dd56cc681cd6a6bd21e569896c397a931` |
| `kmods.txt` | 2,477 B | `53a65957998171e543f5bbca3d721d5851622e370782b51bbd3edaa70ce9a3e4` |
| `dropped-packages.txt` | 1,214 B | `b9e2f130fe47ceeb6d59d609eb4c50fd99956ed5171b3f25cfc0ad66328daab8` |

(`release/v1.0.0/SHA256SUMS` lists the evidence files committed in this repository;
`SHA256SUMS.firmware` lists the two images, which are published as release assets.)

## 3. Cross-checks against the hardware-validated v4 image

v4 is the build that is running on the router: 24,228,120 B,
sha256 `1c2d2c11ed5fc38a500e1289bcb74704d882e05df765100f3a8601964265d2df`. This image was
compared to it file by file:

| check | result |
|---|---|
| root file list | strict subset: **0 extra files**, 612 v4-only files (the dropped app payloads) |
| boot chain: busybox, init, procd, ubusd, netifd, uhttpd, inittab, rc.local, libc, libubox/ubus/uci/blobmsg | **md5-identical** to v4 |
| kernel modules | **140/140 byte-identical** |
| FIT `fdt-1` | identical, `79ddb02416709dc3…` — the hash the gate expects |
| decompressed kernel | 14,841,864 B in both; 570 differing bytes, all embedded `root@…` / GCC-tag strings |
| sizes vs flash layout | kernel 4.67 MB ≤ 8 MiB partition; squashfs ≤ 24 MiB fwconcat; `hsqs` at offset 0, 2048-aligned |
| image root vs staged `root-mediatek` | byte-identical, all md5s — no sparse-file corruption |
| DTS, `mt7622.mk` stanza, `-no-sparse` patch | unchanged (DTS md5 `82339214…`) |
| packaged set | apk db 210 packages, `base-files 260907.74499~20261104`; none of openclash, passwall, mwan3, sqm, wol, argon-missing, upnpd, microsocks, etherwake |
| `/etc/config` | `bridger dhcp dropbear firewall luci luci_plugins rpcd uhttpd` only |

Known benign differences: the kernel banner reads `root@<buildhost>` and
`OpenWrt GCC 14.4.0` instead of v4's `root@Parsa` / `r41058-4571a7569d`, because the build tree
had no `.git` (see [BUILD.md](BUILD.md) §3). Nothing else in the kernel image differs.

## 4. What was **not** verified

Be explicit about this before you flash:

- **No boot test of this exact build on hardware.** The evidence is structural: identical boot
  chain, identical modules, strict-subset file list, passing gate. The v4 image that shares all of
  that *was* validated on the router; this one was not flashed by the author of this repository.
- **No Wi-Fi, WAN, PPPoE, throughput or long-running stability testing** of this build.
- **No test of the apps** (OpenClash, PassWall, mwan3, SQM, WOL). The claim made here is narrower:
  the module set they require is present in the image, so `apk` installation cannot fail on a
  missing kernel module.
- **No test of the first-boot `uci-defaults` scripts on a virgin flash of this exact image.** They
  are the same scripts the v4 rebuild used, and they are written to be no-ops when the target
  configuration is not in the state they expect.

If you flash this, you are the boot test. Report results as an issue with `dmesg`, `logread` and
`sha256sum` of the image you used.

## 5. Verify it yourself

```sh
# the image you downloaded
sha256sum -c SHA256SUMS.firmware

# the full gate (needs bash, tar, unsquashfs)
bash scripts/verify-image.sh immortalwrt-...-squashfs-sysupgrade.bin

# what is actually inside, per package
grep -E '^kmod-' immortalwrt-...-dlink_dir-x3260-a1.manifest | wc -l     # -> 76
grep -E '^(luci-app-openclash|luci-app-passwall|mwan3|sqm-scripts|luci-app-wol) - ' *.manifest
```

On the router after flashing:

```sh
ubus call system board
opkg --version 2>/dev/null || apk --version
uname -r                                   # 6.18.44
for m in nft_tproxy tun sched_cake ifb ipt_ipset; do lsmod | grep -q "$m" && echo "ok $m"; done
```
