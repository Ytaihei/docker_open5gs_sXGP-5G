# 4G構成 起動手順

## 概要
このドキュメントでは、実eNB (Baicells) と接続する4G構成の起動手順を説明します。

## ネットワーク構成
- **4G Core Network**: `172.24.1.0/24`
  - MME: `172.24.1.40`
  - HSS: `172.24.1.10`
  - SGWC: `172.24.1.20`
  - SGWU: `172.24.1.21`
  - SMF: `172.24.1.30`
  - UPF: `172.24.1.31`
  - PCRF: `172.24.1.11`
  - MongoDB: `172.24.1.2`
  - WebUI: `172.24.1.3`

- **eNB Network**: `172.24.0.0/24`
  - eNB: `172.24.0.111` (固定)

- **Bridge Interface**: `br-open5gs_4g`
  - ゲートウェイ: `172.24.1.1` (Dockerホスト)
  - セカンダリIP: `172.24.0.1` (eNB通信用)

## 起動手順

### 1. 既存の5G構成を停止（必要な場合）
```bash
cd /home/taihei/docker_open5gs_sXGP-5G/deployments/5g
docker compose down
```

### 2. Dockerネットワークの準備
既存のネットワークがある場合は削除して再作成：
```bash
# 既存ネットワークを削除（初回は不要）
docker network rm br-open5gs_4g

# 新しいネットワークを作成
docker network create --driver=bridge --subnet=172.24.1.0/24 --gateway=172.24.1.1 br-open5gs_4g
```

### 3. 物理インターフェースをブリッジに接続
```bash
# eno1をbr-open5gs_4gに接続
sudo ip link set eno1 master br-open5gs_4g

# ブリッジにeNB通信用のIPを追加
sudo ip addr add 172.24.0.1/24 dev br-open5gs_4g

# ブリッジに4G Core用のIPを追加（docker network createで自動設定されるが念のため）
sudo ip addr add 172.24.1.1/24 dev br-open5gs_4g
```

### 4. ブリッジ設定の確認
```bash
# ブリッジのIPアドレスを確認
ip addr show br-open5gs_4g

# 期待される出力:
# 5: br-open5gs_4g: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
#     inet 172.24.0.1/24 scope global br-open5gs_4g
#     inet 172.24.1.1/24 scope global br-open5gs_4g

# 物理インターフェースの接続を確認
ip link show master br-open5gs_4g

# 期待される出力:
# 2: eno1: <BROADCAST,MULTICAST,UP,LOWER_UP> ... master br-open5gs_4g
```

### 5. eNBへの疎通確認
```bash
ping -c 2 172.24.0.111
```

成功すれば次のステップへ。失敗する場合：
- eNBの電源が入っているか確認
- eNBのIPが `172.24.0.111` に設定されているか確認
- eno1が正しくブリッジに接続されているか確認

### 6. 4G Core Networkの起動
```bash
cd /home/taihei/docker_open5gs_sXGP-5G/deployments/4g
docker compose up -d
```

### 7. コンテナ起動確認
```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

期待される出力（9個のコンテナ）：
- mme
- hss
- pcrf
- webui
- sgwc
- sgwu
- smf
- upf
- mongo

### 8. MMEのIPアドレス確認
```bash
docker exec mme ip addr show eth0
```

期待される出力：
```
inet 172.24.1.40/24 brd 172.24.1.255 scope global eth0
```

### 9. MMEログの確認
```bash
docker logs -f mme
```

正常起動のメッセージを確認：
- `Open5GS daemon v2.x.x`
- `mme_s1ap_init()`
- `s1ap_server() [0.0.0.0]:36412`

## eNB設定

### eNB WebUIへのアクセス
ラップトップから以下のコマンドでSSHポートフォワーディング：
```bash
ssh -p 2002 -L 8443:172.24.0.111:443 taihei-nuc-ubuntu
```

その後、ブラウザで `https://localhost:8443` にアクセス。

### eNB必須設定項目
eNB WebUIで以下を設定：

1. **MME IP Address**: `172.24.1.40`
2. **eNB IP Address**: `172.24.0.111` (既に設定済みの場合は変更不要)
3. **PLMN**:
   - MCC: `001`
   - MNC: `01`
4. **TAC**: `1`

設定後、eNBを再起動。

## Attach テスト準備

### パケットキャプチャの開始
別ターミナルで：
```bash
cd /home/taihei/docker_open5gs_sXGP-5G
sudo tcpdump -i br-open5gs_4g -w log/4g_attach_$(date +%Y%m%d_%H%M%S).pcap \
  'sctp port 36412 or (udp port 2152 and host 172.24.1.21)'
```

キャプチャ対象：
- `sctp port 36412`: S1AP (eNB ↔ MME)
- `udp port 2152`: GTP-U (eNB ↔ SGWU)
- `host 172.24.1.21`: SGWU (データプレーン)

### 詳細ログの有効化（オプション）
MMEの詳細ログを確認したい場合：
```bash
docker exec -it mme tail -f /open5gs/install/var/log/open5gs/mme.log
```

### UE情報の登録確認
Open5GS WebUI (`http://<ホストIP>:9999`) で以下を確認：
- IMSI: `001011234567895`
- K (Ki): `8baf473f2f8fd09487cccbd7097c6862`
- OPc: `8e27b6af0e692e750f32667a3b14605d`
- APN: `internet`

## Attachテストの実行

1. UE (Google Pixel 8a) の電源を入れる
2. ネットワーク設定で4G/LTE専用モードに設定（可能であれば）
3. キャリア選択で手動検索 → MCC001-MNC01を選択
4. Attachプロセスを観察

## ログ収集

### S1APメッセージの確認
```bash
tshark -r log/4g_attach_*.pcap -Y "s1ap" -V > log/4g_s1ap_analysis.txt
```

### Authentication/Security関連の抽出
```bash
tshark -r log/4g_attach_*.pcap -Y "nas_eps.nas_msg_emm_type == 0x52 or \
  nas_eps.nas_msg_emm_type == 0x53 or \
  nas_eps.nas_msg_emm_type == 0x5d or \
  nas_eps.nas_msg_emm_type == 0x5e" -V > log/4g_security_flow.txt
```

NASメッセージタイプ：
- `0x52`: Authentication Request
- `0x53`: Authentication Response
- `0x5d`: Security Mode Command
- `0x5e`: Security Mode Complete

### Initial Context Setup関連
```bash
tshark -r log/4g_attach_*.pcap -Y "s1ap.procedureCode == 9" -V > log/4g_ics_messages.txt
```

### MMEログの保存
```bash
docker logs mme > log/4g_mme_$(date +%Y%m%d_%H%M%S).log 2>&1
```

## トラブルシューティング

### eNBに到達できない
```bash
# ブリッジの状態確認
ip link show br-open5gs_4g

# eno1がブリッジに接続されているか確認
ip link show master br-open5gs_4g | grep eno1

# 再接続
sudo ip link set eno1 nomaster
sudo ip link set eno1 master br-open5gs_4g
```

### MMEがS1AP接続を受け付けない
```bash
# MMEのポート確認
docker exec mme netstat -nap | grep 36412

# ファイアウォール確認
sudo iptables -L -n | grep 36412

# MME再起動
docker restart mme
```

### Attach失敗時の確認事項
1. **Authentication失敗**: HSS/WebUIのUE登録情報（Ki, OPc）を確認
2. **Security Mode失敗**: 暗号化・完全性保護アルゴリズムの不一致を確認
3. **Initial Context Setup失敗**: KeNB、セキュリティアルゴリズム、UE Capability情報を確認

## 停止手順

### 4G構成の停止
```bash
cd /home/taihei/docker_open5gs_sXGP-5G/deployments/4g
docker compose down
```

### ネットワークのクリーンアップ（必要な場合）
```bash
# 物理インターフェースをブリッジから切り離し
sudo ip link set eno1 nomaster

# ブリッジネットワークの削除
docker network rm br-open5gs_4g
```

## 備考

### sXGP-5G構成への切り替え
4G構成からsXGP-5G構成に切り替える場合：

```bash
# 4G構成を停止
cd /home/taihei/docker_open5gs_sXGP-5G/deployments/4g
docker compose down

# 5G構成のネットワーク準備
docker network create --driver=bridge --subnet=172.24.0.0/16 --gateway=172.24.0.1 br-sXGP-5G

# eno1を5Gブリッジに接続
sudo ip link set eno1 nomaster
sudo ip link set eno1 master br-sXGP-5G

# 5G構成を起動
cd /home/taihei/docker_open5gs_sXGP-5G/sXGP-5G
docker compose up -d
```

### IP構成の設計方針
- **172.24.0.x**: eNB固定IP、5G構成用（sXGP-5G）
- **172.24.1.x**: 4G Core Network専用
- この分離により、eNBのIP変更なしに4G/5G構成を切り替え可能

### パフォーマンスチューニング
長時間の安定稼働が必要な場合：
```bash
# コンテナリソース制限の確認
docker stats

# ログローテーション設定
# /etc/docker/daemon.json に追加:
# {
#   "log-driver": "json-file",
#   "log-opts": {
#     "max-size": "10m",
#     "max-file": "3"
#   }
# }
```

## 関連ドキュメント
- [4G構成README](./README.md)
- [Network Setup Guide](./README_NETWORK_SETUP.md)
- [sXGP-5G構成との比較](../MIGRATION_GUIDE.md)
