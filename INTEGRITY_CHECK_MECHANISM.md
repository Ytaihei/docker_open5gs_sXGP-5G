# RRC Security Mode Integrity Check 仕組みの調査

## 問題の症状
- **InitialContextSetupFailure** (Frame 760)
- **原因**: `failure-in-radio-interface-procedure` 
- **実際の失敗**: RRC SecurityModeCommand に対する UE からの **SecurityModeFailure**

## Integrity Check の仕組み (UE ↔ eNB ↔ MME)

### 1. NAS層のIntegrity Protection (UE ↔ MME)

#### 1.1 NAS Security Context確立
```
Sequence:
1. Authentication Request/Response → Kasme生成
2. Security Mode Command (NAS) → NAS Key導出
   - Kasme → KNASenc, KNASint
3. Security Mode Complete (NAS) → NAS層integrity開始

NAS Integrity Algorithm: EIA1/EIA2/EIA3
Input:
  - Key: KNASint (256-bit)
  - COUNT: DL-NAS-COUNT (32-bit, 各方向で独立)
  - Bearer: 0 (NAS always uses bearer 0)
  - Direction: 0=UL, 1=DL
  - Message: NAS PDU本体

Output:
  - MAC-I (32-bit) = NIA(KNASint, COUNT, Bearer, Dir, Message)
```

#### 1.2 現在のs1n2実装状況
```c
// s1n2_converter.c: Attach Accept integrity protection
[DEBUG] EIA2 MAC Input (count=0x00000003, bearer=0, dir=1, msg_len=96):
[DEBUG]   Header: 00 00 00 03 04 00 00 00
                   ^^^^^^^^^ ^^
                   COUNT=3   Bearer=0,Dir=1(DL)
[DEBUG]   Message (full 96 bytes): 03 07 42 02 29 06 40 00 F1 10...
                                     ^^ ^^ ^^^^^^^^^^^^^^^^^^^^^^
                                     SEQ=3, Attach Accept本体

[INFO] Wrapped Attach Accept with NAS cipher+integrity 
       (EEA=0,EIA=2, COUNT-DL=0x00000003, SEQ=3)
[DEBUG] MAC=34 DC 24 BF  ← 計算されたMAC-I
```

**PCAP確認**:
```
Frame 756 (ICS Request内のAttach Accept):
nAS-PDU: 279ec646af01074202...
         ^^ ^^^^^^^^ ^^ ^^^^
         27=Sec Hdr  01=SEQ  07 42 02=Attach Accept
         9ec646af = MAC-I

問題: s1n2計算MAC=34DC24BF ≠ PCAP内MAC=9EC646AF
```

---

### 2. RRC層のIntegrity Protection (UE ↔ eNB)

#### 2.1 RRC Security Context確立
```
Sequence (ICS内):
1. S1AP InitialContextSetupRequest受信
2. eNBがRRC SecurityModeCommandを送信
   - Input: SecurityKey IE (KeNB, 256-bit)
   - KeNB → KRRCint, KRRCenc, KUPenc 導出
3. UE検証:
   a) KeNBからKRRCintを導出 (同じアルゴリズム)
   b) RRC SecurityModeCommandのMAC-Iを検証
   c) OK → SecurityModeComplete / NG → SecurityModeFailure

RRC Integrity Algorithm: NIA1/NIA2/NIA3 (NAS keyとは独立)
Input:
  - Key: KRRCint (128-bit, KeNBから導出)
  - COUNT: RRC COUNT (UL/DL独立管理)
  - Bearer: SRB1=1, SRB2=2
  - Direction: 0=UL, 1=DL
  - Message: RRC PDU本体

Output:
  - MAC-I (32-bit) = NIA(KRRCint, COUNT, Bearer, Dir, Message)
```

#### 2.2 RRC SecurityModeCommandのMAC-I
```
ICS Request送信時:
[s1n2] Item 5: SecurityKey (KeNB)
        → eNBに送信
        → eNB: KeNB → KRRCint導出
        → eNB: RRC SecurityModeCommand生成
              MAC-I = NIA(KRRCint, COUNT=0, Bearer=1, Dir=1, RRC_SMC)

UE側:
  1. RRC SecurityModeCommand受信
  2. ICS内のAttach AcceptからKeNBを抽出（**ここが問題！**）
  3. KeNB → KRRCint導出
  4. 受信したRRC SMCのMAC-I再計算
  5. 比較: 計算MAC == 受信MAC ?
     - YES → SecurityModeComplete
     - NO  → SecurityModeFailure
```

---

### 3. KeNB導出の仕組み (重要!)

#### 3.1 正常なKeNB導出 (4G Native)
```
4G Network (Native):
  MME: Kasme + UL-NAS-COUNT → KeNB
       KeNB = KDF(Kasme, UL-NAS-COUNT)
  
  UE:  Kasme + UL-NAS-COUNT → KeNB
       (同じ入力 → 同じKeNB)
```

#### 3.2 s1n2でのKeNB導出 (現在の実装)
```c
5G→4G変換:
  AMF: Kamf + UL-NAS-COUNT → KgNB (5G)
       ICS Request送信時にKgNBを含む

  s1n2: KgNB → KeNB変換
        **現在の実装**: KgNB をそのまま KeNB として使用
        // TODO: NH chain処理が必要か?

  UE:  **UEはKasmeからKeNBを導出しようとする**
       問題: UEは4Gのkey導出を行う
             Kasme → KeNB (4G derivation)
       しかし、s1n2が送ったKeNBは5GのKgNB

  結果: UE計算KeNB ≠ s1n2送信KeNB
        → UE: KRRCint不一致
        → RRC SecurityModeCommand MAC-I検証失敗
        → SecurityModeFailure
```

---

## 問題の根本原因 (確定)

### **根本原因: KeNB導出時のCOUNT値エラー** ⭐⭐⭐

#### TS 33.401 Annex A.3の要求:
```
KeNB = KDF(Kasme, UL-NAS-COUNT, ...)

where UL-NAS-COUNT is the value of the uplink NAS COUNT that was 
used in the NAS SMC (Security Mode Command) message
```

#### 現在のs1n2実装:
```c
// s1n2_nas.c: Security Mode Command生成時
printf("[INFO] [KeNB] ✅ Cached NAS COUNT for KeNB derivation: 0x00000000\n");
//                                                              ^^^^^^^^^^
//                                                              常に0！

// s1n2_converter.c: ICS Request生成時
if (s1n2_derive_kenb_from_kasme(kasme, 0, kenb_derived) == 0) {
//                                      ^ 
//                                      COUNT=0 (固定値)
```

#### 問題:
```
[s1n2計算]
  KeNB = KDF(Kasme, UL-COUNT=0)
        = KDF(Kasme, 0x00000000)

[UE計算]
  UE側のUL-NAS-COUNTは何?
  
  可能性1: UE側もCOUNT=0を使用
    → KeNB一致するはず
    → しかし実際はRRC SecurityModeFailure発生
    → 何か他の問題がある

  可能性2: UE側がCOUNT≠0を使用
    → KeNB不一致
    → KRRCint不一致
    → MAC-I不一致
    → SecurityModeFailure ✅ 症状と一致
```

#### UEのUL-NAS-COUNT値を確認する必要:
```
Security Mode Complete (Frame 646):
- UL方向 (UE→MME)
- Sequence Number: ?
- UL-NAS-COUNT: ?

この値がs1n2のcached_nas_count=0と一致するか確認必須
```

**証拠**:
- s1n2ログ: `cached_nas_count = 0x00000000` (SMC時)
- s1n2ログ: `Derived KeNB from KASME (COUNT=0x00000000)`
- PCAP: ICS Request送信後、RRC SMCでFailure
- TS 33.401: KeNBはUL-NAS-COUNTから導出（DL-COUNTではない）

### 仮説2: NAS COUNT同期問題
```
[s1n2側 DL-NAS-COUNT]
  Security Mode Complete後: COUNT=1
  Attach Accept #1: COUNT=2
  Attach Accept #2: COUNT=3  ← s1n2ログで確認
  Attach Accept #3: COUNT=4

[UE側 DL-NAS-COUNT]
  Security Mode Complete後: COUNT=1
  Attach Accept受信: COUNT=?
  
  問題: UEが期待するCOUNT値とs1n2のCOUNT値がずれている可能性
  → Attach AcceptのMAC-I検証失敗
  → KeNB導出失敗（COUNT依存のため）
```

### 仮説3: Integrity Algorithmの不一致
```
[AMF → s1n2]
  Selected: NIA2 (5G-NIA2)

[s1n2 → eNB]
  Selected: NIA? (変換時にアルゴリズム指定してない?)

[UE]
  Capability: EIA1/EIA2/EIA3対応
  
問題: eNBがどのNIAを選択したかUEに通知されていない可能性
```

---

## 検証すべき項目

### 1. KeNB導出の確認 🔴 最優先
```bash
# s1n2のSecurityKey IE内容を確認
# PCAP Frame 756の詳細解析
tshark -r 20251114_6.pcap -Y "frame.number==756" -V | grep -A 20 "SecurityKey"

# 期待値:
# - SecurityKey IE存在
# - 32バイト(256-bit)のKeNB値
# - UE側のKasme→KeNB導出と一致する必要
```

### 2. NAS COUNT同期確認 🟡
```bash
# s1n2ログから各メッセージのCOUNT値抽出
docker logs s1n2 | grep "COUNT-DL\|COUNT-UL"

# UE側のCOUNT期待値:
# SMC: COUNT=0 (初回)
# SM Complete: COUNT=1 (UL)
# Attach Accept: COUNT=2 (DL, ICS内)
```

### 3. Integrity Algorithm確認 🟢
```bash
# ICS RequestのUESecurityCapabilities確認
tshark -r 20251114_6.pcap -Y "frame.number==756" -V | grep -A 10 "UESecurityCapabilities"

# RRC SecurityModeCommandのalgorithm確認
# (eNBログまたはL3Traceが必要)
```

---

## 次のアクション

1. **SecurityKey IEの内容確認** (KeNB値)
2. **UE側のKasme/KeNB導出ロジック調査**
3. **s1n2のKgNB→KeNB変換実装確認**
4. **必要に応じてKeNB導出修正**

---

## 参考仕様

- **TS 33.401**: 4G Security Architecture (KeNB導出)
- **TS 33.501**: 5G Security Architecture (KgNB導出)  
- **TS 36.331**: RRC Security Mode Command
- **TS 24.301**: NAS Security (COUNT管理)
