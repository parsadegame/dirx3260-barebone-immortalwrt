# Rebuilding this image from source

## 1. Host

- Linux. The 2026-11-04 build ran in **WSL2 Ubuntu 24.04** (6 cores / 7 GB, `JOBS=4`);
  any x86_64 Linux with ≥ 4 GB RAM and ~40 GB free disk works.
- Budget **8 GB RAM** if you have it: this tree also builds a host LLVM/BPF toolchain for
  `bridger` (an `mt7622` subtarget default package) — roughly 4300 C++ objects, and its link step
  will thrash a 10 GB VM into swap.
- Debian/Ubuntu prerequisites:

```sh
sudo apt-get install -y build-essential gawk git gettext libncurses5-dev libssl-dev \
     python3 python3-distutils rsync unzip wget file zlib1g-dev time xxd
```

## 2. Source tree

The device support lives in a fork; the base is ImmortalWrt. Use the tree the images were built
from — a fresh clone of a moving branch gives you today's feed heads, which is exactly the drift
that breaks binary compatibility of `kmod-*` and `base-files`.

```bash
git clone https://github.com/mimiyang518-alt/DIR-X3260-ImmortalWrt.git
cd DIR-X3260-ImmortalWrt
git checkout 4571a7569d88c7c814df6c0f903fe5bef07c05d9   # the commit recorded for this build
./scripts/feeds update -a
./scripts/feeds install -a
```

A build from a different commit is a different firmware: `vermagic` and the feed ABI must match
the modules you already have, and `docs/VERIFICATION.md` no longer applies to it.

## 3. Build

From this repository:

```bash
# 1) resolve and validate the config only — about a minute, no compilation
TREE=/path/to/DIR-X3260-ImmortalWrt bash scripts/build-barebone.sh --check

# 2) full build: patch check → defconfig → tools → toolchain → kernel → packages → target
TREE=/path/to/DIR-X3260-ImmortalWrt JOBS=4 bash scripts/build-barebone.sh
```

| variable | meaning |
|---|---|
| `TREE` | path to the ImmortalWrt source tree |
| `JOBS` | `make -j` value (defaults to `nproc`) |
| `VREV` | the `REVISION` string, must be hex (default `20261104`) |
| `OUT` | output directory (default `release/`) |
| `DIST_SUFFIX` | appended to the output folder name |

The script is not a wrapper around `make`; it is a guardrail. Before it compiles anything it
asserts that the `-no-sparse` patch is present, that the device recipe (`DEVICE_DTS`,
`KERNEL_SIZE := 8192k`, `append-squashfs4-fakeroot`) and the DTS partitions
(`0x300000/8 MiB`, `0xB00000/24 MiB`, `0x2B00000/24 MiB`) are unchanged, and after `defconfig`
it asserts that all 76 kmods resolved to `=y` and no feature app came back. After the build it
runs `scripts/verify-image.sh` and checks the image manifest for 76/76 kmods and zero app
packages. Any failure stops before an image is packaged.

### Three stage-order details that cost a failed run each

1. **The stage order is fixed:** `tools/install`, `toolchain/install`, `target/compile`,
   `package/compile`, `package/install`, `target/install`. `target/install` alone does not build
   the toolchain (the kernel then dies in kconfig with misleading bison/lexer errors), and without
   `package/install` mksquashfs4 fails with `Cannot stat source directory ... root-mediatek`.
2. **Kernel modules must be built after the kernel.** `target/compile` has to run before the kmod
   packages, otherwise modpost reports every kernel symbol as undefined because `Module.symvers`
   does not exist yet.
3. **`REVISION` must be pinned to a hex value.** A tree without `.git` makes `scripts/getver.sh`
   return `unknown`, so `base-files` becomes `<release>~unknown`, which apk-tools rejects
   (`the part after ~ must be numeric/hex`).

Timing: 60–120 min from scratch on 12 cores, a few minutes for an incremental rebuild after only
a config change, 6–10 min on 4 cores of a 7 GB WSL2 VM for a package-only change.

## 4. The one patch

`patches/0001-buildhost-mksquashfs-no-sparse.patch` appends `SQUASHFSOPT += -no-sparse` to
`include/image.mk`. On a build host that reports `st_blocks = 0` for small files (WSL1 does),
mksquashfs treats them as sparse, its `SEEK_DATA` probe fails, and it **silently writes them as
0-byte files** — which includes `/etc/inittab`, and the router then shows an orange LED forever.
The image gate catches this after the fact; the patch prevents it. Keep it.

## 5. Output

```
release/barebone-<stamp>/
  immortalwrt-mediatek-mt7622-dlink_dir-x3260-a1-squashfs-sysupgrade.bin
  immortalwrt-mediatek-mt7622-dlink_dir-x3260-a1-initramfs-kernel.bin
  immortalwrt-mediatek-mt7622-dlink_dir-x3260-a1.manifest
  config.txt  kmods.txt  dropped-packages.txt  gate.log  SHA256SUMS
  BUILD-INFO.txt
```

`*.bin` is git-ignored: images belong in a release, not in the repository.

## 6. Baking an application into the image

Installing at runtime is limited by the ~30 MB overlay (see
[WHATS-INSIDE.md](WHATS-INSIDE.md)), and a sysupgrade discards the overlay anyway. For anything
you want permanently, add it to the config:

```bash
# edit config/barebone.config, add for example:
#   CONFIG_PACKAGE_luci-app-passwall=y
#   CONFIG_PACKAGE_xray-core=y
TREE=/path/to/DIR-X3260-ImmortalWrt JOBS=4 bash scripts/build-barebone.sh
```

The script will **not** stop you — it only refuses to let the five tracked apps
(`luci-app-openclash`, `luci-app-passwall`, `luci-app-mwan3`, `luci-app-sqm`, `luci-app-wol`,
plus `mwan3`, `sqm-scripts`, `miniupnpd-nftables`) be selected by accident when you asked for a
barebone image. If you are intentionally changing the profile, remove the check or pass your own
list; the gate (`verify-image.sh`) and the manifest check still run and still have to pass.

## 7. Reproducibility caveat

Same tree + same config + same host does not guarantee the same bytes: the build embeds a
timestamp and the build user into the kernel banner (`root@<host>`, `OpenWrt GCC 14.4.0`) and
packages carry their own build stamps. What *is* reproducible is the part that decides whether it
boots: the packaged set, the kmod set, `vermagic`, the DTS/image recipe and the gate result.
Compare manifest and module hashes, not whole-image hashes, when comparing two builds.
