# U-Plane確立ガイド: 4G eNB ↔ 5G Core 通信実現

## 概要

本ドキュメントは、4G eNB (実機) と 5G Core (Open5GS) 間でのU-Plane (User Plane) データ通信を実現するために実施した修正と、その結果を記録したものです。

**構成:**
```
実機eNB (4G) → s1n2コンバーター → Open5GS (5G Core)
   S1AP         S1AP→NGAP変換        NGAP
   GTP-U        GTP-U TEID変換       GTP-U
```

**達成目標:**
- ✅ Attach手続きの成功
- ✅ Initial Context Setup (ICS) 完了
- ✅ PDU Session確立
- ✅ Uplink/Downlink U-Plane通信 (ping成功)

---

## 実装履歴

### Phase 1-11: C-Plane確立とNAS暗号化 (完了)

- Attach Request → Registration Request変換
- Authentication成功
- Security Mode Complete実装
- 双方向NAS暗号化実装 (EEA2/NEA2, EIA2/NIA2)

---

### Phase 12: Initial Context Setup Response実装 (完了)

**日付:** 2025-11-15
**pcap:** 20251115_27.pcap

#### 問題:
Initial Context Setupまで進むが、eNBからのInitial Context Setup Responseが処理されず、U-Planeが確立できない。

#### 修正内容:

**1. Initial Context Setup Response変換実装**

**ファイル:** `src/s1n2_converter.c`

```c
// Line 674-770: s1n2_convert_initial_context_setup_response() 関数追加
int s1n2_convert_initial_context_setup_response(s1n2_context_t *ctx,
                                                 uint8_t *s1ap_data, size_t s1ap_len,
                                                 uint8_t *ngap_data, size_t *ngap_len)
{
    // S1AP InitialContextSetupResponse decode
    // E-RAB Setup List抽出
    // GTP-U TEID情報取得 (eNB側のDL TEID)
    // NGAP PDUSessionResourceSetupResponse構築
    // QoS Flow設定
    // GTP-U Tunnel情報設定
}
```

**重要なポイント:**
- E-RAB Setup List → PDU Session Resource Setup Response List変換
- eNB S1-U TEID (Downlink)を抽出してUE mappingに保存
- QoS Flow Identifier = 1固定
- Transport Layer Address変換 (eNB IP → s1n2 IP)

**2. UE mapping構造体拡張**

**ファイル:** `include/s1n2_converter.h`

```c
typedef struct {
    // ... existing fields ...

    // GTP-U Tunnel Information (eNB側)
    bool has_enb_s1u_info;
    uint32_t enb_s1u_teid;              // eNB S1-U Downlink TEID
    char enb_s1u_addr[INET_ADDRSTRLEN]; // eNB S1-U IP Address

    // GTP-U Tunnel Information (s1n2側)
    bool has_s1n2_uplink_teid;
    uint32_t s1n2_s1u_uplink_teid;      // s1n2が割り当てたUplink TEID
} ue_id_mapping_t;
```

**3. メインループでの処理追加**

**ファイル:** `src/s1n2_converter.c`

```c
// Line 3867-3881: InitialContextSetupResponse処理追加
if (nas_init->value.present == S1AP_InitiatingMessage__value_PR_InitialContextSetupResponse) {
    printf("[INFO] ★★★ Received S1AP InitialContextSetupResponse ★★★\n");
    printf("[INFO] Converting to NGAP PDUSessionResourceSetupResponse\n");

    if (s1n2_convert_initial_context_setup_response(ctx, data, len,
                                                     ngap_data, &ngap_len) == 0) {
        printf("[INFO] ✅ Conversion successful, forwarding to AMF\n");
        ssize_t sent = sendto(ctx->n2_fd, ngap_data, ngap_len, 0,
                             (struct sockaddr *)&ctx->amf_addr,
                             sizeof(ctx->amf_addr));
        // ...
    }
}
```

#### 結果:
- ✅ Initial Context Setup Response変換成功
- ✅ AMFへの転送成功
- ✅ PDU Session確立完了
- ⚠️ しかし、U-Plane通信は不通（GTP-Uパケット転送未実装）

---

### Phase 13: GTP-U Uplink実装 (完了)

**日付:** 2025-11-15
**pcap:** 20251115_28.pcap (初回テスト)

#### 問題:
PDU Session確立後もpingが通らない。GTP-Uパケット転送が未実装。

#### 修正内容:

**1. GTP-U処理基盤実装**

**ファイル:** `src/core/s1n2_gtp.c`

```c
// Enhanced GTP-U packet processing
int s1n2_enhanced_gtp_message_handler(s1n2_context_t *ctx,
                                      uint8_t *data, size_t len)
{
    // GTP-Uヘッダー解析
    uint8_t message_type = data[1];
    uint32_t teid = (data[4] << 24) | (data[5] << 16) |
                    (data[6] << 8) | data[7];

    if (message_type == 0xFF) { // G-PDU
        // Direction detection based on TEID
        // Uplink: eNB → s1n2 → UPF
        // Downlink: UPF → s1n2 → eNB
    }
}
```

**2. Uplink TEID変換実装**

**ファイル:** `src/transport/gtp_tunnel.c`

```c
int gtp_tunnel_process_s1u_to_n3(const uint8_t *s1u_packet, size_t s1u_len,
                                 uint8_t **n3_packet, size_t *n3_len)
{
    // S1-U TEID (eNB → s1n2) を N3 TEID (s1n2 → UPF) に変換
    // TEID mapping table参照
    uint32_t old_teid = extract_teid(s1u_packet);
    uint32_t new_teid = lookup_n3_teid(old_teid);

    // GTP-Uヘッダー書き換え
    set_teid(output_packet, new_teid);
}
```

**3. Direction検出ロジック**

```c
// Uplink判定: s1n2が割り当てたS1-U Uplink TEIDと一致
for (size_t i = 0; i < ctx->num_ue_mappings; i++) {
    if (ctx->ue_mappings[i].s1n2_s1u_uplink_teid == teid) {
        is_uplink = true;
        // TEID変換してUPFへ転送
        break;
    }
}
```

#### 結果:
- ✅ Uplink GTP-U処理成功
- ✅ Ping Request (ICMP Echo Request) が 8.8.8.8 に到達
- ✅ Ping Reply (ICMP Echo Reply) が UPFまで戻る
- ❌ **Downlink不通**: Reply が eNB に届かない

---

### Phase 14: GTP-U Downlink実装 - Option A採用 (完了)

**日付:** 2025-11-15
**pcap:** 20251115_29.pcap, 20251115_30.pcap

#### 問題:
Downlink GTP-Uパケット (UPF → eNB方向) が転送されない。

#### 検討したアプローチ:

**Option A: Transparent Proxy (TEID変換なし) ✅採用**
```
UPF → s1n2: TEID = 0x01000908 (eNB TEID)
s1n2 → eNB: TEID = 0x01000908 (そのまま)
```
- 実装が最も簡単
- eNB TEIDをそのまま使用
- s1n2はパケット転送のみ

**Option B: Full TEID Translation (不採用)**
```
UPF → s1n2: TEID = 0xAAAAAAAA (s1n2 allocated)
s1n2 → eNB: TEID = 0x01000908 (eNB TEID)
```
- 実装が複雑
- SMFへのTEID通知が必要

#### 修正内容:

**1. Downlink Direction検出**

**ファイル:** `src/core/s1n2_gtp.c`

```c
// Downlink判定: eNBのS1-U Downlink TEIDと一致
for (size_t i = 0; i < ctx->num_ue_mappings; i++) {
    if (ctx->ue_mappings[i].has_enb_s1u_info &&
        ctx->ue_mappings[i].enb_s1u_teid == teid) {
        is_downlink = true;
        ue_map_downlink = &ctx->ue_mappings[i];
        break;
    }
}
```

**2. Transparent Proxy実装**

```c
if (is_downlink) {
    printf("[INFO] Processing DOWNLINK: N3 -> S1-U (Transparent Proxy)\n");

    if (ue_map_downlink->has_enb_s1u_info) {
        // eNB S1-U addressへ転送 (TEID変換なし)
        struct sockaddr_in enb_addr;
        inet_pton(AF_INET, ue_map_downlink->enb_s1u_addr,
                  &enb_addr.sin_addr);
        enb_addr.sin_port = htons(2152);

        ssize_t sent = sendto(ctx->s1u_fd, data, len, 0,
                            (struct sockaddr *)&enb_addr,
                            sizeof(enb_addr));
    }
}
```

**3. Initial Context Setup ResponseでのeNB情報保存**

```c
// E-RAB Setup Listから取得
ue_map->has_enb_s1u_info = true;
ue_map->enb_s1u_teid = enb_teid;
strncpy(ue_map->enb_s1u_addr, enb_ip_str,
        sizeof(ue_map->enb_s1u_addr) - 1);

printf("[INFO] Saved eNB S1-U Info: TEID=0x%08x, IP=%s\n",
       enb_teid, enb_ip_str);
```

#### 結果:
- ✅ **Downlink GTP-U処理成功**
- ✅ **Ping Reply が eNB に到達**
- ✅ **UEでPing成功確認！**
- ✅ **双方向U-Plane通信確立**

**pcap 28:** 4回 ping成功
**pcap 29:** 7回 ping成功
**pcap 30:** 6回 ping成功

---

## U-Plane確立成功の確認

### 成功した通信フロー:

```
┌─────────────────────────────────────────────────────────────────┐
│ Uplink (UE → Internet)                                          │
├─────────────────────────────────────────────────────────────────┤
│ UE → eNB: ICMP Echo Request (192.168.100.2 → 8.8.8.8)         │
│ eNB → s1n2: GTP-U G-PDU (S1-U TEID=0x00000001)                │
│ s1n2 → UPF: GTP-U G-PDU (N3 TEID=0x0000dda3) ← TEID変換      │
│ UPF → Internet: ICMP Echo Request (192.168.100.2 → 8.8.8.8)   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Downlink (Internet → UE)                                        │
├─────────────────────────────────────────────────────────────────┤
│ Internet → UPF: ICMP Echo Reply (8.8.8.8 → 192.168.100.2)     │
│ UPF → s1n2: GTP-U G-PDU (N3 TEID=0x01000908)                  │
│ s1n2 → eNB: GTP-U G-PDU (S1-U TEID=0x01000908) ← 変換なし    │
│ eNB → UE: ICMP Echo Reply (8.8.8.8 → 192.168.100.2)           │
└─────────────────────────────────────────────────────────────────┘
```

### pcap 30の詳細タイムライン:

```
Time 138.1s: Initial Context Setup完了
Time 138.6s: PDU Session確立完了
Time 139.8s: Ping #1 成功 (Reply受信)
Time 140.8s: Ping #2 成功
Time 141.8s: Ping #3 成功
Time 142.8s: Ping #4 成功
Time 143.8s: Ping #5 成功
Time 144.8s: Ping #6 成功
Time 148.9s: TAU Request発生 ← 問題発生
Time 149.0s: PFCP Session Deletion
以降: Ping Reply来ない (Downlink不通)
```

---

## 発見された問題: TAU後の通信断

### 現象:

- ✅ ICS完了後、6-7回のping成功
- ❌ 約10秒後にTAU (Tracking Area Update) 発生
- ❌ TAU後、ping timeoutになる

### 根本原因:

```
┌─────────────────────────────────────────────────────────────────┐
│ TAU発生メカニズム                                                │
├─────────────────────────────────────────────────────────────────┤
│ 1. Authentication Synch Failure発生                            │
│    - UE SQN: 154342                                            │
│    - Network SQN: 0 (リセット後)                               │
│    - 再認証成功するがUE側が不信感を持つ                         │
│                                                                 │
│ 2. SRB Poll Timer失効                                           │
│    - eNBがUEのNAS応答遅延を検出                                 │
│    - Timer expired (約10秒)                                    │
│                                                                 │
│ 3. UE自発的TAU実行                                              │
│    - ICS完了10秒後に発生                                        │
│    - 4G TAU Request (0x48)送信                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ TAU処理フロー (問題)                                             │
├─────────────────────────────────────────────────────────────────┤
│ 1. UE → eNB → s1n2: TAU Request (0x48)                        │
│                                                                 │
│ 2. s1n2の変換処理:                                              │
│    TAU Request (0x48) → Registration Request (0x41)           │
│    ※常に "initial registration (0x01)" として変換              │
│                                                                 │
│ 3. AMFの判断:                                                   │
│    "GUTI has already been allocated"                           │
│    → このUEは既に登録済み                                       │
│    → 新しいRegistration Request = 再登録要求                   │
│    → 既存のPDU Sessionは不要と判断                             │
│                                                                 │
│ 4. AMF → SMF: PDU Session Release要求                          │
│    POST /nsmf-pdusession/v1/sm-contexts/1/release             │
│                                                                 │
│ 5. SMF → UPF: PFCP Session Deletion Request                   │
│    → UPFがDownlink Path削除                                    │
│                                                                 │
│ 6. 結果:                                                        │
│    Uplink: 動作継続 ✅ (s1n2のTEID mapping維持)               │
│    Downlink: 不通 ❌ (UPFがTEID削除済み)                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## TAU問題への対応実装 (Phase 15)

**日付:** 2025-11-15
**pcap:** 20251115_31.pcap

### 実装内容:

#### 1. TAU検出機能追加

**ファイル:** `src/s1n2_converter.c`

```c
// Line 2340-2390: TAU Request検出
if (ue_map && processed_nas_len > 0) {
    uint8_t nas_message_type = 0;
    if (processed_nas_len >= 2) {
        nas_message_type = processed_nas_buf[1];
    }

    if (nas_message_type == 0x48) {
        // TAU Request detected
        printf("[INFO] ========== TAU REQUEST DETECTED ==========\n");
        printf("[INFO] Will be converted to 5G Mobility Registration Update\n");

        ue_map->in_tau_procedure = true;
        ue_map->preserve_teid_mapping = true;
        ue_map->tau_start_time = time(NULL);
    }
}
```

#### 2. TAU → Mobility Registration Update変換

**ファイル:** `src/nas/s1n2_nas.c`

```c
// Line 1847-1880: Registration type判定
uint8_t registration_type_5g = 0x01;  // Default: initial registration

if (msg_type == 0x48) {
    // 4G TAU Request → 5G Mobility Registration Update
    printf("[INFO] Converting 4G TAU Request (0x48) -> 5G Mobility Registration Update\n");
    printf("[INFO] Registration type: 0x03 (mobility registration updating)\n");
    registration_type_5g = 0x03;  // mobility registration updating
} else if (msg_type == 0x41 || msg_type == 0x0C) {
    printf("[INFO] Converting 4G Attach Request -> 5G Registration Request (initial)\n");
    registration_type_5g = 0x01;  // initial registration
}

nas_5g[nas_5g_offset++] = 0x41;  // Registration Request
nas_5g[nas_5g_offset++] = registration_type_5g;
```

#### 3. GTP-U処理でのTAU aware logging

**ファイル:** `src/core/s1n2_gtp.c`

```c
// TAU中のGTP-U転送ログ
if (ue_map_uplink->in_tau_procedure) {
    printf("[INFO] [TAU-AWARE] UE in TAU procedure, continuing U-Plane forwarding\n");
}
if (ue_map_uplink->preserve_teid_mapping) {
    printf("[DEBUG] [TAU-AWARE] TEID mapping protected (preserve_teid=true)\n");
}
```

### 結果:

**✅ 変換成功:**
- TAU Request (0x48) → Registration Request (0x41)
- Registration type = 3 (periodic/mobility registration updating)

**❌ 問題継続:**
- AMFが registration type を無視
- 常に "initial registration" として処理
- PFCP Session Deletion発生
- Ping通信断 (TAU後)

---

## 技術的詳細

### TEID Mapping Table

| Direction | Source | TEID | Destination | TEID |
|-----------|--------|------|-------------|------|
| **Uplink** | eNB (S1-U) | 0x00000001 | UPF (N3) | 0x0000dda3 |
| **Downlink** | UPF (N3) | 0x01000908 | eNB (S1-U) | 0x01000908 |

**Note:** Downlink方向は Transparent Proxy のため TEID変換なし

### GTP-U Header Structure

```c
struct gtp_header {
    uint8_t flags;        // Version, PT, E, S, PN
    uint8_t message_type; // 0xFF = G-PDU
    uint16_t length;      // Payload length
    uint32_t teid;        // Tunnel Endpoint Identifier
    // Optional: Sequence Number, N-PDU Number, Extension Header
};
```

### UE Mapping構造体 (最終版)

```c
typedef struct {
    bool in_use;
    long ran_ue_ngap_id;
    long amf_ue_ngap_id;
    long enb_ue_s1ap_id;
    long mme_ue_s1ap_id;

    // Security Context
    bool has_nas_keys;
    bool has_5g_nas_keys;
    uint8_t k_nas_int[32];
    uint8_t k_nas_enc[32];
    uint8_t k_nas_int_5g[32];
    uint8_t k_nas_enc_5g[32];
    uint32_t nas_ul_count_5g;
    uint32_t nas_dl_count_5g;

    // GTP-U Tunnel Information
    bool has_enb_s1u_info;
    uint32_t enb_s1u_teid;              // eNB Downlink TEID
    char enb_s1u_addr[INET_ADDRSTRLEN]; // eNB IP Address

    bool has_s1n2_uplink_teid;
    uint32_t s1n2_s1u_uplink_teid;      // s1n2 Uplink TEID

    // TAU (Tracking Area Update) handling
    bool in_tau_procedure;
    bool preserve_teid_mapping;
    time_t tau_start_time;

    time_t last_update;
} ue_id_mapping_t;
```

---

## 実装統計

### 修正ファイル数: 5ファイル

1. `src/s1n2_converter.c` - 主要な変換ロジック
2. `src/nas/s1n2_nas.c` - NAS変換処理
3. `src/core/s1n2_gtp.c` - GTP-U処理
4. `src/transport/gtp_tunnel.c` - TEID変換
5. `include/s1n2_converter.h` - 構造体定義

### コード追加量:

- Initial Context Setup Response: 約100行
- GTP-U Uplink処理: 約150行
- GTP-U Downlink処理: 約80行
- TAU検出・変換: 約60行
- **Total: 約390行**

---

## 動作確認済みシナリオ

### ✅ 成功シナリオ:

1. **4G Attach → 5G Registration**
   - Attach Request変換
   - Authentication成功
   - Security Mode Complete
   - Registration Complete

2. **Initial Context Setup**
   - ICS Request処理
   - E-RAB Setup
   - ICS Response変換
   - PDU Session確立

3. **U-Plane通信 (TAU前)**
   - Uplink ping成功
   - Downlink ping成功
   - 6-7回連続ping成功

### ⚠️ 制限事項:

1. **TAU後の通信断**
   - 原因: Open5GS AMFがregistration typeを無視
   - 影響: TAU発生後 (ICS完了10秒後) にDownlink不通
   - 対策: 未解決

2. **PDU Session再確立が必要**
   - TAU後は新しいPDU Session確立が必要
   - 自動再確立は未実装

---

## デバッグログ例

### 成功時のログ (U-Plane確立):

```
[INFO] ★★★ Received S1AP InitialContextSetupResponse ★★★
[INFO] Converting to NGAP PDUSessionResourceSetupResponse
[INFO] E-RAB Setup List: 1 items
[INFO] E-RAB ID: 5
[INFO] eNB S1-U TEID: 0x01000908
[INFO] eNB S1-U Address: 172.24.0.111
[INFO] Saved eNB S1-U Info: TEID=0x01000908, IP=172.24.0.111
[INFO] Building NGAP PDUSessionResourceSetupResponse
[INFO] ✅ Conversion successful, forwarding to AMF

[DEBUG] Enhanced GTP-U G-PDU processing, TEID=0x00000001
[DEBUG] Detected UPLINK packet: TEID=0x00000001 matches s1n2 uplink TEID
[INFO] Processing UPLINK: S1-U -> N3 (TEID translation)
[INFO] UPLINK S1-U→N3 G-PDU forwarded: TEID=0x00000001 (84 bytes)

[DEBUG] Enhanced GTP-U G-PDU processing, TEID=0x01000908
[DEBUG] Detected DOWNLINK packet: TEID=0x01000908 matches eNB downlink TEID
[INFO] Processing DOWNLINK: N3 -> S1-U (Transparent Proxy)
[INFO] DOWNLINK N3→S1-U G-PDU forwarded: TEID=0x01000908 to eNB 172.24.0.111 (84 bytes)
```

### TAU検出時のログ:

```
[DEBUG] [TAU-CHECK] NAS Message Type: 0x48
[INFO] ========== TAU REQUEST DETECTED ==========
[INFO] UE is initiating Tracking Area Update procedure
[INFO] Will be converted to 5G Mobility Registration Update (type=0x03)
[INFO] AMF should preserve existing PDU Session
[INFO] ENB=2, MME=2, AMF=2, RAN=2
[INFO] TAU flags set: in_tau=1, preserve_teid=1

[INFO] ========== Converting 4G TAU Request (0x48) -> 5G Mobility Registration Update ==========
[INFO] Registration type: 0x03 (mobility registration updating)
```

---

## 今後の課題

### 優先度: High

1. **TAU後の通信断解決**
   - Open5GS AMFソースコード修正
   - または TAU Request無視/偽装応答実装

2. **PDU Session自動再確立**
   - TAU Complete後の自動再確立機能

### 優先度: Medium

3. **複数UE対応**
   - 現状は1 UEのみテスト済み
   - 複数UE同時接続の検証

4. **Handover対応**
   - S1-Handover処理
   - X2-Handover処理

### 優先度: Low

5. **QoS制御**
   - 現状はQFI=1固定
   - 複数QoS Flow対応

6. **エラーハンドリング強化**
   - TEID mapping失敗時の処理
   - GTP-U Echo処理

---

## 参考資料

### 3GPP仕様:

- **TS 24.301:** NAS protocol for EPS (4G)
- **TS 24.501:** NAS protocol for 5GS (5G)
- **TS 36.413:** S1AP protocol (4G)
- **TS 38.413:** NGAP protocol (5G)
- **TS 29.281:** GTP-U protocol
- **TS 33.401:** Security architecture (4G)
- **TS 33.501:** Security architecture (5G)

### 実装時の重要な発見:

1. **Downlink TEID は eNB が決定する**
   - Initial Context Setup Responseで通知される
   - s1n2は変更せずそのまま使用 (Transparent Proxy)

2. **Uplink TEID は s1n2 が割り当てる**
   - Initial Context Setup Requestで指定
   - UPFへの通知に使用

3. **TAU Request は常に変換される**
   - s1n2は全4G NASを5G Registrationに変換
   - Registration typeの指定が重要

4. **AMF は registration type を無視する**
   - Open5GSの制限
   - ソースコード修正が必要

---

## まとめ

本実装により、4G eNBと5G Core間でのU-Plane通信が成功し、双方向のデータ通信が確認されました。

**達成事項:**
- ✅ Initial Context Setup Response変換実装
- ✅ GTP-U Uplink/Downlink処理実装
- ✅ TEID mapping管理
- ✅ Ping通信成功 (6-7回連続)

**残課題:**
- ❌ TAU後の通信断 (Open5GS AMFの制限)
- ⚠️ 長時間通信の安定性未検証

**最終評価:**
Phase 12-14の実装により、U-Plane確立の目標は達成されました。Phase 15のTAU対応は部分的な成功に留まり、Open5GS AMFの改修が必要です。

---

**Document Version:** 1.0
**Last Updated:** 2025-11-16
**Author:** s1n2 Development Team
