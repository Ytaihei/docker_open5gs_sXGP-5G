# s1n2コンバータにおける鍵変換戦略

## 前提条件

### コンバータが持つ情報
- **IMSI**: UEの識別子
- **K (Ki)**: USIM内の恒久鍵 (128 bits) - `auth_keys.yaml`から取得
- **OPc**: オペレータバリアント鍵 (128 bits) - `auth_keys.yaml`から取得

### コンバータが受信する情報
- **5G側 (AMFから)**:
  - RAND (128 bits) - 5G Authentication Requestに含まれる
  - AUTN - Authentication Token
  - ABBA (2 bytes, 通常 0x0000)
  - Kamf (AMFが保持、s1n2には送信されない)
  - KgNB (Initial Context Setup Requestに含まれる)

- **4G側 (UEから)**:
  - RES (4G Authentication Response)
  - Security Mode Complete MAC

---

## 鍵変換の3つのアプローチ

### アプローチ1: 完全4G Native再現 ✅ **推奨** (現在の実装)

```
┌─────────────────────────────────────────────────────────────┐
│ s1n2コンバータの動作                                          │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│ 1. Authentication Request処理 (5G→4G変換時)                  │
│    ┌──────────────────────────────────────────┐             │
│    │ 入力: 5G Authentication Request          │             │
│    │   - RAND, AUTN, ABBA                     │             │
│    │ キャッシュ:                               │             │
│    │   - RAND (16 bytes)                      │             │
│    │   - SQN⊕AK (6 bytes, from AUTN)         │             │
│    │   - ABBA (2 bytes) ※後で無視            │             │
│    └──────────────────────────────────────────┘             │
│                                                               │
│ 2. Authentication Response処理 (4G→5G変換時)                 │
│    ┌──────────────────────────────────────────┐             │
│    │ 入力: 4G Authentication Response         │             │
│    │   - RES (8 bytes)                        │             │
│    │                                           │             │
│    │ ★★★ 4G Native鍵導出 (UEと同じ) ★★★    │             │
│    │                                           │             │
│    │ Step 1: Milenage                         │             │
│    │   Input: K, OPc, RAND                    │             │
│    │   Output: CK, IK (各16 bytes)            │             │
│    │                                           │             │
│    │ Step 2: KASME導出 (FC=0x10)              │             │
│    │   Key: CK || IK (32 bytes)               │             │
│    │   S = 0x10 || SNN || len(SNN) ||        │             │
│    │       SQN⊕AK || 0x0006                   │             │
│    │   KASME = HMAC-SHA-256(CK||IK, S)        │             │
│    │                                           │             │
│    │ Step 3: K_NASenc, K_NASint導出           │             │
│    │   K_NASint = KDF(KASME, 0x02, EIA2)      │             │
│    │   K_NASenc = KDF(KASME, 0x01, EEA2)      │             │
│    │                                           │             │
│    │ ★★★ 重要: KASME をキャッシュ ★★★       │             │
│    │   ue_mapping->kasme = KASME              │             │
│    │   ue_mapping->has_kasme = true           │             │
│    └──────────────────────────────────────────┘             │
│                                                               │
│ 3. Security Mode Command変換 (5G→4G)                         │
│    ┌──────────────────────────────────────────┐             │
│    │ 使用鍵: キャッシュされた K_NASint        │             │
│    │ MAC計算: UEと同じ K_NASint で計算        │             │
│    │ → UEが検証可能                           │             │
│    └──────────────────────────────────────────┘             │
│                                                               │
│ 4. Initial Context Setup変換 (5G→4G)                         │
│    ┌──────────────────────────────────────────┐             │
│    │ ★★★ AMFのKgNBは使用しない ★★★          │             │
│    │                                           │             │
│    │ Step 1: NAS COUNT取得                    │             │
│    │   count = ue_mapping->nas_count_for_kenb │             │
│    │   (Security Mode Command送信時の値)      │             │
│    │                                           │             │
│    │ Step 2: KeNB導出 (FC=0x11)               │             │
│    │   Key: ue_mapping->kasme                 │             │
│    │   S = 0x11 || COUNT (4 bytes) || 0x0004 │             │
│    │   KeNB = HMAC-SHA-256(KASME, S)          │             │
│    │                                           │             │
│    │ Step 3: S1AP ICS送信                     │             │
│    │   SecurityKey = KeNB (導出した値)        │             │
│    │   E-RAB情報, NAS-PDU等                   │             │
│    └──────────────────────────────────────────┘             │
│                                                               │
└─────────────────────────────────────────────────────────────┘

【結果】
✅ UE: CK||IK --[FC=0x10]--> KASME --[FC=0x11]--> KeNB
✅ s1n2: CK||IK --[FC=0x10]--> KASME --[FC=0x11]--> KeNB
✅ KASME一致 → KeNB一致 → RRCセキュリティ成功
```

**利点**:
- UEと完全に同じ鍵階層
- ABBAの有無に関係なく動作
- 4G UEの実際の動作と完全一致

**実装上の注意**:
```c
// auth_keys.yamlからK, OPcを取得
const subscriber_t *sub = find_subscriber_by_imsi(imsi);
if (!sub) {
    printf("[ERROR] Subscriber not found: %s\n", imsi);
    return -1;
}

// Milenage
uint8_t ck[16], ik[16];
s1n2_milenage_f2345(sub->opc, sub->ki, rand, NULL, ck, ik, NULL);

// KASME導出 (FC=0x10) - 4G native
uint8_t kasme[32];
s1n2_kdf_kasme(ck, ik, sqn_xor_ak, plmn_id, kasme);

// ★重要: KASME をキャッシュ (memsetで消去しない!)
memcpy(ue_mapping->kasme, kasme, 32);
ue_mapping->has_kasme = true;
```

---

### アプローチ2: 5G-AKA変換 (Kamf → KASME) ❌ **非推奨** (4G UEでは不可)

```
┌─────────────────────────────────────────────────────────────┐
│ s1n2の動作 (理論上の5G→4G Interworking)                      │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│ 1. Authentication Response処理                                │
│    ┌──────────────────────────────────────────┐             │
│    │ Step 1: 5G鍵階層を完全再現                │             │
│    │   Milenage: K + OPc + RAND → CK, IK      │             │
│    │   KDF(FC=0x6A): CK||IK + SNN + SQN⊕AK    │             │
│    │                 → Kausf                   │             │
│    │   KDF(FC=0x6C): Kausf + SNN → Kseaf      │             │
│    │   KDF(FC=0x6D): Kseaf + SUPI + ABBA      │             │
│    │                 → Kamf                    │             │
│    │                                           │             │
│    │ Step 2: Kamf→KASME変換 (FC=0x71)         │             │
│    │   S = 0x71 || COUNT || 0x0004            │             │
│    │   KASME = HMAC-SHA-256(Kamf, S)          │             │
│    │                                           │             │
│    │ Step 3: K_NAS導出                        │             │
│    │   K_NASint = KDF(KASME, 0x02, EIA2)      │             │
│    │   K_NASenc = KDF(KASME, 0x01, EEA2)      │             │
│    └──────────────────────────────────────────┘             │
│                                                               │
│ 2. Initial Context Setup変換                                 │
│    ┌──────────────────────────────────────────┐             │
│    │ Step 1: KeNB導出 (FC=0x11)               │             │
│    │   KeNB = HMAC-SHA-256(KASME, 0x11||COUNT)│             │
│    └──────────────────────────────────────────┘             │
│                                                               │
└─────────────────────────────────────────────────────────────┘

【問題】
❌ UE: CK||IK --[FC=0x10]--> KASME_UE
❌ s1n2: CK||IK --[FC=0x6A→0x6C→0x6D]--> Kamf --[FC=0x71]--> KASME_s1n2
❌ KASME_UE ≠ KASME_s1n2 → KeNB不一致 → Security Mode Reject
```

**この方法が失敗する理由**:
1. **4G UEはABBAを理解しない**
2. **4G UEは常にFC=0x10でKASMEを導出**
3. **s1n2がFC=0x71を使っても、UEと鍵が一致しない**

**適用可能なケース**:
- 5G対応UE (NR/LTE dual mode)
- UEが5G-AKA手順を理解する場合
- UEがABBAを正しく処理する場合

---

### アプローチ3: KgNBを直接KeNBとして使用 ❌ **完全に誤り**

```
┌─────────────────────────────────────────────────────────────┐
│ 誤った実装例                                                  │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│ Initial Context Setup変換:                                    │
│   - AMFから KgNB を受信                                       │
│   - KgNB をそのまま KeNB として S1AP ICSに設定                │
│                                                               │
└─────────────────────────────────────────────────────────────┘

【問題】
❌ AMF: Kamf --[FC=0x70]--> KgNB (5G基地局用)
❌ UE:  KASME --[FC=0x11]--> KeNB (4G基地局用)
❌ KgNB ≠ KeNB (導出方法が完全に異なる)
❌ 結果: RRC Security Mode Command失敗
```

---

## 正しい実装フロー (アプローチ1の詳細)

### Phase 1: 初期化
```c
// auth_keys.yaml読み込み
typedef struct {
    char imsi[16];
    uint8_t ki[16];
    uint8_t opc[16];
} subscriber_t;

subscriber_t subscribers[] = {
    {
        .imsi = "001011234567895",
        .ki = {0x8b, 0xaf, 0x47, 0x3f, ...},
        .opc = {0x8e, 0x27, 0xb6, 0xaf, ...}
    }
};
```

### Phase 2: Authentication Request (5G→4G変換)
```c
// NGAP Authentication Request受信
void handle_authentication_request_5g_to_4g(
    const uint8_t *rand,        // 16 bytes from AMF
    const uint8_t *autn,        // 16 bytes from AMF
    const uint8_t *abba,        // 2 bytes from AMF
    ue_mapping_t *ue_mapping)
{
    // 1. RANDをキャッシュ
    memcpy(ue_mapping->rand, rand, 16);

    // 2. AUTNからSQN⊕AKを抽出 (最初の6バイト)
    memcpy(ue_mapping->sqn_xor_ak, autn, 6);

    // 3. ABBAをキャッシュ (4G UE用には使用しない)
    if (abba) {
        memcpy(ue_mapping->abba, abba, 2);
        ue_mapping->abba_len = 2;
        printf("[INFO] ABBA cached: %02X %02X\n", abba[0], abba[1]);
        printf("[INFO] 4G UE will IGNORE this and use 4G native key derivation\n");
    }

    // 4. S1AP Authentication Requestに変換して送信
    //    (RAND, AUTN含む、ABBAは含めない)
}
```

### Phase 3: Authentication Response (4G→5G変換)
```c
// S1AP Authentication Response受信
void handle_authentication_response_4g_to_5g(
    const uint8_t *res,         // 8 bytes from UE
    const char *imsi,
    ue_mapping_t *ue_mapping)
{
    // 1. auth_keys.yamlから鍵取得
    const subscriber_t *sub = find_subscriber_by_imsi(imsi);
    if (!sub) {
        printf("[ERROR] Subscriber not found\n");
        return;
    }

    // 2. Milenage: CK, IK導出
    uint8_t ck[16], ik[16];
    s1n2_milenage_f2345(sub->opc, sub->ki,
                        ue_mapping->rand,
                        NULL, ck, ik, NULL);

    printf("[DEBUG] CK: ");
    for (int i = 0; i < 16; i++) printf("%02X", ck[i]);
    printf("\n");

    printf("[DEBUG] IK: ");
    for (int i = 0; i < 16; i++) printf("%02X", ik[i]);
    printf("\n");

    // 3. KASME導出 (FC=0x10) - 4G native
    uint8_t kasme[32];
    uint8_t plmn_id[3] = {0x00, 0xf1, 0x10}; // MCC=001, MNC=01

    int ret = s1n2_kdf_kasme(ck, ik,
                             ue_mapping->sqn_xor_ak,
                             plmn_id,
                             kasme);
    if (ret != 0) {
        printf("[ERROR] KASME derivation failed\n");
        return;
    }

    printf("[DEBUG] KASME (4G native, FC=0x10): ");
    for (int i = 0; i < 32; i++) printf("%02X", kasme[i]);
    printf("\n");

    // 4. ★★★ 重要: KASME をキャッシュ ★★★
    memcpy(ue_mapping->kasme, kasme, 32);
    ue_mapping->has_kasme = true;

    // 5. K_NASenc, K_NASint導出
    uint8_t int_alg = 2; // EIA2
    uint8_t enc_alg = 2; // EEA2

    s1n2_kdf_nas_keys(kasme, 0x02, int_alg, ue_mapping->k_nas_int);
    s1n2_kdf_nas_keys(kasme, 0x01, enc_alg, ue_mapping->k_nas_enc);
    ue_mapping->has_nas_keys = true;

    printf("[DEBUG] K_NASint: ");
    for (int i = 0; i < 16; i++) printf("%02X", ue_mapping->k_nas_int[i]);
    printf("\n");

    // 6. RES→RES*変換 (5G Core向け)
    uint8_t res_star[16];
    compute_res_star(ck, ik, imsi, rand, res, res_star);

    // 7. NGAP Authentication Responseに変換して送信
    send_ngap_authentication_response(res_star);

    // CK, IKは消去 (KASME は残す!)
    memset(ck, 0, 16);
    memset(ik, 0, 16);
}
```

### Phase 4: Security Mode Command (5G→4G変換)
```c
void handle_security_mode_command_5g_to_4g(
    ue_mapping_t *ue_mapping,
    uint8_t *plain_nas_msg,
    size_t plain_len)
{
    // 1. NAS COUNTをキャッシュ (KeNB導出用)
    ue_mapping->nas_count_for_kenb = ue_mapping->nas_dl_count;
    printf("[INFO] [KeNB] Cached NAS COUNT: 0x%08X\n",
           ue_mapping->nas_count_for_kenb);

    // 2. MAC計算 (キャッシュされたK_NASintを使用)
    uint8_t mac[4];
    uint8_t seq = (uint8_t)(ue_mapping->nas_dl_count & 0xFF);

    // MAC入力: seq || plain_nas_msg
    uint8_t mac_input[256];
    mac_input[0] = seq;
    memcpy(&mac_input[1], plain_nas_msg, plain_len);

    // EIA2 MAC計算
    s1n2_eia2(ue_mapping->k_nas_int,
              ue_mapping->nas_dl_count,
              0,  // bearer
              1,  // direction (downlink)
              mac_input,
              1 + plain_len,
              mac);

    printf("[INFO] MAC computed: %02X %02X %02X %02X\n",
           mac[0], mac[1], mac[2], mac[3]);

    // 3. Integrity-protected NAS message構築
    uint8_t protected_nas[512];
    protected_nas[0] = 0x27;  // Security header type=2, PD=7
    memcpy(&protected_nas[1], mac, 4);
    protected_nas[5] = seq;
    memcpy(&protected_nas[6], plain_nas_msg, plain_len);

    // 4. DL COUNT increment
    ue_mapping->nas_dl_count++;

    // 5. S1AP Downlink NAS Transportで送信
    send_s1ap_downlink_nas_transport(protected_nas, 6 + plain_len);
}
```

### Phase 5: Initial Context Setup (5G→4G変換)
```c
void handle_initial_context_setup_5g_to_4g(
    const uint8_t *kgnb,        // from AMF (32 bytes) - 使用しない!
    ue_mapping_t *ue_mapping)
{
    printf("[INFO] [ICS] Received KgNB from AMF (will NOT use it)\n");
    printf("[INFO] [ICS] Deriving KeNB from cached KASME (4G native)\n");

    // 1. キャッシュされたKASMEを確認
    if (!ue_mapping->has_kasme) {
        printf("[ERROR] KASME not cached!\n");
        return;
    }

    // 2. キャッシュされたNAS COUNTを使用
    uint32_t count = ue_mapping->nas_count_for_kenb;
    printf("[INFO] [ICS] Using NAS COUNT: 0x%08X\n", count);

    // 3. KeNB導出 (FC=0x11) - TS 33.401 A.3
    uint8_t kenb[32];
    int ret = s1n2_kdf_kenb(ue_mapping->kasme, count, kenb);
    if (ret != 0) {
        printf("[ERROR] KeNB derivation failed\n");
        return;
    }

    printf("[INFO] [KDF] KeNB derivation from KASME (TS 33.401 A.3)\n");
    printf("[INFO] [KDF]   FC = 0x11 (KeNB derivation)\n");
    printf("[INFO] [KDF]   NAS_COUNT = 0x%08X\n", count);
    printf("[INFO] [KDF]   Input KASME (32 bytes):\n");
    for (int i = 0; i < 32; i++) {
        if (i % 16 == 0) printf("[INFO] [KDF]     ");
        printf("%02X", ue_mapping->kasme[i]);
        if (i % 16 == 15) printf("\n");
    }
    printf("[INFO] [KDF]   Output KeNB (32 bytes):\n");
    for (int i = 0; i < 32; i++) {
        if (i % 16 == 0) printf("[INFO] [KDF]     ");
        printf("%02X", kenb[i]);
        if (i % 16 == 15) printf("\n");
    }

    // 4. S1AP Initial Context Setup Request構築
    //    SecurityKey = kenb (導出した値を使用)
    build_and_send_s1ap_ics(kenb, ue_mapping);
}
```

### KDF実装例
```c
// TS 33.401 A.2: KASME derivation (FC=0x10)
int s1n2_kdf_kasme(const uint8_t *ck,
                   const uint8_t *ik,
                   const uint8_t *sqn_xor_ak,
                   const uint8_t *plmn_id,
                   uint8_t *kasme)
{
    uint8_t key[32];
    memcpy(key, ck, 16);
    memcpy(key + 16, ik, 16);

    // SNN: "EPS:mnc<MNC>.mcc<MCC>.3gppnetwork.org"
    char snn[64];
    sprintf(snn, "EPS:mnc%03d.mcc%03d.3gppnetwork.org",
            plmn_id[1] << 4 | plmn_id[2],  // MNC
            plmn_id[0] << 4 | (plmn_id[1] & 0x0F));  // MCC

    size_t snn_len = strlen(snn);

    // S = FC || P0 || L0 || P1 || L1
    uint8_t s[256];
    size_t pos = 0;

    s[pos++] = 0x10;  // FC for KASME derivation

    memcpy(&s[pos], snn, snn_len);
    pos += snn_len;

    s[pos++] = (snn_len >> 8) & 0xFF;
    s[pos++] = snn_len & 0xFF;

    memcpy(&s[pos], sqn_xor_ak, 6);
    pos += 6;

    s[pos++] = 0x00;
    s[pos++] = 0x06;

    // HMAC-SHA-256
    return hmac_sha256(key, 32, s, pos, kasme);
}

// TS 33.401 A.3: KeNB derivation (FC=0x11)
int s1n2_kdf_kenb(const uint8_t *kasme,
                  uint32_t nas_count,
                  uint8_t *kenb)
{
    // S = FC || P0 || L0
    uint8_t s[7];
    s[0] = 0x11;  // FC for KeNB derivation

    // NAS uplink COUNT (big endian)
    s[1] = (nas_count >> 24) & 0xFF;
    s[2] = (nas_count >> 16) & 0xFF;
    s[3] = (nas_count >> 8) & 0xFF;
    s[4] = nas_count & 0xFF;

    // Length of COUNT
    s[5] = 0x00;
    s[6] = 0x04;

    // HMAC-SHA-256
    return hmac_sha256(kasme, 32, s, 7, kenb);
}
```

---

## まとめ: s1n2での正しい鍵変換

### 実装のポイント

1. **auth_keys.yamlを活用**:
   ```yaml
   subscribers:
     - imsi: "001011234567895"
       ki: "8baf473f2f8fd09487cccbd7097c6862"
       opc: "8e27b6af0e692e750f32667a3b14605d"
   ```

2. **4G UEに対しては常に4G native**:
   - ABBAの有無に関係なく
   - FC=0x10でKASME導出
   - UEと完全に同じ鍵階層

3. **KASMEを必ずキャッシュ**:
   ```c
   memcpy(ue_mapping->kasme, kasme, 32);
   ue_mapping->has_kasme = true;
   // memset(kasme, 0, 32); ← これをしない!
   ```

4. **AMFのKgNBは使わない**:
   - KgNBは5G基地局用 (FC=0x70で導出)
   - KeNBは4G基地局用 (FC=0x11で導出)
   - s1n2がKASMEからKeNBを再導出

5. **NAS COUNT管理**:
   ```c
   // Security Mode Command送信時
   ue_mapping->nas_count_for_kenb = ue_mapping->nas_dl_count;

   // ICS送信時
   uint32_t count = ue_mapping->nas_count_for_kenb;
   s1n2_kdf_kenb(ue_mapping->kasme, count, kenb);
   ```

### 鍵変換フロー全体図

```
auth_keys.yaml
    ↓ (読み込み)
  K, OPc
    ↓
[Authentication Request (5G→4G)]
    ↓ RAND, SQN⊕AK キャッシュ
[Authentication Response (4G→5G)]
    ↓
Milenage(K, OPc, RAND) → CK, IK
    ↓
KDF(FC=0x10) → KASME ← ★キャッシュ
    ↓
KDF(type=0x01/0x02) → K_NASenc, K_NASint
    ↓
[Security Mode Command (5G→4G)]
    ↓ NAS COUNT キャッシュ
[Initial Context Setup (5G→4G)]
    ↓
KDF(FC=0x11) → KeNB ← ★KASME + COUNT から導出
    ↓
S1AP ICS Request送信
```

---

*Last updated: 2025-11-14*
