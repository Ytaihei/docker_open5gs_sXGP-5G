# Authentication Failure転送問題の調査結果

**日付:** 2025年11月19日
**問題:** eNB→コンバーターに届いたAuthentication Failure (0x5C)がAMFに転送されていない

---

## 問題の発見経緯

### pcap分析結果 (`log/20251118_14.pcap`)

1. **eNB→コンバーター: Authentication Failure到達を確認**
   ```
   Frame 1901 (40.258105s): 172.24.0.111 → 172.24.0.1
     - Protocol: S1AP UplinkNASTransport (procedureCode=13)
     - NAS Message Type: 0x5C (Authentication Failure)
     - EMM Cause: 21 (Synch failure)
     - AUTS: 2ebceaa18de4e9d46bf101f3d729

   Frame 3827 (108.763s): 同様のパターン
     - AUTS: d2ed59404640ba9edda53941bf18
   ```

2. **コンバーター→AMF: 転送されていない**
   ```
   tshark -r 20251118_14.pcap -Y "ngap" -T fields -e ngap.procedureCode
   結果: 172.24.0.1 (converter) → 172.24.0.30 (AMF) の
         NGAP UplinkNASTransport (procedureCode=46) が存在しない
   ```

3. **タイミング分析**
   ```
   Frame 1901 (40.258105s): eNB→converter Auth Failure受信
   Frame 1904 (40.258263s): AMF→RAN_UE DownlinkNASTransport
   ギャップ: わずか0.158ms後にAMFが別のメッセージ送信
   ```
   → コンバーターはAuth Failureを受信したが、AMFに転送していない

---

## コード分析結果

### 1. UplinkNASTransportハンドラの存在確認

**ファイル:** `sXGP-5G/src/s1n2_converter.c`

#### メインループ (Line 3168-4000)

**エントリーポイント:** `s1n2_handle_s1c_message()`
- S1SetupRequest (0x11): ✅実装済み
- InitialUEMessage (0x0C): ✅実装済み
- **NAS Transport (0x0D): ✅実装済み (Line 3669-3900)**

#### procedureCode 0x0D ハンドラ (Line 3669-3900)

```c
if (data[0] == 0x00 && data[1] == 0x0D) {
    bool is_uplink = false;
    bool classified = false;

    // Step 1: ASN.1デコードによる分類
    S1AP_S1AP_PDU_t *nas_transport_pdu = NULL;
    asn_dec_rval_t nas_transport_dr = aper_decode_complete(...);

    if (nas_transport_dr.code == RC_OK && nas_transport_pdu &&
        nas_transport_pdu->present == S1AP_S1AP_PDU_PR_initiatingMessage) {
        if (nas_init->value.present == S1AP_InitiatingMessage__value_PR_UplinkNASTransport) {
            is_uplink = true;
            classified = true;
        }
    }

    // Step 2: フォールバック - ヒューリスティック分類
    if (!classified) {
        // NAS-PDU IE (ID=26)を探索してNASメッセージタイプで判定
        switch (nas_msg_type) {
            case 0x53: // Authentication Response
            case 0x5C: // Authentication Failure (コメントは間違っているが動作は正しい)
                is_uplink = true;
                classified = true;
                break;
            case 0x5E: // Security Mode Complete
                is_uplink = true;
                classified = true;
                break;
            default:
                is_uplink = false;  // ← ここに落ちると転送されない
                classified = true;
                break;
        }
    }

    // Step 3: Uplink処理
    if (is_uplink) {
        uint8_t ngap_data[512];
        size_t ngap_len = sizeof(ngap_data);

        if (s1n2_convert_uplink_nas_transport(ctx, data, len, ngap_data, &ngap_len) == 0) {
            // NGAP UplinkNASTransportをAMFに送信
            ssize_t sent = sctp_sendmsg(ctx->n2_fd, ngap_data, (size_t)ngap_len,
                                        NULL, 0, htonl(60), 0, 0, 0, 0);
            if (sent == (ssize_t)ngap_len) {
                printf("[INFO] UplinkNASTransport -> NGAP UplinkNASTransport sent (%zd bytes, PPID=60)\n", sent);
            }
        }
    }
}
```

**コードの状態:**
- ✅ UplinkNASTransportハンドラは実装済み
- ✅ 0x5Cは`case 0x5C:`に含まれ、`is_uplink=true`になるはず
- ✅ ASN.1分類ロジックも正しい
- ⚠️ しかし実際には転送されていない

### 2. 変換関数の実装状況

**関数:** `s1n2_convert_uplink_nas_transport()` (Line 2007-2300)

```c
int s1n2_convert_uplink_nas_transport(s1n2_context_t *ctx, uint8_t *s1ap_data, size_t s1ap_len,
                                     uint8_t *ngap_data, size_t *ngap_len) {
    // Step 1: S1AP PDUデコード
    S1AP_S1AP_PDU_t *pdu = NULL;
    asn_dec_rval_t dr = aper_decode_complete(...);
    if (dr.code != RC_OK) {
        printf("[ERROR] Failed to decode S1AP UplinkNASTransport (code=%d)\n", dr.code);
        return -1;  // ← ここで失敗？
    }

    // Step 2: UE ID抽出 (MME-UE-S1AP-ID, eNB-UE-S1AP-ID)
    long mme_ue_id = -1;
    long enb_ue_id = -1;
    const uint8_t *nas_buf = NULL;
    size_t nas_len = 0;

    // Step 3: UE ID mappingの取得
    ue_id_mapping_t *ue_map = NULL;
    if (enb_ue_id >= 0) {
        ue_map = s1n2_context_ensure_mapping_for_enb(ctx, enb_ue_id);
    }
    // ue_mapがNULLでも処理は継続される

    // Step 4: NASセキュリティ処理 (復号化/MAC検証)
    // Step 5: 4G→5G NAS変換
    // Step 6: NGAP UplinkNASTransport構築
    // Step 7: 戻り値 0=成功, -1=失敗
}
```

**潜在的な失敗ポイント:**
1. ASN.1デコード失敗 (code != RC_OK)
2. NAS-PDU抽出失敗 (nas_buf == NULL)
3. UE ID mapping取得失敗 (ue_map == NULL) ← 最も疑わしい
4. NAS変換失敗 (`convert_4g_nas_to_5g()` エラー)
5. NGAPメッセージ構築失敗 (`build_ngap_uplink_nas()` エラー)

---

## 推測される根本原因

### シナリオA: UE ID mapping不在

**問題:**
- Authentication Failure送信時点でUEコンテキストが完全に確立されていない
- `ue_map`がNULLまたは必要なフィールド (AMF-UE-NGAP-ID) が未設定
- NGAPメッセージ構築に失敗してエラーリターン

**証拠:**
- Frame 1901は最初のAuthentication Requestの応答
- この時点ではまだ認証プロセスの初期段階
- AMF-UE-NGAP-IDはDownlinkNASTransportで初めて割り当てられる可能性

### シナリオB: ASN.1分類失敗 → default caseに分類

**問題:**
- ASN.1デコードが失敗 (`classified=false`のまま)
- ヒューリスティック分類でNAS-PDU抽出に失敗
- `default: is_uplink=false`に分類され、Uplink処理がスキップされる

**反証:**
- pcapでは正しいS1AP UplinkNASTransport構造が確認済み
- ASN.1デコードが失敗する理由が不明

### シナリオC: エラーログが出力されているが未確認

**問題:**
- 実際にはエラーが発生してログに記録されている
- コンテナが停止しているため最新ログを確認できていない

**次のステップ:**
システム再起動して実際のコンバーターログを確認

---

## 検証済み事項

### Open5GS側の実装は完全

1. **AMF Authentication Failureハンドラ** (`gmm-sm.c` Line 1656-1705):
   ```c
   case OGS_NAS_5GS_AUTHENTICATION_FAILURE:
       switch (authentication_failure->gmm_cause) {
       case OGS_5GMM_CAUSE_SYNCH_FAILURE:
           // AUTS処理 → AUSF再認証リクエスト
   ```

2. **UDM AUTS処理 + MongoDB自動更新** (`nudm-handler.c` Line 73-195):
   ```c
   if (ResynchronizationInfo) {
       ogs_auc_sqn(udm_ue->opc, udm_ue->k, rand, auts, sqn_ms, mac_s);
       sqn = (sqn + 32 + 1) & OGS_MAX_SQN;  // SQN_MS + 33
       // MongoDB更新 via UDR
   ```

3. **s1n2 4G→5G NAS変換** (`s1n2_nas.c` Line 1486-1606):
   ```c
   if (msg_type == 0x5C) {  // 4G Authentication Failure
       // AUTS抽出 (IEI 0x30, 14 bytes)
       // 5G Authentication Failure (0x59)構築
       return 0;  // 成功
   ```

**結論:** Open5GS側は完全に実装済み。問題はs1n2コンバーターにある。

---

## 次のアクションプラン

### 優先度1: ログ確認による実際のエラー特定

```bash
# システム起動
cd /home/taihei/docker_open5gs_sXGP-5G
docker-compose -f deployments/5g/docker-compose.yml up -d

# Authentication Failure再現
# (eNBを接続してSIM認証実行)

# コンバーターログ確認
docker logs s1n2 2>&1 | grep -A 10 -B 10 "proc=0x0D\|UplinkNAS\|Authentication\|ERROR\|WARN"
```

**期待される発見:**
- `[ERROR] Failed to decode S1AP UplinkNASTransport`
- `[ERROR] S1AP UplinkNASTransport missing NAS-PDU`
- `[WARN] UE mapping not found`
- `[ERROR] Failed to build NGAP UplinkNASTransport`

### 優先度2: デバッグログ追加

**対象箇所:**
1. `s1n2_handle_s1c_message()` Line 3669:
   ```c
   if (data[0] == 0x00 && data[1] == 0x0D) {
       printf("[DEBUG] ★★★ Received procedureCode=0x0D (len=%zu) ★★★\n", len);
   ```

2. Line 3773前後:
   ```c
   if (is_uplink) {
       printf("[DEBUG] ★★★ is_uplink=true, calling s1n2_convert_uplink_nas_transport ★★★\n");
       int ret = s1n2_convert_uplink_nas_transport(...);
       printf("[DEBUG] ★★★ Conversion result: %d ★★★\n", ret);
   } else {
       printf("[DEBUG] ★★★ is_uplink=false, skipping Uplink processing ★★★\n");
   }
   ```

3. `s1n2_convert_uplink_nas_transport()` Line 2100前後:
   ```c
   if (!ue_map) {
       printf("[ERROR] ★★★ UE mapping not found (enb_ue_id=%ld, mme_ue_id=%ld) ★★★\n",
              enb_ue_id, mme_ue_id);
   }
   ```

### 優先度3: 暫定対応 (もしUE ID mapping問題なら)

**方針:** Authentication Failure時はUE ID mappingなしでも転送を試みる

```c
// Line 2100付近に追加
if (!ue_map && nas_len >= 2 && nas_buf[1] == 0x5C) {
    printf("[INFO] Authentication Failure detected without UE mapping, forwarding anyway\n");
    // AMF-UE-NGAP-ID = 0xFFFFFFFF (invalid marker)
    // RAN-UE-NGAP-ID = enb_ue_id
    // → AMFが新規UEとして処理
}
```

---

## 技術的詳細

### S1AP vs NGAP procedureCode対応

| 4G (S1AP) | 5G (NGAP) | 方向 | 用途 |
|-----------|-----------|------|------|
| 12 (DownlinkNASTransport) | 4 (DownlinkNASTransport) | MME→eNB / AMF→gNB | Downlink NAS |
| 13 (UplinkNASTransport) | 46 (UplinkNASTransport) | eNB→MME / gNB→AMF | Uplink NAS |

### NASメッセージタイプ

| 4G (EMM) | 5G (5GMM) | 意味 |
|----------|-----------|------|
| 0x41 | 0x41 | Authentication Request |
| 0x53 | 0x53 | Authentication Response |
| 0x5C | 0x59 | Authentication Failure |
| 0x5D | 0x5D | Security Mode Command |
| 0x5E | 0x5E | Security Mode Complete |

**注意:** Authentication Failureのみ、4G=0x5C → 5G=0x59に変換が必要

### AUTS構造 (14 bytes)

```
[0-5]:  SQN_MS ⊕ AK (6 bytes)
[6-13]: MAC-S (8 bytes)
```

**抽出例 (Frame 1901):**
```
AUTS: 2ebceaa18de4e9d46bf101f3d729
SQN_MS⊕AK: 2ebceaa18de4
MAC-S:     e9d46bf101f3d729
```

---

## 関連ファイル

### コアロジック
- `sXGP-5G/src/s1n2_converter.c` Line 3669-3900: procedureCode 0x0Dハンドラ
- `sXGP-5G/src/s1n2_converter.c` Line 2007-2300: `s1n2_convert_uplink_nas_transport()`
- `sXGP-5G/src/nas/s1n2_nas.c` Line 1486-1606: 4G→5G NAS変換

### Open5GS (動作確認済み)
- `sources/open5gs/src/amf/gmm-sm.c` Line 1656-1705: AMF Auth Failureハンドラ
- `sources/open5gs/src/udm/nudm-handler.c` Line 73-195: UDM AUTS処理

### pcap証拠
- `log/20251118_14.pcap` Frame 1901, 3827: Auth Failure到達確認

---

## まとめ

**判明した事実:**
1. ✅ s1n2コンバーターにUplinkNASTransportハンドラは実装済み
2. ✅ 0x5C (Auth Failure)は`case 0x5C:`に含まれる
3. ✅ Open5GS側は完全に実装済み (AMF/AUSF/UDM/UDR)
4. ❌ pcap証拠: Auth FailureがeNB→converterに到達するが、AMFに転送されない

**最も可能性が高い原因:**
`s1n2_convert_uplink_nas_transport()`関数内でエラーが発生し、NGAPメッセージ送信がスキップされている。特にUE ID mappingの取得失敗が疑わしい。

**次のステップ:**
システムを再起動してコンバーターログから実際のエラーメッセージを確認する。

---

## 2025-11-19: 最新ログ・pcapから判明した事実

### ログ証拠 (`log/20251119_2.pcap` 取得時の `docker compose logs -n 400 s1n2`)

1. **UL NASはすべて`security_header=0x1`で到着**
    - `[WARN] [NAS-SEC-UL] Encrypted/integrity-protected message received but no NAS keys available`
    - NAS鍵を導出していないため、実際のAuthentication Failureが暗号化されたまま扱われ、再登録リクエストとして再構築されてしまう。

2. **AMF-UE-NGAP-ID未確立時の明示的ブロック**
    - `s1n2_convert_uplink_nas_transport()`内 (`[UL-MAP]` ログ) にて `nas_message_type_for_map == 0x5C` かつ `amf_ue_ngap_id <= 0` の場合に `[WARN] Blocking uplink NAS (type=0x5C) because AMF-UE-NGAP-ID not assigned yet` と出力して `return -1`。
    - つまり、今回のドロップは推測ではなく「AMF側でUE ID未割当ならAuth Failureを送らない」という実装が原因。

3. **AMF側では毎回新しいAuthentication Requestを送出**
    - `RAND/AUTN` が毎回キャッシュされるログ (`[SUCCESS] [SQN-FIX] ...`) が多数出力。
    - 実際のAuth FailureはAMFに届かず、AMFは毎回「新規Registration Request」だと認識している。

4. **追加のS1AP手続き (proc=16/18/15) が未実装のため警告連発**
    - `[WARN] Unknown S1AP message type: 00 10/00 12/00 0f` が続く。内容は Downlink NAS再送、NAS Non-Delivery、Reset 相当。

### pcap確認
- `Frame 2071` (S1AP UplinkNASTransport) はNAS type 0x5Cを保持し、AUTSも含む。
- `Frame 2074` (NGAP UplinkNASTransport) では5GMM Auth Failure(0x59)が一度は生成・送信されているものの、その後の再登録ループではNAS鍵未導出のまま再構築され、実際のFailureは渡らない。

---

## 実装方針の更新

### 1. AMF-UE-NGAP-ID未割当時でもAuth Failureを届ける

- `s1n2_convert_uplink_nas_transport()` の `amf_ue_ngap_id` チェックを緩和し、初回Auth Failureは以下いずれかで送出する:
  1. **InitialUEMessage経由**で再送（AMFが再度IDを採番できる）
  2. **一時的なAMF-UE-ID (例: 0xFFFFFFFF)** を埋めて NGAP UplinkNASTransport を送る
  3. **送信を遅延し、DownlinkNASTransportでIDが計上された瞬間に再送**
- 現実装は即座に`return -1`してしまうため、この制御をリファクタ。

### 2. NAS鍵導出の即時実装

- `s1n2_auth` と `s1n2_security` に既存のKDF/EEA/EIA実装があるため、以下の流れを確立する:
  1. Downlink Authentication Request受信時 (`[SQN-FIX]` ログ) で既に RAND/AUTN/IMSI をキャッシュしている。
  2. 同タイミングで `s1n2_auth_kdf_get_nas_keys()` を呼び出し、UL NAS復号に必要な `KNASint/KNASenc` を保持する。
  3. UL NAS受信時は即座に復号し、NASメッセージ種別を正しく判定して 5G NAS 0x59 を構築。
- これにより `[WARN] no NAS keys available` を解消し、暗号化されたAuthentication Failureも正しく扱える。

### 3. S1AP proc=16/18/15 の最低限ハンドリング

- 16: DownlinkNASTransport再送 → 既存0x0Dハンドラで扱えるように統合、あるいは単純にACKしてログを減らす。
- 18: NAS Non-Delivery → NGAP `NAS-NON-DELIVERY-INDICATION` へ変換し、AMFへ通知。
- 15: Reset → gNB Reset扱いでNGAP `NGReset` を送信、少なくとも無視せずログを明瞭化。

### 4. ドキュメントとログの整備

- 本ドキュメントに「実際にブロックしているコードパス」「NAS鍵未導出による再登録ループ」を明記済みだが、変更後も再発した際に追跡できるよう、ログメッセージを固定フォーマット化する予定。

---

## 改訂版アクションプラン

1. **ドキュメント更新 (本稿)**
    - ✅ 現象と原因を明文化（AMF IDガード/NAS鍵未導出）
2. **コード改修 第1弾**
    - `s1n2_convert_uplink_nas_transport()` の `amf_ue_ngap_id` ガードを緩和し、Auth Failureを確実に送出
    - 暫定では「AMF ID無しでもUplinkNASTransportを一度送る」実装を行い、AMF側で受理されることを確認
3. **コード改修 第2弾**
    - Downlink Auth Request受信時にNAS鍵を導出 → ULで即復号
    - 復号後は `convert_4g_nas_to_5g()` の結果が0x59になることを再確認
4. **S1AP追加手続きの実装/無害化**
    - proc=15/16/18 の取り扱いを整理し、警告を減らす
5. **再試験**
    - 端末を再度Attachさせて `log/20251119_x.pcap` を取得
    - Auth FailureがNGAP経由でAMFに届き、AUSFのSQN再同期が走ることを検証

---

## 次の作業

- [ ] `s1n2_converter.c` と `s1n2_nas.c` に上記変更を実装
- [ ] 追加のユニットテスト/ログで回帰チェック
- [ ] pcap再取得とOpen5GSログの検証

