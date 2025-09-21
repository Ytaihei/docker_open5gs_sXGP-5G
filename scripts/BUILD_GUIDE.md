# Sources Directory Docker Build Scripts

このディレクトリには、`/home/taihei/docker_open5gs_sXGP-5G/sources`配下のソフトウェアをDockerイメージとしてビルドするためのスクリプトが含まれています。

## スクリプト一覧

### 1. `build_all_sources.sh`
**基本的な一括ビルドスクリプト**

すべてのソフトウェアコンポーネントを順次ビルドします。各コンポーネント用のDockerfileが存在しない場合は、自動的に基本的なDockerfileを生成します。

```bash
./scripts/build_all_sources.sh
```

**ビルドされるコンポーネント:**
- SoapySDR（SDRライブラリ）
- bladeRF（BladeRFハードウェアサポート）
- LimeSuite（LimeSDRサポート）
- SoapyBladeRF（BladeRF用SoapySDRプラグイン）
- srsGUI（SDR用GUI）
- Open5GS（5G/4Gコアネットワーク）
- srsRAN_4G（4G RAN）
- srsRAN_Project（5G RAN）

### 2. `build_sources_optimized.sh`
**最適化版ビルドスクリプト**

マルチステージビルドを使用してイメージサイズを最適化し、並列ビルドもサポートします。

```bash
# 基本的な使用方法
./scripts/build_sources_optimized.sh

# 特定のコンポーネントのみビルド
./scripts/build_sources_optimized.sh --target open5gs
./scripts/build_sources_optimized.sh --target srsran5g

# 並列ビルド（実験的）
./scripts/build_sources_optimized.sh --parallel

# キャッシュを無効化
./scripts/build_sources_optimized.sh --no-cache

# ヘルプ表示
./scripts/build_sources_optimized.sh --help
```

**利用可能なターゲット:**
- `sdr`: SDR関連コンポーネント
- `open5gs`: Open5GSコアネットワーク
- `srsran4g`: srsRAN 4G
- `srsran5g`: srsRAN Project (5G)
- `all`: すべてのコンポーネント（デフォルト）

## 前提条件

### 1. ソースコードのダウンロード
```bash
# 完全版（推奨）
./scripts/clone_sources.sh

# 最小版
./scripts/clone_sources_minimal.sh

# シンプル版
./scripts/clone_sources_simple.sh
```

### 2. システム要件
- Docker Engine
- 十分なディスク容量（20GB以上推奨）
- 十分なRAM（8GB以上推奨）

### 3. 依存関係
各コンポーネントの依存関係は自動的にDockerfile内でインストールされます。

## 使用例

### 基本的なワークフロー
```bash
# 1. ソースコードをクローン
cd /home/taihei/docker_open5gs_sXGP-5G
./scripts/clone_sources.sh

# 2. すべてのコンポーネントをビルド
./scripts/build_all_sources.sh

# 3. ビルドされたイメージを確認
docker images | grep docker_
```

### 最適化版を使用したワークフロー
```bash
# 1. Open5GSのみビルド
./scripts/build_sources_optimized.sh --target open5gs

# 2. 5G RANコンポーネントをビルド
./scripts/build_sources_optimized.sh --target srsran5g

# 3. すべてを並列でビルド（高性能マシン向け）
./scripts/build_sources_optimized.sh --parallel
```

## 生成されるDockerイメージ

### 基本版 (`build_all_sources.sh`)
- `docker_soapysdr`
- `docker_bladerf`
- `docker_limesuite`
- `docker_soapybladerf`
- `docker_srsgui`
- `docker_open5gs` ← **YAMLファイルで使用**
- `docker_srslte` ← **YAMLファイルで使用（4G RAN）**
- `docker_srsran` ← **YAMLファイルで使用（5G RAN）**

### 最適化版 (`build_sources_optimized.sh`)
- `docker_soapysdr_optimized`
- `docker_open5gs` ← **YAMLファイルで使用**
- `docker_srslte` ← **YAMLファイルで使用（4G RAN）**
- `docker_srsran` ← **YAMLファイルで使用（5G RAN）**

## デプロイメントでの使用

ビルドしたイメージは、以下のYAMLファイルで直接使用できます：

### 自動的に使用されるイメージ
- **5g-data-only-deploy.yaml**: `docker_open5gs`（ビルド指定）
- **4g-volte-deploy.yaml**: `docker_open5gs`（ビルド指定）
- **srsgnb_zmq.yaml**: `docker_srsran`
- **srsue_zmq.yaml**: `docker_srslte`
- **srsenb_zmq.yaml**: `docker_srslte`

## トラブルシューティング

### 1. ビルド失敗
```bash
# ログを確認
docker build --no-cache --progress=plain ...

# 依存関係の問題の場合、個別にビルド
./scripts/build_sources_optimized.sh --target sdr
./scripts/build_sources_optimized.sh --target open5gs
```

### 2. ディスク容量不足
```bash
# 未使用イメージを削除
docker system prune -a

# 特定のイメージを削除
docker rmi <image_name>
```

### 3. メモリ不足
```bash
# 並列ビルドを無効化
./scripts/build_sources_optimized.sh --target all

# またはmakeのジョブ数を制限（Dockerfile内で -j$(nproc) を -j2 など）
```

## デプロイメントでの使用

ビルドしたイメージをデプロイメントで使用するには、docker-composeファイルでイメージ名を変更します：

```yaml
# 例: 5g-data-only-deploy.yaml
services:
  nrf:
    image: docker_open5gs_optimized  # ← ビルドしたイメージを使用
    # または
    # image: docker_open5gs_sources
```

## パフォーマンス最適化

### マルチステージビルドの利点
- 最終イメージサイズの削減
- ビルド時依存関係の除外
- セキュリティ向上

### 並列ビルドの注意点
- 高いCPU・メモリ使用量
- ビルド失敗時のデバッグが困難
- 十分なシステムリソースが必要

## 関連ファイル
- `/scripts/clone_sources*.sh`: ソースコードクローンスクリプト
- `/deployments/*.yaml`: デプロイメント設定ファイル
- `/sources/`: ソースコードディレクトリ
