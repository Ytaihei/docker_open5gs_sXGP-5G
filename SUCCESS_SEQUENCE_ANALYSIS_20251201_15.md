# 成功時PCAPシーケンス分析 (20251201_15.pcap)

## 概要
Frame 4292〜4551 における S1AP/NGAP シーケンスの詳細分析。
このシーケンスは **TAU (Tracking Area Update) フォールバック** により接続を維持している成功例。

## ネットワーク構成
| IP Address     | Role              |
|----------------|-------------------|
| 172.24.0.111   | eNB (4G基地局)     |
| 172.24.0.30    | s1n2 Converter    |
| 172.24.0.12    | AMF (5G Core)     |

---

## S1AP/NGAP シーケンス一覧

### Phase 1: Security Mode Complete + Registration Request (Frame 4292-4295)

| Frame | 方向 | Protocol | メッセージ | 詳細 |
|-------|------|----------|-----------|------|
| 4292 | eNB → Converter | S1AP | UplinkNASTransport | **Ciphered message** (Security header type=4: Integrity protected and ciphered with new EPS security context, SQN=0) |
| 4294 | Converter → AMF | NGAP | UplinkNASTransport | **Security mode complete (0x5E)** + **Registration request (0x41)** |
| 4295 | AMF → Converter | NGAP | **UEContextReleaseCommand** | Cause: nas (2) - AMFがUEコンテキストを解放 |

**暗号化メッセージの推定:**
| Frame | 暗号化メッセージ | 推定内容 | 根拠 |
|-------|-----------------|---------|------|
| 4292 | Ciphered (SHT=4, SQN=0) | **TAU Request (0x48)** | Frame 4294でConverterがRegistration Requestに変換して送信、Frame 4415でTAU Acceptが返されることから、元はTAU Requestと推定 |

**重要ポイント:**
- Frame 4292: UE が **TAU Request** を送信 (Ciphered)
- Frame 4294: Converter が TAU Request を **Registration Request** に変換して AMF に送信（+ Security Mode Complete も付加）
- Frame 4295 で **AMF が UEContextReleaseCommand を送信** (これは一旦コンテキストをクリアする動作)

---

### Phase 2: TAU Accept による再接続 (Frame 4413-4435)

| Frame | 方向 | Protocol | メッセージ | 詳細 |
|-------|------|----------|-----------|------|
| 4413 | AMF → Converter | NGAP | DownlinkNASTransport | Security protected NAS 5GS message (SHT=2, SQN=1) |
| **4415** | **Converter → eNB** | **S1AP** | **InitialContextSetupRequest** | **Tracking area update accept (0x49)** - TAU Acceptを含む！ |
| 4425 | eNB → Converter | S1AP | UECapabilityInfoIndication | UE Capability Information |
| 4427 | eNB → Converter | S1AP | **InitialContextSetupResponse** | eNBがICS成功を応答 |
| 4430 | eNB → Converter | S1AP | UplinkNASTransport | **Ciphered message** (SHT=2, SQN=1) |
| **4432** | **Converter → AMF** | **NGAP** | **UplinkNASTransport** | **Registration complete (0x43)** |
| 4433 | AMF → Converter | NGAP | DownlinkNASTransport | Security protected NAS 5GS message (SHT=2, SQN=2) |
| **4434** | **Converter → AMF** | **NGAP** | **UplinkNASTransport** | **UL NAS transport (0x67)**, **PDU session establishment request (0xC1)**, PSI=5, Type=IPv4 |
| 4435 | Converter → eNB | S1AP | DownlinkNASTransport | (AMF→Converterのメッセージを転送, SHT=7: Reserved) |

**暗号化メッセージの推定:**
| Frame | 暗号化メッセージ | 推定内容 | 根拠 |
|-------|-----------------|---------|------|
| 4413 | 5GS Protected (SHT=2, SQN=1) | **Registration Accept (0x42)** | Frame 4415でTAU Acceptに変換されていることから。5G CoreはRegistration Requestに対してRegistration Acceptで応答 |
| 4430 | Ciphered (SHT=2, SQN=1) | **TAU Complete (0x4A)** | Frame 4432でRegistration Completeに変換されていることから |
| 4433 | 5GS Protected (SHT=2, SQN=2) | **Configuration Update Command (0x54)** または **DL NAS Transport** | Registration Complete後にCoreから送信される設定更新の可能性 |
| 4435 | NAS (SHT=7: Reserved) | **4433の転送** | 4433と同じNAS-PDU値、Converterが5G NASをそのまま転送（変換失敗または透過モード） |

**重要ポイント:**
- Frame 4415: **Converter が TAU Accept を含む InitialContextSetupRequest を eNB に送信**
- Frame 4427: eNB が **InitialContextSetupResponse** で成功を応答
- Frame 4432: **Registration complete** が AMF に正常到達
- Frame 4434: **PDU session establishment request** が送信される

---

### Phase 3: PDU Session 確立完了 (Frame 4540-4543)

| Frame | 方向 | Protocol | メッセージ | 詳細 |
|-------|------|----------|-----------|------|
| **4540** | **AMF → Converter** | **NGAP** | **InitialContextSetupRequest** | PDUSessionResourceSetupListCxtReq: PSI=5, Type=IPv4, DL/UL=1Gbps, **NAS-PDU含む (Protected)** |
| **4543** | **Converter → AMF** | **NGAP** | **InitialContextSetupResponse** | PDUSessionResourceSetupListCxtRes: 成功応答 |

**暗号化メッセージの推定:**
| Frame | 暗号化メッセージ | 推定内容 | 根拠 |
|-------|-----------------|---------|------|
| 4540 | NAS-PDU (Protected) | **DL NAS Transport (0x68) + PDU Session Establishment Accept (0xC2)** | InitialContextSetupRequest内のNAS-PDUはPDU Session確立の応答を含む |

**重要ポイント:**
- Frame 4540: AMF から **NGAP InitialContextSetupRequest** (PDU Session 設定含む) が到着
- Frame 4543: Converter から **InitialContextSetupResponse** で成功を応答
- **この時点で PDU Session が正常に確立**

---

## 成功フローの図解

```
eNB (4G)                    Converter (s1n2)                 AMF (5G Core)
   |                              |                               |
   |--- UL NAS (Ciphered) ------->|                               |   (4292)
   |                              |--- SMC Complete + Reg Req --->|   (4294)
   |                              |<-- UEContextReleaseCommand ---|   (4295)
   |                              |                               |
   |         ... (timeout/retry period) ...                       |
   |                              |                               |
   |                              |<-- DL NAS (Protected) --------|   (4413)
   |<-- ICS Request + TAU Accept -|                               |   (4415)
   |--- UE Capability Info ------>|                               |   (4425)
   |--- ICS Response ------------>|                               |   (4427)
   |--- UL NAS (TAU Complete) --->|                               |   (4430)
   |                              |--- Registration Complete ---->|   (4432)
   |                              |<-- DL NAS (Config Update?) ---|   (4433)
   |                              |--- PDU Session Est Req ------>|   (4434)
   |<-- DL NAS -------------------|                               |   (4435)
   |                              |                               |
   |         ... (PDU Session setup processing) ...               |
   |                              |                               |
   |                              |<-- NGAP ICS Req (PDU Sess) ---|   (4540)
   |                              |--- NGAP ICS Resp (Success) -->|   (4543)
   |                              |                               |
   |============= PDU SESSION ESTABLISHED (ping OK) ==============|
```

---

## 重要な成功要因

1. **TAU Accept (0x49) の使用**
   - Frame 4415 では `Attach Accept (0x42)` ではなく `TAU Accept (0x49)` が使用されている
   - これにより UE は既存のセキュリティコンテキストを維持しつつ接続を確立

2. **InitialContextSetupRequest/Response の成功**
   - Frame 4415 (S1AP ICS Request) → Frame 4427 (S1AP ICS Response) が正常完了
   - Frame 4540 (NGAP ICS Request) → Frame 4543 (NGAP ICS Response) が正常完了

3. **Registration Complete (0x43) の正常送信**
   - Frame 4432 で Converter → AMF に `Registration complete` が送信される
   - これが AMF に到達し、PDU Session 設定が開始される

4. **PDU Session Establishment Request の送信**
   - Frame 4434 で `UL NAS transport (0x67)` + `PDU session establishment request (0xC1)` が送信
   - PSI=5, Type=IPv4

5. **NGAP InitialContextSetupRequest (PDU Session) の受信と応答**
   - Frame 4540 で AMF から PDU Session 設定を含む NGAP ICS Request を受信
   - Frame 4543 で成功応答を返す
   - **この段階でデータプレーンが確立**

---

## 失敗時との比較ポイント (要調査)

失敗時の PCAP (`20251202_17.pcap`) と比較する際は、以下の点に注目:

1. Frame 4292 相当の UL NAS が存在するか
2. Frame 4294 相当の Security Mode Complete + Registration Request が送信されているか
3. **Frame 4415 相当の TAU Accept が送信されているか (Attach Accept ではないか)**
4. Frame 4427 相当の InitialContextSetupResponse が返されているか
5. Frame 4432 相当の Registration Complete が送信されているか
6. Frame 4434 相当の PDU Session Establishment Request が送信されているか
7. **Frame 4540 相当の NGAP InitialContextSetupRequest (PDU Session) が到着しているか**
8. **Frame 4543 相当の InitialContextSetupResponse が返されているか**
