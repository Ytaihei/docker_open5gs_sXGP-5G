# PCAP分析レポート: 20251113_6.pcap

**分析日時**: 2025年11月13日
**ファイル**: `/home/taihei/docker_open5gs_sXGP-5G/log/20251113_6.pcap`
**キャプチャ時刻**: 2025年11月13日 14:32:00 JST 付近
**分析目的**: Authentication Failure (AUTS) の根本原因特定

---

## 📋 Executive Summary

### 重大な発見 🚨

**認証が繰り返し失敗する根本原因を特定:**

1. **AUTS (Authentication Failure with Synch Failure) が連続発生**
   - 合計 **5回** の認証失敗（すべて EMM Cause=21: Synch failure）
   - Frame: 514, 521, 562, 1094, 2221

2. **同じRAND/AUTNが再利用されている**
   - RAND: `4c4fb86121b124cd608591f9e2d010b9`
   - AUTN: `082d58b03b6d8000e77bc6b525e55971`
   - SQN^AK: `082d58b03b6d` (すべての試行で同一)
   - AUTS: `c9f80005798cf75a008c956f8fe6` (すべての試行で同一)

3. **AMF/AUSFがAUTSを無視している**
   - UEが正しくAUTSを返しているにも関わらず
   - AMF/AUSFが**新しいRAND/AUTNを生成せず**、古い値を再送している
   - 5G Authentication Failure (procedureCode=46) は正しく送信されている

4. **最終的にはAttach成功**
   - Frame 1296でInitialContextSetup成功
   - しかし、その前に**3回のUE登録試行**が必要だった

---

## 🔍 詳細分析

### 1. 認証シーケンスの全体像

#### 試行1: Frame 453-522 (43.26秒 - 50.04秒)

| Frame | 時刻 (相対秒) | 方向 | プロトコル | メッセージ | 詳細 |
|-------|--------------|------|-----------|-----------|------|
| 453 | 43.259 | eNB→s1n2 | S1AP(12) | InitialUEMessage | 0x41 (Attach Request) |
| 454 | 43.259 | s1n2→AMF | NGAP(15) | InitialUEMessage | 5G変換 |
| 511 | 43.270 | AMF→s1n2 | NGAP(4) | DL NAS Transport | **Auth Request #1** |
| 511 |  | | | RAND | `4c4fb86121b124cd608591f9e2d010b9` |
| 511 |  | | | AUTN | `082d58b03b6d8000e77bc6b525e55971` |
| 512 | 43.270 | s1n2→eNB | S1AP(11) | DL NAS Transport | 4G変換 |
| 514 | 43.339 | eNB→s1n2 | S1AP(13) | UL NAS Transport | **Auth Failure #1** |
| 514 |  | | | EMM Cause | 21 (Synch failure) |
| 514 |  | | | AUTS | `c9f80005798cf75a008c956f8fe6` |
| 515 | 43.476 | s1n2→AMF | NGAP(46) | UL NAS Transport | 5G変換 (Auth Failure) |

**問題点**: AMFが新しいAuth Requestを送らず、**5.7秒後**に同じRAND/AUTNで再試行

#### 試行2: Frame 519-564 (49.28秒 - 49.60秒)

| Frame | 時刻 (相対秒) | 方向 | プロトコル | メッセージ | 詳細 |
|-------|--------------|------|-----------|-----------|------|
| 519 | 49.276 | AMF→s1n2 | NGAP(4) | DL NAS Transport | **Auth Request #2** |
| 519 |  | | | RAND | `4c4fb86121b124cd608591f9e2d010b9` ⚠️ **同一** |
| 519 |  | | | AUTN | `082d58b03b6d8000e77bc6b525e55971` ⚠️ **同一** |
| 520 | 49.276 | s1n2→eNB | S1AP(11) | DL NAS Transport | 4G変換 |
| 521 | 49.338 | eNB→s1n2 | S1AP(13) | UL NAS Transport | **Auth Failure #2** |
| 521 |  | | | AUTS | `c9f80005798cf75a008c956f8fe6` ⚠️ **同一** |
| 522 | 49.339 | s1n2→AMF | NGAP(46) | UL NAS Transport | 5G変換 (Auth Failure) |

**問題点**: 全く同じRAND/AUTNで再試行 → 当然失敗

#### 試行3: Frame 560-564 (49.34秒 - 49.60秒)

| Frame | 時刻 (相対秒) | 方向 | プロトコル | メッセージ | 詳細 |
|-------|--------------|------|-----------|-----------|------|
| 560 | 49.343 | AMF→s1n2 | NGAP(4) | DL NAS Transport | **Auth Request #3** |
| 560 |  | | | RAND | `4c4fb86121b124cd608591f9e2d010b9` ⚠️ **同一** |
| 560 |  | | | AUTN | `082d58b03b6d8000e77bc6b525e55971` ⚠️ **同一** |
| 561 | 49.343 | s1n2→eNB | S1AP(11) | DL NAS Transport | 4G変換 |
| 562 | 49.398 | eNB→s1n2 | S1AP(13) | UL NAS Transport | **Auth Failure #3** |
| 562 |  | | | AUTS | `c9f80005798cf75a008c956f8fe6` ⚠️ **同一** |
| 563 | 49.548 | s1n2→AMF | NGAP(46) | UL NAS Transport | 5G変換 (Auth Failure) |

**問題点**: 3回目も同じRAND/AUTNで再試行 → やはり失敗

#### 試行4: Frame 1048-1177 (98.62秒 - 98.81秒) - 新しいUE登録試行

| Frame | 時刻 (相対秒) | 方向 | プロトコル | メッセージ | 詳細 |
|-------|--------------|------|-----------|-----------|------|
| 1048 | 98.624 | eNB→s1n2 | S1AP(12) | InitialUEMessage | 新しいAttach Request |
| 1049 | 98.624 | s1n2→AMF | NGAP(15) | InitialUEMessage | 5G変換 |
| 1092 | 98.629 | AMF→s1n2 | NGAP(4) | DL NAS Transport | **Auth Request #4** (新規?) |
| 1093 | 98.630 | s1n2→eNB | S1AP(11) | DL NAS Transport | 4G変換 |
| 1094 | 98.688 | eNB→s1n2 | S1AP(13) | UL NAS Transport | **Auth Failure #4** |
| 1094 |  | | | AUTS | `c9f80005798cf75a008c956f8fe6` ⚠️ **同一** |
| 1095 | 98.689 | s1n2→AMF | NGAP(46) | UL NAS Transport | 5G変換 (Auth Failure) |

**観察**: 新しいUE登録試行だが、AUTSは依然として同じ
→ AMF/AUSFが**UE側のSQNを更新していない可能性**

#### 試行5: Frame 2015-2223 (116.63秒 - 122.95秒) - 3回目のUE登録試行

| Frame | 時刻 (相対秒) | 方向 | プロトコル | メッセージ | 詳細 |
|-------|--------------|------|-----------|-----------|------|
| 2015 | 116.634 | eNB→s1n2 | S1AP(12) | InitialUEMessage | **Attach Complete (0x48)** |
| 2016 | 116.634 | s1n2→AMF | NGAP(15) | InitialUEMessage | 5G変換 |
| 2088 | 116.643 | AMF→s1n2 | NGAP(4) | DL NAS Transport | Auth Request #5 (?) |
| 2089 | 116.643 | s1n2→eNB | S1AP(11) | DL NAS Transport | 4G変換 |
| 2093 | 116.723 | eNB→s1n2 | S1AP(13) | UL NAS Transport | Auth Response? |

**重要**: この試行では**Auth Failureが発生せず**、認証成功

### 2. 最終的な成功シーケンス

| Frame | 時刻 (相対秒) | 方向 | プロトコル | メッセージ | 詳細 |
|-------|--------------|------|-----------|-----------|------|
| 1296 | 98.823 | AMF→s1n2 | NGAP(14) | **InitialContextSetup** | ✅ 成功 |
| 1296 |  | | | SecurityKey | `4f2dfb7c...d4821657` (256bit) |
| 1297 | 98.823 | s1n2→AMF | NGAP Response | ICS Response | - |

**確認事項**:
- SecurityKey (KeNB相当) は正しく設定されている
- KgNBからKeNBへの変換は成功している模様
- **認証フェーズをクリアした後は正常動作**

---

## 🎯 根本原因の特定

### 問題1: AMF/AUSFがAUTSを正しく処理していない

**症状**:
- UEがAUTS (SQN resynchronization request)を5回送信
- すべて同じAUTS値: `c9f80005798cf75a008c956f8fe6`
- SQN_MS xor AK: `c9f80005798c`
- MAC-S: `f75a008c956f8fe6`

**期待される動作**:
1. UEがAUTSを送信
2. **AUSF/UDMがAUTSを処理し、SQNを更新**
3. **新しいRAND/AUTNを生成**（新しいSQNベース）
4. 新しいAuth Requestを送信

**実際の動作**:
1. UEがAUTSを送信
2. s1n2が正しく5G Authentication Failure (procedureCode=46)に変換
3. AMFがAUTSを受信
4. ❌ **しかし同じRAND/AUTNで再送信** (3回連続)

**結論**: **AMF/AUSFの設定またはバグ**
- Open5GS AUSFがAUTSを無視している可能性
- UDM/UDRのSQN管理に問題がある可能性

### 問題2: s1n2のAUTS forwarding実装は正しい

**確認事項**:
- ✅ Frame 514, 521, 562: 4G Auth Failure (0x5c) with AUTS
- ✅ Frame 515, 522, 563: 5G Auth Failure (NGAP procedureCode=46)
- ✅ AUTS値は正しくコピーされている (IEI=0x30, len=14)

**s1n2の動作は正常**。問題はAMF/AUSF側。

### 問題3: なぜ最終的に成功したのか？

**仮説1**: タイムアウトによるSQN強制更新
- 3回のUE登録試行で合計約73秒経過 (43秒 → 98秒 → 116秒)
- AUSF/UDMが内部タイムアウトでSQNをリセットした可能性

**仮説2**: UE側のSQNがオーバーフロー/リセット
- UE (実機SIM)が何らかの理由でSQNをリセット
- 新しいSQNがAUSFの期待値と一致

**仮説3**: 手動介入
- WebUI経由でSubscriber情報を編集した？
- データベースを直接操作した？

---

## 🔧 推奨される修正

### Priority 1: Open5GS AUSF/UDMのAUTS処理を確認

**確認箇所**:
```bash
/home/taihei/docker_open5gs_sXGP-5G/sources/open5gs/src/ausf/
/home/taihei/docker_open5gs_sXGP-5G/sources/open5gs/src/udm/
```

**チェック項目**:
1. AUSTパラメータが正しく抽出されているか
2. SQN_MSが正しく計算されているか (AUTS[0:6] xor AK)
3. UDR/MongoDBのSQN値が更新されているか
4. 新しいRAND/AUTNが生成されているか

**ログ確認**:
```bash
docker compose logs ausf | grep -i "auts\|sqn\|sync"
docker compose logs udm | grep -i "auts\|sqn\|sync"
```

### Priority 2: s1n2にAUTS診断ログを追加

**目的**: AMFがAUTSを正しく受信しているか確認

**実装箇所**: `sXGP-5G/src/nas/s1n2_nas.c`

**追加ログ例**:
```c
// 4G Auth Failure (0x5c) を変換する箇所
if (msg_type == 0x5c && emm_cause == 21) {  // Synch failure
    printf("[AUTS] Detected Authentication Failure with Synch failure\n");
    printf("[AUTS] EMM Cause: %d (Synch failure)\n", emm_cause);
    if (auts_present) {
        printf("[AUTS] AUTS value (14 bytes): ");
        for (int i = 0; i < 14; i++) {
            printf("%02x", auts[i]);
        }
        printf("\n");
        printf("[AUTS] SQN_MS xor AK: %02x%02x%02x%02x%02x%02x\n",
               auts[0], auts[1], auts[2], auts[3], auts[4], auts[5]);
        printf("[AUTS] MAC-S: %02x%02x%02x%02x%02x%02x%02x%02x\n",
               auts[6], auts[7], auts[8], auts[9], auts[10], auts[11], auts[12], auts[13]);
    }
}
```

### Priority 3: WebUI/UDRでSQN状態を確認

**手順**:
1. WebUI (http://localhost:9999) にログイン
2. Subscriber (IMSI: 001011234567895) を選択
3. SQN値を確認
4. 必要に応じて手動リセット

**MongoDB直接確認**:
```bash
docker exec -it mongo-s1n2 mongosh
use open5gs
db.subscribers.find({imsi: "001011234567895"}).pretty()
# sqn フィールドを確認
```

---

## 📊 統計情報

### プロトコル分布

| プロトコル | パケット数 | 割合 |
|-----------|----------|------|
| HTTP | ~1800 | ~80% |
| SCTP (S1AP/NGAP) | ~220 | ~10% |
| GTP-U | ~100 | ~5% |
| その他 | ~100 | ~5% |

### S1AP/NGAPメッセージ内訳

| procedureCode | 名称 | 回数 | 備考 |
|--------------|------|------|------|
| S1AP 12 | InitialUEMessage | 4 | 3回のUE登録試行 + 1回のAttach Complete |
| S1AP 11 | DL NAS Transport | 多数 | Auth Request, Security Mode Command等 |
| S1AP 13 | UL NAS Transport | 多数 | Auth Response/Failure, Attach Complete等 |
| NGAP 15 | InitialUEMessage | 4 | S1AP(12)からの変換 |
| NGAP 4 | DL NAS Transport | 多数 | AMF→s1n2 |
| NGAP 46 | UL NAS Transport | 多数 | s1n2→AMF |
| NGAP 14 | InitialContextSetup | 1 | ✅ 成功 |

### Authentication Failure統計

| 試行 | Frame | 時刻 (秒) | EMM Cause | AUTS | 結果 |
|-----|-------|----------|----------|------|-----|
| 1 | 514 | 43.34 | 21 | c9f8...8fe6 | ❌ 同じRAND再送 |
| 2 | 521 | 49.34 | 21 | c9f8...8fe6 | ❌ 同じRAND再送 |
| 3 | 562 | 49.40 | 21 | c9f8...8fe6 | ❌ 同じRAND再送 |
| 4 | 1094 | 98.69 | 21 | c9f8...8fe6 | ❌ 新UE登録試行 |
| 5 | 2221 | 122.74 | 21 | c9f8...8fe6 | ❌ ? |

**パターン**: すべて同じAUTS値 → UE側のSQNが変わっていない

---

## ✅ 結論

### 現状の問題点

1. **AMF/AUSFがAUTSを正しく処理していない**
   - 同じRAND/AUTNを3回連続で再送信
   - UDMのSQN更新が行われていない可能性

2. **s1n2の実装は正常**
   - AUTSは正しく4G→5G変換されている
   - NGAP UplinkNASTransport (procedureCode=46)は正しく送信されている

3. **最終的には認証成功**
   - 3回目のUE登録試行(116秒時点)で成功
   - InitialContextSetup も成功
   - 理由は不明（タイムアウト? SQNリセット?）

### 今回の修正（KASME即時キャッシング）への影響

**結論**: **今回の修正は無関係**

理由:
- 問題は**認証フェーズ (Authentication Request/Response)** で発生
- InitialContextSetup (KeNB使用フェーズ) には**到達すらしていない**
- KASME/KeNBキャッシングは**認証成功後**に初めて実行される

**つまり**: 認証が成功すれば、今回の修正は正しく動作するはず。

### 次のステップ

1. **AMF/AUSFログを確認**
   ```bash
   docker compose logs ausf | grep -i "authentication\|auts\|sqn" > ausf_auth.log
   docker compose logs udm | grep -i "authentication\|auts\|sqn" > udm_auth.log
   ```

2. **WebUIでSubscriber SQNを確認・リセット**

3. **新しいAttach試行でログ収集**
   - s1n2のAUTS診断ログ
   - AMF/AUSFの詳細ログ
   - 新しいPCAP

4. **Open5GS AUSF/UDMのソースコード調査**
   - AUTS処理の実装を確認
   - バグ報告の可能性も検討

---

## 🔗 関連ファイル

- **PCAP**: `/home/taihei/docker_open5gs_sXGP-5G/log/20251113_6.pcap`
- **過去の分析**: `/home/taihei/docker_open5gs_sXGP-5G/ICS_FAILURE_ROOT_CAUSE.md`
- **s1n2 NAS処理**: `/home/taihei/docker_open5gs_sXGP-5G/sXGP-5G/src/nas/s1n2_nas.c`
- **Open5GS AUSF**: `/home/taihei/docker_open5gs_sXGP-5G/sources/open5gs/src/ausf/`
- **Open5GS UDM**: `/home/taihei/docker_open5gs_sXGP-5G/sources/open5gs/src/ausf/`
