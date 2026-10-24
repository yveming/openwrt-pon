# 更新日志

本文件记录固件仓库的重要功能、稳定性和维护变更。常规的
ImmortalWrt 上游合并不逐项展开，仅记录会影响本设备构建或运行行为的内容。

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
- 设备树：`an7581-evb-emmc.dtsi` 随上游删除（`max-link-speed=<2>` 已在新的
  `an7581-evb-multievb.dts` 中）；EN8811H 的 1s/100ms 复位时序移到
  `an7583-evb-emmc.dtso`；`image/an7581.mk`、`an7583.mk` 采用上游 multi-evb
  结构并保留全部产品 profile，Nokia 设备补回 `automount`。
- `configs/*.config` 删除内核已移除的 `CONFIG_KERNEL_REISER_FS_POSIX_ACL`。

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

