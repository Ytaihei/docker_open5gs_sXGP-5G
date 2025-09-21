# 4G LTE構成の設定ファイル構造ガイド

## 概要

このドキュメントは、docker_open5gs_sXGP-5Gプロジェクトにおける4G LTE構成の設定ファイル構造とその参照関係について詳述します。2025年9月16日時点での動作確認済み構成です。

## アーキテクチャ概要

```
UE (srsUE) <--RF--> eNodeB (srsENB) <--S1AP--> MME <--S6a--> HSS
                       |                        |
                       |--GTP-U--> SGW-U <---> UPF
                       |           |
                       |--GTP-C--> SGW-C <--Gx--> PCRF
                                   |
                                   |--S11--> MME
```

## ディレクトリ構造

### プロジェクトルート
```
/home/taihei/docker_open5gs_sXGP-5G/
├── deployments/
│   ├── 4g-data-only-deploy.yaml    # 4G構成Docker Compose
│   └── .env_4g                     # 4G環境変数
├── ran/
│   ├── srslte/                     # 4G eNB用設定ファイル
│   └── srsue/
│       └── 4g/                     # 4G UE専用設定ファイル
├── 4g/                             # Open5GS 4Gコア設定
└── open5gs/                        # Open5GS共通設定
```

### RAN設定ディレクトリ詳細
```
ran/
├── srslte/                         # 4G eNodeB用
│   ├── Dockerfile                  # srsLTE構築用
│   ├── srslte_init.sh             # 初期化スクリプト
│   ├── enb_zmq.conf               # eNB ZMQ設定
│   ├── rb_enb_zmq.conf            # eNB Radio Bearer設定
│   ├── rr_enb_zmq.conf            # eNB Radio Resource設定
│   └── sib_enb_zmq.conf           # eNB System Information設定
└── srsue/
    └── 4g/                        # 4G UE専用
        ├── ue_zmq.conf            # UE主設定
        ├── rb_ue_zmq.conf         # UE Radio Bearer設定
        └── sib_ue_zmq.conf        # UE System Information設定
```

## 設定ファイル参照フロー

### 1. Docker Compose設定

**ファイル**: `deployments/4g-data-only-deploy.yaml`

#### eNodeB (srsenb_zmq)
```yaml
srsENB_zmq:
  build:
    dockerfile: ran/srslte/Dockerfile
  volumes:
    - ../ran/srslte:/mnt/srslte      # eNB設定マウント
  environment:
    - COMPONENT_NAME=enb_zmq
```

#### UE (srsue_zmq)
```yaml
srsue_zmq:
  build:
    dockerfile: ran/srslte/Dockerfile
  volumes:
    - ../ran/srslte:/mnt/srslte      # バイナリ用
    - ../ran/srsue:/mnt/srsue        # UE専用設定マウント
  environment:
    - COMPONENT_NAME=ue_zmq
```

### 2. 初期化スクリプト処理

**ファイル**: `ran/srslte/srslte_init.sh`

#### eNodeB設定コピー
```bash
elif [[ "$COMPONENT_NAME" =~ ^(enb_zmq[[:digit:]]*$) ]]; then
    cp /mnt/srslte/rb_${COMPONENT_NAME}.conf /etc/srsran/rb.conf
    cp /mnt/srslte/rr_${COMPONENT_NAME}.conf /etc/srsran/rr.conf
    cp /mnt/srslte/sib_${COMPONENT_NAME}.conf /etc/srsran/sib.conf
    cp /mnt/srslte/${COMPONENT_NAME}.conf /etc/srsran/enb.conf
```

#### UE設定コピー (修正版)
```bash
elif [[ "$COMPONENT_NAME" =~ ^(ue_zmq[[:digit:]]*$) ]]; then
    echo "Configuring component: '$COMPONENT_NAME' from dedicated UE config directory"
    cp /mnt/srsue/4g/rb_ue_zmq.conf /etc/srsran/rb.conf
    cp /mnt/srsue/4g/sib_ue_zmq.conf /etc/srsran/sib.conf
    cp /mnt/srsue/4g/ue_zmq.conf /etc/srsran/ue.conf
```

## 環境変数 (.env_4g)

### ネットワーク設定
```bash
MCC=001                            # Mobile Country Code
MNC=01                             # Mobile Network Code
TAC=1                              # Tracking Area Code
TEST_NETWORK=172.22.0.0/24         # Docker内部ネットワーク
```

### IPアドレス割り当て
```bash
# Core Network
MME_IP=172.22.0.9                  # MME (Mobility Management Entity)
HSS_IP=172.22.0.3                  # HSS (Home Subscriber Server)
SGWC_IP=172.22.0.5                 # SGW-C (Serving Gateway Control)
SGWU_IP=172.22.0.6                 # SGW-U (Serving Gateway User)
UPF_IP=172.22.0.8                  # UPF (User Plane Function)
PCRF_IP=172.22.0.4                 # PCRF (Policy Control and Rules Function)

# RAN
SRS_ENB_IP=172.22.0.22             # eNodeB
SRS_UE_IP=172.22.0.34              # UE

# UE Data Network
UE_IPV4_INTERNET=192.168.100.0/24  # UE用IPアドレス範囲
```

### 認証情報
```bash
UE1_IMSI=001011234567895            # UE識別子
UE1_KI=8baf473f2f8fd09487cccbd7097c6862  # 認証鍵
UE1_OP=11111111111111111111111111111111  # オペレータ鍵
```

## 主要設定ファイル詳細

### 1. eNodeB設定 (enb_zmq.conf)

```ini
[enb]
enb_id = 0x19B
mcc = 001
mnc = 01
mme_addr = 172.22.0.9              # MME接続先
gtp_bind_addr = 172.22.0.22        # GTP-U待受アドレス
s1c_bind_addr = 172.22.0.22        # S1-C待受アドレス

[rf]
device_name = zmq
device_args = fail_on_disconnect=true,tx_port=tcp://172.22.0.22:2000,rx_port=tcp://172.22.0.34:2001,id=enb,base_srate=23.04e6

[pcap]
enable = false
filename = /mnt/srslte/enb.pcap
```

### 2. UE設定 (ue_zmq.conf)

```ini
[rf]
device_name = zmq
device_args = tx_port=tcp://172.22.0.34:2001,rx_port=tcp://172.22.0.22:2000,id=ue,base_srate=23.04e6

[rat.eutra]
dl_earfcn = 3350                   # ダウンリンク周波数

[usim]
mode = soft
algo = milenage
op  = 11111111111111111111111111111111
k   = 8baf473f2f8fd09487cccbd7097c6862
imsi = 001011234567895
imei = 353490069873319

[nas]
apn = internet                     # アクセスポイント名
apn_protocol = ipv4

[gw]
ip_devname = tun_srsue             # TUNインターフェース名
```

## ZMQ RF通信設定

### 通信フロー
```
UE (172.22.0.34) <---ZMQ-TCP---> eNodeB (172.22.0.22)
     TX: :2001  <---------------->  RX: :2001
     RX: :2000  <---------------->  TX: :2000
```

### ポート設定
- **eNodeB→UE**: `tx_port=tcp://172.22.0.22:2000` → `rx_port=tcp://172.22.0.22:2000`
- **UE→eNodeB**: `tx_port=tcp://172.22.0.34:2001` → `rx_port=tcp://172.22.0.34:2001`

## プロトコルインターフェース

### S1-AP (eNodeB ↔ MME)
- **ポート**: 36412/SCTP
- **アドレス**: 172.22.0.22 ↔ 172.22.0.9

### GTP-U (eNodeB ↔ SGW-U)
- **ポート**: 2152/UDP
- **アドレス**: 172.22.0.22 ↔ 172.22.0.6

### S6a/Diameter (MME ↔ HSS)
- **ポート**: 3868/SCTP
- **アドレス**: 172.22.0.9 ↔ 172.22.0.3

## 動作確認手順

### 1. 4G構成の起動
```bash
cd /home/taihei/docker_open5gs_sXGP-5G/deployments
docker compose --env-file .env_4g -f 4g-data-only-deploy.yaml up -d
```

### 2. 接続確認
```bash
# UE接続確認
docker logs srsue_zmq | grep -E "(connected|attach)"

# eNB接続確認
docker logs srsenb_zmq | grep -E "(User.*connected|RACH)"

# TUNインターフェース確認
docker exec srsue_zmq ip addr show tun_srsue
```

### 3. 設定ファイル確認
```bash
# UE設定確認
docker exec srsue_zmq ls -la /etc/srsran/
docker exec srsue_zmq grep -E "(imsi|device_args)" /etc/srsran/ue.conf

# eNB設定確認
docker exec srsenb_zmq grep -E "(mcc|mme_addr)" /etc/srsran/enb.conf
```

## トラブルシューティング

### 設定ファイル参照エラー
- **症状**: 設定ファイルが見つからない
- **確認**: `docker exec [container] ls -la /mnt/`でマウント確認
- **解決**: ボリュームマウント設定確認

### UE接続失敗
- **症状**: UEがeNBに接続できない
- **確認**: ZMQ通信設定、認証情報
- **解決**: IPアドレス、ポート設定確認

### 認証失敗
- **症状**: UEが認証を通らない
- **確認**: IMSI、Ki、OPc設定
- **解決**: HSS加入者情報との整合性確認

## 修正履歴

- **2025-09-16**: 初版作成
- **2025-09-16**: UE設定ファイル参照を専用ディレクトリ(/ran/srsue/4g/)に修正
- **2025-09-16**: 動作確認完了（UE接続、IP割り当て成功）

## 関連ドキュメント

- [5G設定構造ガイド](./5G_CONFIG_STRUCTURE_GUIDE.md) (作成予定)
- [PROJECT_STRUCTURE.md](./PROJECT_STRUCTURE.md)
- [TESTING_RESULTS.md](./TESTING_RESULTS.md)
