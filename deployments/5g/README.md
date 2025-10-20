# 5G Core Network Deployment

このディレクトリは5Gコアネットワークの新方式デプロイメント構成です。

## 起動方法

```bash
cd /home/taihei/docker_open5gs_sXGP-5G/deployments/5g
docker compose up -d
```

- `.env`ファイルは自動で読み込まれます
- `env_file: ['.env']`で各コンテナにも環境変数が注入されます

## ネットワーク構成
- ブリッジ: `br-open5gs_5g`
- サブネット: `172.23.0.0/24`
- AMF: `${AMF_IP}`
- UPF: `${UPF_IP}`

## 主要サービス
| サービス | IP | ポート | 役割 |
|----------|----|--------|------|
| AMF      | ${AMF_IP} | 38412/sctp | 5G接続管理 |
| UPF      | ${UPF_IP} | 2152/udp   | ユーザプレーン |
| NRF      | ${NRF_IP} | 7777/tcp   | 機能リポジトリ |
| MongoDB  | ${MONGO_IP} | 27017/tcp | DB |
| WebUI    | ${WEBUI_IP} | 9999/tcp  | 管理画面 |

## RAN連携
- gNB: `${SRS_GNB_IP}`
- UE: `${SRS_UE_IP}`

## トラブルシューティング
- `docker compose ps` で状態確認
- `docker compose logs -f amf` でAMFの起動・接続ログ確認
- `docker compose logs -f upf` でUPFのPFCP/GTP-U確認

## 旧構成からの違い
- `.env_5g` → `.env`（自動読み込み）
- `--env-file`不要
- サービスごとに `env_file: ['.env']` で環境変数注入
- パスは `../../` で親ディレクトリ参照

## 詳細は `../README.md` や `MIGRATION_GUIDE.md` を参照してください
