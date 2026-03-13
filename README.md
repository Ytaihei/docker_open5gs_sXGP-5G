# open5gs-compose

Docker Compose を使った Open5GS 4G/5G コアネットワークのデプロイ環境です。
[herlesupreeth/docker_open5gs](https://github.com/herlesupreeth/docker_open5gs) をベースに、sXGP / S1-N2 ゲートウェイ対応を追加しています。

## 主な構成要素

| コンポーネント | 説明 |
|---|---|
| **Open5GS** | 4G EPC / 5G SA コアネットワーク |
| **s1n2-gateway** | S1AP ↔ NGAP プロトコル変換ゲートウェイ（git submodule） |
| **srsRAN** | 4G eNB / 5G gNB / UE シミュレータ |

## ディレクトリ構成

```
open5gs-compose/
├── base/                        # Open5GS ベースイメージ (Dockerfile)
├── config/
│   ├── 4g/                      # 4G NF 設定 (hss, mme, pcrf, sgwc, sgwu)
│   └── 5g/                      # 5G NF 設定 (amf, ausf, bsf, nrf, nssf, pcf, scp, smf, udm, udr, upf)
├── db/mongo/                    # MongoDB データ (永続化)
├── log/                         # パケットキャプチャ等 (gitignore)
├── ran/                         # RAN 設定 (srsran, srslte, srsue)
├── s1n2-gateway/                # S1-N2 変換ゲートウェイ (git submodule)
├── script/                      # ビルド・ユーティリティスクリプト
│   └── exclusive_mode.sh        # 排他制御の共通関数
├── webui/                       # Open5GS WebUI 初期化スクリプト
├── docker-compose-4g.yaml       # 4G EPC デプロイ
├── docker-compose-5g.yaml       # 5G SA デプロイ
├── .env-4g.example              # 4G 環境変数テンプレート
├── .env-5g.example              # 5G 環境変数テンプレート
├── start-4g.sh                  # 4G 起動スクリプト (排他制御付き)
└── start-5g.sh                  # 5G 起動スクリプト (排他制御付き)
```

## 前提条件

- Ubuntu 22.04 以上
- [Docker Engine](https://docs.docker.com/engine/install/) 22.0.5+
- [Docker Compose](https://docs.docker.com/compose/) v2.14+
- (OTA テスト時) SDR デバイス (USRP B210, LimeSDR 等)

## クイックスタート

### 1. クローン

```bash
git clone --recursive https://github.com/Ytaihei/open5gs-compose.git
cd open5gs-compose
```

### 2. Docker イメージの準備

ビルド済みイメージを pull:

```bash
docker pull ghcr.io/herlesupreeth/docker_open5gs:master
docker tag  ghcr.io/herlesupreeth/docker_open5gs:master docker_open5gs
```

または、ソースからビルド:

```bash
cd base && docker build -t docker_open5gs . && cd ..
```

### 3. 環境変数の設定

#### 5G SA コアの場合

```bash
cp .env-5g.example .env-5g
# .env-5g を編集し、IP アドレスや SIM 情報を設定
```

#### 4G EPC の場合

```bash
cp .env-4g.example .env-4g
# .env-4g を編集し、IP アドレスや SIM 情報を設定
```

> **注意**: `.env` ファイルには SIM の Ki/OP 等の秘匿情報が含まれます。Git にコミットしないでください。

### 4. 起動

3 つの構成は**排他的に動作**します。どの起動スクリプトを実行しても、他の構成を自動停止しネットワーク競合を解消してから起動します。プロジェクトルートから実行してください。

#### 4G EPC（物理 eNB + ZMQ シミュレータ）

```bash
./start-4g.sh
```

- `eno1` を `br-open5gs_4g` に自動接続し、物理 eNB と通信可能にします
- 停止: `docker compose -f docker-compose-4g.yaml down`
- ログ: `docker compose -f docker-compose-4g.yaml logs -f mme-4g`

#### 5G SA コア（ソフトウェア RAN）

```bash
# UERANSIM を使用（デフォルト）
./start-5g.sh

# srsRAN を使用
./start-5g.sh srsran
```

- 物理 NIC は不使用（`eno1` をすべてのブリッジから切断）
- 停止: `docker compose -f docker-compose-5g.yaml down`
- ログ (ueransim): `docker compose -f docker-compose-5g.yaml logs -f ueransim_ue ueransim_gnb amf`
- ログ (srsran): `docker compose -f docker-compose-5g.yaml logs -f srsue_5g_zmq srsgnb_zmq amf`

5G RAN プロファイル:

| プロファイル | gNB | UE | 特徴 |
|---|---|---|---|
| `ueransim` | UERANSIM gNB | UERANSIM UE | 軽量、安定、5Gコア検証向け |
| `srsran` | srsRAN Project gNB | srsRAN 4G UE | ZMQベースでPHY寄りの検証向け |

プロファイル切替:

```bash
# 停止
docker compose -f docker-compose-5g.yaml down

# 別プロファイルで起動
./start-5g.sh srsran   # または ueransim
```

動作確認（5G）:

```bash
# UERANSIM
docker logs ueransim_ue --tail 100
docker exec ueransim_ue ping -I uesimtun0 -c 4 8.8.8.8

# srsRAN
docker logs srsue_5g_zmq --tail 100
docker exec srsue_5g_zmq ping -I tun_srsue -c 4 8.8.8.8
```

5G RAN の既知の制約:

- UERANSIM: 物理層なし（IP層シミュレーション）
- srsRAN: 組み合わせや設定によっては UE が PLMN-SEARCH で停止する場合あり

#### S1-N2 ゲートウェイ（sXGP 用 — 物理 eNB + 5GC）

```bash
./s1n2-gateway/start.sh
```

- `eno1` を `br-s1n2-gw` に自動接続し、物理 eNB と通信可能にします
- 停止: `cd s1n2-gateway && docker compose down`
- ログ: `docker logs -f s1n2`
- 詳細は [s1n2-gateway/README.md](s1n2-gateway/README.md) を参照

> **排他制御の仕組み**: 各起動スクリプトは `script/exclusive_mode.sh` の共通関数を使い、
> (1) 他の全構成のコンテナ停止 → (2) 競合する Docker ネットワーク削除 → (3) NIC の NetworkManager プロファイル切替 → (4) 不要なブリッジ IP 除去 の順で実行します。

### 5. SIM 情報の登録

Open5GS WebUI (`http://<WEBUI_IP>:9999`) にアクセスし、IMSI・Ki・OPc を登録してください。

デフォルトの WebUI 認証情報:
- ユーザー名: `admin`
- パスワード: `1423`

## ネットワーク構成

### 5G SA (docker-compose-5g.yaml)
- 内部ネットワーク: `172.23.0.0/24`

### 4G EPC (docker-compose-4g.yaml)
- 内部ネットワーク: `172.24.0.0/16` (`br-open5gs_4g`, GW `172.24.1.1`)

### S1-N2 ゲートウェイ (s1n2-gateway/docker-compose.yml)
- 内部ネットワーク: `172.24.0.0/16` (`br-s1n2-gw`)
- N6 ネットワーク: `172.25.0.0/24` (`br-s1n2-gw-n6`)

## スクリプト一覧

起動・ビルドスクリプトはリポジトリに含まれていません。
詳細は [Wiki](https://github.com/Ytaihei/docker_open5gs_sXGP-5G/wiki) を参照し、ローカルに配置してください。

| スクリプト | 説明 |
|---|---|
| `start-4g.sh` | 4G EPC 起動（排他制御付き） |
| `start-5g.sh` | 5G SA 起動（排他制御付き） |
| `s1n2-gateway/start.sh` | S1-N2 ゲートウェイ起動（排他制御付き） |
| `script/exclusive_mode.sh` | 排他制御の共通関数（各起動スクリプトが source） |
| `script/build_essential.sh` | 必要最小限の Docker イメージをビルド |
| `script/clone_sources.sh` | ソースコードを `sources/` に取得 |

## ベースリポジトリ

このプロジェクトは [herlesupreeth/docker_open5gs](https://github.com/herlesupreeth/docker_open5gs) をベースにしています。

## ライセンス

[BSD-2-Clause](LICENSE)
