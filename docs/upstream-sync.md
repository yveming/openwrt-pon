# 上游同步与分支模型

本仓库的产品分支 `pon` 只承载"官方基座 + 产品补丁"，第三方仓库（pbs05 / naoki66）
不再以 git 血缘整体并入，而是作为**可挑选的来源**。这样每次同步的冲突面从
"多血缘 merge"缩小到"我们自己的改动"。

## 分支

| 分支 | 定义 | 规则 |
| --- | --- | --- |
| `master` | `immortalwrt/immortalwrt` 的**纯镜像** | 只允许 `git merge --ff-only upstream/master`，不提交任何本地改动 |
| `pon` | 产品分支 = `master` + 产品层 | 仓库默认分支，发布 tag 打在这里 |
| `topic-*` | 单用途分支（一个修复一条） | 从 `pon` 拉出，合回 `pon`；上游化的补丁在这里先成型 |

远程：

```
origin     yveming/openwrt-pon                                （可写，默认分支 = pon）
upstream   immortalwrt/immortalwrt                              只读
pbs05      pbs05/ponwrt                                         只读，产品层（设备/镜像 profile）
naoki66    naoki66/ImmortalWrt-for-Gemtek-brightspeed           只读，XR1710G 线（只挑单个补丁）
```

`git remote set-url --push <vendor> DISABLED_READ_ONLY` 已设置，防止误推。

## 内容分层

| 层 | 内容 | 位置 | 规则 |
| --- | --- | --- | --- |
| L0 | 官方基座 | `master` | 不碰 |
| L1 | 内核/网络补丁 | `target/linux/*/patches-*`、`generic/{pending,hack}-*` | **只增不改**：上游补丁文件只读，我们的改动一律新增补丁号 |
| L2 | 产品树 | `target/linux/airoha/{dts,an7581,an7583,base-files,image,files-6.18}`、`configs/` | 新增文件零冲突；改上游文件尽量走 `files/` overlay 或 patch |
| L3 | 外置软件包 | **`openwrt-pon-feed`** | 官方基座没有的包一律外置；主树不留供应商包 |
| L4 | 自留地 | `.github/`、`scripts/`、`docs/`、`CHANGELOG.md`、`feeds.conf.default`、`include/feed-patches.mk`、`patches/feeds/` | 我们自有，随产品演进 |

## 同步流程

```sh
# 1) 看各来源的增量（只读）
scripts/sync-vendors.sh

# 2) 官方基座
git fetch upstream
git switch pon && git merge upstream/master

# 3) 产品层（必要时；新增包要移到 pon_feed，而不是留在主树）
git fetch pbs05 && git merge pbs05/master

# 4) XR1710G 线只挑单个补丁
git switch -c topic-xxx pon
git cherry-pick <naoki66 的提交>
git switch pon && git merge --no-edit topic-xxx

# 5) 更新 vendor.lock 里对应的 SHA，然后构建验证
```

### 冲突裁决约定

- `target/linux/airoha/{dts,image,base-files}` 的**设备表**：取并集（本产品同时出货
  XR1710G/XG2010G 与 FiberHome/Nokia/ZNXT/H3C/UnionMan 两套设备线）
- **`target/linux/**/patches-*`（L1 内核补丁栈）：只能取一家，不能取并集。**
  pbs05 与 naoki66 对同一个内核各维护一套完整补丁，混用会出现"同号不同名""同功能
  两份实现""补丁对当前内核已失效"等情况；`patch-kernel.sh` 失败即 `exit 1`，
  所以一旦混用构建必炸。**本产品线就是 pbs05 的设备集，因此基准取 pbs05**，
  仓库自有的追加补丁（如 `928`）逐个叠加，每叠一个都要过
  `scripts/check-patch-stack.sh`。
  历史教训：合并时 L1 混用导致 14 个补丁失败；naoki66 的 `914/914b` 也早已对
  6.18.55 失效（在他们上游仓库同样套不上），随其整套补丁一并弃用。
- 纯产品开关（wireguard、i2c-tools 等）：以 `configs/*.config` 为准

## 校验

```sh
# 1) 内核补丁链能不能干净套用（2 分钟，不需要 swig/python3-setuptools）
scripts/check-patch-stack.sh airoha

# 2) 种子符号是否还有效（每个种子跑一次 defconfig）
./scripts/feeds update -a && ./scripts/feeds install -a
scripts/check-seed-symbols.sh configs/1710.config configs/2010.config configs/2010-2g.config
#   或一次全部：scripts/check-seed-symbols.sh
```

`check-seed-symbols.sh` 会在 `make defconfig` 之后断言种子配置里选中的包仍然生效 ——
feed 没挂上、包被移出主树时，符号会被 Kconfig **静默丢弃**（`lucky`、`luci-app-airoha-*`
都踩过这个坑）。

## 已知的历史坑

- `image/an7581.mk` 里的 `gemtek_xr1710g*` / `gemtek_xg2010g-ubi` / `gemtek_xg2010g-2g-ubi`
  曾被对齐 pbs05 时覆盖掉，导致三个出货配置引用的 profile 全部落空（见 CHANGELOG）。
  合并设备表时务必确认 profile 定义还在。
- `patches/feeds/<feed>/...` 只对 `feeds.conf.default` 里存在的 feed 生效；feed 被移除后
  目录要一起删，否则构建前会打印 "feed is not present" 并跳过。
