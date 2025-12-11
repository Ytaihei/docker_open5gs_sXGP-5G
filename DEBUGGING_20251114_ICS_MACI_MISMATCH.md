# 4G Attach失敗デバッグ記録 (2025年11月14日)

## 問題の概要

### 初期状態
5G Registration Requestを送信すると、NAS Security Mode Rejectが発生し認証が完了しない状態。

### 現在の状態
NAS Security Mode Completeまでは成功するが、Initial Context Setup (ICS)が失敗。
- ICS Failure原因: Cause=26 (failure-in-radio-interface-procedure)
- eNB syslogに「**MAC-I does not match!!!!**」エラー
  - Recv_MACI = 0x0 (UEから受信)
  - Cal_MACI = 0x7451c8e4 (eNBが計算)

---

## 本日の取り組み

### 問題1: NAS Security Mode Reject (解決済み)

#### 仮説
5G Registration Requestから4G Attach Requestへの変換時に、4G nativeキー導出パスが正しく動作していない可能性。

#### 調査結果
- 5G→4G変換時、常に5G-AKAパス（KAUSF→KAMF→KASME）を使用していた
- 4G native UEは5G鍵（KAUSF/KAMF）を持たないため、CK/IKから直接KASME導出が必要
- ABBAフィールドの有無で5G-AKAか4G nativeかを判別すべき

#### 実施した修正
**ファイル**: `src/s1n2_converter.c`

ICS作成時のKASME/KeNB導出ロジックを修正：
```c
// ABBA有無で分岐
if (ue_map->abba_len == 2) {
    // 5G-AKAパス: KAUSF→KAMF→KASME→KeNB
    s1n2_kdf_kasme_from_kausf(kausf, ue_map->sqn_xor_ak, ue_map->abba, kasme);
} else {
    // 4G nativeパス: CK/IK→KASME→KeNB
    s1n2_kdf_kasme(ck, ik, ue_map->sqn_xor_ak, plmn, kasme);
}
```

類似の導出箇所3箇所すべてに同様の修正を適用。

#### 結果
- ✅ NAS Security Mode Complete成功
- ✅ 4G native鍵導出パスが正常動作
- ✅ KASME由来の鍵（K_NASenc/K_NASint）が正しく機能

---

### 問題2: Initial Context Setup Failure (未解決)

#### 現象
NAS Security Mode Complete後、ICSが失敗。
- eNBがRRC Security Mode Commandを送信
- UEがMAC-I=0x0を返信（計算失敗または未計算）
- eNBが期待するMAC-I=0x7451c8e4と不一致
- RRC Security Mode失敗 → ICS Failure

#### 鍵導出の状態
```
KASME導出: ✅ 成功 (NAS Security Mode Completeが成功)
   ↓
KeNB導出:  ❓ 不明 (s1n2側は正常だがUE側が不明)
   ↓
K_RRCint:  ❌ 失敗 (UEがMAC-I=0x0を送信)
```

#### 仮説と検証

**仮説1: PLMN ID不一致**
- KeNB導出にPLMN IDが必要
- s1n2とUEで異なるPLMN値を使用している可能性

**検証内容**:
1. PLMN TBCDエンコーディング確認（3GPP TS 24.008）
   - MCC=001, MNC=01 → `0x00 0xF1 0x10`

2. Open5GS MME実装確認
   - `ogs-kdf.c`: バイナリPLMN (3バイト) 使用を確認
   - s1n2実装と一致

3. 設定値確認
   - s1n2環境変数: MCC=001, MNC=01
   - eNB設定: PLMNID=00101
   - s1n2キャッシュ: PLMN=00F110
   - すべて一致

**結論**: PLMN設定に問題なし

**仮説2: NAS_COUNT不一致** (未検証)
- KeNB = KDF(KASME, NAS_COUNT)
- s1n2とUEで異なるCOUNT値を使用？

**仮説3: セキュリティアルゴリズム不一致** (未検証)
- ICSで指定したアルゴリズムとUEの期待値が異なる？

**仮説4: UE実装問題** (可能性高)
- 4G native認証からのKeNB導出に未対応
- KeNB導出実装バグ

---

## 次のステップ

### 優先度: HIGH
1. **NAS_COUNT値の検証**
   - ICS時のCOUNT値をログ出力
   - Security Mode Complete時のCOUNTと一致するか確認

2. **セキュリティアルゴリズム確認**
   - ICSで送信したUESecurityCapabilities
   - 選択されたアルゴリズム (EIA/EEA)
   - UEの期待値と一致するか

3. **UE側ログの詳細確認**
   - KeNB導出処理のログ
   - RRC Security Mode Command受信確認
   - エラーメッセージ

### 優先度: MEDIUM
4. **pcap詳細分析**
   - ICS SecurityKey IEの内容 (KeNB値)
   - RRC Security Mode Commandの内容
   - UESecurityCapabilitiesの内容

5. **代替UEでのテスト**
   - 既知の動作する4G UEでの動作確認
   - 本UEの4G native対応状況の切り分け

---

## 技術メモ

### 鍵導出チェーン（4G native）
```
[s1n2/HSS]
  Ki + OPC + RAND
    ↓ Milenage f2-f5
  RES, CK, IK, AK
    ↓ KDF (FC=0x10, P0=PLMN, P1=SQN⊕AK)
  KASME (32 bytes)
    ↓ KDF (FC=0x11, P0=NAS_COUNT)
  KeNB (32 bytes)
    ↓ KDF (FC=0x15, P0=Algorithm)
  K_NASenc, K_NASint, K_RRCenc, K_RRCint
```

### ABBA判定ロジック
```c
if (ue_map->abba_len == 2) {
    // 5G-AKA: Authentication Requestに5G ABBA含む
    // パス: KAUSF → KAMF → KASME
} else {
    // 4G native: ABBA無し
    // パス: CK/IK → KASME
}
```

### MAC-I計算
```
MAC-I = AES-CMAC(K_RRCint, COUNT || BEARER || DIRECTION || MESSAGE)
- K_RRCint: KeNBから導出
- Algorithm: EIA1/EIA2/EIA3
```

---

## まとめ

### 解決した問題
- ✅ **NAS Security Mode Reject**: 4G native鍵導出パスを実装し解決
- ✅ ABBA有無による5G-AKA/4G native判定ロジック実装
- ✅ KASME導出が正常動作（NAS暗号化/完全性保護成功）

### 未解決の問題
- ❌ **RRC Security Mode失敗**: UEがMAC-I=0x0を送信
- ❓ KeNB導出の正否不明（s1n2側は正常、UE側不明）
- ❓ UEの4G native KeNB導出対応状況不明

### 次回の調査方針
1. NAS_COUNT値の一致確認
2. セキュリティアルゴリズム選択の検証
3. UE側ログの詳細分析
4. 必要に応じて代替UEでの動作確認

---

**作成日**: 2025年11月14日
**最終更新**: 2025年11月14日
**状態**: ICS失敗原因調査中
**ビルド状態**: ✅ 正常
