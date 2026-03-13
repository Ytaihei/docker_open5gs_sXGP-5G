# UE設定ディレクトリ構造

このディレクトリは、UE（User Equipment）専用の設定ファイルを管理するために作成されました。
設定ファイルの識別性と管理の効率化を目的としています。

## ディレクトリ構造

```
srsue/
├── 4g/           # 4G UE (LTE) 設定ファイル
│   ├── ue_zmq.conf       # 4G UE メイン設定
│   ├── rb_ue_zmq.conf    # 4G UE RB設定
│   └── sib_ue_zmq.conf   # 4G UE SIB設定
│
└── 5g/           # 5G UE (NR) 設定ファイル
    ├── ue_5g_zmq.conf         # 5G UE メイン設定
    ├── rb_ue_zmq.conf         # 5G UE RB設定（基本）
    ├── rb_ue_5g_zmq.conf      # 5G UE RB設定（5G専用）
    ├── sib_ue_zmq.conf        # 5G UE SIB設定（基本）
    └── sib_ue_5g_zmq.conf     # 5G UE SIB設定（5G専用）
```

## 使用方法

### Docker Compose設定
各UEコンテナは以下のようにsrsueディレクトリをマウントします：

```yaml
volumes:
  - ../ran/srslte:/mnt/srslte     # srsue バイナリ用
  - ../ran/srsue:/mnt/srsue       # UE専用設定ファイル用
```

### 初期化スクリプト
`srslte_init.sh`は以下のように設定ファイルを読み込みます：

- **4G UE (ue_zmq)**: `/mnt/srsue/4g/` から設定を読み込み
- **5G UE (ue_5g_zmq)**: `/mnt/srsue/5g/` から設定を読み込み

## 設定ファイルの編集

UE設定を変更する場合は、このディレクトリ内の適切なファイルを編集してください：

- 4G UE設定: `ran/srsue/4g/` 内のファイルを編集
- 5G UE設定: `ran/srsue/5g/` 内のファイルを編集

## 利点

1. **識別性**: 4G/5Gの設定が明確に分離されている
2. **独立性**: UE設定がeNB/gNB設定から独立している
3. **管理性**: UE専用ディレクトリで設定の管理が容易
4. **互換性**: 既存のsrslte/srsranディレクトリとは独立して動作

## 技術的詳細

- UEバイナリ（srsue）はsrsLTEプロジェクトに含まれているため、srslteのDockerfileを使用
- 設定ファイルのみこの専用ディレクトリから読み込むことで識別性を確保
- 5G UEも内部的にはsrsue（srsLTE）を使用するが、設定は5G用に調整済み
