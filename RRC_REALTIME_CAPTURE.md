# RRC Real-time Data Capture Guide

## Overview
eNBからRRCメッセージをリアルタイムでこのマシンに送信し、キャプチャ・解析する方法。

## Network Configuration

### このマシンの接続情報
- **IPアドレス**: `172.24.0.1`
- **受信ポート**: `4337` (UDP)
- **ネットワークインターフェース**: `br-sXGP-5G` (bridge)
- **物理インターフェース**: `eno1` (bridge member)

### eNB側の設定
eNBの管理画面で以下を設定：
- **RRC送信先IPアドレス**: `172.24.0.1`
- **RRC送信先ポート**: `4337`
- **プロトコル**: UDP
- **フォーマット**: PDCP-LTE (Wireshark互換)

## Capture Methods

### Method 1: リアルタイム監視（ターミナル表示）

UE接続中にRRCメッセージをリアルタイム表示：

```bash
sudo tcpdump -i br-sXGP-5G -n port 4337 -XX -vv
```

オプション説明：
- `-i br-sXGP-5G`: ブリッジインターフェースで監視
- `-n`: ホスト名解決しない（高速化）
- `port 4337`: ポート4337のパケットのみ
- `-XX`: ペイロードを16進数+ASCII表示
- `-vv`: 詳細表示

**停止方法**: `Ctrl+C`

### Method 2: pcapファイルに保存（推奨）

後でWiresharkで詳細解析できる形式で保存：

```bash
# 30秒間キャプチャ
sudo timeout 30 tcpdump -i br-sXGP-5G -n port 4337 -w /home/taihei/docker_open5gs_sXGP-5G/log/$(date +%Y%m%d_%H%M%S)_rrc.pcap

# または手動停止（Ctrl+Cで停止）
sudo tcpdump -i br-sXGP-5G -n port 4337 -w /home/taihei/docker_open5gs_sXGP-5G/log/$(date +%Y%m%d_%H%M%S)_rrc.pcap
```

### Method 3: パケット数制限キャプチャ

特定のパケット数だけキャプチャ：

```bash
# 最初の20パケットのみ
sudo tcpdump -i br-sXGP-5G -n port 4337 -c 20 -w /home/taihei/docker_open5gs_sXGP-5G/log/rrc_capture.pcap
```

## Analysis Methods

### Quick Analysis: tsharkでパケット確認

```bash
# パケット数とサイズを確認
tshark -r /path/to/rrc.pcap -T fields -e frame.number -e frame.len -e udp.length

# 大きなパケット（RRC Reconfiguration候補）を抽出
tshark -r /path/to/rrc.pcap -Y "udp.length > 100" -T fields -e frame.number -e udp.length -e data.data

# 生データ表示
tshark -r /path/to/rrc.pcap -x
```

### Detailed Analysis: RRCメッセージ解析

PDCP-LTEヘッダー後のRRCメッセージ抽出例：

```bash
# hexデータからバイナリ変換
echo "<hex_data>" | xxd -r -p | xxd -g 1
```

### Wireshark GUI分析

1. pcapファイルをWiresharkで開く
2. フィルタ: `udp.port == 4337`
3. PDCP-LTE形式として認識される
4. RRCメッセージツリーで詳細確認

## RRC Message Types (参考)

### DL-DCCH Messages (Downlink Dedicated Control Channel)
- `0x20`: **RRCConnectionReconfiguration** - ICS後に送信される重要メッセージ
- `0x28`: RRCConnectionRelease
- `0x30`: SecurityModeCommand
- `0x38`: UEInformationRequest

### UL-DCCH Messages (Uplink Dedicated Control Channel)
- `0x21`: RRCConnectionReconfigurationComplete - UEからの成功応答
- `0x31`: SecurityModeComplete
- `0x39`: SecurityModeFailure

## Typical Packet Sizes

接続フロー中の典型的なパケットサイズ：
- **45-73 bytes**: 小さな制御メッセージ
- **100-175 bytes**: **RRC Connection Reconfiguration** (ICS後)
- **500-600 bytes**: UE Capability Information

## Integration with S1AP Analysis

RRCとS1APを同時解析する場合：

```bash
# S1AP + RRCを同時キャプチャ
sudo tcpdump -i br-sXGP-5G -w /path/to/combined.pcap \
  'sctp port 36412 or sctp port 38412 or udp port 4337'
```

フィルタ：
- `sctp port 36412`: S1AP (4G)
- `sctp port 38412`: NGAP (5G)
- `udp port 4337`: RRC (eNBからの送信)

## Troubleshooting

### パケットが見えない場合

1. **eNB設定確認**:
   - 送信先IP: `172.24.0.1` が正しいか
   - 送信先ポート: `4337` が正しいか
   - RRC送信機能が有効か

2. **ネットワーク接続確認**:
   ```bash
   # ブリッジ設定確認
   ip addr show br-sXGP-5G

   # eNBからpingテスト
   ping 172.24.0.111  # eNBのIP
   ```

3. **ファイアウォール確認**:
   ```bash
   # ポート4337が開いているか
   sudo iptables -L -n | grep 4337
   ```

### PDCP-LTE形式が認識されない場合

Wiresharkの設定：
1. Edit → Preferences → Protocols → PDCP-LTE
2. "Try to decode signalling plane data" を有効化

## Example Session

実際のキャプチャセッション例：

```bash
# 1. キャプチャ開始
echo "Capturing RRC data. Please connect UE now..."
sudo tcpdump -i br-sXGP-5G -n port 4337 -w /home/taihei/docker_open5gs_sXGP-5G/log/20251112_rrc.pcap &
TCPDUMP_PID=$!

# 2. UEを接続（別ターミナルまたは手動）

# 3. キャプチャ停止（30秒後 or Ctrl+C）
sleep 30
sudo kill $TCPDUMP_PID

# 4. 簡易確認
tshark -r /home/taihei/docker_open5gs_sXGP-5G/log/20251112_rrc.pcap -Y "udp.length > 100" | wc -l
# RRC Reconfigurationらしきパケット数が表示される

# 5. 詳細分析（Wiresharkで開く）
```

## Known Issues

### ICS Failure (Cause 26) との関連

**Symptom**: S1AP ICS RequestにRRC Reconfigurationが続くが、UEからReconfiguration Completeが返らず、ICS Failureになる

**RRC確認ポイント**:
1. eNBがRRC Connection Reconfigurationを**送信している**か → RRCキャプチャで確認
2. UEがRRC Connection Reconfiguration Completeを**返している**か → pcapには出ない（無線）

**分析方法**:
- RRCキャプチャでReconfigurationメッセージ（~155-175 bytes）を確認
- S1APキャプチャでICS RequestのタイミングとRRC送信タイミングを比較
- Security header type（暗号化の有無）を確認

## Related Files

- S1AP/NGAPキャプチャ: `/home/taihei/docker_open5gs_sXGP-5G/log/YYYYMMDD_N.pcap`
- RRCキャプチャ: `/home/taihei/docker_open5gs_sXGP-5G/log/YYYYMMDD_HHMMSS_rrc.pcap`
- s1n2ログ: `docker logs s1n2`

## References

- 3GPP TS 36.331: RRC Protocol Specification
- 3GPP TS 36.323: PDCP Specification
- Wireshark PDCP-LTE dissector documentation
