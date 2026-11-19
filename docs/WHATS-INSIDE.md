# What is inside the image

Built from `config/barebone.config` → `make defconfig` → `config/barebone.resolved.config`.
Final packaged set: **210 packages**, **1,268 files**, 29,019,048 B uncompressed,
**76** of the packages are `kmod-*`.

## 1. The split that defines this image

| layer | locked to the build? | how it is added |
|---|---|---|
| kernel + its modules (`kmod-*`) | **yes** — `vermagic 6.18.44 SMP mod_unload aarch64` | only by rebuilding the image |
| everything else (LuCI apps, proxy cores, daemons) | no | `apk add` on the running router |

So the image contains the whole module set of the hardware-validated v4 build, and none of the
applications. Installing an app later cannot fail on a missing module.

## 2. The 76 kernel modules, by purpose

The authoritative list is [`config/kmods.txt`](../config/kmods.txt) (one package per line, grouped
the same way). Summary:

| group | count | modules |
|---|---|---|
| Wi-Fi / WPA3 crypto (deps of mac80211) | 17 | `kmod-crypto-{aead,ccm,cmac,ctr,gcm,geniv,gf128,ghash,hash,hmac,manager,null,rng,seqiv,sha1,sha3,sha512}` |
| radios | 9 | `kmod-cfg80211`, `kmod-mac80211`, `kmod-mt76-core`, `kmod-mt76-connac`, `kmod-mt7615-common`, `kmod-mt7615e`, `kmod-mt7915e`, `kmod-mt7915-firmware`, `kmod-mt7622-firmware` |
| platform / board | 6 | `kmod-gpio-button-hotplug`, `kmod-leds-gpio`, `kmod-hwmon-core`, `kmod-i2c-core`, `kmod-thermal`, `kmod-lib-crc-ccitt` |
| WAN PPPoE | 5 | `kmod-ppp`, `kmod-pppox`, `kmod-pppoe`, `kmod-mppe`, `kmod-slhc` |
| netfilter core | 22 | `kmod-nfnetlink`, `kmod-nf-*` (conntrack, conntrack-netlink, flow, ipt, ipt6, log, log6, nat, reject, reject6, socket, tproxy, conncount), `kmod-nft-{core,compat,fib,nat,offload,fullcone,socket,tproxy}` |
| iptables / ipset back end | 7 | `kmod-iptables`, `kmod-ip6tables`, `kmod-ipt-core`, `kmod-ipt-conntrack`, `kmod-ipt-conntrack-extra`, `kmod-ipt-ipopt`, `kmod-ipt-ipset` |
| qdiscs for SQM | 6 | `kmod-sched-core`, `kmod-sched-cake`, `kmod-ifb`, `kmod-sched-act-vlan`, `kmod-sched-bpf`, `kmod-sched-flower` |
| tunnels / sockets for OpenClash | 3 | `kmod-tun`, `kmod-inet-diag`, `kmod-netlink-diag` |
| misc for multi-WAN / proxies | 1 | `kmod-macvlan` |

The image ends up with **140** kernel module files, all with the single `vermagic`
`6.18.44 SMP mod_unload aarch64`.

## 3. What each app needs — and that it is present

Dependency lists come from the feed Makefiles:
`immortalwrt/luci: applications/luci-app-openclash`, `applications/luci-app-passwall`,
`Openwrt-Passwall/openwrt-passwall2`, `openwrt/packages: net/mwan3`, `net/sqm-scripts`,
`openwrt/luci: applications/luci-app-wol`.

| you will install | user-space packages | modules already in this image |
|---|---|---|
| **OpenClash** | `luci-app-openclash` | `kmod-tun`, `kmod-inet-diag`, `kmod-netlink-diag`, `kmod-nft-tproxy`, `kmod-nf-tproxy`, `kmod-nft-core`, `kmod-nft-fib`, `kmod-nft-nat`, `kmod-nf-reject`, `kmod-nf-reject6` |
| **PassWall 1** | `luci-app-passwall` (+ a core such as `xray-core`) | `kmod-nft-socket`, `kmod-nft-tproxy`, `kmod-nft-nat`, `kmod-nf-reject`, `kmod-nf-reject6` |
| **PassWall 2** | `luci-app-passwall2` (extra feed) | same as PassWall 1, plus the `kmod-ipt-*` TPROXY set if you choose iptables mode |
| **mwan3** | `mwan3`, `luci-app-mwan3` | `kmod-ipt-ipset`, `kmod-ipt-conntrack-extra`, `kmod-ipt-ipopt`, `kmod-iptables`, `kmod-ip6tables`, `kmod-ipt-core`, `kmod-macvlan` |
| **SQM / cake** | `sqm-scripts`, `luci-app-sqm`, `tc` | `kmod-sched-cake`, `kmod-sched-core`, `kmod-ifb` (+ `kmod-sched-act-vlan/bpf/flower`) |
| **Wake-on-LAN** | `luci-app-wol`, `etherwake` | none needed — the MT7531/ethernet driver handles magic packets |

## 4. What was deliberately left out

`config/dropped-packages.txt` lists all 56 packages that are `is not set` relative to the v4
config, grouped by reason. The five tracked apps plus their user-space-only helpers:

- the apps: `luci-app-openclash`, `luci-app-passwall`, `luci-app-mwan3`, `luci-app-sqm`,
  `luci-app-upnp`, `luci-app-wol`, `mwan3`, `sqm-scripts`, `miniupnpd-nftables`, `etherwake`
- runtime only openclash/passwall needed: `bash`, `libreadline`, `libncurses`, `terminfo`,
  `coreutils*`, `curl`, `libcurl`, `libnghttp2`, `unzip`, `ruby*`, `lyaml`, `libyaml`,
  `microsocks`, `resolveip`, `shellsync`
- runtime only mwan3/sqm needed (the **modules** stay in): `ipset`, `libipset`, `iptables-nft`,
  `ip6tables-nft`, `xtables-nft`, `iptables-mod-*`, `libiptext*`, `tc-tiny`
- theme/translations for the dropped apps — note `luci-theme-argon` itself **is** included and is
  the default theme

`apk` pulls these back in automatically when you install an app, so nothing is lost by their
absence; only ~14 MB of flash is reclaimed.

## 5. Space: the overlay is the real limit

Storage on this target is `rootfs` (squashfs, read-only) plus `rootfs_data` (UBIFS, the writable
overlay) inside 382 usable LEBs of 126,976 B. The overlay gets whatever the squashfs does not use.

Measured on an earlier build of this config (206 packages): squashfs 8,896,321 B → 71 LEBs,
`rootfs_data` 311 LEBs ≈ 37 MiB, ≈ 34 MiB free after first boot. The published Argon build adds
~1 MB uncompressed (1,268 files, 29.0 MB), so expect roughly **33–34 MiB of overlay, ~30 MiB
free**.

Real compressed `.apk` sizes from the snapshot feed:

| package | `.apk` | roughly unpacked |
|---|---|---|
| `luci-app-openclash` | 8.3 MB | ~20 MB |
| `luci-app-passwall` | 0.86 MB | ~2.5 MB (UI only) |
| `xray-core` | 11.3 MB | ~30 MB |
| `sing-box` | 22.7 MB | ~65 MB |
| `mwan3` + `luci-app-mwan3` | 35 KB | < 1 MB |
| `sqm-scripts` + `luci-app-sqm` | 24 KB | < 1 MB |
| `luci-app-wol` + `etherwake` | 11 KB | < 1 MB |

Two consequences, both important:

**(a) `apk` writes into the overlay and sysupgrade wipes the overlay.** `mwan3`, SQM and WOL fit
trivially and OpenClash fits. PassWall + `xray-core` is a tight fit; `passwall2` + `sing-box` does
not fit at all. Everything installed with `apk` is lost on the next sysupgrade (only
`/etc/config` survives), so anything you intend to keep belongs in the image — see
[BUILD.md](BUILD.md) §6.

**(b) A full overlay is a broken router, not a slow one.** Check before installing:
`apk add --simulate <pkgs>` for the download size, `df -h /overlay` for what is left.

## 6. First boot behaviour

`files/etc/uci-defaults/90-barebone-ssh`, `91-barebone-rootpw`, `92-barebone-theme` run once on a
fresh flash: guarantee a dropbear listener on 22, set the root password to `root` **only if it is
empty**, and select Argon as the LuCI theme. They never overwrite unrelated user configuration.
Details and the security warning: [INSTALL.md](INSTALL.md) §4.
