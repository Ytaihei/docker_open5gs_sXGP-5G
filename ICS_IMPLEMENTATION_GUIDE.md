# Initial Context Setup (ICS) Implementation Guide

## 概要

このドキュメントは、s1n2コンバーターにおける4G Initial Context Setup (ICS) の実装プロセスと、成功に至るまでの問題解決手順を記録します。

## 背景

### 問題の発生

4G UEが5G Coreへのアタッチを試みた際、以下のエラーが発生していました:

```
[WARN] Detected S1AP InitialContextSetupFailure (unsuccessfulOutcome)
Cause: protocol (3) - abstract-syntax-error-falsely-constructed-message (5)
```

### 根本原因の特定

ICS Failureの原因は2つありました:

1. **UESecurityCapabilities のビットマップエラー**
2. **ICS Request の IE 順序エラー**

---

## 実装の詳細

### 1. KeNB (eNodeB Key) の導出実装

#### 背景

ICS Requestには、eNBがRRC Security Modeで使用する**KeNB (256-bit)**を含める必要があります。KeNBはKASME（EPS認証マスター鍵）から導出されます。

#### 仕様 (TS 33.401 Annex A.3)

```
KeNB = HMAC-SHA-256(KASME, FC || NAS_COUNT || L0)
```

**パラメータ:**
- `FC = 0x11` (KeNB導出の機能コード)
- `NAS_COUNT` = Uplink NAS COUNT (32-bit, big-endian)
- `L0 = 0x0004` (NAS_COUNTパラメータの長さ)

#### 実装ファイル

**1. `sXGP-5G/src/auth/s1n2_auth.c`**

```c
int s1n2_kdf_kenb(const uint8_t *kasme, uint32_t ul_count, uint8_t *kenb)
{
    if (!kasme || !kenb) {
        fprintf(stderr, "[ERROR] s1n2_kdf_kenb: NULL input\n");
        return -1;
    }

    // TS 33.401 Annex A.3: KeNB derivation
    // KeNB = HMAC-SHA-256(KASME, FC || NAS_COUNT || L0)
    uint8_t input[7];

    // FC = 0x11 (KeNB derivation)
    input[0] = 0x11;

    // NAS_COUNT (4 bytes, big-endian)
    input[1] = (ul_count >> 24) & 0xFF;
    input[2] = (ul_count >> 16) & 0xFF;
    input[3] = (ul_count >> 8) & 0xFF;
    input[4] = ul_count & 0xFF;

    // L0 = 0x0004 (2 bytes, length of NAS_COUNT parameter)
    input[5] = 0x00;
    input[6] = 0x04;

    // HMAC-SHA-256
    if (kdf_hmac_sha256(kasme, 32, input, 7, kenb, 32) != 0) {
        fprintf(stderr, "[ERROR] s1n2_kdf_kenb: HMAC-SHA-256 failed\n");
        return -1;
    }

    printf("[INFO] KeNB derived from KASME (COUNT=0x%08X)\n", ul_count);
    return 0;
}
```

**2. `sXGP-5G/include/s1n2_auth.h`**

```c
int s1n2_kdf_kenb(const uint8_t *kasme, uint32_t ul_count, uint8_t *kenb);
```

**3. `sXGP-5G/include/s1n2_converter.h`**

UE mapping構造体にKeNB関連フィールドを追加:

```c
typedef struct ue_id_mapping {
    // ... existing fields ...

    uint8_t kasme[32];           // EPS master key
    bool has_kasme;              // KASME derivation flag
    uint8_t kenb[32];            // eNB key
    bool has_kenb;               // KeNB derivation flag
    uint32_t kenb_ul_count;      // NAS COUNT used for KeNB
} ue_id_mapping_t;
```

**4. `sXGP-5G/src/nas/s1n2_nas.c`**

KASME導出 (Authentication Response受信時):

```c
// After deriving 4G NAS keys (CK, IK)
if (s1n2_kdf_kasme(ck, ik, ue_mapping->sqn_xor_ak, plmn_id, ue_mapping->kasme) == 0) {
    ue_mapping->has_kasme = true;
    printf("[SUCCESS] KASME derived and cached\n");
}
```

KeNB導出 (Security Mode Complete受信時):

```c
// After Security Mode Complete verification
if (security_map && security_map->has_kasme) {
    uint32_t ul_count = security_map->nas_ul_count;
    if (s1n2_kdf_kenb(security_map->kasme, ul_count, security_map->kenb) == 0) {
        security_map->has_kenb = true;
        security_map->kenb_ul_count = ul_count;
        printf("[SUCCESS] KeNB derived (NAS COUNT=0x%08X)\n", ul_count);
    }
}
```

**5. `sXGP-5G/src/s1n2_converter.c`**

ICS Request構築時にKeNBを使用:

```c
static int build_s1ap_initial_context_setup_request(
    // ... parameters ...
    const uint8_t *kenb  // Added parameter
)
{
    // ... SecurityKey IE construction ...

    if (kenb) {
        memcpy(sk->buf, kenb, 32);
        printf("[DEBUG] ICS Request: Using derived KeNB (first 8): ");
        for (int i = 0; i < 8; i++) printf("%02X", kenb[i]);
        printf("..\n");
    } else {
        // Fallback to dummy pattern
        printf("[WARN] ICS Request: KeNB not provided, using dummy pattern\n");
        for (int i = 0; i < 32; i++) sk->buf[i] = (uint8_t)(0x11 + (i & 0x0F));
    }
}
```

呼び出し側:

```c
build_s1ap_initial_context_setup_request(
    // ... parameters ...
    (ue_map && ue_map->has_kenb) ? ue_map->kenb : NULL
);
```

---

### 2. UESecurityCapabilities の修正

#### 問題

ICS RequestのUESecurityCapabilitiesフィールドで、ビットマップが逆順になっていました。

**誤った実装:**
```c
caps->encryptionAlgorithms.buf[0] = 0x05;  // 0000 0101b
caps->integrityProtectionAlgorithms.buf[0] = 0x06;  // 0000 0110b
```

**pcap解析結果 (失敗時):**
```
encryptionAlgorithms: 0500 [bit length 16, 0000 0101 0000 0000]
  128-EEA1: Not supported
  128-EEA2: Not supported
  128-EEA3: Not supported
  Reserved: 0x0500  ← 不正！
```

**eNBエラー:**
```
Cause: protocol (3) - abstract-syntax-error-falsely-constructed-message (5)
```

#### 解決策

S1AP BIT STRINGは**MSB first**（最上位ビットが先）なので、bit 15, 14, 13をセットする必要がありました。

**正しい実装:**

**ファイル:** `sXGP-5G/src/s1n2_converter.c`

```c
// Encryption algorithms: enable EEA1, EEA2, EEA3 (MSB first: bit 15, 14, 13)
caps->encryptionAlgorithms.buf = calloc(1, 2);
if (!caps->encryptionAlgorithms.buf) goto fail;
caps->encryptionAlgorithms.size = 2;
caps->encryptionAlgorithms.bits_unused = 0;
caps->encryptionAlgorithms.buf[0] = 0xE0;  // 1110 0000b -> EEA1, EEA2, EEA3
caps->encryptionAlgorithms.buf[1] = 0x00;

// Integrity algorithms: enable EIA1, EIA2, EIA3 (MSB first: bit 15, 14, 13)
caps->integrityProtectionAlgorithms.buf = calloc(1, 2);
if (!caps->integrityProtectionAlgorithms.buf) goto fail;
caps->integrityProtectionAlgorithms.size = 2;
caps->integrityProtectionAlgorithms.bits_unused = 0;
caps->integrityProtectionAlgorithms.buf[0] = 0xE0;  // 1110 0000b -> EIA1, EIA2, EIA3
caps->integrityProtectionAlgorithms.buf[1] = 0x00;
```

**pcap解析結果 (成功時):**
```
encryptionAlgorithms: e000 [bit length 16, 1110 0000 0000 0000]
  1... .... .... .... = 128-EEA1: Supported
  .1.. .... .... .... = 128-EEA2: Supported
  ..1. .... .... .... = 128-EEA3: Supported
  ...0 0000 0000 0000 = Reserved: 0x0000  ← 正しい！
```

---

### 3. ICS Request の IE 順序修正

#### 問題

eNBが特定のIE順序を期待していましたが、s1n2の実装が異なっていました。

**4G EPC MME (正しい順序):**
```
1. MME-UE-S1AP-ID
2. eNB-UE-S1AP-ID
3. uEaggregateMaximumBitrate
4. E-RABToBeSetupListCtxtSUReq  ← セキュリティIEの前
5. UESecurityCapabilities
6. SecurityKey
```

**s1n2 (誤った順序):**
```
1. MME-UE-S1AP-ID
2. eNB-UE-S1AP-ID
3. uEaggregateMaximumBitrate
4. UESecurityCapabilities          ← 順序が違う
5. SecurityKey                      ← 順序が違う
6. E-RABToBeSetupListCtxtSUReq      ← 順序が違う
```

#### 解決策

**ファイル:** `sXGP-5G/src/s1n2_converter.c`

IEの追加順序を変更しました:

```c
static int build_s1ap_initial_context_setup_request(/* ... */)
{
    // ... PDU initialization ...

    // 1. MME-UE-S1AP-ID
    // 2. eNB-UE-S1AP-ID
    // 3. uEaggregateMaximumBitrate

    // 4. E-RABToBeSetupListCtxtSUReq (BEFORE security IEs)
    // NOTE: Must come BEFORE UESecurityCapabilities per TS 36.413
    ie = calloc(1, sizeof(*ie));
    // ... E-RAB setup ...
    ASN_SEQUENCE_ADD(&req->protocolIEs.list, ie);

    // 5. UESecurityCapabilities (AFTER E-RAB list)
    ie = calloc(1, sizeof(*ie));
    // ... UE security capabilities ...
    ASN_SEQUENCE_ADD(&req->protocolIEs.list, ie);

    // 6. SecurityKey (AFTER E-RAB list)
    ie = calloc(1, sizeof(*ie));
    // ... SecurityKey with KeNB ...
    ASN_SEQUENCE_ADD(&req->protocolIEs.list, ie);

    // ... encoding ...
}
```

---

## 検証結果

### テスト環境

- **日付:** 2025年11月15日
- **pcapファイル:** `/home/taihei/docker_open5gs_sXGP-5G/log/20251115_4.pcap`
- **UE:** 実機4G端末
- **eNB:** Baicells実機eNodeB
- **Core:** Open5GS 5G Core

### 成功ログ

**Docker log (s1n2):**
```
[DEBUG] ICS Request: Using derived KeNB (first 8): 096A3E8EE34A2845..
[INFO] ICS Request built with derived KeNB (COUNT=0x00000000)
[SUCCESS] Bridged 5G Registration Accept -> S1AP InitialContextSetupRequest
[DEBUG] Detected S1AP InitialContextSetupResponse (successfulOutcome)
[INFO] [ICS] Marked ICS completed (ENB=1, MME=1, attempts=1)
[INFO] Added bidirectional TEID mapping: S1-U 0x01000008 ↔ N3 0x01000008
```

**pcap解析:**
```bash
$ tshark -r 20251115_4.pcap -Y "s1ap.InitialContextSetupResponse_element"
Frame 8090: InitialContextSetupResponse
  - MME-UE-S1AP-ID: 1
  - eNB-UE-S1AP-ID: 1
  - E-RABSetupListCtxtSURes: 1 item
    - E-RAB-ID: 5
    - transportLayerAddress: 172.24.0.111
    - gTP-TEID: 0x01000008
```

### 修正前後の比較

| 項目 | 修正前 | 修正後 |
|------|--------|--------|
| KeNB | ダミーパターン (0x11, 0x12, ...) | KASMEから正しく導出 |
| encryptionAlgorithms | `0x05` (不正) | `0xE0` (EEA1/2/3サポート) |
| integrityProtectionAlgorithms | `0x06` (不正) | `0xE0` (EIA1/2/3サポート) |
| IE順序 | Security IEs → E-RAB | E-RAB → Security IEs |
| ICS結果 | **Failure** (Cause: 0x35) | **Success** |

---

## 参考仕様

### 3GPP仕様書

1. **TS 33.401** - 3GPP System Architecture Evolution (SAE); Security architecture
   - Annex A.3: KeNB derivation
   - Annex A.7: KASME derivation

2. **TS 36.413** - Evolved Universal Terrestrial Radio Access Network (E-UTRAN); S1 Application Protocol (S1AP)
   - Section 8.3.1: Initial Context Setup procedure
   - Section 9.1.4.1: INITIAL CONTEXT SETUP REQUEST

3. **TS 24.301** - Non-Access-Stratum (NAS) protocol for Evolved Packet System (EPS)
   - Section 5.4.3: NAS security mode control procedure
   - Section 8.2.7: Attach accept

### Open5GS参考実装

**KeNB導出:** `sources/open5gs/src/mme/emm-sm.c`
```c
// Line 1232-1234
case EMM_REGISTERED:
    // ... after Security Mode Complete ...
    ogs_kdf_kenb(mme_ue->kasme, mme_ue->ul_count.i32, mme_ue->kenb);
```

**KDF実装:** `sources/open5gs/lib/crypt/ogs-kdf.c`
```c
// Line 342-352
void ogs_kdf_kenb(uint8_t *kasme, uint32_t ul_nas_count, uint8_t *kenb)
{
    uint8_t s[7];
    s[0] = FC_KENB;  // 0x11
    s[1] = (ul_nas_count >> 24) & 0xFF;
    s[2] = (ul_nas_count >> 16) & 0xFF;
    s[3] = (ul_nas_count >> 8) & 0xFF;
    s[4] = ul_nas_count & 0xFF;
    s[5] = 0x00;
    s[6] = 0x04;
    ogs_hmac_sha256(kasme, 32, s, 7, kenb, 32);
}
```

---

## トラブルシューティング

### 問題: ICS Failure (Cause: protocol - abstract-syntax-error)

**原因:**
- UESecurityCapabilitiesのビットマップが不正
- IEの順序が仕様と異なる

**解決策:**
- UESecurityCapabilitiesを`0xE0/0xE0`に修正
- IE順序をE-RAB → Security IEsに変更

### 問題: MAC-I mismatch (RRC Security Mode失敗)

**原因:**
- KeNBが導出されていない、またはダミー値使用

**解決策:**
- KASMEからKeNBを正しく導出
- NAS COUNTを正しく使用（Security Mode Complete時点のUL COUNT）

### 問題: KeNB derivation error

**原因:**
- KASMEが導出されていない
- NAS COUNTが不正

**解決策:**
- Authentication Response後にKASMEを導出
- Security Mode Complete後、正しいUL COUNTでKeNBを導出

---

## まとめ

s1n2コンバーターでICSを成功させるために実施した主要な実装:

1. **KeNB導出の実装**
   - TS 33.401 Annex A.3に準拠したKDF実装
   - KASME → KeNB の鍵階層の実装
   - NAS COUNT管理

2. **UESecurityCapabilitiesの修正**
   - ビットマップをMSB firstに修正
   - 0xE0/0xE0でEEA1/2/3、EIA1/2/3をサポート

3. **ICS Request IE順序の修正**
   - 4G EPC MMEと同じ順序に変更
   - E-RABToBeSetupListCtxtSUReqをセキュリティIEの前に配置

これらの実装により、4G UEが5G Coreに正常にアタッチできるようになりました。

---

**作成日:** 2025年11月15日
**バージョン:** 1.0
**ステータス:** ICS Success確認済み
