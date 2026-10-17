# 实施记录：x86-64 ImageBuilder Action

计划：[2026-10-17-x86-64-imagebuilder.md](2026-10-17-x86-64-imagebuilder.md)　规格：[../specs/2026-10-17-x86-64-imagebuilder-design.md](../specs/2026-10-17-x86-64-imagebuilder-design.md)

## 验证情况

| 内容 | 结果 |
| --- | --- |
| `sh tests/run.sh`（macOS sh 与 dash） | 9/9 通过；数据分区的 sfdisk 演练在 macOS 上跳过 |
| ShellCheck 0.11.0（`-S warning`，与 CI 相同命令） | 无问题 |
| actionlint 1.7.12（含 ShellCheck） | 无问题 |
| `build/fetch-extras.sh` 真实下载 | Docker 29.9.1（TUNA）、Compose v5.6.0、DPanel v1.11.1、timecontrol v3.2.4 |
| `build/stage.sh` 真实组装 | 覆盖层完整（8 个 Docker 二进制、Compose、DPanel、配置） |
| packages.txt 中每个包 | 均在 25.12.2 官方索引中（timecontrol 来自 GitHub） |
| 只能在 CI 验证 | ImageBuilder 构建、manifest 校验、sfdisk 数据分区演练（dash 测试与构建后的 smoke test）、BusyBox 下的测试 |
| 只能在真机验证 | PPPoE、2.5G 网口识别、macvlan/shim 互通、DPanel 运行、/data 首次分区 |

## 执行中做出的决定

1. 在当前目录直接修改，不建 worktree、不提交：工作区里有你自己暂存的改动，提交与否由你决定。
2. `.gitignore` 除 `.DS_Store` 外还忽略 `.superpowers/`（执行工具的临时目录）。
3. 测试用 `TEST_SHELL=dash sh tests/run.sh` 在 dash 下运行（计划里写的 `dash tests/run.sh` 只会让运行器本身用 dash）。
4. 数据分区用 `start=` 不写 `size=`，让 sfdisk 占满空闲区，避免显式大小被重新对齐；CI 会检查分区是否用到磁盘末尾。
5. 增加 `datadisk_find_label` 及其测试，用于复用已有的 `LABEL=data` 分区。
6. sfdisk 相关测试在本机（macOS，无 util-linux）无法运行；参数已对照 util-linux 2.41 手册核对，真实运行在 CI。
7. sshd 配置改用 awk 编辑（不同平台的 `sed -i` 行为不同），只替换第一处 `PermitRootLogin`，没有时才追加。
8. sysctl 测试只检查非注释行和完整键名（`arp_filter` 包含 `rp_filter` 子串）。
9. PPPoE 用户名密码不写入（真实 uci 设置空值等于删除），LuCI 中显示为空；伪 uci 已按真实行为修正。
10. 其余网口的接口名做了字符过滤（`ll_<网口>`），uci 不接受 `-` 和 `.`。
11. kexue 标签的选项先删后加，脚本重复执行不会产生重复项。
12. 服务脚本增加停止顺序：DPanel（K05）先于 Docker（K10），Docker 停止时最多等待 60 秒让容器退出。
13. DPanel 跳转页的提示文字直接写中文，没有翻译文件。
14. 依赖 jq 的 JSON 断言在没有 jq 的 BusyBox 镜像中跳过，Ubuntu 上的 dash 运行会覆盖。
15. 构建脚本都写成 POSIX sh，便于在 dash / BusyBox 下测试；容器内仍用 bash 执行。
16. `apply_config_override` 改为接收 `<覆盖片段> <.config>` 两个参数，并用 awk 实现。
17. 构建校验额外拒绝 ext4 镜像；下载后检查 Docker 的 8 个二进制和 timecontrol 的两个 apk 都在。
18. 下载速度低于 100 KB/s 持续 60 秒即视为失败，TUNA 在海外 Runner 上太慢时自动改用 download.docker.com。
19. Release 说明用 Markdown 粗体代替中文引号（ShellCheck SC1111）。

## 最终审查（作者自查，未使用独立审查代理）

修复（均先写失败测试再修复，修复后 9/9 通过）：

- **严重**：数据分区脚本原名 `10-custom-data-disk`，排在 fstools 的 `10-fstab` 之前，全新设备上 `/etc/config/fstab` 尚不存在，`/data` 永远不会挂载。已改名为 `15-custom-data-disk`，并加了排序测试。
- **重要**：shim 持有 LAN 地址，dnsmasq 会在 shim 上重复应答 DHCP。已增加 `dhcp.macvlan_shim`（`ignore=1`）。
- **重要**：`/etc/docker/daemon.json` 在保留配置升级后会被还原。已加入 `/lib/upgrade/keep.d/custom`。

只写入文档、未改代码：

- 修改根分区大小后重刷会在新位置重建 `/data`，原数据丢失（旧文件系统无法安全定位）。已写入 README。
- 安装官方 `dockerd` / `luci-app-dockerman` 会与静态 Docker 冲突。已写入 README。
