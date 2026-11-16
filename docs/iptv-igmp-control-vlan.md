# IPTV 组播控制报文 VLAN

## 背景

`kmod-iptv` 默认把 IPv4/IPv6 组播帧统一打上 `mcast_vid`。这在多数运营商
上没问题，但少数运营商的组播 VLAN 只用于下行直播流，所有上行（DHCP、
认证、VOD、IGMP）都走业务 VLAN。此时 STB 的 IGMP Report 如果被打成组播
VLAN，`pon0` 上没有对应的上行 flow，会在 `airoha_pon_select_flow()` 处
`tx_no_mapping` 丢包，表现为：

- IPTV 盒子能拿到 IP，认证/VOD 正常；
- 直播黑屏；
- `tcpdump -ni pon0 -e -n igmp` 只看到组播 VLAN 的 Report。

## 配置

`/etc/config/iptv`：

```uci
config iptv 'config'
	option enabled '1'
	option uplink 'pon0'
	option name 'itv'
	option service_vid '9'
	option mcast_vid '2060'
	option igmp_vid 'service'   # 或 mcast（默认）
	option macaddr ''
```

- `mcast`（默认）：IGMP/MLD 走 `mcast_vid`，保持原有行为；
- `service`：IGMP/MLD 走 `service_vid`，适用于组播 VLAN 只下行的运营商。

LuCI 的“组播控制报文 VLAN”选项对应这个配置。

## 匹配规则

只把下列报文视为组播控制报文：

- IPv4：`IPPROTO_IGMP`（IGMP v1/v2/v3）；
- IPv6：ICMPv6 类型 130（MLD Query）、131（MLDv1 Report）、
  132（MLDv1 Done）、143（MLDv2 Report）。

其他组播仍走 `mcast_vid`，特别是：

- IPv6 NDP（类型 133–137）；
- IPv6 组播数据；
- mDNS、SSDP 等普通组播。

## 诊断

```sh
# 看 Report 实际从哪个 VLAN 出去
tcpdump -ni pon0 -e -n -vv 'igmp'

# 看 PON 上行是否因没有 flow 丢包
cat /sys/kernel/debug/airoha-xpon-pon0/datapath

# 看 PON 侧 OMCI 报告（仅参考，不依赖自动下发）
ponctl --device pon0 status --json
```

`tx_no_mapping` 增长通常表示所选控制 VLAN 没有上行 flow。选 `service`
后该计数应停止增长。

## 边界

- 暂不支持不带 tag 的 IGMP 上行（OMCI tag control 0 / Transparent）；
- 不依赖 OMCI 自动下发 IGMP VLAN，按运营商实际情况手动选择；
- `itv` 的 RX 仍只解业务/组播两个 VLAN，控制报文选择不新增第三个 VLAN。
