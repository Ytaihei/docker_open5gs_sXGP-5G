# 🔧 Security Header Type修正計画
## Date: 2025-11-12
## Target: s1n2_nas.c Attach Accept生成処理

---

## 📊 現状分析

### 問題のコード箇所

**ファイル**: `/home/taihei/docker_open5gs_sXGP-5G/sXGP-5G/src/nas/s1n2_nas.c`
**行**: 2260-2330

### 現在のロジック（バグあり）

```c
// Line 2269: 暗号化アルゴリズム選択
s1n2_nas_encryption_alg_t enc_alg = S1N2_NAS_EEA0;
if (eea_sel == 2) {
    enc_alg = S1N2_NAS_EEA2;
}
// ❌ eea_sel=0の場合、enc_algはEEA0のまま

// Line 2274: 暗号化試行
uint8_t cipher[384];
bool enc_ok = false;
if (enc_alg != S1N2_NAS_EEA0) {
    if (s1n2_nas_encrypt(...) == 0) {
        enc_ok = true;  // ← EEA2のみtrueになる
    }
}
// ❌ EEA0の場合、このブロックがスキップされ、enc_ok=falseのまま

// Line 2283: 暗号化成功時の処理（Type 2使用）
if (enc_ok) {
    // Type 2 (0x27)を使用
    nas_4g[w++] = 0x27;  // Ciphered + Integrity protected
    memcpy(nas_4g + w, mac, 4); w += 4;
    nas_4g[w++] = seq;
    memcpy(nas_4g + w, cipher, out_off);  // 暗号化されたペイロード
    wrapped = true;
}

// Line 2317: フォールバック処理（Type 1使用）
if (!wrapped) {
    // Type 1 (0x17)を使用
    nas_4g[w++] = 0x17;  // Integrity protected only
    memcpy(nas_4g + w, mac, 4); w += 4;
    nas_4g[w++] = seq;
    memcpy(nas_4g + w, out, out_off);  // 平文ペイロード
    wrapped = true;
}
// ❌ EEA0の場合、このパスが選択される → Type 1 (0x17)
```

### 問題点の詳細

| ケース | eea_sel | enc_alg | enc_ok | 選択されるType | 結果 |
|--------|---------|---------|--------|--------------|------|
| **失敗** | 0 (EEA0) | EEA0 | false | Type 1 (0x17) | ❌ ICS Failure |
| **成功** | 0 (EEA0) | EEA0 | **true** | Type 2 (0x27) | ✅ ICS Success |
| EEA2 | 2 (EEA2) | EEA2 | true | Type 2 (0x27) | ✅ |

**バグの根本原因**:
- コメント (Line 2265): "encryption disabled by SMC -> integrity-only (0x17)"
- これは**誤った解釈**！
- EEA0 = "null cipher"であり、"use different format"ではない
- Type 2 + EEA0 = 正当な組み合わせ（暗号化フォーマット + 恒等変換）

---

## 🎯 修正方針

### 修正の目的

**EEA0でもType 2 (0x27)フォーマットを使用する**

### 修正の原則

1. **EEA0もenc_ok=trueにする**
2. **EEA0の"暗号化"は恒等変換（memcpy）**
3. **Type 1パスは削除または非推奨化**

### 追加対応: 環境変数によるNASセキュリティモード切替

| 目的 | 詳細 |
|------|------|
| 運用切替容易化 | `S1N2_SECURITY_PROFILE`（`encrypted`/`null`。省略時は`encrypted`）を起動時に読み込んで`ctx->security_profile`にキャッシュし、ログで明示する。 |
| UE Capabilityの整合 | `encrypted`モードでは従来通り `0xF0 0x70 0xF0 0x70` を広告。`null`モードでは NEA/NIA0 のみを立てた4オクテットを生成し、AMFにnull希望を明確化。 |
| NAS鍵導出の分岐 | `s1n2_try_derive_4g_nas_keys()` および 5G NAS鍵導出ブロックでも常にKDFを実行し、`null`モードでは派生済みキーをType-2ヘッダのMAC計算専用に使用（EEA0恒等変換）。`encrypted`モードでは従来どおりEEA2を使用。 |
| NAS暗号ラッパ | Attach Accept/Registration Request等の包み込みでは `encrypted`時にEEA2/EEA0へ委譲、`null`時は恒等変換でType-2ヘッダを維持。Integrity計算に失敗した場合のみType-1へフォールバック。 |
| 公開API | `s1n2_context_get_security_profile()` ヘルパーを追加し、NAS層から直接環境変数を読まない。 |

**段階実装案**
1. `s1n2_converter.h` に `s1n2_security_profile_t` 列挙と `ctx->security_profile` フィールドを追加。
2. `s1n2_init_context()` で環境変数を読んで列挙へ変換、ログ出力。内部ヘルパー/アクセサを `s1n2_context_internal.h` へ宣言。
3. `s1n2_try_derive_4g_nas_keys()` と `s1n2_nas.c` の5G KDFブロックにプロファイル判定を追加し、`null`モードではEEA選択を強制的にEEA0へ落とし込む（鍵は導出したまま）。
4. `s1n2_nas.c` で UE Security Capability ビルダとNAS包み込みヘルパーにプロファイル分岐を実装（EEA0恒等写像 + Type-2固定）。
5. 既存ログ/テスト手順を更新し、`encrypted` と `null` の双方でpcap・ICSログ確認フローを準備。

### 修正戦略

#### Option A: EEA0専用ブロックを追加（推奨）✅

**メリット**:
- 明示的でわかりやすい
- EEA0の特殊性を明確に示す
- 既存のEEA2ロジックに影響なし

**デメリット**:
- コード行が少し増える

#### Option B: 条件を緩和してEEA0も暗号化ブロックに含める

**メリット**:
- コード変更が最小限

**デメリット**:
- s1n2_nas_encrypt()がEEA0を処理する必要がある
- 関数の変更が必要な可能性

**推奨**: **Option A** - 明示的で安全

---

## 📝 具体的な修正コード

### 修正前（Line 2269-2280）

```c
s1n2_nas_encryption_alg_t enc_alg = S1N2_NAS_EEA0;
if (eea_sel == 2) {
    enc_alg = S1N2_NAS_EEA2;
}
uint8_t cipher[384];
bool enc_ok = false;
if (enc_alg != S1N2_NAS_EEA0) {
    if (s1n2_nas_encrypt(enc_alg, security_cache->k_nas_enc, count_dl, 0 /*bearer*/, 1 /*DL*/, out, out_off, cipher) == 0) {
        enc_ok = true;
    } else {
        printf("[WARN] NAS EEA%u encryption failed, will fallback to integrity-only\n", eea_sel);
    }
} // if EEA0 negotiated, leave enc_ok=false to select integrity-only path
```

### 修正後（Option A: EEA0専用ブロック追加）

```c
s1n2_nas_encryption_alg_t enc_alg = S1N2_NAS_EEA0;
if (eea_sel == 2) {
    enc_alg = S1N2_NAS_EEA2;
}
uint8_t cipher[384];
bool enc_ok = false;

// Handle EEA0: null cipher (identity function)
if (enc_alg == S1N2_NAS_EEA0) {
    // EEA0 = null cipher: output = input (no transformation)
    // Still use Type 2 format (0x27) for proper message structure
    memcpy(cipher, out, out_off);
    enc_ok = true;
    printf("[INFO] NAS EEA0 (null cipher) applied: data unchanged, using Type 2 format\n");
} else if (enc_alg == S1N2_NAS_EEA2) {
    // Handle EEA2: actual AES-CTR encryption
    if (s1n2_nas_encrypt(enc_alg, security_cache->k_nas_enc, count_dl, 0 /*bearer*/, 1 /*DL*/, out, out_off, cipher) == 0) {
        enc_ok = true;
    } else {
        printf("[WARN] NAS EEA2 encryption failed, will fallback to integrity-only\n");
    }
} else {
    // Other algorithms (EEA1, EEA3) not implemented
    printf("[WARN] NAS EEA%u not implemented, will fallback to integrity-only\n", eea_sel);
}
```

### 変更点の説明

#### 1. EEA0専用ブロック追加

```c
if (enc_alg == S1N2_NAS_EEA0) {
    memcpy(cipher, out, out_off);  // ← 恒等変換（暗号化なし）
    enc_ok = true;                  // ← Type 2を使用するためtrue
    printf("[INFO] NAS EEA0 (null cipher) applied: data unchanged, using Type 2 format\n");
}
```

**ポイント**:
- `memcpy(cipher, out, out_off)`: 平文をそのまま"cipher"にコピー
- `enc_ok = true`: Type 2パス（0x27）を選択
- ログメッセージで意図を明確化

#### 2. EEA2ブロックの条件変更

```c
} else if (enc_alg == S1N2_NAS_EEA2) {  // ← "if"から"else if"に変更
```

**理由**: EEA0を別ブロックで処理するため

#### 3. その他のアルゴリズムのフォールバック

```c
} else {
    printf("[WARN] NAS EEA%u not implemented, will fallback to integrity-only\n", eea_sel);
}
```

**理由**: EEA1, EEA3などの未実装アルゴリズムの処理

---

## 🔍 修正後の動作確認ポイント

### 1. ログメッセージの確認

**期待されるログ（EEA0時）**:
```
[INFO] NAS EEA0 (null cipher) applied: data unchanged, using Type 2 format
[INFO] Wrapped Attach Accept with NAS cipher+integrity (EEA=0,EIA=2, COUNT-DL=0x00000001, SEQ=1)
[DEBUG] MAC=XX XX XX XX
```

**重要**: "integrity (fallback or EEA0-negotiated)"ではなく、"cipher+integrity"が表示される

### 2. Wiresharkでの確認

**pcapファイル解析**:
```bash
tshark -r <new_test>.pcap -Y "s1ap.nas_pdu" -V | grep "Security header"
```

**期待される出力**:
```
Security header type: Integrity protected and ciphered (2)
                                ^^^^^^^^^^^^^^^^^^^^^^^^^ ← Type 2
```

### 3. RRCメッセージの確認

**RRCキャプチャ（UDP port 4337）**:
```bash
tcpdump -i br-sXGP-5G -n port 4337 -w <timestamp>_rrc.pcap
```

**期待される動作**:
```
1. eNB → UE: RRC Connection Reconfiguration (Type 2 Attach Accept)
2. UE → eNB: RRC Connection Reconfiguration Complete ← これが来る！
3. ICS Success
```

### 4. S1AP ICS Responseの確認

**期待されるS1APメッセージ**:
```bash
tshark -r <new_test>.pcap -Y "s1ap.procedureCode == 9" -V
```

**期待される出力**:
```
InitialContextSetupResponse
  E-RABSetupListCtxtSURes
    E-RABSetupItemCtxtSURes
      e-RAB-ID: 5
      transportLayerAddress: ...
      gTP-TEID: ...
```

**重要**: Cause 26 (Radio resources not available)が**出ない**こと

---

## 🧪 テスト計画

### Phase 1: ビルドとデプロイ

```bash
# 1. コード修正
vim /home/taihei/docker_open5gs_sXGP-5G/sXGP-5G/src/nas/s1n2_nas.c

# 2. ビルド
cd /home/taihei/docker_open5gs_sXGP-5G
docker compose build s1n2

# 3. コンテナ再起動
docker compose down s1n2
docker compose up -d s1n2

# 4. ログ確認
docker compose logs -f s1n2
```

### Phase 2: パケットキャプチャ準備

**ターミナル1: S1AP/NAS キャプチャ**
```bash
sudo tcpdump -i br-sXGP-5G -w /home/taihei/docker_open5gs_sXGP-5G/log/20251112_7.pcap \
  'sctp port 36412 or sctp port 38412 or tcp port 7777 or tcp port 80'
```

**ターミナル2: RRC キャプチャ**
```bash
sudo tcpdump -i br-sXGP-5G -n port 4337 -w /home/taihei/docker_open5gs_sXGP-5G/log/$(date +%Y%m%d_%H%M%S)_rrc.pcap
```

### Phase 3: UE接続テスト

```bash
# UEを接続（実機）
# Attach手順を実行
```

### Phase 4: 結果検証

#### A. ログ解析
```bash
# s1n2ログでType 2使用を確認
docker compose logs s1n2 | grep "Wrapped Attach Accept"
# 期待: "cipher+integrity (EEA=0,EIA=2"

# ICS Responseを確認
docker compose logs s1n2 | grep "InitialContextSetup"
# 期待: "InitialContextSetupResponse" (not Failure)
```

#### B. pcap解析
```bash
# Security Header Type確認
tshark -r /home/taihei/docker_open5gs_sXGP-5G/log/20251112_7.pcap \
  -Y "s1ap.procedureCode == 9" -V | grep "Security header"
# 期待: "Integrity protected and ciphered (2)"

# ICS Response確認
tshark -r /home/taihei/docker_open5gs_sXGP-5G/log/20251112_7.pcap \
  -Y "s1ap.procedureCode == 9" -T fields -e s1ap.procedureCode -e s1ap.Cause
# 期待: 空（Causeなし = Success）
```

#### C. RRC解析
```bash
# RRC Reconfiguration Complete確認
tshark -r /home/taihei/docker_open5gs_sXGP-5G/log/<timestamp>_rrc.pcap -t a
# 期待: UEからのuplink message（~100 bytes程度）がある
```

---

## 📋 成功基準

### ✅ 必須条件（全て満たす必要あり）

1. **ビルド成功**: s1n2コンテナが正常にビルドされる
2. **Type 2使用**: ログに"cipher+integrity (EEA=0"が表示される
3. **pcap確認**: Security header type = 2 (Integrity protected and ciphered)
4. **RRC Complete**: UEからRRC Connection Reconfiguration Completeが送信される
5. **ICS Success**: InitialContextSetupResponse（Cause 26なし）
6. **Bearer確立**: E-RABSetupListCtxtSURes に bearer情報が含まれる

### 🎯 最終目標

**UE接続成功**:
- Attach Accept処理成功
- Default bearer確立
- データ通信可能（ping/curl）

---

## 🚨 リスク分析

### Low Risk ✅

**変更箇所**:
- 既存のロジックを置き換えではなく、条件分岐を追加
- EEA2の処理は変更なし
- フォールバック（Type 1）は維持（他のエラー時のため）

**影響範囲**:
- Attach Accept生成のみ
- 他のNASメッセージ（Security Mode Command, TAU Accept等）には影響なし

### Rollback Plan 🔄

**問題発生時**:
```bash
# 1. 元のコードに戻す
git checkout sXGP-5G/src/nas/s1n2_nas.c

# 2. 再ビルド
docker compose build s1n2
docker compose restart s1n2
```

**バックアップ**:
```bash
# 修正前のコードを保存
cp sXGP-5G/src/nas/s1n2_nas.c sXGP-5G/src/nas/s1n2_nas.c.backup_20251112
```

---

## 📊 予想される結果

### 修正前（現在）

```
eNB → Core: Initial UE Message (Attach Request)
Core → eNB: ICS Request (Type 1 Attach Accept) ← 0x17
eNB → UE:   RRC Reconfiguration (with Type 1 NAS)
UE:         [サイレント拒否] ← Type 1は不適切
eNB:        [タイムアウト 41ms+]
eNB → Core: ICS Failure (Cause 26) ❌
```

### 修正後（期待）

```
eNB → Core: Initial UE Message (Attach Request)
Core → eNB: ICS Request (Type 2 Attach Accept) ← 0x27
eNB → UE:   RRC Reconfiguration (with Type 2 NAS)
UE → eNB:   RRC Reconfiguration Complete ✅
eNB → Core: ICS Response (E-RAB Setup Success) ✅
UE → Core:  Attach Complete
Core → UE:  [Default Bearer Active] ✅
```

---

## 🎓 技術的背景

### 3GPP TS 24.301 の解釈

**Section 5.4.3.2 - Security header type**:

| Value | Type | Description |
|-------|------|-------------|
| 0 | Plain | Not security protected |
| 1 | Integrity protected | Integrity protected with **new** EPS security context |
| 2 | Integrity protected and ciphered | Integrity protected and **ciphered** with **new** EPS security context |
| 3 | Integrity protected (old) | With current EPS security context |
| 4 | Integrity protected and ciphered (old) | With current EPS security context |

**重要な点**:
- Type 1 = "Integrity protected" (新しいコンテキスト)
- Type 2 = "Integrity protected and ciphered" (新しいコンテキスト)
- **"ciphered"は"フォーマット"を意味し、実際の暗号化アルゴリズムは別途指定**

### EEA0の定義

**3GPP TS 33.401 Annex B**:
```
EEA0: Null ciphering algorithm
  - Input:  plaintext
  - Output: plaintext (unchanged)
  - Purpose: Testing, development, or when confidentiality is not required
```

**重要**: EEA0は"暗号化アルゴリズム"の一種であり、"暗号化しない"とは異なる。

### Type 2 + EEA0の組み合わせ

**正当な組み合わせ**:
- Message structure: Type 2 format (0x27)
- Encryption algorithm: EEA0 (null cipher)
- Result: Type 2 format + plaintext payload

**実装例（Open5GS MME）**:
```c
// Open5GS always uses Type 2 for Attach Accept
nas_security_header_type = OGS_NAS_SECURITY_HEADER_INTEGRITY_PROTECTED_AND_CIPHERED;

// Then apply the negotiated algorithm (even if EEA0)
if (ue->security.selected_enc_alg == OGS_NAS_SECURITY_ALGORITHMS_EEA0) {
    // EEA0: no actual encryption, but still use Type 2 format
    memcpy(ciphered, plain, len);
}
```

---

## 📝 修正サマリー

### 変更箇所

**ファイル**: `sXGP-5G/src/nas/s1n2_nas.c`
**行**: ~2274 (暗号化処理ブロック)

### 変更内容

**Before**:
```c
if (enc_alg != S1N2_NAS_EEA0) {
    // Only encrypt if NOT EEA0
    enc_ok = true;
}
// EEA0: enc_ok = false → Type 1 (0x17)
```

**After**:
```c
if (enc_alg == S1N2_NAS_EEA0) {
    // EEA0: null cipher, but use Type 2 format
    memcpy(cipher, out, out_off);
    enc_ok = true;  // → Type 2 (0x27)
} else if (enc_alg == S1N2_NAS_EEA2) {
    // EEA2: actual encryption
    enc_ok = true;  // → Type 2 (0x27)
}
// Both cases use Type 2 format
```

### 期待される効果

1. ✅ EEA0でもType 2 (0x27)を使用
2. ✅ UEがAttach Acceptを正常に処理
3. ✅ RRC Connection Reconfiguration Completeが送信される
4. ✅ ICS Success
5. ✅ Default bearer確立
6. ✅ UE接続成功

---

## 次のステップ

1. ✅ 修正方針確定（このドキュメント）
2. 📝 コード修正実施
3. 🔨 ビルドとデプロイ
4. 🧪 実機テスト
5. 📊 結果検証
6. 📄 ドキュメント更新

**準備完了！コード修正を開始しますか？** 🚀
