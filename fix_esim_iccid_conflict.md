# eSIM ICCID衝突エラーの解決方法

## エラー内容
```
installFailedDueToIccidAlreadyExistsOnEuicc
```

このエラーは、Pixel内のeUICCに同じICCIDのプロファイルが既に存在することを意味します。

---

## 解決手順

### 方法A: Pixel設定画面から削除（推奨）

1. **設定を開く**
   ```
   設定 → ネットワークとインターネット → SIM
   ```

2. **すべてのeSIMプロファイルを確認**
   - アクティブなプロファイル
   - 無効化されているプロファイル（グレーアウトしているもの）

3. **該当するeSIMプロファイルを削除**
   ```
   プロファイル名（例: sXGP_5G）をタップ
   → 「SIMを削除」または「プロファイルを削除」
   ```

4. **無効化されたプロファイルも削除**
   - 「使用していないSIM」「無効」と表示されているものも含めてすべて削除

5. **端末を再起動**
   ```
   電源ボタン → 再起動
   ```

---

### 方法B: adbコマンドで確認・削除（詳細確認用）

#### 1. 現在のeUICCプロファイル一覧を確認

```bash
# PCとPixelをUSB接続
adb devices

# eUICCの状態を確認
adb shell dumpsys euicc

# プロファイル一覧を見やすく表示
adb shell dumpsys euicc | grep -A 10 "Profile:"
adb shell dumpsys euicc | grep -i iccid
```

**出力例:**
```
Profile: nickname=sXGP_5G, iccid=898100000000000009, state=ENABLED
Profile: nickname=old_profile, iccid=898100000000000009, state=DISABLED
```

→ **同じICCID（898100000000000009）が複数表示される場合、これが原因**

#### 2. プロファイルIDを確認

```bash
adb shell dumpsys euicc | grep -E "(Profile:|profileId:|iccid:)"
```

**出力例:**
```
profileId: 1
iccid: 898100000000000009
nickname: sXGP_5G
state: DISABLED
```

#### 3. プロファイルを削除（adb経由）

⚠️ **注意:** この方法は高度な操作です。通常は設定画面からの削除を推奨します。

```bash
# プロファイルを無効化
adb shell cmd euicc disable --portIndex 0 --iccid 898100000000000009

# プロファイルを削除
adb shell cmd euicc delete --portIndex 0 --iccid 898100000000000009
```

#### 4. 削除確認

```bash
adb shell dumpsys euicc | grep -i 898100000000000009
```

→ 何も表示されなければ削除成功

---

### 方法C: 新しいICCIDで再生成（最も確実）

既存プロファイルの削除が難しい場合、**別のICCIDで新しいプロファイルを作成**します。

#### 1. Simlesslyで新しいプロファイル作成

**新しいExcelファイル:**
```csv
ICCID,KI,OPC,IMSI
898100000000000012,8BAF473F2F8FD09487CCCBD7097C6862,8E27B6AF0E692E750F32667A3B14605D,001011234567898
```

**変更点:**
- ICCID: `898100000000000012` （最後の数字を変更）
- IMSI: `001011234567898` （最後の数字を変更）

#### 2. auth_keys.yamlとMongoDBを更新

**auth_keys.yaml:**
```yaml
  - imsi: "001011234567898"
    ki: "8baf473f2f8fd09487cccbd7097c6862"
    opc: "8e27b6af0e692e750f32667a3b14605d"
```

**MongoDB:**
```bash
docker exec -it mongo-s1n2 mongosh --eval "
  db = db.getSiblingDB('open5gs');
  db.subscribers.updateOne(
    {imsi: '001011234567898'},
    {\$set: {
      'security.k': '8baf473f2f8fd09487cccbd7097c6862',
      'security.opc': '8e27b6af0e692e750f32667a3b14605d',
      'security.op': null,
      'security.amf': '8000',
      'security.sqn': NumberLong(0)
    }},
    {upsert: true}
  )
"
```

#### 3. 新しいQRコードでインストール

---

## トラブルシューティング

### Q1: 設定画面にプロファイルが表示されない
**A:** adbで確認してください。無効化された「隠れたプロファイル」が残っている可能性があります。

```bash
adb shell dumpsys euicc | grep -A 5 "state=DISABLED"
```

### Q2: 削除できない
**A:** 端末を**セーフモード**で起動して削除を試してください。

```
1. 電源ボタン長押し
2. "電源を切る" を長押し
3. "セーフモードで再起動" を選択
4. セーフモードで設定 → SIM → プロファイル削除
5. 通常モードで再起動
```

### Q3: それでも削除できない
**A:** 端末の**ネットワーク設定をリセット**（⚠️ Wi-FiパスワードやBluetooth接続も消えます）

```
設定 → システム → リセット オプション → ネットワーク設定のリセット
```

---

## 推奨される手順（最短ルート）

### ✅ **最も簡単な方法（推奨）:**

1. **Pixel設定でeSIMを完全削除**
   - 設定 → ネットワークとインターネット → SIM
   - すべてのeSIMプロファイルを削除（アクティブ・非アクティブ両方）

2. **端末を再起動**

3. **新しいICCIDでプロファイル作成**
   - ICCID: `898100000000000012`（末尾を変更）
   - IMSI: `001011234567898`（末尾を変更）

4. **新しいQRコードでインストール**

---

これで確実に解決します！
