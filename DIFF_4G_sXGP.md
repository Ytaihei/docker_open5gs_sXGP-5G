# 4G構成 vs sXGP-5G構成 S1APシグナリング詳細比較

## 1. シグナリングフロー比較

### 4G構成（物理4G UE + 物理sXGP eNB + EPC）- 成功
| Step | Frame | Time(rel) | Direction | Message |
|------|-------|-----------|-----------|---------|
| 1 | 394 | 27.401 | eNB→MME | InitialUEMessage (Attach request) |
| 2 | 408 | 27.442 | MME→eNB | DownlinkNASTransport (Auth request) |
| 3 | 410 | 27.511 | eNB→MME | UplinkNASTransport (Auth response) |
| 4 | 411 | 27.512 | MME→eNB | DownlinkNASTransport (Security mode command) |
| 5 | 417 | 27.651 | eNB→MME | UplinkNASTransport (Security mode complete) |
| 6 | 428 | 27.706 | MME→eNB | DownlinkNASTransport (ESM information request) |
| 7 | 430 | 27.751 | eNB→MME | UplinkNASTransport (ESM information response) |
| 8 | 452 | 27.789 | MME→eNB | InitialContextSetupRequest (Attach accept) |
| 9 | 457 | 27.987 | eNB→MME | UECapabilityInfoIndication |
| 10 | 458 | 28.051 | eNB→MME | InitialContextSetupResponse |
| 11 | 460 | 28.052 | eNB→MME | UplinkNASTransport (Attach complete) |

### sXGP-5G構成（物理4G UE + 物理sXGP eNB + s1n2 + 5GC）- 失敗
| Step | Frame | Time(rel) | Direction | Message |
|------|-------|-----------|-----------|---------|
| 0 | 37 | 8.928 | eNB→s1n2 | S1SetupRequest |
| 0 | 41 | 8.935 | s1n2→eNB | S1SetupResponse |
| 1 | 223 | 29.759 | eNB→s1n2 | InitialUEMessage (Attach request) |
| 2 | 290 | 29.770 | s1n2→eNB | DownlinkNASTransport (Auth request) |
| 3 | 312 | 29.844 | eNB→s1n2 | UplinkNASTransport (Auth response) |
| 4 | 352 | 29.852 | s1n2→eNB | DownlinkNASTransport (Security mode command) |
| 5 | 370 | 29.884 | eNB→s1n2 | UplinkNASTransport (Security mode complete) |
| 6 | 482 | 29.910 | s1n2→eNB | DownlinkNASTransport |
| 7 | 592 | 30.114 | s1n2→eNB | InitialContextSetupRequest (Attach accept) |
| 8 | 605 | 30.325 | eNB→s1n2 | UECapabilityInfoIndication |
| 9 | 606 | 30.365 | eNB→s1n2 | InitialContextSetupFailure (Cause=26) |

## 2. シグナリングフロー差異

| 項目 | 4G構成（成功） | sXGP-5G構成（失敗） |
|------|----------------|---------------------|
| ESM Information Request/Response | ✅ 存在 (Frame 428, 430) | ❌ 欠落 |
| 追加のDownlinkNASTransport | ❌ なし | ✅ 存在 (Frame 482) |
| ICS Result | InitialContextSetupResponse | InitialContextSetupFailure (Cause=26) |

---

## 3. InitialUEMessage (Attach request) 詳細比較

### 3.1 S1AP層の差異

| フィールド | 4G構成 | sXGP-5G構成 | 差異 |
|-----------|--------|-------------|------|
| ENB-UE-S1AP-ID | 2 | 10 | ✅ 異なる（eNBが割り当てる値） |
| NAS-PDU Length | 111 bytes (0x6f) | 106 bytes (0x6a) | ⚠️ 5バイト差 |

### 3.2 NAS層の差異

| フィールド | 4G構成 | sXGP-5G構成 | 差異 |
|-----------|--------|-------------|------|
| **UE network capability Length** | **7 bytes** | **5 bytes** | ⚠️ **2バイト短い** |
| UE network capability (先頭5バイト) | `f0f0c04011 80` | `f0f0c04011 00` | ⚠️ 最後のバイトが異なる |
| Extended features (6-7バイト目) | `30 00` | (欠落) | ⚠️ **sXGP-5G側に存在しない** |
| **ESM message container Length** | **41 bytes (0x29)** | **44 bytes (0x2c)** | ⚠️ **3バイト長い** |
| ESM info transfer flag | 0xd1 | 0xd1 | ✅ 一致 |
| Protocol Config Options Length | 33 bytes (0x21) | 36 bytes (0x24) | ⚠️ 3バイト長い |
| PCO内容 - IPCP部分 | 含まれる | 含まれる | - |
| PCO内容 - 末尾追加データ | (なし) | 3バイト追加 | ⚠️ sXGP-5G側に追加データ |
| **Attach request末尾** | **`6f04f0007000`** | **(欠落)** | ⚠️ **6バイトがsXGP-5G側に欠落** |

### 3.3 NAS-PDU 16進数比較

#### 4G構成 (111 bytes)
```
07 41 72 08 09 10 10 21 43 65 87 59 07 f0 f0 c0
40 11 80 30 00 29 02 01 d0 11 d1 27 21 80 80 21
10 01 00 00 10 81 06 00 00 00 00 83 06 00 00 00
00 00 0d 00 00 0a 00 00 05 00 00 1a 01 05 c0 5c
10 04 31 04 65 b1 3e 05 90 11 03 57 58 a6 20 0a
61 14 04 e2 91 81 40 04 86 90 40 08 04 02 60 04
00 02 1f 02 5d 01 03 c1 6f 04 f0 00 70 00
```

#### sXGP-5G構成 (106 bytes)
```
07 41 72 08 09 10 10 21 43 65 87 59 05 f0 f0 c0
40 11 00 2c 02 01 d0 11 d1 27 24 80 80 21 10 01
00 00 10 81 06 00 00 00 00 83 06 00 00 00 00 00
0d 00 00 0a 00 00 05 00 00 10 00 00 1a 01 05 c0
5c 10 04 31 04 65 b1 3e 00 90 11 03 57 58 a6 20
0a 61 14 04 e2 91 81 40 04 86 90 40 08 04 02 60
04 00 02 1f 02 5d 01 03 c1
```

### 3.4 主要な差異まとめ

| 項目 | 詳細 | 影響 |
|------|------|------|
| UE network capability短縮 | 7→5バイト（末尾2バイト欠落） | 拡張機能情報の欠落 |
| ESM message container増加 | 41→44バイト（3バイト増加） | PCO内容の差異 |
| Attach request末尾データ欠落 | 6バイト `6f04f0007000` が欠落 | 不明なIE欠落 |

---

## 4. 各メッセージ詳細比較（続き）

（次セクション以降で残りのメッセージ比較を実施）

### 4.1 DownlinkNASTransport (Authentication request) 差異

| フィールド | 4G構成 | sXGP-5G構成 | 差異 |
|------------|--------|-------------|------|
| NAS key set identifier (KSI) | 0 | 1 | ⚠️ 異なる |
| RAND / AUTN | `ba c7 90 b7 ... 06 e5 / 10 40 93 e0 ... 07 6c 10` | `03 15 f2 51 ... 18 d5 / 10 66 b3 31 ... 27 78 a3` | ✅ 認証ベクター一式が異なる (別チャレンジ) |

（他フィールド長・全長は同じ 0x25=37 bytes ）

### 4.2 UplinkNASTransport (Authentication response) 差異

| フィールド | 4G構成 | sXGP-5G構成 | 差異 |
|------------|--------|-------------|------|
| ENB-UE-S1AP-ID | 2 | 10 | ⚠️ 異なる |
| Authentication response RES | `d8 a9 cf 0c c3 99 a5 7c` | `fe 9b 9b ec 8f 63 8f 47` | ⚠️ 異なる |

### 4.3 DownlinkNASTransport (Security mode command) 差異

| フィールド | 4G構成 | sXGP-5G構成 | 差異 |
|------------|--------|-------------|------|
| NAS key set identifier (KSI) | 0 | 1 | ⚠️ 異なる |
| NAS-PDU 末尾長/内容 | 長い: `... 07 5d 02 00 05 f0 f0 c0 40 18 c1 4f 08 36 ce fc f4 67 32 71 d6 6f 04 f0 00 70 00` | 短い: `... 07 5d 02 01 05 f0 f0 c0 40 11 c1` | ⚠️ sXGP-5G側は後続IEが短い（4G側に存在する末尾フィールドが欠落） |

### 4.4 UplinkNASTransport (Security mode complete) 差異

| フィールド | 4G構成 | sXGP-5G構成 | 差異 |
|------------|--------|-------------|------|
| ENB-UE-S1AP-ID | 2 | 10 | ⚠️ 異なる |
| NAS Security header MAC | `0x83fefc32` | `0x470e4211` | ⚠️ 異なる |

### 4.5 InitialContextSetupRequest (Attach accept, Activate default EPS bearer context request) 差異

| フィールド | 4G構成 | sXGP-5G構成 | 差異 |
|------------|--------|-------------|------|
| ENB-UE-S1AP-ID | 2 | 10 | ⚠️ 異なる |
| S1APフレーム長 | 306 bytes (Flow行) | 234 bytes (Flow行) | ⚠️ 長さが異なる |
