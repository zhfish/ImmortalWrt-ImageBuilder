#!/bin/bash
# =====================================================================
#  可选软件包清单（x86-64 / ImmortalWrt 25.12.x / apk）
# =====================================================================
#  用法：去掉某一行开头的 "#"，就会把该行的包集成进固件。
#        本文件只是在拼接 CUSTOM_PACKAGES 字符串，最终交给 x86-64/build25.sh。
#
#  来源标记：
#    【官方】   ImmortalWrt 25.12 官方软件源
#    【第三方】 仅在 github.com/wukongdaily/apk 仓库提供
#               （只要启用了任意一个自定义包，构建时就会拉取这个仓库）
#    【GitHub】 构建时直接从项目的 GitHub Release 下载
#
#  注意：
#  - 已默认集成、不用在这里开启的包（见 build25.sh）：
#      argon 主题、diskman 磁盘管理、filemanager 文件管理、ttyd 网页终端、
#      package-manager 软件包管理、firewall 防火墙、openssh-sftp-server、curl、
#      Docker（dockerman）、nftables 防火墙栈（firewall4 / dnsmasq-full / 流量卸载）
#  - 本固件只用 nftables：标注【依赖 iptables】的包会带进 iptables、ipset 等旧组件，
#    请不要开启。（例外是 Docker：它硬性依赖 iptables-nft，但已改用 nftables 后端）
#  - iStore 商店（luci-app-store）由工作流里的“集成 iStore 商店”勾选项控制。
#  - 官方 x86 默认软件包里没有无线网卡、蓝牙和声卡驱动；
#    但如果开启的包依赖这些驱动，它们会被一并装上。
#  - 第三方仓库里的 argon、passwall、daed、rtp2httpd 等版本可能比官方新，
#    启用任意自定义包后，通常会优先使用第三方仓库里的新版本。
#  - 包名前加 "-" 表示从默认包里去掉该包，例如 "-luci-app-argon-config"。
# =====================================================================

CUSTOM_PACKAGES="${CUSTOM_PACKAGES:-}"

# ==================== 首页与软件安装 ====================
# 【第三方】iStore 首页和网络向导（依赖 iStore，开启后会一并集成商店）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-quickstart-zh-cn"
# 【第三方】Run 安装器：在网页上安装 makeself 打包的 .run 插件（与 quickfile 的 nginx 配置冲突，二选一）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-run"

# ==================== 主题 ====================
# 【第三方】Aurora 极光主题及其设置页 by eamonxg
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-aurora luci-app-aurora-config luci-i18n-aurora-config-zh-cn"

# ==================== 系统管理 ====================
# 【第三方】分区扩容：把硬盘剩余空间扩展给 overlay 或挂载为数据分区 by sirpdboy
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-partexp luci-i18n-partexp-zh-cn"
# 【第三方】任务设置：定时重启、定时执行脚本等 by sirpdboy
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-taskplan luci-i18n-taskplan-zh-cn"
# 【官方】定时重启
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-autoreboot-zh-cn"
# 【官方】网络看门狗：断网时自动重启接口或整机
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-watchcat-zh-cn"
# 【官方】自定义命令：把常用 shell 命令做成网页按钮
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-commands-zh-cn"
# 【官方】账户管理：创建多个 LuCI 登录账户并分配权限
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-acl-zh-cn"
# 【官方】在线升级（Attended Sysupgrade），依赖官方在线编译服务，固件里有第三方包时通常无法使用
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-attendedsysupgrade-zh-cn"
# 【官方】中断均衡：把网卡中断分摊到多个 CPU 核心，提升多核软路由的转发性能
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-irqbalance-zh-cn"
# 【官方】CPU 占用限制：限制指定进程的 CPU 使用率
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-cpulimit-zh-cn"
# 【官方】一键释放内存
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-ramfree-zh-cn"
# 【官方】LXC 容器管理
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-lxc-zh-cn"
# 【官方】uHTTPd Web 服务器设置
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-uhttpd-zh-cn"
# 【官方】xinetd 超级服务器设置
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-xinetd-zh-cn"

# ==================== 状态监控与统计 ====================
# 【第三方】Bandix 流量监控：按设备实时显示上下行流量 by timsaya
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES bandix luci-app-bandix luci-i18n-bandix-zh-cn"
# 【官方】带宽统计（nlbwmon）：按设备、按协议统计流量
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-nlbwmon-zh-cn"
# 【官方】vnStat 2 流量统计：按接口统计日、月流量
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-vnstat2-zh-cn"
# 【官方】系统统计图表（collectd）：CPU、内存、流量等历史曲线
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-statistics-zh-cn"
# 【官方】Netdata 实时性能监控面板
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-netdata-zh-cn"
# 【官方】LuCI 仪表盘首页（dashboard 风格的状态总览）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-dashboard-zh-cn"
# 【官方】微信推送：设备上下线、WAN IP 变化等事件推送到微信
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-wechatpush-zh-cn"
#  【官方】SNMP 服务：供外部网管系统采集路由器数据
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-snmpd-zh-cn"
# 【官方】LLDP 链路层发现：让交换机等设备识别本机
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-lldpd-zh-cn"

# ==================== 路由、多拨与 QoS ====================
# 【官方】【依赖 iptables】MWAN3 多 WAN 负载均衡与故障切换（依赖 ipset、iptables）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-mwan3-zh-cn"
# 【官方】策略路由（PBR）：按源/目标地址、域名选择出口
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-pbr-zh-cn"
# 【官方】【依赖 iptables】SQM 智能队列管理：降低满载时的延迟（游戏、视频通话）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-sqm-zh-cn"
# 【官方】【依赖 iptables】QoS 流量控制（传统规则式）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-qos-zh-cn"
# 【官方】Easy QoS：按 IP 限速
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-eqos-zh-cn"
# 【官方】UPnP / NAT-PMP：让游戏机、BT 等设备自动映射端口（明确指定 nftables 版 miniupnpd）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES miniupnpd-nftables luci-i18n-upnp-zh-cn"
# 【官方】NATMap：保持 NAT 打洞端口映射，在无公网 IP 时对外提供服务
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-natmap-zh-cn"
# 【官方】基于 3proxy 的简易端口转发
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-3cat-zh-cn"
# 【官方】IP/MAC 绑定（静态 ARP）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-arpbind-zh-cn"
# 【官方】Keepalived 双机热备（VRRP 虚拟 IP；编译选项可能使它依赖 iptables，开启前请确认）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-keepalived-zh-cn"
# 【官方】PPPoE 服务端：让下级设备向本机拨号
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-pppoe-server-zh-cn"
# 【官方】PPPoE 服务端（Roaring Penguin 实现）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-rp-pppoe-server-zh-cn"
# 【官方】PPPoE 中继：把下级设备的拨号转发到上级
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-pppoe-relay-zh-cn"
# 【官方】BCP38：丢弃源地址伪造的出站包
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-bcp38-zh-cn"
# 【官方】OLSR Mesh 路由协议及其服务发现、拓扑可视化
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-olsr-zh-cn"
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-olsr-services-zh-cn"
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-olsr-viz-zh-cn"
# 【官方】BMX7 Mesh 路由协议
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-bmx7-zh-cn"

# ==================== 校园网 / 运营商认证 ====================
# 【官方】MiniEAP：802.1X 校园网认证客户端
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-minieap-zh-cn"
# 【官方】中山大学 H3C 802.1X 认证客户端
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-sysuh3c-zh-cn"
# 【官方】有线 802.1X 认证客户端
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-cd8021x-zh-cn"
# 【官方】深澜（Srun）校园网自动登录
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-bitsrunlogin-go-zh-cn"
# 【官方】UA2F：修改 HTTP User-Agent，规避校园网多设备检测
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-ua2f-zh-cn"
# 【官方】迅雷快鸟宽带提速
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-xlnetacc-zh-cn"

# ==================== 代理 ====================
# 【官方】PassWall（含 Xray、sing-box、Hysteria 核心）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES geoview xray-core sing-box hysteria luci-i18n-passwall-zh-cn"
# 【第三方】PassWall2
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES geoview xray-core sing-box hysteria kmod-nft-socket kmod-nft-tproxy luci-app-passwall2 luci-i18n-passwall2-zh-cn"
# 【第三方】ShadowSocksR Plus+（构建时自动下载 mihomo 核心）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-nft-tproxy kmod-nft-socket xray-core naiveproxy luci-app-ssr-plus luci-i18n-ssr-plus-zh-cn"
# 【GitHub】OpenClash（构建时自动下载最新版 apk、Meta 内核和 GeoIP/GeoSite 数据）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash luci-compat kmod-tun kmod-inet-diag kmod-nft-tproxy bash curl ip-full unzip"
# 【第三方】Nikki（mihomo 透明代理，与 clashoo 配置冲突，二选一）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-nikki-zh-cn"
# 【第三方】Clashoo by kenzok8（与 nikki 配置冲突，二选一）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES clashoo luci-app-clashoo luci-i18n-clashoo-zh-cn"
# 【官方】HomeProxy（基于 sing-box 的代理平台）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-homeproxy-zh-cn"
# 【官方】dae（基于 eBPF 的高性能透明代理）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-dae-zh-cn"
# 【官方】daed（dae 的网页控制面板版本；第三方仓库提供更新的 1.28.0）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-daed-zh-cn"
# 【官方】v2rayA（v2ray/xray 的网页客户端）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-v2raya-zh-cn"
# 【官方】GOST 隧道/转发工具
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-gost-zh-cn"
# 【官方】MicroSocks：轻量 SOCKS5 服务器
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-microsocks-zh-cn"
# 【官方】Privoxy HTTP 代理（过滤广告、转发到上游代理）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-privoxy-zh-cn"
# 【官方】Tinyproxy 轻量 HTTP(S) 代理
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-tinyproxy-zh-cn"
# 【官方】Squid HTTP 代理与缓存
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-squid-zh-cn"
# 【官方】Tor 匿名网络
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-tor-zh-cn"

# ==================== DNS 与去广告 ====================
# 【第三方】MosDNS（分流 DNS 转发器）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-mosdns luci-i18n-mosdns-zh-cn"
# 【官方】SmartDNS（多上游测速，返回最快的解析结果）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-smartdns-zh-cn"
# 【官方】DNS over HTTPS 代理
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-https-dns-proxy-zh-cn"
# 【官方】Unbound 递归 DNS 服务器
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-unbound-zh-cn"
# 【官方】NextDNS 客户端
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-nextdns-zh-cn"
# 【官方】Adblock：基于 DNS 的广告拦截
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-adblock-zh-cn"
# 【官方】Adblock-Fast：更轻量的 DNS 广告拦截
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-adblock-fast-zh-cn"

# ==================== 安全与访问控制 ====================
# 【官方】应用过滤（OpenAppFilter）：按应用类型（游戏、视频等）限制上网
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-appfilter-zh-cn"
# 【官方】banIP：按 IP 黑名单、国家/地区封禁访问
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-banip-zh-cn"
# 【官方】CrowdSec 防火墙联动：根据社区威胁情报自动封禁
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-crowdsec-firewall-bouncer-zh-cn"
# 【官方】ClamAV 病毒扫描
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-clamav-zh-cn"
# 【官方】【依赖 iptables】fwknopd 单包授权（端口敲门后才开放端口，只支持 iptables）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-fwknopd-zh-cn"
# 【官方】ACME 自动申请和续期 HTTPS 证书
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-acme-zh-cn"

# ==================== VPN 与异地组网 ====================
# 【官方】WireGuard 协议支持（在“网络-接口”中添加）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-proto-wireguard"
# 【官方】Tailscale
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-tailscale-community luci-i18n-tailscale-community-zh-cn"
# 【官方】ZeroTier
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-zerotier-zh-cn"
# 【官方】OpenVPN 客户端/服务端配置
# （不要集成 luci-app-openvpn-server，它的配置文件有 bug，会导致报错）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-openvpn-zh-cn"
# 【官方】IPSec VPN 服务端（IKEv1 + PSK + Xauth）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-ipsec-vpnd-zh-cn"
# 【官方】OpenConnect VPN 服务端（兼容 Cisco AnyConnect 客户端）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-ocserv-zh-cn"
# 【官方】SoftEther VPN
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-softethervpn-zh-cn"
# 【官方】n2n 点对点 VPN
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-n2n-zh-cn"
# 【官方】EoIP 二层隧道（兼容 MikroTik）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-eoip-zh-cn"

# ==================== 内网穿透与动态域名 ====================
# 【第三方】Lucky：DDNS、反向代理、端口转发、STUN 穿透 by gdy666 & sirpdboy
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-lucky lucky luci-i18n-lucky-zh-cn"
# 【官方】DDNS 动态域名（ddns-scripts）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-ddns-zh-cn"
# 【官方】DDNS-Go 动态域名
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-ddns-go-zh-cn"
# 【官方】frp 客户端
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-frpc-zh-cn"
# 【官方】frp 服务端
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-frps-zh-cn"
# 【官方】xfrpc（C 语言实现的轻量 frp 客户端）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-xfrpc-zh-cn"
# 【官方】NPS 内网穿透客户端
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-nps-zh-cn"
# 【官方】ngrok 客户端
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-ngrokc-zh-cn"
# 【官方】PageKite 内网穿透
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-pagekitec-zh-cn"
# 【官方】Cloudflare Tunnel
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-cloudflared-zh-cn"
# 【官方】SSH 隧道
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-sshtunnel-zh-cn"

# ==================== 存储、共享与网盘 ====================
# 【第三方】QuickFile 文件管理器 by sbwml（与 luci-app-run 冲突，二选一）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES bash quickfile luci-app-quickfile luci-i18n-quickfile-zh-cn"
# 【官方】FileBrowser 网页文件管理（Go 版，默认账号密码 admin/admin）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-filebrowser-go-zh-cn"
# 【官方】LuCI 内置文件浏览器
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-filebrowser-zh-cn"
# 【官方】Samba4 网络共享（Windows/macOS 可直接访问）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-samba4-zh-cn"
# 【官方】Ksmbd 网络共享（内核态 SMB，比 Samba 更省资源）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-ksmbd-zh-cn"
# 【官方】NFS 网络共享
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-nfs-zh-cn"
# 【官方】FTP 服务器（vsftpd）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-vsftpd-zh-cn"
# 【官方】挂载远程 SMB/CIFS 共享
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-cifs-mount-zh-cn"
# 【官方】硬盘空闲休眠
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-hd-idle-zh-cn"
# 【官方】OpenList 网盘聚合（AList 社区版）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-openlist-zh-cn"
# 【官方】Rclone 网盘挂载与同步
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-rclone-zh-cn"
# 【官方】Syncthing 多设备文件同步
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-syncthing-zh-cn"

# ==================== 下载 ====================
# 【官方】Aria2 多线程下载
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-aria2-zh-cn"
# 【官方】qBittorrent BT 下载
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-qbittorrent-zh-cn"
# 【官方】Transmission BT 下载
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-transmission-zh-cn"
# 【官方】aMule（eD2k/Kad 电驴下载）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-amule-zh-cn"

# ==================== IPTV 与多媒体 ====================
# 【官方】rtp2httpd：把 IPTV 组播转成 HTTP 单播 by stackia（第三方仓库有更新版本）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-rtp2httpd luci-i18n-rtp2httpd-zh-cn"
# 【官方】udpxy：IPTV 组播转 HTTP
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-udpxy-zh-cn"
# 【官方】msd_lite：IPTV 组播转 HTTP（多流）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-msd_lite-zh-cn"
# 【官方】omcproxy：组播代理（IGMP/MLD），用于 IPTV
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-omcproxy-zh-cn"
# 【官方】MiniDLNA 局域网媒体服务器（电视可直接播放共享视频）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-minidlna-zh-cn"
# 【官方】PS3 网络游戏共享服务（ps3netsrv）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-ps3netsrv-zh-cn"
# 【官方】OSCam 卫星电视读卡服务
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-oscam-zh-cn"

# ==================== 远程唤醒与远程桌面 ====================
# 【官方】网络唤醒（Wake-on-LAN）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-wol-zh-cn"
# 【官方】定时网络唤醒
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-timewol-zh-cn"
# 【官方】RustDesk 远程桌面中继服务器
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-rustdesk-server-zh-cn"

# ==================== 4G/5G 模块 ====================
# 【官方】蜂窝模块信息（信号、运营商等）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-3ginfo-lite-zh-cn"
# 【官方】蜂窝模块频段锁定
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-modemband-zh-cn"
# 【官方】短信收发与 USSD
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-sms-tool-js-zh-cn"

# ==================== 其他服务 ====================
# 【官方】KMS 激活服务器（vlmcsd）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-vlmcsd-zh-cn"
# 【官方】Mosquitto MQTT 服务器（智能家居常用）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-mosquitto-zh-cn"
# 【官方】UPS 管理（Network UPS Tools）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-nut-zh-cn"
# 【官方】网络打印服务器（p910nd）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-p910nd-zh-cn"
# 【官方】USB 打印机共享
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-usb-printer-zh-cn"
# 【官方】串口转网络（ser2net）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-ser2net-zh-cn"
# 【官方】邮件中继（EmailRelay）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-email-zh-cn"
# 【官方】CoovaChilli 热点认证（Captive Portal）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-coovachilli-zh-cn"
# 【官方】OpenWISP 集中管理客户端
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-openwisp-zh-cn"
# 【官方】dump1090 航班 ADS-B 信号接收（需要 RTL-SDR USB 接收器）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-dump1090-zh-cn"

# ==================== 特殊硬件（x86 一般用不到）====================
# 【官方】Linksys 双分区切换重启
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-advanced-reboot-zh-cn"
# 【官方】电池状态显示（便携路由器）
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-battstatus-zh-cn"
# 【官方】OLED 屏幕显示
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-oled-zh-cn"
# 【官方】DSL 调制解调器状态
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-dsl-zh-cn"
