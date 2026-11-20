# 更新日志

本文件记录固件仓库的重要功能、稳定性和维护变更。常规的
ImmortalWrt 上游合并不逐项展开，仅记录会影响本设备构建或运行行为的内容。

## 2026-11-20

### pbs05 同步与 naoki66 产品线移除

- 合并 `pbs05/master` `f6977f2`：新增 FiberHome AN4475-G2
  （DTS、image profile、2 MiB PON data、LED/network）、HG5585F 的
  MT7916 TX/NAPI CPU 亲和性、RTL8221B RJ45 LED 初始化补丁 762。
- 设备表以 pbs05 为准：删除 naoki66 带来的 XR1710G（`gemtek_xr1710g*`）
  和 XG2010G UBI/2G（`gemtek_xg2010g-ubi`、`gemtek_xg2010g-2g-ubi`）
  共 4 个 profile、4 个 DTS 及对应 `board.d`/升级/U-Boot env 条目。
  保留 pbs05 的 W1700K 和 XG2010G 原厂布局版（`gemtek_xg2010g`）。
- 删除只服务 XR/XG 的内核补丁（`0401/0402`、`201/202`、
  `920-xg2010g-pon-17..20`、ptp ToD、generic hack `767`）。
  共享驱动补丁（pinctrl/PCS/RTL8261/PCIe/flowtable 及 mt76、
  mac80211、hostapd、wireless-regdb）保留。
- 删除 naoki66 LuCI feed（`airoha_luci`）及只被其设备使用的
  `luci-app-mlo`、`airoha-an7581-mt7996-board`、mesh/DAWN feed 补丁。
- 删除 `1710/2010/2010-2g` 种子、Gemtek 专用检查脚本和 naoki 通用
  默认值（watchcat/crontab/igmpproxy/sysctl）。
- `vendor.lock` 的 pbs05 基线更新到 `f6977f2`，移除 naoki66 来源；
  默认构建 seed 改为 `an7581.config`/`an7583.config`。

## 2026-11-19

### FXS 通用化：fxs-core / chan_fxs

- `fxs-core` 事件 FIFO 改为按 `struct fxs_event` 元素入队，修复
  `/dev/fxs0` 读出的 hook 事件只有 `type` 有效、其余字段为栈垃圾的
  问题。
- `fxs-core` 增加 SLIC 后端注册/探测接口和
  `/sys/class/fxs/fxs0/{line_name,state,hook,ringing,active}` 状态。
- `an7581-fxs` 改为在 probe 时自动探测已注册的 SLIC 后端，不再写死
  Le9641；`an7581-slic-le9641` 自己注册 detector，并在
  `fxs-core` 注册 line 时完成 SLIC init/audio up。
- `an7581-voice.init` 删除；模块加载改由 `kmod-an7581-fxs` /
  `kmod-an7581-slic-le9641` 的 `AUTOLOAD` 和模块依赖完成。
- Asterisk 通道改名：`asterisk-chan-an7581` → `asterisk-chan-fxs`，
  `chan_an7581.so` → `chan_fxs.so`，tech `AN7581` → `FXS`，
  `AN7581/line1` → `FXS/line1`，`an7581.conf` → `fxs.conf`。
- `voip-apply` 写 `fxs.conf`、使用 `Dial(FXS/$line)`，状态改读
  `fxs-core` sysfs；LEC 通过 `FXS_IOC_SET_ECHO_CANCEL` 控制，不再
  依赖 `an7581_pcm` sysfs 参数。
- 设备权限改由 `voip-apply boot` 统一设置 `/dev/fxs*`。

## 2026-11-18

### 语音状态页策略路由与 IPTV 抓包说明

- `luci-app-voip`（仍为 0.2.1-r1）：策略路由状态改为按 IP 主机地址
  匹配 netifd 生成的 `from <ip> lookup <table>` 规则，不再用显示用的
  CIDR 去 grep；同时移除状态页的设备行，保留接口、链路、IP、网关和
  策略路由。
- IPTV 抓包文档（`iptv-nd/docs/igmp-control-vlan.md`）：`pon0` 上的
  Query 和 Report 都带 VLAN tag，统一改用 `vlan and igmp`。下行 Query
  的 PCP 由 OLT 决定（常见为 0），上行 Report 的 PCP 由 `iptv` 的
  `priority` 决定，不要求双向一致。
- 源码提交：`airoha-voip` 的 `825d089`；feed 只更新 tarball pin，
  不在 feed 内维护本地补丁。
- 该状态页修复只涉及 `luci-app-voip`，不改动 `kmod-iptv` /
  `iptv-nd` 驱动版本。

### 语音挂机状态与出局忙音

- `asterisk-chan-an7581`（仍为 11）：移除 `wait_onhook` 锁存。hook
  监视器读到的是当前状态而不是事件队列，快速挂机/再摘机可能漏掉
  中间 onhook；原先该锁存一旦残留，后续 `an7581_start_outgoing()`
  会一直提前返回。现在每次 offhook 且没有 owner 时都会重新启动
  出局呼叫，并在挂机、启动音频或 PBX 失败时显式清理 owner 和
  dialing/collecting 状态。
- `luci-app-voip`：出局 `Dial()` 返回后统一进入 `postdial`，播放
  `busy` 忙音 `busy_tone_timer` 秒后再挂断，修复远端先挂机时本机
  听不到忙音的问题。
- 源码提交：`airoha-voip` 的 `825d089`；仅更新 `luci-app-voip` 和
  `asterisk-chan-an7581` 的 tarball pin，不升版本。

## 2026-11-17

### HG5582A 语音参数对齐原厂

- `luci-app-voip` 默认 codec 顺序改为原厂配置：G.711A 1、
  G.711U 2、G.729 3、G.722 4。此前 G.722 默认为 1，真实外线会
  优先协商 16k codec，在 8k FXS/PCM 路径上增加转码和毛刺风险。
- 新增静态 jitter buffer 配置（默认 50ms），`voip-apply` 在入呼
  PJSIP 通道和出呼 pre-dial handler 上设置 `JITTERBUFFER(fixed)`。
- 语音 VLAN 默认 MTU 1460、802.1p 6，由 `voip-apply` 在接口
  创建/重载时设置，不再单独安装 hotplug 钩子。
- `flashhook_min` 默认 100ms、数图长定时器 20s、时间同步默认开启，
  并在 LuCI 中暴露 jitter buffer 参数。
- 镜像 profile 增加 `asterisk-func-jitterbuffer` 和
  `asterisk-codec-g729`（bcg729）。源码修改位于
  `yveming/airoha-voip`；feed 的源码 pin 需要在该仓库提交后更新。

### HG5582A 语音/IPTV UI 简化与版本

- `luci-app-voip` 0.2.1-r1：语音状态页只保留设备、接口、链路、
  IP 地址、网关和策略路由状态；IP 地址显示为带前缀的 CIDR，后续
  可扩展 IPv6。
- `luci-app-iptv` 0.2.1-r1、`kmod-iptv` release 3：IPTV 配置新增
  802.1p 优先级（默认 3）和 MTU（默认 1500）。驱动对所有上行
  service、multicast 和 IGMP/MLD 报文统一设置 VLAN PCP，不依赖
  下层 `egress-qos-map`。
- 源码提交：`airoha-voip` 的 `d2464d7`，`iptv-nd` 的 `306b30f`。
  feed 的源码 pin 仍需在 push 后更新。

## 2026-11-16

### IPTV 组播控制报文 VLAN 可选

- `kmod-iptv` 新增 `igmp_on_service` sysfs 开关，`luci-app-iptv` 新增
  “组播控制报文 VLAN”选项，对应 `/etc/config/iptv` 的 `igmp_vid`
  （`mcast` / `service`）。
- IGMP/MLD 控制报文不再强制使用 `mcast_vid`。少数运营商的组播 VLAN
  只下行，IGMP 走业务 VLAN；旧逻辑在 `pon0` 上行没有对应 flow，
  `tx_no_mapping` 丢包，表现为 IPTV 认证/VOD 正常但直播黑屏。
  默认保持 `mcast`，这类运营商改为 `service`。
- 只匹配 IPv4 IGMP 和 IPv6 MLD（130/131/132/143）；其他 IPv4/IPv6
  组播（含 NDP）仍走组播 VLAN。
- `luci-app-iptv` 版本提升到 `0.2.0-r1`，`kmod-iptv` 包 release 保持 `2`。
- 上游仓库 `yveming/iptv-nd` 已直接包含驱动/LuCI 改动（commit `0001c0f`），
  `pon_feed` 只固定 tarball，不再维护本地补丁。

## 2026-11-08

### feed 与包结构整理

- `pon_feed` 只保留打包 Makefile 和本地补丁：`airoha-voice`、
  `asterisk-chan-en75xx`、`nf-nathelper-fcc`、`iptv`（thin packages）。
- `nf-nathelper-fcc`、`iptv` 改为 `PKG_SOURCE` 引用上游，源码不再复制进 feed。
- `airoha-voice` / `asterisk-chan-en75xx` 共用一个 `airoha_voip` 源码 tar 包。
- LuCI Airoha 应用改走 `naoki66/luci-app-airoha` feed；`clientstatus` 系列删除。
- `luci-app-mlo`、`airoha-an7581-mt7996-board`、`znxt-zn515-mt7916-eeprom`
  回到主树 `package/`（产品树自带、没有独立上游）。
- 移除 `onu_config` feed；语音配置改为需要时手动 clone。
- 移除 `luci-theme-glass` feed。

### IPTV 驱动与配置合成一个包

- `iptv-scripts` 并入 `kmod-iptv`：`kmod-iptv` 现在同时安装 `iptv.ko`、
  `/etc/config/iptv`、`/etc/init.d/iptv` 和
  `/etc/uci-defaults/30-iptv-stb-ignore`。
- `/usr/libexec/iptv-apply` 删除，apply 逻辑合并进 `/etc/init.d/iptv`；
  失败只记 `logger`（tag `iptv`）并返回，不再 `exit`，保证 procd reload
  trigger 始终注册。
- `luci-app-iptv` 依赖改为 `+kmod-iptv`；`CONFIG_PACKAGE_iptv-scripts`
  符号取消。
- 修复 `luci-i18n-iptv-zh-cn` 只装 uci-defaults、没有 `.lmo` 的问题：
  thin package 在解析期展开 `$(wildcard ...)` 时上游 po 还没解包，改为
  install 阶段 shell glob。
- 上游 `yveming/iptv-nd` 同步调整，固定到 `ed62fbe`。

### Airoha NPU 状态页改用通用上游

- `luci-app-airoha-npu` 从 naoki66 的板级 `2.0.0-r9` 换成
  `rchen14b/luci-app-airoha-npu` 的 `1.0.1`，修复 pbs05 XG2010G 等
  非 Gemtek 板卡上的运行时错误。
- 上游仓库不是 feed 布局，改在 `pon_feed` 里以 thin package 打包，固定
  commit `14521b8`，构建时提取仓库根目录的 `htdocs/`、`root/`、`po/`。
- 包名和 `CONFIG_PACKAGE_luci-app-airoha-npu` 符号不变；旧
  `luci-i18n-airoha-npu-zh-cn` 翻译包随旧包移除。
- 移除临时的 `arioha_npu` / `airoha_npu` src-git feed 条目。

### pbs05 同步与 L1 补丁栈切换

- 合并 `pbs05/master` `d9dd3a4`；bridge flowtable 从本地 7 补丁栈切到
  pbs05/ImmortalWrt 的官方 `675-01..675-14` 系列，`650`/`915-01` 跟随刷新。
- 保留本地 `922`（与 pbs05 的 922 功能等价，仅上下文适配）和 `310-10`
  （已包含 `port->lock` 的 MIB stats 转换）；`310-11`/`310-12` 暂不加入。
- `9999-12` 的 `thoff==0` 检查已由 `675-09` 吸收；`9999-11` 按新
  `nft_flow_route()` API 重生成。
- `928` 拆分：保留 pbs05 的 `928`（PPE bind rate），本地 UPDMEM 补丁改名 `929`；
  新增 `999-mt7530-trap-frames-to-conduit`。
- `firewall4` `PKG_RELEASE` `5 -> 6`。
- 验证：`scripts/check-patch-stack.sh airoha` 783 个补丁全绿；
  `make target/linux/compile` 通过。

## 2026-11-03

### 修好种子校验脚本的两个盲点，并清理由此暴露的种子残留

合并后的 `make defconfig` 暴露出 `check-seed-symbols.sh` 一直在给假绿：

- **元数据缓存**：脚本直接用 `tmp/.packageinfo`。上游删包后若增量扫描没刷新，校验会拿
  旧符号表比对 —— `kmod-iptables` 被上游删除（`ca454c00b6`）时就这样漏过。现在每次
  运行前强制删掉 `tmp/.packageinfo`、`tmp/.config-package.in`、`tmp/.config-feeds.in`。
- **符号正则漏连字符**：`^CONFIG_[A-Za-z0-9_]+=` 匹配不到 `kmod-*`、`luci-app-*` 这类
  名字。1710 种子 1282 个符号里有 292 个从未被检查（990 → 1276）。正则补上 `-`，
  查找改用固定字符串，避免符号里的 `+`/`.` 被当成正则。

由此暴露并清理的种子残留：

| 符号 | 原因 |
| --- | --- |
| `kmod-iptables`（1710/2010/2010-2g） | 上游删除（`ca454c00b6`，KCONFIG 并入 `kmod-nf-ipt`） |
| `kmod-nf-log6` | 上游删除（`313889ee5c`） |
| `kmod-crypto-lib-chacha20poly1305` / `curve25519` | 隐藏包，只由选择者（wireguard）拉起；种子已关 wireguard，属残留 |
| `kmod-udptunnel4/6`（1710/2010/2010-2g） | 隐藏包，没有选择者 |
| `luci-i18n-airoha-zh-cn`（1710/2010） | `luci-app-airoha` 已不存在（现为 `-npu`/`-factory`/`-fancontrol`/`-recovery`） |
| `luci-i18n-iptv-zh-cn`、`luci-i18n-pon-zh-cn`（2010） | 对应 app 未选中，i18n 是孤儿 |
| `luci-i18n-airoha-npu-zh-cn`（2010-2g） | 该 app 没有 zh-cn 翻译包 |
| `MODULE_DEFAULT_luci-app-iptv`、`MODULE_DEFAULT_luci-i18n-iptv-zh-cn`（an7581） | 符号不存在 |

校验：6 个种子 0 丢弃（1710 1276 / 2010-2g 983 / 2010 889 / an7581 1144 /
an7583 1105 / release 10）。

### 去掉误选的 OpenVPN DCO 内核模块

`configs/an7581.config`、`an7583.config` 从 pbs05 的旧配置里继承了
`CONFIG_PACKAGE_kmod-ovpn-backports=y`（OpenVPN data channel offload）。它只对
`openvpn-openssl` 有用，而种子并没有选 OpenVPN；该模块自身依赖
`kmod-udptunnel4/6`、`kmod-crypto-lib-chacha20poly1305`、`kmod-crypto-lib-curve25519`
等一串 tunnel/crypto 模块 —— 这就是构建列表里"无缘无故"多出来的那几个。

已从两个种子删除；`make defconfig` 之后 `kmod-udptunnel4/6` 与 crypto-lib 模块
随之消失（有别的包需要时 Kconfig 仍会自动 select）。

## 2026-11-02

### 同步 immortalwrt 上游（401 个提交）

- 合并 `immortalwrt/immortalwrt` `e695009c15..89f1ef18c8`（401 个提交），
  `vendor.lock` 的 `upstream` 基线随之前移到 `89f1ef18c8`。
- 上游放弃 kernel 6.12（`32c7a1346e`）：`target/linux/generic/*-6.12` 随之删除
  （`pending-6.12` 上游自己还留着 6 个 media 补丁，按上游状态保留）。
- 上游新增 backport `706-01`（把 `net_device_path_ctx` 传入
  `dev_fill_forward_path()`）与 `708/709` 系列（flowtable priority / VLAN match），
  与本地 675 桥接卸载系列正面相撞。处理：
  - `675-01` 只剩 `br_fdb_find_rcu` 导出（同时改名）；`__dev_fill_forward_path`
    已由上游 706-01 以 ctx 形式提供；
  - `675-02` 按新 API 重写：ctx 由调用方预填（含 `ieee80211`），daddr 写回
    ctx 后调用 `dev_fill_forward_path(ctx, stack)`；`nft_flow_route` 拆成
    routing / bridging 两条路径；
  - `675-04`（VLAN passthrough）注入点随新控制流改写；
  - `9999-11`（xfrm/SOE 绑定）改写进 `nft_flow_route_routing`，复用
    `err_dst_release`；
  - `9993`（PPE cache-miss 桥接路径）改用 `dev_fill_forward_path(ctx, stack)`。
  补丁链从「710 个中 4 个失败」恢复为 0 失败。
- 冲突裁决：`firewall4/Makefile` 保留本地 `PKG_RELEASE=5`（fullcone 补丁与上游
  刷新后的版本逐字节一致）；`915-01` 取上游（内容相同，仅按新内核刷新上下文）；
  `generic/config-6.12` 接受上游删除。
- `configs/*.config`：删掉上游已移除的 5 个内核选项
  （`MEMCG_KMEM`、`CIFS_ACL`、`HFS_FS_POSIX_ACL`、`HFSPLUS_FS_POSIX_ACL`、
  `NFS_ACL_SUPPORT`，见上游 `e4722f914b` / `c48a071499`）。
- 验证：`scripts/check-patch-stack.sh airoha` → 710 个补丁 0 失败；
  `make target/linux/compile`（an7581 种子）通过；`firewall4` 的两个补丁在新
  Git HEAD（`e6f600c4`，2026-10-29）上仍可干净套用；6 个种子符号校验 0 丢弃。

### 供应商状态

- `pbs05/ponwrt`：**无新提交**（tip `03c1345447` 已在 `pon` 里）。
- `naoki66`：新增 5 个提交，本轮**未吸收**（按「只挑单个补丁」策略）：
  - `c1794cceb7` an7581/an7583/en7523 内核配置把 bridge flowtable 相关符号改为内置；
  - `8aa505c865` 新增 `920-17`：PPPoE 会话头计入 PPE/WAN egress MTU（修全尺寸
    PPPoE 帧被硬件丢弃），依赖其 `920-16`，与我们当前的 airoha 补丁栈上下文不符，
    留作后续 topic 单独移植；
  - `748b4b28ed` 文档、`405d518bca` `luci-app-clientstatus` 菜单修复。

## 2026-10-25

### 同步 immortalwrt 上游（179 个提交）

- 合并 `immortalwrt/immortalwrt` `2248ed7546..e695009c15`（179 个提交），
  `vendor.lock` 的 `upstream` 基线随之前移到 `e695009c15`。
- 上游把 airoha 补丁系列整体重做（`916-02` → `194-v7.2` LRO、`920-16` 由
  `190/191` 取代、`920-12` → `193-03`、`310-10` 重写并已包含 `port->lock`
  统计锁修复），AN7581/AN7583 EVB 改为 multi-evb DTS + overlay。
- 本地处理：保留上游新系列；删除被取代的旧副本（`182`、`923-01/02`、
  `920-12/16`、`916-02`、`9994`）；产品补丁 `922/925/930` 改用 pbs05 已在
  新基座上 rebase 的版本，`920-xg2010g-pon-17/20`、`9990/9993` 重新 rebase；
  新增 pbs05 的 `924`（NPU mailbox coherent DMA）。
- 删除 `310-11`（disconnect PHY after QDMA teardown）：上游 922 已在
  `airoha_dev_stop()` 内条件化 `phylink_stop/disconnect_phy`，该补丁成为重复项，
  且旧 hunk 上下文过于宽泛，会在新基座上误套到 `airoha_fe_mc_vlan_clear()`。
  补丁链 674 个全部干净套用，`target/linux/compile` 通过。
- `an7583`、`en7523` 的 `config-6.18` 补上
  `# CONFIG_AIROHA_PON_COMPAT is not set`；该符号由 `920-xg2010g-pon-20`
  引入，未写入子目标内核配置时 `syncconfig` 会把它当作 NEW 符号并报错。
- `scripts/check-firmware-artifacts.sh` 改为按 `.config` 实际选中的设备逐个
  校验 ITB（优先 sysupgrade，只有 initramfs 的设备回退到 initramfs），不再只
  认 Gemtek profile；修复 an7581/an7583 构建成功后 `Verify device artifacts`
  误报 “no supported Gemtek firmware profile”。
- 设备树：`an7581-evb-emmc.dtsi` 随上游删除（`max-link-speed=<2>` 已在新的
  `an7581-evb-multievb.dts` 中）；EN8811H 的 1s/100ms 复位时序移到
  `an7583-evb-emmc.dtso`；`image/an7581.mk`、`an7583.mk` 采用上游 multi-evb
  结构并保留全部产品 profile，Nokia 设备补回 `automount`。
- `configs/*.config` 删除内核已移除的 `CONFIG_KERNEL_REISER_FS_POSIX_ACL`。

### 构建产物命名

- 恢复 `ponwrt-` 镜像名前缀：`scripts/set-build-version.sh` 不再默认注入
  `ImmortalWrt naoki66` 和首个设备型号，改为 `PonWrt`；`1710`、`2010`、
  `2010-2g` 种子的 `CONFIG_VERSION_DIST` 同步改为 `PonWrt`。CI 产物从
  `immortalwrt-naoki66-[device-]日期-commit-...` 回到
  `ponwrt-日期-commit-...`。

### 修好上游提醒与自动合并

- 删除 `sync-upstream.yml`（旧模型遗留：默认分支改 `pon` 后会把 upstream 合进
  `pon` 却 push master，且绕过补丁链校验）。
- `check-upstream.yml` 增加"双方都改过的文件"预览，`behind=0` 时自动关闭跟踪
  issue；仓库重新打开 Issues（fork 默认关闭，之前 `createIssue` 一直 403）。

## 2026-10-18

### 仓库结构迁移到 `pon` 分支模型

- `master` = `immortalwrt/immortalwrt` 纯镜像（只允许 fast-forward），`pon` = 产品分支
  （仓库默认分支）。pbs05 / naoki66 不再以 git 血缘整体并入，改为"可挑选的来源"。
- 上游同步不再由 CI 自动合并：`.github/workflows/check-upstream.yml` 只检测并开 issue，
  合并由本地按 `docs/upstream-sync.md` 执行。来源锁定见 `vendor.lock` +
  `scripts/sync-vendors.sh`。

### 修复 XR1710G / XG2010G UBI profile 与 board.d 条目缺失

- `image/an7581.mk` 的 `gemtek_xr1710g*`、`gemtek_xg2010g-ubi`、`gemtek_xg2010g-2g-ubi`
  以及 `board.d/{01_leds,02_network,03_pon_data}`、`upgrade/platform.sh` 里的
  `gemtek,xr1710g*` 分支，在上一轮 pbs05 对齐中被覆盖丢失（XR1710G 会落到 `*)`
  打印 "Unsupported hardware"）。现已补回。
- 注：本产品线为 pbs05 的设备集（出货配置 `configs/an7581.config` / `an7583.config`），
  不含 XR1710G；这些条目保留是为了不丢失已修好的设备支持。

### 内核补丁栈（L1）基准 = pbs05

> 2026-10-25 起该描述已过时：L1 已改为"官方系列 + 产品补丁"，旧的整套
> pbs05 叠法不再适用，详见上方 2026-10-25 条目。

- 两个供应商对同一个内核各维护一套补丁，合并后混用导致 **14 个补丁无法套用**；
  `patch-kernel.sh` 失败即 `exit 1`，即构建无法产出镜像。
- 本产品线即 pbs05 的设备集（`configs/an7581.config` / `an7583.config`），
  因此 L1 采用 **pbs05 的整套补丁栈**（643 个补丁干净套用），只保留仓库自有的
  `928`（UPDMEM IPv6 源 MAC）作为追加补丁。
- naoki66 那一套（含 XR1710G 专用件、以及已对 6.18.55 失效的 `914`/`914b`）
  不再并入；其 `920-xg2010g-pon-*`、`9990/9993/9994/9999-*` 等为 XR1710G 线相关，
  如后续确认对本产品线有价值，再逐个叠加并验证。

### 产品配置与 CI

- CI 的构建选项由 `1710/2010/2010-2g` 改为 **`an7581.config` / `an7583.config`**
  （即本产品实际出货的配置），产物路径随子目标动态解析。
- 移除 CI 里 Gemtek 专用的 `check-profile-isolation.sh` 检查（对多设备配置不适用）。

### 供应商包外置到 feed

- 新增 `src-git pon_feed https://github.com/yveming/openwrt-pon-feed.git`，
  收纳官方基座没有的 15 个包（`luci-app-airoha-*`、`airoha-voice`、`asterisk-chan-en75xx`、
  `luci-app-mlo`、`clientstatus` 系列、`airoha-an7581-mt7996-board`、`znxt-zn515-mt7916-eeprom`、
  `kmod-nf-nathelper-fcc`、`luci-app-{mesh-conf,netmode}` 等），主树只留官方基座与产品补丁。
- 主树删除这些包与 `lucky`（包出树、符号悬空）。

### 构建前守卫

- `scripts/check-seed-symbols.sh`：`make defconfig` 之后断言种子选中的符号仍在
  —— 防的是"包被移出主树 / feed 未挂上"导致的**静默丢包**。
- `scripts/check-patch-stack.sh`：不编译即可验证整条内核补丁链能否干净套用。
- 两者都已接进 `build-firmware.yml`（defconfig 之后、编译之前）。
- 顺带修正：`configs/*.config` 删除 lucky、统一关闭 wireguard、去掉 i2c-tools、
  补回官方自带的 `video` feed、清理上游已不存在的僵尸符号。

## 2026-10-12

### 合并对齐策略

- 内核/驱动/网络补丁以 naoki66/master 为对齐基线（其补丁集随上游活跃更新）。
- 产品定义（设备 DTS、image profile、产品化配置）以 pbs05/ponwrt 为准——
  naoki66 库不含本产品线设备，两者冲突时产品侧一律以 pbs05 裁决。
- 本轮合并后 `target/linux/airoha/patches-6.18/` 与 `target/linux/generic/pending-6.18/`
  已与 naoki66/master 完全一致，唯一差异为本仓库新增的 928 号补丁。

### 修复 PON 链路上 IPv6 硬件分载静默断流（UPDMEM 源 MAC 失同步）

- 新增
  `target/linux/airoha/patches-6.18/928-net-airoha-sync-UPDMEM-egress-mac-for-ipv6-offload.patch`：
  `airoha_ppe_foe_entry_prepare()` 在为路由式 IPv6 流写 `smac_id` 之前，先把该流
  实际使用的出向源 MAC 编程进 UPDMEM 表项（复用 `airoha_ppe_init_upd_mem()`）。
- 根因：IPv6 FOE 条目不内联源 MAC，硬件按 `smac_id` 查 UPDMEM；该表只在 probe
  时写入 GDM 端口自身的 `dev_addr`（gdm2 = factory 0x3e = `:f3`）。当会话 MAC
  与端口 MAC 不一致时——例如 pon0.1024 为隔离多服务 DHCP 而单独配置 `:f8`——
  硬件发出的 IPv6 帧携带过期的源 MAC，被上游静默丢弃。TCP/TLS 在慢路径完成，
  流量恰在硬件分载接管后停摆，表现为"只有 IPv6、传一半卡死"。IPv4 HNAPT 条目
  内联源 MAC，故完全不受影响。
- 现网验证：手工向 UPDMEM[2] 写入 `:f8` 后 v6 立即恢复满速（中科大测速从数 MB
  恢复到与 v4 同速），conntrack 正常挂载 `[HW_OFFLOAD]`。补丁将此行为固化。
- 已知边界：同一 GDM 端口并发承载多个不同源 MAC 的路由式 IPv6 流时，表项按
  最近一次 offload 生效（当前家庭业务仅上网 VLAN 走 v6 路由，不受影响）。

### fcc helper 注册改为镜像内置 + 卸载对称清理

- `kmod-nf-nathelper-fcc` 的 postinst 原先使用绝对路径，构建镜像时以
  `IPKG_INSTROOT` 指向 rootfs 暂存目录执行，检查的是构建机自身的
  `/usr/share/firewall4`（不存在）而静默退出，导致烧录镜像永远缺失 helper 段，
  只有设备上手动 `apk add` 才生效。现改为 `IPKG_INSTROOT` 感知路径，
  `modprobe`/`fw4 reload` 仅在真机执行。
- 新增 prerm（apk 的 pre-deinstall）：卸载时按
  `# >>>/<<< kmod-nf-nathelper-fcc` 标记删除 helpers 中的 fcc 段并 reload。
  追加进 firewall4 文件的内容不属于本包，`apk del` 不会清理，此前会残留。
  段改用标记注释包裹，移除仅用 sed 实现，不引入额外依赖。

## 2026-10-08

### 同步 ImmortalWrt 上游至 6.18.54

- 合并 `immortalwrt/immortalwrt` 的 306 个上游提交，内核补丁基线从 6.18.52
  推进到 6.18.54。
- 上游将 RTL8261C/D 的 LED 支持从 `hack-6.18/750-*` 迁出，改为新增
  `pending-6.18/721-02-net-phy-realtek-add-LED-support-for-RTL8261C-D.patch`
  并补齐亮度、极性和使能位处理，因此删除本地已无用的 `hack-6.18/750-*`。
- `pending-6.18/737-02` phylink PCS 补丁改用上游版本：本地此前的 v15 写法
  与上游 v3 写法功能完全等价，而上游版本已按 6.18.54 基线校订行号。
- `pending-6.18/743` RTL8261N USXGMII SerDes 补丁保留本地的 `sds_work`
  竞态修复语义（`READ_ONCE`/`WRITE_ONCE` 发布顺序，以及每次寄存器访问前和
  重新排队前的 disable 检查），叠加在上游的行号框架之上。

### 修正路由式 IPTV 组播丢包（引入 PonWrt #29）

- 引入 `pbs05/ponwrt#29` 的 `airoha: restore opt-in fraglist GRO` 修复。上游
  `hack-6.18/600` 把 `NETIF_F_GRO_FRAGLIST` 设为默认开启后，fraglist GRO 会把
  同流连续 UDP 报文合并成保留 DF 标志的超大 skb，该 skb 经 IPv4 组播路由转发
  时在 `ipmr_prepare_xmit()` 被静默丢弃，导致高码率 IPTV 流大量丢包（组播不可
  分片、无法收到 ICMP 错误，只有 `FragFails` 递增）。
- 新增 `target/linux/airoha/patches-6.18/980-revert-fraglist-gro-by-default.patch`，
  在 airoha target 内把 fraglist GRO 恢复为 opt-in 默认关闭，不改动通用补丁。
- 该修复只影响 `NETIF_F_GRO_FRAGLIST` 软件路径，与 XR1710G 的
  `NETIF_F_GRO_HW` 硬件 GRO（916-02 补丁）互不影响。

