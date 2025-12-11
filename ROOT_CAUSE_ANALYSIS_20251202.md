# 根本原因分析: ping 途切れ問題 (2025/12/02)

## 概要

成功時 PCAP (`20251201_15.pcap`) と失敗時 PCAP (`20251202_17.pcap`) の比較、および失敗時ログ (`s1n2_follow_20251202_182802.log`) の分析により、根本原因を特定。

---

## 決定的な違い: InitialContextSetupRequest 内の NAS メッセージ

### PCAP 比較

| 項目 | 成功時 (Frame 4415) | 失敗時 (Frame 849) |
|------|---------------------|-------------------|
| **Security Header Type** | **0 (Plain)** | **2 (Integrity protected and ciphered)** |
| **NAS Message Type** | **TAU Accept (0x49)** | **Ciphered (不明)** |
| **UE の処理** | 平文で復号不要、正常処理 | 暗号化されており、復号に失敗する可能性 |

### ログ分析 (失敗時)

失敗時ログの該当箇所：

```
Line 657: [INFO] Converting 5G Registration Accept (0x42) -> 4G Attach Accept (0x42) [minimal]
Line 680: [DEBUG] 4G Attach Accept (integrity-wrapped) bytes head: 27 73 71 EA D8 01 ...
Line 682: [DEBUG] [ICS-TRIGGER] Detected encrypted Attach Accept (0x27, len=48)
Line 686: [INFO] [ICS] Detected integrity-wrapped Attach Accept; embedding protected NAS as-is (len=48) into ICS
```

**問題点:**
1. **メッセージタイプ**: `Attach Accept (0x42)` に変換 (成功時は `TAU Accept (0x49)`)
2. **暗号化状態**: `0x27` = SHT=2 (Ciphered) で送信 (成功時は SHT=0 Plain)

---

## 追加の問題: Frame 888 (SHT=7 Reserved)

### PCAP

失敗時 Frame 888 で Security Header Type = 7 (Reserved) という異常値が検出。

### ログ分析

```
Line 863: [WARN] 5G NAS message type 0x54 not supported for conversion
Line 864: [WARN] DownlinkNASTransport: 5G->4G NAS conversion failed, forwarding original NAS
```

**問題点:**
- 5G NAS メッセージ (Type 0x54 = 5GMM Status / Configuration Update) が変換できず
- **5G NAS がそのまま 4G UE に転送** → UE が解釈できず通信断

---

## 根本原因のまとめ

### 原因 1: NAS メッセージタイプの違い

| 条件 | 成功時 | 失敗時 |
|------|--------|--------|
| 5G → 4G 変換 | Registration Accept → **TAU Accept (0x49)** | Registration Accept → **Attach Accept (0x42)** |

**影響**: TAU Accept は既存のセキュリティコンテキストを維持するが、Attach Accept は新規確立を要求するため、UE の状態と不整合が発生する可能性。

### 原因 2: 暗号化状態の違い

| 条件 | 成功時 | 失敗時 |
|------|--------|--------|
| Security Header Type | **0 (Plain)** | **2 (Ciphered)** |
| UE の処理 | 復号不要 | 復号が必要だが鍵不整合の可能性 |

**影響**: 4G UE が暗号化された NAS を復号できない場合、メッセージを破棄し接続が失敗する。

### 原因 3: 5G NAS の透過転送

| 条件 | 成功時 | 失敗時 |
|------|--------|--------|
| Type 0x54 の処理 | (不明) | **そのまま転送** |

**影響**: 4G UE は 5G NAS を解釈できず、通信が途絶える。

---

## 修正方針

### 優先度 1: TAU Accept への変換

**対象ファイル**: `src/s1n2_converter.c`

現在:
```c
[INFO] Converting 5G Registration Accept (0x42) -> 4G Attach Accept (0x42) [minimal]
```

修正案:
```c
// 5G Registration Accept (0x42) を 4G TAU Accept (0x49) に変換
// TAU Accept は既存セキュリティコンテキストを維持するため、UE との整合性が取れる
```

### 優先度 2: Plain NAS での送信

**対象**: InitialContextSetupRequest 内の NAS-PDU

現在:
```c
[ICS] Detected integrity-wrapped Attach Accept; embedding protected NAS as-is
```

修正案:
- 暗号化された NAS を復号してから 4G TAU Accept を構築
- または、Plain NAS として送信するロジックを追加

### 優先度 3: Type 0x54 のハンドリング

**対象ファイル**: `src/s1n2_converter.c`

現在:
```c
[WARN] 5G NAS message type 0x54 not supported for conversion
[WARN] DownlinkNASTransport: 5G->4G NAS conversion failed, forwarding original NAS
```

修正案:
- Type 0x54 (5GMM Status / Configuration Update Command) を適切な 4G NAS に変換
- または、UE に影響を与えないよう破棄

---

## 参考: 成功時のシーケンス (Frame 4292-4551)

詳細は `SUCCESS_SEQUENCE_ANALYSIS_20251201_15.md` を参照。

重要なポイント:
1. Frame 4295 で **UEContextReleaseCommand** が発行され、コンテキストがリセット
2. Frame 4415 で **TAU Accept (0x49, Plain)** が送信
3. Frame 4432 で **Registration Complete** が正常到達
4. Frame 4540-4543 で **PDU Session** が確立

---

## 次のアクション

1. [ ] `src/s1n2_converter.c` で Registration Accept → TAU Accept 変換ロジックを確認・修正
2. [ ] Plain NAS 送信のトリガー条件を調査
3. [ ] Type 0x54 の変換ハンドラを追加
4. [ ] 修正後、再テストして PCAP を比較
