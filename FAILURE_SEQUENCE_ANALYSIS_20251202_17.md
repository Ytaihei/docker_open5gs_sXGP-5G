# 失敗時PCAPシーケンス分析 (20251202_17.pcap)

## 概要
Frame 728〜1006 における S1AP/NGAP シーケンスの詳細分析。
このシーケンスは **ping が途切れた** 失敗例。

## ネットワーク構成
| IP Address     | Role              |
|----------------|-------------------|
| 172.24.0.111   | eNB (4G基地局)     |
| 172.24.0.30    | s1n2 Converter    |
| 172.24.0.12    | AMF (5G Core)     |

---

## S1AP/NGAP シーケンス一覧

### Phase 1: Security Mode Complete + Registration Request (Frame 728-730)

| Frame | 方向 | Protocol | メッセージ | 詳細 |
|-------|------|----------|-----------|------|
| 728 | eNB → Converter | S1AP | UplinkNASTransport | **Ciphered message** (SHT=4, SQN=0) |
| 730 | Converter → AMF | NGAP | UplinkNASTransport | **Security mode complete (0x5E)** + **Registration request (0x41)** |

**暗号化メッセージの推定:**
| Frame | 暗号化メッセージ | 推定内容 | 根拠 |
|-------|-----------------|---------|------|
| 728 | Ciphered (SHT=4, SQN=0) | **TAU Request (0x48)** | Frame 730でRegistration Requestに変換されている |

---

### Phase 2: Registration Accept → InitialContextSetup (Frame 848-888)

| Frame | 方向 | Protocol | メッセージ | 詳細 |
|-------|------|----------|-----------|------|
| 848 | AMF → Converter | NGAP | DownlinkNASTransport | Security protected NAS 5GS message (SHT=2, SQN=1) |
| **849** | **Converter → eNB** | **S1AP** | **InitialContextSetupRequest** | ⚠️ **Ciphered message** (SHT=2, SQN=1) - **TAU Accept ではない！** |
| 867 | eNB → Converter | S1AP | UECapabilityInfoIndication | UE Capability Information |
| 880 | eNB → Converter | S1AP | **InitialContextSetupResponse** | eNBがICS成功を応答 |
| 883 | eNB → Converter | S1AP | UplinkNASTransport | **Ciphered message** (SHT=2, SQN=1) |
| **885** | **Converter → AMF** | **NGAP** | **UplinkNASTransport** | **Registration complete (0x43)** |
| 886 | AMF → Converter | NGAP | DownlinkNASTransport | Security protected NAS 5GS message (SHT=2, SQN=2) |
| **887** | **Converter → AMF** | **NGAP** | **UplinkNASTransport** | **UL NAS transport (0x67)**, **PDU session establishment request (0xC1)**, PSI=5, Type=IPv4 |
| 888 | Converter → eNB | S1AP | DownlinkNASTransport | ⚠️ **SHT=7 (Reserved)** - 5G NASがそのまま転送されている |

**暗号化メッセージの推定:**
| Frame | 暗号化メッセージ | 推定内容 | 根拠 |
|-------|-----------------|---------|------|
| 848 | 5GS Protected (SHT=2, SQN=1) | **Registration Accept (0x42)** | AMFからの応答 |
| 849 | Ciphered (SHT=2, SQN=1) | ⚠️ **不明 (暗号化されたまま)** | 成功時は **TAU Accept (0x49, Plain)** だった |
| 883 | Ciphered (SHT=2, SQN=1) | **TAU Complete (0x4A)** | Frame 885でRegistration Completeに変換 |
| 886 | 5GS Protected (SHT=2, SQN=2) | **Configuration Update Command** | Registration Complete後の応答 |
| 888 | NAS (SHT=7: Reserved) | ⚠️ **5G NASがそのまま転送** | 変換失敗 |

---

### Phase 3: PDU Session 確立 (Frame 997-1000)

| Frame | 方向 | Protocol | メッセージ | 詳細 |
|-------|------|----------|-----------|------|
| **997** | **AMF → Converter** | **NGAP** | **InitialContextSetupRequest** | PDUSessionResourceSetupListCxtReq: PSI=5, Type=IPv4, DL/UL=1Gbps, NAS-PDU含む |
| **1000** | **Converter → AMF** | **NGAP** | **InitialContextSetupResponse** | PDUSessionResourceSetupListCxtRes: 成功応答 |

---

## 成功時フローの図解

```
eNB (4G)                    Converter (s1n2)                 AMF (5G Core)
   |                              |                               |
   |--- UL NAS (Ciphered) ------->|                               |   (728)
   |                              |--- SMC + Reg Req ------------>|   (730)
   |                              |                               |
   |                              |<-- DL NAS (Protected) --------|   (848)
   |<-- ICS Req + CIPHERED -------|                               |   (849) ⚠️ 成功時はTAU Accept (Plain)
   |--- UE Capability Info ------>|                               |   (867)
   |--- ICS Response ------------>|                               |   (880)
   |--- UL NAS (Ciphered) ------->|                               |   (883)
   |                              |--- Registration Complete ---->|   (885)
   |                              |<-- DL NAS (Protected) --------|   (886)
   |                              |--- PDU Session Est Req ------>|   (887)
   |<-- DL NAS (SHT=7 Reserved) --|                               |   (888) ⚠️ 5G NASそのまま
   |                              |                               |
   |                              |<-- NGAP ICS Req (PDU Sess) ---|   (997)
   |                              |--- NGAP ICS Resp (Success) -->|   (1000)
   |                              |                               |
```

---

## ⚠️ 成功時との重要な違い

### 1. Frame 849 vs Frame 4415: InitialContextSetupRequest 内の NAS メッセージ

| 項目 | 成功時 (Frame 4415) | 失敗時 (Frame 849) |
|------|---------------------|-------------------|
| Security Header Type | **0 (Plain)** | **2 (Integrity protected and ciphered)** |
| NAS Message | **TAU Accept (0x49)** 平文 | **Ciphered message** 暗号化されたまま |

**⇒ 成功時は平文の TAU Accept が送られているが、失敗時は暗号化されたままのメッセージが送られている！**

### 2. Frame 888: SHT=7 (Reserved)

失敗時の Frame 888 では、Security Header Type = 7 (Reserved) という異常な値が設定されている。
これは **5G NAS メッセージがそのまま 4G UE に転送されている** ことを示唆。

### 3. UEContextReleaseCommand の有無

| 成功時 | 失敗時 |
|--------|--------|
| Frame 4295 で **UEContextReleaseCommand** あり | **なし** |

成功時は一度 UE Context が解放され、再接続が行われている。

---

## 根本原因の推定

1. **NAS メッセージの暗号化状態の違い**
   - 成功時: Converter が 5G Registration Accept を **平文の 4G TAU Accept** に正しく変換
   - 失敗時: Converter が **暗号化されたままの NAS** を送信 → UE が復号できない可能性

2. **5G→4G NAS 変換の失敗**
   - Frame 888 で SHT=7 (Reserved) となっており、5G NAS がそのまま転送されている
   - 4G UE はこれを解釈できず、通信が途絶える

3. **セキュリティコンテキストの不整合**
   - 成功時は UEContextReleaseCommand で一度リセットされる
   - 失敗時はリセットなしで進行 → 鍵の不整合が発生している可能性

---

## 次の調査ポイント

1. **なぜ Frame 849 で暗号化されたままのメッセージが送られたのか？**
   - Converter のログを確認し、NAS 変換処理を追跡

2. **Frame 888 の SHT=7 の原因**
   - Converter が 5G NAS を 4G NAS に変換できなかった理由を調査

3. **UEContextReleaseCommand がない理由**
   - AMF が UEContextReleaseCommand を送信しない条件を調査
