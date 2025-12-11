# PCAP比較分析レポート: 20251204_1 vs 20251203_9

## 1. 概要
本ドキュメントは、Ping疎通が安定していた `20251203_9.pcap` と、不安定で途切れる現象が発生した `20251204_1.pcap` のシーケンスレベルでの比較分析結果をまとめたものである。

## 2. 比較サマリ

| 項目 | 安定版 (20251203_9.pcap) | 不安定版 (20251204_1.pcap) |
| :--- | :--- | :--- |
| **Attach/Registration** | 67.9秒付近で開始し、スムーズに完了。 | 18秒〜59秒の間、リトライを繰り返すが、**最終的な成功シーケンスは安定版と同一**。 |
| **Security Mode** | Rejectは1回のみ発生し、その後成功。 | Rejectが多発するが、成功時の `Security Mode Complete` 以降の流れに差分なし。 |
| **Ping (ICMP)** | PDUセッション確立後、370秒以上安定して継続。 | 62秒付近で疎通開始するが、99秒付近で停止。 |
| **Tracking Area Update (TAU)** | **1回のみ** (97.4秒)、正常に応答あり。 | **4回** (69.2秒, 79.3秒, 89.3秒, 99.4秒)、約10秒周期で繰り返し発生。最後のTAUで切断。 |

### 2.1. TAU発生回数の比較

| キャプチャ | TAU Request 回数 | タイミング |
|-----------|-----------------|------------|
| **安定版** (20251203_9.pcap) | **1回** | 97.4秒 |
| **不安定版** (20251204_1.pcap) | **4回** | 69.2秒, 79.3秒, 89.3秒, 99.4秒 (約10秒周期) |

**重要な発見**: 不安定版では約10秒ごとにTAU Requestが発生している。これは異常に頻繁であり、UEがTAU Acceptを正しく受信/処理できていないため、繰り返しTAUを送っている可能性がある。

## 3. 詳細シーケンス分析

### 3.1. 共通の成功シーケンス (Security Mode Complete 以降)
両方のキャプチャにおいて、接続確立に成功した際のシーケンスは**完全に一致**している。

**安定版 (20251203_9.pcap) - 87秒付近:**
| Frame | Time (s) | Protocol | Message |
|-------|----------|----------|---------|
| 3482 | 87.052 | NGAP/NAS-5GS | UplinkNASTransport, **Security mode complete, Registration request** |
| 3604 | 87.078 | S1AP/NAS-EPS | **InitialContextSetupRequest**, Ciphered message |
| 3612 | 87.372 | S1AP | **InitialContextSetupResponse** |
| 3617 | 87.373 | NGAP/NAS-5GS | UplinkNASTransport, **Registration complete** |
| 3619 | 87.375 | NGAP/NAS-5GS | UplinkNASTransport, **PDU session establishment request** |
| 3723 | 87.396 | NGAP/NAS-5GS | **InitialContextSetupRequest** (PDU Session Resource) |
| 3726 | 87.396 | NGAP | **InitialContextSetupResponse** |

**不安定版 (20251204_1.pcap) - 58-59秒付近:**
| Frame | Time (s) | Protocol | Message |
|-------|----------|----------|---------|
| 1835 | 58.924 | NGAP/NAS-5GS | UplinkNASTransport, **Security mode complete, Registration request** |
| 1973 | 58.955 | S1AP/NAS-EPS | **InitialContextSetupRequest**, Ciphered message |
| 2002 | 59.245 | S1AP | **InitialContextSetupResponse** |
| 2007 | 59.246 | NGAP/NAS-5GS | UplinkNASTransport, **Registration complete** |
| 2009 | 59.247 | NGAP/NAS-5GS | UplinkNASTransport, **PDU session establishment request** |
| 2149 | 59.274 | NGAP/NAS-5GS | **InitialContextSetupRequest** (PDU Session Resource) |
| 2152 | 59.275 | NGAP | **InitialContextSetupResponse** |

このことから、**コンバーターの接続確立ロジック自体は正常に機能しており、安定版と不安定版で動作に違いはない**。

### 3.2. 不安定版 (20251204_1.pcap) の特異点
*   **18s - 59s: 接続試行のループ**
    *   成功するまでの間、Security Mode Command に対する Reject が多発している。
*   **69s - 99s: 頻繁なTAU Request**
    *   PDUセッション確立後、約10秒ごとにTAU Requestが発生 (69.2s, 79.3s, 89.3s, 99.4s)。
    *   各TAUに対してDownlink NAS Transport (TAU Accept相当) は返されているが、UEが正しく処理できていない可能性がある。
*   **99s - 103s: 最終切断**
    *   99.4s: UEが **4回目のTAU Request** を送信。
    *   99.4s: Converter → eNB: **DownlinkNASTransport** (TAU Accept) を送信。
    *   99.4s: 最後のPing応答がeNBへ届く。
    *   99.7s: eNB → Converter: **NASNonDeliveryIndication** (Cause: **radio-connection-with-ue-lost**) が発生。
    *   103.0s: **UEContextReleaseRequest** (Cause: failure-in-radio-interface-procedure) でコンテキスト解放。
    *   **分析**: コンバーターはTAU Acceptを正しくeNBに転送しているが、eNBがUEに無線で配信しようとした際にUEとの接続が切れていた。

## 4. 原因仮説と考察 (修正版)

1.  **接続確立シーケンスは正常**
    *   Security Mode Complete 以降のフローに差分がないため、コンバーターの Registration / PDU Session Establishment ロジックにバグはないと考えられる。

2.  **TAU Acceptの処理に問題がある可能性**
    *   不安定版では約10秒周期でTAU Requestが繰り返し発生している。
    *   これはUE側がTAU Acceptを正しく受信・処理できていないことを示唆する。
    *   考えられる原因:
        *   **NAS暗号化/完全性保護の不整合**: TAU AcceptのNASメッセージがUEで正しく復号できていない可能性。
        *   **TAU Accept変換の問題**: コンバーターが5GのService Accept等を4GのTAU Acceptに変換する際に、何らかのIEが欠落または不正になっている可能性。

3.  **切断の直接原因は無線区間 (Radio Link Failure)**
    *   最終的な切断は `RadioNetwork-cause=radio-connection-with-ue-lost` で発生。
    *   コンバーターはTAU Acceptを正しくeNBに転送しているが、UE側で処理できずに無線リンクが切断された。

4.  **初期リトライ多発の要因**
    *   18-59秒のリトライ多発も、同様の理由（NASメッセージの処理失敗）でUEが正しく応答できなかった可能性がある。

## 5. 根本原因: TAU Accept EPS Update Result のビット演算バグ (確定)

### 5.1. コンバーターログからの発見

**安定版ログ** (`s1n2_follow_20251203_133232.log`) と **不安定版ログ** (`s1n2_follow_20251204_134142.log`) を比較した結果、TAU処理に決定的な違いを発見した。

#### TAU Accept (平文) の比較:

| 版 | TAU Accept Plain (hex) | EPS Update Result |
|---|---|---|
| **安定版** | `07 49 01 29 54 ...` | `0x01` = Combined TA/LA updating |
| **不安定版** | `07 49 02 29 54 ...` | `0x02` = TA updating only |

#### TAU Request の EPS Update Type:

| 版 | EPS Update Type Octet | 下位4ビット (Update Type) | 上位4ビット (Additional) |
|---|---|---|---|
| **安定版** | `0x12` | `0x2` (Combined TA/LA) | `0x1` (Active flag) |
| **不安定版** | `0x22` | `0x2` (Combined TA/LA) | `0x2` (SMS only) |

### 5.2. バグの場所

**ファイル**: `sXGP-5G/src/nas/s1n2_nas.c` 590行目

```c
// 誤ったコード:
uint8_t eps_update_type = (uint8_t)((eps_update_type_octet >> 4) & 0x07);
```

**問題**: `eps_update_type_octet` から EPS Update Type Value を抽出する際に、**上位4ビット** (Additional update type) を取得している。

**TS 24.301 9.9.3.14** によると、EPS Update Type IE の構造は:
```
ビット: 8   7   6   5 | 4   3   2   1
       | Additional  | |   EPS update  |
       | update type | |   type value  |
```

正しくは **下位4ビット (bits 1-4)** を取得すべき。

### 5.3. バグの影響

| UE Request | コードの計算 | 生成された EPS Update Result | 正しい値 | 結果 |
|------------|------------|--------------------------|---------|------|
| `0x12` | `(0x12 >> 4) & 0x07 = 0x01` | `0x01` (Combined) | `0x02` | **偶然成功** |
| `0x22` | `(0x22 >> 4) & 0x07 = 0x02` | `0x02` (TA only) | `0x02` | **偶然成功 (だが不整合)** |

**なぜ不安定版で問題が発生したか:**

1. UEは `0x22` (Combined TA/LA updating + SMS only) で TAU Request を送信
2. コンバーターは `(0x22 >> 4) & 0x07 = 0x02` を計算
3. TAU Accept に `EPS Update Result = 0x02` (TA updating only) を設定
4. **UEは Combined TAU/LAU を要求したのに、TAU only で応答された**
5. UEはTAU失敗と判断し、10秒後にリトライ
6. 4回リトライ後、UEがRRC接続を解放 → 切断

### 5.4. バグの経緯 (Git履歴より)

Git履歴を調査した結果、このバグには以下の経緯があることが判明:

1. **コミット 7847e08** ("pingを40秒ぐらい通す") で TAU Accept 機能が追加された
   - 最初から読み取り側にバグがあった: `(eps_update_type_octet >> 4) & 0x07`
   - 書き込み側にもバグがあった: `(eps_update_type & 0x07) << 4` (上位4ビットに書き込み)

2. **コミット 8374d51** (HEAD, "pingをずっと通す") で**部分的に修正**された
   - 書き込み側は修正: `(eps_update_type & 0x07)` (正しく下位4ビットに)
   - **読み取り側は修正されなかった**: `(eps_update_type_octet >> 4) & 0x07` のまま

```diff
# 7847e08 → 8374d51 の差分 (src/nas/s1n2_nas.c)
  plain[off++] = 0x49; // TAU Accept (per detector)
+ // EPS update result: Spare (bits 5-8) + EPS update result value (bits 1-4)
+ // TS 24.301 Table 9.9.3.13.1: value in bits 1-4, spare in bits 5-8
  uint8_t eps_update_type = (uint8_t)((eps_update_type_octet >> 4) & 0x07);  // ← 未修正！
  if (eps_update_type == 0) {
          eps_update_type = 0x01;
  }
- plain[off++] = (uint8_t)((eps_update_type & 0x07) << 4);  // 旧: 上位4ビットに書き込み
+ plain[off++] = (uint8_t)(eps_update_type & 0x07);         // 新: 下位4ビットに書き込み
```

**結論**: 以前「下位4ビット」に関連する修正を行ったが、それは**出力側 (EPS Update Result を書き込む位置)** の修正であり、**入力側 (eps_update_type_octet からの読み取り)** は修正漏れだった。

### 5.5. 修正案

```c
// 修正後 (読み取り側):
uint8_t eps_update_type = (uint8_t)(eps_update_type_octet & 0x07);
```

## 6. 修正の実施と検証結果

### 6.1. 修正内容

**ファイル**: `sXGP-5G/src/nas/s1n2_nas.c`

#### 修正1: EPS Update Type の読み取り (行594付近)
```c
// 修正前 (バグ):
uint8_t eps_update_type = (uint8_t)((eps_update_type_octet >> 4) & 0x07);

// 修正後:
uint8_t eps_update_type = (uint8_t)(eps_update_type_octet & 0x07);
```

#### 修正2: EPS Update Type → EPS Update Result のマッピング追加
```c
// 追加: TS 24.301 に準拠したマッピング
// EPS update result の有効な値は 0 (TA updating) または 1 (Combined TA/LA updating) のみ
uint8_t eps_update_result;
if (eps_update_type == 1 || eps_update_type == 2) {
    eps_update_result = 0x01;  // Combined TA/LA updating
} else {
    eps_update_result = 0x00;  // TA updating only
}
plain[off++] = (uint8_t)(eps_update_result & 0x07);
```

**重要な発見**: 最初の修正 (読み取り側のビットシフト修正) だけでは不十分だった。

TS 24.301 によると:
- **EPS update type** (UE→NW): 0=TA, 1=Combined TA/LA, 2=Combined TA/LA with IMSI attach, 3=Periodic
- **EPS update result** (NW→UE): **0=TA updating, 1=Combined TA/LA updating のみ有効**

UEが `type=2` を送信した場合、そのまま `result=2` を返すと無効値となりUEが正しく処理できない。

### 6.2. 検証結果

#### 検証1: 20251204_2.pcap (読み取り側のみ修正)

| 項目 | 結果 |
|------|------|
| EPS Update Type 抽出 | ✅ `input_octet=0x22` → `extracted_type=2` (正しく下位4ビット) |
| EPS Update Result | ❌ `2` (無効値をそのまま返却) |
| TAU Request 回数 | ❌ **4回** (問題未解決) |

#### 検証2: 20251204_3.pcap (マッピング追加後)

| 項目 | 結果 |
|------|------|
| EPS Update Type 抽出 | ✅ `input_octet=0x22` → `extracted_type=2` |
| EPS Update Result | ✅ `type=2` → `result=1` (Combined TA/LA updating) |
| TAU Request 回数 | ✅ **1回** |
| Ping継続時間 | ✅ **100秒以上** (73s〜173s) |
| ICMPパケット数 | 609パケット |

### 6.3. 比較表

| 項目 | 不安定版 (20251204_1) | 修正v1 (20251204_2) | 修正v2 (20251204_3) |
|------|----------------------|---------------------|---------------------|
| **TAU Request回数** | 4回 | 4回 | **1回** ✅ |
| **EPS Update Result** | 2 (無効) | 2 (無効) | **1 (Combined)** ✅ |
| **Ping安定性** | 〜99秒で切断 | 〜99秒で切断 | **100秒+継続** ✅ |

### 6.4. ログ出力の追加

修正にあわせて、TAU Accept処理時のログ出力を追加:

```
[INFO] [TAU-ACCEPT] EPS Update Type extraction: input_octet=0x22, extracted_type=2
[INFO] [TAU-ACCEPT] Combined TA/LA requested (type=2) -> result=1
[INFO] [TAU-ACCEPT] EPS Update Result: 1 (Combined TA/LA updating)
```

## 7. 結論

### 7.1. 根本原因 (2段階の問題)

1. **ビットシフト方向の誤り**: `eps_update_type_octet` から EPS Update Type を抽出する際、上位4ビットを読んでいた（正しくは下位4ビット）

2. **Type→Result マッピングの欠如**: EPS update type の値をそのまま EPS update result として返していたが、TS 24.301 では result に 0 と 1 しか定義されていない

### 7.2. 修正結果

✅ TAU が正常に1回で完了するようになった
✅ Ping接続が100秒以上安定して継続することを確認
✅ 修正内容がログから観測可能

## 8. 推奨される次のアクション

1.  ✅ ~~TAU Accept の NAS ペイロード確認~~ → **完了: バグ特定済み**
2.  ✅ ~~バグ修正の実施~~ → **完了**
3.  ✅ ~~再試験~~ → **完了: 問題解決確認**
4.  **長時間テスト**: より長時間 (10分以上) のping疎通テストで安定性を確認
5.  **コミット**: 修正をGitにコミット

