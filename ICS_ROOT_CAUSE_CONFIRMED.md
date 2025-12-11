# ICS失敗の根本原因 - 確定事項 (2025年11月14日)

## 確定した因果関係

**Initial Context Setup (ICS) Failure の直接原因は RRC Security Mode の失敗である**

---

## 証拠1: pcap分析

**ファイル**: `log/20251114_17.pcap`

```
Frame 4238 @ 62.981s : Initial Context Setup Request (s1n2 → eNB)
                       ↓
                    [eNB内部処理]
                    RRC Security Mode Command送信（エアIF、pcap外）
                       ↓
                    MAC-I mismatch検出
                       ↓
Frame 4245 @ 63.225s : Initial Context Setup Failure (eNB → s1n2)
                       Cause = radioNetwork(0).failure-in-radio-interface-procedure(26)
```

**時間差**: 244ms

---

## 証拠2: eNBログ

**ファイル**: `traial_eNB_log/syslog/syslog`

```
Nov 14 19:51:59 err : [STK_MD_MAC] MAC-I does not match!!!!
                      Recv_MACI:0x0 Cal_MACI:0x7451c8e4
```

- eNBが計算したMAC-I: `0x7451c8e4`
- UEから受信したMAC-I: `0x0` (ゼロ)
- **結果**: MAC-I不一致によりRRC Security Mode失敗

---

## タイムライン

1. **62.981s**: s1n2がICS Requestを送信
2. **[内部]**: eNBがICS Requestを受理し処理開始
3. **[内部]**: eNBがRRC Security Mode CommandをUEに送信
4. **19:51:59**: eNBがUEからの応答でMAC-I mismatch検出
5. **63.225s**: eNBがICS Failureを返信（Cause=26）

---

## ICS失敗の構造

```
ICS Request (正常)
  ↓
RRC Security Mode (失敗) ← ★ 根本原因
  ↓
ICS Failure (結果)
```

---

## 確定した事実

### ✅ ICS Requestメッセージは正常
- eNBは正常に受理して処理を開始
- メッセージフォーマットに問題なし

### ✅ RRC Security ModeでMAC-I検証が失敗
- UEがMAC-I=0x0を送信（計算失敗または未実装）
- eNBの期待値=0x7451c8e4と不一致

### ✅ RRC手順失敗がICS失敗の直接原因
- eNBが"failure-in-radio-interface-procedure"を返す
- これはRRC層での問題を示す標準的なCause値

---

## 次の調査対象

### RRC Security Mode失敗の原因

**なぜUEはMAC-I=0x0を送信するのか？**

### 可能性のある原因

1. **UEがKeNBを正しく導出できていない**
2. **UEがK_RRCintを正しく導出できていない**
3. **UEがMAC-I計算に失敗している**
4. **s1n2とUEでKeNB導出の入力パラメータが異なる**

### 検証が必要なパラメータ

- KASME: ✅ 正常（NAS Security Mode Complete成功から確認済み）
- **KeNB = KDF(KASME, NAS_COUNT)** ← 要検証
- **K_RRCint = KDF(KeNB, Algorithm)** ← 要検証

---

**作成日**: 2025年11月14日
**確認方法**: pcap + eNBログの照合
**状態**: 根本原因（RRC Security Mode失敗）確定
**次のステップ**: KeNB導出パラメータ（特にNAS_COUNT）の検証

---

## 追加検証1: ICSメッセージの妥当性（4G EPC成功例との比較）

### 比較対象
- **成功例**: `sample_pcap/4G_EPC_success.pcap` (4G UE + eNB + 4G EPC/MME)
- **失敗例**: `log/20251114_17.pcap` (4G UE + eNB + s1n2 + 5G Core)

### ICS Request構造の比較

#### IE構成
| Item | 成功例(MME) | 失敗例(s1n2) |
|------|-------------|--------------|
| 0 | id-MME-UE-S1AP-ID | id-MME-UE-S1AP-ID |
| 1 | id-eNB-UE-S1AP-ID | id-eNB-UE-S1AP-ID |
| 2 | id-uEaggregateMaximumBitrate | id-uEaggregateMaximumBitrate |
| 3 | id-E-RABToBeSetupListCtxtSUReq | id-E-RABToBeSetupListCtxtSUReq |
| 4 | id-UESecurityCapabilities | id-UESecurityCapabilities |
| 5 | id-SecurityKey | id-SecurityKey |
| 6 | id-Masked-IMEISV | id-Masked-IMEISV |

**結果**: ✅ **完全に一致（7 IEs、同じ順序）**

#### UESecurityCapabilities
| パラメータ | 成功例 | 失敗例 |
|-----------|--------|--------|
| encryptionAlgorithms | 0xE000 (EEA1/2/3) | 0xE000 (EEA1/2/3) |
| integrityProtectionAlgorithms | 0xE000 (EIA1/2/3) | 0xE000 (EIA1/2/3) |

**結果**: ✅ **完全に一致**

### タイムライン比較

#### 成功例（4G EPC）
```
33.360s: ICS Request
33.629s: ICS Response (+269ms) ← 成功
```

#### 失敗例（s1n2）
```
62.825s: NAS Security Mode Complete ← KASME鍵は正常
62.981s: ICS Request (+156ms)
63.225s: ICS Failure (+244ms) ← RRC Security Mode失敗
```

### 確定した事実

#### ✅ ICS Requestメッセージは仕様準拠
- MMEが送信するICSと構造が完全に一致
- UESecurityCapabilitiesも同一
- **s1n2のICS実装は正しい**

#### ✅ KASME由来の鍵は正常動作
- NAS Security Mode Completeが成功
- K_NASenc/K_NASintは正常に動作

#### ❌ KeNB由来の鍵で失敗
- RRC Security Mode でMAC-I不一致
- K_RRCintの導出または使用に問題

### 結論

**「MMEと同様のロジックでICSを送信すれば成功する」という仮説は部分的に正しい**

- ✅ ICSメッセージ自体は既にMMEと同じ
- ✅ eNBはICSを正常に受理
- ❌ **問題はICS送信後のRRC Security Mode処理にある**

**根本原因の絞り込み**:
1. **s1n2のKeNB導出が正しくない可能性**
   - NAS_COUNTが異なる？
   - 他の入力パラメータが異なる？

2. **UEがs1n2環境でKeNBを正しく導出できない可能性**
   - 4G native認証パスの実装問題？
   - KeNB導出ロジックのバグ？

**次の検証**: s1n2とMMEのKeNB導出パラメータ（特にNAS_COUNT）の比較

---

## 追加検証2: RRC Security Mode成功に必要なS1AP要件

### 質問
**RRC Security ModeでMAC-I検証を成功させるには、S1APレイヤーで何が正しい必要があるか？**

### RRC Security Modeの処理フロー

#### eNB側の処理
```
1. ICS Request受信
   └─ SecurityKey IE（KeNB）を取得
2. KeNB → K_RRCint/K_RRCenc 導出
   └─ UESecurityCapabilitiesからアルゴリズム選択
3. RRC Security Mode Command送信（エアIF）
4. UEからのRRC Security Mode Completeを受信
5. MAC-I検証
   └─ 計算: MAC-I = AES-CMAC(K_RRCint, RRC_message)
   └─ 比較: 計算値 vs 受信値
```

#### UE側の処理
```
1. [既にKASMEを保持] ← NAS Security Mode Commandで導出済み
2. NAS_COUNTを使用してKeNB導出
   └─ KeNB = KDF(KASME, NAS_COUNT, 0x11)
3. KeNB → K_RRCint/K_RRCenc 導出
4. RRC Security Mode Command受信（エアIF）
5. RRC Security Mode Complete送信
   └─ MAC-I = AES-CMAC(K_RRCint, RRC_message)
```

### MAC-I検証が成功する条件

#### 必須条件
1. **eNBとUEが同じKeNBを持つ**
   - eNB: ICSのSecurityKey IEから取得
   - UE: KASME + NAS_COUNT から導出
   - ⚠️ **s1n2とUEが同じNAS_COUNTを使用する必要がある**

2. **eNBとUEが同じK_RRCintを持つ**
   - K_RRCint = KDF(KeNB, Algorithm_ID, 0x15)
   - Algorithm_IDはUESecurityCapabilitiesから選択

3. **eNBとUEが同じアルゴリズムを使用**
   - UESecurityCapabilitiesで指定
   - eNBがサポートするアルゴリズムと交差

### S1AP ICS Requestで正しく設定すべきパラメータ

#### 1. SecurityKey IE (id-SecurityKey: 73)
**内容**: KeNB (256 bits)

**導出方法**:
```c
KeNB = KDF(KASME, NAS_COUNT, 0x11)
```

**重要**:
- ✅ KASMEは正しい（NAS Security Mode Complete成功から確認済み）
- ❓ **NAS_COUNTがUEと一致しているか？** ← **最重要検証項目**

**NAS_COUNTとは**:
- NAS Downlink COUNT: MME/s1n2がNASメッセージ送信時にインクリメント
- UEはこのCOUNTを追跡
- KeNB導出時点のCOUNT値を使用

#### 2. UESecurityCapabilities IE (id-UESecurityCapabilities: 107)
**内容**:
- encryptionAlgorithms (16 bits): EEA0/1/2/3のサポート状況
- integrityProtectionAlgorithms (16 bits): EIA0/1/2/3のサポート状況

**重要**:
- ✅ 既に正しく設定されている（MMEと同一）
- eNBはこれを元にアルゴリズムを選択

### 現在の状況分析

#### ✅ 正しく設定されているもの
1. **ICS構造**: 7 IEs、MMEと同一
2. **UESecurityCapabilities**: EEA1/2/3, EIA1/2/3（MMEと同一）
3. **KASME**: 正常（NAS Security Mode Complete成功）

#### ❓ 検証が必要なもの
1. **NAS_COUNT値**
   - s1n2がKeNB導出時に使用したCOUNT
   - UEが想定しているCOUNT
   - **この不一致がMAC-I=0x0の原因である可能性が最も高い**

#### ❓ その他の可能性
1. **アルゴリズム選択**
   - eNBが選択したEIA (EIA1/2/3)
   - UEが期待するEIA

2. **KeNB導出タイミング**
   - s1n2: いつKeNBを導出したか？
   - UE: いつKeNBを導出するか？（ICS受信時？RRC Security Mode Command受信時？）

### 結論: S1APレイヤーで正しく設定すべきもの

#### 最重要
**SecurityKey IEのKeNB値が、UEが導出するKeNBと一致すること**

具体的には:
```
s1n2のKeNB = KDF(KASME, NAS_COUNT_s1n2, 0x11)
UEのKeNB   = KDF(KASME, NAS_COUNT_ue, 0x11)

→ NAS_COUNT_s1n2 == NAS_COUNT_ue である必要がある
```

#### 重要
**UESecurityCapabilitiesが正しいこと**（✅ 既に確認済み）

### 次の検証ステップ

1. **s1n2のNAS_COUNT確認**
   - KeNB導出時に使用したCOUNT値をログ出力
   - NAS Security Mode Command送信後のCOUNT値

2. **UEのNAS_COUNT推定**
   - UEが受信したNASメッセージ数をpcapから確認
   - UEが想定するCOUNT値を推定

3. **COUNT不一致の修正**
   - s1n2がKeNB導出に使用するCOUNT値を修正
   - または、KeNB導出タイミングを調整

---

## 追加検証3: MME vs s1n2のKeNB導出実装比較

### MMEのKeNB導出実装

**ファイル**: `sources/open5gs/src/mme/emm-sm.c`

#### KeNB導出タイミング
**Line 1232-1234** (NAS Security Mode Complete受信後):
```c
ogs_kdf_kenb(mme_ue->kasme, mme_ue->ul_count.i32,
        mme_ue->kenb);
ogs_kdf_nh_enb(mme_ue->kasme, mme_ue->kenb, mme_ue->nh);
mme_ue->nhcc = 1;
```

**Line 651-653** (TAU - Tracking Area Update時):
```c
ogs_kdf_kenb(mme_ue->kasme, mme_ue->ul_count.i32,
        mme_ue->kenb);
ogs_kdf_nh_enb(mme_ue->kasme, mme_ue->kenb, mme_ue->nh);
```

#### KeNB導出関数の実装

**ファイル**: `sources/open5gs/lib/crypt/ogs-kdf.c`

**Line 342-352**:
```c
void ogs_kdf_kenb(const uint8_t *kasme, uint32_t ul_count, uint8_t *kenb)
{
    kdf_param_t param;

    memset(param, 0, sizeof(param));
    ul_count = htobe32(ul_count);  // ホストバイトオーダー → ビッグエンディアン
    param[0].buf = (uint8_t *)&ul_count;
    param[0].len = 4;

    ogs_kdf_common(kasme, OGS_SHA256_DIGEST_SIZE,
            FC_FOR_KENB_DERIVATION, param, kenb);
}
```

**FC値**: `#define FC_FOR_KENB_DERIVATION 0x11` (Line 34)

#### ICS Request送信時のKeNB使用

**ファイル**: `sources/open5gs/src/mme/s1ap-build.c`

**Line 690**:
```c
memcpy(SecurityKey->buf, mme_ue->kenb, SecurityKey->size);
```

### s1n2のKeNB導出実装

**ファイル**: `sXGP-5G/src/s1n2_converter.c`

#### 現在の実装（Line 222）
```c
// ダミー値を設定
for (int i = 0; i < 32; i++) sk->buf[i] = (uint8_t)(0x11 + (i & 0x0F));
```

#### 問題点
1. **KeNB導出処理が存在しない** ← ★ 根本原因
2. **ダミー値（0x11, 0x12, ...）を使用**
3. **KASMEもNAS_COUNTも使用していない**

### 比較まとめ

| 項目 | MME | s1n2 | 一致? |
|------|-----|------|-------|
| KeNB導出関数 | ✅ `ogs_kdf_kenb()` | ❌ **未実装** | ✗ |
| KASME使用 | ✅ `mme_ue->kasme` | ❌ **使用していない** | ✗ |
| NAS_COUNT使用 | ✅ `mme_ue->ul_count.i32` | ❌ **使用していない** | ✗ |
| FC値 | ✅ 0x11 | ❌ **ダミー値0x11で開始** | ✗ |
| 導出タイミング | ✅ Security Mode Complete後 | ❌ **導出していない** | ✗ |
| KeNB保存 | ✅ `mme_ue->kenb` | ❌ **保存していない** | ✗ |
| ICS送信時 | ✅ `memcpy(SecurityKey->buf, mme_ue->kenb, ...)` | ❌ **ダミー値をコピー** | ✗ |

### 確定した根本原因

**s1n2はKeNBを全く導出していない**

- ダミーパターン（0x11, 0x12, 0x13, ...）をSecurityKey IEに設定
- UEは正しいKeNBを導出（KASME + NAS_COUNTから）
- eNBはダミーKeNBからK_RRCintを導出
- UEは正しいKeNBからK_RRCintを導出
- **K_RRCintが一致しないため、MAC-I検証失敗**

### 必要な修正

1. **KASMEとKeNBをue_id_mapping_tに追加**
   ```c
   typedef struct {
       // 既存フィールド...
       uint8_t kasme[32];          // KASME - 4G master key
       bool has_kasme;             // KASME導出済みフラグ
       uint8_t kenb[32];           // KeNB - eNB key
       bool has_kenb;              // KeNB導出済みフラグ
   } ue_id_mapping_t;
   ```

2. **KeNB導出関数の実装**
   - `ogs_kdf_kenb()`を利用
   - またはs1n2独自実装

3. **KeNB導出タイミング**
   - NAS Security Mode Complete受信後
   - ICS Request送信前

4. **ICS Request作成時に正しいKeNBを使用**
   ```c
   // Line 222を修正
   memcpy(sk->buf, ue_mapping->kenb, 32);
   ```

### 次のステップ

1. **ue_id_mapping_t構造体にkasmeとkenbフィールドを追加**
2. **NAS Security Mode Complete処理時にKASME/KeNBを保存**
3. **ICS Request作成時に保存したKeNBを使用**
4. **ビルド・テスト・検証**

