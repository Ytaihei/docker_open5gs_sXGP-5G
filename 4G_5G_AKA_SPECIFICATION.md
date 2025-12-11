# 4G/5G AKA (Authentication and Key Agreement) 仕様整理

## 目次
1. [4G EPS-AKA (LTE)](#1-4g-eps-aka-lte)
2. [5G 5G-AKA](#2-5g-5g-aka)
3. [5G→4G Interworking](#3-5g4g-interworking)
4. [実装における課題](#4-実装における課題)

---

## 1. 4G EPS-AKA (LTE)

### 1.1 参照規格
- **3GPP TS 33.401**: Security architecture for System Architecture Evolution (SAE)
  - Annex A.2: Key derivation for EPS
  - Annex A.3: KeNB derivation

### 1.2 鍵階層構造

```
                         K (Permanent key in USIM)
                               |
                    +----------+----------+
                    |                     |
                   CK                    IK
            (Cipher Key)          (Integrity Key)
                    |                     |
                    +----------+----------+
                               |
                          CK || IK (32 bytes)
                               |
                    +----------v----------+
                    | KDF (FC=0x10)      |  ← 4G native key derivation
                    | TS 33.401 A.2      |
                    | Input: SQN⊕AK, PLMN|
                    +--------------------+
                               |
                           KASME (32 bytes)
                               |
              +----------------+----------------+
              |                                 |
         K_NASenc                           K_NASint
      (NAS encryption)                 (NAS integrity)
              |                                 |
         +----v----+                       +----v----+
         | EEA0-3  |                       | EIA0-3  |
         +---------+                       +---------+
              |
              +----------------+----------------+
                               |
                          KeNB (32 bytes)
                               |
                    +----------v----------+
                    | KDF (FC=0x11)      |  ← KeNB derivation
                    | TS 33.401 A.3      |
                    | Input: NAS UL COUNT|
                    +--------------------+
                               |
              +----------------+----------------+
              |                                 |
         K_UPenc                            K_RRCint
      (User plane)                       (RRC integrity)
```

### 1.3 主要KDF (Key Derivation Function)

#### 1.3.1 KASME導出 (FC=0x10)
```c
// TS 33.401 A.2
Input:
  - Key: CK || IK (32 bytes)
  - FC: 0x10 (4G native KASME derivation)
  - P0: Service Network name (SNN)
  - L0: length of SNN
  - P1: SQN ⊕ AK (6 bytes)
  - L1: 0x00 0x06

Output:
  - KASME (32 bytes)

Algorithm: HMAC-SHA-256
S = FC || P0 || L0 || P1 || L1
KASME = HMAC-SHA-256(Key=CK||IK, Data=S)
```

#### 1.3.2 K_NAS導出
```c
// TS 33.401 A.7
Input:
  - Key: KASME (32 bytes)
  - FC: 0x15 (NAS key derivation)
  - P0: Algorithm type distinguisher (0x01=enc, 0x02=int)
  - L0: 0x00 0x01
  - P1: Algorithm identifier (e.g., 0x02 for EIA2/EEA2)
  - L1: 0x00 0x01

Output:
  - K_NASenc or K_NASint (32 bytes, use first 16 bytes)

Algorithm: HMAC-SHA-256
```

#### 1.3.3 KeNB導出 (FC=0x11)
```c
// TS 33.401 A.3
Input:
  - Key: KASME (32 bytes)
  - FC: 0x11 (KeNB derivation)
  - P0: NAS uplink COUNT (4 bytes)
  - L0: 0x00 0x04

Output:
  - KeNB (32 bytes)

Algorithm: HMAC-SHA-256
S = FC || P0 || L0
KeNB = HMAC-SHA-256(Key=KASME, Data=S)
```

### 1.4 プロトコルフロー

```
UE                    eNB                   MME                   HSS
|                      |                     |                     |
|--- Attach Request -->|                     |                     |
|                      |--- S1: Initial UE ->|                     |
|                      |       Message       |                     |
|                      |                     |                     |
|                      |                     |<-- Authentication ->|
|                      |                     |    Data Request     |
|                      |                     |                     |
|                      |                     |    (HSS generates   |
|                      |                     |     RAND, AUTN,     |
|                      |                     |     XRES, KASME)    |
|                      |                     |                     |
|                      |                     |<-- Authentication --|
|                      |                     |    Data Response    |
|                      |                     |    (RAND, AUTN,     |
|                      |                     |     XRES, KASME)    |
|                      |                     |                     |
|                      |<-- Auth Request ----|                     |
|<-- Auth Request -----|                     |                     |
|                      |                     |                     |
| [UE derives CK, IK]  |                     |                     |
| [UE derives KASME]   |                     |                     |
|                      |                     |                     |
|--- Auth Response --->|                     |                     |
|                      |--- Auth Response -->|                     |
|                      |                     | [MME verifies RES]  |
|                      |                     |                     |
|                      |<-- Security Mode ---|                     |
|<-- Security Mode ----|    Command          |                     |
|                      |                     |                     |
| [UE derives K_NASenc,|                     |                     |
|  K_NASint from KASME]|                     |                     |
|                      |                     |                     |
|--- Security Mode --->|                     |                     |
|    Complete          |--- Security Mode -->|                     |
|    (with MAC)        |    Complete         |                     |
|                      |                     | [MME verifies MAC]  |
|                      |                     |                     |
|                      |<-- Initial Context--|                     |
|                      |    Setup Request    |                     |
|                      |    (KeNB, E-RAB)    |                     |
|                      |                     |                     |
| [UE derives KeNB     |                     | [MME derives KeNB   |
|  from KASME + COUNT] |                     |  from KASME + COUNT]|
|                      |                     |                     |
|<-- RRC Security ---  |                     |                     |
|    Mode Command      | [eNB derives        |                     |
|                      |  K_RRCenc, K_RRCint |                     |
|                      |  from KeNB]         |                     |
|                      |                     |                     |
|--- RRC Security ---> |                     |                     |
|    Mode Complete     |                     |                     |
|                      |                     |                     |
|<-- RRC Reconfiguration                     |                     |
|    (E-RAB setup)     |                     |                     |
|--- RRC Reconfig ---> |                     |                     |
|    Complete          |                     |                     |
|                      |--- ICS Response --->|                     |
|                      |                     |                     |
```

### 1.5 重要なポイント

1. **UEとMMEの対称性**:
   - 両者とも同じ K (USIM内) を持つ
   - 両者とも同じ RAND, SQN⊕AK を使う
   - 結果: 同じ CK, IK → 同じ KASME → 同じ K_NASenc/int

2. **KeNBの導出タイミング**:
   - Security Mode Command送信時にNAS UL COUNTを使用
   - MME: Security Mode Commandの送信前にCOUNTを記録
   - UE: Security Mode Completeの送信時にCOUNTを使用
   - **重要**: 両者で同じCOUNT値を使う必要がある

3. **NAS COUNT管理**:
   - DL (Downlink): MME → UE方向
   - UL (Uplink): UE → MME方向
   - Security Mode Command後に新しいセキュリティコンテキストが有効化
   - COUNT値はKeNB導出に使用される

---

## 2. 5G 5G-AKA

### 2.1 参照規格
- **3GPP TS 33.501**: Security architecture and procedures for 5G System
  - Annex A.2: Kausf derivation
  - Annex A.6: Kseaf derivation  
  - Annex A.7: Kamf derivation
  - Annex A.9: KgNB derivation
  - Annex A.11: KASME derivation from Kamf (5G→4G interworking)

### 2.2 鍵階層構造

```
                         K (Permanent key in USIM)
                               |
                    +----------+----------+
                    |                     |
                   CK                    IK
            (Cipher Key)          (Integrity Key)
                    |                     |
                    +----------+----------+
                               |
                          CK || IK (32 bytes)
                               |
                    +----------v----------+
                    | KDF (FC=0x6A)      |  ← 5G Kausf derivation
                    | TS 33.501 A.2      |
                    | Input: SNN, SQN⊕AK |
                    | ABBA              |
                    +--------------------+
                               |
                           Kausf (32 bytes)
                               |
                    +----------v----------+
                    | KDF (FC=0x6C)      |  ← Kseaf derivation
                    | TS 33.501 A.6      |
                    | Input: SNN         |
                    +--------------------+
                               |
                           Kseaf (32 bytes)
                               |
                    +----------v----------+
                    | KDF (FC=0x6D)      |  ← Kamf derivation
                    | TS 33.501 A.7      |
                    | Input: SUPI, ABBA  |
                    +--------------------+
                               |
                           Kamf (32 bytes)
                               |
              +----------------+----------------+
              |                                 |
         K_NASenc                           K_NASint
      (5G NAS encryption)              (5G NAS integrity)
              |                                 |
         +----v----+                       +----v----+
         | NEA0-3  |                       | NIA0-3  |
         +---------+                       +---------+
              |
              +----------------+
                               |
                          KgNB (32 bytes)
                               |
                    +----------v----------+
                    | KDF (FC=0x70)      |  ← KgNB derivation (5G)
                    | TS 33.501 A.9      |
                    | Input: NAS UL COUNT|
                    +--------------------+
                               |
              +----------------+----------------+
              |                                 |
         K_UPenc                            K_RRCint
      (User plane)                       (RRC integrity)
```

### 2.3 主要KDF

#### 2.3.1 Kausf導出 (FC=0x6A)
```c
// TS 33.501 A.2
Input:
  - Key: CK || IK (32 bytes)
  - FC: 0x6A (Kausf derivation)
  - P0: Service Network Name (SNN)
       Format: "5G:mnc<MNC>.mcc<MCC>.3gppnetwork.org"
  - L0: length of SNN (2 bytes)
  - P1: SQN ⊕ AK (6 bytes)
  - L1: 0x00 0x06

Output:
  - Kausf (32 bytes)

Algorithm: HMAC-SHA-256
```

#### 2.3.2 Kseaf導出 (FC=0x6C)
```c
// TS 33.501 A.6
Input:
  - Key: Kausf (32 bytes)
  - FC: 0x6C (Kseaf derivation)
  - P0: Service Network Name (SNN)
  - L0: length of SNN (2 bytes)

Output:
  - Kseaf (32 bytes)

Algorithm: HMAC-SHA-256
```

#### 2.3.3 Kamf導出 (FC=0x6D)
```c
// TS 33.501 A.7
Input:
  - Key: Kseaf (32 bytes)
  - FC: 0x6D (Kamf derivation)
  - P0: SUPI (Subscription Permanent Identifier)
       Format: "imsi-<IMSI>" (e.g., "imsi-001011234567895")
  - L0: length of SUPI (2 bytes)
  - P1: ABBA (2 bytes, typically 0x0000)
  - L1: 0x00 0x02

Output:
  - Kamf (32 bytes)

Algorithm: HMAC-SHA-256
```

#### 2.3.4 KgNB導出 (FC=0x70)
```c
// TS 33.501 A.9
Input:
  - Key: Kamf (32 bytes)
  - FC: 0x70 (KgNB derivation)
  - P0: NAS uplink COUNT (4 bytes)
  - L0: 0x00 0x04

Output:
  - KgNB (32 bytes)

Algorithm: HMAC-SHA-256
```

### 2.4 ABBA (Anti-Bidding down Between Architectures)

**目的**: 5G → 4G へのダウングレード攻撃を防ぐ

**仕様**: TS 33.501 Section 6.12.3
- 2バイトのパラメータ
- 5G Authentication Requestに含まれる
- 通常の値: `0x0000`
- Kamf導出の入力として使用される

**重要な制約**:
- **4G UEはABBAを理解しない**
- 4G UEは ABBAを受信しても無視する
- 4G UEは常に 4G native key derivation (FC=0x10) を使用

### 2.5 プロトコルフロー

```
UE                   gNB                    AMF                   AUSF/UDM
|                     |                      |                      |
|--- Registration --->|                      |                      |
|    Request          |--- Initial UE ------>|                      |
|                     |    Message           |                      |
|                     |                      |                      |
|                     |                      |-- Auth Request ----->|
|                     |                      |                      |
|                     |                      |    [AUSF generates   |
|                     |                      |     RAND, AUTN,      |
|                     |                      |     Kausf, Kseaf]    |
|                     |                      |                      |
|                     |                      |<-- Auth Response ----|
|                     |                      |    (RAND, AUTN,      |
|                     |                      |     HXRES*, Kseaf)   |
|                     |                      |                      |
|                     |<-- Auth Request -----|                      |
|                     |    (RAND, AUTN, ABBA)|                      |
|<-- Auth Request ----|                      |                      |
|                     |                      |                      |
| [UE derives CK, IK] |                      |                      |
| [UE derives Kausf]  |                      |                      |
| [UE derives Kseaf]  |                      |                      |
| [UE derives Kamf]   |                      |                      |
| [UE computes RES*]  |                      |                      |
|                     |                      |                      |
|--- Auth Response -->|                      |                      |
|    (RES*)           |--- Auth Response --->|                      |
|                     |                      | [AMF verifies RES*]  |
|                     |                      | [AMF derives Kamf    |
|                     |                      |  from Kseaf]         |
|                     |                      |                      |
|                     |<-- Security Mode ----|                      |
|<-- Security Mode ---|    Command           |                      |
|                     |                      |                      |
| [UE derives K_NASenc,                      |                      |
|  K_NASint from Kamf]|                      |                      |
|                     |                      |                      |
|--- Security Mode -->|                      |                      |
|    Complete (MAC)   |--- Security Mode --->|                      |
|                     |    Complete          | [AMF verifies MAC]   |
|                     |                      |                      |
|                     |<-- Initial Context --|                      |
|                     |    Setup Request     |                      |
|                     |    (KgNB, PDU Session)                      |
|                     |                      |                      |
| [UE derives KgNB    |                      | [AMF derives KgNB    |
|  from Kamf + COUNT] |                      |  from Kamf + COUNT]  |
|                     |                      |                      |
```

---

## 3. 5G→4G Interworking

### 3.1 参照規格
- **3GPP TS 33.501 Annex A.11**: KASME derivation from Kamf

### 3.2 Kamf → KASME 変換 (FC=0x71)

```c
// TS 33.501 A.11: For 5G to 4G mobility
Input:
  - Key: Kamf (32 bytes)
  - FC: 0x71 (KASME derivation from Kamf)
  - P0: NAS uplink COUNT (4 bytes)
  - L0: 0x00 0x04

Output:
  - KASME (32 bytes)

Algorithm: HMAC-SHA-256
S = FC || P0 || L0
KASME = HMAC-SHA-256(Key=Kamf, Data=S)
```

### 3.3 鍵階層の比較

```
4G Native Path:
CK||IK --[FC=0x10]--> KASME --[FC=0x11]--> KeNB

5G Path:
CK||IK --[FC=0x6A]--> Kausf --[FC=0x6C]--> Kseaf --[FC=0x6D]--> Kamf --[FC=0x70]--> KgNB

5G→4G Interworking Path:
CK||IK --[FC=0x6A]--> Kausf --[FC=0x6C]--> Kseaf --[FC=0x6D]--> Kamf --[FC=0x71]--> KASME --[FC=0x11]--> KeNB
```

### 3.4 重要な相違点

| 項目 | 4G Native | 5G → 4G Interworking |
|------|-----------|----------------------|
| KASME導出 | FC=0x10 (CK\|\|IK → KASME) | FC=0x71 (Kamf → KASME) |
| 入力パラメータ | SQN⊕AK, PLMN | NAS UL COUNT |
| ABBAの影響 | ABBAなし | ABBAあり (Kamf導出に使用) |
| 導出元 | CK\|\|IK直接 | Kamf経由 |
| 結果 | KASME_4G | KASME_5G (値が異なる) |

**結論**: 同じCK||IKから導出しても、**4G nativeとInterworkingでKASMEの値は異なる**

---

## 4. 実装における課題

### 4.1 s1n2コンバータの役割

```
5G Network (NGAP)          s1n2         4G Network (S1AP)
AMF --[N2]--> s1n2 --[S1]--> MME/eNB
              ↓
        鍵変換が必要
```

### 4.2 4G UE + 5G Core の組み合わせ

**問題の本質**:
- UE: 4G専用 → 4G native key derivation (FC=0x10) を使用
- AMF: 5G → ABBAを送信、5G key hierarchy (FC=0x6A→0x6C→0x6D) を使用

**結果**:
- UE: CK||IK --[FC=0x10]--> KASME_UE
- AMF: CK||IK --[FC=0x6A]--> Kausf → Kseaf → Kamf
- s1n2が Kamf --[FC=0x71]--> KASME_s1n2 しても:
  - KASME_UE ≠ KASME_s1n2 (導出方法が異なる)

### 4.3 解決策: s1n2での4G Native再現

**アプローチ**:
s1n2がAMFの5G鍵階層を無視し、UEと同じ4G native方式を使用

```c
// s1n2の実装
// 1. Authentication Request処理時:
//    - RANDとSQN⊕AKをキャッシュ
//    - Ki, OPc (HSS/UDMから取得済み) を使用

// 2. Authentication Response処理時:
//    - Milenage: Ki + OPc + RAND → CK, IK
//    - KDF(FC=0x10): CK||IK + SQN⊕AK + PLMN → KASME
//    - KASME をキャッシュ (ue_mapping->kasme)

// 3. Security Mode Command変換時:
//    - キャッシュされた KASME から K_NASenc, K_NASint を導出
//    - 4G Security Mode Command に変換

// 4. Initial Context Setup変換時:
//    - キャッシュされた KASME を使用
//    - KDF(FC=0x11): KASME + NAS_COUNT → KeNB
//    - AMFから受信した KgNB は使用しない
```

**利点**:
- UEとs1n2で完全に同じKASME → 同じKeNB
- 5G CoreのABBAは無視される (4G UEの動作と一致)
- MAC検証、RRCセキュリティが正常動作

### 4.4 NAS COUNT管理

**重要**: KeNB導出に使用するNAS COUNTは、Security Mode Command送信時の値

```c
// Security Mode Command送信時のCOUNT
- MME (s1n2): Security Mode Command送信前のDL COUNT
- UE: Security Mode Complete送信時のUL COUNT (通常は0)

// 典型的な値:
- 初回Attach: COUNT = 0
- 再認証: COUNT = 前回のCOUNT + Security Modeメッセージ数
```

### 4.5 実装時の注意点

1. **KASME のキャッシュ**:
   ```c
   // NG: KASME を導出後に memset() で消去
   memset(kasme, 0, sizeof(kasme));  // ← KeNB導出で使えなくなる
   
   // OK: KASME をUEマッピングに保存
   memcpy(ue_mapping->kasme, kasme, 32);
   ue_mapping->has_kasme = true;
   ```

2. **ABBAの扱い**:
   ```c
   // 4G UE用実装
   bool use_5g_aka = false;  // 4G UEはABBAを無視
   
   if (ue_mapping->abba_len == 2 && use_5g_aka) {
       // 5G-AKA path (5G UE用、現在未実装)
       s1n2_kdf_kasme_from_kamf(...);
   } else {
       // 4G native path (4G UE用、常にこちら)
       s1n2_derive_4g_nas_keys(...);
   }
   ```

3. **NAS COUNT同期**:
   ```c
   // Security Mode Command送信時にCOUNTをキャッシュ
   ue_mapping->nas_count_for_kenb = ue_mapping->nas_dl_count;
   
   // ICS送信時にキャッシュされたCOUNTを使用
   uint32_t count = ue_mapping->nas_count_for_kenb;
   s1n2_kdf_kenb(ue_mapping->kasme, count, kenb_out);
   ```

### 4.6 デバッグのポイント

**鍵導出の検証**:
```bash
# s1n2ログで確認すべき項目:
# 1. KASME導出方法
[INFO] 4G NAS keys derived for UE (4G native method)  # ← FC=0x10使用

# 2. KASME値
[DEBUG] K_ASME: 9b2428a449227298...

# 3. K_NASint値 (Security Mode Command MAC計算で使用)
[DEBUG] K_NASint: 248FB360876457A4...

# 4. KeNB導出
[INFO] [KDF] KeNB derivation from KASME (TS 33.401 A.3)
[INFO] [KDF]   FC = 0x11 (KeNB derivation)
[INFO] [KDF]   NAS_COUNT = 0x00000000

# 5. KeNB値
[INFO] [KDF]   Output KeNB (32 bytes):
[INFO] [KDF]     0b8560fee221e463...
```

**UE側の検証** (eNBログまたはWireshark):
```
# Security Mode Complete の MAC
# → UEが計算したMAC、s1n2が検証

# RRC Security Mode Command の MAC
# → eNBが計算したMAC (KeNBから導出した鍵を使用)
```

---

## 5. まとめ

### 5.1 鍵導出パスの選択基準

| UEタイプ | AMF設定 | s1n2の動作 | 使用する導出パス |
|----------|---------|-----------|-----------------|
| 4G専用   | ABBAあり | 4G native再現 | CK\|\|IK --[FC=0x10]--> KASME |
| 4G専用   | ABBAなし | 4G native再現 | CK\|\|IK --[FC=0x10]--> KASME |
| 5G対応   | ABBAあり | 5G-AKA使用 | Kamf --[FC=0x71]--> KASME |
| 5G対応   | ABBAなし | 4G native再現 | CK\|\|IK --[FC=0x10]--> KASME |

### 5.2 実装ステータス (現在のs1n2)

- ✅ 4G native key derivation実装済み
- ✅ KASME, K_NASenc, K_NASint 導出動作確認
- ✅ KeNB導出動作確認  
- ✅ Security Mode Complete成功
- ⚠️ Initial Context Setup: 送信済みだが eNB側でエラー
- ❌ 5G UE対応: 未実装 (use_5g_aka=false固定)

### 5.3 次のステップ

1. ICS失敗の原因調査 (鍵以外の問題の可能性)
2. eNB側のエラー詳細ログ確認
3. 必要に応じてICSメッセージ構造の調整

---

## 参考資料

- 3GPP TS 33.401 V16.0.0 (2020-07)
- 3GPP TS 33.501 V16.0.0 (2020-07)  
- 3GPP TS 24.301 V16.0.0 (2020-07) - NAS protocol
- 3GPP TS 36.331 V16.0.0 (2020-07) - RRC protocol
- 3GPP TS 38.331 V16.0.0 (2020-07) - 5G NR RRC

---

*Last updated: 2025-11-14*
