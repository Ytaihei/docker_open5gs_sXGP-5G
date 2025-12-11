# 🔬 COUNT二重増分修正後テスト結果分析
## Test Date: 2025年11月12日 12:39-12:45

---

## 📋 Executive Summary

**結果**: ❌ **Registration Reject発生 - 新たな問題発覚**

### 重大な発見 🚨
COUNT二重増分を修正したことで、**全く別の問題**が明らかになりました：

1. **AMF側でRegistration Reject (Cause=95)が発生**
2. **IMSI/SUCIの不一致問題**が根本原因
3. **ICS Failureよりも前の段階**（Authentication）で失敗

---

## 🔍 問題の詳細分析

### 1. Registration Reject の原因

#### AMFログの証拠（amf-s1n2）
```
11/12 12:40:29.095: [gmm] INFO: [suci-0-421-80-0000-0-0-90010112] SUCI
11/12 12:40:29.097: [gmm] ERROR: [suci-0-421-80-0000-0-0-90010112] HTTP response error [400]
11/12 12:40:29.097: [amf] WARNING: [suci-0-421-80-0000-0-0-90010112] Registration reject [95]
```

**原因**: AUSF (Authentication Server Function)がHTTP 400エラーを返した
**Reject Cause 95**: `Semantically incorrect message`

#### s1n2ログの証拠
```
[DEBUG] Extracted NAS-PDU via ASN.1 parse (len=111)
[INFO] Converting 4G message type 0x21 -> 5G Registration Request (0x41)
[DEBUG] decode_imsi: Decoded IMSI=4218090010112 (len=13)
[INFO] Successfully extracted IMSI: 4218090010112
[SUCCESS] Cached IMSI in UE mapping: 4218090010112 (ENB-UE-ID=11, RAN-UE-ID=11)

↓ NGAPメッセージでは

[DEBUG] 5G Registration Request created (len=24, IMSI=4218090010112)
[DEBUG] SUCI payload (len=12): 01 24 F1 08 00 00 00 00 09 10 10 21
```

### 2. IMSI/SUCIマッピングの問題

#### 成功ケース（以前のテスト）
- **IMSI**: `001011234567895`
- **SUCI**: `suci-0-001-01-0000-0-0-1234567895`
- **PLMN**: MCC=001, MNC=01
- **結果**: ✅ Registration Accept

#### 失敗ケース（今回のテスト）
- **IMSI**: `4218090010112`
- **SUCI**: `suci-0-421-80-0000-0-0-90010112` ⚠️
- **PLMN**: MCC=421, MNC=80 ⚠️
- **結果**: ❌ Registration Reject (Cause=95)

### 3. 問題の根本原因

**s1n2のSUCI生成ロジックに誤り**:
```c
// SUCI payload (len=12): 01 24 F1 08 00 00 00 00 09 10 10 21
//                        ↑  ↑  ↑  ↑
//                        |  |  |  └─ PLMN ID: 24 F1 08 = MCC=421, MNC=80
//                        |  |  └───── Routing Indicator (00)
//                        |  └──────── SUCI format (F1 = NAI format?)
//                        └─────────── Type (01 = SUCI)
```

**期待されるSUCI**（成功ケースと同じPLMN）:
- **MCC**: 001 (not 421)
- **MNC**: 01 (not 80)
- **SUCI**: `suci-0-001-01-0000-0-0-...`

**実際のSUCI**（4G SIMから読み取ったIMSIベース）:
- **MCC**: 421 ← 4G SIMのPLMN
- **MNC**: 80  ← 4G SIMのPLMN
- **SUCI**: `suci-0-421-80-0000-0-0-90010112`

### 4. データベース不整合

#### UDMに登録されているSubscriber
```
IMSI: 001011234567895
PLMN: MCC=001, MNC=01
```

#### 実際のUE（4G SIM）
```
IMSI: 421809001011X
PLMN: MCC=421, MNC=80
```

**結果**: AUSFがSubscriberを見つけられず、HTTP 400エラー

---

## 📊 テスト結果の整理

### A. COUNT二重増分修正の効果

#### 修正前（20251112_9.pcap）
```
Security Mode Command: COUNT 0→2 (二重増分)
Attach Accept:         COUNT 2→3
Result: SEQ=2 で成功（たまたま）
```

#### 修正後（今回）
```
No Security Mode Command sent (Registration Rejectで停止)
ICS Failureに到達せず
```

**評価**: COUNT修正の効果を**評価不可**（より前の段階で失敗）

### B. プロトコルフロー

#### 1. S1 Setup（成功）✅
```
Frame 37: eNB → s1n2: S1SetupRequest
Frame 41: s1n2 → eNB: S1SetupResponse
```

#### 2. Initial UE Message（成功）✅
```
s1n2: InitialUEMessage (4G) received
s1n2: Converting to NGAP InitialUEMessage (5G)
s1n2: IMSI=4218090010112 extracted
s1n2: SUCI=suci-0-421-80-0000-0-0-90010112 generated ⚠️
```

#### 3. Authentication（失敗）❌
```
AMF → AUSF: Authentication request for SUCI
AUSF → AMF: HTTP 400 (Subscriber not found)
AMF → s1n2: Registration Reject (Cause=95)
```

#### 4. ICS（到達せず）⏸️
```
No ICS Request sent
No Cause 26
```

### C. pcap分析

#### コア側pcap（20251112_10.pcap）
- **S1AP**: S1 Setup成功を確認
- **NGAP**: AMF-s1n2間の通信正常
- **NAS**: Registration Rejectのみ（Security Mode Command/Attach Acceptなし）

#### RRC側pcap（20251112_123949_rrc.pcap）
- **UDP 4337**: eNB-UE間のRRCメッセージ
- **Frames 1-9**: RRC Connection Setup
- **Frames 10-22**: Attach手順開始、Registration Reject受信

---

## 🎯 重要な気づき

### 1. COUNT問題は「氷山の一角」だった

これまでICS Failure (Cause 26)に焦点を当てていましたが、実は：
- **Authentication段階**で失敗している
- **IMSI/SUCIマッピング**が正しくない
- **データベース登録情報**と実機SIMが不一致

### 2. 成功ケースとの違い

#### 成功ケース（Phase 1-22で使用）
```
UE: IMSI=001011234567895 (仮想/テストSIM)
DB: IMSI=001011234567895 (登録済み)
→ Authentication成功 → ICS Failureまで到達
```

#### 失敗ケース（今回）
```
UE: IMSI=421809001011X (実機SIM)
DB: IMSI=001011234567895 (登録なし)
→ Authentication失敗 → Registration Reject
```

### 3. テスト環境の問題

今回のテストは実機eNB/UEを使用していますが：
- **4G SIM**のIMSI（421-80-...）を使用
- **5Gコア**のDB（001-01-...）と不一致
- **s1n2**のSUCI生成が4G SIMのPLMNを使用

---

## 🔧 修正が必要な箇所

### Priority 1: SUCI生成ロジック修正

**Location**: `sXGP-5G/src/s1n2_converter.c`

#### 現在の実装（推測）
```c
// 4G IMSIからPLMNを抽出してSUCIを生成
// IMSI=421809001011X → SUCI=suci-0-421-80-0000-0-0-90010112
```

#### 修正案
```c
// Option A: ハードコードで5GコアのPLMNを使用
#define TARGET_5G_MCC "001"
#define TARGET_5G_MNC "01"
// SUCI=suci-0-001-01-0000-0-0-<digits>

// Option B: 設定ファイルから読み込み
// s1n2.yaml: target_plmn: {mcc: "001", mnc: "01"}

// Option C: IMSI全体を変換
// IMSI 421809001011X → 001011234567895
```

### Priority 2: データベース登録

**実機4G SIMのIMSIを5GコアDBに登録**:

```bash
# MongoDB登録
docker exec -it mongo-s1n2 mongo open5gs
db.subscribers.insertOne({
  "imsi": "421809001011X",  # 実機SIMのIMSI
  "security": {
    "k": "...",             # 実機SIMのK
    "op": "...",            # 実機SIMのOP
    "amf": "8000"
  },
  "slice": [...],
  "schema_version": 1
})
```

### Priority 3: COUNT修正の再検証

IMSI問題を解決した後、改めて：
1. Security Mode CommandのCOUNT増分を確認
2. Attach AcceptのSequence Numberを確認
3. ICS Success/Failureを確認

---

## 📈 次のステップ

### Immediate (今すぐ実施)

1. **s1n2のSUCI生成ロジックを確認**
   ```bash
   grep -n "SUCI\|suci" sXGP-5G/src/s1n2_converter.c
   grep -n "24 F1 08" sXGP-5G/src/
   ```

2. **IMSIマッピングコードを特定**
   - 4G IMSI → 5G SUCIの変換箇所
   - PLMNの抽出/設定箇所

### Short-term (本日中)

3. **SUCI生成を修正**
   - Target PLMN: MCC=001, MNC=01
   - IMSI digits: 実機SIMから抽出（後半部分）

4. **データベース登録**
   - 実機SIMのIMSI/K/OPを登録
   - または: IMSIマッピングテーブル作成

### Mid-term (明日以降)

5. **修正後の再テスト**
   - Authentication成功を確認
   - Security Mode Command到達を確認
   - ICS Failure再現を確認
   - COUNT管理の検証

6. **成功ケースとの完全な比較**
   - 全メッセージシーケンスの一致確認
   - Security設定の一致確認

---

## 📝 結論

### 今回の発見

1. **COUNT二重増分修正は正しい** ✅
   - ロジック的に適切
   - ただし効果を検証できず

2. **新たな問題を発見** 🔍
   - IMSI/SUCIマッピング不正
   - Authentication失敗（Cause=95）
   - データベース不整合

3. **問題の優先順位が変更** 📊
   ```
   Before: ICS Failure (Cause 26) が最優先
   After:  Authentication Failure (Cause 95) が最優先
   ```

### 重要なポイント

**ICS Failureに到達していない** = Security Mode Commandも送信されていない

つまり：
- COUNT管理の修正効果は**未検証**
- ICS Failure (Cause 26)の原因は**依然不明**
- まずAuthentication成功が**必須**

### 次の論理的アクション

**Option A: 実機SIMのIMSIを使用** (推奨)
- s1n2のSUCI生成を修正（MCC/MNC強制設定）
- UDMに実機SIMを登録
- **メリット**: 実環境に近いテスト

**Option B: テストSIMに変更**
- 実機UEにテストSIM（IMSI=001011234567895）を挿入
- **メリット**: 既存DB設定を利用可能
- **デメリット**: テストSIM入手が必要

**Option C: IMSIマッピング実装**
- s1n2で4G IMSI → 5G IMSI変換
- 例: 421809001011X → 001011234567895
- **メリット**: 柔軟性が高い
- **デメリット**: 実装が複雑

---

## 🔄 Phase 27の目標

1. ✅ **COUNT二重増分修正完了**
2. 🔄 **新問題発見: Authentication Failure**
3. 🎯 **次: SUCI生成修正 + IMSIマッピング**

**Status**: Registration Reject (Cause=95) by AUSF HTTP 400 error
**Root Cause**: IMSI/SUCI mismatch between 4G SIM (421-80) and 5G Core (001-01)
**Next Action**: Fix SUCI generation logic in s1n2_converter.c

---

## 📎 関連ファイル

- **コア側pcap**: `/home/taihei/docker_open5gs_sXGP-5G/log/20251112_10.pcap`
- **RRC側pcap**: `/home/taihei/docker_open5gs_sXGP-5G/log/20251112_123949_rrc.pcap`
- **s1n2ログ**: `docker logs s1n2`
- **AMFログ**: `docker logs amf-s1n2`
- **前回の分析**: `TEST_RESULT_20251112_COUNT_FIX_ANALYSIS.md`

---

**Analysis Date**: 2025年11月12日 12:50
**Analyzer**: GitHub Copilot
**Test Phase**: Phase 27 (COUNT二重増分修正後)
