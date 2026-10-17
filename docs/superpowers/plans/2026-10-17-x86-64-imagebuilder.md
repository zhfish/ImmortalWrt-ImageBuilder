# x86-64 ImmortalWrt ImageBuilder Action Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `workflow_dispatch` Action that builds one x86-64 UEFI ImmortalWrt image with nftables-only networking, static Docker + DPanel, and first-boot provisioning (data disk, port mode, DNS/DHCP, macvlan + shim).

**Architecture:** Runner downloads third-party binaries (Docker from TUNA, Compose, DPanel, timecontrol apk) and stages a rootfs overlay; the official `immortalwrt/imagebuilder` container builds the image from `packages.txt` + `config.override` and verifies the manifest. All on-device behaviour lives in small POSIX-sh scripts under `build/files/` that share `/usr/lib/custom/lib.sh`; each script is exercised by sh tests that use fake `uci`/`ethtool`/`docker`/`logger` and a fake sysfs.

**Tech Stack:** POSIX sh (BusyBox ash on device; dash/busybox in CI), uci, procd, sfdisk/partx, GitHub Actions, gh CLI, ImageBuilder (apk).

**Spec:** `docs/superpowers/specs/2026-10-17-x86-64-imagebuilder-design.md`

## Global Constraints

- Inputs: `version` default `25.12.2` matching `^[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$`; `lan_ip` default `10.214.37.1`, must be `x.x.x.1`, octets 0–255, no leading zeros, /24.
- Image: squashfs `combined-efi` only, `CONFIG_GRUB_TIMEOUT="3"`, `CONFIG_TARGET_ROOTFS_PARTSIZE=4096`.
- Firmware apk mirror `https://mirrors.cernet.edu.cn/immortalwrt` (via `system.@imm_init[0].apk_mirror`); build-time packages from official `downloads.immortalwrt.org`.
- Docker static tgz from `https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/static/stable/x86_64/`, fallback `https://download.docker.com/linux/static/stable/x86_64/`; no feed `dockerd`/`docker`/`containerd`/`runc`.
- Address plan (P = LAN prefix): P.1 router + shim /32; P.2–P.7 fixed containers (P.2 = kexue); P.8/29 macvlan auto range; DHCP P.50–P.200 (`start=50`, `limit=151`); shim route `P.0/28`.
- DNS: `noresolv=1`, servers `123.123.123.123`, `114.114.114.114`, `cachesize=8000`, `rebind_protection=0`; nothing else in dnsmasq changed.
- LAN has no IPv6 (no `ip6assign`, no `ula_prefix`, `ra`/`dhcpv6`/`ndp` = `disabled`); `wan6` `reqaddress=try`, `reqprefix=no`, `peerdns=0`.
- Log tag `custom-init`; marker `/etc/custom-provisioned`; build config `/etc/custom/build.conf`; shared lib dir `/usr/lib/custom`.
- DPanel: port `8086`, data `/data/dpanel`; Docker data `/data/docker`; json-file logs `max-size=100m`, `max-file=5`.
- **No git commits or pushes during execution** — the working tree contains the user's own staged changes; the user decides at the end.
- All device scripts are POSIX sh (no bashisms); tests must pass under `dash` and `busybox sh`.

## Review Focus

1. **VM disk exactly the image size, or second boot after partitioning** → no new partition, no error, `/data` still a directory. Test: `test_datadisk.sh` second-run and no-free-space cases (Task 3).
2. **Docker version list where 29.10.0 > 29.9.1** → must pick 29.10.0, not lexical max. Test: `test_build.sh::latest_docker_version_numeric` (Task 9).
3. **NICs reporting 2500baseT as a lower mode (5G/10G) or no link modes (virtio)** → not counted as 2.5G; virtio-only machine stays in default mode. Test: `test_lib.sh` speed fixtures + `test_network.sh` 10G and virtio cases (Tasks 2, 5).
4. **Sysupgrade with kept settings (marker present)** → scripts 20/30/40/50 make zero uci writes. Test: marker case in each of `test_system.sh`, `test_network.sh`, `test_dhcp.sh`, `test_docker_fw.sh` (Tasks 4–7).
5. **`lan_ip` typos (`10.214.37.01`, trailing space, `.254`)** → workflow fails before building. Test: `test_build.sh` validate cases (Task 9).

---

## File Structure

```
.gitignore                                         .DS_Store
archive/                                           old workflow, x86-64/, shell/, files/ (moved, untouched)
.github/workflows/build.yml                        new Action (test job + build job)
build/packages.txt                                 package list, one per line, # comments
build/config.override                              image config fragment
build/validate-inputs.sh                           valid_version / valid_lan_ip + CLI
build/fetch-extras.sh                              runner-side downloads → extras dir + versions.env
build/stage.sh                                     assemble overlay: files + binaries + rendered templates
build/build.sh                                     inside IB container: config, packages, make image, verify
build/smoke-datadisk.sh                            run datadisk_new_partition against the built image (CI)
build/templates/daemon.json.in                     Docker config, @LAN_IP@
build/files/usr/lib/custom/lib.sh                  shared helpers (pure where possible)
build/files/usr/lib/custom/datadisk.sh             partition creation on a given disk path
build/files/etc/uci-defaults/10-custom-data-disk
build/files/etc/uci-defaults/20-custom-system
build/files/etc/uci-defaults/30-custom-network
build/files/etc/uci-defaults/40-custom-dhcp
build/files/etc/uci-defaults/50-custom-docker
build/files/etc/uci-defaults/90-custom-done
build/files/lib/upgrade/keep.d/custom              /etc/custom-provisioned
build/files/etc/sysctl.d/90-router.conf
build/files/etc/init.d/dockerd                     procd service for static dockerd
build/files/etc/init.d/dpanel                      procd service for DPanel
build/files/etc/init.d/lan-macvlan                 procd one-shot running the script below
build/files/usr/libexec/custom/lan-macvlan.sh      create lan_macvlan when Docker is ready
build/files/usr/share/luci/menu.d/luci-app-dpanel.json
build/files/www/luci-static/resources/view/dpanel.js
tests/run.sh  tests/helpers.sh  tests/stubs/{uci,ethtool,logger,docker}
tests/fixtures/...                                 ethtool outputs, uci default state, sfdisk -F, dpanel config, html listing, manifests
tests/test_*.sh
README.md                                          rewritten
```

Script conventions (every device script):
- `#!/bin/sh`, sources `"${CUSTOM_LIBDIR:-/usr/lib/custom}/lib.sh"`.
- Guarded scripts (20/30/40/50) start with `custom_is_provisioned && exit 0`.
- All uci writes use plain `uci -q set|delete|add_list|del_list|add` commands (no `uci batch`) so the fake can record them; finish with `uci commit <pkg>`.
- Always `exit 0` (errors are logged, never retried by uci-defaults), except tests may inspect logs.

---

### Task 1: Archive old content and add the test harness

**Files:**
- Move: `.github/workflows/build-x86-64-25.12.x.yml`, `x86-64/`, `shell/`, `files/` → `archive/` (same relative paths)
- Create: `.gitignore`, `tests/run.sh`, `tests/helpers.sh`, `tests/stubs/uci`, `tests/stubs/ethtool`, `tests/stubs/logger`, `tests/stubs/docker`, `tests/test_harness.sh`, `tests/fixtures/uci/default.state`

**Interfaces:**
- Produces:
  - `sh tests/run.sh` runs every `tests/test_*.sh` in a fresh `sh`, prints `PASS <file>`/`FAIL <file>`, exits non-zero if any fail.
  - `tests/helpers.sh`: `assert_eq <expected> <actual> <msg>`, `assert_contains <haystack> <needle> <msg>`, `assert_not_contains <haystack> <needle> <msg>`, `assert_file_contains <file> <needle> <msg>`, `fail <msg>`; `setup_env` creates `$T` (mktemp dir) and exports `PATH="$REPO/tests/stubs:$PATH"`, `CUSTOM_LIBDIR="$REPO/build/files/usr/lib/custom"`, `CUSTOM_CONF="$T/build.conf"` (content `LAN_IP='10.214.37.1'`), `CUSTOM_MARKER="$T/provisioned"`, `CUSTOM_SYSFS="$T/sys"`, `UCI_STATE="$T/uci.state"` (copy of `fixtures/uci/default.state`), `UCI_LOG="$T/uci.log"`, `LOG_FILE="$T/log"`, `ETHTOOL_DIR="$T/ethtool"`, `DOCKER_LOG="$T/docker.log"`; `uci_val <key>` prints the fake state value(s); `make_port <name> <ethtool-fixture|none> [wireless]` creates `$CUSTOM_SYSFS/class/net/<name>/{type=1,device/}` and copies the fixture to `$ETHTOOL_DIR/<name>`; `make_virtual <name> <type>` creates an entry without `device/`.
  - Fake `uci` (state file `$UCI_STATE`, one `key=value` per line, list items are repeated keys, section lines are `pkg.sec=type`): strips `-q`; `get k` prints values space-joined or exits 1; `set k=v` replaces; `delete k` removes `k` and `k.*`; `add_list k=v` appends; `del_list k=v` removes that exact line; `add pkg type` appends `pkg.@type[n]=type` with the next free n; `show pkg` prints lines starting with `pkg.`; `commit`/`revert` no-op; every invocation except `get`/`show` appended to `$UCI_LOG`.
  - Fake `ethtool <dev>` → `cat "$ETHTOOL_DIR/<dev>"`, exit 1 if missing. Fake `logger` → appends `$*` to `$LOG_FILE`. Fake `docker` → appends `$*` to `$DOCKER_LOG`; behaviour driven by env `DOCKER_INFO_RC` (exit code for `info`, default 0), `DOCKER_NET_EXISTS` (1 = `network inspect` succeeds), `DOCKER_NET_DESC` (output of `network inspect -f ...`).
  - `fixtures/uci/default.state`: ImmortalWrt x86 defaults the scripts touch: `network.lan` (device `br-lan`, proto static, ipaddr `192.168.1.1`, netmask, `ip6assign=60`), `network.@device[0]` (name `br-lan`, type bridge, ports `eth0`), `network.wan` (device `eth1`, proto dhcp), `network.wan6` (device `eth1`, proto dhcpv6), `network.globals.ula_prefix`, `dhcp.@dnsmasq[0]` (`cachesize=8000`, `rebind_protection=1`, `dns_redirect=1`, `resolvfile=...`), `dhcp.lan` (start 100, limit 150, `ra=server`, `dhcpv6=server`), `firewall.@defaults[0]`, `firewall.@zone[0]` (name lan, network lan), `firewall.@zone[1]` (name wan, network wan wan6), `luci.main.mediaurlbase=/luci-static/bootstrap`, `upnpd.config.enabled=1`, `system.@system[0]=system`.

- [ ] **Step 1: Move old content into `archive/`** with `mkdir -p archive/.github/workflows && mv` (plain `mv`, not `git mv`; the user's staged state stays as-is). Create `.gitignore` containing `.DS_Store`.
- [ ] **Step 2: Write `tests/test_harness.sh`** asserting the fake uci contract: after `uci set network.lan.ipaddr=10.0.0.1`, `uci_val network.lan.ipaddr` = `10.0.0.1`; `uci add_list dhcp.lan.dhcp_option=3,a` twice-different values → `uci -q get` prints both space-joined; `uci delete network.lan` removes `network.lan.*`; `uci -q get network.nope` exits 1; `uci add system imm_init` then `uci -q get system.@imm_init[0]` exits 0; `UCI_LOG` has the `set` line but not the `get`.
- [ ] **Step 3: Run `sh tests/run.sh`** — expected FAIL (stubs/helpers missing).
- [ ] **Step 4: Implement `tests/run.sh`, `tests/helpers.sh`, the four stubs, and `default.state`** per the contract above.
- [ ] **Step 5: Run `sh tests/run.sh` and `dash tests/run.sh`** — expected `PASS tests/test_harness.sh`, exit 0.

### Task 2: Shared library `lib.sh`

**Files:**
- Create: `build/files/usr/lib/custom/lib.sh`, `tests/test_lib.sh`, `tests/fixtures/ethtool/{1g,2g5,10g,virtio}.txt`, `tests/fixtures/sfdisk-F.txt`

**Interfaces:**
- Consumes: Task 1 harness.
- Produces (all in `lib.sh`; defaults `CUSTOM_CONF=/etc/custom/build.conf`, `CUSTOM_MARKER=/etc/custom-provisioned`, `CUSTOM_SYSFS=/sys`, each overridable by env):
  - `custom_log <msg...>` → `logger -t custom-init "<msg>"`
  - `custom_load_conf` → sources `$CUSTOM_CONF`, sets `LAN_IP` and `LAN_PREFIX`
  - `custom_is_provisioned` → status 0 iff `$CUSTOM_MARKER` exists
  - `lan_prefix <ip>` → prints first three octets
  - `ethtool_max_speed` → reads `ethtool` text on stdin, prints the max numeric prefix of tokens like `2500baseT/Full` inside the `Supported link modes:` block (continuation lines until the next `Key:` line), `0` if none
  - `port_max_speed <dev>` → `ethtool <dev> 2>/dev/null | ethtool_max_speed`
  - `phys_ports` → names under `$CUSTOM_SYSFS/class/net` having `device/`, `type` = `1`, and no `wireless/` or `phy80211`; one per line sorted by trailing number (`eth2` before `eth10`)
  - `pick_2g5_ports` → stdin lines `<name> <speed>` in port order; if exactly two have speed `2500`, prints `<first> <second>` and returns 0, else prints nothing and returns 1
  - `part_name <disk> <n>` → `sda 3`→`sda3`; `nvme0n1 3`→`nvme0n1p3`; `mmcblk0 3`→`mmcblk0p3` (append `p` when disk name ends in a digit)
  - `sfdisk_largest_free` → stdin `sfdisk -F` output; prints `<start> <end>` (sectors) of the row with the most sectors; nothing if no rows
  - `uci_zone_index <name>` → prints i where `firewall.@zone[i].name` = name (scan i=0.. until get fails); return 1 if absent

- [ ] **Step 1: Write fixtures.** `2g5.txt` = realistic igc output whose link modes span two lines ending `2500baseT/Full`; `1g.txt` ends at `1000baseT/Full`; `10g.txt` lists `... 2500baseT/Full 5000baseT/Full 10000baseT/Full`; `virtio.txt` has `Supported link modes:   Not reported`. `sfdisk-F.txt` = header lines plus rows `34 511 478 239K` and `8521728 16777182 8255455 3.9G`.
- [ ] **Step 2: Write `tests/test_lib.sh`** with assertions: `lan_prefix 10.214.37.1` = `10.214.37`; `ethtool_max_speed < 2g5.txt` = `2500`, `< 1g.txt` = `1000`, `< 10g.txt` = `10000`, `< virtio.txt` = `0`; `printf 'eth0 1000\neth1 2500\neth2 2500\neth3 1000\n' | pick_2g5_ports` = `eth1 eth2`; with three 2500 lines → empty + status 1; with `eth1 2500` and `eth2 10000` → empty + status 1; `part_name sda 3`=`sda3`, `part_name nvme0n1 3`=`nvme0n1p3`; `sfdisk_largest_free < sfdisk-F.txt` = `8521728 16777182`; `phys_ports` over fake sysfs with `eth10`, `eth2`, `lo`(772, no device), `br-lan`(no device), `wlan0`(wireless) prints `eth2\neth10`; `custom_is_provisioned` false before / true after `touch $CUSTOM_MARKER`; `uci_zone_index wan` = `1` on default state.
- [ ] **Step 3: Run `sh tests/run.sh`** — expected FAIL on `test_lib.sh`.
- [ ] **Step 4: Implement `lib.sh`** (awk for `ethtool_max_speed` and `sfdisk_largest_free`; no bash features).
- [ ] **Step 5: Run `sh tests/run.sh` and `dash tests/run.sh`** — expected all PASS.

### Task 3: Data disk (`/data`)

**Files:**
- Create: `build/files/usr/lib/custom/datadisk.sh`, `build/files/etc/uci-defaults/10-custom-data-disk`, `build/smoke-datadisk.sh`, `tests/test_datadisk.sh`

**Interfaces:**
- Consumes: `sfdisk_largest_free`, `part_name`, `custom_log` (Task 2).
- Produces:
  - `datadisk_new_partition <disk_path> <min_bytes>` (in `datadisk.sh`): `sfdisk --relocate gpt-bak-std`; take `sfdisk -F` largest region; align start up to a multiple of 2048 sectors; if `(end - start + 1) * 512 < min_bytes` return 1 printing nothing; else `printf 'start=%s, size=%s, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=data\n' | sfdisk --append --no-reread --no-tell-kernel -q <disk>` and print the new partition number (from `sfdisk -d` line whose `start=` equals the aligned start; number = trailing digits of the device field).
  - `build/smoke-datadisk.sh <image.img.gz>`: decompress into a sparse 8 GiB file (tolerate gzip exit 2 "trailing garbage"), run `datadisk_new_partition` with 1 GiB, assert it prints `3`, `sfdisk --verify` succeeds, partition 3 ends within 2048 sectors of the disk end, and a second run returns 1.
  - `10-custom-data-disk` flow: fstab section `fstab.data` exists → log + exit; find boot disk with `/lib/upgrade/common.sh` `export_bootdevice && export_partdevice disk 0`; reuse an existing `LABEL="data"` partition of that disk (from `block info`); else `datadisk_new_partition /dev/$disk 1073741824`, `partx --add --nr <n> /dev/$disk`, wait ≤5 s for `/dev/$(part_name $disk <n>)`; run `mkfs.ext4 -q -F -L data` only if `block info <part>` shows no `TYPE=`; `uci set fstab.data=mount`, `target=/data`, `uuid=<UUID>`, `enabled=1`, commit; `block mount`; always `mkdir -p /data/docker /data/dpanel`; every failure → `custom_log` and fall through to the `mkdir`; `exit 0`.

- [ ] **Step 1: Write `tests/test_datadisk.sh`**: if `sfdisk` is absent print `SKIP` and exit 0. Otherwise build a synthetic OpenWrt-like GPT in a 300 MiB file (`p128` bios-boot start 34 size 478, `p1` start 512 size 64 MiB, `p2` after p1 size 128 MiB), then `truncate -s 2G`. Assert: `datadisk_new_partition "$img" 536870912` prints `3`; `sfdisk --verify "$img"` exits 0; partition 3 start is a multiple of 2048 and ≥ p2 end; second call returns 1 and prints nothing. A third case on a fresh 300 MiB image (no growth) returns 1.
- [ ] **Step 2: Run `sh tests/run.sh`** — on Linux expected FAIL (no `datadisk.sh`); on macOS expected SKIP.
- [ ] **Step 3: Implement `datadisk.sh`, `10-custom-data-disk`, `smoke-datadisk.sh`.**
- [ ] **Step 4: Run `sh tests/run.sh`** — expected PASS (Linux) / SKIP (macOS); `sh -n` on all three files exits 0.

### Task 4: System settings, sysctl, marker

**Files:**
- Create: `build/files/etc/uci-defaults/20-custom-system`, `build/files/etc/uci-defaults/90-custom-done`, `build/files/etc/sysctl.d/90-router.conf`, `build/files/lib/upgrade/keep.d/custom`, `tests/test_system.sh`, `tests/fixtures/sshd_config`

**Interfaces:**
- Consumes: `custom_is_provisioned`, `custom_log` (Task 2).
- Produces: `20-custom-system` honours `SSHD_CONFIG` (default `/etc/ssh/sshd_config`); `90-custom-done` creates `$CUSTOM_MARKER`.

Exact values: `luci.main.mediaurlbase=/luci-static/argon`; ensure `system.@imm_init[0]` exists (`uci -q add system imm_init` when `get` fails) then `system.@imm_init[0].apk_mirror=https://mirrors.cernet.edu.cn/immortalwrt`; `upnpd.config.enabled=0`; `firewall.@defaults[0].flow_offloading=0` and `flow_offloading_hw=0`; sshd: replace any `#PermitRootLogin …`/`PermitRootLogin …` line with `PermitRootLogin yes`, append if none. sysctl file lines (exact):
`net.ipv4.tcp_congestion_control=bbr`, `net.core.default_qdisc=fq_codel`, `net.netfilter.nf_conntrack_max=262144`, `net.core.netdev_max_backlog=16384`, `net.core.netdev_budget=600`, `net.core.rmem_max=16777216`, `net.core.wmem_max=16777216`, `net.ipv4.tcp_rmem=4096 131072 16777216`, `net.ipv4.tcp_wmem=4096 16384 16777216`, `net.ipv4.tcp_fastopen=3`, `net.ipv4.tcp_mtu_probing=1`, `net.ipv4.tcp_slow_start_after_idle=0`, `net.ipv4.neigh.default.gc_thresh1=1024`, `net.ipv4.neigh.default.gc_thresh2=4096`, `net.ipv4.neigh.default.gc_thresh3=8192`, `fs.inotify.max_user_watches=524288`, `fs.inotify.max_user_instances=512`, `net.ipv4.conf.macvlan-shim.arp_filter=1` — each preceded by a one-line Chinese comment. keep.d file: `/etc/custom-provisioned`.

- [ ] **Step 1: Write `tests/test_system.sh`**: run `20-custom-system` on default state with `SSHD_CONFIG=$T/sshd_config` (copy of fixture containing `#PermitRootLogin prohibit-password`); assert the five uci values above, `system.@imm_init[0].apk_mirror`, and that the sshd file has exactly one `PermitRootLogin yes` and no other `PermitRootLogin` line. Marker case: `touch $CUSTOM_MARKER`, rerun on fresh state → `$UCI_LOG` empty and sshd file unchanged. `90-custom-done` creates `$CUSTOM_MARKER`. sysctl file contains `tcp_congestion_control=bbr` and `macvlan-shim.arp_filter=1` and no `arp_ignore` / `rp_filter`.
- [ ] **Step 2: Run tests** — expected FAIL on `test_system.sh`.
- [ ] **Step 3: Implement the four files.**
- [ ] **Step 4: Run `sh tests/run.sh` and `dash tests/run.sh`** — expected all PASS.

### Task 5: Port mode and WAN/LAN (`30-custom-network`)

**Files:**
- Create: `build/files/etc/uci-defaults/30-custom-network`, `tests/test_network.sh`

**Interfaces:**
- Consumes: `custom_load_conf`, `phys_ports`, `port_max_speed`, `pick_2g5_ports`, `custom_log`, `custom_is_provisioned` (Task 2).
- Produces: after it runs, `network.lan.device` holds the LAN L3 device (`br-lan` or the LAN port) — Task 7 and Task 8 read it.

Behaviour: build `<name> <speed>` lines from `phys_ports` + `port_max_speed`, log each; `pick_2g5_ports`.
- Custom mode (`wan lan` picked): delete the `network.@device[i]` whose `name=br-lan`; `network.lan.device=<lan>`, `proto=static`, `ipaddr=$LAN_IP`, `netmask=255.255.255.0`; `network.wan.device=<wan>`, `proto=pppoe`, `username=`, `password=`, `ipv6=1`, `peerdns=0`; `network.wan6.device=@wan`, `proto=dhcpv6`; every other physical port `p` → `network.ll_<p>=interface`, `device=<p>`, `proto=none`. Log `mode=custom wan=<wan> lan=<lan>`.
- Default mode: `network.lan.ipaddr=$LAN_IP`, `netmask=255.255.255.0`, `network.wan.peerdns=0`. Log `mode=default`.
- Both modes: delete `network.lan.ip6assign` and `network.globals.ula_prefix`; `network.wan6.reqaddress=try`, `reqprefix=no`, `peerdns=0`; `uci commit network`.

- [ ] **Step 1: Write `tests/test_network.sh`** with cases (fresh `setup_env` each):
  - A: `eth0` 1g, `eth1` 2g5, `eth2` 2g5, `eth3` 1g → `network.wan.device`=`eth1`, `wan.proto`=`pppoe`, `wan.ipv6`=`1`, `wan.peerdns`=`0`, `wan6.device`=`@wan`, `wan6.reqprefix`=`no`, `lan.device`=`eth2`, `lan.ipaddr`=`10.214.37.1`, no `network.@device[0].name`, `ll_eth0.proto`=`none`, `ll_eth3.device`=`eth3`, no `network.lan.ip6assign`, no `network.globals.ula_prefix`; log contains `mode=custom`.
  - B: one 2g5 + one 1g → `lan.device`=`br-lan`, `wan.proto`=`dhcp`, `lan.ipaddr`=`10.214.37.1`, `wan6.reqprefix`=`no`, no `ll_` keys; log `mode=default`.
  - C: three 2g5 → default mode.
  - D: `eth0` 2g5, `eth1` 10g, `eth2` 2g5 → custom with wan `eth0`, lan `eth2`, `ll_eth1` present.
  - E: two virtio ports → default mode.
  - F: marker present with case-A ports → `$UCI_LOG` empty.
- [ ] **Step 2: Run tests** — expected FAIL on `test_network.sh`.
- [ ] **Step 3: Implement `30-custom-network`.**
- [ ] **Step 4: Run `sh tests/run.sh` and `dash tests/run.sh`** — expected all PASS.

### Task 6: DNS / DHCP (`40-custom-dhcp`)

**Files:**
- Create: `build/files/etc/uci-defaults/40-custom-dhcp`, `tests/test_dhcp.sh`

**Interfaces:**
- Consumes: `custom_load_conf`, `custom_is_provisioned` (Task 2).

Exact writes: `dhcp.@dnsmasq[0].noresolv=1`; delete then add_list `server` `123.123.123.123`, `114.114.114.114`; `cachesize=8000`; `rebind_protection=0`. `dhcp.lan.start=50`, `limit=151`; delete then add_list `dhcp_option` `3,$LAN_IP`, `6,$LAN_IP`; `dhcp.lan.ra=disabled`, `dhcpv6=disabled`, `ndp=disabled`. `dhcp.kexue=tag`, add_list `dhcp.kexue.dhcp_option=3,$LAN_PREFIX.2`. Commit dhcp.

- [ ] **Step 1: Write `tests/test_dhcp.sh`**: assert every value above (servers in order `123.123.123.123 114.114.114.114`, options `3,10.214.37.1 6,10.214.37.1`, kexue `3,10.214.37.2`); `dhcp.@dnsmasq[0].dns_redirect` still `1` and `resolvfile` unchanged; marker case → `$UCI_LOG` empty.
- [ ] **Step 2: Run tests** — expected FAIL.
- [ ] **Step 3: Implement `40-custom-dhcp`.**
- [ ] **Step 4: Run `sh tests/run.sh`** — expected all PASS.

### Task 7: Docker firewall zone and shim (`50-custom-docker`)

**Files:**
- Create: `build/files/etc/uci-defaults/50-custom-docker`, `tests/test_docker_fw.sh`

**Interfaces:**
- Consumes: `custom_load_conf`, `uci_zone_index`, `custom_is_provisioned` (Task 2); `network.lan.device` (Task 5).

Exact writes: `firewall.docker=zone`, `name=docker`, `input=ACCEPT`, `output=ACCEPT`, `forward=ACCEPT`, add_list `device` `docker0` and `br-+`; forwardings `firewall.docker_wan` (src docker, dest wan), `firewall.docker_lan` (src docker, dest lan), `firewall.lan_docker` (src lan, dest docker). `network.macvlan_shim_dev=device`, `type=macvlan`, `name=macvlan-shim`, `ifname=<network.lan.device>`, `mode=bridge`; `network.macvlan_shim=interface`, `device=macvlan-shim`, `proto=static`, `ipaddr=$LAN_IP`, `netmask=255.255.255.255`; `network.macvlan_shim_route=route`, `interface=macvlan_shim`, `target=$LAN_PREFIX.0/28`; add_list `network=macvlan_shim` on `firewall.@zone[<uci_zone_index lan>]`. Commit firewall, network.

- [ ] **Step 1: Write `tests/test_docker_fw.sh`**: default state → shim `ifname`=`br-lan`, route target `10.214.37.0/28`, shim `ipaddr`=`10.214.37.1`, zone devices `docker0 br-+`, the three forwardings, `firewall.@zone[0].network` = `lan macvlan_shim`; with `network.lan.device` preset to `eth2` → shim `ifname`=`eth2`; marker case → `$UCI_LOG` empty.
- [ ] **Step 2: Run tests** — expected FAIL.
- [ ] **Step 3: Implement `50-custom-docker`.**
- [ ] **Step 4: Run `sh tests/run.sh`** — expected all PASS.

### Task 8: Docker, DPanel and macvlan services; LuCI link

**Files:**
- Create: `build/files/etc/init.d/dockerd`, `build/files/etc/init.d/dpanel`, `build/files/etc/init.d/lan-macvlan`, `build/files/usr/libexec/custom/lan-macvlan.sh`, `build/templates/daemon.json.in`, `build/files/usr/share/luci/menu.d/luci-app-dpanel.json`, `build/files/www/luci-static/resources/view/dpanel.js`, `tests/test_services.sh`

**Interfaces:**
- Consumes: `custom_load_conf`, `custom_log` (Task 2); `network.lan.device` (Task 5).
- Produces: `daemon.json.in` with placeholder `@LAN_IP@` (rendered in Task 9); `/etc/custom/build.conf` key `DPANEL_VERSION` (written in Task 9) read by `init.d/dpanel`.

Details:
- `init.d/dockerd`: `USE_PROCD=1`, `START=99`; instance command `/usr/bin/dockerd --config-file=/etc/docker/daemon.json`, `limits nofile="<nr_open> <nr_open>"`, `respawn`, `stderr 1`, `term_timeout 60`.
- `init.d/dpanel`: `START=99`; `mkdir -p /data/dpanel`; command `/usr/bin/dpanel server:start -f /etc/dpanel/config.yaml`; env `APP_NAME=dpanel APP_SERVER_PORT=8086 DP_SYSTEM_STORAGE_LOCAL_PATH=/data/dpanel DP_RUN_IN_CONTAINER=0 DP_LOG_CONSOLE_LEVEL=info APP_VERSION=$DPANEL_VERSION`; `respawn`; `stdout 1`, `stderr 1`.
- `init.d/lan-macvlan`: `START=99`; one instance running `/usr/libexec/custom/lan-macvlan.sh`, no respawn.
- `lan-macvlan.sh`: `custom_load_conf`; `parent=$(uci -q get network.lan.device)`; poll `docker info` every 2 s up to `${DOCKER_WAIT:-120}` s (log + exit 0 on timeout); if `docker network inspect lan_macvlan` succeeds, compare `docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}} {{index .Options "parent"}}' lan_macvlan` with `"$LAN_PREFIX.0/24 $parent"` and on mismatch log a warning containing `lan_macvlan` (never recreate); else run `docker network create -d macvlan --subnet $LAN_PREFIX.0/24 --gateway $LAN_IP --ip-range $LAN_PREFIX.8/29 -o parent=$parent lan_macvlan`.
- `daemon.json.in`: exactly the JSON in spec §9.1 with `"dns": ["@LAN_IP@"]`.
- Menu JSON: key `admin/services/dpanel`, `"title": "DPanel"`, `"order": 90`, `"action": {"type": "view", "path": "dpanel"}`.
- `dpanel.js`: LuCI `view.extend`; `render()` computes `'http://' + window.location.hostname + ':8086/'`, calls `window.location.replace(url)`, returns a paragraph with a plain link to the same URL; `handleSave`, `handleSaveApply`, `handleReset` = `null`.

- [ ] **Step 1: Write `tests/test_services.sh`**: (a) `lan-macvlan.sh` with `DOCKER_NET_EXISTS=0`, `network.lan.device=eth2` → `$DOCKER_LOG` contains `network create -d macvlan --subnet 10.214.37.0/24 --gateway 10.214.37.1 --ip-range 10.214.37.8/29 -o parent=eth2 lan_macvlan`; (b) exists with `DOCKER_NET_DESC='10.214.37.0/24 eth2'` → no `network create`, no warning; (c) exists with `'192.168.1.0/24 br-lan'` → no `network create`, log contains `lan_macvlan`; (d) `DOCKER_INFO_RC=1 DOCKER_WAIT=2` → exits 0, no `network create`, log mentions timeout. (e) `daemon.json.in` with `@LAN_IP@` replaced parses with `jq` (or `python3 -m json.tool`) and has `.["firewall-backend"]=="nftables"`, `.["data-root"]=="/data/docker"`, `.["log-opts"]["max-size"]=="100m"`, `.["log-opts"]["max-file"]=="5"`; menu JSON parses and has `.["admin/services/dpanel"].action.path=="dpanel"`.
- [ ] **Step 2: Run tests** — expected FAIL.
- [ ] **Step 3: Implement the eight files.**
- [ ] **Step 4: Run `sh tests/run.sh`; `sh -n` the three init scripts; `node --check dpanel.js` if node exists** — expected all PASS.

### Task 9: Build pipeline scripts

**Files:**
- Create: `build/packages.txt`, `build/config.override`, `build/validate-inputs.sh`, `build/fetch-extras.sh`, `build/stage.sh`, `build/build.sh`, `tests/test_build.sh`, `tests/fixtures/{docker-index.html,dpanel-config.yaml,manifest-good.txt,manifest-bad.txt}`

**Interfaces:**
- Consumes: Task 8 template; all of `build/files/`.
- Produces (each script sources cleanly with `BUILD_LIB_ONLY=1` so tests can call functions without running `main`):
  - `validate-inputs.sh`: `valid_version <v>`, `valid_lan_ip <ip>` (status only); CLI `validate-inputs.sh <version> <lan_ip>` prints `::error::…` and exits 1 on failure.
  - `fetch-extras.sh <out_dir>`: `latest_docker_version` (stdin HTML → highest `X.Y.Z` among `docker-X.Y.Z.tgz`, numeric sort with `sort -t. -k1,1n -k2,2n -k3,3n`); `download <url> <file>` (`curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 20`); `gh_latest_tag <owner/repo>` (`gh api repos/<r>/releases/latest --jq .tag_name`). Outputs `out/docker/*` (extracted tgz contents), `out/docker-compose`, `out/dpanel`, `out/dpanel-config.yaml`, `out/apk/*.apk`, `out/versions.env` (`DOCKER_VERSION`, `COMPOSE_VERSION`, `DPANEL_VERSION`, `TIMECONTROL_VERSION`).
  - `stage.sh <extras_dir> <lan_ip> <out_files_dir>`: `render_template <in> <out> <lan_ip>` (replace every `@LAN_IP@`); `patch_dpanel_config <file>` (set the `host:` line inside the `prof:` block to `127.0.0.1`, leave `server.http.host` untouched). Copies `build/files`, installs binaries to `usr/bin` (mode 755), compose to `usr/libexec/docker/cli-plugins/docker-compose` + symlink `usr/bin/docker-compose`, writes `etc/custom/build.conf` (`LAN_IP` + all keys of `versions.env`), renders `etc/docker/daemon.json`, writes patched `etc/dpanel/config.yaml`.
  - `build.sh` (run in IB container, cwd `/home/build/immortalwrt`): `apply_config_override <file>` (carry over from `archive/x86-64/build25.sh`); `packages_from_list <file>` (strip comments/blank lines → space-separated); `check_manifest <manifest> <packages_file>` (fail if any of `dropbear dnsmasq iptables-zz-legacy ip6tables-zz-legacy xtables-legacy dockerd docker containerd runc` is a package name in the manifest, or any non-`-` entry of the list is missing; prints each offender); `check_images <dir>` (exactly one `*-squashfs-combined-efi.img.gz`, no `*-combined.img.gz`, no `*.iso`). `main`: apply override, copy `/extra/apk/*.apk` into `packages/`, `make image PROFILE=generic PACKAGES="…" FILES=/staging/files`, then `check_manifest` and `check_images`.
  - `packages.txt` = spec §6 table, grouped with Chinese comments; `config.override` = spec §5 block with Chinese comments (`##` lines).

- [ ] **Step 1: Write fixtures and `tests/test_build.sh`**: `valid_version` accepts `25.12.2`, `25.12.0-rc2`; rejects `25.12`, `v25.12.2`, `25.12.2 `; `valid_lan_ip` accepts `10.214.37.1`, `192.168.1.1`; rejects `10.214.37.2`, `192.168.1.254`, `10.214.37.01`, `256.1.1.1`, `10.214.37.1 `, `10.214.37`; `latest_docker_version < docker-index.html` (contains 29.9.1, 29.10.0, 28.5.2) = `29.10.0`; `packages_from_list` drops comments and keeps `-dropbear`; `check_manifest manifest-good.txt build/packages.txt` passes, `manifest-bad.txt` (has `dropbear` and lacks `ethtool`) fails and prints both names; `render_template` replaces both occurrences in a two-placeholder file; `patch_dpanel_config` on the release `config.yaml` fixture leaves `host: ${APP_SERVER_HOST-0.0.0.0}` and sets the prof host to `127.0.0.1`.
- [ ] **Step 2: Run tests** — expected FAIL.
- [ ] **Step 3: Implement the six build files.**
- [ ] **Step 4: Run `sh tests/run.sh` and `dash tests/run.sh`** — expected all PASS. `bash -n build/*.sh` exits 0.

### Task 10: Workflow and README

**Files:**
- Create: `.github/workflows/build.yml`
- Modify: `README.md` (full rewrite)

**Interfaces:**
- Consumes: every script from Tasks 1–9 with their CLI signatures.

Workflow `Build ImmortalWrt x86-64`, `workflow_dispatch` inputs `version` / `lan_ip` (type string, defaults per Global Constraints), `permissions: contents: write`, `concurrency: build-x86-64-${{ inputs.version }}`. Inputs reach shell only through `env:` (never inline `${{ }}` in `run:`).
- Job `test` (ubuntu-24.04): checkout; `shellcheck -s sh` on `build/files/**` scripts + `tests/**/*.sh`, `shellcheck` on `build/*.sh`; `sh tests/run.sh` (dash, runs the real sfdisk test); `docker run --rm -v "$PWD:/w" -w /w busybox:1.36 sh tests/run.sh`.
- Job `build` (needs test): validate inputs; `build/fetch-extras.sh "$RUNNER_TEMP/extras"` with `GH_TOKEN`; `build/stage.sh "$RUNNER_TEMP/extras" "$LAN_IP" "$RUNNER_TEMP/files"`; IB `docker run --rm --user root` mounting `bin/`, `$RUNNER_TEMP/files:/staging/files`, `$RUNNER_TEMP/extras/apk:/extra/apk`, `build/build.sh`, `build/config.override`, `build/packages.txt`; `sudo apt-get install -y` nothing extra (util-linux present) then `build/smoke-datadisk.sh bin/targets/x86/64/*-squashfs-combined-efi.img.gz`; `sha256sum` → `sha256sums.txt`; release notes (LAN address, address plan table, DPanel URL `http://<lan_ip>:8086`, component versions from `versions.env`, package list in `<details>`); `gh release delete x86-64-$VERSION --cleanup-tag --yes || true` then `gh release create` with the img.gz and `sha256sums.txt`.
README (Chinese): what it builds, inputs, first-boot behaviour (two modes), address plan, how to fill PPPoE, DPanel/menu link, where to look (`logread -e custom-init`), how to customise (packages.txt, config.override, files/), known limits (PD-only ISP, no LAN IPv6, Docker upgrades by rebuilding).

- [ ] **Step 1: Write `build.yml` and `README.md`.**
- [ ] **Step 2: Validate** — `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/build.yml'))"` (or `ruby -ryaml`) succeeds; `actionlint` passes if available; grep confirms no `${{ inputs.` inside any `run:` block.

### Task 11: Final verification

- [ ] **Step 1: Run `sh tests/run.sh` and `dash tests/run.sh`** — all PASS (datadisk SKIP on macOS).
- [ ] **Step 2: Run `shellcheck`** (if installable locally) on every script — no findings.
- [ ] **Step 3: Self-review against the spec** section by section; fix gaps.
- [ ] **Step 4: Report** what was verified locally, what only CI can verify (IB build, real sfdisk smoke test, busybox run), and what only hardware can verify (PPPoE, macvlan/shim, DPanel); leave commit/push to the user.
