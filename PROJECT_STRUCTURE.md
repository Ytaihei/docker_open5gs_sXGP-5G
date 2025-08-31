# Docker Open5GS sXGP-5G - 整理後プロジェクト構造

このプロジェクトは4G・5Gコア機能と管理用ディレクトリを機能別に整理し、データ通信に特化したデプロイメントを提供します。

## ディレクトリ構造

```
docker_open5gs_sXGP-5G/
├── 4g/                    # 4Gコア機能
│   ├── hss/              # Home Subscriber Server
│   ├── mme/              # Mobility Management Entity
│   ├── pcrf/             # Policy and Charging Rules Function
│   ├── sgwc/             # Serving Gateway Control Plane
│   └── sgwu/             # Serving Gateway User Plane
├── 5g/                    # 5Gコア機能
│   ├── amf/              # Access and Mobility Management Function
│   ├── ausf/             # Authentication Server Function
│   ├── bsf/              # Binding Support Function
│   ├── nrf/              # Network Repository Function
│   ├── nssf/             # Network Slice Selection Function
│   ├── pcf/              # Policy Control Function
│   ├── scp/              # Service Communication Proxy
│   ├── smf/              # Session Management Function
│   ├── udm/              # Unified Data Management
│   ├── udr/              # Unified Data Repository
│   └── upf/              # User Plane Function
├── open5gs/               # Open5GS共通基盤
│   ├── base/             # Docker基盤イメージ
│   └── webui/            # Web管理インターフェース
├── ran/                   # 無線アクセスネットワーク
│   ├── srslte/           # srsLTE (4G)
│   └── srsran/           # srsRAN (5G)
├── deployments/           # デプロイメント設定
│   ├── 4g-data-only-deploy.yaml    # 4G データ専用
│   ├── 5g-data-only-deploy.yaml    # 5G データ専用
│   ├── 4g-volte-deploy.yaml        # 4G VoLTE対応
│   ├── sa-deploy.yaml              # 5G SA展開
│   └── srs*.yaml                   # srsRAN設定
├── scripts/               # 管理スクリプト
│   ├── build-docker-images.sh      # Dockerイメージビルド
│   ├── build_from_source.sh        # ソースビルド
│   ├── clone_sources.sh            # ソースクローン
│   └── update_deployment_paths.sh  # パス更新
├── log/                   # ログディレクトリ
└── sources/               # ソースコード
```

## クイックスタート

### 1. ソースコードの取得
```bash
./scripts/clone_sources.sh
```

### 2. Dockerイメージのビルド
```bash
./scripts/build-docker-images.sh
```

### 3. 4Gデータ通信の開始
```bash
cd deployments/
docker compose -f 4g-data-only-deploy.yaml up -d
```

### 4. 5Gデータ通信の開始
```bash
cd deployments/
docker compose -f 5g-data-only-deploy.yaml up -d
```

### 5. Web管理画面アクセス
ブラウザで http://localhost:9999 にアクセス

## 主な変更点

- **機能別ディレクトリ分離**: 4G/5G/共通/RAN/管理でディレクトリを分離
- **データ通信特化**: VoLTE/SMS/IMS関連コンポーネントを削除
- **ソースベースビルド**: 完全にローカルソースからのビルドに対応
- **パス管理**: デプロイメントファイルから相対パスで各コンポーネントを参照

## 注意事項

- デプロイメントは `deployments/` ディレクトリから実行してください
- `.env` ファイルはプロジェクトルートに配置されています
- ログは `../log/` ディレクトリに出力されます
