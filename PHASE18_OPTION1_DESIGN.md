# Phase 18: Option 1 実装設計書（最終改訂版）
**NGAP InitialContextSetupRequest遅延実行アプローチ**

作成日: 2025年11月11日
最終改訂: 2025年11月11日 22:00（Phase 18.1-18.3試行結果に基づく設計変更）
対象: ICS Failure問題の根本解決

---

## 🎯 Phase 18.1-18.3で判明した根本問題

### 問題の本質: RRC Connection Release
**タイムライン** (20251111_20.pcap):
```
17:16:06.xxx: eNB: attach,success
17:16:07.969: s1n2 → eNB: InitialContextSetupRequest (dummy UPF: 172.24.0.30)
17:16:08.195: eNB → s1n2: InitialContextSetupFailure (Cause=26: radio interface failure)
17:16:08.195: eNB: "release cause,,other" ← ★RRC Connection Release発行
17:16:08.369: s1n2 → eNB: E-RABSetupRequest (実UPF: 172.24.0.21) ← 174ms遅れ
              ↑ UEは既にRRC IDLE状態 = 無意味
```

### Phase 18.1-18.3の成果と限界

#### ✅ 成功した実装
1. **Phase 18.1-Revised**: ICS Failure検出 → Registration Complete偽装 → AMF状態遷移成功
2. **Phase 18.2**: PDU Session Resource Setup Request (proc=29) からUPF N3情報抽出成功
3. **Phase 18.3**: E-RAB Setup Request構築・送信成功（ASN.1 Protocol IE wrapper対応）

#### ❌ 判明した限界
1. **eNBはICS Failure直後にRRC Connection Releaseを発行**（Baicells実機の動作）
2. **E-RAB Setup Requestは切断後のUEに送信**（無効）
3. **S1AP ICS手順はRequest/Responseのみ**（後からSuccessを送れない）
4. **AMFは1回しかNGAP ICS Request (proc=14) を送信しない**（2nd ICS期待は誤り）

### 唯一の解決策: NGAP ICS Request遅延実行

**コンセプト**:
```
問題のフロー:
1. NGAP ICS Request受信 (dummy UPF)
2. 即座にS1AP ICS Request送信 (dummy UPF)
3. eNB: ICS Failure → RRC Release ← ★問題
4. PDU Session Resource Setup Request受信 (実UPF)
5. E-RAB Setup Request送信 ← 遅すぎる、UEはIDLE

修正後のフロー:
1. NGAP ICS Request受信 (dummy UPF)
2. UPF情報チェック → なし → ★ICS Requestをキャッシュ（保留）
3. Phase 18.1-Revised実行 (Registration Complete送信)
4. PDU Session Resource Setup Request受信 (実UPF) ← UPF情報取得
5. ★キャッシュされたICS Requestを実行（実UPF情報で）
6. S1AP ICS Request送信 (実UPF) ← 最初から正しい情報
7. eNB: ICS Response Success ✅
8. RRC Connection維持 ✅
```

---

## ⚠️ 重要な技術的発見（実装前の検証結果）

### 発見1: Registration Completeのメッセージタイプ
- ✅ **正しい**: `0x43` (TS 24.501, Open5GS定義で確認)
- ❌ **誤り**: コード内コメントに`0x5E`と記載あり（修正不要、実装は正しい）
- 📍 確認箇所: `/home/taihei/docker_open5gs_sXGP-5G/sources/open5gs/lib/nas/5gs/message.h:73`
  ```c
  #define OGS_NAS_5GS_REGISTRATION_COMPLETE 67  // 0x43
  ```

### 発見2: AMF FSM状態遷移（Open5GS v2.7.2実装）
- 📍 `/home/taihei/docker_open5gs_sXGP-5G/sources/open5gs/src/amf/gmm-sm.c:2366`
  ```c
  case OGS_NAS_5GS_REGISTRATION_COMPLETE:
      // ... 各種処理 ...
      OGS_FSM_TRAN(s, &gmm_state_registered);  // ★ここで状態遷移
      break;
  ```

### 発見3: 既存実装の確認
- ✅ `build_registration_complete()` 関数実装済み
  - 📍 `/home/taihei/docker_open5gs_sXGP-5G/sXGP-5G/src/nas/s1n2_nas.c:3027-3090`
  - Integrity protection対応
  - UL NAS COUNT管理

- ✅ NGAP UplinkNASTransport構築関数実装済み
  - 📍 L6238で既に使用実績あり（AUTO-SEND機能）

### 発見4: eNBとUPF間のGTP-U設計
- ✅ **eNBは直接UPFとGTP-Uトンネルを確立**
- ✅ s1n2は制御プレーンのみ（S1AP ↔ NGAP変換）
- ✅ データプレーンは素通し
- 構成:
  ```
  eNB (実機) ─S1AP─→ s1n2 (172.24.0.30) ─NGAP─→ AMF
      │
      └─────GTP-U────→ UPF (172.24.0.21)
         direct tunnel
  ```

---

## ⚠️ 重要な技術的発見（Phase 18.1-18.3試行結果）

### 発見1: AMFは2回目のNGAP ICS Requestを送信しない
**検証結果** (20251111_20.pcap):
```bash
# NGAP InitialContextSetupRequest (proc=14) の検索
$ docker logs s1n2 | grep "procedureCode.*14.*detected"
[DEBUG] NGAP InitialContextSetupRequest detected (proc=14) - IE count: 7
# → 1回だけ！

# 代わりにPDU Session Resource Setup Request (proc=29) を送信
$ tshark -r 20251111_20.pcap -Y "ngap.procedureCode == 29"
2982    Nov 11, 2025 17:16:08.219893000 JST
```

**結論**: 設計文書の「2回目のNGAP ICS」想定は誤り。実際はproc=29で実UPF情報を送信。

### 発見2: S1AP InitialContextSetup手順の正しい理解
```
S1AP InitialContextSetup手順:
MME/s1n2 → eNB: InitialContextSetupRequest
eNB → MME/s1n2: InitialContextSetupResponse (成功時)
               OR
eNB → MME/s1n2: InitialContextSetupFailure (失敗時)
```

**重要**: 
- ResponseもFailureも**eNBが送信するもの**
- s1n2は**受信側**であり、後からSuccessを送ることはプロトコル違反
- ICS手順は既に完了しており、再試行は新しいRequest送信が必要

### 発見3: eNBの動作特性（Baicells実機）
**ICS Failure時の挙動**:
```
17:16:07.969: ICS Request受信
17:16:08.195: ICS Failure送信
17:16:08.195: RRC Connection Release発行 ← ★即座に実行（1秒以内）
```

**eNBログ証跡**:
```
Nov 11 17:16:06: IMSI(001011234567895) attach,success
Nov 11 17:16:07: release cause,,other
```

**結論**: eNBはICS Failure後、即座にUEをRRC IDLE状態に遷移させる。この後に何を送っても無効。

### 発見4: Phase 18.1-18.3の実装は正常動作
**検証済み項目**:
- ✅ Registration Complete偽装 → AMF状態遷移成功
- ✅ PDU Session Resource Setup Request (proc=29) → UPF情報抽出成功
- ✅ E-RAB Setup Request構築・送信成功（ASN.1 Protocol IE wrapper対応）

**問題点**:
- ❌ E-RAB Setup Requestは既に切断されたUEに送信（174ms遅延）
- ❌ タイミングが遅すぎる（eNBはICS Failure後即座にRRC Release）

---

## 1. 実装方針（Option 1: NGAP ICS Request遅延実行）

### 1.1 実現可能性: ★★★★★ (98%)

#### 既存コンポーネント（Phase 18で確認済み）
| コンポーネント | 場所 | 状態 |
|---------------|------|------|
| Phase 18.1-Revised | s1n2_converter.c:5985-6100 | ✅ 実装・動作確認済み |
| Phase 18.2 (UPF抽出) | s1n2_converter.c:6550-6700 | ✅ 実装・動作確認済み |
| Phase 18.3 (E-RAB構築) | s1n2_converter.c:7210-7370 | ✅ 実装・動作確認済み |
| pending機構 | s1n2_converter.c:6754-6800 | ✅ ICS Response用に存在 |
| UE context管理 | s1n2_context.h | ✅ 拡張可能 |

#### 必要な追加実装（Phase 18.4）
1. **UE context構造体の拡張**（10-15行）
   ```c
   bool has_pending_ngap_ics_request;
   uint8_t pending_ngap_ics_request[2048];
   size_t pending_ngap_ics_request_len;
   time_t ngap_ics_request_time;
   ```

2. **NGAP ICS Request受信時の遅延判断**（20-30行）
   - Line 6935付近: `has_upf_n3_info`チェック
   - UPF情報なし → NGAP ICS Requestをキャッシュ
   - S1AP ICS Request送信をスキップ

3. **PDU Session Resource Setup Request受信時の実行**（15-25行）
   - UPF N3情報取得後
   - キャッシュされたNGAP ICS Requestを処理
   - Phase 18.2/18.4の既存ロジックを活用

### 1.2 リスク評価

#### 技術的リスク
- ✅ **リスクなし**: プロトコル準拠（ICS Requestを遅延させるだけ）
- ✅ **RRC接続維持**: 最初から正しいUPF情報でICS Requestを送信
- ✅ **既存実装活用**: Phase 18で実装・検証済みのロジックを流用

#### タイミングリスク
- ⚠️ **低リスク**: AMFからのタイムアウト（通常10-30秒）
  - 対策: Phase 18.1-RevisedでRegistration Complete送信済み
  - AMFは待機状態なので問題なし
  - PDU Session確立は通常1-3秒で完了

#### セキュリティリスク
- ✅ **リスクなし**: NAS Integrity保護は実装済み（Phase 18.1で検証済み）

#### 互換性リスク
- ✅ **リスクなし**: 標準的なS1AP ICS Request送信（タイミングが少し遅いだけ）
- ✅ **eNB互換性**: 正しいUPF情報を受信するため、ICS Successを返す

---

## 2. 代替案の評価と不可能性の確認

### Option 2: ICS Success偽装（Phase 18で誤解を訂正）
- ❌ **実現不可**: ICS ResponseもFailureもeNBが送信するもの
- ❌ **プロトコル違反**: s1n2は受信側であり、後からSuccessを送れない
- 結論: **根本的に不可能**

### Option 3: 2nd ICS Request送信（Phase 18で誤解を訂正）
- ❌ **無効**: eNBは既にRRC Connection Releaseを発行済み
- ❌ **UE context不在**: 切断後のUEに対してICS Requestを送っても無意味
- 結論: **RRC接続が切断された後では何をしても無効**

### Option 4: E-RAB Setup Request（Phase 18.3で実装・検証済み）
- ✅ **実装成功**: ASN.1エンコーディング成功（43 bytes）
- ❌ **タイミング問題**: 174ms遅延、UEは既にIDLE状態
- 結論: **実装は正しいが、タイミングが遅すぎる**

### Option 5: UPF情報ハードコード
- ⚠️ **実現可能だが非推奨**: 70%
- メリット: タイミング問題完全回避
- デメリット:
  - ❌ 環境依存（UPF IPが変わると動かない）
  - ❌ TEID衝突リスク
  - ❌ Phase 18.2で取得した実TEIDと不一致
- 評価: **緊急回避策としてのみ検討**

---

## 3. 実装詳細（Option 1: Phase 18.4）

### 3.1 Phase 18.4: NGAP ICS Request遅延機構

#### 実装箇所
📍 `/home/taihei/docker_open5gs_sXGP-5G/sXGP-5G/src/s1n2_converter.c`

**Step 1**: Line 6935付近（UPF情報チェック箇所）
**Step 2**: PDU Session Resource Setup Request受信時（Line 6550-6700付近）

```c
// 📍 Line 6935付近に追加
// Phase 18.4: NGAP ICS Request遅延判断

// 既存のPhase 18.2条件チェックの前に追加:
printf("[INFO] [Phase 18.4] Checking UPF N3 info availability\n");

if (!map2 || !map2->has_upf_n3_info) {
    printf("[INFO] [Phase 18.4] ★★★ No UPF N3 info yet - deferring ICS Request ★★★\n");
    printf("[INFO] [Phase 18.4]   Strategy: Wait for PDU Session Resource Setup Request\n");
    printf("[INFO] [Phase 18.4]   Expected: AMF will send proc=29 with real UPF info\n");
    fflush(stdout);
    
    // NGAP ICS Requestをキャッシュ
    if (!map2) {
        // UE contextがない場合は作成（通常はあるはず）
        printf("[WARN] [Phase 18.4] No UE context, creating new mapping\n");
        map2 = s1n2_context_find_or_create_mapping(ctx, enb_ue_id, mme_ue_id);
    }
    
    if (map2) {
        // NGAP ICS Requestを保存
        size_t copy_len = (len < sizeof(map2->pending_ngap_ics_request)) ? 
                          len : sizeof(map2->pending_ngap_ics_request);
        memcpy(map2->pending_ngap_ics_request, data, copy_len);
        map2->pending_ngap_ics_request_len = copy_len;
        map2->has_pending_ngap_ics_request = true;
        map2->ngap_ics_request_time = time(NULL);
        
        printf("[SUCCESS] [Phase 18.4] ✅ NGAP ICS Request cached (%zu bytes)\n", copy_len);
        printf("[INFO] [Phase 18.4]   Will execute after receiving UPF N3 info\n");
        printf("[INFO] [Phase 18.4]   AMF-UE-NGAP-ID: %ld, RAN-UE-NGAP-ID: %ld\n", 
               map2->amf_ue_ngap_id, map2->ran_ue_ngap_id);
        fflush(stdout);
        
        // S1AP ICS Requestは送信しない（重要！）
        handled = 1;
        goto cleanup;
    } else {
        printf("[ERROR] [Phase 18.4] Failed to create UE context for caching\n");
        // フォールバック: 従来通りdummy UPFで送信
    }
}

// UPF情報がある場合は通常処理（既存のPhase 18.2/18.4ロジック）
printf("[INFO] [Phase 18.4] UPF N3 info available - proceeding with ICS\n");
printf("[INFO] [Phase 18.4]   UPF IP: %s, TEID: 0x%08X\n",
       inet_ntoa(*(struct in_addr*)&map2->upf_n3_ip), map2->upf_n3_teid);
fflush(stdout);

// 以下、既存のPhase 18.2/18.4処理...
```

#### 実装コード（Step 2: 遅延実行）
```c
// 📍 PDU Session Resource Setup Request受信時（Line 6600-6650付近）
// UPF N3情報抽出後に追加:

if (ue_map) {
    ue_map->upf_n3_ip = upf_ip_be;
    ue_map->upf_n3_teid = ntohl(upf_dl_teid_be);
    ue_map->has_upf_n3_info = true;
    printf("[INFO] Stored UPF N3 info in UE context (ENB=%ld, UPF N3 TEID=0x%08x)\n",
           ue_map->enb_ue_s1ap_id, ue_map->upf_n3_teid);
    
    // ★★★ Phase 18.4: 遅延されたNGAP ICS Requestを実行 ★★★
    if (ue_map->has_pending_ngap_ics_request) {
        printf("\n");
        printf("[INFO] ═══════════════════════════════════════════════════════════════════\n");
        printf("[INFO] [Phase 18.4] ★★★ Executing deferred NGAP ICS Request ★★★\n");
        printf("[INFO] [Phase 18.4]   UPF N3 info now available: IP=%s, TEID=0x%08X\n",
               inet_ntoa(*(struct in_addr*)&ue_map->upf_n3_ip), ue_map->upf_n3_teid);
        printf("[INFO] ═══════════════════════════════════════════════════════════════════\n");
        fflush(stdout);
        
        // 遅延時間計測
        time_t now = time(NULL);
        double delay = difftime(now, ue_map->ngap_ics_request_time);
        printf("[INFO] [Phase 18.4] ICS Request was deferred for %.1f seconds\n", delay);
        
        // キャッシュされたNGAP ICS Requestを処理
        // 既存のNGAP ICS処理関数を呼び出し（ue_mapに実UPF情報が格納済み）
        int result = s1n2_handle_ngap_ics_internal(
            ctx,
            ue_map->pending_ngap_ics_request,
            ue_map->pending_ngap_ics_request_len,
            ue_map  // 実UPF情報を含むUE context
        );
        
        if (result == 0) {
            printf("[SUCCESS] [Phase 18.4] ✅ Deferred ICS Request executed successfully\n");
            printf("[INFO] [Phase 18.4]   S1AP ICS sent to eNB with real UPF info\n");
            printf("[INFO] [Phase 18.4]   Expected: eNB will return ICS Response (Success)\n");
        } else {
            printf("[ERROR] [Phase 18.4] Failed to execute deferred ICS Request (ret=%d)\n", result);
        }
        
        // キャッシュクリア
        ue_map->has_pending_ngap_ics_request = false;
        ue_map->pending_ngap_ics_request_len = 0;
        fflush(stdout);
    }
}
```

### 3.2 UE Context構造体の拡張

#### 実装箇所
📍 `/home/taihei/docker_open5gs_sXGP-5G/sXGP-5G/src/s1n2_context.h`

#### 追加フィールド
```c
typedef struct {
    // 既存フィールド...
    bool has_pending_s1ap_ics;
    uint8_t pending_s1ap_ics[512];
    size_t pending_s1ap_ics_len;
    
    // ★Phase 18.4新規追加★
    bool has_pending_ngap_ics_request;
    uint8_t pending_ngap_ics_request[2048];
    size_t pending_ngap_ics_request_len;
    time_t ngap_ics_request_time;
    
    // 既存フィールド（Phase 18.1-18.3で追加済み）
    bool has_upf_n3_info;
    uint32_t upf_n3_ip;
    uint32_t upf_n3_teid;
    uint8_t qfi;
    // ...
} ue_id_mapping_t;
```

### 3.3 内部処理関数の実装

#### s1n2_handle_ngap_ics_internal()
```c
// 📍 s1n2_converter.c に追加

/**
 * @brief NGAP InitialContextSetupRequestを処理（内部用）
 * 
 * 既存のNGAP ICS処理ロジックを関数化。
 * Phase 18.4でキャッシュされたICS Requestを処理する際に使用。
 * 
 * @param ctx s1n2コンテキスト
 * @param data NGAP PDUデータ
 * @param len データ長
 * @param ue_map UE context（実UPF情報を含む）
 * @return 0: 成功、-1: 失敗
 */
static int s1n2_handle_ngap_ics_internal(
    s1n2_context_t *ctx,
    const uint8_t *data,
    size_t len,
    ue_id_mapping_t *ue_map)
{
    // 既存のNGAP ICS処理ロジック（Line 6484-7000）を
    // 関数として抽出。ue_mapを引数として受け取り、
    // has_upf_n3_infoをチェックして実UPF情報を使用。
    
    // Phase 18.2/18.4の既存実装を活用
    // ue_map->has_upf_n3_info == true なので、
    // 実UPF情報でS1AP ICS Requestを構築
    
    // 実装詳細は既存コード（Line 6924-7000）を参照
    return 0;  // 成功
}
```

---

## 4. テストと検証計画

### 4.1 期待される動作フロー

```
テストシナリオ: Phase 18.4実装後の完全フロー

1. UE → eNB: RRC Connection Request
   ↓
2. eNB → s1n2: S1AP InitialUEMessage
   ↓
3. s1n2 → AMF: NGAP InitialUEMessage
   ↓
4. AMF → s1n2: NGAP DownlinkNASTransport (Authentication Request)
   ↓
5. s1n2 → eNB: S1AP DownlinkNASTransport
   ↓
6. ... (Authentication, Security Mode) ...
   ↓
7. AMF → s1n2: NGAP InitialContextSetupRequest (proc=14, dummy UPF)
   ↓
8. ★Phase 18.4★ s1n2: UPF情報チェック → なし
   ↓
9. ★Phase 18.4★ s1n2: NGAP ICS Requestをキャッシュ
   ログ: "[Phase 18.4] ★★★ No UPF N3 info yet - deferring ICS Request ★★★"
   ↓
10. ★Phase 18.4★ s1n2: S1AP ICS Request送信をスキップ
    eNBには何も送信しない（重要！）
   ↓
11. ★Phase 18.1-Revised★ s1n2 → AMF: Registration Complete (偽装)
   ↓
12. AMF: gmm_state_registered へ遷移
   ↓
13. ★Phase 18.1-Revised★ s1n2 → AMF: PDU Session Establishment Request
   ↓
14. AMF → SMF → UPF: PDU Session確立
   ↓
15. AMF → s1n2: PDU Session Resource Setup Request (proc=29, 実UPF情報)
   ↓
16. ★Phase 18.2★ s1n2: UPF N3情報抽出
    - UPF IP: 172.24.0.21
    - UPF TEID: 0x12345678 (実値)
    - QFI: 9
   ↓
17. ★Phase 18.4★ s1n2: has_pending_ngap_ics_request == true を検出
    ログ: "[Phase 18.4] ★★★ Executing deferred NGAP ICS Request ★★★"
   ↓
18. ★Phase 18.4★ s1n2: キャッシュされたNGAP ICS Requestを処理
    実UPF情報でS1AP ICS Requestを構築
   ↓
19. ★Phase 18.4★ s1n2 → eNB: S1AP InitialContextSetupRequest (実UPF情報)
    - Transport Layer Address: 172.24.0.21
    - GTP-TEID: 0x12345678
    - E-RAB ID: 5 (PDU Session IDから)
    - QCI: 9
   ↓
20. eNB: E-RAB確立処理（RRC Connection Reconfiguration）
   ↓
21. eNB → s1n2: S1AP InitialContextSetupResponse ✅ SUCCESS
    - E-RAB Setup Response List含む
    - eNB S1-U IP/TEID含む
   ↓
22. s1n2 → AMF: NGAP InitialContextSetupResponse
   ↓
23. eNB ↔ UPF: GTP-Uトンネル確立 ✅
   ↓
24. UE: データ通信可能 ✅
```

### 4.2 検証項目とログ確認

#### s1n2ログで確認すべき項目
```bash
# Phase 18.4: ICS Request遅延
$ docker logs s1n2 | grep "Phase 18.4"
[INFO] [Phase 18.4] ★★★ No UPF N3 info yet - deferring ICS Request ★★★
[SUCCESS] [Phase 18.4] ✅ NGAP ICS Request cached (XXX bytes)

# Phase 18.1-Revised: Registration Complete送信
$ docker logs s1n2 | grep "Phase 18.1-Revised"
[INFO] [Phase 18.1-Revised] ★★★ ICS Failure Detected - Initiating Workaround ★★★
[SUCCESS] [Phase 18.1-Revised] ✅ Fake Registration Complete sent

# Phase 18.2: UPF情報抽出
$ docker logs s1n2 | grep "Phase 18.2"
[SUCCESS] [Phase 18.2] ★★★ All conditions met - Adding E-RAB Setup info
[INFO] [Phase 18.2] UPF N3: IP=172.24.0.21, TEID=0x12345678

# Phase 18.4: 遅延実行
$ docker logs s1n2 | grep "Executing deferred"
[INFO] [Phase 18.4] ★★★ Executing deferred NGAP ICS Request ★★★
[SUCCESS] [Phase 18.4] ✅ Deferred ICS Request executed successfully
```

#### pcapで確認すべき項目
```bash

    if (build_registration_complete(reg_complete_nas, &reg_complete_len, ue_map) != 0) {
        printf("[ERROR] [Phase 18.1-Revised] Failed to build Registration Complete\n");
        goto skip_phase18_1_revised;
    }

    printf("[INFO] [Phase 18.1-Revised] Built Registration Complete (%zu bytes)\n", reg_complete_len);

    // 4. NGAP UplinkNASTransport構築
    uint8_t ngap_uplink[256];
    size_t ngap_uplink_len = sizeof(ngap_uplink);

    if (build_ngap_uplink_nas(ngap_uplink, &ngap_uplink_len,
                              ue_map->amf_ue_ngap_id, ue_map->ran_ue_ngap_id,
                              reg_complete_nas, reg_complete_len,
                              ue_map->has_location_info ? ue_map->plmn_id : NULL,
                              ue_map->has_location_info ? ue_map->plmn_id_len : 0,
                              ue_map->has_location_info ? ue_map->cell_id : 0,
                              ue_map->has_location_info ? ue_map->tac : 0) != 0) {
        printf("[ERROR] [Phase 18.1-Revised] Failed to build NGAP UplinkNASTransport\n");
        goto skip_phase18_1_revised;
    }

    // 5. AMFへ送信
    ssize_t sent = s1n2_send_ngap(ctx, ngap_uplink, ngap_uplink_len,
                                   "UplinkNASTransport(FakeRegistrationComplete)", 60);
    if (sent != (ssize_t)ngap_uplink_len) {
        printf("[ERROR] [Phase 18.1-Revised] Failed to send Registration Complete (ret=%zd)\n", sent);
        goto skip_phase18_1_revised;
    }

    printf("[SUCCESS] [Phase 18.1-Revised] ✅ Fake Registration Complete sent (%zd bytes)\n", sent);
    printf("[INFO] [Phase 18.1-Revised]   AMF will transition to gmm_state_registered\n");
    fflush(stdout);

    // 6. AMF状態遷移待機（10ms）
    usleep(10000);

    // 7. PDU Session Establishment Request送信
    printf("[INFO] [Phase 18.1-Revised] Sending PDU Session Establishment Request\n");

    uint8_t pdu_session_nas[512];
    size_t pdu_session_len = sizeof(pdu_session_nas);
    int ret = -1;

    if (USE_UL_NAS_TRANSPORT_WRAPPER) {
        ret = build_gmm_ul_nas_transport_with_n1_sm(
            pdu_session_nas, &pdu_session_len, ue_map,
            ue_map->pdu_session_id, ue_map->apn, 1, 1);
    } else {
        ret = build_5gsm_pdu_session_establishment_request(
            pdu_session_nas, &pdu_session_len, ue_map,
            ue_map->pdu_session_id, ue_map->apn, 1, 1);
    }

    if (ret != 0) {
        printf("[ERROR] [Phase 18.1-Revised] Failed to build PDU Session Request\n");
        goto skip_phase18_1_revised;
    }

    // NGAP UplinkNASTransport構築
    uint8_t ngap_pdu_session[512];
    size_t ngap_pdu_session_len = sizeof(ngap_pdu_session);

    if (build_ngap_uplink_nas(ngap_pdu_session, &ngap_pdu_session_len,
                              ue_map->amf_ue_ngap_id, ue_map->ran_ue_ngap_id,
                              pdu_session_nas, pdu_session_len,
                              ue_map->has_location_info ? ue_map->plmn_id : NULL,
                              ue_map->has_location_info ? ue_map->plmn_id_len : 0,
                              ue_map->has_location_info ? ue_map->cell_id : 0,
                              ue_map->has_location_info ? ue_map->tac : 0) != 0) {
        printf("[ERROR] [Phase 18.1-Revised] Failed to build NGAP for PDU Session\n");
        goto skip_phase18_1_revised;
    }

    sent = s1n2_send_ngap(ctx, ngap_pdu_session, ngap_pdu_session_len,
                          "UplinkNASTransport(PDUSessionRequest)", 60);
    if (sent != (ssize_t)ngap_pdu_session_len) {
        printf("[ERROR] [Phase 18.1-Revised] Failed to send PDU Session Request (ret=%zd)\n", sent);
        goto skip_phase18_1_revised;
    }

    printf("[SUCCESS] [Phase 18.1-Revised] ✅ PDU Session Request sent (%zd bytes)\n", sent);
    printf("[INFO] [Phase 18.1-Revised]   Waiting for UPF N3 info from AMF...\n");
    fflush(stdout);

    // フラグ設定（後続でE-RAB Setup待機）
    ue_map->waiting_for_upf_info = true;

skip_phase18_1_revised:
    // 既存処理継続
}
```

### 3.2 Phase 18.2: UPF情報受信とE-RAB Setup

既存のPhase 18.2ロジックを活用：
- NGAP DownlinkNASTransport受信
- または NGAP InitialContextSetupRequest #2受信
- UPF情報抽出（既存コードL6390-6490）
- E-RAB Setup Request送信

---

## 5. 設計概要

### 5.1 根本問題: "Chicken-and-Egg" Problem

```
┌────────────────────────────────────────────────────────┐
│  ICS Success ──→ Attach Complete ──→ Registered      │
│       ↑                                    ↓           │
│  Real UPF Info ←─── PDU Session ←── UL NAS Transport │
└────────────────────────────────────────────────────────┘
```

- **問題点**:
  - ICS成功にはReal UPF情報が必要
  - Real UPF情報取得にはPDU Session確立が必要
  - PDU Session確立には`registered`状態が必要
  - `registered`状態にはAttach Completeが必要
  - Attach CompleteにはICS成功が必要 → ★デッドロック★

### 5.2 Solution: Registration Complete偽装による状態遷移強制

```
ICS Failure Detection (Frame 1047)
         ↓
┌───────────────────────────────────┐
│ s1n2-converter                    │
│  ★ Fake Registration Complete ★  │  ← Phase 18.1-Revised
│  → AMF                            │
└───────────────────────────────────┘
         ↓ 10ms wait
┌───────────────────────────────────┐
│ AMF gmm-sm.c:2366                 │
│  OGS_FSM_TRAN(s,                  │
│    &gmm_state_registered)         │  ← State transition
└───────────────────────────────────┘
         ↓
┌───────────────────────────────────┐
│ s1n2-converter                    │
│  PDU Session Request              │  ← Now accepted
│  → AMF                            │
└───────────────────────────────────┘
         ↓
┌───────────────────────────────────┐
│ AMF → SMF → UPF                   │
│  N4 Session Establishment         │  ← UPF allocates TEID
└───────────────────────────────────┘
         ↓
┌───────────────────────────────────┐
│ AMF → s1n2 (NGAP)                 │
│  PDU Session Accept               │  ← Contains UPF N3 info
│  or ICS #2                        │
└───────────────────────────────────┘
         ↓
┌───────────────────────────────────┐
│ s1n2-converter                    │
│  E-RAB Setup Request              │  ← With Real UPF info
│  → eNB (S1AP)                     │     (172.24.0.21 + real TEID)
└───────────────────────────────────┘
         ↓
┌───────────────────────────────────┐
│ eNB → UPF                         │
│  GTP-U Tunnel Established         │  ← Direct tunnel
│  Data plane active                │
└───────────────────────────────────┘
```

### 5.3 詳細フロー（修正版）

#### ステップ1: 初期ICS失敗（既存動作）
```
eNB ←─ ICS(dummy: 172.24.0.30/0x01020304) ─ s1n2 ← AMF
     ─→ ICS Failure ────────────────────→ s1n2
```

#### ステップ2: Registration Complete偽装（NEW）
```
s1n2: build_registration_complete()
  ┌────────────────────────────┐
  │ 0x7E 0x01 [MAC] [SEQ]      │  ← Integrity protected
  │ 0x7E 0x00 0x43             │  ← Plain NAS (0x43 = Reg Complete)
  └────────────────────────────┘
       ↓
s1n2: build_ngap_uplink_nas()
  ┌────────────────────────────┐
  │ NGAP-PDU                   │
  │  procedureCode: 46         │  ← UplinkNASTransport
  │  RAN-UE-NGAP-ID            │
  │  AMF-UE-NGAP-ID            │
  │  NAS-PDU: [Reg Complete]   │
  └────────────────────────────┘
       ↓
s1n2 ──→ AMF (SCTP)
```

#### ステップ3: AMF状態遷移確認
```
AMF gmm-sm.c:2287
  case OGS_NAS_5GS_REGISTRATION_COMPLETE:
    ogs_info("[%s] Registration complete", amf_ue->supi);
    ...
    OGS_FSM_TRAN(s, &gmm_state_registered);  ← L2366
    break;
```

#### ステップ4: PDU Session Request送信（10ms後）
```
s1n2: Wait 10ms (usleep(10000))
s1n2: build_gmm_ul_nas_transport_with_n1_sm()
       ↓
s1n2 ──→ AMF (UL NAS Transport)
       ↓
AMF gmm-sm.c:1571 (registered state)
  common_register_state() ← Now accepted!
       ↓
AMF → SMF: PDU Session Create
SMF → UPF: N4 Session Establishment Request
UPF → SMF: N4 Session Establishment Response
        ├─ UPF N3 IP: 172.24.0.21
        └─ TEID: 0xXXXXXXXX (allocated)
```

#### ステップ5: UPF情報取得とE-RAB Setup
```
AMF ──→ s1n2 (NGAP DownlinkNASTransport or ICS #2)
           │
           ├─ PDU Session Accept (N1 SM)
           │   └─ QoS Profile
           │
           └─ PDU Session Resource Setup Request List
               └─ QosFlowSetupRequestList
                   ├─ UPF N3 IP: 172.24.0.21
                   └─ TEID: 0xXXXXXXXX
s1n2: Extract UPF info (Phase 18.2 existing logic)
s1n2: Build E-RAB Setup Request
  ┌────────────────────────────┐
  │ E-RAB Setup Request        │
  │  MME-UE-S1AP-ID            │
  │  eNB-UE-S1AP-ID            │
  │  E-RABToBeSetupListBearerSUReq:
  │    e-RAB-ID: 5             │
  │    e-RABlevelQoSParameters │
  │    transportLayerAddress:  │
  │      172.24.0.21           │  ← Real UPF IP
  │    gTP-TEID:               │
  │      0xXXXXXXXX            │  ← Real TEID
  └────────────────────────────┘
       ↓
s1n2 ──→ eNB (S1AP)
eNB ──→ s1n2 (E-RAB Setup Response - Success)
eNB ─(GTP-U)─→ UPF (Direct tunnel)
```

---

## 6. 検証方法

### 6.1 AMFログによる状態確認
```bash
docker logs -f amf 2>&1 | grep -E "Registration complete|FSM_TRAN|gmm_state_registered|UL NAS Transport"
```

**期待される出力**:
```
11/15 10:30:12.345: [amf] INFO: [imsi-001010123456789] Registration complete (amf-sm.c:2287)
11/15 10:30:12.346: [amf] INFO: [imsi-001010123456789] [gmm-sm] initial_context_setup -> registered (fsm.c:159)
11/15 10:30:12.356: [amf] INFO: [imsi-001010123456789] UL NAS Transport received (gmm-sm.c:1571)
11/15 10:30:12.357: [amf] INFO: [imsi-001010123456789] PDU Session Establishment Request
```

### 6.2 s1n2ログによる動作確認
```bash
tail -f /tmp/s1n2_converter.log | grep -E "Phase 18.1-Revised|SUCCESS|ERROR"
```

**期待される出力**:
```
[INFO] [Phase 18.1-Revised] ★★★ ICS Failure - sending fake Registration Complete
[INFO] [Phase 18.1-Revised]   Strategy: Force AMF state transition to gmm_state_registered
[SUCCESS] [Phase 18.1-Revised] ✅ Fake Registration Complete sent (87 bytes)
[INFO] [Phase 18.1-Revised]   AMF will transition to gmm_state_registered
[INFO] [Phase 18.1-Revised] Sending PDU Session Establishment Request
[SUCCESS] [Phase 18.1-Revised] ✅ PDU Session Request sent (143 bytes)
[INFO] [Phase 18.1-Revised]   Waiting for UPF N3 info from AMF...
[SUCCESS] [Phase 18.2] Extracted UPF N3 info: IP=172.24.0.21, TEID=0x12345678
[SUCCESS] [Phase 18.4] E-RAB Setup Request sent with real UPF info
```

### 6.3 eNBログによるE-RAB確認
```bash
grep "E-RAB Setup" /path/to/enb.log
```

**期待される出力**:
```
E-RAB Setup Request received: RAB-ID=5, UPF=172.24.0.21, TEID=0x12345678
E-RAB Setup successful: GTP-U tunnel established
```

### 6.4 Wiresharkによるパケット確認
```
フィルタ: sctp.port == 38412 or gtp
```

**確認ポイント**:
1. **Frame N**: S1AP InitialContextSetupFailure
2. **Frame N+1** (3-5ms後): NGAP UplinkNASTransport (Registration Complete 0x43)
3. **Frame N+2** (10-15ms後): NGAP UplinkNASTransport (PDU Session Request)
4. **Frame N+3**: NGAP DownlinkNASTransport (PDU Session Accept)
5. **Frame N+4**: S1AP E-RABSetupRequest (transportLayerAddress=172.24.0.21)
6. **Frame N+5**: S1AP E-RABSetupResponse (Success)
7. **Frame N+6以降**: GTP-U (172.24.0.21 ↔ eNB)

---

## 7. 成功基準

### 必須条件
- [ ] AMFが`gmm_state_registered`に遷移
- [ ] PDU Session Establishment成功
- [ ] UPF N3情報取得成功（IP + TEID）
- [ ] E-RAB Setup Response Success受信
- [ ] GTP-U Echoテスト成功

### 追加確認
- [ ] UE IPアドレス割り当て成功
- [ ] Ping疎通確認（UE ↔ DN）
- [ ] セキュリティ: NAS Integrityチェック成功

---

## 8. 想定される課題と対策

### 8.1 タイミング問題
**課題**: 10msの待機時間が不足する可能性
**対策**:
```c
// Adaptive waiting with polling
for (int i = 0; i < 50; i++) {  // Max 50ms
    usleep(1000);  // 1ms
    if (amf_state_confirmed) break;  // State check via NGAP query
}
```

### 8.2 NAS Sequence Number不整合
**課題**: 偽装メッセージのSEQ番号がずれる
**対策**:
- `ue_map->ul_nas_count`を正しく管理
- `build_registration_complete()`内で自動インクリメント確認

### 8.3 AMF側での検証失敗
**課題**: Integrity MAC検証失敗の可能性
**対策**:
- `ue_map->knas_int`が正しく設定されているか確認
- デバッグログで送信前にMAC値を出力

---

## 9. 将来の拡張

### Option 3実装（フォールバック）
```yaml
# s1n2_config.yaml
upf:
  default_n3_ip: "172.24.0.21"
  teid_range_start: 0x00010000
  teid_range_end: 0x0001FFFF
```

実装優先度: **Phase 3** (Option 1成功後)

---

## 10. 参考資料

- Open5GS AMF FSM: `/sources/open5gs/src/amf/gmm-sm.c`
- s1n2 NAS Builder: `/sXGP-5G/src/nas/s1n2_nas.c`
- 3GPP TS 24.501: 5GS NAS Protocol
- 3GPP TS 38.413: NG-RAN NGAP
- 3GPP TS 36.413: E-UTRAN S1AP

---

**Document Status**: ✅ Ready for Implementation
**Last Updated**: 2025-11-15
**Next Action**: Implement Phase 18.1-Revised at `s1n2_converter.c:5892`



### Week 1: Phase 18.1-Revised実装（1-2日）
- [ ] ICS Failure検出箇所にコード追加
- [ ] UE ID抽出ロジック
- [ ] Registration Complete偽装送信
- [ ] PDU Session Request送信
- [ ] ビルド・動作確認

### Week 2: 統合テスト（1日）
- [ ] 実eNBでの動作確認
- [ ] AMFログで状態遷移確認
- [ ] UPF情報取得確認
- [ ] E-RAB確立確認
- [ ] GTP-U通信確認

### Week 3: Phase 3実装（Option 3 フォールバック）（1-2日）
- [ ] YAML設定ファイルパーサー実装
- [ ] 静的UPF情報読み込み
- [ ] フォールバックロジック追加

**予想実装期間**: 3-5日

---

### 1.1 アプローチ
AMFから受信したNGAP InitialContextSetupRequestをs1n2が介入・修正し、E-RAB Setup情報を追加してeNBに送信する。

### 1.2 利点
- ✅ **タイミング問題なし**: AMFの内部処理に依存しない
- ✅ **3GPP仕様準拠**: S1AP ICSにE-RAB Setupは標準的に含まれる
- ⚠️ **課題**: 4G UEシナリオではUPF情報取得経路が限定的
- ✅ **既存コード活用**: Phase 17のPDU Session関連実装を一部流用可能

### 1.3 実装箇所
| 機能 | ファイル | 行番号範囲 | 説明 | 状態 |
|------|---------|-----------|------|------|
| NGAP ICS検出 | `s1n2_converter.c` | 6745-6835 | proc=14でのICS受信処理 | ✅ 実装済 |
| E-RAB追加 | `s1n2_converter.c` | 420-620 | S1AP ICS修正ロジック | ✅ 実装済 |
| UPF情報取得 | `s1n2_converter.c` | **要再設計** | 4G UE対応が必要 | ❌ 未実装 |

---

## 2. 技術的背景と現実の動作

### 2.1 5G UE標準フロー（設計時の想定）vs 4G UE接続フロー（現実）

#### 📊 5G UE標準フロー
```
UE (5G) → AMF: PDU Session Request
   ↓
AMF → SMF: Nsmf_PDUSession_CreateSMContext
   ↓
SMF → UPF: N4 Session Establishment (UPFがN3 TEID割り当て)
   ↓
SMF → AMF: N2 SM Information (UPF N3 IP/TEID含む)
   ↓
AMF → RAN: InitialContextSetupRequest
            └─ IE 74: PDUSessionResourceSetupListCxtReq ✅
                └─ PDUSessionResourceSetupRequestTransfer
                    └─ UL-NGU-UP-TNLInformation
                        ├─ transportLayerAddress: UPF IP ✅
                        └─ gTP-TEID: UPF TEID ✅
```

**この場合**: 既存コード (line 6390-6490) でIE 74からUPF情報を抽出可能 ✅

---

#### ⚠️ 4G UE接続フロー（実際の動作 - pcap_4 + AMFログで確認）
```
UE (4G) → s1n2 → AMF: Registration Request (4G UEと認識)
   ↓
┌─ s1n2: Security Mode Complete送信
│  ↓
├─ Phase 18.1: PDU Session Request送信 ✅
│  ├─ Frame 531: NGAP UplinkNASTransport
│  │   └─ 5GMM UL NAS Transport (0x67)
│  │       └─ PDU Session ID: 5
│  │       └─ Message Type: 0xC1 (PDU Session Establishment Request)
│  │       └─ DNN: "internet", SST: 1
│  ↓
├─ ★ AMF受信・デコード成功 ✅
│  └─ AMFログ: "Decode UL_NAS_TRANSPORT", "PDU_SESSION_IDENTITY_2: 0x05"
│  ↓
├─ ❌ AMF処理拒否（タイミング不適切）
│  ├─ AMFログ: "Unknown message [103]" (0x67 = UL NAS Transport)
│  ├─ 理由: Security Mode Complete処理中に受信
│  └─ AMF状態: gmm_state_security_mode() → gmm_state_initial_context_setup()
│     ↓
├─ ❌ AMF → SMF: Nsmf_PDUSession_CreateSMContext **送信されず** ❌
│     理由: AMFがPDU Session Requestを拒否
│     ↓
├─ ❌ SMF → UPF: N4 Session **確立されず** ❌
│     ↓
├─ ❌ UPF N3 TEID **割り当てなし** ❌
│     ↓
├─ AMF → s1n2: DownlinkNASTransport (Frame 624) ✅
│  └─ NAS-PDU: 0x7e02a44b0807... (暗号化)
│      └─ MAC: A4 4B 08 07 (AMFログと一致確認済み)
│      └─ 中身: Registration Accept (0x42)
│      └─ ★ PDU Session情報は含まれない（AMFが処理していないため）
│     ↓
├─ AMF内部状態確認 ❌
│  ├─ AMFログ: "Session summary: total=0, with_transfer=0, transfer_needed=FALSE"
│  └─ 管理中のPDU Session数 = 0個
│     ↓
└─ AMF → s1n2: InitialContextSetupRequest (Frame 530) ❌
    ├─ IE 74 (PDUSessionResourceSetupListCxtReq): なし ❌
    │   理由1: AMFが管理するPDU Session = 0個
    │   理由2: 4G eNB向けに省略（IE 74理解不可）
    └─ NAS-PDU: Registration Accept (暗号化)
       ↓
Phase 18.2: has_upf_n3_info == false
            → レガシービルダー使用
            → ダミー値設定 (IP=172.24.0.30, TEID=0x01020304)
            → eNB InitialContextSetupFailure
```

**検証済みの事実**:
- ✅ Frame 531: s1n2がPDU Session Request送信成功
- ✅ AMF受信: AMFがデコード成功、PDU Session ID=5確認
- ❌ AMF拒否: "Unknown message [103]" でSMFに転送せず
- ❌ Session数: `total=0, with_transfer=0` → IE 74なし
- ❌ UPF情報: どの経路でも取得不可

**この場合**: **AMFがPDU Session Requestを処理しないため、UPF情報取得経路が存在しない** ❌

---

### 2.2 AMF側の動作 (Open5GS) - 実証済み + UL NAS Transport受理条件

#### 2.2.1 ICS送信判断ロジック

**ソースコード**: `sources/open5gs/src/amf/nas-path.c` line 140-180

```c
// ICS送信判断ロジック
bool transfer_needed = false;
ogs_list_for_each(&amf_ue->sess_list, sess) {
    if (sess->transfer.pdu_session_resource_setup_request) {
        transfer_needed = true;  // ★ SMFからN2 SM情報が格納されている
        break;
    }
}

if (ran_ue->initial_context_setup_request_sent == false &&
    (ran_ue->ue_context_requested == true || transfer_needed == true)) {
    // InitialContextSetupRequest送信
    ngapbuf = ngap_ue_build_initial_context_setup_request(amf_ue, gmmbuf);
}
```

#### 2.2.2 AMF FSMのUL NAS Transport受理条件（コード調査結果）

**ソースコード**: `sources/open5gs/src/amf/gmm-sm.c`

| AMF状態 | UL NAS Transport受理 | 条件 | コード行 | 備考 |
|---------|---------------------|------|---------|------|
| **de_registered** | ✅ 受理ロジックあり | Integrity保護 + Security Context有効 | L1080–1220 `common_register_state()` | 初回はSecurity Context未確立で実質通らない |
| **authentication** | ❌ 不受理（Unknown） | — | L1600–1800 `default:` | 認証中はUL NAS処理しない |
| **security_mode** | ❌ 不受理（Unknown） | — | L1897–2060 `default:` | ★ここで「Unknown message [103]」発生 |
| **initial_context_setup** | ❌ 不受理（Unknown） | — | L2220–2450 `default:` | ICS処理中もUL NAS処理しない |
| **registered** | ✅ 受理 | Integrity保護 + Security Context有効 | L619–920 → `common_register_state()` L1571 | ★初回で受理可能な最初のタイミング |
| **exception** | ❌ 不受理 | — | L2460以降 | 例外状態 |

**受理条件の実装**（`common_register_state()` 内、L1571–1590）:
```c
case OGS_NAS_5GS_UL_NAS_TRANSPORT:
    if (!h.integrity_protected || !SECURITY_CONTEXT_IS_VALID(amf_ue)) {
        ogs_error("No Security Context");
        OGS_FSM_TRAN(s, gmm_state_exception);
        break;
    }

    gmm_handle_ul_nas_transport(
            ran_ue, amf_ue, &nas_message->gmm.ul_nas_transport);
    break;
```

**拒否ロジックの実装例**（`gmm_state_security_mode()`、L2058–2060）:
```c
default:
    ogs_error("Unknown message[%d]", nas_message->gmm.h.message_type);
    break;
```
→ このため「Unknown message [103]」（0x67 = UL NAS Transport）が記録される

**pcap_4 + AMFログから実証された事実**:

#### Frame 531 (29.653s): PDU Session Request送信
```
s1n2 → AMF: NGAP UplinkNASTransport
└─ 5GMM UL NAS Transport (0x67)
    └─ PDU Session Establishment Request (0xC1)
        ├─ PDU Session ID: 5
        ├─ DNN: "internet"
        └─ SST: 1
```

#### AMFログ (11:31:15.106): 受信・拒否
```
[nas] TRACE: [NAS] Decode UL_NAS_TRANSPORT
[nas] TRACE:   PAYLOAD_CONTAINER_TYPE - 0xf1
[nas] TRACE:   PDU_SESSION_IDENTITY_2 - 0x05 ✅
[nas] TRACE:   REQUEST_TYPE - 0x81
[nas] TRACE:   PAYLOAD_CONTAINER - 2e0501c1ffff91a1
                                      ^^    ^^ = PDU Session Establishment Request (0xC1) ✅
[gmm] ERROR: Unknown message [103] ❌ (0x67 = UL NAS Transport)
```
→ **拒否理由**: AMF状態が`gmm_state_security_mode()`にあり、UL NAS Transportの`case`が存在しない（L2058–2060で`default:`→Unknown）

#### AMFログ (11:31:15.106): Session状態
```
[amf] WARNING: Session summary: total=0, with_transfer=0, transfer_needed=FALSE ❌
[amf] INFO: InitialContextSetupRequest selected (ICS and PDU Session setup not required)
```

#### AMF状態遷移のタイムライン
```
11:31:15.105: Security Mode Complete受信 → gmm_state_security_mode()処理中
11:31:15.106: UL NAS Transport受信 → "Unknown message [103]" で拒否 ❌
11:31:15.106: gmm_state_security_mode() → gmm_state_initial_context_setup() 遷移
11:31:15.107: InitialContextSetupRequest送信（IE 74なし）
   （以降、gmm_state_registered()へ遷移するまでUL NAS Transport受理不可）
```

**結論**:
1. ✅ AMFはPDU Session Requestを**受信・デコード成功**
2. ❌ AMFは`gmm_state_security_mode()`中のため**「Unknown message [103]」で拒否**（コード: gmm-sm.c L2058–2060）
3. ❌ AMF → SMF通信は**発生せず** (AMFログに `Nsmf_PDUSession_CreateSMContext` なし)
4. ❌ `total=0` → AMFが管理するPDU Session数 = 0個
5. ❌ `transfer_needed=FALSE` → NGAP ICSにIE 74を含めない
6. ❌ 結果: s1n2がUPF情報を取得する手段がない

### 2.2 s1n2の既存実装

#### UE Context構造体 (`ue_id_mapping_t`)
**定義**: `sXGP-5G/include/s1n2_converter.h` line 150-270

既に必要な情報がすべて存在:
```c
typedef struct {
    // PDU Session情報
    uint8_t pdu_session_id;        // PDU Session ID (1-15)
    uint8_t qfi;                   // 5QI/QFI
    char apn[64];                  // APN/DNN

    // UPF N3トンネル情報
    uint32_t upf_n3_ip;            // UPF N3 IP (network byte order)
    uint32_t upf_n3_teid;          // UPF N3 TEID (host byte order)
    bool has_upf_n3_info;          // UPF情報の有効性フラグ ← ★ これがfalseのまま

    // その他の必要情報
    long enb_ue_s1ap_id;
    long mme_ue_s1ap_id;
    // ... (省略)
} ue_id_mapping_t;
```

#### 既存のUPF情報抽出コード
**場所**: `s1n2_converter.c` line 6320-6490

```c
// NGAP InitialContextSetupRequest処理
case NGAP_ProtocolIE_ID_id_PDUSessionResourceSetupListCxtReq:
    // IE 74から抽出
    // → UL-NGU-UP-TNLInformation (UPF IP/TEID)
    // → ue_map->upf_n3_ip = upf_ip_be;
    // → ue_map->upf_n3_teid = ntohl(upf_dl_teid_be);
    // → ue_map->has_upf_n3_info = true; ✅
```

**問題点**: 4G UEシナリオではIE 74が存在しないため、このコードが実行されない ❌

---

## 3. コンバーター単独でのPDU Session Request送信タイミング戦略

### 3.1 現状の問題整理（AMF改造なし前提）

#### 問題点
1. **Security Mode直後の送信（現Phase 18.1）**: AMFが`gmm_state_security_mode()`中で「Unknown message [103]」拒否
2. **Initial Context Setup中**: 同様に`gmm_state_initial_context_setup()`で拒否
3. **初回ICSには間に合わない**: AMFが`gmm_state_registered()`に遷移するのは**Registration Complete受信後**

#### AMF改造なしで実現可能な送信タイミング（AMF FSM遷移の実装確認済み）

| タイミング | AMF状態 | 受理可否 | 状態遷移コード | 実現可能性 |
|-----------|---------|---------|--------------|----------|
| Security Mode直後 | `gmm_state_security_mode()` | ❌ 拒否 | — | 現Phase 18.1（失敗済み） |
| ICS受信直後 | `gmm_state_initial_context_setup()` | ❌ 拒否 | — | 実装しても無意味 |
| Registration Accept受信後 | `gmm_state_initial_context_setup()` ⚠️ | ❌ 拒否 | L2234: Accept送信するが遷移せず | ❌ **不可** |
| **Registration Complete送信後** | `gmm_state_registered()` ✅ | ✅ 受理 | L2366: Complete受信で遷移 | ✅ **実現可能**（唯一の選択肢） |

**重要**: gmm-sm.c L2234でRegistration Acceptを送信しますが、その直後L2253の遷移条件（`!amf_ue->next.m_tmsi`）は通常GUTI割り当て済みのため**実行されません**。実際の`gmm_state_registered()`への遷移は**L2366のRegistration Complete受信時**です。

---

### 3.2 推奨戦略: Registration Complete後のPDU Session確立（AMF改造なし）

#### 概要
**シミュレーター成功ケース（simrator_success1call.pcap）で実証済み**のフローを採用。
Registration Complete送信直後にPDU Session Requestを送ることで、**2回目のInitialContextSetupRequest（NGAP）**にIE 74（UPF情報）を含めることが可能。

#### シミュレーター成功ケースの実測タイミング

```
=== 1回目のInitialContextSetup (S1AP) ===
Frame 1041 (61.225s): DownlinkNASTransport
Frame 1042 (61.225s): S1AP InitialContextSetupRequest（1回目）
                      - Attach accept含む
                      - E-RAB Setup含む（E-RAB ID: 5）
                      - transportLayerAddress: 172.24.0.30 ← シミュレーターのIP
Frame 1056 (62.517s): InitialContextSetupResponse (1.3秒後)

=== Registration Complete ===
Frame 1058 (62.721s): Attach complete
Frame 1059 (62.723s): Registration Complete送信
   ↓ 3.0ms
Frame 1061 (62.726s): UL NAS Transport (PDU Session Request) ✅
   ↓ 53.7ms (AMF内部処理: SMF→UPF→N4 Session確立)

=== 2回目のInitialContextSetup (NGAP) ===
Frame 1159 (62.780s): ★ NGAP InitialContextSetupRequest（2回目）
                      └─ IE 74: PDUSessionResourceSetupListCxtReq ✅
                          └─ PDU Session ID: 5
                          └─ transportLayerAddress: ac180015 (172.24.0.21)
                          └─ gTP-TEID: 00002ef0
   ↓ 0.4ms
Frame 1162 (62.780s): InitialContextSetupResponse ✅
```

**重要な発見**:
1. **InitialContextSetupRequestは2回送信される**
   - 1回目: S1AP (Frame 1042) - 4G Attach accept時
   - 2回目: NGAP (Frame 1159) - 5G PDU Session確立時 ← ★ IE 74含む
2. Registration Complete送信から**わずか3ms後**にPDU Session Requestを送信
3. AMFは`gmm_state_registered()`状態でこれを受理
4. 53.7ms後に送信される**2回目のInitialContextSetupRequest（NGAP）**にUPF情報が含まれる

**⚠️ シミュレーターと実eNBの動作差異**:
- **シミュレーター**: 1回目のS1AP ICS (Frame 1042)が**成功**（Response返却）
  - シミュレーターはE-RAB情報の厳密なチェックを行わない
  - transportLayerAddress: 172.24.0.30 (シミュレーター自身のIP)で受理
- **実eNB（予測）**: 1回目のS1AP ICS (Frame 1042)は**失敗**（Failure返却）
  - 実eNBはE-RAB情報を厳密にチェックする
  - UPF情報が正しくない、またはダミー値の場合はICS Failureを返す
  - **これは設計上想定内** - 2回目のNGAP ICSでリカバリー

**設計への影響**: なし
- 1回目のICS失敗は想定済み（既存設計の「3.5 完全なメッセージフロー」参照）
- 2回目のNGAP ICSのIE 74から正しいUPF情報を取得
- S1AP E-RAB Modify/Setupで実eNBに送信 → 成功

#### フロー（シミュレーター実証済み）

```
┌─────────┐                ┌─────────┐                ┌─────────┐
│   eNB   │                │  s1n2   │                │   AMF   │
└────┬────┘                └────┬────┘                └────┬────┘
     │                          │                          │
     │  1. Registration Req     │                          │
     ├─────────────────────────>│─────────────────────────>│
     │                          │                          │
     │  2. Security Mode        │                          │
     │<─────────────────────────│<─────────────────────────┤
     │                          │                          │
     │  3. SMC                  │                          │
     ├─────────────────────────>│─────────────────────────>│
     │                          │                          │
     │                          │  (AMF状態不適合のため)    │
     │                          │                          │
     │  4. NGAP ICS (IE 74なし) │                          │
     │<─────────────────────────│<─────────────────────────┤
     │                          │                          │
     │  5. S1AP ICS (ダミー値)   │                          │
     │<─────────────────────────│                          │
     │                          │  ★ Phase 18.2:           │
     │                          │  has_upf_n3_info=false   │
     │                          │  → レガシービルダー使用   │
     │                          │                          │
     │  6. ICS Failure ❌        │                          │
     │  4. NGAP ICS候補スキップ │                          │
     │     (AMF未送信)          │                          │
     │                          │                          │
     │  5. Registration Accept  │                          │
     │<─────────────────────────│<─────────────────────────┤
     │                          │  ★ まだ initial_context   │
     │                          │    _setup 状態 ⚠️         │
     │                          │  (gmm-sm.c L2234)        │
     │                          │                          │
     │  6. Registration Complete│                          │
     ├─────────────────────────>│─────────────────────────>│
     │                          │                          │
     │                          │  ★ AMF状態遷移完了 ✅      │
     │                          │  gmm_state_registered()  │
     │                          │  (gmm-sm.c L2366)        │
     │                          │                          │
     │                          │  ★ 3ms待機 (実測値)       │
     │                          │                          │
     │                          │  7. PDU Session Req ✅    │
     │                          ├─────────────────────────>│
     │                          │  (Phase 18.1実行)        │
     │                          │  UL NAS Transport (0x67) │
     │                          │  └─ PDU Session Req(0xC1)│
     │                          │     PSI=5, DNN=internet  │
     │                          │  ★ registered状態で受理   │
     │                          │    (gmm-sm.c L1571)      │
     │                          │                          │
     │                          │  8. AMF→SMF→UPF処理      │
     │                          │         (53.7ms実測)     │
     │                          │<─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┤
     │                          │  Nsmf_PDUSession_Create  │
     │                          │  N4 Session Establish    │
     │                          │  UPF N3 TEID割り当て ✅  │
     │                          │                          │
     │  9. NGAP ICS ✅          │                          │
     │<─────────────────────────│<─────────────────────────┤
     │     IE 74含む！           │  (proc=14)               │
     │     UPF IP: 172.24.0.21  │                          │
     │     UPF TEID: 00002ef0   │                          │
     │                          │                          │
     │  10. S1AP ICS ✅         │                          │
     │<─────────────────────────┤                          │
     │     E-RAB Setup含む       │  ★ Phase 18.2:          │
     │     UPF情報正常 ✅        │  IE 74抽出成功           │
     │                          │  has_upf_n3_info=true    │
     │                          │                          │
     │  11. ICS Response ✅      │                          │
     ├─────────────────────────>│─────────────────────────>│
     │     eNB DL TEID含む       │                          │
     │                          │                          │
```

#### メリット
- ✅ **AMF改造不要**: コンバーター側のみで実装可能
- ✅ **1回のAttachで完了**: 初回ICSにE-RAB情報を含められる（シミュレーター実証済み）
- ✅ **確実に受理される**: `gmm_state_registered()`でのUL NAS Transport受理は仕様準拠（gmm-sm.c L619→L1571）
- ✅ **タイミングが短い**: Registration Complete送信からわずか3ms後でOK（実測値）
- ✅ **標準フローに準拠**: 5G UEの初回Attach時PDU Session確立と同等
- ✅ **実績あり**: simrator_success1call.pcapで動作確認済み

#### デメリット
- ⚠️ **タイミングが重要**: Registration Complete送信直後（3-10ms程度）に送信が必要
- ⚠️ **AMF処理時間依存**: SMF→UPF→N4 Sessionの確立に50ms程度必要（AMFがICS送信前に完了させる）
- ⚠️ **実eNBでは1回目ICS失敗**: シミュレーターは1回目ICSを受理するが、実eNBは厳密チェックで拒否（想定内）

#### 実eNB vs シミュレーターの差異

| 項目 | シミュレーター | 実eNB（予測） |
|------|--------------|--------------|
| 1回目S1AP ICS | ✅ 成功 (Response) | ❌ 失敗 (Failure) |
| 理由 | E-RAB情報の厳密チェックなし | E-RAB情報を厳密チェック |
| 2回目NGAP ICS | ✅ IE 74受信 | ✅ IE 74受信 |
| E-RAB Modify/Setup | （不要） | ✅ 必要（2回目ICSから生成） |
| 最終結果 | ✅ 通信成功 | ✅ 通信成功 |

**設計への影響**: なし
- 実eNBでの1回目ICS失敗は想定済み
- 2回目のNGAP ICSでリカバリーする設計
- Phase 18.2で2回目ICSのIE 74を処理

---

### 3.3 実装アプローチ（シミュレーター成功パターン踏襲）

#### Phase 18.1の修正（送信タイミング変更）

**現状**（失敗している実装）:
// Security Mode Complete送信直後
if (has_pending_pdu_session && has_sent_smc) {
    printf("[INFO] [Phase 18.1] ★★★ Requesting PDU Session\n");
    send_pdu_session_establishment_request(...);
    // ❌ AMFが gmm_state_security_mode() 中で拒否
}
```

**修正後**（Registration Complete送信後に変更）:
```c
// UplinkNASTransport送信時（Registration Complete含む）
if (nas_pdu_type == 0x43) {  // Registration Complete
    printf("[INFO] Phase 18.1: Registration Complete sent\n");

    // AMF状態遷移を待つ（Registration Complete受信→gmm_state_registered遷移）
    // gmm-sm.c L2366: OGS_FSM_TRAN(s, &gmm_state_registered)
    usleep(50000);  // 50ms待機（AMF内部処理）

    if (has_pending_pdu_session) {
**修正後**（Registration Complete送信後3ms - シミュレーター実測値）:
```c
// UplinkNASTransport送信時（Registration Complete含む）
if (nas_pdu_type == 0x43) {  // Registration Complete
    printf("[INFO] Phase 18.1: Registration Complete sent\n");

    // シミュレーター成功ケースの実測値: 3ms待機
    // AMF状態遷移完了を待つ (gmm-sm.c L2366: OGS_FSM_TRAN(s, &gmm_state_registered))
    usleep(3000);  // 3ms待機（実測: 3.037ms）

    if (has_pending_pdu_session) {
        printf("[INFO] [Phase 18.1] ★★★ Requesting PDU Session after Registration Complete\n");
        printf("[INFO] [Phase 18.1]     Timing: 3ms after Reg Complete (simulator verified)\n");
        send_pdu_session_establishment_request(...);
        // ✅ AMFが gmm_state_registered() で受理（L619→L1571）
        // ✅ 53.7ms後にInitialContextSetupRequestでIE 74含む（実測）
    }
}
```

#### Phase 18.2の修正（proc=14のIE 74対応強化）

**重要**: シミュレーター成功ケースでは**InitialContextSetupRequest (proc=14)にIE 74が含まれる**。
proc=29対応は不要で、既存のproc=14ハンドラでIE 74抽出を確実に実行すればよい。

```c
// NGAP proc=14 (InitialContextSetupRequest) 受信時
case 14:  // InitialContextSetup
    printf("[INFO] Received InitialContextSetupRequest (proc=14)\n");

    // ★ IE 74（PDUSessionResourceSetupListCxtReq）抽出を確実に実行
    // シミュレーターではここにUPF情報が含まれる
    if (extract_upf_info_from_ie74(...) == SUCCESS) {
        printf("[INFO] [Phase 18.2] ✅ UPF N3 info extracted from IE 74\n");
        printf("[INFO] [Phase 18.2]     UPF IP: %s, TEID: 0x%08x\n", upf_ip, upf_teid);

        // S1AP ICS with E-RAB Setup構築
        build_s1ap_ics_with_erab(...);
    } else {
        printf("[WARN] [Phase 18.2] No IE 74 in ICS, using legacy builder\n");
        // レガシービルダーでフォールバック（ダミー値）
        build_s1ap_ics_legacy(...);
    }
    break;
```

---

### 3.4 期待される動作（シミュレーター実証済みフロー）

#### 初回Attach（1回で成功）
```
Frame 1-1058: 通常のRegistrationフロー（Authentication, Security Mode）
Frame 1059: Registration Complete送信 (62.723s)
Frame 1061: ★ Phase 18.1実行（3ms後, 62.726s）
            - UL NAS Transport (PDU Session Request)
            - AMF: gmm_state_registered()で受理 ✅
Frame 1159: NGAP InitialContextSetupRequest (53.7ms後, 62.780s)
            - ★ IE 74含む！ ✅
            - UPF IP: 172.24.0.21
            - UPF TEID: 0x00002ef0
Frame 1160: s1n2がIE 74抽出 ✅ (Phase 18.2)
Frame 1161: S1AP ICS with E-RAB Setup送信 ✅
            - E-RAB ID: 5
            - UPF N3 IP: 172.24.0.21
            - UPF N3 TEID: 0x00002ef0
Frame 1162: eNB ICS Response Success ✅
            - eNB DL TEID返却
Frame 1163以降: GTP-Uトンネル確立、データ通信開始 ✅
#### AMFログ（期待 - シミュレーター実証済みパターン）
```
[時刻A]: [amf] INFO: [imsi-001010000000001] Registration complete
[時刻A]: [gmm] INFO: State transition: initial_context_setup → registered (L2366)
[時刻A+3ms]: [gmm] INFO: UL NAS Transport received ✅
[時刻A+3ms]: [nas] TRACE: Decode UL_NAS_TRANSPORT ✅
[時刻A+3ms]: [nas] TRACE: PDU_SESSION_IDENTITY_2 - 0x05
[時刻A+4ms]: [smf] INFO: Nsmf_PDUSession_CreateSMContext ✅
[時刻A+10ms]: [smf] INFO: N4 Session Establishment Request
[時刻A+50ms]: [upf] INFO: N4 Session Established, N3 TEID allocated ✅
[時刻A+53ms]: [smf] INFO: N2 SM Info sent to AMF (UPF IP/TEID)
[時刻A+54ms]: [amf] INFO: Sending InitialContextSetupRequest
[時刻A+54ms]: [ngap] INFO: IE 74 (PDUSessionResourceSetupListCxtReq) included ✅
```

**重要**: シミュレーター成功ケースでは、InitialContextSetupRequestにIE 74が含まれるため、**1回のAttachで完全に成功**します。2回目のフローは不要です。

---

### 3.5 実際にUE通信が可能になるまでの完全なメッセージフロー

#### 前提条件
- AMF改造なし（コンバーターのみで実装）
- 初回ICSは失敗するが、登録は完了
- PDU Session確立後のNGAP proc=29でE-RAB確立

#### フロー全体像

```
┌──────────┐          ┌──────────┐          ┌─────┐     ┌─────┐     ┌─────┐
│   UE     │          │   eNB    │          │ s1n2│     │ AMF │     │ UPF │
│  (4G)    │          │          │          │     │     │     │     │     │
└────┬─────┘          └────┬─────┘          └──┬──┘     └──┬──┘     └──┬──┘

═══════════════════════ Phase 1: 初回Attach（失敗するが登録完了） ════════════════════════

     │ Attach Request       │                   │         │         │
     ├─────────────────────>│ S1AP Initial UE   │         │         │
     │                      ├──────────────────>│ NGAP    │         │
     │                      │                   ├────────>│         │
     │                      │                   │  Registration Req │
     │                      │                   │         │         │
     │                      │  Authentication / Security Mode       │
     │<═════════════════════╪═══════════════════╪═════════╪═════════│
     │                      │                   │         │         │
     │ Security Mode Complete                   │         │         │
     ├─────────────────────>│                   │         │         │
     │                      ├──────────────────>│────────>│         │
     │                      │                   │   ✅ SMC received  │
     │                      │                   │         │ (L1959) │
     │                      │                   │         │ state=  │
     │                      │                   │         │ security│
     │                      │                   │         │ _mode   │
     │                      │                   │         │         │
     │                      │ NGAP ICS (no IE74)│         ├───┐     │
     │                      │<─────────────────────────────┤   │ ICS │
     │                      │                   │         │<──┘ sent│
     │ S1AP ICS (dummy)     │                   │         │ (L2131) │
     │<─────────────────────┤                   │         │ state=  │
     │                      │  ★ has_upf_n3_info=false    │ initial │
     │                      │  → legacy builder  │         │ _context│
     │                      │                   │         │ _setup  │
     │                      │                   │         │         │
     │ ICS Failure ❌        │                   │         │         │
     ├─────────────────────>│ S1AP ICS Failure  │         │         │
     │                      ├──────────────────>│ NGAP    │         │
     │                      │                   ├────────>│         │
     │                      │                   │  ICS Failure      │
     │                      │                   │         │         │
     │                      │  Registration Accept        │         │
     │<═════════════════════╪═══════════════════╪═════════┤         │
     │                      │                   │         │ (L2234) │
     │                      │                   │   ⚠️ state = still│
     │                      │                   │     initial_context│
     │                      │                   │     _setup!       │
     │                      │                   │         │         │
     │ Registration Complete│                   │         │         │
     ├─────────────────────>│                   │         │         │
     │                      ├──────────────────>│────────>│         │
     │                      │                   │   Reg Complete    │
     │                      │                   │         ├───┐     │
     │                      │                   │         │   │State│
     │                      │                   │         │   │Trans│
     │                      │                   │         │<──┘ition│
     │                      │                   │         │ (L2366) │
     │                      │                   │         │ state = │
     │                      │                   │         │registered│
     │                      │                   │         │    ✅    │

═══════════ Phase 2: PDU Session確立開始（Registration Complete送信後） ═══════════

     │                      │                   │ ★ 50ms wait       │
     │                      │                   │   (AMF internal)  │
     │                      │                   │         │         │
     │                      │  [Phase 18.1] PDU Session Request     │
     │                      │                   ├────────>│         │
     │                      │                   │ UL NAS Transport  │
     │                      │                   │  (0x67) │         │
     │                      │                   │   └─ PDU Session  │
     │                      │                   │      Establishment│
     │                      │                   │      Request(0xC1)│
     │                      │                   │         ├───┐     │
     │                      │                   │         │   │Accept│
     │                      │                   │         │<──┘(L1571)│
     │                      │                   │         │ state=  │
     │                      │                   │         │registered│
     │                      │                   │         │   ✅     │
     │                      │                   │         │         │
     │                      │                   │      AMF→SMF      │
     │                      │                   │         ├────────>│
     │                      │                   │   Nsmf_PDUSession_│
     │                      │                   │   CreateSMContext │
     │                      │                   │         │         │
     │                      │                   │         │      SMF→UPF
     │                      │                   │         │         ├──>
     │                      │                   │         │    N4 Session
     │                      │                   │         │    Establishment
     │                      │                   │         │         │
     │                      │                   │         │    ✅ UPF N3
     │                      │                   │         │      TEID
     │                      │                   │         │      allocated
     │                      │                   │         │         │
     │                      │                   │      SMF→AMF      │
     │                      │                   │         │<────────┤
     │                      │                   │    N2 SM Info     │
     │                      │                   │    (UPF IP/TEID)  │

═══════════ Phase 3: E-RAB確立（AMFからproc=29受信） ═══════════════════

     │                      │  NGAP PDUSessionResourceSetupRequest  │
     │                      │<─────────────────────────────────────┤
     │                      │                   │ (proc=29)         │
     │                      │                   │<────────┤         │
     │                      │                   │ ★ IE 74:│         │
     │                      │                   │  UPF N3 │         │
     │                      │                   │  IP/TEID│         │
     │                      │                   │         │         │
     │                      │                   ├───┐     │         │
     │                      │                   │   │[Phase 18.2]   │
     │                      │                   │   │Extract IE 74  │
     │                      │                   │<──┘ UPF info ✅   │
     │                      │                   │ has_upf_n3_info=  │
     │                      │                   │        true       │
     │                      │                   │         │         │
     │                      │                   ├───┐     │         │
     │                      │                   │   │Build S1AP     │
     │                      │                   │   │E-RAB Setup    │
     │                      │                   │<──┘ or Modify     │
     │                      │                   │         │         │
     │ S1AP E-RAB Setup Request (正しいUPF情報)  │         │         │
     │<─────────────────────┤                   │         │         │
     │  - E-RAB ID          │<──────────────────┤         │         │
     │  - UPF N3 IP ✅      │                   │         │         │
     │  - UPF N3 TEID ✅    │                   │         │         │
     │  - QoS parameters    │                   │         │         │
     │                      │                   │         │         │
     ├────┐                 │                   │         │         │
     │    │ eNB: E-RAB      │                   │         │         │
     │    │ setup, allocate │                   │         │         │
     │    │ eNB DL TEID     │                   │         │         │
     │<───┘                 │                   │         │         │
     │                      │                   │         │         │

═══════════ Phase 4: E-RAB確立完了 & GTP-Uトンネル確立 ═══════════════

     │ E-RAB Setup Response │                   │         │         │
     ├─────────────────────>│ S1AP Response     │         │         │
     │  - eNB DL TEID ✅    ├──────────────────>│ NGAP    │         │
     │                      │                   ├────────>│         │
     │                      │                   │  Response         │
     │                      │                   │  (eNB TEID)       │
     │                      │                   │         ├────────>│
     │                      │                   │      AMF→SMF      │
     │                      │                   │   (eNB TEID info) │
     │                      │                   │         │         │
     │                      │                   │         │      SMF→UPF
     │                      │                   │         │         ├──>
     │                      │                   │         │    N4 Modify
     │                      │                   │         │    (eNB TEID)
     │                      │                   │         │         │
     │                      │                   │         │    ✅ UPF DL
     │                      │                   │         │      rule
     │                      │                   │         │      updated
     │                      │                   │         │         │

═══════════════════ Phase 5: データ通信開始 ✅ ═══════════════════════

     │                      │                   │         │         │
     │ ★ UE → eNB: Uplink Data (IP packet)      │         │         │
     ├─────────────────────>│                   │         │         │
     │                      │ GTP-U (UL)        │         │         │
     │                      │  Src: eNB UL TEID │         │         │
     │                      │  Dst: UPF N3 TEID ✅        │         │
     │                      ├─────────────────────────────┼────────>│
     │                      │                   │         │         ├──> Internet
     │                      │                   │         │         │
     │ ★ Internet → UPF: Downlink Data          │         │         │
     │                      │                   │         │    <────┤
     │                      │ GTP-U (DL)        │         │         │
     │                      │  Src: UPF internal│         │         │
     │                      │  Dst: eNB DL TEID ✅        │         │
     │<─────────────────────┤<────────────────────────────┼─────────┤
     │ Downlink Data        │                   │         │         │
     │                      │                   │         │         │
     │ ✅ 通信成功！          │                   │         │         │
```

#### 重要なポイント（シミュレーター成功ケース分析結果）

1. **Registration Complete後にAMF状態遷移**
   - L2366で`gmm_state_registered()`に遷移
   - ここで初めてUL NAS Transport受理可能に

2. **PDU Session Requestは3ms後でOK**
   - シミュレーター実測: Registration Complete送信から3.0ms後
   - AMF状態遷移は即座に完了（コード上は同期処理）
   - 3-10ms程度の待機で十分

3. **InitialContextSetupRequestは2回送信される（重要！）**
   - **1回目 (Frame 1042)**: S1AP InitialContextSetupRequest
     - 4G Attach accept時
     - E-RAB Setup含む（ただしシミュレーターのIP: 172.24.0.30）
     - Registration Complete前に送信
   - **2回目 (Frame 1159)**: NGAP InitialContextSetupRequest ← ★ IE 74含む
     - 5G PDU Session確立時
     - PDU Session Request受信から53.7ms後（実測）
     - AMF内部でSMF→UPF→N4 Session確立を完了してからICS送信
     - IE 74にUPF N3情報を含む（UPF IP: 172.24.0.21, TEID: 0x00002ef0）

4. **Phase 18.2は2回目（NGAP）のICS対応が必要**
   - 1回目のS1AP ICSには4G用のE-RAB情報しかない
   - **2回目のNGAP ICSのIE 74からUPF情報を抽出する**
   - has_upf_n3_info=true になることを確認
   - S1AP E-RAB Modify Request構築が必要（2回目のICS用）
   - **proc=29対応は不要**（シミュレーターでは送信されないため）

5. **GTP-Uトンネル確立の流れ（シミュレーター実証）**
   ```
   1. PDU Session Request (Frame 1061)
      ↓
   2. AMF → SMF → UPF: N4 Session (53.7ms)
      ↓
   3. UPF N3 TEID割り当て: 0x00002ef0
      ↓
   4. NGAP ICS with IE 74 (Frame 1159)
      ↓
   5. s1n2: IE 74抽出 → UPF IP: 172.24.0.21, TEID: 0x00002ef0
      ↓
   6. S1AP ICS with E-RAB Setup
      ↓
   7. eNB: E-RAB確立、DL TEID割り当て
      ↓
   8. ICS Response (Frame 1162) → Success ✅
   ```

---

### 3.6 実装スケジュール（シミュレーター成功パターン踏襲）

#### Week 1: Phase 18.1修正（1-2日）
- [ ] Registration Complete検出ロジック追加
- [ ] 送信タイミング変更（Security Mode直後 → **Registration Complete送信後3ms**）
  - シミュレーター実測値: 3.037ms
  - 実装値: usleep(3000) で3ms待機
- [ ] テスト・デバッグ
  - pcapでタイミング確認
  - AMFログで受理確認

#### Week 2: Phase 18.2確認（1日）
- [ ] proc=14 (InitialContextSetupRequest) のIE 74抽出確認
  - 既存コードが正常動作するか検証
  - has_upf_n3_info=true になることを確認
- [ ] S1AP ICS with E-RAB Setup構築確認
  - UPF N3情報が正しく埋め込まれるか確認
- [ ] デバッグログ追加
  - IE 74抽出成功/失敗を明確に出力

#### Week 3: 統合テスト（1-2日）
- [ ] pcapキャプチャ（全フロー記録）
- [ ] 初回Attach成功確認（シミュレーター同様）
  - Registration Complete送信
  - 3ms後にPDU Session Request送信
  - UL NAS Transport受理確認（AMFログ）
  - 53ms程度待機
  - InitialContextSetupRequest受信
  - IE 74含まれることを確認 ✅
- [ ] E-RAB確立確認
  - S1AP ICS with E-RAB Setup送信
  - eNB ICS Response Success確認 ✅
- [ ] データ通信確認
  - UL GTP-U疎通（UE→eNB→UPF）
  - DL GTP-U疎通（Internet→UPF→eNB→UE）
  - ping/http動作確認 ✅

**予想される実装期間**: 2-4日（シミュレーター成功パターンを踏襲するため、短期間で実装可能）

---

## 4. シミュレーター成功ケース vs 実eNB失敗ケースの比較
Frame 531 (29.653s): s1n2 → AMF: PDU Session Request送信 ✅
   ↓
AMFログ (11:31:15.106):
   - [nas] TRACE: Decode UL_NAS_TRANSPORT ✅
   - [nas] TRACE: PDU_SESSION_IDENTITY_2: 0x05 ✅
   - [gmm] ERROR: Unknown message [103] ❌ (0x67 = UL NAS Transport)
   - 理由: Security Mode Complete処理中に受信
   ↓
AMFログ (11:31:15.106):
   - [amf] WARNING: Session summary: total=0 ❌
   - with_transfer=0, transfer_needed=FALSE ❌
   ↓
結果:
   - AMF → SMF通信なし ❌
   - UPF N3 TEID割り当てなし ❌
   - NGAP ICS IE 74なし ❌
```

**結論**: Phase 18.1は正しく送信されているが、**AMFのタイミング制約により処理されない**。
→ 以下の選択肢はすべて、この根本的問題を解決する必要がある。

---

### Option A: NAS復号化実装 ⚠️ 複雑だが確実

#### 概要
DownlinkNASTransport (Frame 624) の暗号化NAS-PDUを復号化し、PDU Session Acceptを解析してUPF情報を抽出。

#### メリット
- ✅ 4G UEシナリオで動作する**可能性**がある
- ✅ 5GC標準フローに準拠

#### デメリット
- ❌ **AMFがPDU Session Requestを拒否しているため、Frame 624にPDU Session情報が含まれない**
- ❌ 復号化しても意味がない（Registration Acceptのみ）
- ❌ NAS暗号化アルゴリズム実装が必要（AES-128-CTR, SNOW 3G, ZUC）
- ❌ 5GSM (PDU Session) メッセージパーサー実装が必要
- ❌ 実装コストが高く保守困難
- ❌ セキュリティリスク（鍵管理）

#### 実装コスト
**推定**: 2週間〜4週間

**pcap_4検証結果**: ❌ **実装しても無意味**（AMFがPDU Session処理していない）

---

### Option A-2: Phase 18.1のタイミング変更 + NAS復号化 ⚠️ 複雑

#### 概要
1. PDU Session Requestの送信を**ICS受信後**に変更
2. AMFが再度DownlinkNASTransportを送信するのを待つ
3. その応答を復号化してUPF情報抽出

#### メリット
- ✅ AMFの状態遷移後なので処理される可能性

#### デメリット
- ❌ ICS受信後では遅すぎる（eNBは既にICS Failureを返す）
- ❌ タイミング問題が複雑化
- ❌ NAS復号化実装が必要
- ❌ 動作保証なし

#### 実装コスト
**推定**: 3週間〜5週間

---

### Option B: AMF動作変更（2段階アプローチ） ✅ 最も確実

#### 概要
Open5GS AMFのコードを修正し、以下2点を改善:
1. **Phase 18.1の受信タイミング問題修正**: Security Mode Complete処理中でもUL NAS Transportを受け付ける
2. **4G UE接続時のIE 74追加**: NGAP ICSにPDU Session情報を含める

#### メリット
- ✅ 根本的問題（AMFのタイミング制約）を解決
- ✅ s1n2側の既存コード (line 6320-6490) がそのまま使える
- ✅ 実装がシンプル
- ✅ 5GC標準に準拠（IE 74は本来含まれるべき）

#### デメリット
- ⚠️ Open5GS AMFの改造が必要（2箇所）
- ⚠️ Open5GSのアップデート時に再適用が必要

#### 実装手順（修正1: タイミング問題解決）
```c
// sources/open5gs/src/amf/gmm-sm.c
// gmm_state_security_mode() 関数内

// 修正前:
case OGS_NAS_5GS_SECURITY_MODE_COMPLETE:
    // Security Mode処理のみ
    break;
default:
    ogs_error("Unknown message [%d]", message_type); ❌
    return;
```

```c
// 修正後:
case OGS_NAS_5GS_SECURITY_MODE_COMPLETE:
    // Security Mode処理
    break;
case OGS_NAS_5GS_UL_NAS_TRANSPORT: // ★ UL NAS Transportも受付
    // PDU Session Request処理に転送
    gmm_handle_ul_nas_transport(amf_ue, &message->gmm);
    break;
default:
    ogs_error("Unknown message [%d]", message_type);
    return;
```

#### 実装手順（修正2: IE 74追加）
```c
// sources/open5gs/src/amf/ngap-build.c
// ngap_ue_build_initial_context_setup_request() 関数内

// 修正前:
if (sess->transfer.pdu_session_resource_setup_request) {
    // IE 74追加
}

// 修正後:
if (sess->transfer.pdu_session_resource_setup_request ||
    (amf_ue->rat_type == OpenAPI_rat_type_EUTRA && sess->pdu_session_id)) {
    // ★ 4G UE + PDU Session存在時も強制追加
    // IE 74追加（4G UEの場合はsessから情報取得）
}
```

#### 実装コスト
**推定**: 5日〜1週間（2箇所修正 + テスト）

---

### Option C: PDUSessionResourceSetupRequest待ち受け ⚠️ 不確実

#### 概要
NGAP ICS後に送信される可能性のある `PDUSessionResourceSetupRequest` (proc=29) を待ち受け、そこからUPF情報を抽出。

#### メリット
- ✅ s1n2側のみの実装で完結
- ✅ 既存コード (line 6320-6490) の一部を流用可能

#### デメリット
- ❌ **pcap_4で確認済み**: このメッセージが来ない ❌
- ❌ AMFが送信しない場合は無意味
- ❌ タイミング依存の問題が発生する可能性

#### 実装コスト
**推定**: 5日〜1週間（調査含む）

**pcap_4検証結果**: `proc=29` のメッセージは存在しない → **実装不可**

---

### Option D: ダミー値使用（現状維持） ❌ 非推奨

#### 概要
UPF情報を取得せず、ダミー値でS1AP ICSを構築（現在の動作）。

#### メリット
- ✅ 実装不要

#### デメリット
- ❌ eNBが確実にICS Failureを返す
- ❌ 接続失敗

**結果**: pcap_4で確認済み - Frame 536でeNB InitialContextSetupFailure ❌

---

### Option E: Phase 18.1送信タイミング完全変更 ⚠️ 根本解決にならない

#### 概要
PDU Session RequestをICS受信**後**に送信し、次回のPDU Session確立フローでUPF情報を取得。

#### メリット
- ✅ AMFの状態遷移完了後なので処理される可能性

#### デメリット
- ❌ ICS受信後では遅すぎる（eNBは既にICS処理済み）
- ❌ 次回のフローでしか効果がない（初回Attach失敗）
- ❌ タイミング問題が複雑化
- ❌ 実装しても現在の問題は解決しない

**結論**: ❌ 実装する意味なし

---

## 4. 推奨アプローチ：Option B（AMF改造 - 2段階修正）

### 4.1 理由
1. **根本的問題を解決**（AMFのタイミング制約 + IE 74欠如）
2. **実装コストは中程度**（5日〜1週間）
3. **既存のs1n2コードをそのまま活用可能**
4. **5GC標準に準拠**（IE 74は本来含まれるべき情報）
5. **確実に動作する**（問題の根本原因を修正）

### 4.1.1 AMFログから判明した根本原因

**pcap_4 + AMFログ検証結果**:
```
11/11 11:31:15.106: [gmm] ERROR: Unknown message [103] ❌
```
→ AMFが`gmm_state_security_mode()`中に受信したUL NAS Transport (0x67)を拒否

**AMFソースコード**: `sources/open5gs/src/amf/gmm-sm.c` line 1909-2422
```c
void gmm_state_security_mode(ogs_fsm_t *s, amf_event_t *e)
{
    switch (e->h.id) {
        case OGS_NAS_5GS_SECURITY_MODE_COMPLETE:
            // 処理する
            break;
        default:
            ogs_error("Unknown message [%d]", message_type); ❌
            return; // ★ ここでPDU Session Requestが拒否される
    }
}
```

**結論**: Option Bの修正1（タイミング問題解決）は**必須**

### 4.2 実装計画

#### Step 1: AMF動作調査（1日）
```bash
# AMFソースコード確認
cd sources/open5gs/src/amf
grep -r "Unknown message" .
grep -r "gmm_state_security_mode" .
grep -r "PDUSessionResourceSetupListCxtReq" .
grep -r "initial_context_setup" .
```

**期待される発見**:
- `gmm-sm.c` line 2422: `ogs_error("Unknown message [%d]", message_type);` ← ★修正箇所1
- `ngap-build.c` line ???: `if (sess->transfer.pdu_session_resource_setup_request)` ← ★修正箇所2

#### Step 2: AMF修正1 - タイミング問題解決（2日）
**ファイル**: `sources/open5gs/src/amf/gmm-sm.c`

**現状のコード** (line 1909-2422付近):
```c
void gmm_state_security_mode(ogs_fsm_t *s, amf_event_t *e)
{
    // ... (省略)
    switch (e->h.id) {
        case OGS_NAS_5GS_SECURITY_MODE_COMPLETE:
            // SMC処理
            gmm_handle_security_mode_complete(amf_ue, &message->gmm);
            break;
        default:
            ogs_error("Unknown message [%d]", message_type); ❌
            return; // ★ ここがPDU Session拒否の原因
    }
}
```

**修正後のコード**:
```c
void gmm_state_security_mode(ogs_fsm_t *s, amf_event_t *e)
{
    // ... (省略)
    switch (e->h.id) {
        case OGS_NAS_5GS_SECURITY_MODE_COMPLETE:
            // SMC処理
            gmm_handle_security_mode_complete(amf_ue, &message->gmm);
            break;
        case OGS_NAS_5GS_UL_NAS_TRANSPORT: // ★ 追加
            // UL NAS Transport処理に転送
            ogs_debug("Received UL NAS Transport during Security Mode");
            gmm_handle_ul_nas_transport(amf_ue, &message->gmm);
            break;
        default:
            ogs_error("Unknown message [%d]", message_type);
            return;
    }
}
```

**期待される効果**:
- PDU Session Request (0xC1) が拒否されず、SMFに転送される
- AMF → SMF: `Nsmf_PDUSession_CreateSMContext` 送信
- SMF → UPF: N4 Session確立、TEID割り当て
- `total=1, with_transfer=1, transfer_needed=TRUE` になる

#### Step 3: AMF修正2 - IE 74追加（1日）
**ファイル**: `sources/open5gs/src/amf/ngap-build.c`

```c
// 関数: ngap_ue_build_initial_context_setup_request()

// 修正箇所: IE 74追加判定
ogs_list_for_each(&amf_ue->sess_list, sess) {
    if (sess->pdu_session_id) {
        // ★ 修正: 4G UEの場合も強制的にIE 74を追加
        if (sess->transfer.pdu_session_resource_setup_request ||
            (amf_ue->rat_type == OpenAPI_rat_type_EUTRA && sess->sm_context_ref)) {
            // ★ 条件追加: 4G UE && Session確立済み

            // PDUSessionResourceSetupListCxtReq構築
            // (既存コードを流用)
        }
    }
}
```

#### Step 4: AMF再ビルド・デプロイ（1日）
```bash
cd sources/open5gs
meson build --reconfigure
ninja -C build
docker compose build amf-s1n2
docker compose up -d amf-s1n2
```

#### Step 5: 動作確認（1-2日）
```bash
# pcap_5キャプチャ
sudo tcpdump -i br-sXGP-5G -w log/20251111_5.pcap 'sctp or udp port 2152 or tcp port 7777'

# AMFログ確認（修正1の効果）
docker logs amf-s1n2 | grep -E "PDU|Unknown|Session summary"

# 期待されるログ:
# [gmm] DEBUG: Received UL NAS Transport during Security Mode ✅
# [nas] TRACE: Decode UL_NAS_TRANSPORT ✅
# [amf] WARNING: Session summary: total=1, with_transfer=1 ✅ (0から1に変化)

# Frame確認（修正2の効果）
tshark -r log/20251111_5.pcap -Y "frame.number == 530" -V | grep "PDUSessionResource"

# 期待される出力:
# IE 74: PDUSessionResourceSetupListCxtReq ✅
#   PDU Session ID: 5
#   UL-NGU-UP-TNLInformation
#     transportLayerAddress: 172.24.0.13 (UPF IP)
#     gTP-TEID: 0x12345678
```

---

## 5. 詳細設計（Option B採用時）

### 5.1 全体フロー（改訂版）

```
┌─────────┐                ┌─────────┐                ┌─────────┐                ┌─────────┐
│   eNB   │                │  s1n2   │                │   AMF   │                │   SMF   │
└────┬────┘                └────┬────┘                └────┬────┘                └────┬────┘
     │                          │                          │                          │
     │  1. SMC                  │                          │                          │
     ├─────────────────────────>│                          │                          │
     │                          │  2. SMC (NGAP)           │                          │
     │                          ├─────────────────────────>│                          │
     │                          │                          │                          │
     │                          │  3. PDU Session Req      │                          │
     │                          ├─────────────────────────>│  4. CreateSMContext      │
     │                          │     (Phase 18.1)         ├─────────────────────────>│
     │                          │                          │                          │
     │                          │                          │  5. N4 Session (UPF選択) │
     │                          │                          │<─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┤
     │                          │                          │  6. N2 SM Info           │
     │                          │                          │<─────────────────────────┤
     │                          │  7. DownlinkNASTransport │     (UPF IP/TEID)        │
     │                          │<─────────────────────────┤                          │
     │                          │     (暗号化: スキップ)     │                          │
     │                          │                          │                          │
     │                          │  8. NGAP ICS             │                          │
     │                          │<─────────────────────────┤                          │
     │                          │     ★ IE 74: あり ✅      │                          │
     │                          │     (AMF改造により追加)    │                          │
     │                          │                          │                          │
     │                          │  ★ Phase 18.2介入 ★       │                          │
     │                          │  - IE 74からUPF情報抽出   │                          │
     │                          │    (既存コード line 6390) │                          │
     │                          │  - has_upf_n3_info=true  │                          │
     │                          │  - E-RAB情報生成         │                          │
     │                          │  - S1AP ICS構築          │                          │
     │                          │    (IE 24: E-RAB追加)    │                          │
     │                          │                          │                          │
     │  9. S1AP ICS (IE 24含む) │                          │                          │
     │<─────────────────────────┤                          │                          │
     │                          │                          │                          │
     │  10. ICS Response ✅      │                          │                          │
     ├─────────────────────────>│                          │                          │
     │                          │  11. NGAP ICS Response   │                          │
     │                          ├─────────────────────────>│                          │
     │                          │                          │                          │
```

### 5.2 Phase 18.1: PDU Session Request送信（現状維持）

#### 目的
AMFにPDU Session作成を依頼し、SMFがUPFを選択・N3トンネルを確立するきっかけを作る。

#### 実装状態
✅ **実装済み** (line 4914-5100)

**動作**:
```c
// Security Mode Complete送信後
if (has_pending_pdu_session && has_sent_smc) {
    printf("[INFO] [Phase 18.1] ★★★ Requesting PDU Session to obtain UPF info\n");

    // PDU Session Establishment Request送信
    // → AMF受信 → デコード成功
    // → ❌ AMFが"Unknown message [103]"で拒否（タイミング不適切）
    // → SMF/UPF通信は発生せず
}
```

**pcap_4 + AMFログ検証結果**:
- ✅ Frame 531: PDU Session Request送信成功
- ✅ AMF受信: デコード成功、PDU Session ID=5確認
- ❌ AMF処理: 「Unknown message [103]」で拒否
  - 理由: Security Mode Complete処理中に受信
  - AMF状態: `gmm_state_security_mode()` → `gmm_state_initial_context_setup()`
- ❌ AMF → SMF: `Nsmf_PDUSession_CreateSMContext` **送信されず**
- ❌ Session状態: `total=0, with_transfer=0, transfer_needed=FALSE`
- ❌ Frame 624: DownlinkNASTransport（Registration Acceptのみ、PDU Session情報なし）

**根本的な問題**:
Phase 18.1の送信タイミングは正しい（SMC AFTER + 2ms）が、AMFの内部状態機械が**「Security Mode Complete処理中」に受信したUL NAS Transport**を拒否する実装になっている。

**Option B採用後の期待**:
- AMFの動作は変わらないが、**別の手段**（後続のPDU Session Request再送、またはAMF状態遷移後の再処理）でPDU Session確立が完了すれば、次回のICSではIE 74が含まれる可能性がある
- しかし、**現在のフロー（初回Registration時）ではPDU Session確立が完了しない**ため、AMF改造なしでは解決困難

### 5.3 Phase 18.2: NGAP ICS検出とUPF情報抽出

#### 実装箇所
`s1n2_converter.c` line 6320-6490 **(既存コード - Option B採用時はそのまま活用)**

#### 動作フロー
```c
// NGAP InitialContextSetupRequest受信 (proc=14)
case NGAP_ProtocolIE_ID_id_PDUSessionResourceSetupListCxtReq:
    // ★ IE 74が存在する（AMF改造により保証）

    for (int j = 0; j < lst->list.count; j++) {
        struct NGAP_PDUSessionResourceSetupItemCxtReq *item = lst->list.array[j];

        // PDUSessionResourceSetupRequestTransferをデコード
        NGAP_PDUSessionResourceSetupRequestTransfer_t *transfer = ...;

        // UL-NGU-UP-TNLInformation抽出
        if (xfer_ie->id == NGAP_ProtocolIE_ID_id_UL_NGU_UP_TNLInformation) {
            NGAP_GTPTunnel_t *gtp_tunnel = ...;

            // UPF IP抽出
            uint32_t upf_ip_be = 0;
            memcpy(&upf_ip_be, gtp_tunnel->transportLayerAddress.buf, 4);

            // UPF TEID抽出
            uint32_t upf_dl_teid_be = 0;
            memcpy(&upf_dl_teid_be, gtp_tunnel->gTP_TEID.buf, 4);

            // UE contextに格納
            ue_map->upf_n3_ip = upf_ip_be;
            ue_map->upf_n3_teid = ntohl(upf_dl_teid_be);
            ue_map->has_upf_n3_info = true;  // ★ フラグ立て

            printf("[INFO]     Stored UPF N3 info in UE context (ENB=%ld, UPF N3 TEID=0x%08x)\n",
                   ue_map->enb_ue_s1ap_id, ue_map->upf_n3_teid);
        }
    }
```

**pcap_4検証結果（Option B採用前）**:
- ❌ IE 74なし → このコードが実行されない
- ❌ `has_upf_n3_info` がfalseのまま

**Option B採用後の期待**:
- ✅ IE 74あり → このコード実行される
- ✅ `has_upf_n3_info = true`
- ✅ Phase 18.4でE-RAB構築可能

### 5.4 Phase 18.3: E-RAB情報追加判断（proc=14パス）

#### 実装箇所
`s1n2_converter.c` line 6745-6835 **(実装済み - 動作確認済み)**

#### 動作フロー
```c
// NGAP InitialContextSetup処理 (proc=14)
// S1AP ICS構築前の介入ポイント

printf("[INFO] [Phase 18.2] ★★★ NGAP InitialContextSetup detected (proc=14)\n");

// Phase 18.2: 介入判断
int phase18_success = 0;
ue_id_mapping_t *map2 = s1n2_context_find_recent_security(ctx);

// 条件1: UE context存在確認
if (!map2) {
    printf("[WARN] [Phase 18.2] No UE context found\n");
    goto use_legacy_ics_builder;
}

// 条件2: UPF情報有無確認
if (!map2->has_upf_n3_info) {
    printf("[WARN] [Phase 18.2] No UPF N3 info available (PSI=%u), using legacy ICS builder\n",
           map2->pdu_session_id);
    printf("[WARN] [Phase 18.2] This will likely result in ICS Failure from eNB\n");
    goto use_legacy_ics_builder;
}

// 条件3: NGAP ICS IE 74有無確認（冗長チェック）
if (check_ngap_ics_has_pdu_session(data, len)) {
    printf("[INFO] [Phase 18.2] NGAP ICS already has PDU Session IE\n");
    // Option B採用後はここを通る想定
}

// Phase 18.4: E-RAB追加実行
printf("[INFO] [Phase 18.2] ★★★ All conditions met - Adding E-RAB Setup info\n");
if (s1n2_add_erab_to_s1ap_ics(ctx, data, len, s1ap_ics_buf, &phase18_s1ap_len, map2) == 0) {
    phase18_success = 1;
    printf("[SUCCESS] [Phase 18.4] ★★★ E-RAB info added successfully (new len=%zu)\n",
           phase18_s1ap_len);
}

use_legacy_ics_builder:
    if (!phase18_success) {
        // フォールバック: レガシービルダー使用
        rc_ics = build_s1ap_initial_context_setup_request(...);
    } else {
        // Phase 18成功: 構築済みS1AP ICSを使用
        rc_ics = 0;
    }
```

**pcap_4検証結果**:
- ✅ Phase 18.2実行確認（proc=14で検出）
- ❌ 条件2で失敗（`has_upf_n3_info == false`）
- ✅ フォールバック動作確認（レガシービルダー使用）

**Option B採用後の期待**:
- ✅ 条件1: UE context存在 ✓
- ✅ 条件2: `has_upf_n3_info == true` ✓（Phase 18.2で設定）
- ✅ 条件3: IE 74あり ✓（AMF改造により保証）
- ✅ Phase 18.4実行成功 ✓

### 5.5 Phase 18.4: E-RAB Setup List構築

#### 実装状態
✅ **実装済み** (line 420-620)

#### 関数: `s1n2_add_erab_to_s1ap_ics()`
```c
/**
 * S1AP InitialContextSetupRequestにE-RAB Setup情報を追加
 */
static int s1n2_add_erab_to_s1ap_ics(
    s1n2_context_t *ctx,
    const uint8_t *ngap_data, size_t ngap_len,
    uint8_t *s1ap_data, size_t *s1ap_len,
    ue_id_mapping_t *ue_map)
{
    // 1. NGAP ICSデコード
    NGAP_NGAP_PDU_t *ngap_pdu = ...;

    // 2. 必要情報抽出 (AMF-UE-ID, RAN-UE-ID, NAS-PDU, SecurityKey等)

    // 3. S1AP ICS新規構築
    S1AP_S1AP_PDU_t *s1ap_pdu = calloc(...);
    S1AP_InitialContextSetupRequest_t *ics = ...;

    // 4. Mandatory IEs追加 (IE 0, 8, 66, 107, 108)

    // 5. ★ E-RAB Setup List (IE 24) 追加
    if (s1n2_build_erab_setup_list(ics, ue_map) != 0) {
        return -1;
    }

    // 6. S1AP PDUエンコード
    asn_enc_rval_t er = aper_encode_to_buffer(&asn_DEF_S1AP_S1AP_PDU, NULL,
                                               s1ap_pdu, s1ap_data, *s1ap_len);

    *s1ap_len = (er.encoded + 7) / 8;
    return 0;
}
```

#### 関数: `s1n2_build_erab_setup_list()`
```c
/**
 * E-RAB Setup List (IE 24) 構築
 */
static int s1n2_build_erab_setup_list(
    S1AP_InitialContextSetupRequest_t *ics,
    ue_id_mapping_t *ue_map)
{
    // E-RAB Setup Item作成
    S1AP_E_RABToBeSetupItemCtxtSUReq_t *erab_item = ...;

    // E-RAB ID
    erab_item->e_RAB_ID = ue_map->pdu_session_id;  // 5

    // QoS Parameters
    qos->qCI = convert_5qi_to_qci(ue_map->qfi);  // 9
    qos->allocationRetentionPriority.priorityLevel = 9;
    qos->allocationRetentionPriority.pre_emptionCapability = 0;
    qos->allocationRetentionPriority.pre_emptionVulnerability = 0;

    // Transport Layer Address (UPF N3 IP)
    uint32_t upf_ip_be = ue_map->upf_n3_ip;  // 172.24.0.13
    memcpy(erab_item->transportLayerAddress.buf, &upf_ip_be, 4);

    // GTP-TEID (UPF N3 TEID)
    uint32_t upf_teid_be = htonl(ue_map->upf_n3_teid);  // 実際のTEID
    memcpy(erab_item->gTP_TEID.buf, &upf_teid_be, 4);

    ASN_SEQUENCE_ADD(&erab_list->list, erab_item);
    ASN_SEQUENCE_ADD(&ics->protocolIEs.list, ie_erab);

    return 0;
}
```

**Option B採用後の期待**:
- ✅ `ue_map->upf_n3_ip` に実際のUPF IP格納済み
- ✅ `ue_map->upf_n3_teid` に実際のUPF TEID格納済み
- ✅ E-RAB Setup Listに正しい値が設定される
- ✅ eNBがInitialContextSetupResponseを返す

---

## 6. 実装スケジュール（Option B採用時 - 2段階修正）

### Week 1: AMF動作調査・修正（優先度: 最高）
- [x] pcap_4解析完了（問題特定）
- [x] AMFログ解析完了（根本原因特定: "Unknown message [103]"）
- [ ] AMFソースコード調査（修正箇所1: `gmm-sm.c`）
- [ ] AMFソースコード調査（修正箇所2: `ngap-build.c`）
- [ ] AMF修正1実装（UL NAS Transport受付）
- [ ] AMF修正2実装（4G UE時にもIE 74追加）
- [ ] AMF再ビルド・デプロイ

### Week 2: 動作確認・デバッグ（優先度: 高）
- [ ] pcap_5キャプチャ
- [ ] AMFログ確認（PDU Session処理成功、Session summary: total=1確認）
- [ ] Frame 530確認（IE 74存在確認）
- [ ] s1n2ログ確認（Phase 18.2でUPF情報抽出成功確認）
- [ ] Frame 532確認（S1AP ICS IE 24確認）
- [ ] Frame 536確認（eNB ICS Response Success確認）
- [ ] エラー時のデバッグ

### Week 3: 最終調整（優先度: 中）
- [ ] GTP-Uトンネル疎通確認（ping test）
- [ ] データ通信確認
- [ ] ドキュメント更新
- [ ] 本番環境デプロイ

---

## 7. 検証計画（Option B採用後）

### 7.1 期待される動作

#### pcap_5での確認項目

| Frame | メッセージ | 確認内容 | 期待値 |
|-------|----------|---------|--------|
| ~530 | NGAP ICS | IE 74有無 | ✅ あり |
| ~530 | NGAP ICS | PDU Session ID | 5 |
| ~530 | NGAP ICS | UPF IP | 172.24.0.13 |
| ~530 | NGAP ICS | UPF TEID | 0x12345678 (例) |
| ~532 | S1AP ICS | IE 24有無 | ✅ あり |
| ~532 | S1AP ICS | E-RAB ID | 5 |
| ~532 | S1AP ICS | QCI | 9 |
| ~532 | S1AP ICS | TransportLayerAddress | 172.24.0.13 ✅ |
| ~532 | S1AP ICS | GTP-TEID | 0x12345678 ✅ |
| ~536 | S1AP ICS Response | Cause | **Success** ✅ |

#### ログ確認

**s1n2ログ（期待）**:
```
[INFO] [Phase 18.1] ★★★ Requesting PDU Session to obtain UPF info
[SUCCESS] [Phase 18.1] ★★★ PDU Session Request sent to AMF (70 bytes)
[DEBUG]     Decoded PDUSessionResourceSetupRequestTransfer successfully
[INFO]     UPF N3 Downlink Tunnel: IP=172.24.0.13, TEID=0x12345678
[INFO]     Stored UPF N3 info in UE context (ENB=53, UPF N3 TEID=0x12345678) ✅
[INFO] [Phase 18.2] ★★★ NGAP InitialContextSetup detected (proc=14)
[INFO] [Phase 18.2] ★★★ All conditions met - Adding E-RAB Setup info ✅
[SUCCESS] [Phase 18.4] ★★★ E-RAB info added successfully (new len=xxx) ✅
[SUCCESS] [Phase 18] ★★★ Sent S1AP ICS with E-RAB to eNB
```

**eNBログ（期待）**:
```
Received InitialContextSetupRequest
E-RAB ID=5 QCI=9 established
S1-U tunnel: UPF=172.24.0.13:0x12345678 ✅
Sending InitialContextSetupResponse ✅
```

### 7.2 Wiresharkフィルタ

```
# NGAP ICS確認
ngap.procedureCode == 14

# IE 74確認
ngap.PDUSessionResourceSetupListCxtReq_element

# UPF情報確認
ngap.UL_NGU_UP_TNLInformation_element

# S1AP ICS確認
s1ap.procedureCode == 9

# E-RAB確認
s1ap.E_RABToBeSetupListCtxtSUReq_element
s1ap.transportLayerAddress
s1ap.gTP_TEID
```

---

## 8. リスク管理

### 8.1 リスク1: AMF改造が複雑
**症状**: IE 74追加箇所が見つからない、またはビルドエラー

**対策**:
1. Open5GS公式ドキュメント確認
2. GitHub issuesで類似事例検索
3. Option Aへの切り替え検討（NAS復号化）

### 8.2 リスク2: IE 74にUPF情報が含まれない
**症状**: IE 74はあるがUL-NGU-UP-TNLInformationが空

**対策**:
1. AMF-SMF間N11通信確認
2. SMFログでN4 Session確立確認
3. UPFログでTEID割り当て確認

### 8.3 リスク3: eNBがE-RABパラメータを拒否
**症状**: InitialContextSetupFailure (Cause=radioNetwork)

**対策**:
1. QCI値確認（9が正しいか）
2. ARP値確認（9/0/0が正しいか）
3. UPF IP到達性確認（`docker exec s1n2 ping 172.24.0.13`）
4. 実機成功pcapとの比較

---

## 9. 代替案（Option A）の概要

### 9.1 NAS復号化アプローチ

Option Bが失敗した場合の代替案として残しておく。

#### 実装箇所
`s1n2_converter.c` 新規関数追加

#### 必要な実装
1. **NAS復号化関数**:
   ```c
   int decrypt_5g_nas_pdu(
       const uint8_t *encrypted_pdu, size_t encrypted_len,
       const uint8_t *k_nas_enc,  // 暗号化キー
       uint32_t nas_count,        // COUNT値
       uint8_t *decrypted_pdu, size_t *decrypted_len);
   ```

2. **5GSM PDU Session Acceptパーサー**:
   ```c
   int parse_pdu_session_accept(
       const uint8_t *nas_pdu, size_t nas_len,
       uint32_t *upf_ip, uint32_t *upf_teid, uint8_t *qfi);
   ```

3. **DownlinkNASTransport処理への統合**:
   ```c
   // Frame 624受信時
   if (nas_security_header == 0x02) {  // 暗号化+完全性保護
       decrypt_5g_nas_pdu(...);
       if (message_type == 0xC2) {  // PDU Session Accept
           parse_pdu_session_accept(...);
           ue_map->upf_n3_ip = upf_ip;
           ue_map->upf_n3_teid = upf_teid;
           ue_map->has_upf_n3_info = true;
       }
   }
   ```

#### 実装コスト
**推定**: 2〜4週間

---

## 10. まとめ

### 現状
- ✅ Phase 18.2/18.4実装完了（コードパス修正、E-RAB構築）
- ✅ pcap_4で動作確認済み（Phase 18.2実行、フォールバック動作確認）
- ❌ UPF情報取得失敗（4G UEシナリオでIE 74なし）

### 推奨アクション
**Option B: AMF改造** を優先実施
- 実装コスト: 3〜5日
- 成功確率: 高
- 既存コード活用: 可能

### 成功基準
1. ✅ NGAP ICSにIE 74が含まれる
2. ✅ s1n2がIE 74からUPF情報抽出成功
3. ✅ `has_upf_n3_info = true` 設定成功
4. ✅ Phase 18.4でE-RAB構築成功
5. ✅ eNBがInitialContextSetupResponse (Success) 返却
6. ✅ GTP-Uトンネル確立、データ通信成功

---

## 11. 参考資料

### 3GPP仕様書
- **TS 36.413**: S1AP protocol (InitialContextSetupRequest, E-RAB Setup)
- **TS 38.413**: NGAP protocol (InitialContextSetupRequest, PDU Session Setup)
- **TS 23.501**: 5G System Architecture (QoS, 5QI definitions)
- **TS 23.502**: Procedures for 5G System (PDU Session establishment)
- **TS 33.501**: Security architecture for 5GS (NAS encryption)

### pcapファイル
- `20251111_4.pcap`: Phase 18検証（IE 74なし、UPF情報取得失敗）
- `real_eNB_Attach.pcap`: 実機成功事例（E-RABパラメータ参照用）
- `4G_Attach_Successful.pcap`: 4G正常Attach手順
- `5G_Registration_Successful.pcap`: 5G正常Registration手順

### ソースコード
- `sXGP-5G/src/s1n2_converter.c`: s1n2コンバータ本体
- `sXGP-5G/include/s1n2_converter.h`: UE context定義
- `sources/open5gs/src/amf/nas-path.c`: AMF ICS送信ロジック
- `sources/open5gs/src/amf/ngap-build.c`: NGAP ICS構築（★要修正箇所）
- `sources/open5gs/src/amf/context.h`: AMF session構造体

---

**最終更新**: 2025年11月11日（全面改訂 + 根本原因特定）
**ステータス**: 設計完了、Option B実装準備完了、AMFログ解析完了
**根本原因**: AMFが`gmm_state_security_mode()`中にUL NAS Transport (0x67)を「Unknown message [103]」で拒否
**次のステップ**: AMFソースコード修正（2箇所: タイミング問題 + IE 74追加）
