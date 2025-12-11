# InitialContextSetup PDU Session欠落問題 - 修復試行記録

## 問題の概要

### 根本原因
4G eNB（sXGP）から接続するUEが、5G Registration完了後にInitialContextSetupを受信するが、**E-RAB-ToBeSetupListCtxtSUReq (IE 24)が欠落**しているため、データ通信ができない。

### 期待される動作 vs 実際の動作

| 項目 | 期待される動作 (4G正常時) | 実際の動作 (4G-5G変換時) |
|------|--------------------------|-------------------------|
| Registration | Attach Request → Attach Accept | Registration Request → Registration Accept |
| Bearer確立 | ICS に E-RAB Setup含む | ICS に E-RAB Setup**なし** |
| UE状態 | RRC Connected + Bearer確立 | RRC Connected だが Bearer未確立 |
| データ通信 | ✅ 可能 | ❌ 不可能 (Bearer無し) |

### 技術的詳細

**5G側 (AMF)**:
- InitialContextSetupRequestに`PDUSessionResourceSetupListCxtReq` (IE 74)が含まれない
- 理由: AMFがPDU Session Establishment Requestを受信していない

**4G側 (eNB)**:
- InitialContextSetupRequestに`E-RAB-ToBeSetupListCtxtSUReq` (IE 24)が必要
- s1n2コンバータがAMFからのICSをそのまま変換 → IE 24が無い

---

## 前提知識: 4G-5G変換における基礎実装

### 実装済み基盤機能（2025年9月-10月）

これらの機能は既に実装・動作確認済みで、本問題（ICS PDU Session欠落）の前提となる。

#### 1. NAS変換機能（Phase 1-10）
**実施時期**: 2025年9月22-24日

**実装内容**:
- 4G NAS → 5G NAS変換エンジン（`s1n2_nas.c`）
- Authentication Response (0x54 → 0x57) 変換
- Security Mode Complete (0x5E → 0x5E) 変換
- **ESM → 5GMM変換**: ESM (PD=0x6) → 5GMM Registration Request (0x7E 0x00 0x41)
  - 初期実装: ESM → 5GSM (0x2E) で失敗
  - 修正実装: ESM → 5GMM (0x7E) で成功
- Attach Complete (0x43) → Registration Complete (0x43) 変換

**重要な発見**:
```
修正前: ESM(0x6) → 5GSM(0x2E) → AMF「Invalid extended_protocol_discriminator [0]」
修正後: ESM(0x6) → 5GMM(0x7E) → AMF 5GMMとして正常処理 ✅
```

**ログ証跡**（2025-09-24）:
```
[INFO] Detected 4G ESM message (PD=0x6)
[INFO] Converting 4G ESM message (PD=0x6) to 5G Registration Request
[INFO] 5G ESM→5GMM Registration Request created (len=15): 7E 00 41...
```

#### 2. NAS暗号化・整合性保護（Phase 5-10）
**実施時期**: 2025年10月9-11日

**実装内容**:
- 5G NAS Integrity Protection (EIA2 - AES-CMAC)
- Security Context管理（K_NASint, K_NASenc）
- COUNT管理（UL/DL別管理）
- 下りNAS暗号化（Attach Accept等）

**技術的詳細**:
```c
// 実装場所: s1n2_security.c
int compute_5g_nas_mac(
    const uint8_t *nas_msg, size_t nas_len,
    uint32_t count, uint8_t bearer, uint8_t direction,
    const uint8_t k_nas_int[16], uint8_t mac_out[4]);
```

**重要な知見**:
- Security Mode Complete **後**の下りNASは最低限Integrity保護が必要
- ICSのE-RABパラメータ不正 → eNBがNASをRRCに内包しない（データが届かない）

#### 3. Masked-IMEISV問題の解決（Phase 10-11）
**実施時期**: 2025年11月5日

**問題**: 全バイト0xFFのMasked-IMEISVをeNBが拒否
- **pcap証跡**: `20251105_7.pcap`
- **eNB Failure Cause**: `radioNetwork=26 (failure-in-radio-interface-procedure)`

**解決策**:
```c
// 修正前（全マスク）:
uint8_t masked_imeisv[8] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

// 修正後（先頭5バイト実値、後半3バイトマスク）:
uint8_t masked_imeisv[8] = {0x35, 0x54, 0x96, 0x49, 0x95, 0xFF, 0xFF, 0x41};
```

**成功事例との比較**:
| 項目 | 成功 (real_eNB_Attach.pcap) | 失敗 (20251105_7.pcap) |
|------|------------------------------|------------------------|
| Masked-IMEISV | `3554964995ffff41` | `ffffffffffffffff` ❌ |
| ICS Result | Response受信 | Failure (Cause=26) |

#### 4. ICS IE順序問題の解決（Phase 11）
**実施時期**: 2025年11月5日

**問題**: eNBがIE順序に敏感（Optional IEが先頭にあると拒否）

**修正内容**:
- Mandatory IE: 先頭配置（0, 8, 66, 24, 107, 73）
- Optional IE: 末尾配置（192, 269）
- **期待IE順序**: `0, 8, 66, 24, 107, 73, 192, 269`

**検証結果**: ✅ IE順序は正しい（pcap_50で確認）
- 成功事例と一致
- eNBも受理（Masked-IMEISV問題解決後）

#### 5. UEコンテキスト管理（Phase 8-11）
**実施時期**: 2025年10月-11月

**実装内容**:
- S1AP ↔ NGAP ID マッピングテーブル
- UE状態管理（ENB-UE-S1AP-ID ↔ RAN-UE-NGAP-ID ↔ AMF-UE-NGAP-ID）
- Security Context（K_NASint, K_NASenc, UL/DL COUNT）
- Location Info（PLMN ID, Cell ID, TAC）

**重要な問題と対策**:
- **ICS Failure後のコンテキスト残留** → `unknown-enb-ue-s1ap-id` (Cause=14)
- **対策**: ICS Failure/UEContextRelease受信時に強制削除

---

## 解決アプローチの試行履歴

### Phase 1-16: 基礎調査とコンセプト検証

#### Phase 1-10: 問題の特定と初期実装
- **実施内容**: pcap解析、AMF/s1n2ログ解析、UE状態追跡
- **判明事項**:
  - AMFがPDU Session Establishment Requestを受信していない
  - UEは4G端末なので5G NASのPDU Session確立手順を知らない
  - s1n2がプロキシとしてPDU Session Requestを送信する必要がある

#### Phase 11-16: PDU Session構築ロジックの実装
- **実施内容**:
  - `build_pdu_session_establishment_request()` 実装
  - `build_gmm_ul_nas_transport_with_n1_sm()` 実装（5GMM UL NAS Transport wrapper）
  - Registration Complete受信時にPDU Session Requestを自動送信
- **結果**: ✅ PDU Session Request送信成功
- **新たな問題**: タイミング問題 - AMFが既にICSを送信済み---

### Phase 17: タイミング最適化の試行（Option 1アプローチ）

**コンセプト**: s1n2がAMFにPDU Session Establishment Requestを送信し、AMFに5G正規手順でPDU Session確立させる

#### Phase 17.1: Registration Complete後の送信
- **実施時期**: 2025年11月初旬
- **実装内容**: Registration Complete (0x43) 受信直後にPDU Session Request送信
- **タイミング**:
  ```
  t=0ms:    UE → s1n2 → AMF: Registration Complete (0x43)
  t=1ms:    s1n2 → AMF: PDU Session Est Req (0xC1)
  t=15ms:   AMF → s1n2: InitialContextSetupRequest
  ```
- **結果**: ❌ 失敗
- **問題**: AMFはReg Complete受信後、即座にICS送信（約14-15ms）。PDU Session処理が間に合わない

#### Phase 17.2: Security Mode Complete直後の送信（試行1）
- **実施時期**: 2025年11月5-6日
- **実装内容**: Security Mode Complete (0x5E) 送信直後にPDU Session Request送信
- **根拠**: SMC送信からICS受信まで約14ms → この間にPDU Session処理を完了させる
- **タイミング**:
  ```
  t=0ms:    s1n2 → AMF: Security Mode Complete (0x5E)
  t=0.5ms:  s1n2 → AMF: PDU Session Est Req (0xC1)
  t=14ms:   AMF → s1n2: InitialContextSetupRequest
  ```
- **pcap結果**: pcap_45, pcap_46で確認
- **結果**: ❌ 失敗
- **問題**: AMFはSMC受信後すぐにRegistration Acceptを生成開始。PDU Session処理が間に合わない

#### Phase 17.3: Security Mode Complete **前**の送信（試行2）
- **実施時期**: 2025年11月7-9日
- **実装内容**:
  - SMC受信検知 → SMC送信**前**にPDU Session Request送信
  - 狙い: AMFにPDU Sessionを先に処理させる
- **コード位置**: `s1n2_converter.c` lines 4914-4975
- **タイミング**:
  ```
  pcap_48 (2025-11-09取得):
  t=0ms:     s1n2 → AMF: PDU Session Est Req (0xC1)
  t=+201ms:  s1n2 → AMF: Security Mode Complete (0x5E)
  t=+219ms:  AMF → s1n2: InitialContextSetupRequest
  ```
- **結果**: ❌ 失敗
- **致命的な問題発見**:
  - AMFログ: `Unknown message[103] error`
  - **AMF状態遷移の制約**を発見

#### **重要な発見: AMF GMM State Machine の制約**

**AMFログ解析結果** (pcap_48対応ログ、2025-11-09):
```
20:32:28.709: gmm_state_security_mode(): ENTRY
20:32:28.709: gmm_state_security_mode(): AMF_EVENT_5GMM_MESSAGE (PDU Session受信)
              → ERROR: Unknown message[103]
20:32:28.910: gmm_state_security_mode(): AMF_EVENT_5GMM_MESSAGE (SMC受信)
20:32:28.911: gmm_state_security_mode(): EXIT
20:32:28.911: gmm_state_initial_context_setup(): ENTRY
20:32:28.927: Registration Accept sent (with ICS)
```

**判明した仕様制約**:
- AMF GMMステートマシンは状態ごとに受付可能なNASメッセージが決まっている
- **Security Mode状態**: Security Mode Complete (0x5E) のみ受付
- **Security Mode状態**: UL NAS Transport (0x67, PDU Session含む) → **"Unknown message" エラー**
- **Initial Context Setup状態**: UL NAS Transport (0x67) 受付可能
- 状態遷移タイミング: SMC受信から約1ms後

#### Phase 17.4: Security Mode Complete **後**の送信（最終試行）
- **実施時期**: 2025年11月10日
- **実装内容**:
  - SMC送信 → 2ms待機 (`usleep(2000)`) → PDU Session Request送信
  - 狙い: AMFの状態遷移（Security Mode → Initial Context Setup）を待つ
- **コード位置**: `s1n2_converter.c` lines 4998-5100
- **期待タイミング**:
  ```
  理論値:
  t=0ms:    s1n2 → AMF: Security Mode Complete (0x5E)
  t=1ms:    AMF状態遷移: Security Mode → Initial Context Setup
  t=2ms:    usleep(2000) 完了
  t=2ms:    s1n2 → AMF: PDU Session Est Req (0xC1) 送信開始
  t=3ms:    AMF: PDU Session Est Req 受信・処理
  t=16ms:   AMF → s1n2: InitialContextSetupRequest (IE 74含む)
  ```
- **実測タイミング** (pcap_50, 2025-11-10取得):
  ```
  t=96.198868s: eNB → s1n2: SMC (S1AP UplinkNASTransport)
  t=96.199096s: s1n2 → AMF: SMC (NGAP UplinkNASTransport) [+0.23ms]
                ↓ usleep(2000) 実行 (2ms)
                ↓ NAS暗号化処理 (約11ms)
  t=96.212967s: AMF → s1n2: InitialContextSetupRequest [+13.87ms] ← ICS先に到着
  t=96.212994s: s1n2 → AMF: PDU Session Est Req [+13.90ms] ← 0.03ms遅れ
  ```
- **結果**: ❌ 失敗
- **決定的な問題**:
  - `usleep(2000)`は正常動作（2ms待機）
  - しかし、その後のNAS暗号化処理（MAC計算、NGAP構築）に**約11ms**かかる
  - 合計13.9ms後の送信 → AMFは既にICS送信済み（13.87ms）

**s1n2処理内訳** (ログ解析):
```
96.199096s: SMC送信完了
            ↓
            usleep(2000)              → 2ms
            ↓
            5GSM PDU構築              → 0.5ms
            5GMM UL NAS Transport構築  → 0.5ms
            COUNT計算                 → 0.1ms
            K_NASint_5G取得           → 0.2ms
            EIA2 MAC計算              → 8ms (CPUバウンド)
            NGAP構築                  → 2ms
            ↓
96.212994s: PDU Session送信
```

**Option 1アプローチの本質的限界**:
1. ✅ AMF状態遷移タイミングは理解できた（1ms）
2. ✅ usleepは意図通り動作
3. ❌ s1n2内部の暗号化処理時間（8-11ms）が予測困難
4. ❌ AMFのICS送信タイミング（13-18ms）との競合
5. ❌ 処理時間は負荷依存で制御不可能

### Option 1 総括

**試行回数**: Phase 17.1 - 17.4 (4回の大規模試行)
**判明した技術的制約**:
- AMF GMM State Machineの状態依存メッセージ受付制御
- NAS暗号化処理のオーバーヘッド（8-11ms）
- AMFの5G SBI (HTTP/2) アーキテクチャ（SMF非同期通信）
- タイミング制御の不確実性（負荷・CPU依存）

**結論**: ❌ **Option 1は実装不可能**
- 理由1: 処理時間の変動が大きすぎる（暗号化処理）
- 理由2: AMFの内部タイミング（ICS送信判断）に依存
- 理由3: マルチスレッド化しても根本解決にならない

---

## 仕様調査: 代替案の検討

### 検討案1: SMCと同時にPDU Session送信
**提案**: Security Mode Complete送信時に、同一パケットでPDU Session Establishment Requestを送信

**プロトコル構造**:
```
NGAP UplinkNASTransport
└─ NAS-PDU
   ├─ Security Mode Complete (5GMM, 0x5E)
   └─ UL NAS Transport (5GMM, 0x67) + PDU Session (5GSM, 0xC1)
```

**仕様調査結果**: ❌ **不可能**
- **3GPP TS 24.501**: 1つのNAS-PDUには1つの5GMMメッセージのみ
- Security Mode Complete は 5GMM メッセージ
- UL NAS Transport も 5GMM メッセージ
- → 2つの5GMMメッセージを同一NAS-PDUに含められない

**Piggybackingの可能性**:
- 一部の5GMMメッセージはNASコンテナIEでpiggyback可能
- 例: Registration Request + PDU Session Est Req
- しかし、**Security Mode CompleteにはNASコンテナIEが存在しない** (TS 24.501 Section 8.2.26)

### 検討案2: ICS Response送信時にPDU Session送信
**提案**: InitialContextSetupResponse送信時に、PDU Session Establishment Requestを同時送信

**プロトコル構造案A** (連続送信):
```
Message 1: NGAP InitialContextSetupResponse
Message 2: NGAP UplinkNASTransport (PDU Session)
```
**結果**: ⚠️ 技術的に可能だが無意味
- ICS Response送信時点 = Registration手続き完了後
- AMFは既に次の処理に移行済み
- タイミングが遅すぎて効果なし

**プロトコル構造案B** (同一メッセージ):
```
NGAP InitialContextSetupResponse
└─ NAS-PDU (optional?)
   └─ UL NAS Transport + PDU Session
```
**仕様調査結果**: ❌ **不可能**
- **3GPP TS 38.413 (NGAP)**: InitialContextSetupResponse の IE一覧
  - AMF-UE-NGAP-ID (M)
  - RAN-UE-NGAP-ID (M)
  - PDU Session Resource Setup Response List (O)
  - PDU Session Resource Failed to Setup List (O)
  - Criticality Diagnostics (O)
- **NAS-PDU IEは存在しない**

---

## Option 2: ICS修正アプローチ（推奨解決策）

### コンセプト
s1n2がAMFから受信したInitialContextSetupRequestを修正し、eNBへ送信する際に**E-RAB Setup情報を追加**する。

### メッセージフロー
```
通常の5G UE:
AMF → AMF: PDU Session確立判断
AMF → gNB: InitialContextSetupRequest (IE 74: PDUSessionResourceSetupListCxtReq含む)

4G UE (s1n2変換):
AMF → s1n2: InitialContextSetupRequest (IE 74なし)
s1n2内部: 判断「このUEはPDU Sessionが必要」
s1n2内部: E-RAB Setup情報を生成
  - PDU Session ID
  - QoS parameters (QCI)
  - UPF GTP-U tunnel情報 (IP, TEID)
s1n2 → eNB: InitialContextSetupRequest (IE 24: E-RAB-ToBeSetupListCtxtSUReq含む)
```

### 実装方針

#### 1. ICS受信時の判断ロジック
```c
// s1n2_converter.c: s1n2_handle_ngap_message()内
if (ngap_pdu->present == NGAP_NGAP_PDU_PR_initiatingMessage &&
    ngap_pdu->choice.initiatingMessage->procedureCode ==
    NGAP_ProcedureCode_id_InitialContextSetup) {

    // IE 74 (PDUSessionResourceSetupListCxtReq) の有無確認
    bool has_pdu_session_ie = check_ie_74_presence(ngap_pdu);

    // UE contextから判断
    ue_id_mapping_t *ue_map = get_ue_mapping(amf_ue_ngap_id, ran_ue_ngap_id);

    if (!has_pdu_session_ie && ue_map->requires_bearer) {
        // Option 2実行: E-RAB情報を生成
        add_erab_setup_to_ics(ngap_pdu, ue_map);
    }

    // 4G S1AP ICSに変換
    convert_ngap_to_s1ap_ics(ngap_pdu, s1ap_pdu);
}
```

#### 2. E-RAB情報の生成
```c
// 必要な情報:
// - E-RAB ID (PDU Session IDから導出)
// - QCI (5QIから変換: 5QI 9 → QCI 9)
// - GTP-U Tunnel Endpoint:
//   - Transport Layer Address (UPF IP)
//   - GTP-TEID
// - NAS-PDU (optional: PDU Session Accept相当)

typedef struct {
    uint8_t erab_id;           // E-RAB ID (1-15)
    uint8_t qci;               // QCI (1-9)
    uint32_t upf_ip;           // UPF IPv4 address (network byte order)
    uint32_t upf_teid;         // GTP-U TEID (network byte order)
    uint8_t *nas_pdu;          // NAS-PDU (optional)
    size_t nas_pdu_len;
} erab_setup_info_t;
```

#### 3. UPF情報の取得方法

**課題**: AMFからのICSにPDU Session情報がない場合、UPF IPとTEIDをどう取得するか？

**解決策A: SMF/UPF情報の事前取得** (推奨)
```c
// Registration Complete送信時に、SMFへPDU Session作成リクエスト
// (Option 1で実装済みのロジックを流用)
//
// SMFレスポンス (HTTP 201 Created) から取得:
// - n2SmInfo: PDUSessionResourceSetupRequestTransfer
//   - UL-NGU-UP-TNLInformation: UPF IP + TEID
//   - PDUSessionType, QosFlowSetupRequestList
//
// この情報をUE contextに保存
ue_map->upf_ip = extract_upf_ip_from_smf_response();
ue_map->upf_teid = extract_upf_teid_from_smf_response();
ue_map->qfi = extract_qfi_from_smf_response();
```

**解決策B: デフォルト値の使用** (フォールバック)
```c
// UPF情報が取得できない場合のデフォルト
#define DEFAULT_UPF_IP   "172.24.0.13"  // docker compose UPF IP
#define DEFAULT_QCI      9               // Best effort
// TEIDは動的生成（UE contextごとにユニーク値）
```

#### 4. 既存関数の活用
```c
// sXGP-5G/src/s1n2_converter.c 既存実装:

// NGAP PDUSessionResourceSetupRequestを構築 (lines 3490-3650)
static int build_ngap_pdu_session_setup_request(
    uint8_t *buffer, size_t *buffer_len,
    long amf_ue_ngap_id, long ran_ue_ngap_id,
    uint8_t pdu_session_id, uint8_t qci,
    uint32_t upf_ipv4_be, uint32_t upf_teid_be);

// S1AP E-RABSetupRequest構築も同様のロジックで実装可能
static int build_s1ap_erab_setup_in_ics(
    S1AP_InitialContextSetupRequest_t *ics_msg,
    erab_setup_info_t *erab_info);
```

### Option 2の利点
1. ✅ **タイミング問題なし**: eNB側で正しい順序で処理される
2. ✅ **3GPP仕様準拠**: S1AP ICSにE-RAB Setupは標準的に含まれる
3. ✅ **確実性**: AMFの内部タイミングに依存しない
4. ✅ **既存コード活用**: Phase 17で実装したPDU Session関連関数が流用可能

### Option 2の課題と対策
**課題1**: UPF情報の取得
- **対策**: Option 1で実装したSMF通信ロジックを流用（別タイミングで実行）

**課題2**: 5G-4G QoS変換
- **対策**: 5QI → QCI マッピングテーブル実装（標準的な対応表あり）

**課題3**: デバッグの複雑さ
- **対策**: 詳細ログ追加、pcap解析による検証

---

## 開発環境のトラブルシューティング

### 問題A: UE-eNB間接続失敗とInitialUEMessage未生成

**症状** (2025年9月22-23日に頻発):
- UE: "Attaching UE..." で停止
- eNB: RACHメッセージが生成されない
- s1n2: InitialUEMessageを受信しない
- AMF: InitialUEMessageが届かない

**根本原因**:
1. **ZMQ Physical Layer同期失敗**: UE-eNB間のZMQ接続で周波数同期が確立されない
2. **コンテナ起動順序の問題**: eNBが完全起動前にUEが接続を試行
3. **S1AP接続タイミング**: eNB-s1n2間のSCTP接続が未確立

**確実な解決手順**:
```bash
# Step 1: 完全環境リセット
cd /home/taihei/docker_open5gs_sXGP-5G/sXGP-5G
docker compose --env-file .env_s1n2 -f docker-compose.s1n2.yml down

# Step 2: s1n2を優先起動（N2接続確立を待つ）
docker compose --env-file .env_s1n2 -f docker-compose.s1n2.yml up -d s1n2
sleep 5
docker logs s1n2 --tail 10 | grep "N2 connected"

# Step 3: eNB起動とS1Setup確認
docker compose --env-file .env_s1n2 -f docker-compose.s1n2.yml up -d srsenb_zmq
sleep 10
docker logs s1n2 --tail 20 | grep "S1SetupResponse sent"

# Step 4: UE起動（eNB完全起動後）
docker compose --env-file .env_s1n2 -f docker-compose.s1n2.yml up -d srsue_zmq
sleep 15
docker logs srsue_zmq --tail 20 | grep "RRC Connected"
```

**成功指標**:
- ZMQ周波数設定: `Setting frequency: DL=2660.0 Mhz, UL=2540.0 MHz`
- RACH成功: `RACH: tti=xxxx, preamble=xx, temp_crnti=0xxx`
- InitialUEMessage受信: `[INFO] InitialUEMessage detected (88 bytes)`

### 問題B: s1n2コンバータのビルド・デプロイ失敗

**症状**:
- `make`コマンドでビルドが途中で停止
- ASN.1ライブラリの依存関係エラー
- コンテナ起動時のライブラリエラー: `libogsasn1c-common.so.2: cannot open shared object file`

**根本原因** (2025年9月22日に解決):
1. **ASN.1ヘッダーパス問題**: 複雑なASN.1ライブラリ構造による参照エラー
2. **ライブラリ依存関係**: 動的ライブラリの参照失敗
3. **Makefileのwildcardパターン不完全**: `NGAP_*.c`では`NGAP_ProtocolIE-Field.c`が除外される

**確実な解決策**:
```makefile
# Makefile修正（正しいwildcardパターン）
NGAP_SRCS := $(wildcard open5gs_lib/asn1c/ngap/*.c)  # すべての.cファイルを含む
S1AP_SRCS := $(wildcard open5gs_lib/asn1c/s1ap/*.c)
```

**ビルド確認**:
```bash
# ビルドディレクトリのクリーンアップ
rm -rf build/*

# ビルド実行
make clean && make

# バイナリサイズ確認（正常: 19.3MB程度）
ls -lh build/s1n2-converter
```

**デプロイ確認**:
```bash
# 新イメージでコンテナ再作成
docker compose --env-file .env_s1n2 -f docker-compose.s1n2.yml build s1n2 --no-cache
docker compose --env-file .env_s1n2 -f docker-compose.s1n2.yml up -d s1n2 --force-recreate

# ライブラリ依存関係確認
docker exec s1n2 ldd /usr/local/bin/s1n2-converter | grep -E "(ogsasn1c|ogscore)"
```

### 問題C: eNB再起動後のS1接続不能

**症状** (2025年10月29日):
- eNB再起動後、以前はつながっていたS1が確立しない
- UEもInitialUEMessage以降進まず
- s1n2ログ: `deferring S1SetupResponse`（書込不可のため応答保留）
- SCTP状態: `ST=10 (LISTEN)` かつ `RX_QUEUE=300`

**根本原因**:
- s1n2のS1Cソケットが一時的に書込不可（pollで未準備）
- eNB側はCOOKIE ECHOを再送し続ける

**復旧手順**:
```bash
# s1n2コンテナ再起動
docker compose --env-file .env_s1n2 -f docker-compose.s1n2.yml restart s1n2

# 15秒待機後、SCTP接続確認
sleep 15
docker exec s1n2 cat /proc/net/sctp/assocs | grep "172.24.0.111"
# 期待: ST=3 (ESTABLISHED)
```

**予防策**:
- ヘルスチェックで「S1(36412↔36412)とN2(→38412)のST=3」を監視
- s1n2コード側でPOLLOUT待ちのリトライ実装（2025年10月29日実装済み）

### 問題D: InitialContextSetup送信タイミング問題

**症状** (2025年11月8日 - pcap 20251108_10.pcap):
- Registration Accept は送信される
- PDU Session Establishment Accept も送信される（約10秒遅延）
- しかし **InitialContextSetup (procedureCode 14) が一切送信されない**

**根本原因**:
- AMFのICS送信条件: `!initial_context_setup_request_sent && (ue_context_requested || transfer_needed)`
- 条件2a (`ue_context_requested`): InitialUEMessageに`UEContextRequest` IE欠落 → **false**
- 条件2b (`transfer_needed`): SMFからPDU_RES_SETUP_REQのN2 Transferが格納されていない → **false**
- 結果: `(false || false) == false` → ICS送信されず

**ソースコード解析結果** (Open5GS AMF):
```c
// sources/open5gs/src/amf/nas-path.c: nas_5gs_send_registration_accept()
if (ran_ue->initial_context_setup_request_sent == false &&
    (ran_ue->ue_context_requested == true || transfer_needed == true))
{
    // Send InitialContextSetupRequest
    ngap_ue_build_initial_context_setup_request(...);
}

// transfer_neededの判定
bool transfer_needed = false;
ogs_list_for_each(&amf_ue->sess_list, sess) {
    if (sess->transfer.pdu_session_resource_setup_request) {
        transfer_needed = true;
        break;
    }
}
```

**AMFログ分析** (2025-11-09):
- 18:55:33.304 InitialUEMessage受信（UEContextRequest IEなし）
- 18:55:33.463 Registration Accept生成
- 18:55:33.464 UL NAS Transport（PDU Session Request）受信・SMFへ転送
- 18:55:43.675 PDU Session Accept送信（10秒遅延）
- **重要**: `InitialContextSetupRequest(Session)` ログが一切出力されていない

**対策**:
1. s1n2でInitialUEMessageに`UEContextRequest` IEを追加（`ue_context_requested = true`化）
2. AMF側にて、SMFのN2 Transfer格納後にもICS判定を再評価（未実装の改修案）

**この問題がOption 1の限界を示唆**:
- タイミングに依存する解決策では、SMFの非同期レスポンスを制御できない
- **Option 2（s1n2がICSを修正）が根本的解決策**

---

## 学習事項と今後の注意点

### 避けるべき轍

#### 1. タイミング制御への過信
❌ **誤った考え**: 「usleepで適切に待機すれば間に合う」
✅ **正しい理解**:
- 暗号化処理などCPUバウンド処理の時間は予測不可能
- 相手（AMF）の内部タイミングは制御不可能
- タイミング依存の解決策は避けるべき

#### 2. プロトコル仕様の軽視
❌ **誤った考え**: 「複数のメッセージを1つにまとめれば効率的」
✅ **正しい理解**:
- 3GPP仕様は厳密に定義されている
- IEの有無、メッセージ構造は仕様書で確認必須
- "できそう"と"仕様で許可"は別物

#### 3. ステートマシンの軽視
❌ **誤った考え**: 「AMFはいつでもどのメッセージでも受け付ける」
✅ **正しい理解**:
- AMF/MMEはステートマシンで動作
- 状態ごとに受付可能なメッセージが異なる
- 状態遷移のタイミングを把握することが重要

### 効果的だったデバッグ手法

#### 1. pcap + ログの組み合わせ分析
```bash
# pcapでパケットタイミングを精密測定
tshark -r pcap.pcap -T fields -e frame.number -e frame.time_relative \
  -e ngap.procedureCode -e nas_5gs.mm.message_type

# AMFログで内部状態を確認
docker logs amf | grep "gmm_state"

# 相関分析: pcapの相対時刻 → Dockerログの絶対時刻に変換
```

#### 2. 段階的な実装とテスト
- ❌ 一度に複数の変更を加える
- ✅ 1つの変更 → pcapキャプチャ → ログ分析 → 次の変更

#### 3. カスタムログの活用
```c
// AMF側にカスタムログ追加 (sources/open5gs/src/amf/...)
ogs_warn("[%s] ★★★ PDU Session Establishment Request received", amf_ue->supi);
ogs_warn("[%s] ★ ICS decision: has_pdu_session=%s",
         amf_ue->supi, has_pdu ? "TRUE" : "FALSE");
```
→ `docker logs amf | grep "★"` で重要イベントを追跡

---

## 次のステップ: Option 2実装計画

### Phase 18: Option 2実装

#### Step 1: ICS受信時の判断ロジック実装
- [ ] NGAP InitialContextSetupRequest受信ハンドラ特定
- [ ] IE 74 (PDUSessionResourceSetupListCxtReq) 有無チェック
- [ ] UE context参照: Bearer確立が必要か判断

#### Step 2: E-RAB情報生成
- [ ] UE contextからUPF情報取得
- [ ] 5QI → QCI変換テーブル実装
- [ ] E-RAB ID割り当てロジック
- [ ] GTP-U Tunnel情報構築

#### Step 3: S1AP ICS修正
- [ ] `build_s1ap_erab_setup_in_ics()` 実装
- [ ] ASN.1エンコーディング
- [ ] 既存ICSメッセージへの追加

#### Step 4: テストと検証
- [ ] pcapキャプチャ: S1AP ICSにIE 24が含まれることを確認
- [ ] eNBログ: E-RAB Setup成功を確認
- [ ] UEログ: Bearer確立、データ通信可能を確認

---

## 参考資料

### 3GPP仕様書
- **TS 24.501**: 5G NAS protocol (Security Mode, UL NAS Transport, PDU Session)
- **TS 38.413**: NGAP protocol (InitialContextSetupRequest, IE definitions)
- **TS 36.413**: S1AP protocol (InitialContextSetupRequest, E-RAB Setup)
- **TS 23.502**: 5G System Architecture (PDU Session establishment procedure)

### キーワード
- AMF GMM State Machine
- Security Mode Complete
- PDU Session Establishment Request
- InitialContextSetupRequest
- E-RAB-ToBeSetupListCtxtSUReq (S1AP IE 24)
- PDUSessionResourceSetupListCxtReq (NGAP IE 74)
- NAS-PDU structure
- 5GMM vs 5GSM messages

### pcapファイル
- `20251110_48.pcap`: Phase 17.3 (PDU Session BEFORE SMC) - Unknown message error
- `20251110_50.pcap`: Phase 17.4 (PDU Session AFTER SMC +2ms) - タイミング遅延
- `20251108_10.pcap`: ICS未送信問題の詳細解析用（UEContextRequest IE欠落）
- `20251105_7.pcap`: Masked-IMEISV問題（全0xFF → eNB Cause=26）
- `20251023_3.pcap`: Attach Accept変換の検証
- `4G_Attach_Successful.pcap`: 正常な4G Attach手順（比較用）
- `5G_Registration_Successful.pcap`: 正常な5G Registration手順（比較用）
- `real_eNB_Attach.pcap`: 実eNBとMME間の成功事例（Masked-IMEISV, IE順序の参照）

### 開発履歴の重要マイルストーン

#### 2025年9月22日: ASN.1ライブラリ問題完全解決
- Makefileのwildcardパターン修正
- 19.3MBバイナリ正常生成
- NGAP/S1AP変換機能の基盤確立

#### 2025年9月23-24日: ESM→5GMM変換の実装と検証
- 初期実装: ESM → 5GSM (0x2E) で失敗
- 修正実装: ESM → 5GMM (0x7E 0x00 0x41) で成功
- AMF「Invalid extended_protocol_discriminator [0]」エラー解消

#### 2025年10月9-11日: Security Mode Command変換成功
- 5G NAS Integrity Protection実装
- EIA2 (AES-CMAC) による整合性保護
- Security Context管理とCOUNT管理

#### 2025年10月20-21日: Attach Accept変換実装
- Registration Accept (0x42) → Attach Accept (0x42) 変換
- ESM container（PDN Connectivity Accept）生成
- TAI/PLMN/GUTI の4G形式変換

#### 2025年10月23日: Attach Complete変換修正
- メッセージタイプ判定の修正（0x4E → 0x43）
- Attach Complete (0x43) → Registration Complete (0x43) 変換成功

#### 2025年10月29日: s1n2安定化対応
- S1C書き込みリトライ実装（POLLOUT待ち＋EAGAIN再送）
- SCTP接続の安定性向上
- ヘルスチェック機能の改善

#### 2025年11月5日: ICS IE順序とMasked-IMEISV問題解決
- Optional IE（192, 269）を末尾に移動
- Masked-IMEISVの正しいフォーマット実装
- eNB Cause=26（failure-in-radio-interface-procedure）解消

#### 2025年11月8-9日: ICS未送信問題の根本原因特定
- AMF ICS送信条件の詳細解析
- UEContextRequest IE欠落が原因と判明
- SMF N2 Transfer タイミング問題の発見

#### 2025年11月10日: Option 1の限界確定
- Phase 17.1-17.4の全試行結果を統合分析
- AMF State Machine制約の完全理解
- NAS暗号化処理時間（8-11ms）の影響確認
- **Option 2への移行決定**

### 実装済み機能の一覧

#### NAS変換機能
- ✅ Authentication Response (4G 0x54 → 5G 0x57)
- ✅ Security Mode Complete (4G 0x5E → 5G 0x5E)
- ✅ ESM → 5GMM Registration Request (0x6 → 0x7E 0x00 0x41)
- ✅ Attach Complete (4G 0x43 → 5G 0x43)
- ✅ Registration Accept → Attach Accept (5G 0x42 → 4G 0x42)

#### セキュリティ機能
- ✅ 5G NAS Integrity Protection (EIA2)
- ✅ Security Context管理（K_NASint, K_NASenc）
- ✅ UL/DL COUNT管理
- ✅ 下りNAS暗号化対応

#### NGAP/S1AP変換
- ✅ NGSetupRequest → S1SetupResponse
- ✅ InitialUEMessage (S1AP → NGAP)
- ✅ DownlinkNASTransport (NGAP → S1AP)
- ✅ UplinkNASTransport (S1AP → NGAP)
- ✅ InitialContextSetupRequest (NGAP → S1AP) - IE順序・Masked-IMEISV対応済み
- ⚠️ InitialContextSetupRequest - **E-RAB Setup情報生成は未実装**（Option 2で対応予定）

#### UEコンテキスト管理
- ✅ S1AP ↔ NGAP IDマッピング
- ✅ Security Context保存・参照
- ✅ Location Info管理（PLMN ID, Cell ID, TAC）
- ✅ PDU Session情報管理（Session ID, APN/DNN, QoS）

#### デバッグ・監視機能
- ✅ 詳細ログ出力（NAS変換、セキュリティ、プロトコル変換）
- ✅ ヘルスチェック機能（SCTP接続監視）
- ✅ SCTP接続リトライ機能
- ✅ カスタムログマーカー（★）による重要イベント追跡

### 未実装機能（Option 2で対応予定）

#### InitialContextSetup修正機能
- ⬜ NGAP ICS受信時のIE 74（PDUSessionResourceSetupListCxtReq）有無判定
- ⬜ E-RAB Setup情報の動的生成
- ⬜ UPF情報取得（IP, TEID）
- ⬜ 5QI → QCI変換
- ⬜ S1AP ICSへのE-RAB情報追加

#### その他の4G↔5G変換
- ⬜ Service Request (4G ↔ 5G)
- ⬜ TAU ↔ Mobility Registration Update
- ⬜ Detach ↔ Deregistration
- ⬜ Paging (NGAP ↔ S1AP)

#### ユーザープレーン
- ⬜ GTP-U TEIDマッピング（S1-U ↔ N3）
- ⬜ GTP-Uブリッジ実装
- ⬜ ユーザーデータ疎通確認

---

## Phase 18: 新たな問題の発見（2025年11月11日）

### Phase 18.1-18.3: E-RAB Setup Request実装とタイミング問題

#### Phase 18.1-Revised: ICS Failure検出とRegistration Complete偽装
**実施日**: 2025年11月11日

**背景**:
- Phase 17のOption 1アプローチの限界を受け、Option 2実装を開始
- しかし、新たな根本的問題を発見

**実装内容**:
```c
// s1n2_converter.c: lines 5985-6100
// ICS Failure検出時:
// 1. AMFにRegistration Complete (偽) を送信
// 2. AMF状態遷移: initial_context_setup → gmm_state_registered
// 3. PDU Session Establishment Requestを送信
// 4. AMFからPDU Session Resource Setup Request (proc=29) を受信
```

**成功**: ✅ AMFから実UPF情報を含むPDU Session Resource Setup Request受信

#### Phase 18.2: UPF N3情報の抽出
**実装内容**:
- PDU Session Resource Setup Request (procedureCode=29) からUPF情報抽出
- UPF IP: 172.24.0.21
- UPF TEID: 動的値（テストごとに変化）
- QFI抽出と5QI→QCI変換

**成功**: ✅ 実UPF情報の取得成功

#### Phase 18.3: E-RAB Setup Request構築と送信
**実装内容**:
```c
// s1n2_converter.c: lines 7210-7370
// build_s1ap_erab_setup_request()
// - ASN.1構造: S1AP_E_RABToBeSetupItemBearerSUReqIEs_t (Protocol IE wrapper)
// - 実UPF情報を使用
```

**問題発覚**: E-RAB Setup Request送信成功 (43 bytes, Frame 609/3026) しかし、eNBからの応答なし

#### 根本的な問題: RRC Connection Release

**タイムライン解析** (20251111_20.pcap):
```
17:16:06.xxx: eNB: attach,success
17:16:07.969: s1n2 → eNB: InitialContextSetupRequest (dummy UPF)
17:16:08.195: eNB → s1n2: InitialContextSetupFailure (Cause=26: radio interface failure)
17:16:08.195: eNB: "release cause,,other" ← ★RRC Connection Release
17:16:08.369: s1n2 → eNB: E-RABSetupRequest (実UPF) ← 174ms遅れ、UEは既にIDLE状態
```

**eNBログ証跡**:
```
Nov 11 17:16:06: IMSI(001011234567895) attach,success
Nov 11 17:16:07: release cause,,other
```

**決定的な発見**:
1. ✅ Phase 18.1-18.3の実装は全て正常動作
2. ✅ E-RAB Setup Requestも正しく構築・送信されている
3. ❌ **eNBはICS Failure直後にRRC Connection Releaseを発行**
4. ❌ E-RAB Setup Requestは既に切断されたUEに送信されている（無意味）

### Phase 18の技術的洞察

#### ICS Failureの原因
```
Cause: radioNetwork: failure-in-radio-interface-procedure (26)
```
- これはRRCレイヤーの失敗を示す
- eNBがUEに対してRRC Connection Reconfigurationを送信
- UE側で何らかの問題（おそらくdummy UPF情報による）

#### S1AP InitialContextSetup手順の理解
**重要な気づき**:
```
S1AP InitialContextSetup手順:
MME/s1n2 → eNB: InitialContextSetupRequest
eNB → MME/s1n2: InitialContextSetupResponse (成功時)
               OR
eNB → MME/s1n2: InitialContextSetupFailure (失敗時)
```

**プロトコル違反の誤解を訂正**:
- ❌ 誤: 「ICS Failureの後にICS Successを返せる」
- ✅ 正: ICS手順は既に完了。ResponseもFailureもeNBが返すもの。s1n2は受信側。

#### Design Document vs 実際のAMF動作

**Design期待** (PHASE18_OPTION2_DESIGN.md):
- AMFは2回のNGAP ICS Requestを送信
- 1回目: dummy UPF情報
- 2回目: 実UPF情報（IE 74含む）

**実際の動作**:
```bash
# NGAP ICS Request (proc=14)の検索
$ docker logs s1n2 | grep "procedureCode.*14.*detected"
[DEBUG] NGAP InitialContextSetupRequest detected (proc=14) - IE count: 7

# → 1回だけ！

# PDU Session Resource Setup Request (proc=29)の存在
$ tshark -r 20251111_20.pcap -Y "ngap.procedureCode == 29"
2982    Nov 11, 2025 17:16:08.219893000 JST
```

**判明した事実**:
- AMFは1回しかNGAP ICS Request (proc=14) を送信しない
- 代わりにPDU Session Resource Setup Request (proc=29) を送信
- Design documentの想定と異なる

#### eNBの動作特性（Baicells実機）

**発見した挙動**:
1. ICS Failureを返す
2. **即座にRRC Connection Releaseを発行** (1秒以内)
3. UEをRRC IDLE状態に遷移させる
4. この後に何を送っても無効（UE contextが存在しない）

**過去のログパターン解析**:
```
パターン1: ICS Failure直後の即座release
attach,success → release cause,,other (1秒後)

パターン2: タイムアウトrelease（別セッション）
attach,success → release cause,,other (1秒後)
→ release cause,,not receive mme initial context setup request (30-40秒後)
```

### Phase 18の試行による重要な学び

#### ❌ 試行して判明した「不可能なこと」

**1. ICS Success偽装は不可能**
- 理由: ICS ResponseもFailureもeNBが送信するもの
- s1n2は受信側であり、後から別のResponseを送ることはプロトコル違反

**2. ICS Retry（2nd ICS Request）も無効**
- 理由: eNBは既にRRC Connection Releaseを発行済み
- UE contextが存在しない状態でICS Requestを送っても無意味

**3. E-RAB Setup Requestも無効**
- 理由: 同上。RRC接続が切断された後に送信
- eNBは無視またはエラー応答

#### ✅ 判明した「唯一の解決策」

**Option 1: ICS Requestを遅延させる（実UPF情報を待つ）**

**コンセプト**:
```
現在の問題フロー:
1. NGAP ICS Request受信 (dummy UPF)
2. 即座にS1AP ICS Request送信 (dummy UPF)
3. eNB: ICS Failure → RRC Release
4. PDU Session Resource Setup Request受信 (実UPF)
5. E-RAB Setup Request送信 ← 遅すぎる、UEはIDLE

修正後のフロー:
1. NGAP ICS Request受信 (dummy UPF)
2. UPF情報チェック → なし → **ICS Requestをキャッシュ（保留）**
3. Phase 18.1-Revised実行 (Registration Complete送信)
4. PDU Session Resource Setup Request受信 (実UPF) ← UPF情報取得
5. **キャッシュされたICS Requestを実行**（実UPF情報で）
6. S1AP ICS Request送信 (実UPF)
7. eNB: ICS Success ✅
8. RRC Connection維持 ✅
```

**既存コード構造の活用**:
```c
// s1n2_converter.c: lines 6750-6800
// 既にS1AP ICS Responseのキャッシング機構が存在:
if (ue_map->has_pending_s1ap_ics && ue_map->pending_s1ap_ics_len > 0) {
    // キャッシュされたICS Responseを後で送信
}

// 同様の機構をICS Requestにも実装可能:
if (!ue_map->has_upf_n3_info) {
    // NGAP ICS Requestをキャッシュ
    ue_map->has_pending_ngap_ics_request = true;
    memcpy(ue_map->pending_ngap_ics_request, data, len);
    // S1AP ICS Requestは送信しない（保留）
    return;
}
```

**実現可能性の評価**: ⭐⭐⭐⭐⭐
1. ✅ 既存のpending機構を活用できる
2. ✅ プロトコル準拠（ICSを遅延させるだけ）
3. ✅ タイミング問題を回避（UPF情報が揃ってから送信）
4. ✅ RRC接続を維持（eNBはICS Successを返す）
5. ✅ コード変更箇所が明確

**懸念事項**:
- AMFからのタイムアウト（通常10-30秒）
- しかし、Phase 18.1-RevisedでRegistration Complete送信済み
- AMFは待機状態なので問題なし

### Phase 18で判明した代替案の不可能性

#### 代替案A: ICS Requestパラメータ改善（ハードコード）
**評価**: ⭐⭐ (非推奨)
- 実UPF IP (172.24.0.21) をハードコード
- 問題1: 環境依存（UPF IPが変わると動かない）
- 問題2: TEID衝突の可能性
- 問題3: Phase 18.2で取得した実TEIDと不一致
- 問題4: なぜICS Failureが発生するか根本原因不明のまま

#### 代替案B: ICS Failureを受け入れて再接続
**評価**: ⭐ (非推奨)
- UEの再Attachが必要
- 問題1: ユーザー体験が悪い（接続に時間がかかる）
- 問題2: 2回目のAttachでも同じ問題が起きる可能性
- 問題3: 根本解決にならない

#### 代替案C: UE Context Modification Request
**評価**: ❌ (不可能)
- eNBが既にUE contextを解放済み
- UE Context Modificationは存在しないUEに対して送信不可

### 次のステップ: Option 1実装計画

#### 実装方針の明確化

**Phase 18.4: NGAP ICS Request遅延機構の実装**

**Step 1: UE context構造体の拡張**
```c
// s1n2_context.h
typedef struct {
    // 既存フィールド
    bool has_pending_s1ap_ics;
    uint8_t pending_s1ap_ics[512];
    size_t pending_s1ap_ics_len;

    // 新規追加
    bool has_pending_ngap_ics_request;
    uint8_t pending_ngap_ics_request[2048];
    size_t pending_ngap_ics_request_len;
    time_t ngap_ics_request_time;
} ue_id_mapping_t;
```

**Step 2: NGAP ICS Request受信時の遅延判断**
```c
// s1n2_converter.c: line 6935付近
if (!map2->has_upf_n3_info) {
    printf("[INFO] [Phase 18.4] No UPF info yet, deferring ICS Request\n");

    // NGAP ICS Requestをキャッシュ
    map2->has_pending_ngap_ics_request = true;
    memcpy(map2->pending_ngap_ics_request, data, len);
    map2->pending_ngap_ics_request_len = len;
    map2->ngap_ics_request_time = time(NULL);

    // S1AP ICS Requestは送信しない
    handled = 1;
    goto cleanup;
}
```

**Step 3: PDU Session Resource Setup Request受信時の実行**
```c
// PDU Session Resource Setup Request (proc=29) 受信時
// UPF N3情報取得後:

if (ue_map->has_pending_ngap_ics_request) {
    printf("[INFO] [Phase 18.4] UPF info obtained, executing deferred ICS\n");

    // キャッシュされたNGAP ICS Requestを処理
    s1n2_handle_ngap_ics_with_upf_info(ctx,
                                       ue_map->pending_ngap_ics_request,
                                       ue_map->pending_ngap_ics_request_len,
                                       ue_map);

    ue_map->has_pending_ngap_ics_request = false;
}
```

**Step 4: テストと検証**
```bash
# 期待される動作:
# 1. NGAP ICS Request受信 → ログ "No UPF info yet, deferring ICS Request"
# 2. Registration Complete送信
# 3. PDU Session Resource Setup Request受信 → ログ "UPF info obtained"
# 4. S1AP ICS Request送信（実UPF情報）
# 5. eNB: ICS Response Success
# 6. eNBログ: "attach,success" のみ（releaseなし）

# pcapで確認:
# - S1AP ICS RequestのtransportLayerAddress = 172.24.0.21
# - S1AP ICS RequestのgTP-TEID = 実際の値（0x01020304ではない）

# eNBログで確認:
# - "attach,success"
# - "release cause,,other" が**出現しない**こと
```

---

**最終更新**: 2025年11月11日（Phase 18完了）
**ステータス**: Option 1実装方針確定、Phase 18.4実装準備完了
**次のマイルストーン**: Phase 18.4 - NGAP ICS Request遅延機構の実装
**重要な学び**: RRC Connection維持が絶対条件。ICS Failureを回避する唯一の方法は「最初から正しいUPF情報でICS Requestを送る」こと。
