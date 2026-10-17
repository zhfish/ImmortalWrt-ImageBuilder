# ImmortalWrt-ImageBuilder（x86-64 软路由）

用 GitHub Actions 和 ImmortalWrt 官方 ImageBuilder 打包一个 **x86-64 UEFI** 固件：只用 nftables，集成最新 Docker 与 DPanel，首次启动自动完成数据盘、网口、DNS/DHCP、Docker macvlan 的配置。不从源码编译，几分钟出一个固件。

> 与 ImmortalWrt 官方无关，自定义固件的问题请不要去官方渠道反馈。
> 旧版本的工作流与脚本保存在 [archive/](archive/)，只作参考，不参与构建。

## 使用方法

1. Fork 本仓库。
2. 打开 **Actions → Build ImmortalWrt x86-64 → Run workflow**，填写参数后运行。
3. 构建完成后到 **Releases** 下载，每个版本一个 Release（如 `x86-64-25.12.2`），只保留最新一次构建。

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| 版本号 | `25.12.2` | 需要有对应的 `immortalwrt/imagebuilder:x86-64-openwrt-<版本>` 镜像 |
| LAN 地址 | `10.214.37.1` | 必须是 `x.x.x.1`，掩码 /24 |
| 使用定制网口配置 | 勾选 | WAN 用 PPPoE、LAN 直连网口，见下文；做虚拟机测试时建议取消勾选 |

产物只有一个 `*-squashfs-combined-efi.img.gz`：写入硬盘或导入虚拟机，UEFI 和传统 BIOS 都能启动。GRUB 菜单等待 3 秒，根分区 4 GiB。

## 固件内容

- **防火墙只用 nftables**：firewall4、dnsmasq-full；需要 `iptables` 命令的程序走 `iptables-nft` 兼容层，不含 legacy 版本。
- **SSH 用 OpenSSH**（去掉了 dropbear），允许 root 用密码登录：先在“系统 → 管理权”设置 root 密码。
- **默认主题 argon**；apk 软件源为 `https://mirrors.cernet.edu.cn/immortalwrt`。
- **BBR** 已开启（影响路由器本机和容器的 TCP），sysctl 按路由器场景调整，见 [90-router.conf](build/files/etc/sysctl.d/90-router.conf)。流量卸载模块已装但默认关闭；UPnP 已装但默认关闭。
- **插件**：irqbalance、vnstat2、lldpd、pbr、UPnP、网络唤醒、NUT（UPS，含通用 USB 驱动）、timecontrol（上网时间控制）、磁盘管理、文件管理、网页终端，均为中文界面。
- **VPN（客户端为主）**：WireGuard、SoftEther 客户端、OpenVPN。
- **Docker**：清华 TUNA 镜像上的最新官方静态版本（构建时获取），加 Docker Compose 插件；使用 nftables 防火墙后端，日志为 json-file、每个容器最多 500M（100M × 5），数据在 `/data/docker`。
- **DPanel**：最新社区版，开机自启，`http://<LAN 地址>:8086`，LuCI 菜单“服务 → DPanel”可直接跳转。数据在 `/data/dpanel`。

## 首次启动做了什么

首次启动的设置都写在 `/etc/uci-defaults/` 下的脚本里，用 `logread -e custom-init` 查看每一步的结果。

### 数据盘 `/data`

硬盘比固件大（剩余 ≥ 1 GiB）时，剩余空间自动做成 ext4 分区挂载到 `/data`。重刷固件后如果那块空间里已有文件系统，不会重新格式化。

### 网口

- **勾选了“使用定制网口配置”**（默认）且至少有 2 个网口时，进入接口定制模式：
  - 选网口：恰好有 2 个 2.5G 网口（按最高速率判断，1G、10G 口不算）时用这两个，否则按顺序用 eth0、eth1；
  - 前一个是 **WAN**，PPPoE 拨号：到“网络 → 接口 → wan”填写账号密码；
  - 后一个直接作为 **LAN**（没有 br-lan 网桥）；
  - 其余网口只启用链路，不分配地址、不加入防火墙区域。
- **没有勾选**，或机器只有 1 个网口：保持官方布局，eth0 在 br-lan 里作 LAN，eth1 作 WAN（DHCP）。
- 虚拟机的网卡也会按 eth0=WAN、eth1=LAN 进入定制模式；在虚拟机里测试时建议取消勾选。
- **IPv6**：只有路由器 WAN 侧获取一个 IPv6 地址；局域网不分配 IPv6（不发 RA，不开 DHCPv6）。

### DNS 与 DHCP

- 上游 DNS 只用 `123.123.123.123` 和 `114.114.114.114`（不用运营商下发的 DNS），开启缓存，关闭重绑定保护。
- DHCP 地址池 `.50`–`.200`，网关与 DNS 都是路由器。
- **kexue 标签**：在“网络 → DHCP/DNS → 静态地址分配”中给设备选择标签 `kexue`，它拿到的网关就是 `x.x.x.2`（DNS 仍是路由器）。

### 地址规划（以 10.214.37.1 为例）

| 地址 | 用途 |
| --- | --- |
| 10.214.37.1 | 路由器 |
| 10.214.37.2 – .7 | 固定 IP 的 macvlan 容器，用 `--ip` 指定（.2 是 kexue 网关） |
| 10.214.37.8 – .15 | macvlan 容器自动分配 |
| 10.214.37.16 – .49 | 有线设备静态 IP |
| 10.214.37.50 – .200 | DHCP 地址池 |
| 10.214.37.201 – .254 | 有线设备静态 IP |

### Docker 网络与防火墙

- macvlan 网络 `lan_macvlan`：子网为 LAN 网段，网关为 LAN 地址，开机后自动创建。容器直接出现在局域网里：

  ```bash
  docker run -d --network lan_macvlan --ip 10.214.37.2 <镜像>
  ```

  Docker 无法关闭网络内的自动分配，所以自动分配被限制在 `.8`–`.15`；需要固定地址的容器用 `--ip`。
- **shim 接口** `macvlan_shim`（加入 lan 防火墙区域）让路由器与 macvlan 容器互通，`x.x.x.0/28` 的路由走它。
- 防火墙区域 `docker` 包含 `docker0` 与 Compose/DPanel 创建的 `br-xxxx` 网桥：允许容器访问外网和局域网、局域网访问容器；**公网不能直接访问容器**，需要时自己加端口转发规则。

### 升级

保留配置升级（sysupgrade）后，网口、DNS/DHCP、防火墙等设置不会被重新初始化，你填写的 PPPoE 账号等都会保留；恢复出厂设置后会按上面的规则重新初始化。Docker 和 DPanel 随固件升级：重新构建固件即可，`apk upgrade` 不会改动它们。

## 自定义

| 想改什么 | 改哪里 |
| --- | --- |
| 软件包 | [build/packages.txt](build/packages.txt) |
| 镜像格式、GRUB、分区大小 | [build/config.override](build/config.override) |
| 首次启动的设置 | [build/files/etc/uci-defaults/](build/files/etc/uci-defaults/) |
| Docker 配置 | [build/templates/daemon.json.in](build/templates/daemon.json.in)（`@LAN_IP@` 在构建时替换；固件内为 `/etc/docker/daemon.json`） |
| 往固件里放任意文件 | 放到 `build/files/` 下对应的路径 |

修改脚本后在本机运行测试（需要 POSIX sh；有 `sfdisk` 时会真实演练数据分区）：

```bash
sh tests/run.sh
```

## 已知限制

- 运营商只下发前缀（PD）、不给 WAN 地址时，路由器本身拿不到公网 IPv6。
- 修改 LAN 地址后，需要同步修改 `/etc/docker/daemon.json` 的 `dns`，并删除重建 `lan_macvlan` 网络（`docker network rm lan_macvlan && /etc/init.d/lan-macvlan restart`）。`daemon.json` 在保留配置升级时会保留。
- 修改 [config.override](build/config.override) 的根分区大小后重刷，硬盘分区布局会改变，`/data` 会在新位置重新建立，**原有数据会丢失**，请先备份。
- Docker 使用官方静态二进制，**不要再安装** `dockerd`、`docker` 或依赖它们的 `luci-app-dockerman`，否则会与固件里的 Docker 冲突。容器管理请用 DPanel。
