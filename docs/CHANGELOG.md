# Changelog

## v1.0.0 — 2026-11-04

First public release: the barebone DIR-X3260 A1 ImmortalWrt image.

**Image**

- Built from ImmortalWrt `mediatek/mt7622` at `4571a7569d88c7c814df6c0f903fe5bef07c05d9`
  (Dir-X3260 port tree), kernel **6.18.44**, apk-tools.
- **210** packages, **76** `kmod-*`, 1,268 files, 29,019,048 B uncompressed.
- sysupgrade image 14,029,071 B, sha256
  `62c98acbd4396ab349664f5f64c7c37a610a98d46612e97baa9c29091474feca`.
- initramfs image 13,392,224 B, sha256
  `087a7c5daffed922a7b8fb47de472a0531d99c74da84d9673e196f9ef0a0f61f`.
- Gate: `RESULT: PASS -- safe to flash` — 140 modules, single vermagic
  `6.18.44 SMP mod_unload aarch64`, no zero-byte files, boot chain intact.

**Profile**

- Base system + LuCI (light, firewall, package manager) + `apk`, Argon default theme.
- Whole kmod set of the hardware-validated v4 build baked in, so OpenClash, PassWall 1/2, mwan3,
  SQM/cake and Wake-on-LAN can be installed later with `apk` without a rebuild.
- No applications shipped: openclash, passwall, mwan3, sqm, wol, upnp, rclone and the 56
  user-space packages only they need are `is not set` (list: `config/dropped-packages.txt`).

**First boot**

- `90-barebone-ssh` guarantees a dropbear listener on port 22 on a fresh flash.
- `91-barebone-rootpw` sets root's password to `root` when it is empty — change it with `passwd`.
- `92-barebone-theme` selects `luci-theme-argon` as the LuCI theme.

**Build**

- `scripts/build-barebone.sh` refuses to build when the `-no-sparse` patch, the device recipe, the
  DTS flash layout, the 76 kmods or the "no apps" rule are violated, and gates the result with
  `scripts/verify-image.sh`.
- Fixed stage order (`tools → toolchain → target/compile → package/compile → package/install →
  target/install`) and a pinned hex `REVISION`, both required for a working build on this tree.

**Known limitations**

- Not boot-tested on hardware for this exact build; verification is structural against the
  hardware-proven v4 image. See `docs/VERIFICATION.md` §4.
- `apk` installs live in the overlay, which every sysupgrade recreates (~30 MB free).
  `passwall2` + `sing-box` does not fit; bake it into the image instead.
