# TAU Mobility Update 実装方針

## 背景
- 2025-11-19 の DL 停止は、S1N2 コンバータが LTE TAU を 5GS `Registration Request (Initial)` として送出し、AMF が既存 SM Context を Release したことが直接の原因。
- PFCP Session Delete → DL TEID 消滅 → Downlink のみ断。UL は維持され非対称状態となった。
- 再発防止には「TAU を Mobility/Periodic Update として扱う」「既存 UE Context/TEID を維持する」「Open5GS が既存ロジックのまま Mobility Update と認識できる NAS を生成する」3 点が必要。
- 2025-11-26 の最新版トレースでは、Mobility Update へ換装した NAS にも `PDU Session Status IE` を平文で付与していたため、Open5GS が `Non cleartext IEs is included [0x84]` → `Registration Reject (0x5F)` → `Implicit NG release` に至ることを確認。平文 Initial/Mobility Registration では cleartext **以外の IE を送らない**実装ガードが必須と判明した。

## 要件整理
1. **NAS 変換レイヤ (sXGP-5G)**
   - LTE TAU Detection を確実化し、5GS `Registration Request` の `registration_type.value` を `OGS_NAS_5GS_REGISTRATION_TYPE_MOBILITY_UPDATING` もしくは `PERIODIC_UPDATING` に設定する。
   - `registration_type.follow_on_req` は TAU 種別に応じて継承。
   - `update_type` IE を `last_visited_registered_tai` と共にセットし、AMF が Mobility Update と判定できる状態にする。
   - `access_type` は `OGS_ACCESS_TYPE_3GPP` 固定。MF only シナリオでは `OGS_ACCESS_TYPE_MF` を使用し、Open5GS 側との整合を保つ。
   - `PDU Session Status IE` は NAS セキュリティ文脈が確立し `Registration Request` を Integrity 保護できる場合のみ挿入し、初回登録/平文 Mobility Update では付与しない（cleartext IE 制約順守）。
2. **UE Context 保持**
   - `ue_id_mapping_t` に 5G-GUTI/AMF UE NGAP ID/ngKSI/`registration_result` をキャッシュするフィールドを追加し、TAU 後の再利用を可能にする。
   - `preserve_teid_mapping`, `in_tau_procedure` フラグで TEID を破棄しないガードを掛け、TAU 中も `teid_mapping_t` を維持する。
3. **Open5GS AMF 期待挙動の確認**
   - AMF 側は既存実装のままとし、S1N2 から渡す NAS が Mobility/Periodic Update 条件を満たせば SM Release が発行されないことを検証で保証する。
   - `registration_type.value` / `update_type` / `last_visited_registered_tai` が揃っている場合に `amf_sess_release_all()` が呼ばれないことをログで確認する。
   - もし正しい NAS を送っても SM Release が発行される場合に限り、フォールバックとして AMF ガード案を別途検討する。
4. **テスト/検証**
   - `test_s1n2_uecontextrequest.py` を流用して TAU シナリオを再現。pcap で PFCP Session Delete が発生しないことを確認。
   - `log/amf.log` に `/nsmf-pdusession/v1/sm-contexts/.../release` が出ないこと、`log/upf.log` に Error Indication が出ないことを確認。
   - NAS ダンプで `Registration Request` の `registration_type=0x02` (Mobility) / `update_type=0x04` (TA updating) を確認。

## コンポーネント別方針

### 1. S1N2 NAS 変換 (`sXGP-5G/src/nas/s1n2_nas.c`)

#### 1-1. 現状コードの整理
- ファイル先頭付近で、TAU/Mobility 用のヘルパが既に実装されている：
   - `s1n2_map_eps_update_type()`
      - EPS Update Type (`eps_update_type & 0x07`) を 5GS Registration Type 値に対応付け
      - `0,1,2 → S1N2_5GS_REG_TYPE_MOBILITY (0x02)` / `3 → PERIODIC (0x03)` / その他は INITIAL
   - `s1n2_map_eps_update_type_to_update_ie()`
      - EPS Update Type から 5GS Update Type IE 値を導出
      - `3 → S1N2_5GS_UPDATE_TYPE_PERIODIC_UPDATING (0x06)`, それ以外は `TA_UPDATING (0x04)`
   - `s1n2_build_registration_type_octet()`
      - `reg_value` / `follow_on_request` と UE コンテキスト (`ue_map`) から 1オクテットの Registration Type を構成
      - `ue_map->has_last_ngksi_5g` / `has_security_mode` を見て KSI/TSC を復元している
   - `s1n2_append_update_type()` / `s1n2_append_last_visited_tai()`
      - それぞれ IEI 0x53 / 0x52 で 5GS Update Type / last_visited_registered_TAI をエンコードする共通ロジック
- PDU Session Status については、以下が実装済み：
   - `s1n2_has_active_pdu_context()` / `s1n2_find_session_mapping()` / `s1n2_build_pdu_session_status_mask()`
      - TEID や UPF/N3 情報の有無から「アクティブな PDU セッションがある UE mapping」を検索し、PSI→ビットマスクを構成
   - `s1n2_append_pdu_session_status()`
      - IEI 0x50 を LSByte→MSByte の順に格納（Open5GS の内部 byte-swap 前提）

これらから分かる通り、「Mobility Update 用の値決定ロジック」は既に `s1n2_nas.c` に存在しており、
**問題は TAU 受信時にこのロジックを使わず、常に INITIAL Registration 生成パスへ落としていること**にある。

#### 1-2. 修正方針：TAU をコンバータ内で終端し、Registration 再送を止める

目的：
- Frame 4632 のような LTE TAU Request を受信したとき、
   - これを 5GS Registration Request(Initial) に変換して AMF へ送らない
   - S1N2 コンバータ内で TAU 手続きを完結させ、eNB/UE には 4G TAU Accept を返す
   - その際、既存の 5G Registration/PDU Session 状態（AMF/SMF/UPF 側コンテキスト）を変更しない

実装レベルでは、以下 2 段階に分ける：

1. **TAU uplink の検知と Registration パスからの分離**
2. **TAU Accept downlink の生成と返送**

##### (A) TAU uplink の検知と Registration パスからの分離

1. `s1n2_convert_uplink_nas_transport()`（またはそれに相当する uplink NAS 変換関数）内で、現状は
    - 4G NAS の 2 バイト目 (`msg_type`) を見て `ATTACH REQUEST` / `AUTHENTICATION RESPONSE` / その他…のように振り分け
    - TAU Request 相当のメッセージについても、`0xFF` など独自判定経由で `Registration Request (Initial)` 生成ルートへ落ちている
2. ここに **TAU Request 専用の判定ブロック**を追加する：
    - 4G NAS 先頭 2バイト (`first_byte`, `second_byte`) と Security Header Type を参照
    - `PD=EPS mobility management (0x7)` かつ `msg_type = TRACKING AREA UPDATE REQUEST (0x48/0x49 系)` を検出
    - 検出した場合は、**既存の Registration 変換ルートへ入れず**、新設する `s1n2_handle_tau_request()` へ分岐させる。
3. このとき、既存の `s1n2_map_eps_update_type()` / `s1n2_map_eps_update_type_to_update_ie()` を使って
    - どの種類の TAU（Normal / Combined / Periodic）かを判定し、UE mapping (`ue_map`) の `in_tau_procedure` フラグを立てる
    - TEID preservation ロジック（`s1n2_context_should_preserve_teid()`）と連動させて「この UE の既存 TEID マッピングは cleanup 対象外」にする

> 重要：このステップでは **AMF へは何も送らない**。あくまで「TAU が来た」という事実を UE context に記録し、後続の downlink で TAU Accept を返す準備をするだけとする。

##### (B) TAU Accept downlink の生成と返送

1. S1C 側で TAU に対する DL 応答を返すトリガは、
    - (シンプル案) TAU Request を受け取った直後、コンバータ内で即座に TAU Accept を生成して S1AP Downlink NAS Transport として返す
    - (拡張案) 将来、AMF にも TAU 情報を共有したくなった場合に備え、内部状態を見て再利用可能な形で TAU Accept IEs を組み立てる
2. TAU Accept の 4G NAS 本体は、新規関数 `s1n2_build_tau_accept_nas()` を追加して構築する：
    - 入力：`ue_map`, `eps_update_type`, 既存 Registration から引き継いだコンテキスト
    - 出力：4G NAS バイト列（`buffer[ ]`, `len`）
    - 中に含める IE（最低限）：
       - EPS Update Result（TA update 成功）
       - TAI List（`s1n2_append_last_visited_tai()` に類似／再利用して構築）
       - EPS Bearer Context Status（既存 PDU セッションを維持するため）
       - 必要に応じて NAS security パラメータ（既に確立済みの K_NAS に基づく）
3. 上記 4G NAS を S1AP に載せる処理は、既存の Downlink NAS 変換パスを再利用する：
    - Security Mode Command や Authentication Request で利用している S1AP Downlink ビルダ関数
       （例：`build_s1ap_downlink_nas()` 相当）に、メッセージタイプ `TAU ACCEPT` を追加するだけでよい。
    - UE mapping (`ue_map`) の `MME_UE_S1AP_ID` / `ENB_UE_S1AP_ID` は既存処理ですでに保持されているため、そのまま流用できる。
4. 最後に、TAU フローの完了時に `ue_map->in_tau_procedure` を false に戻し、必要であれば Registration/Mobility 用にキャッシュしている `last_visited_registered_tai` などを更新する。

#### 1-3. PDU Session Status IE 付与条件の明文化（既存ガードの整理）

すでに実装済みの `s1n2_build_pdu_session_status_mask()` / `s1n2_append_pdu_session_status()` に加え、
「**どのタイミングでこの IE を付与してよいか**」を以下のように整理してコードに反映する：

- 付与してよい条件（5G NAS 側）：
   - `ue_map->has_5g_nas_keys == true` かつ `ue_map->has_security_mode == true`
   - かつ、送信する 5G NAS の Security Header Type が `INTEGRITY PROTECTED` (≠ 平文)
- 付与してはいけない条件：
   - Initial Registration Request（SHT=0, PD=5GSMM）
   - Mobility Registration / TAU 相当であっても、Security Mode 前で NAS が平文のケース

実装としては、Registration/Mobility 変換パスの中で：

```c
bool can_send_pdu_status_ie = false;
if (ue_map && ue_map->has_5g_nas_keys && ue_map->has_security_mode &&
      nas_security_header_type_is_integrity_protected(sec_header_type)) {
      can_send_pdu_status_ie = true;
}

if (can_send_pdu_status_ie) {
      uint16_t mask = s1n2_build_pdu_session_status_mask(ctx, ue_map);
      if (mask) {
            s1n2_append_pdu_session_status(nas, &offset, capacity, mask);
      }
} else {
      printf("[TRACE] Skipped PDU Session Status IE (mask would be built) because NAS is not integrity protected yet\n");
}
```

のように、既に入っているガードを **Mobility/TAU シナリオでも必ず通る共通ルート**に集約しておく。これにより、
Frame 4632 以降のような「平文 Registration/Mobility に PDU Session Status が付与されて AMF に弾かれる」ケースを再度防止できる。

### 2. UE Context 拡張 (`sXGP-5G/include/s1n2_converter.h`, `src/context/s1n2_context.c`)
- 追加フィールド案：
  - `ogs_nas_5gs_registration_result_t last_registration_result;`
  - `ogs_nas_5gs_mobile_identity_guti_t last_5g_guti;`
  - `uint8_t last_ngksi_tsc;`
  - `uint8_t last_ngksi_value;`
  - `uint8_t last_5gs_access_type;`
- Security/TEID 保護フラグを駆動する `s1n2_context_mark_tau_start()/mark_tau_end()` を実装し、TAU 中の `teid_mapping_t` cleanup を抑止。
- `s1n2_convert_initial_ue_message()` で初回登録時に上記フィールドを更新し、以降の TAU で参照する。

### 3. Open5GS AMF 側の検証観点
- AMF の既存 FSM が Mobility/Periodic Update を受信した際に SM Release を発行しないことを、ログとpcapで確認する。
- `amf.log` で `amf_sess_release_all()` 呼び出しや `/sm-contexts/.../release` リクエストが出ていないかを監視し、S1N2 側で生成した NAS が期待値に達していることを証明する。
- 想定と異なる挙動が残る場合は、S1N2 側の NAS 生成不足を再チェックし、それでも解消しない場合にのみ AMF ガード案を検討する (本計画では範囲外)。

### 4. テスト/検証
- **Unit-like**: `sXGP-5G/test/test_all_algorithms.c` は対象外。代わりに `scripts/test_tau_flow.sh` (新規) を追加し、TAU→Mobility Update の NAS hex を生成して AMF ログのみを検証する軽量テストを追加する。
- **Integration**: 既存 `check_implementation.sh` に TAU シナリオを追記。pcap 取得→`tshark` で `Registration type` と `PFCP Session Deletion` の有無を grep。
- `amf.log` には `Registration Request includes PDU Session Status IE` が Mobility Update 初手で出ないこと、`Non cleartext IEs is included [0x84]` が再発しないことを必須チェック項目として追記する。

## 実施手順
1. `sXGP-5G` 側
   1. `ue_id_mapping_t` 拡張と Getter/Setter 実装。
   2. TAU 変換ロジック改修。初回登録データを再利用し Mobility Update を生成。
   3. TEID preservation フラグに基づく cleanup 抑止。
2. Open5GS 検証
   1. Mobility Update 変換後の NAS を投入し、Open5GS AMF ログ/pcap を確認。`/sm-contexts/.../release` が発生しないことを証跡化。
   2. もし Release が残る場合は NAS 生成内容を再点検し、必要なら別紙で AMF 側ガード案をまとめる。
3. ドキュメント/テスト
   1. `DL_OUTAGE_INVESTIGATION_20251119.md` に再発防止策反映。
   2. `scripts/check_implementation.sh` へ新テストフローを組み込む。
   3. pcap/ログの確認手順を `TAU_VERIFICATION_REPORT.md` に追記。

## 成功判定
- Mobility Update 時の AMF ログ/pcap に `/sm-contexts/.../release` や `amf_sess_release_all()` 呼び出しが現れない。
- SMF/UPF ログで PFCP Session Delete が走らない。
- UE 側 dl throughput が維持される（ping/iperf で確認）。
- `Registration Accept` の `5GS Registration result` が TAU 前後で変化しない。
