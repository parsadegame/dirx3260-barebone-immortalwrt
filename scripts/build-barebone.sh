#!/usr/bin/env bash
#
# build-barebone.sh -- build the barebone DIR-X3260 A1 ImmortalWrt image.
#
#   ./build-barebone.sh              full build + gate + package into dist/
#   ./build-barebone.sh --check      only resolve the config and check it
#
# Run it inside WSL/Linux, from anywhere:
#     bash barebone/scripts/build-barebone.sh
#
# Environment (all optional):
#     TREE=/root/build/dirx3260   the ImmortalWrt source tree
#     JOBS=4                      make -j
#     UNSQUASHFS=...              for the post-build gate
#
# What it guarantees, in order:
#   1. the -no-sparse patch is in include/image.mk  (the brick bug, CONTEXT.md 6)
#   2. the device image recipe and DTS layout are untouched
#   3. the resolved .config really contains every required kmod and no app
#   4. the build log has no "Failed to read file" lines
#   5. scripts/verify-image.sh prints RESULT: PASS
#   6. the image manifest carries all 76 kmods and none of the 5 apps
#   7. dist/<stamp>/ holds image + manifest + config + checksums
#
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # this repository
WS="$(cd "$KIT/.." && pwd)"                              # workspace root
TREE="${TREE:-/root/build/dirx3260}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
CHECK_ONLY=false
[ "${1:-}" = "--check" ] && CHECK_ONLY=true

# BUILD.md 1: this environment for every build command
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export FORCE_UNSAFE_CONFIGURE=1 LC_ALL=C TZ=UTC

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok()   { printf '  ok   %s\n' "$*"; }
info() { printf '  ..   %s\n' "$*"; }
fail() { printf '\nFAIL: %s\n' "$*" >&2; exit 1; }

KMODS="$(awk '/^[a-z]/ && !/^#/ {print $1}' "$KIT/config/kmods.txt" | grep '^kmod-' || true)"
[ "$(printf '%s\n' "$KMODS" | wc -l)" -eq 76 ] || fail "kmods.txt should list 76 modules"
KMODS_CSV="$(printf '%s' "$KMODS" | tr '\n' ' ')"
APPS="luci-app-openclash luci-app-passwall luci-app-mwan3 luci-app-sqm luci-app-wol mwan3 sqm-scripts miniupnpd-nftables"

# ---------------------------------------------------------------------------
say "1/6 preflight: source tree"
[ -d "$TREE/include" ] || fail "no ImmortalWrt tree at $TREE (set TREE=/path/to/tree)"
cd "$TREE"
if [ -d .git ]; then
	info "HEAD $(git log -1 --format='%h %s' 2>/dev/null | cut -c1-70)"
	dirty="$(git status --porcelain | awk '{print $2}' | grep -v '^include/image.mk$' | head -5)"
	[ -z "$dirty" ] || fail "unexpected working-tree changes:"$'\n'"$dirty"
fi
info "kernel $(grep -E '^KERNEL_PATCHVER' target/linux/mediatek/Makefile | head -1)"

if ! grep -q 'SQUASHFSOPT += -no-sparse' include/image.mk; then
	info "applying -no-sparse patch"
	patch -p1 --forward < "$KIT/patches/0001-buildhost-mksquashfs-no-sparse.patch" \
		|| fail "could not apply the -no-sparse patch (re-apply by hand, see BUILD-KIT/CONTEXT.md 6)"
fi
grep -q 'SQUASHFSOPT += -no-sparse' include/image.mk || fail "-no-sparse missing from include/image.mk"
ok "-no-sparse present (the WSL1/mksquashfs brick fix)"

MSQ="$TREE/staging_dir/host/bin/mksquashfs4"
[ -x "$MSQ" ] && info "mksquashfs $("$MSQ" -version 2>&1 | head -1)"

# device invariants (CONTEXT.md 7) -- abort if the recipe or DTS moved
MK=target/linux/mediatek/image/mt7622.mk
grep -q 'DEVICE_DTS := mt7622-dlink-dir-x3260-a1' "$MK"      || fail "device stanza changed: DEVICE_DTS"
grep -q 'KERNEL_SIZE := 8192k' "$MK"                          || fail "device stanza changed: KERNEL_SIZE"
grep -q 'append-squashfs4-fakeroot' "$MK"                     || fail "device stanza changed: fakeroot trailer gone"
DTS=target/linux/mediatek/dts/mt7622-dlink-dir-x3260-a1.dts
grep -qi 'reg = <0x300000 0x800000>' "$DTS"      || fail "DTS: kernel partition is not 0x300000/8 MiB"
grep -qi 'reg = <0xb00000 0x1800000>' "$DTS"     || fail "DTS: fwconcat0 is not 0xB00000/24 MiB"
grep -qi 'reg = <0x2b00000 0x1800000>' "$DTS"    || fail "DTS: fwconcat1 is not 0x2B00000/24 MiB"
ok "device recipe + DTS flash layout unchanged"

# ---------------------------------------------------------------------------
say "2/6 config: barebone seed -> .config"
cp "$KIT/config/barebone.config" .config
make defconfig >"$TREE/defconfig.log" 2>&1 || { tail -20 "$TREE/defconfig.log" >&2; fail "make defconfig failed"; }
info "$(grep -c '^CONFIG_PACKAGE_.*=y' .config) packages selected, $(grep -c '^CONFIG_PACKAGE_kmod-.*=y' .config) of them kmods"

grep -q '^CONFIG_TARGET_mediatek_mt7622_DEVICE_dlink_dir-x3260-a1=y' .config \
	|| fail "device not selected after defconfig"
grep -q '^CONFIG_USE_APK=y' .config            || fail "apk not selected"

# The source tree has no .git, so scripts/getver.sh yields REVISION=unknown. base-files
# then builds version "$(PKG_RELEASE)~$(REVISION)" = "...~unknown", which apk-tools
# rejects (the part after ~ must be numeric/hex). Pin REVISION to a hex code; image
# filenames do not include it.
VREV=${VREV:-20261104}
grep -q '^CONFIG_PACKAGE_apk-openssl=y' .config || fail "apk-openssl not selected"
grep -q '^CONFIG_PACKAGE_luci=y' .config       || fail "LuCI not selected"
ok "target/device, apk and LuCI all selected"

missing=""
for k in $KMODS_CSV; do
	grep -q "^CONFIG_PACKAGE_${k}=y$" .config || missing="$missing $k"
done
[ -z "$missing" ] || fail "kernel modules missing from .config:$missing"
ok "all 76 kmods resolved into .config (nothing silently dropped)"

leaked=""
for a in $APPS; do
	grep -q "^CONFIG_PACKAGE_${a}=y$" .config && leaked="$leaked $a"
done
[ -z "$leaked" ] || fail "these apps must NOT be in the image:$leaked"
ok "no feature app selected (openclash/passwall/mwan3/sqm/wol/upnp)"

grep -q '^CONFIG_PACKAGE_luci-theme-argon=y$' .config \
	|| fail "argon theme did not resolve into .config (wget-any/ucode-mod-math dep?)"
ok "argon theme + deps resolved (default LuCI theme, like the v4 build)"

if [ -d "$KIT/files" ]; then
	rm -rf files
	cp -a "$KIT/files" files
	find files -type d -exec chmod 0755 {} +
	find files -type f -exec chmod 0644 {} +
	for f in files/etc/uci-defaults/*; do [ -f "$f" ] && chmod 0755 "$f"; done
	ok "files/ overlay staged: $(cd files && find . -type f -printf '%P ')"
fi

if $CHECK_ONLY; then
	say "config check passed (build not started)"
	cp .config "$KIT/config/barebone.resolved.config"
	info "resolved config saved to config/barebone.resolved.config"
	exit 0
fi

# ---------------------------------------------------------------------------
say "3/6 build (make tools/toolchain/package/target -j$JOBS)"
BD=build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_mt7622
LOG="$TREE/build-barebone-$(date +%Y%m%d-%H%M).log"
rm -f "$BD/root.squashfs" bin/targets/mediatek/mt7622/immortalwrt-* 2>/dev/null || true
info "log: $LOG"
# `make target/install` on its own does NOT build the toolchain: on a clean tree the
# kernel then tries to exec aarch64-openwrt-linux-musl-gcc, which does not exist yet,
# and dies in kconfig with misleading bison/lexer errors. It also does NOT populate
# build_dir/target-*/root-mediatek -- only `make package/install` does, and without it
# mksquashfs4 dies with 'Cannot stat source directory ... root-mediatek'. And kmod
# packages must come after the kernel's own `make modules` pass, otherwise modpost
# reports every kernel symbol as undefined (Module.symvers not generated yet). Build
# all stages in dependency order. Each stage is a no-op if already up to date.
: >"$LOG"
rc=0
for stage in tools/install toolchain/install target/compile package/compile package/install target/install; do
	info "make $stage -j$JOBS"
	if ! make "$stage" V=s -j"$JOBS" REVISION="$VREV" >>"$LOG" 2>&1; then rc=1; break; fi
done
[ $rc -eq 0 ] || { grep -n 'Error [0-9]\|error:' "$LOG" | tail -15 >&2; fail "build failed in $stage (rc=$rc), see $LOG"; }
ok "build finished rc=0 (tools, toolchain, kernel, package, target)"

n=$(grep -c 'Failed to read file' "$LOG" || true)
[ "$n" -eq 0 ] || fail "$n 'Failed to read file' lines -- the sparse/zero-byte bug is active, image is a brick"
ok "0 'Failed to read file' lines in the log"
grep -n 'recovery.bin is too big\|file is too big' "$LOG" | tail -2 || true
info "(a 'recovery.bin is too big' warning is expected and harmless -- see BUILD.md 3)"

B=bin/targets/mediatek/mt7622
IMG="$B/immortalwrt-mediatek-mt7622-dlink_dir-x3260-a1-squashfs-sysupgrade.bin"
INITRAMFS="$B/immortalwrt-mediatek-mt7622-dlink_dir-x3260-a1-initramfs-kernel.bin"
MANIFEST="$B/immortalwrt-mediatek-mt7622-dlink_dir-x3260-a1.manifest"
[ -f "$IMG" ] || fail "sysupgrade image not produced"

# ---------------------------------------------------------------------------
say "4/6 gate: verify-image.sh"
bash "$KIT/scripts/verify-image.sh" "$IMG" | tee "$TREE/gate.log" | tail -20
grep -q 'RESULT: PASS' "$TREE/gate.log" || fail "gate did not pass -- do not flash"

# ---------------------------------------------------------------------------
say "5/6 manifest: what is actually inside the image"
for k in $KMODS_CSV; do
	grep -q "^$k - " "$MANIFEST" || fail "$k missing from the image manifest"
done
ok "76/76 kmods in the image manifest"
for a in $APPS; do
	grep -q "^$a - " "$MANIFEST" && fail "$a leaked into the image"
done
ok "no app packages in the image"
info "$(wc -l <"$MANIFEST") packages installed"

# squashfs -> overlay arithmetic (FILESYSTEM.md 3)
SQ=""
[ -f "$BD/root.squashfs" ] && SQ="$BD/root.squashfs"
if [ -z "$SQ" ]; then
	tmpd="$(mktemp -d)"; tar -xf "$IMG" -C "$tmpd" root 2>/dev/null && SQ="$tmpd/root"
fi
if [ -n "$SQ" ] && [ -f "$SQ" ]; then
	sz=$(stat -c%s "$SQ")
	leb=$(( (sz + 126976 - 1) / 126976 ))
	left=$(( 382 - leb ))
	[ "$left" -lt 8 ] && fail "rootfs uses $leb LEBs, overlay left: only $left LEBs"
	printf '  ..   squashfs %s B -> %s LEBs, rootfs_data %s LEBs = %s MiB, ~%s MiB free after first boot\n' \
		"$sz" "$leb" "$left" "$(( left * 126976 / 1048576 ))" "$(( left * 126976 / 1048576 - 3 ))"
else
	info "root.squashfs not found, skipping overlay arithmetic"
fi

# ---------------------------------------------------------------------------
say "6/6 package release"
STAMP="$(date +%Y%m%d)${DIST_SUFFIX:+-$DIST_SUFFIX}"
D="${OUT:-$KIT/release}/barebone-$STAMP"
mkdir -p "$D" 2>/dev/null && :
cp "$IMG" "$INITRAMFS" "$MANIFEST" "$D/"
cp .config "$D/config.txt"
cp "$KIT/config/kmods.txt" "$D/kmods.txt"
cp "$KIT/config/dropped-packages.txt" "$D/dropped-packages.txt"
[ -f "$TREE/gate.log" ] && cp "$TREE/gate.log" "$D/gate.log"
if [ -d .git ]; then git diff >"$D/0001-local-changes.patch"; fi
{
	echo "device   D-Link DIR-X3260 A1 (mediatek/mt7622, aarch64_cortex-a53)"
	echo "tree     $TREE"
	echo "head     $(git -C "$TREE" log -1 --format='%H %s' 2>/dev/null || echo 'no git')"
	echo "built    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	echo "kmods    $(printf '%s\n' "$KMODS" | wc -l)"
	echo "packages $(wc -l <"$MANIFEST")"
	echo "profile  barebone: base system + LuCI light + apk + kmods for openclash/passwall1/passwall2/mwan3/sqm/wol"
	echo "extras   luci-theme-argon default, dropbear on 22, first-boot root password 'root' (change it)"
} >"$D/BUILD-INFO.txt"
( cd "$D" && sha256sum * > SHA256SUMS && sed 's/^/  /' SHA256SUMS )

say "done"
printf '  %s\n' "$D"
printf '  %s bytes\n' "$(stat -c%s "$IMG")"
printf '\n  Next: read dist output, flash with sysupgrade -n (see BUILD-KIT/FLASH.md).\n'
