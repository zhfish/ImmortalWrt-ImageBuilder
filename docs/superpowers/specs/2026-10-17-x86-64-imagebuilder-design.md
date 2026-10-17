# x86-64 ImmortalWrt ImageBuilder Action 设计

日期：2026-10-17
状态：已确认设计，待评审 spec

## 1. 目标

用 GitHub Actions + ImmortalWrt 官方 ImageBuilder，打包一个面向 x86-64 软路由的 UEFI 固件：
nftables-only、集成最新 Docker + DPanel、首次启动自动完成数据盘、网口、DNS/DHCP、Docker macvlan 的配置。

仓库中现有内容只作归档和参考，新方案以最佳实践为准，不受旧代码约束。

### 成功标准

- Actions 页面只需填 2 个参数即可产出固件并发布 Release。
- 刷入后首次启动无需手动干预：`/data` 已挂载、Docker 与 DPanel 已运行、macvlan 网络与 shim 已就绪。
- 在“恰好 2 个 2.5G 网口”的机器上自动进入接口定制模式；其他机器保持官方默认网口布局。
- 固件中不含 dropbear、iptables-legacy / xtables-legacy；构建时自动校验。

## 2. Action 输入

| 输入 | 默认值 | 校验 |
| --- | --- | --- |
| `version` 版本号 | `25.12.2` | `^[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$`，且对应的 `immortalwrt/imagebuilder:x86-64-openwrt-<version>` 镜像存在 |
| `lan_ip` LAN 地址 | `10.214.37.1` | 必须为 `x.x.x.1`，各段 ≤ 255；掩码固定 /24 |

下文以 `P` 表示 LAN 前缀（例：`10.214.37`），`P.1` 即 LAN 地址。

## 3. 仓库结构

```
.github/workflows/build.yml        新 Action（lint/test → 构建 → 校验 → 发布）
.github/workflows/clean-workflow.yml  保留
build/
  build.sh                         在 ImageBuilder 容器内执行
  fetch-extras.sh                  在 Runner 上下载第三方二进制与 apk
  packages.txt                     软件包清单（一行一个，# 注释）
  config.override                  镜像配置覆盖片段
  files/                           固件根目录覆盖层
tests/                             纯函数单元测试（模拟 ethtool 输出等）
archive/                           旧的 workflow、脚本、配置（仅供参考，不参与构建）
docs/superpowers/specs/            本文档
README.md                          重写
```

## 4. 构建流程

1. **lint & test**：`shellcheck` 所有脚本，运行 `tests/`。
2. **fetch-extras.sh**（Runner 上执行，使用 `GITHUB_TOKEN` 避免 API 限流）下载到暂存目录：
   - Docker 静态包：从 `https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/static/stable/x86_64/` 取最高版本 `docker-X.Y.Z.tgz`；TUNA 失败时回退 `https://download.docker.com/linux/static/stable/x86_64/`。
   - Docker Compose：GitHub `docker/compose` 最新 Release 的 `docker-compose-linux-x86_64`。
   - DPanel：GitHub `donknap/dpanel` 最新 Release 的 `dpanel-ce-musl-amd64` 与 `config.yaml`。
   - timecontrol：GitHub `sirpdboy/luci-app-timecontrol` 最新 Release 的 `SNAPSHOT-x86_64.tar.gz`（apk v3），解出 `luci-app-timecontrol` 与 `luci-i18n-timecontrol-zh-cn`。
   - 记录各组件版本，供 Release 说明使用。
3. **组装覆盖层**：复制 `build/files/` 到暂存目录，加入上述二进制，渲染 `/etc/custom/build.conf`（`LAN_IP`、构建版本信息）与 `/etc/docker/daemon.json`（填入 LAN IP）。
4. **ImageBuilder**：`docker run immortalwrt/imagebuilder:x86-64-openwrt-<version>`，挂载暂存覆盖层、本地 apk 目录（timecontrol）、`build.sh`、`config.override`、`packages.txt`。构建时软件包从官方 `downloads.immortalwrt.org` 下载（Runner 在海外）。
5. **校验**（`build.sh` 末尾，失败即中止）：
   - manifest 不含 `dropbear`、`iptables-zz-legacy`、`ip6tables-zz-legacy`、`xtables-legacy`、`dockerd`（官方包）。
   - manifest 包含 `packages.txt` 中所有显式要求的包。
   - 只产出 `*-squashfs-combined-efi.img.gz`。
6. **发布**：删除旧的同名 Release 与 tag 后重建，tag 为 `x86-64-<version>`；附件为 img.gz 与 `sha256sums.txt`；说明中写明 LAN 地址、地址规划、组件版本、软件包列表。

## 5. 镜像配置（config.override）

```
CONFIG_TARGET_ROOTFS_SQUASHFS=y
# CONFIG_TARGET_ROOTFS_EXT4FS is not set
# CONFIG_TARGET_ROOTFS_TARGZ is not set
# CONFIG_GRUB_IMAGES is not set
CONFIG_GRUB_EFI_IMAGES=y
CONFIG_GRUB_TIMEOUT="3"
# CONFIG_ISO_IMAGES is not set
# CONFIG_QCOW2_IMAGES / VDI / VMDK / VHDX is not set
CONFIG_TARGET_IMAGES_GZIP=y
CONFIG_TARGET_ROOTFS_PARTSIZE=4096
```

combined-efi 镜像为 GPT + BIOS boot 分区，UEFI 与传统 BIOS 均可启动。

## 6. 软件包（packages.txt）

| 类别 | 包 |
| --- | --- |
| 移除 | `-dropbear -dnsmasq` |
| 基础 | `curl openssh-server openssh-sftp-server luci-i18n-firewall-zh-cn luci-i18n-package-manager-zh-cn luci-i18n-diskman-zh-cn luci-i18n-filemanager-zh-cn luci-i18n-ttyd-zh-cn luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn firewall4 nftables-json dnsmasq-full default-settings-chn luci-i18n-base-zh-cn ca-bundle` |
| iptables 兼容层 | `iptables-nft ip6tables-nft` |
| kmod | `kmod-tcp-bbr kmod-nft-offload kmod-nf-flow kmod-macvlan kmod-veth kmod-nf-conntrack-netlink kmod-fs-ext4` |
| 磁盘 / 网口工具 | `sfdisk partx-utils e2fsprogs block-mount ethtool` |
| 进阶 | `luci-i18n-irqbalance-zh-cn luci-i18n-vnstat2-zh-cn luci-i18n-lldpd-zh-cn luci-i18n-pbr-zh-cn miniupnpd-nftables luci-i18n-upnp-zh-cn luci-i18n-wol-zh-cn luci-i18n-nut-zh-cn nut-driver-usbhid-ups` |
| 进阶（GitHub） | `luci-app-timecontrol luci-i18n-timecontrol-zh-cn`（sirpdboy，nftables 版，本地 apk） |
| VPN | `luci-proto-wireguard`；`luci-app-softether luci-i18n-softether-zh-cn`（仅依赖 `softethervpn5-client`）；`openvpn-openssl luci-i18n-openvpn-zh-cn` |

说明：
- 不使用 `luci-app-softethervpn`：它强制依赖 server + bridge + client。
- OpenVPN 的 client/server 是同一个程序，无法拆分；不安装 `luci-app-openvpn-server`。
- `luci-app-nut` 本身不带驱动，加装覆盖绝大多数 USB UPS 的 `nut-driver-usbhid-ups`；其他驱动可后续用 apk 安装。
- Docker 不使用官方 `dockerd`/`docker`/`containerd`/`runc` 包，见第 9 节。

## 7. 首次启动脚本（/etc/uci-defaults）

公共函数库 `/usr/lib/custom/lib.sh`：读取 `/etc/custom/build.conf`、日志（`logger -t custom-init`）、判断是否已初始化、计算 LAN 前缀、网口识别等纯函数（可在 `tests/` 中单测）。

### 7.1 执行顺序与“只初始化一次”

| 脚本 | 何时执行 | 内容 |
| --- | --- | --- |
| `15-custom-data-disk` | 每次（幂等） | 数据盘，见 7.2（排在 fstools 的 `10-fstab` 之后） |
| `20-custom-system` | 仅未初始化时 | 主题、apk 镜像、sshd、UPnP、流量卸载 |
| `30-custom-network` | 仅未初始化时 | 网口模式、LAN/WAN、IPv6 |
| `40-custom-dhcp` | 仅未初始化时 | DNS / DHCP / kexue |
| `50-custom-docker` | 仅未初始化时 | Docker 防火墙区域、shim |
| `90-custom-done` | 每次 | 写入标记 `/etc/custom-provisioned` |

- 标记文件与 `/etc/docker/daemon.json` 通过 `/lib/upgrade/keep.d/custom` 加入 sysupgrade 保留列表：保留配置升级后不会重复初始化（不会覆盖已填写的 PPPoE 账号等）；恢复出厂设置后会重新初始化。
- 我们的脚本编号 < 99，先于 ImmortalWrt 自带的 `99-default-settings*` 执行。

### 7.2 数据盘 → /data

1. fstab 中已有 `/data` 挂载项：跳过（由 `block mount` 负责）。
2. 启动盘上已有 `LABEL=data` 的分区：只添加 fstab 并挂载。
3. 否则检查启动盘末尾的未分配空间，≥ 1 GiB 时：
   - `sfdisk --relocate gpt-bak-std` 把 GPT 备份头移到磁盘末尾；
   - `sfdisk --append --no-reread` 新建 Linux 分区占满剩余空间；
   - `partx --add` 通知内核（磁盘正在使用，不能整表重读）；
   - 新分区上**已有文件系统**（例如重刷固件后分区表被覆盖、数据仍在）则不格式化，否则 `mkfs.ext4 -L data`。
4. 通过 uci fstab 按 UUID 挂载到 `/data`，立即 `block mount`；创建 `/data/docker`、`/data/dpanel`。
5. 不足 1 GiB：只创建 `/data` 目录并记录日志（Docker 数据会落在 rootfs 上）。

启动盘通过 `/lib/upgrade/common.sh` 的 `export_bootdevice` / `export_partdevice` 确定；分区设备名按 `sdX3` / `nvme0n1p3` / `mmcblk0p3` 规则推导。

### 7.3 系统设置（20-custom-system）

- 主题：`luci.main.mediaurlbase=/luci-static/argon`。
- apk 镜像：设置 `system.@imm_init[0].apk_mirror=https://mirrors.cernet.edu.cn/immortalwrt`，由 ImmortalWrt 自带的 `99-default-settings-chinese` 写入 `distfeeds.list`（该机制在 sysupgrade 后也会自动重新应用）。
- sshd：`PermitRootLogin yes`（需先在 LuCI 设置 root 密码；空密码仍被拒绝）。
- UPnP：`upnpd.config.enabled=0`（服务保持 enable，在 LuCI 勾选即可启用）。
- 流量卸载：`firewall.@defaults[0].flow_offloading=0`、`flow_offloading_hw=0`（kmod 已装但不启用）。

### 7.4 sysctl（/etc/sysctl.d/90-router.conf，随固件提供）

- 拥塞控制：`net.ipv4.tcp_congestion_control=bbr`，队列规则保持 `fq_codel`。BBR 只影响路由器本机收发的 TCP（含容器），不影响转发流量。
- 连接跟踪：`nf_conntrack_max=262144`。
- 收包与缓冲：`netdev_max_backlog`、`netdev_budget`、`rmem_max`/`wmem_max`、`tcp_rmem`/`tcp_wmem` 适度调大。
- TCP：`tcp_fastopen=3`、`tcp_mtu_probing=1`（PPPoE 下避免 MTU 黑洞）、`tcp_slow_start_after_idle=0`。
- 邻居表：`gc_thresh1/2/3` 调大。
- `fs.inotify.max_user_watches` / `max_user_instances` 调大（容器需要）。
- shim 设备：`net.ipv4.conf.macvlan-shim.arp_filter=1`（设备创建时由 `/etc/hotplug.d/net/00-sysctl` 应用）。
- **不修改** `arp_ignore`（官方默认 1）与 `rp_filter`。

### 7.5 网口模式（30-custom-network）

**网口识别**：遍历 `/sys/class/net/*`，只取物理以太网口（存在 `device`、`type=1`、非无线）。用 `ethtool` 解析 `Supported link modes`，取最高速率；**最高速率恰好 2500 Mb/s** 才算 2.5G 口（10G 口不算，1G 口忽略）。按 ethN 编号排序。

**接口定制模式**（恰好 2 个 2.5G 口）：
- 第 1 个 2.5G 口 → `wan`：`proto=pppoe`，用户名密码留空（LuCI 中填写），`ipv6=1`，`peerdns=0`。
- `wan6`：`proto=dhcpv6`，`device=@wan`，`reqaddress=try`，`reqprefix=no`，`peerdns=0`。
- 第 2 个 2.5G 口 → `lan`：直接作为设备，删除 `br-lan` 网桥；`P.1/24`。
- 其余物理网口：各建一个 `proto=none` 接口（链路 up，只有内核自动生成的 IPv6 link-local），不加入任何防火墙区域（fw4 默认 input REJECT）。

**默认模式**（其他情况）：保持官方布局（eth0 在 br-lan 作 LAN，eth1 作 WAN DHCP），只修改：
- `lan` 地址 `P.1/24`；`wan.peerdns=0`；`wan6.reqprefix=no`、`peerdns=0`。

**IPv6（两种模式相同）**：只有路由器 WAN 侧获取 v6 地址；局域网不使用 v6：
- 删除 `network.lan.ip6assign`、`network.globals.ula_prefix`；
- `dhcp.lan.ra=disabled`、`dhcpv6=disabled`、`ndp=disabled`。

已知限制：若运营商只下发前缀（PD）而不给 WAN 地址（无 IA_NA 也无 SLAAC），路由器本身也拿不到公网 v6。

### 7.6 DNS / DHCP（40-custom-dhcp，两种模式都生效）

- dnsmasq：`noresolv=1`，`server=123.123.123.123`、`server=114.114.114.114`；`cachesize=8000`（ImmortalWrt 默认值，显式写出）；`rebind_protection=0`。其余（含 `dns_redirect`）保持 ImmortalWrt 默认。
- `dhcp.lan`：`start=50`、`limit=151`（P.50–P.200），`dhcp_option=3,P.1`、`dhcp_option=6,P.1`。
- 标签 `kexue`：`config tag 'kexue'`，`dhcp_option=3,P.2`。客户端在 LuCI 静态地址分配中选择标签 `kexue` 即使用 P.2 作为网关（DNS 仍为 P.1）。主机标签选项优先于接口选项，P.2 生效。

## 8. 地址规划

| 地址 | 用途 |
| --- | --- |
| P.1 | 路由器（LAN 口 + shim /32） |
| P.2–P.7 | 固定 IP 容器（`--ip` 指定；P.2 = kexue 网关容器） |
| P.8–P.15 | macvlan 自动分配（`--ip-range P.8/29`，8 个） |
| P.16–P.49 | 有线设备静态 IP |
| P.50–P.200 | DHCP 地址池 |
| P.201–P.254 | 有线设备静态 IP |

Docker 无法关闭网络内的自动分配，只能用 `--ip-range` 限定范围；需要固定地址的容器使用 `--ip`。

## 9. Docker / DPanel / macvlan

### 9.1 Docker（静态二进制）

- `/usr/bin/`：`dockerd docker containerd containerd-shim-runc-v2 ctr runc docker-init docker-proxy`（来自 TUNA 静态包）。
- `/usr/libexec/docker/cli-plugins/docker-compose`，并软链 `/usr/bin/docker-compose`。
- `/etc/init.d/dockerd`：procd 服务，`START=99`，`dockerd --config-file=/etc/docker/daemon.json`，`nofile` 取 `fs.nr_open`，异常退出自动重启。
- `/etc/docker/daemon.json`（构建时渲染）：

```json
{
  "data-root": "/data/docker",
  "firewall-backend": "nftables",
  "log-level": "warn",
  "log-driver": "json-file",
  "log-opts": { "max-size": "100m", "max-file": "5" },
  "dns": ["P.1"]
}
```

日志上限：每个容器 100M × 5 = 500M。容器 DNS 指向路由器 dnsmasq（避免 Docker 回退到 8.8.8.8）。修改 LAN 地址后需同步修改此处。

升级方式：重新构建固件；`apk upgrade` 不会改动 Docker。

### 9.2 防火墙（50-custom-docker）

- 新建区域 `docker`：`device=docker0`、`device=br-+`（Compose / DPanel 创建的网桥），input/output/forward 均 ACCEPT。
- 转发：`docker→wan`、`docker→lan`、`lan→docker`。**不放行 wan→docker**，公网访问容器需手动加规则。
- 默认模式下 `br-+` 也会匹配到 `br-lan`：fw4 按区域顺序先匹配 lan 区域，且 docker 区域的权限是 lan 区域的子集，因此不会扩大 LAN 的权限；为两种模式行为一致，显式允许 `docker→lan`。

### 9.3 macvlan 网络与 shim

**shim**（netifd 管理，开机自动建立）：
- 设备 `macvlan-shim`：`type=macvlan`，父接口为 LAN 的 L3 设备（定制模式下为 LAN 网口，默认模式下为 `br-lan`），`mode=bridge`。
- 接口 `macvlan_shim`：`proto=static`，`P.1/32`，加入 lan 防火墙区域。
- 路由：`P.0/28` 经 `macvlan_shim`。
- `dhcp.macvlan_shim` 设 `ignore=1`：shim 持有 LAN 地址，dnsmasq 否则会在 shim 上重复应答 DHCP。

shim 使用 `P.1/32` 的原因：官方默认 `arp_ignore=1`，只回应目标地址配置在收包接口上的 ARP。macvlan 容器发出的 ARP 只能到达 shim（到不了父接口），所以 shim 必须持有网关地址 P.1，容器才能通过 P.1 上网。shim 上开启 `arp_filter=1`，只回应路由经 shim 的请求方（即容器），避免局域网设备看到 P.1 的 MAC 地址来回变化。

**Docker 网络** `lan_macvlan`：由 `/etc/init.d/lan-macvlan`（procd 一次性任务，`START=99`）在 Docker 就绪后创建：

```
docker network create -d macvlan \
  --subnet P.0/24 --gateway P.1 --ip-range P.8/29 \
  -o parent=<LAN L3 设备> lan_macvlan
```

- 等待 Docker 最多 120 秒；网络已存在则跳过；若已存在的网络子网或父接口与当前 LAN 不一致，只记录警告，不自动重建（可能有容器在用）。

### 9.4 DPanel

- `/usr/bin/dpanel`（`dpanel-ce-musl-amd64`），`/etc/dpanel/config.yaml`（取自同一 Release，`prof.host` 改为 `127.0.0.1`）。
- `/etc/init.d/dpanel`：procd，`START=99`（排在 dockerd 之后），自动重启。环境变量：`APP_NAME=dpanel`、`APP_SERVER_PORT=8086`、`DP_SYSTEM_STORAGE_LOCAL_PATH=/data/dpanel`、`DP_RUN_IN_CONTAINER=0`。
- 访问 `http://P.1:8086`，LAN 可访问，WAN 被 fw4 默认策略拦截。

### 9.5 LuCI 菜单入口

- `/usr/share/luci/menu.d/luci-app-dpanel.json`：在“服务”菜单下增加 “DPanel” 项，指向视图 `dpanel`。
- `/www/luci-static/resources/view/dpanel.js`：打开后立即用 `location.replace('http://' + location.hostname + ':8086/')` 在当前标签页跳转到 DPanel。
  - 地址取当前访问 LuCI 用的主机名或 IP，改了 LAN 地址或用域名访问时也能用。
  - 用 `replace` 而不是普通跳转：在 DPanel 页面按“后退”会回到上一个 LuCI 页面，不会再次被跳转。
  - 页面上同时显示一个普通链接，脚本跳转失败时可手动点击。

## 10. 错误处理与日志

- 所有首次启动脚本通过 `logger -t custom-init` 记录每个决策（识别到的网口及速率、选择的模式、分区结果），用 `logread -e custom-init` 查看。
- 数据盘任一步骤失败：记录错误，不中断其余初始化；Docker 仍可启动（数据落在 rootfs）。
- 网口识别失败（如缺 ethtool 输出）：按默认模式处理。
- 构建侧：下载失败、版本解析失败、manifest 校验失败都直接让 workflow 失败，并给出明确的 `::error::` 信息。

## 11. 测试

- 本地 / CI：
  - `shellcheck` 所有 shell 脚本；`sh -n` 语法检查。
  - `actionlint` 检查 workflow（本地有则跑）。
  - `tests/`：用模拟的 ethtool 输出与 sysfs 目录，测试最高速率解析、2.5G 网口选择（0/1/2/3 个 2.5G、混合 1G/10G）、LAN 前缀与地址计算。
- 构建：第 4 节第 5 步的 manifest 与产物校验。
- 无法在本地验证：真机首次启动（分区、PPPoE、macvlan、shim）。由用户刷机后通过 `logread -e custom-init`、`docker network ls`、`ip route` 确认。

## 12. 不做的事

- 不生成 ISO、纯 BIOS 镜像、虚拟机磁盘格式、ext4 rootfs。
- 不集成 iStore、代理插件等其他第三方软件。
- 局域网不启用 IPv6；Docker 不启用 IPv6。
- 不提供 PPPoE 账号等敏感信息的 workflow 输入。
