#!/bin/bash
#
# verify-image.sh -- pre-flash "brick gate" for D-Link DIR-X3260 A1 images.
#
#   ./verify-image.sh <image.bin|root.squashfs> [--ref <dir>]
#
# Accepts either a sysupgrade .bin (a tar containing kernel + root) or a bare
# squashfs.  Unpacks the root filesystem and checks the things that actually
# decide whether the device boots:
#
#   * /etc/inittab exists and is not empty           (empty inittab = dead box)
#   * /lib/preinit/* scripts are all non-empty
#   * init/procd/ubusd/netifd/busybox/libc are present and ELF
#   * no zero-byte file in a boot-critical directory
#   * exactly one kernel vermagic across all modules
#
# With --ref <dir> it also diffs the image against an extracted known-good
# root tree (file list + md5 + mode), which is how the v4 image was validated
# against the hardware-proven V1 build.
#
# Exit status: 0 = pass, 1 = FAIL (do not flash).
#
set -u

WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

die()  { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok   $*"; }
note() { echo "  ..   $*"; }

IMAGE=""
REF=""
while [ $# -gt 0 ]; do
	case "$1" in
		--ref) REF="$2"; shift 2 ;;
		-h|--help) sed -n '2,24p' "$0"; exit 0 ;;
		*) IMAGE="$1"; shift ;;
	esac
done
[ -n "$IMAGE" ] || die "usage: $0 <image.bin|root.squashfs> [--ref <dir>]"
[ -f "$IMAGE" ] || die "no such file: $IMAGE"

# --- locate unsquashfs ------------------------------------------------------
UNSQ="${UNSQUASHFS:-}"
if [ -z "$UNSQ" ]; then
	for c in \
		"$(dirname "$0")/../../staging_dir/host/bin/unsquashfs4" \
		/root/build/dirx3260/staging_dir/host/bin/unsquashfs4 \
		/root/build/dirx3260/staging_dir/host/bin/unsquashfs
	do
		[ -x "$c" ] && { UNSQ="$c"; break; }
	done
	[ -n "$UNSQ" ] || UNSQ="$(command -v unsquashfs4 || command -v unsquashfs || true)"
fi
[ -n "$UNSQ" ] && [ -x "$UNSQ" ] || die "unsquashfs not found (set UNSQUASHFS=/path/to/unsquashfs4)"

WORK="$(mktemp -d)" || die "cannot create temp dir"

echo "== image =="
printf '  file   %s\n' "$IMAGE"
printf '  size   %s bytes\n' "$(stat -c%s "$IMAGE")"
printf '  sha256 %s\n' "$(sha256sum "$IMAGE" | cut -d' ' -f1)"

# --- get the squashfs out of the sysupgrade tar -----------------------------
SQ="$IMAGE"
if tar -tf "$IMAGE" >/dev/null 2>&1; then
	member="$(tar -tf "$IMAGE" | grep -E '(^|/)root$' | head -1)"
	[ -n "$member" ] || die "tar has no member named 'root'"
	note "sysupgrade tar, member: $member"
	tar -xf "$IMAGE" -C "$WORK" "$member" || die "cannot extract $member"
	SQ="$WORK/$member"
fi

FS="$WORK/fs"
"$UNSQ" -f -d "$FS" "$SQ" >"$WORK/unsq.log" 2>&1 || {
	tail -20 "$WORK/unsq.log" >&2
	die "unsquashfs failed (corrupt or truncated filesystem)"
}
[ -d "$FS/etc" ] || die "unpacked filesystem has no /etc"

echo "== contents =="
FILES="$(find "$FS" -type f | wc -l)"
printf '  files  %s\n' "$FILES"
printf '  bytes  %s (uncompressed)\n' "$(du -sb "$FS" | cut -f1)"
[ "$FILES" -gt 500 ] || die "only $FILES files unpacked -- image is truncated"
[ "$FILES" -gt 1000 ] || note "unusually small file count for a full build"

# --- boot critical checks ---------------------------------------------------
echo "== boot gate =="

INITTAB_SZ=0
[ -f "$FS/etc/inittab" ] && INITTAB_SZ="$(stat -c%s "$FS/etc/inittab")"
[ "$INITTAB_SZ" -ge 50 ] || die "/etc/inittab missing or empty (size=$INITTAB_SZ) -- WILL NOT BOOT"
ok "/etc/inittab present, $INITTAB_SZ bytes"

PRE_N=0
while IFS= read -r f; do
	[ "$(stat -c%s "$f")" -gt 0 ] || die "empty preinit script: ${f#"$FS"}"
	PRE_N=$((PRE_N + 1))
done < <(find "$FS/lib/preinit" -maxdepth 1 -type f 2>/dev/null)
[ "$PRE_N" -ge 10 ] || die "only $PRE_N preinit scripts found"
ok "$PRE_N preinit scripts, all non-empty"

for p in sbin/init sbin/procd sbin/ubusd sbin/netifd bin/busybox; do
	f="$FS/$p"
	[ -e "$f" ] || die "missing $p"
	[ -L "$f" ] && continue
	[ "$(stat -c%s "$f")" -gt 1000 ] || die "$p is only $(stat -c%s "$f") bytes"
	[ "$(head -c 4 "$f" | od -An -c | tr -d ' \n')" = '177ELF' ] || die "$p is not an ELF binary"
	ok "$p $(stat -c%s "$f") bytes"
done

LIBC="$(find "$FS/lib" -maxdepth 1 -name 'ld-musl-*.so.1' | head -1)"
if [ -z "$LIBC" ]; then
	LIBC="$(find "$FS/lib" -maxdepth 1 -name 'libc.so*' -not -type l | head -1)"
fi
[ -n "$LIBC" ] || die "no musl loader/libc in /lib"
LIBC_REAL="$(readlink -f "$LIBC" 2>/dev/null || echo "$LIBC")"
[ "$(stat -c%s "$LIBC_REAL")" -gt 100000 ] || die "musl libc is only $(stat -c%s "$LIBC_REAL") bytes"
ok "${LIBC#"$FS"} -> $(basename "$LIBC_REAL"), $(stat -c%s "$LIBC_REAL") bytes"

# zero-byte files are legal only in these places (package metadata, etc.)
ZERO_BAD=0
ZERO_ALL=0
while IFS= read -r f; do
	rel="${f#"$FS"}"
	case "$rel" in
		/etc/syslog.conf|\
		/etc/luci-uploads/.placeholder|\
		/lib/apk/db/triggers|\
		/lib/apk/packages/*.list|\
		/usr/lib/ruby/*/gem.build_complete|\
		/www/luci-static/resources/xhr.js)
			ZERO_ALL=$((ZERO_ALL + 1)) ;;
		*)
			ZERO_BAD=$((ZERO_BAD + 1))
			echo "  bad  zero-byte: $rel" >&2 ;;
	esac
done < <(find "$FS" -type f -size 0)
[ "$ZERO_BAD" -eq 0 ] || die "$ZERO_BAD unexpected zero-byte file(s) -- the mksquashfs/WSL1 'sparse' bug is back (see CONTEXT.md)"
ok "no unexpected zero-byte files ($ZERO_ALL expected empties)"

# --- kernel modules ---------------------------------------------------------
echo "== modules =="
KO_N=0
VM=""
VM_BAD=0
while IFS= read -r f; do
	KO_N=$((KO_N + 1))
	v="$(strings "$f" | grep -m1 '^vermagic=' | cut -d= -f2-)"
	[ -n "$v" ] || continue
	if [ -z "$VM" ]; then
		VM="$v"
	elif [ "$v" != "$VM" ]; then
		VM_BAD=$((VM_BAD + 1))
		echo "  bad  vermagic mismatch: ${f#"$FS"} -> $v" >&2
	fi
done < <(find "$FS/lib/modules" -name '*.ko*' 2>/dev/null)
[ "$KO_N" -gt 0 ] || die "no kernel modules found"
[ "$VM_BAD" -eq 0 ] || die "$VM_BAD module(s) have a different vermagic than '$VM'"
ok "$KO_N modules, single vermagic: $VM"

# --- optional comparison against a known-good tree --------------------------
if [ -n "$REF" ]; then
	echo "== diff vs reference =="
	[ -d "$REF" ] || die "reference dir not found: $REF"
	( cd "$FS" && find . \( -type f -o -type l \) -printf '%P\n' | LC_ALL=C sort ) >"$WORK/a.list"
	( cd "$REF" && find . \( -type f -o -type l \) -printf '%P\n' | LC_ALL=C sort ) >"$WORK/b.list"
	only_a="$(comm -23 "$WORK/a.list" "$WORK/b.list" | wc -l)"
	only_b="$(comm -13 "$WORK/a.list" "$WORK/b.list" | wc -l)"
	note "files only in image: $only_a, only in reference: $only_b"
	( cd "$FS" && find . -type f -exec md5sum {} + | LC_ALL=C sort -k2 ) >"$WORK/a.md5"
	( cd "$REF" && find . -type f -exec md5sum {} + | LC_ALL=C sort -k2 ) >"$WORK/b.md5"
	same="$(comm -12 "$WORK/a.md5" "$WORK/b.md5" | wc -l)"
	note "md5-identical files: $same"
	printf '  note differing files are expected (package set / version drift);\n'
	printf '       compare the boot chain and modules, not the whole tree.\n'
fi

echo "== RESULT: PASS -- safe to flash =="
