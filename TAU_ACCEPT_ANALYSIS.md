# TAU Accept 不整合分析メモ

## 目的
- UE が TAU Request を 10 秒周期で再送し、eNB から NAS Non-Delivery (radio connection with UE lost) が返ってくる事象について、無線品質ではなくコンバータ実装に起因する可能性を整理する。

## 観測事実
- `20251126_10.pcap` では TAU Request が 18:14:33 / 18:14:43 / 18:14:53 / 18:15:03 (frame 14611, 16080, 17575, 18659) と 10 秒間隔で複数回観測できる。
- eNB `trace/dbglog` でも各 TAU Request に対して DL_NAS 送信処理が走っているが、18:15:01 の処理のみ `DL NAS RLC TRANSFER failed causeValue[35]` ➔ NAS Non-Delivery ➔ radio link failure へ進んでいる。
- UE が再送する理由として、TAU Accept を正常に受信できていない（仕様外内容のため UE 側が破棄している）可能性が浮上。

## コンバータ実装の問題点
### 1. EPS Update Type のビット解釈ミス
- `src/nas/s1n2_nas.c` L592 付近で TAU Request の 3 バイト目（EPS update type octet）を `eps_update_type = (octet >> 4) & 0x07;` と読み取っている。
- 実際は **下位 3 ビット** が EPS update type (0b010 = Combined TA/LA updating with IMSI attach)。上位 3 ビットは KSI/TSC。
- 誤ったビット抽出のため、以降の処理（LAI 付与の判定など）が実際の要求種別と常に食い違う。

### 2. TAU Accept Octet 3 の生成が仕様違反
- TAU Accept の 3 バイト目は "EPS update result" を格納する必須フィールド (TS 24.301 9.9.3.32)。
- 現在の実装では `plain[off++] = (eps_update_type << 4);` のみで、結果コードを設定せず上位ビットに update type を書いている。
- UE から見ると EPS update result が 0 のまま（無効）で、下位ビットも 0 のため Accept が異常と判断される可能性が高い。

### 3. 固定/プレースホルダ IE
- **T3412 タイマ** を `0x29` に固定しており、ネットワーク設計値と乖離している恐れ。
- **TAI / LAI** は `ue_map->has_location_info` が false のとき環境変数ベースのデフォルト (001/01, TAC=1) を使用。TAU Request の旧 TAI と噛み合っていない可能性がある。
- **EPS bearer context status** も単一 bit のみをセットする簡易実装で、複数ベアラを持つ UE では不整合を招きうる。

## 影響
- TAU Accept の必須フィールドが仕様どおりでないため、UE が暗号復号後に破棄し T3410 タイマ再送へ移行していると推定。
- 4 回目の再送時に下り再送 (HARQ/NACK) が閾値を超え、eNB 側で radio link failure 判定となったが、根本は Accept 内容不整合のため UE が一度も TAU Complete を返せていない点にある。

## 対応方針
1. `s1n2_build_tau_accept_nas()` にて EPS update type を下位 3 ビットで取得し、Octet 3 には正しい "update result" を格納するよう修正する。
2. TAU Request で要求された update type を保持し、Accept 側の IE (TAI/LAI) を UE の旧情報と整合する形で生成する。
3. T3412 等のタイマ値は環境依存設定ないし HSS/AMF から得た値を利用できるようにし、固定値を避ける。
4. 可能であれば GUTI を返すなど、Combined TA/LA Updating で必須/推奨とされる IE を揃えて UE の互換性を確保する。

## 次の検証項目
- 修正後の TAU Accept で UE が T3410 を停止し TAU Complete を送出するか確認。
- 修正前後で `s1n2_dump_hex("[TAU-ACCEPT-PLAIN]")` のログを保存し、pcap から Accept 内容の差分を検証。
- UE ログ/AT コマンドで TAU Accept の decode 結果を取得し、各 IE が期待値と一致するか確認。

### UE ログが取得できない場合の進め方
- **TAU Complete の有無を pcap で判定**: `tshark -r <pcap> -d sctp.port==36412,s1ap -Y "nas-eps.msgtype == 0x4e"` 等で Downlink/UpLink の TAU Complete を探索し、1フレームも存在しない場合は UE 側で Accept が棄却されている確度が高いと判断する。
- **NASNonDelivery から原因を推測**: eNB→MME の `S1AP NAS Non-Delivery Indication` を Wireshark/ログで抽出し、Cause=21 が継続しているか、他の cause に変化していないかを追跡する。原因値が一定なら Accept 内容の差し戻しにフォーカス、変化しているなら eNB/無線品質側も再評価する。
- **TAU Accept 平文を仕様表と比較**: `s1n2_dump_hex("[TAU-ACCEPT-PLAIN]")` をそのままドキュメント化し、TS 24.301 の IE 順序・長さ一覧に照らしてチェックリスト化する。UE ログが無くても、NASNonDelivery が出た Accept の HEX を残しておけば、後日 UE ベンダに提示して解析してもらえる。
- **eNB dbglog の詳細化**: 取得可能な場合は `DL NAS RLC TRANSFER failed causeValue[...]` の直前直後のメッセージを抜き出し、失敗時刻と TAU Accept 送出ログ (`[TAU] tau-accept-sent`) をタイムライン上で突き合わせる。UE ログが無い状態でも、ネットワーク側で「どの Accept が即座に落ちたか」を把握できる。
- **差分管理**: UE 側の挙動が見えない間は、各テストごとに `TAU_ACCEPT-PLAIN` の HEX と NASNonDelivery の cause/時刻をセットで残し、accept 生成ロジックを変更した際のビフォーアフター比較ができるようにする。

### 20251128_8 再試験ログ (s1n2_20251128_174843.log / log/20251128_8.pcap)

#### TAU Accept 平文ログ
- `s1n2` ログに `[TAU-ACCEPT-PLAIN] (len=37)` が 4 回出力され、すべて同一内容だった。`S1N2_TAU_T3412=0x29`、`S1N2_TAU_EMM_CAUSE=0x21`、EPS bearer status mask `0x0020` が動的に記録されている。
- GUTI は `MME_GID=0x0200 / MME_CODE=0x40 / M-TMSI=0xC000046B` に変換され、TAI/LAI は `PLMN=00F110, LAC/TAC=0x0001` が固定で挿入されている。
- 平文 NAS は以下の通りで、Octet3=0x10 (EPS update result = TA updated)、Octet4=0x29 (T3412 ≒ 54min) となっている。`IEI 0x54` が EPS mobile identity、`IEI 0x13` が TAI/LAI、`IEI 0x50` が EMM cause、`IEI 0x57` が EPS bearer context status を表している。

```
[TAU-ACCEPT-PLAIN] len=37
0000 : 07 49 10 29 54 06 40 00 F1 10 00 01 13 00 F1 10
0016 : 00 01 50 0B 06 00 F1 10 02 00 40 C0 00 04 6B 53
0032 : 21 57 02 00 20
```

- Octet0-3 は `0x07 0x49 0x10 0x29` で構成され、`EPS update result=0b001 (Tracking area updated)`、`T3412=0x29 (54分)` が固定的に書き込まれている。
- IEI `0x54` (EPS mobile identity) は長さ `0x06` で終端しており、本来 11 octet 必要な GUTI を 6 octet で切り捨てている。ログ上は `MME_GID=0x0200, MME_CODE=0x40, M-TMSI=0xC000046B` と表示されるが、NAS 上では MME Group/Code しか送れていない。
- 続く `0x13` (TAI/LAI) も長さフィールドを持たず 5 octet をそのまま積んでおり、要求側 TAI と突合する仕組みになっていない。
- `S1N2_TAU_EMM_CAUSE=0x21` がそのまま `EMM cause IE` として付与されている (TAU Accept で cause を送る実装は稀)。
- `IEI 0x57` (EPS bearer context status) は `0x57 0x02 00 20` ➔ 値 `0x0020 (default bearer)` のみセットで固定。複数ベアラを運用する UE では矛盾する恐れがある。

※ IE ごとの長さや順序が TS 24.301 に整合しておらず、UE 側 decode で「意味的に不正 (cause 0x5F)」や Accept 棄却につながる要因になり得る。

#### log/20251128_8.pcap のサマリ
- br-sXGP-5G で取得した最新キャプチャでも TAU Complete (`nas_eps.nas_msg_emm_type == 0x4e`) は 0 件。UE は Accept を受信しても ACK を返していない。
- TAU Request (`EMM type 0x48`) は 10 秒周期で 4 回 (frame 1656/1926/2192/2432) 観測され、すべて `ENB-UE-S1AP-ID=31 / MME-UE-S1AP-ID=2` の同一 UE が送信している。
- NAS Non-Delivery Indication (`procedureCode 16`) が frame 2441/2442 で発生し、Cause=0 (radioNetwork unspecified) が eNB→MME に送られている。`s1ap.NAS_PDU` は暗号化済み `27664a...` で、Accept を配下 UE へ転送できなかった証跡となる。

| 種別 | Frame | JST 時刻 | eNB-UE | MME-UE | 備考 |
| --- | --- | --- | --- | --- | --- |
| TAU Request | 1656 / 1657 | 17:50:15.479 | 31 | 2 | 第1回 UL_NAS / ULTransport
| TAU Request | 1926 / 1927 | 17:50:25.519 | 31 | 2 | 第2回 (T3410 expiry)
| TAU Request | 2192 / 2193 | 17:50:35.559 | 31 | 2 | 第3回
| TAU Request | 2432 / 2433 | 17:50:45.599 | 31 | 2 | 第4回 (直後に Non-Delivery)
| NAS Non-Delivery | 2441 / 2442 | 17:50:45.964 | 31 | 2 | Cause=0 (radioNetwork unspecified)、`s1ap.NAS_PDU=27664a3611...61360`

- DownlinkNASTransport (procedureCode 12) が直前に複数回発生しているが、`nas_eps.nas_msg_emm_type` を decode できない (security header type 0x2) ため、pcap 上では Accept 内容が不明→NAS Non-Delivery で再掲されるのみ、という状態が読み取れる。

### 20251128_7.pcap ネットワーク側観測ログ
- **TAU Complete 探索**: `tshark -r log/20251128_7.pcap -d sctp.port==36412,s1ap -Y "nas_eps.nas_msg_emm_type == 0x4e"` でヒット 0 件。今回キャプチャでも UE からの TAU Complete は一度も観測できず、Accept 受信直後に UE が破棄している状況が継続している。
- **NAS Non-Delivery タイムライン**: `tshark -r log/20251128_7.pcap -d sctp.port==36412,s1ap -Y "s1ap.procedureCode == 16"` から抽出。Cause=0 は `radioNetwork=21 (radio connection with UE lost)` にマップされる。

| Frame | Time (JST) | eNB-UE-S1AP-ID | MME-UE-S1AP-ID | S1AP Cause | NAS Cause | 備考 |
| --- | --- | --- | --- | --- | --- | --- |
| 1224 | 16:22:39.624136 | 26 | 2 | radioNetwork=21 | 0x5F (semantically incorrect message) | 平文 NAS PDU `07 44 5f` を同梱 |
| 3082 | 16:23:52.033256 | 27 | 3 | radioNetwork=21 | (ciphered) | Security header type 2、Accept の直後に発生 |
| 3083 | 16:23:52.033276 | 27 | 3 | radioNetwork=21 | (ciphered) | 3082 の再送と思われる |

- **TAU Request HEX スナップショット (frame 2364)**: `s1ap.NAS_PDU = 17a5ff36c4020748020b09101021436587593a55945805f0f0c040115200f110000157022000310465b13e009011035758a6200a611404e291814004869040080402600400021f025d0103c1`。UE→MME の平文 TAU Request (CRNTI 98) をそのまま採取できるため、要求側の GUTI/TAC/ベアラ状態を比較する際の基準になる。

#### eNB dbglog との突合結果 (`/home/taihei/docker_open5gs_sXGP-5G/traial_eNB_log/trace/dbglog`)
- `wr_umm_dlnas.c:wrUmmDlNasProcessor` の `DL NAS RLC TRANSFER failed causeValue[35]` が発生したタイムスタンプは、pcap の NAS Non-Delivery フレームと 1:1 に対応している。causeValue 35 (RLC failure) ➔ S1AP Cause=radioNetwork:21 ➔ `NASNonDeliveryIndication` という流れが双方のログで一致。
- CRNTI 97 (UE ID 0) のケースでは RRC Connection Setup 直後に失敗しており、NAS PDU `07 44 5f` (EMM Cause 0x5F = semantically incorrect message) が eNB ➔ MME へ返送されている。CRNTI 98 (UE ID 1) のケースでは Initial Context Setup 完了後に 10 秒ごと TAU Request ➔ DL NAS 送信が繰り返され、最後の送信直後に radio connection lost で落ちる。

| Time (JST) | dbglog 抜粋 | CRNTI / UE-ID | S1AP IDs (pcap frame) | 備考 |
| --- | --- | --- | --- | --- |
| 16:22:39.62 | `DL NAS RLC TRANSFER failed causeValue[35]…`<br>`[S1AP]:Sending NAS NON DELIVERY INDICATION [MME-UE-S1AP-ID:2][eNB-UE-S1AP-ID:26]` | CRNTI 97 / UE0 | Frame 1224 (`MME-UE=2`, `ENB-UE=26`, NAS cause 0x5F) | TAU Request 初回。pcap 側 NASNonDelivery の平文 IE と完全一致 |
| 16:23:52.03 | `DL NAS RLC TRANSFER failed causeValue[35]…`<br>`[S1AP]:Sending NAS NON DELIVERY INDICATION [MME-UE-S1AP-ID:3][eNB-UE-S1AP-ID:27]` | CRNTI 98 / UE1 | Frames 3082-3083 (`MME-UE=3`, `ENB-UE=27`, S1AP cause 21) | Security header type=2 で NAS cause は暗号化。DL_NAS 送信 (trans id 16) 直後に失敗 |

- dbglog 16:23:21/31/41/51 では `UL_NAS` ➔ `DL_NAS` のトランザクションが連続し、pcap 上でも `frame 2364/2636/2842/3073` として TAU Request が 10 秒周期で観測される。同じ UE (CRNTI 98, ENB-UE 27) が Accept を受信できず再送し続けていることが両ログで確認できる。

### pcap差分解析 (2025-12-01 追加)

#### 成功pcap vs 失敗pcapの比較結果
**検証対象:**
- Success: `20251201_2.pcap` frame 2213 (ping成功)
- Failure: `20251201_5.pcap` frame 7264 (ping失敗)

#### 抽出された TAU Accept (暗号化済み NAS-PDU)

**Success (frame 2213):**
```
176f0eb51f020748120b09101021436587593a55945805f0f0c040115200f110000157022000310465b13e009011035758a6200a611404e291814004869040080402600400021f025d0103c1
```

**Failure (frame 7264):**
```
170d4362f0020748420b09101021436587593a55945805f0f0c040115200f110000157022000310465b13e009011035758a6200a611404e291814004869040080402600400021f025d0103c1
```

#### バイト単位差分

| Position | Success | Failure | Description |
|----------|---------|---------|-------------|
| Byte 0 | `0x17` | `0x17` | Security header type (0001=Integrity protected) + PD (0111=EPS MM) |
| Byte 1-4 | `6f0eb51f` | `0d4362f0` | **MAC (Message Authentication Code) - 完全に異なる** |
| Byte 5 | `0x02` | `0x02` | Sequence number = 2 (共通) |
| Byte 6 | `0x07` | `0x07` | 暗号化: Security header + PD |
| Byte 7 | `0x48` | `0x48` | 暗号化: Message type (0x49 TAU Acceptの可能性) |
| **Byte 8** | **`0x12`** | **`0x42`** | **暗号化: Octet 3 相当 - 唯一のペイロード差分** |
| Byte 9以降 | (同一) | (同一) | 残りの暗号化ペイロードは完全一致 |

#### 差分の詳細解析

**Byte 8の差分 (0x12 vs 0x42):**
```
Success: 0x12 = 0001 0010 (binary)
Failure: 0x42 = 0100 0010 (binary)

XOR: 0101 0000
→ Bit 6 と Bit 4 が異なる

差分: 0x42 - 0x12 = 0x30 (48 decimal)
```

**推定される意味 (TS 24.301 TAU Accept Octet 3):**

TAU Accept の Octet 3 は以下の構造:
- Bit 8-4: Spare / optional IE presence flags
- Bit 3-1: EPS update result value
  - `000` = TA updated
  - `001` = Combined TA/LA updated
  - `100` = TA updated and ISR activated
  - `101` = Combined TA/LA updated and ISR activated

**解釈:**
- Success `0x12` (0001 0010):
  - 上位: `00010` → 何らかのフラグ組み合わせ
  - 下位: `010` → EPS update result (非標準値?)

- Failure `0x42` (0100 0010):
  - 上位: `01000` → 異なるフラグ設定 (bit 6がON)
  - 下位: `010` → 同じupdate result

**Bit 6 差分の可能性:**
1. **EPS bearer context status IE (0x57) の presence flag**
   - `S1N2_TAU_EPS_BEARER_IE=0` (Case A) が有効な場合、IE省略のフラグが立つ
   - Success時にこのフラグがOFFで、Failure時にONになっている

2. **T3412 value の presence indication**
   - T3412タイマーIEの有無を示すフラグの可能性

3. **Optional IEs の組み合わせ差分**
   - LAI, GUTI, EMM cause等のIE存在パターンの違い

#### シーケンス差分の重要な発見

**Success (20251201_2.pcap):**
- 86秒: TAU Accept送信 (frame 2213/2214)
- 86秒: UE応答あり (frame 2216/2218)
- **TAU Accept再送なし → TAU Complete受信成功と推測**

**Failure (20251201_5.pcap):**
- 86秒: TAU Accept送信 (frame 7264/7265)
- 86秒: UE応答あり (frame 7267/7269)
- **96秒、106秒、116秒...と10秒間隔でTAU Accept再送**
- → **TAU Completeが受信されていない**
- → UEがTAU Acceptを正しく処理できていない

#### TAU Request側の既知差分

**NAS key set identifier (KSI):**
- Success: KSI = 1
- Failure: KSI = 4

この差分がセキュリティコンテキストに影響し、暗号化結果とMAC値が変化している。

#### 結論

1. **暗号化前の平文TAU Acceptで1バイト (Octet 3) が異なる**
   - 0x12 (Success) vs 0x42 (Failure)
   - Bit 6とBit 4の差分がIE構成の違いを示唆

2. **この1バイト差分がUEの処理に影響**
   - Failure時: UEがTAU Acceptを受け入れずTAU Completeを送信しない
   - 10秒間隔でTAU Accept再送 → NAS Non-Delivery

3. **環境変数トグルとの関連性**
   - `S1N2_TAU_EPS_BEARER_IE=0` の効果がOctet 3に現れている可能性
   - ただし、Success時に期待した動作をしているのか要検証

#### コード解析結果 (2025-12-01 追加)

**Octet 3生成ロジック (`s1n2_nas.c` L1102-1106):**
```c
uint8_t eps_update_octet = (uint8_t)((eps_update_result & 0x07) << 5);
eps_update_octet |= (uint8_t)((eps_active_flag & 0x01) << 4);
eps_update_octet |= (uint8_t)((eps_update_tsc & 0x01) << 3);
eps_update_octet |= (eps_update_nas_ksi & 0x07);
```

**Octet 3のビットフィールド構造:**
- Bit 7-5: `eps_update_result` (EPS update result)
  - `000` = TA updated
  - `001` = Combined TA/LA updated
  - `010` = TA updated and ISR activated
  - `011` = Combined TA/LA updated and ISR activated
- Bit 4: `eps_active_flag` (Active flag)
- Bit 3: `eps_update_tsc` (Type of security context flag)
- Bit 2-0: `eps_update_nas_ksi` (NAS key set identifier)

**pcap差分の再解析:**

Success: `0x12 = 0001 0010`
- Bit 7-5: `000` → `eps_update_result = 0` (TA updated)
- Bit 4: `1` → `eps_active_flag = 1`
- Bit 3: `0` → `eps_update_tsc = 0`
- Bit 2-0: `010` → `eps_update_nas_ksi = 2`

Failure: `0x42 = 0100 0010`
- Bit 7-5: `010` → `eps_update_result = 2` (TA updated and ISR activated)
- Bit 4: `0` → `eps_active_flag = 0`
- Bit 3: `0` → `eps_update_tsc = 0`
- Bit 2-0: `010` → `eps_update_nas_ksi = 2`

**差分原因の特定:**
1. **`eps_update_result` が異なる**: Success=0 (TA updated) vs Failure=2 (TA updated and ISR activated)
2. **`eps_active_flag` が異なる**: Success=1 (active) vs Failure=0 (not active)

これらはすべて**TAU Requestから読み取った値を反映している**:
- `s1n2_decode_eps_update_type_octet()` がTAU RequestのOctet 3を解析
- その値をそのままTAU AcceptのOctet 3に組み込んでいる

**根本原因:**
TAU Request側で異なる値を送信しているため、TAU Acceptも異なる値を返している。
- Success時のTAU Request: active_flag=1, update_type=0 (TA updating)
- Failure時のTAU Request: active_flag=0, update_type=2 (Periodic updating)

**問題点:**
UEがPeriodic updating (type=2)を要求すると、コンバータは`eps_update_result = TA updated and ISR activated`を返す（L1091-1093）。しかし、UEはこの結果を受け入れられず、TAU Completeを送信しない。

#### 次のアクション

1. **TAU Requestの差分を確認**
   - Success/Failure pcapでTAU RequestのOctet 3を比較
   - なぜUEが異なるupdate typeを要求するのか調査

2. **`eps_update_result`のマッピングを修正**
   - Periodic updating要求に対して ISR activated を返す実装が適切か検証
   - TS 24.301仕様との整合性を確認

3. **環境変数による強制設定を確認**
   - `s1n2_has_forced_eps_update_result()` の動作確認
   - Success時にresult=0を強制する環境変数が設定されていたか調査

### 実装タスク (2025-11-28 時点)
1. **Octet3 正常化 (EPS update result / type)**
	- `s1n2_nas.c::s1n2_build_tau_accept_nas()` で `eps_update_type` の抽出を下位 3bit に修正し、Accept 側は「結果 (上位 3bit)」「spare/KSI (下位 5bit)」を TS 24.301 Figure 9.9.3.32-1 に従ってセットする。
	- Combined TA/LA updating + IMSI attach 要求に対しては結果=0b011 を返せるよう、Request 解析ロジックを共通化。
	- **[2025-12-01追記]** pcap解析により、Octet 3の1バイト差分 (0x12 vs 0x42) がTAU Complete受信可否に直結していることが判明。Bit 6/4の差分原因を特定し、仕様準拠の値を生成する必要がある。
2. **GUTI / EPS mobile identity の完全エンコード**
	- `IEI 0x54` は 11 octet (MCC/MNC + MME Group ID + MME Code + M-TMSI) が必須。現在 6 octet で切り捨てられているため、5G-GUTI から M-TMSI を生成し直し、`struct s1n2_eps_mobile_id` を使って全長を書き込む。
3. **TAI/LAI の長さフィールドと内容を補正**
	- `IEI 0x13` (Tracking area identity list) は length + list type + TAC を持つ。Request 側 `old_tai` を保持して Accept に再掲し、Length 0 のまま書き込まないよう修正。
4. **EMM cause IE の扱いを再検討**
	- Accept に cause が入ると UE が `semantically incorrect message (0x5F)` で Reject するケースがある。`S1N2_TAU_EMM_CAUSE` は Reject/Status 用にとどめ、Accept では IEI `0x53` を省く実装を検討する。
5. **T3412/T3346 などタイマー値の外部設定化**
	- 現状は `0x29` 固定。`.env` か `auth_keys.yaml` と同等の YAML で per-network 値を渡し、`[INFO] [TAU-ACCEPT] Using T3412 value` ログが構成値と一致するようにする。
6. **EPS bearer context status のダイナミック反映**
	- `ie_mask=0x0020` 固定ではマルチベアラ UE の状態と乖離するので、`s1n2_erab_context` から実際の EPS bearer map を生成し、`default bearer` 以外の bit もセット可能にする。
7. **再試験エビデンスの自動保存**
	- `docker logs -f s1n2` を `log/s1n2_*.log` に常時 tee するスクリプトと、`tcpdump` > `log/YYYYMMDD_N.pcap` を開始/停止する helper を用意し、修正ごとの差分比較をしやすくする。
