# DL側疎通断・PFCP Session Deletion・BSFバインディング解除 調査メモ (2025-11-19)

## 1. 事象概要
- 2025-11-19 15:08:34(JST) 頃、UE (IMSI 001011234567895) で DL のみ疎通不可に陥った。
- pcap `log/20251119_6.pcap` と Open5GS ログにて、PFCP Session Deletion と BSF PCF バインディング削除が同時刻に発生していることを確認。
- S1N2 コンバータが 4G LTE TAU を 5GS `Registration Request` (UplinkNASTransport) として AMF に送出したことが直接のトリガ。

## 2. 主要ノード ( `.env` より )
| 機能 | IP |
|------|----|
| SCP | 172.24.0.11 |
| AMF | 172.24.0.12 |
| SMF | 172.24.0.20 |
| UPF | 172.24.0.21 |
| BSF | 172.24.0.17 |
| S1N2 Converter | 172.24.0.30 |
| LTE eNB | 172.24.0.111 |
| UE (APN=internet) | 192.168.100.2 |

## 3. タイムライン (pcap `20251119_6.pcap` 抜粋)
| Frame | 時刻 | 内容 | 補足 |
|-------|------|------|------|
| 8418 | 65.648s | eNB→S1N2, S1AP Uplink NASt, TAU Request | 4G TAU 発生 |
| 8421 | 65.649s | S1N2→AMF, NGAP UplinkNASTransport (Registration Request) | S1N2 が 5GS NAS へ変換 |
| 8425 | 65.650s | AMF→SCP, HTTP/2 HEADERS `POST /nsmf-pdusession/v1/sm-contexts/1/release` | SMF リリース依頼 |
| 8426 | 65.650s | AMF→SCP, HTTP/2 DATA (JSON: `ueLocation`, `ueTimeZone`) | Release Body |
| 8438 | 65.652s | SCP→BSF, HTTP/2 `DELETE /nbsf-management/v1/pcfBindings/1` | 旧PCFバインディング削除 |
| 8448-8449 | 65.653s | 8.8.8.8→UE, GTP-U ICMP Reply | 最後の DL データ |
| 8450-8451 | 65.654s | SMF↔UPF, PFCP Session Deletion Req/Rsp | TEID 0x01000908 破棄 |
| 8534以降 | 66.049s〜 | UPF→S1N2, GTP Error Indication | 削除済 TEID への DL 転送失敗通知 |

## 4. ログ証跡
### 4.1 AMF (`log/amf.log`)
```
2188458-2188507: UplinkNASTransport受信→`/nsmf-pdusession/v1/sm-contexts/1/release`
```
- AMF は Registration Request を受理すると同時に既存 SM Context を Release.

### 4.2 SMF (`log/smf.log`)
```
3610032-3610072: `POST /nsmf-pdusession/v1/sm-contexts/1/release`
 → PCF policy delete
 → PFCP Session Deletion
 → UDM/UDR SMF registration delete
```

### 4.3 BSF (`log/bsf.log`)
```
4012: [DELETE] /nbsf-management/v1/pcfBindings/1
```
- AMF/SCP 経由で PCF バインディングが即時削除。

### 4.4 UPF (`log/upf.log` / pcap)
- PFCP Session Deletion 直後から DL GTP-U TEID 0x01000908 は消滅。
- UL TEID 0x0000281c は継続 (UL は送信可能)。

## 5. 原因分析
1. **S1N2変換の問題**: TAU を 5GS `Registration Request` として送っており、AMFにとっては「再登録」に見える。
2. **AMF仕様**: 新規登録処理前に既存 SM Context を Release するため、SMF → UPF の PFCP Session Delete が必須で走る。
3. **結果**: DL 用 PFCP ルール削除 → DLのみ疎通途絶。UPFがError Indicationを返し、ULは残る非対称状態に。

## 6. 再発防止策
1. **コンバータ修正**
   - LTE TAU を 5GS `Service Request` / `Mobility Registration Update` として変換し、既存 `GUAMI`/`AMF UE NGAP ID` を維持する。
   - Registration Type を "periodic update" 等に設定し、AMFが `sm-context release` を呼ばないようにする。
2. **AMFガード (暫定)**
   - `gmm_state_registered()` で同一 UE からの Registration Request を受信した際、明示的な Deregistration でなければ SM Release をスキップする条件分岐を追加 (Open5GS改造)。
3. **検証手順**
   - 修正後に TAU シナリオを再取得し、`log/amf.log` で `/sm-contexts/.../release` が発生しないこと、pcap で PFCP Session Deletion / GTP Error Indication が出ないことを確認する。

## 7. 今後のアクション
- [ ] コンバータ側 NAS 生成ロジック調査 (`sXGP-5G/src/...`)
- [ ] AMF 側スキップ条件の PoC 実装
- [ ] 再試験用シナリオノート作成
