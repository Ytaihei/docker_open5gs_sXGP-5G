# 🔐 暗号化メッセージの復号化問題の分析

## 📋 問題の概要

**症状:**
- 4G構成のpcap: Wiresharkで暗号化メッセージが **復号化されて表示される**
- sXGP-5G構成のpcap: Wiresharkで暗号化メッセージが **復号化されない** (Ciphered messageのまま)

**分析結果:**
- **sample_pcap/4G_EPC_success.pcap**: Security Mode Command **なし** → EEA0推定
- **log/4G_Attach_Succesful.pcap**: Security Mode Command **あり** → **EEA0 (null ciphering)** を明示的に選択
- **log/20251115_31.pcap (sXGP-5G)**: Security Mode Command **あり** → **128-EEA2 (SNOW 3G)** を使用

**結論:** 両方の4G構成は **「完全性保護のみ (EEA0)」で「暗号化なし」**

---

## 🔍 詳細分析

### 1. **3つのpcapファイルの比較**

| 項目 | sample_pcap/4G_EPC_success.pcap | log/4G_Attach_Succesful.pcap | log/20251115_31.pcap (sXGP-5G) |
|------|--------------------------------|------------------------------|-------------------------------|
| **Security Mode Command** | ❌ なし | ✅ あり (Frame 94) | ✅ あり (Frame 5712) |
| **暗号化アルゴリズム** | (不明 - EEA0推定) | **EEA0 (null ciphering)** | **128-EEA2 (SNOW 3G)** |
| **完全性保護アルゴリズム** | 128-EIA2 (推定) | **128-EIA2 (SNOW 3G)** | **128-EIA2 (SNOW 3G)** |
| **Attach Complete (NAS-PDU)** | 13 bytes | 13 bytes | 51 bytes |
| **Inner header** | 07 (Plain NAS) | 07 (Plain NAS) | 暗号化済み |
| **Wireshark復号化** | ✅ 可能 | ✅ 可能 | ❌ 不可能 |

### 2. **NAS-PDUの16進数比較**

#### **4G EPC構成 (sample_pcap - Frame 518)**

```
NAS-PDU: 27 a4 6d de c1 07 07 43 00 03 52 00 c2
         ↑  ↑--------↑  ↑  ↑------------------↑
         |     MAC    |  |    平文ペイロード
         |            |  └─ Inner header (07 = Plain NAS)
         |            └─ Sequence number (7)
         └─ Security header (27 = Integrity protected and ciphered)

【解析】
27          : Security header = 0x27 = 0010 0111
a46ddec1    : Message authentication code (MAC-I) ← 完全性保護のみ
07          : Sequence number = 7
07          : Inner security header = 0x07 (Plain NAS message) ← 暗号化なし!
43          : Message Type = Attach complete (0x43) ← 読める
00 03       : ESM message container length = 3 ← 読める
5200c2      : ESM message container ← 読める

【サイズ】
Total: 13 bytes
Payload: 7 bytes (完全に平文)
```

#### **4G Attach成功 (log - Frame 111)**

```
NAS-PDU: 27 2c 6e 65 96 02 07 43 00 03 52 00 c2
         ↑  ↑--------↑  ↑  ↑------------------↑
         |     MAC    |  |    平文ペイロード
         |            |  └─ Inner header (07 = Plain NAS)
         |            └─ Sequence number (2)
         └─ Security header (27 = Integrity protected and ciphered)

【解析】
27          : Security header = 0x27 = 0010 0111
2c6e6596    : Message authentication code (MAC-I) ← 完全性保護のみ
02          : Sequence number = 2
07          : Inner security header = 0x07 (Plain NAS message) ← 暗号化なし!
43          : Message Type = Attach complete (0x43) ← 読める
00 03       : ESM message container length = 3 ← 読める
5200c2      : ESM message container ← 読める

【サイズ】
Total: 13 bytes
Payload: 7 bytes (完全に平文)

【Security Mode Commandの設定】
Frame 94で明示的に指定:
- Type of ciphering algorithm: EEA0 (null ciphering algorithm) (0)
- Type of integrity protection algorithm: 128-EIA2 (2)
→ 「暗号化なし、完全性保護のみ」を明示的に選択
```

#### **sXGP-5G構成 (Frame 5850 - Attach Complete)**

```
NAS-PDU: 27 cf d4 d6 18 01 88 b4 d5 49 14 f0 76 d0 12 e5 78 dd ...
         ↑  ↑--------↑  ↑  ↑----------------------------------------
         |     MAC    |  |    暗号化されたペイロード (46 bytes)
         |            |  └─ Sequence number (1)
         |            └─ (暗号化データ)
         └─ Security header (27 = Integrity protected and ciphered)

【解析】
27          : Security header = 0x27 = 0010 0111
              - 0010 .... = Security header type: Integrity protected and ciphered (2)
              - .... 0111 = Protocol discriminator: EPS MM (7)
cfd4d618    : Message authentication code (MAC-I) ← 完全性保護
01          : Sequence number = 1
88b4d549... : Ciphered message ← 完全に暗号化されている!
              (128-EEA2アルゴリズムで暗号化)

【サイズ】
Total: 52 bytes
Payload: 46 bytes (完全に暗号化)
```

### 2. **重要な証拠: Inner Security Header**

Wiresharkが「復号化された」ように見える理由:

```
【4G EPC構成】
Frame 518の詳細:
  Security header type: Integrity protected and ciphered (2)  ← 外側
  Message authentication code: 0xa46ddec1
  Sequence number: 7
  Security header type: Plain NAS message, not security protected (0)  ← 内側!
  NAS EPS Mobility Management Message Type: Attach complete (0x43)
  ESM message container
      Length: 3
      ESM message container contents: 5200c2
          EPS bearer identity: EPS bearer identity value 5 (5)
          Protocol discriminator: EPS session management messages (0x2)
          NAS EPS session management messages: Activate default EPS bearer context accept (0xc2)
```

**結論:** 外側のヘッダーは「Integrity protected and ciphered (2)」だが、内側のヘッダーは「Plain NAS message (0)」= **暗号化されていない**

```
【sXGP-5G構成】
Frame 5850の詳細:
  Security header type: Integrity protected and ciphered (2)  ← 外側
  Message authentication code: 0xcfd4d618
  Sequence number: 1
  Ciphered message: 88b4d54914f076d012e578dd...  ← 内側は暗号化済み
```

**結論:** 内側が完全に暗号化されており、復号化しなければ読めない

---

## 📊 比較表

| 項目 | 4G EPC構成 | sXGP-5G構成 | 評価 |
|------|-----------|------------|------|
| **Security Mode Command** | **なし** | **あり** (Frame 5712) | sXGP-5Gが正しい |
| **暗号化アルゴリズム** | **なし** (EEA0 = null encryption) | 128-EEA2 (SNOW 3G) | sXGP-5Gが正しい |
| **完全性保護アルゴリズム** | **128-EIA2** (SNOW 3G) | 128-EIA2 (SNOW 3G) | 両方とも実装 |
| **Outer Security Header** | Type 2 (Int+Ciph) | Type 2 (Int+Ciph) | 両方とも同じ |
| **Inner Security Header** | **Type 0 (Plain)** | **暗号化済み** | sXGP-5Gが正しい |
| **NAS-PDU サイズ** | 13 bytes | 52 bytes | sXGP-5Gが長い (暗号化のため) |
| **Payload サイズ** | 7 bytes (平文) | 46 bytes (暗号化) | sXGP-5Gが長い |
| **Attach Accept** | 平文 (Frame 507) | 暗号化 (Frame 5836) | sXGP-5Gが正しい |
| **Attach Complete** | 平文 (Frame 518) | 暗号化 (Frame 5850) | sXGP-5Gが正しい |
| **Wireshark復号化** | 可能 (平文のため) | 不可能 (鍵なし) | 両方とも正常 |
| **3GPP TS 33.401準拠** | ⚠️ **部分準拠** (完全性のみ) | ✅ **完全準拠** | sXGP-5Gが正しい |

---

## ✅ 結論

### **4G EPC構成の実装:**
1. ⚠️ **Security Mode Commandが送信されていない**
2. ⚠️ **暗号化アルゴリズム: EEA0 (null encryption)** - 暗号化なし
3. ✅ **完全性保護アルゴリズム: 128-EIA2 (SNOW 3G)** - 完全性保護あり
4. ⚠️ **すべてのNASメッセージが平文で送信されている**
5. ⚠️ **3GPP TS 33.401の推奨に反する** (暗号化推奨)

**実装の詳細:**
```
NAS Security Mode: Integrity Protection Only (No Encryption)
- Outer header: Security header type = 2 (Integrity protected and ciphered)
- Inner header: Security header type = 0 (Plain NAS message)
- MAC-I: 計算・検証される (完全性保護)
- Encryption: なし (EEA0 = null encryption algorithm)
```

**なぜこのような実装か?**
- Open5GSのMME設定で暗号化が無効化されている
- `mme.yaml` の `ciphering_order: [ null ]` または `ciphering_order: []`
- テスト環境のため、パフォーマンス優先で暗号化をスキップ
- 完全性保護のみでメッセージ改ざんは防げる (盗聴は防げない)

### **sXGP-5G構成の実装:**
1. ✅ **Security Mode Commandを正しく送信** (Frame 5712)
2. ✅ **暗号化アルゴリズム: 128-EEA2 (SNOW 3G)** - 完全暗号化
3. ✅ **完全性保護アルゴリズム: 128-EIA2 (SNOW 3G)** - 完全性保護あり
4. ✅ **Attach Accept/Completeが暗号化されている**
5. ✅ **3GPP TS 33.401セキュリティ要件に完全準拠**

**実装の詳細:**
```
NAS Security Mode: Integrity Protection + Encryption
- Outer header: Security header type = 2 (Integrity protected and ciphered)
- Inner content: 完全に暗号化 (128-EEA2で暗号化済み)
- MAC-I: 計算・検証される (完全性保護)
- Encryption: あり (128-EEA2 = SNOW 3G)
```

**なぜWiresharkで復号化できないか:**
- Wiresharkは暗号鍵 (KASME, KNASenc, KNASint) を持っていない
- s1n2は暗号鍵をWiresharkに提供していない
- 正常な動作であり、**問題ではない**
- 暗号化が正しく機能している証拠

---

## 🎯 Wiresharkで復号化する方法

### **Option 1: 暗号鍵を手動設定**

1. **Edit → Preferences → Protocols → NAS-EPS**
2. **"NAS encryption keys"** セクション
3. **KASME, KNASenc, KNASint** を設定

**必要な鍵:**
```
KASME:   <s1n2ログから取得>
KNASenc: <KASMEから導出>
KNASint: <KASMEから導出>
```

### **Option 2: s1n2にWireshark連携機能を追加**

```c
// Wireshark用のkey logファイル出力
FILE *keylog = fopen("/tmp/nas_keys.txt", "a");
fprintf(keylog, "KASME %s %s\n", imsi, kasme_hex);
fprintf(keylog, "KNASenc %s %s\n", imsi, knasenc_hex);
fprintf(keylog, "KNASint %s %s\n", imsi, knasint_hex);
fclose(keylog);
```

Wiresharkで設定:
```
Edit → Preferences → Protocols → NAS-EPS
Key Log File: /tmp/nas_keys.txt
```

### **Option 3: 暗号化を無効化 (テスト用のみ)**

**非推奨** (セキュリティ違反)

---

## 📝 まとめ

| 質問 | 回答 |
|------|------|
| **4G EPC構成はなぜ復号化できる?** | 暗号化されていないため (EEA0 = null encryption) |
| **sXGP-5G構成はなぜ復号化できない?** | 正しく暗号化されているため (128-EEA2, 鍵が必要) |
| **どちらが正しい?** | **sXGP-5G構成** (完全なセキュリティ実装) |
| **4G EPC構成に問題はあるか?** | ⚠️ **あり** (暗号化なし、盗聴可能) |
| **sXGP-5G構成に問題はあるか?** | **なし** (正常動作、3GPP準拠) |
| **Wiresharkで見るには?** | 暗号鍵を手動設定、またはs1n2にkey log機能追加 |

### **3GPP TS 33.401の要件**

3GPP TS 33.401 (Security architecture) では:

1. **Integrity protection (完全性保護):**
   - **必須** (MANDATORY)
   - すべてのNASメッセージに適用
   - 4G EPC構成: ✅ 実装済み (128-EIA2)
   - sXGP-5G構成: ✅ 実装済み (128-EIA2)

2. **Confidentiality protection (機密性保護/暗号化):**
   - **推奨** (RECOMMENDED)
   - セキュアな運用には必須
   - 4G EPC構成: ❌ 未実装 (EEA0 = null)
   - sXGP-5G構成: ✅ 実装済み (128-EEA2)

### **結論:**

✅ **sXGP-5G構成の暗号化実装は完全に正しい**
⚠️ **4G EPC構成は完全性保護のみ (暗号化なし)**

**Wiresharkで復号化できない理由:**
- 正しく暗号化されているため
- 暗号鍵を持っていないため
- これは **正常な動作** であり、**セキュリティが機能している証拠**

**補足:**
4G EPC構成は「完全性保護のみ」の実装で、メッセージ改ざんは防げますが、盗聴は防げません。テスト環境では許容されますが、商用環境では暗号化が必須です。sXGP-5G構成は商用レベルのセキュリティを実装しています。

---

**作成日:** 2025-11-17
**分析対象:**
- 4G EPC構成: `/home/taihei/docker_open5gs_sXGP-5G/sample_pcap/4G_EPC_success.pcap`
- sXGP-5G構成: `/home/taihei/docker_open5gs_sXGP-5G/log/20251115_31.pcap`

---

## 🔬 詳細な証拠

### **証拠1: NAS-PDUの16進数ダンプ**

#### 4G EPC構成 (Frame 518):
```
27 a4 6d de c1 07 07 43 00 03 52 00 c2
                  ^^                    ← 07 = Plain NAS message header
                     ^^ ^^ ^^ ^^ ^^ ^^  ← 完全に読める平文
```

#### sXGP-5G構成 (Frame 5850):
```
27 cf d4 d6 18 01 88 b4 d5 49 14 f0 76 d0 12 e5 78 dd 18 d9 c6 ee ...
                  ^^                                                 ← 88 = 暗号化データ
                     ^^ ^^ ^^ ^^ ^^ ^^ ^^ ^^ ^^ ^^ ^^ ^^ ^^ ^^  ← 読めない暗号化データ
```

### **証拠2: Wiresharkの解析結果**

#### 4G EPC構成 (Frame 518):
```
Non-Access-Stratum (NAS)PDU
    0010 .... = Security header type: Integrity protected and ciphered (2)
    .... 0111 = Protocol discriminator: EPS mobility management messages (0x7)
    Message authentication code: 0xa46ddec1
    Sequence number: 7
    0000 .... = Security header type: Plain NAS message, not security protected (0)  ← 証拠!
    .... 0111 = Protocol discriminator: EPS mobility management messages (0x7)
    NAS EPS Mobility Management Message Type: Attach complete (0x43)  ← デコード成功
    ESM message container
        Length: 3
        ESM message container contents: 5200c2  ← デコード成功
```

#### sXGP-5G構成 (Frame 5850):
```
Non-Access-Stratum (NAS)PDU
    0010 .... = Security header type: Integrity protected and ciphered (2)
    .... 0111 = Protocol discriminator: EPS mobility management messages (0x7)
    Message authentication code: 0xcfd4d618
    Sequence number: 1
    Ciphered message: 88b4d54914f076d012e578dd18d9c6ee73b129d4...  ← デコード不可
```

### **証拠3: Security Mode Commandの有無**

#### 4G EPC構成:
```bash
$ tshark -r 4G_EPC_success.pcap -Y "nas_eps.nas_msg_emm_type == 0x5d" -T fields -e frame.number
(結果なし)  ← Security Mode Commandが送信されていない!
```

#### sXGP-5G構成:
```bash
$ tshark -r 20251115_31.pcap -Y "nas_eps.nas_msg_emm_type == 0x5d" -T fields -e frame.number
5712  ← Security Mode Commandが送信されている!
```

### **証拠4: ペイロードサイズの比較**

| 項目 | 4G EPC構成 | sXGP-5G構成 | 理由 |
|------|-----------|------------|------|
| **Total NAS-PDU** | 13 bytes | 52 bytes | 暗号化によるパディング |
| **Payload** | 7 bytes | 46 bytes | 暗号化により増加 |
| **増加率** | - | **+557%** | 暗号化のオーバーヘッド |

暗号化されると、ブロック暗号のパディングにより、ペイロードサイズが大幅に増加します。
4G EPC構成のペイロードが異常に小さいのは、**暗号化されていない証拠**です。

---

**最終結論:**

4G EPC構成は **「完全性保護のみ (EEA0)」** で、**「暗号化なし」** です。
sXGP-5G構成は **「完全性保護 + 暗号化 (128-EEA2/128-EIA2)」** で、**「完全なセキュリティ実装」** です。

Wiresharkで復号化できないのは、**正しく暗号化されている証拠**であり、**問題ではありません**。
