# Installing on the DIR-X3260 A1

## 0. What you need

- D-Link DIR-X3260 **A1** (this image is built for `mt7622-dlink-dir-x3260-a1` only).
- A computer with Ethernet (Wi-Fi configuration of the router is not carried over).
- The sysupgrade image and its checksum from the
  [v1.0.0 release](https://github.com/parsadegame/dirx3260-barebone-immortalwrt/releases/tag/v1.0.0).
- **A recovery path.** For the D-Link bootloader GUI you need a stock D-Link firmware image for
  this model (download it from D-Link's support page for the DIR-X3260 before you start;
  it is not redistributed in this repository). Recovery requires no working firmware, only the
  bootloader, so a bad flash is recoverable as long as you have that file.

## 1. Verify the download

```sh
sha256sum -c SHA256SUMS
# immortalwrt-...-squashfs-sysupgrade.bin: OK
# immortalwrt-...-initramfs-kernel.bin: OK
```

Expected values are also in the top-level README:

```
62c98acbd4396ab349664f5f64c7c37a610a98d46612e97baa9c29091474feca  squashfs-sysupgrade.bin
087a7c5daffed922a7b8fb47de472a0531d99c74da84d9673e196f9ef0a0f61f  initramfs-kernel.bin
```

Do not flash anything whose hash you have not checked.

## 2. Optional but recommended: run the gate yourself

`scripts/verify-image.sh` is standalone — it needs `bash`, `tar` and `unsquashfs`, nothing else:

```sh
bash scripts/verify-image.sh /path/to/immortalwrt-...-squashfs-sysupgrade.bin
```

It must end with:

```
== RESULT: PASS -- safe to flash ==
```

Anything else means do not flash.

## 3. Flash

### From an existing OpenWrt / ImmortalWrt on the router (recommended)

```sh
scp immortalwrt-mediatek-mt7622-dlink_dir-x3260-a1-squashfs-sysupgrade.bin root@192.168.1.1:/tmp/
ssh root@192.168.1.1

# test first: checks the image is accepted for this device, changes nothing
sysupgrade -T /tmp/immortalwrt-mediatek-mt7622-dlink_dir-x3260-a1-squashfs-sysupgrade.bin

# flash, discarding settings
sysupgrade -n /tmp/immortalwrt-mediatek-mt7622-dlink_dir-x3260-a1-squashfs-sysupgrade.bin
```

`-n` (discard settings) is the right choice here: the package set deliberately differs from
the stock and v4 builds, and half-restored configuration is harder to debug than a clean box.
The flash partition layout is unchanged, so nothing is reformatted that should not be.

### From LuCI

*System → Backup / Flash Firmware → Flash new firmware image*, uncheck **Keep settings**,
upload the `squashfs-sysupgrade.bin`.

### From the D-Link stock firmware

The stock firmware does not accept a sysupgrade image. Two ways in:

1. Flash a known-good OpenWrt/ImmortalWrt build for this model first (see
   [docs/PROVENANCE.md](PROVENANCE.md) for the hardware-validated upstream release), then
   `sysupgrade -n` this image.
2. Use the recovery GUI described in step 5 with an image the bootloader accepts.

The image is **not** a factory/recovery image; do not try to feed it to the bootloader.

## 4. First boot

- Router address: `http://192.168.1.1` (LuCI, Argon theme) and `ssh root@192.168.1.1`.
- The LAN ports and both radios come up with the wired defaults of the target; configure WAN
  (DHCP/PPPoE/static) under *Network → Interfaces*.

Three `uci-defaults` scripts run exactly once, on a **fresh** flash:

| script | what it does |
|---|---|
| `90-barebone-ssh` | replaces a dropbear config that is pinned to `_direct / DirectInterface 'lan'` (which leaves no listener at all on boot) with a stock `port 22`, password-auth-enabled config. Any other dropbear config is left untouched. |
| `91-barebone-rootpw` | if the root password is **empty**, sets it to `root`; an existing password is never overwritten. |
| `92-barebone-theme` | sets `luci.main.mediaurlbase=/luci-static/argon` so Argon is the default theme (the bootstrap theme renders first until this fires). |

**Change the password immediately:**

```sh
passwd
```

Nothing in this image opens WAN-side access (no `uhttpd` on WAN, no `dropbear` on WAN by
default), but a router whose root password is `root` is one misconfiguration away from being
someone else's. Also consider disabling password authentication for SSH in favour of a key.

## 5. Recovery (the guaranteed way back)

Every attempt should start with this path known and the stock D-Link image already downloaded.

1. Power the router off.
2. Configure the computer with a static address in `192.168.0.0/24`, e.g. `192.168.0.10/24`.
3. Hold the **reset** button and power the router on; keep holding until the LED starts to
   blink (the bootloader's recovery mode).
4. Open `http://192.168.0.1` and upload the stock D-Link DIR-X3260 firmware image.
5. Wait for the flash and the reboot, then set the computer back to DHCP.

The `initramfs-kernel.bin` is a RAM-only image useful for inspection (`sysupgrade` from it also
works); it does not persist anything and is not a recovery image in the D-Link sense.

## 6. Troubleshooting

| symptom | cause / fix |
|---|---|
| LEDs orange, no network | a bricked squashfs (zero-byte files) — recover via step 5. This image passed the gate that catches exactly that failure. |
| SSH answers but login is refused | root password is empty or was not set — use LuCI at `192.168.1.1` if the web UI is reachable, otherwise reflash with `sysupgrade -n`. |
| `apk add` says a kmod is unavailable | you are installing a package that needs a module outside the 76 baked ones — see [WHATS-INSIDE.md](WHATS-INSIDE.md); that one needs a rebuild. |
| `apk add` fails, `df -h /overlay` is ~100 % | expected on tight overlays with big proxy cores — bake the package into the image instead ([BUILD.md](BUILD.md)). |
| Wi-Fi missing | check `logread | grep mt76`; the driver modules are in the image, so a missing radio is a calibration/Factory-partition issue, not a package issue. Never write to the Factory partition. |
