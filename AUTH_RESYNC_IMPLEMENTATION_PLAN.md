# Authentication Re-Synchronization 実装方針
## 2025-11-18

---

## 現状の実装状況

### ✅ 実装済み機能

#### 1. AUTS解析機能 (`s1n2_nas.c` Line 1554-1603)
```c
// 4G Authentication Failure (0x5C) → 5G Authentication Failure (0x59) 変換
if (msg_type == 0x5C) {
    // AUTS (14 bytes) を抽出
    // UEの期待SQNをデコード: SQN_MS = (SQN_MS⊕AK) ⊕ AK
    if (s1n2_decode_auts_sqn(keys->opc, keys->ki, ue_map->rand, auts, sqn_ms) == 0) {
        uint64_t sqn_value = 0;
        for (int i = 0; i < 6; i++) {
            sqn_value = (sqn_value << 8) | sqn_ms[i];
        }

        // MongoDB更新コマンドをログに出力
        printf("[INFO] To resolve Sync Failure, update MongoDB:\n");
        printf("[INFO]   docker exec -it mongo-s1n2 mongosh --quiet open5gs \\\n");
        printf("[INFO]     --eval 'db.subscribers.updateOne({imsi: \"%s\"}, \\\n", ue_map->imsi);
        printf("[INFO]     {$set: {\"security.sqn\": NumberLong(\"%lu\")}})'\n", sqn_value + 1000);
    }
}
```

**動作:**
- ✅ 4G Authentication Failure (AUTS付き) を検出
- ✅ AUTSトークン(14 bytes)を抽出
- ✅ Milenage f5を使ってAK計算
- ✅ UEの期待SQN値をデコード
- ✅ MongoDB更新コマンドをログ出力
- ❌ **MongoDB更新は実行しない** (手動運用)

#### 2. AUTS転送機能 (`s1n2_nas.c` Line 1528-1552)
```c
// 5G Authentication Failure メッセージ構築
nas_5g[nas_5g_offset++] = 0x7E; // EPd: 5GMM
nas_5g[nas_5g_offset++] = 0x00; // Security header type: plain
nas_5g[nas_5g_offset++] = 0x59; // Message type: Authentication failure
nas_5g[nas_5g_offset++] = emm_cause; // 5GMM cause (21=Synch failure)

if (has_auts) {
    nas_5g[nas_5g_offset++] = 0x30; // IEI: Authentication failure parameter
    nas_5g[nas_5g_offset++] = 14;   // Length
    memcpy(nas_5g + nas_5g_offset, auts, 14);
    nas_5g_offset += 14;
}
```

**動作:**
- ✅ 4G Authentication Failure → 5G Authentication Failure 変換
- ✅ AUTSをAMFへ透過的に転送
- ✅ 3GPP TS 24.501準拠のメッセージフォーマット

#### 3. SQN^AK管理機能 (`s1n2_converter.c` Line 1526-1540)
```c
// 5G Authentication Request から SQN^AK を抽出してキャッシュ
if (s1n2_extract_rand_autn_from_5g_auth_request(nas_buf, nas_len,
                                                 rand, autn, sqn_xor_ak, cache_map) == 0) {
    memcpy(cache_map->sqn_xor_ak, sqn_xor_ak, 6);
    printf("[SUCCESS] [SQN-FIX] Extracted and cached SQN^AK from 5G Auth Request\n");
    printf("[SUCCESS] [SQN-FIX]   SQN^AK: ");
    for (int i = 0; i < 6; i++) printf("%02X", sqn_xor_ak[i]);
}
```

**動作:**
- ✅ AMF→eNB方向の5G Authentication Requestを監視
- ✅ AUTN内のSQN^AKを抽出
- ✅ UEコンテキスト(`ue_mapping->sqn_xor_ak`)にキャッシュ
- ✅ 4G KASME derivationで使用 (Sync Failure防止)

---

## ❌ 未実装機能: Authentication Re-Synchronization

### 3GPP標準の再同期手順 (TS 33.102)

```
1. UE → eNB → MME: Authentication Failure (AUTS, cause=21 Synch failure)
2. MME: AUTS解析
   - SQN_MS = (SQN_MS⊕AK) ⊕ AK を計算
   - UEの期待SQN値を取得
3. MME → HSS: Update Location Request (新SQN値)
4. HSS: SQN更新 → 新しいAuthentication Vector生成
5. HSS → MME: Update Location Answer (RAND, AUTN, XRES, KASME)
6. MME → eNB → UE: Authentication Request (新RAND, 新AUTN)
7. UE: SQN検証OK → RES計算
8. UE → eNB → MME: Authentication Response (RES)
9. MME: RES=XRES確認 → 認証成功
```

### 現在のs1n2コンバーターの動作

```
1. UE → eNB → converter → AMF: Authentication Failure (AUTS, cause=21)
2. converter: AUTS解析
   - UEの期待SQN値を計算
   - MongoDB更新コマンドをログに出力
   - ❌ MongoDB更新は実行しない
3. converter: Authentication FailureをAMFへ転送
4. ❌ AMF/AUSFは再認証を開始しない (5GC側の実装による)
5. ❌ 新しいAuthentication Requestは送信されない

→ 結果: 運用者が手動でMongoDBを更新し、UEを再起動する必要がある
```

---

## 実装方針: 3つのオプション

### Option A: 完全自動再同期 (推奨)

**概要:**
- コンバーターがAUTSを検出したら自動的にMongoDBを更新
- AMFが新しいAuth Vectorを生成するのを待つ
- 新しいAuthentication RequestがeNBに届いたら自動変換

**実装内容:**

#### A-1. MongoDB C Driver統合
```c
// 必要なライブラリ: libmongoc-1.0, libbson-1.0
#include <mongoc/mongoc.h>

// MongoDB接続関数
mongoc_client_t* s1n2_mongo_connect(const char *uri);
int s1n2_mongo_update_sqn(mongoc_client_t *client,
                          const char *imsi,
                          uint64_t new_sqn);
```

**Makefileの変更:**
```makefile
CFLAGS += -I/usr/include/libmongoc-1.0 -I/usr/include/libbson-1.0
LDFLAGS += -lmongoc-1.0 -lbson-1.0
```

**Dockerfileの変更:**
```dockerfile
RUN apt-get update && apt-get install -y \
    libmongoc-dev \
    libbson-dev
```

#### A-2. AUTS検出時にMongoDB自動更新
```c
// s1n2_nas.c Line 1590付近に追加
if (s1n2_decode_auts_sqn(keys->opc, keys->ki, ue_map->rand, auts, sqn_ms) == 0) {
    uint64_t sqn_value = 0;
    for (int i = 0; i < 6; i++) {
        sqn_value = (sqn_value << 8) | sqn_ms[i];
    }

    printf("[INFO] ========== AUTS ANALYSIS (Sync Failure) ==========\n");
    printf("[INFO] UE expected SQN (dec): %lu\n", sqn_value);

    // ★新規追加: MongoDB自動更新★
    mongoc_client_t *mongo_client = s1n2_mongo_connect("mongodb://mongo-s1n2:27017");
    if (mongo_client) {
        uint64_t new_sqn = sqn_value + 1000; // Grace period
        if (s1n2_mongo_update_sqn(mongo_client, ue_map->imsi, new_sqn) == 0) {
            printf("[SUCCESS] MongoDB SQN updated automatically: %lu\n", new_sqn);
        } else {
            printf("[ERROR] Failed to update MongoDB SQN\n");
            // Fallback: 従来通りコマンドを表示
            printf("[INFO] Manual update command:\n");
            printf("[INFO]   docker exec -it mongo-s1n2 mongosh --quiet open5gs \\\n");
            printf("[INFO]     --eval 'db.subscribers.updateOne({imsi: \"%s\"}, \\\n", ue_map->imsi);
            printf("[INFO]     {$set: {\"security.sqn\": NumberLong(\"%lu\")}})'\n", new_sqn);
        }
        mongoc_client_destroy(mongo_client);
    } else {
        printf("[ERROR] Cannot connect to MongoDB for auto-update\n");
    }
    printf("[INFO] ====================================================\n");
}
```

#### A-3. AMF再認証トリガー (オプション)
```c
// AMFがOpen5GSの場合、MongoDBの変更を検知してAuth Vector再生成は自動
// ただし、AMF→converterへの新Auth Requestを待つ必要がある
// converter側は追加実装不要 (既存のAuth Request変換処理で対応可能)
```

**実装工数:**
- MongoDB C Driver統合: 2時間
- AUTS検出→自動更新ロジック: 1時間
- ビルドシステム修正: 1時間
- テスト・検証: 2時間
- **合計: 6時間**

**メリット:**
- ✅ 完全自動化 (運用負荷ゼロ)
- ✅ 3GPP標準に準拠
- ✅ 再現性の高いテスト実施可能
- ✅ 本番運用レベル

**デメリット:**
- ⚠️ MongoDB C Driver依存追加
- ⚠️ Docker imageサイズ増加 (~10MB)
- ⚠️ MongoDBへのネットワーク接続必須

---

### Option B: スクリプトによる半自動化 (中間案)

**概要:**
- コンバーターのログを監視するPythonスクリプト
- AUTS解析ログを検出したら自動的にMongoDBコマンドを実行

**実装内容:**

#### B-1. ログ監視スクリプト
```python
#!/usr/bin/env python3
# scripts/auto_sqn_update.py

import re
import subprocess
import time
from datetime import datetime

LOG_FILE = "/var/log/s1n2-converter.log"
PATTERN = r'\[INFO\] UE expected SQN \(dec\): (\d+)'
IMSI_PATTERN = r'IMSI: (\d+)'

def monitor_log():
    print(f"[{datetime.now()}] Starting SQN auto-update monitor...")

    with open(LOG_FILE, 'r') as f:
        f.seek(0, 2)  # Go to end of file

        while True:
            line = f.readline()
            if not line:
                time.sleep(0.1)
                continue

            # AUTS解析ログを検出
            match_sqn = re.search(PATTERN, line)
            if match_sqn:
                sqn_value = int(match_sqn.group(1))
                new_sqn = sqn_value + 1000

                # IMSIを前の行から取得
                f.seek(f.tell() - 200, 0)  # 200 bytes戻る
                context = f.read(200)
                match_imsi = re.search(IMSI_PATTERN, context)

                if match_imsi:
                    imsi = match_imsi.group(1)
                    print(f"[{datetime.now()}] Detected Sync Failure: IMSI={imsi}, SQN={sqn_value}")

                    # MongoDB更新コマンド実行
                    cmd = [
                        "docker", "exec", "-i", "mongo-s1n2",
                        "mongosh", "--quiet", "open5gs",
                        "--eval", f'db.subscribers.updateOne({{imsi: "{imsi}"}}, {{$set: {{"security.sqn": NumberLong("{new_sqn}")}}}})'
                    ]

                    try:
                        result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
                        if result.returncode == 0:
                            print(f"[{datetime.now()}] ✅ MongoDB SQN updated: {new_sqn}")
                        else:
                            print(f"[{datetime.now()}] ❌ Failed: {result.stderr}")
                    except Exception as e:
                        print(f"[{datetime.now()}] ❌ Exception: {e}")

                f.seek(0, 2)  # Go back to end

if __name__ == "__main__":
    monitor_log()
```

#### B-2. systemdサービス登録
```ini
# /etc/systemd/system/s1n2-sqn-monitor.service
[Unit]
Description=s1n2 Converter SQN Auto-Update Monitor
After=docker.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/s1n2/scripts/auto_sqn_update.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable s1n2-sqn-monitor
sudo systemctl start s1n2-sqn-monitor
```

**実装工数:**
- Pythonスクリプト作成: 1時間
- systemdサービス設定: 0.5時間
- テスト・検証: 0.5時間
- **合計: 2時間**

**メリット:**
- ✅ 実装が簡単
- ✅ コンバーター本体への変更なし
- ✅ デバッグが容易
- ✅ Pythonの依存のみ

**デメリット:**
- ⚠️ ログファイルへの依存
- ⚠️ リアルタイム性が低い (~100ms遅延)
- ⚠️ ログフォーマット変更に脆弱

---

### Option C: 手動運用継続 (現状維持)

**概要:**
- 現在のログ出力のみの実装を維持
- 運用者がコマンドをコピー&実行

**実装内容:**
- なし (現状のまま)

**実装工数:**
- **0時間**

**メリット:**
- ✅ 実装不要
- ✅ シンプル
- ✅ 依存関係なし

**デメリット:**
- ❌ 運用負荷が高い
- ❌ ヒューマンエラーの可能性
- ❌ 自動テスト不可
- ❌ 本番運用に不適

---

## 推奨実装オプション

### 短期: Option B (スクリプト半自動化)
**理由:**
- 実装が2時間で完了
- コンバーター本体への影響なし
- 運用負荷を大幅削減

### 長期: Option A (完全自動化)
**理由:**
- 本番運用レベル
- 3GPP標準準拠
- テストの自動化が可能

---

## 実装ステップ (Option B → Option A)

### Phase 1: ログ監視スクリプト実装 (Option B)
**期間:** 1日

1. `scripts/auto_sqn_update.py` 作成
2. systemdサービス登録
3. 動作確認
   - AUTS発生時にMongoDB自動更新されるか確認
   - ログに成功メッセージが出力されるか確認

### Phase 2: MongoDB C Driver統合 (Option A)
**期間:** 2-3日

1. Dockerfile修正 (libmongoc-dev追加)
2. Makefile修正 (MongoDB libraries追加)
3. `src/db/s1n2_mongodb.c` 新規作成
   ```c
   mongoc_client_t* s1n2_mongo_connect(const char *uri);
   int s1n2_mongo_update_sqn(mongoc_client_t *client, const char *imsi, uint64_t new_sqn);
   void s1n2_mongo_disconnect(mongoc_client_t *client);
   ```
4. `src/db/s1n2_mongodb.h` 新規作成
5. `src/nas/s1n2_nas.c` Line 1590付近に自動更新ロジック追加
6. ビルド・テスト
7. Option Bのスクリプトを無効化

### Phase 3: 統合テスト
**期間:** 1日

1. 正常系テスト
   - UE起動 → Sync Failure発生 → MongoDB自動更新 → 再認証成功
2. 異常系テスト
   - MongoDB接続失敗時のフォールバック動作確認
   - AUTS解析失敗時の挙動確認
3. 性能テスト
   - MongoDB更新の応答時間測定 (<100ms目標)

---

## テスト計画

### Test Case 1: Sync Failure → 自動回復
**前提条件:**
- UE USIM SQN: 44,022,727,321,853
- MongoDB SQN: 1 (大幅にずれた状態)

**期待動作:**
1. UE → eNB: Attach Request
2. AMF → converter → eNB: Authentication Request
3. eNB → converter → AMF: Authentication Failure (AUTS)
4. converter: AUTS解析 → MongoDB SQN=44,022,727,322,853 に自動更新
5. AMF: 新Auth Vector生成
6. AMF → converter → eNB: Authentication Request (新RAND/AUTN)
7. eNB → converter → AMF: Authentication Response (RES)
8. AMF: RES=XRES確認 → 認証成功

**確認項目:**
- ✅ MongoDB SQN自動更新ログ出力
- ✅ MongoDB実際に更新されているか (`mongosh`で確認)
- ✅ 2回目のAuthentication Requestが送信されるか
- ✅ Authentication Responseが成功するか
- ✅ PDU Session確立完了
- ✅ ICMP Echo Request/Reply双方向通信

### Test Case 2: MongoDB接続失敗時のフォールバック
**前提条件:**
- MongoDB container停止

**期待動作:**
1. UE → eNB: Authentication Failure (AUTS)
2. converter: AUTS解析
3. converter: MongoDB接続失敗 → エラーログ出力
4. converter: 手動更新コマンドをログに出力 (従来通り)

**確認項目:**
- ✅ エラーログ出力
- ✅ 手動更新コマンド表示
- ✅ コンバーターがクラッシュしない

### Test Case 3: 複数UE同時Sync Failure
**前提条件:**
- UE1, UE2, UE3が同時にSync Failure発生

**期待動作:**
- 各UEごとにMongoDB SQN自動更新
- レースコンディションなし

**確認項目:**
- ✅ 3つのMongoDB updateが全て成功
- ✅ ログに3UE分の成功メッセージ

---

## セキュリティ考慮事項

### MongoDB接続の保護
```c
// Connection URIに認証情報を含める
const char *MONGO_URI = "mongodb://admin:password@mongo-s1n2:27017/open5gs?authSource=admin";

// TLS/SSL有効化 (本番環境)
mongoc_ssl_opt_t ssl_opts = {0};
ssl_opts.pem_file = "/etc/ssl/certs/client.pem";
mongoc_client_set_ssl_opts(client, &ssl_opts);
```

### SQN Grace Period設定
```c
// 現在: +1000 (安全マージン)
// 3GPP推奨: +32 (実用的最小値)
// 設定可能化
#define SQN_GRACE_PERIOD 1000  // config.yamlから読み込み可能にする
uint64_t new_sqn = sqn_value + SQN_GRACE_PERIOD;
```

### ログのサニタイゼーション
```c
// IMSI/SQN値のログ出力を環境変数で制御
if (getenv("S1N2_DEBUG_SQN")) {
    printf("[DEBUG] UE expected SQN (dec): %lu\n", sqn_value);
}
```

---

## パフォーマンス目標

| 項目 | 目標値 | 測定方法 |
|------|--------|----------|
| AUTS検出→MongoDB更新 | <100ms | タイムスタンプログ |
| MongoDB更新→Auth Vector生成 | <200ms | AMFログ解析 |
| 合計再同期時間 | <500ms | pcap解析 |
| MongoDB接続エラー時のフォールバック | <10ms | エラーハンドラ応答時間 |

---

## 設定ファイル拡張

### config/s1n2.yaml
```yaml
mongodb:
  uri: "mongodb://mongo-s1n2:27017"
  database: "open5gs"
  collection: "subscribers"
  auth:
    username: "admin"
    password: "password"
    auth_source: "admin"
  connection:
    timeout_ms: 5000
    retry_count: 3

sqn:
  auto_update: true              # AUTS検出時の自動更新
  grace_period: 1000             # UE期待SQN + この値
  log_level: "info"              # "debug", "info", "warn", "error"
  fallback_to_manual: true       # MongoDB失敗時に手動コマンド表示
```

---

## ドキュメント更新

実装完了後に更新すべきドキュメント:

1. **`SQN_FIX_IMPLEMENTATION.md`**
   - Level 2: AUTS自動処理 追加

2. **`TAU_PROBLEM_ANALYSIS.md`**
   - 自動再同期機能による解決策追記

3. **`README.md`**
   - MongoDB C Driver依存追加
   - ビルド手順更新

4. **`docker-compose.yml`**
   - MongoDB環境変数追加

---

## まとめ

### 現状
- ✅ AUTS解析: 実装済み
- ✅ AUTS転送: 実装済み
- ✅ SQN^AK管理: 実装済み
- ❌ **MongoDB自動更新: 未実装**
- ❌ **再同期トリガー: 未実装**

### 実装推奨
1. **短期 (1日):** Option B - ログ監視スクリプト
2. **長期 (3日):** Option A - MongoDB C Driver統合

### 効果
- ✅ 運用負荷削減 (手動作業ゼロ化)
- ✅ 3GPP標準準拠の再同期手順実現
- ✅ テストの自動化・再現性向上
- ✅ 本番運用レベルの信頼性

---

**Implementation Status: 未実装**
**Priority: 中 (運用性改善)**
**Effort: 2時間 (Option B) / 6時間 (Option A)**
**Author: GitHub Copilot**
**Date: 2025-11-18**
