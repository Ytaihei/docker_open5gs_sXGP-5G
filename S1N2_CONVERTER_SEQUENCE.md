# S1N2 Converter プロトコル変換シーケンス

## 概要

S1N2 Converter は、4G LTE eNB (S1AP) と 5G Core (NGAP) 間のプロトコル変換を行うゲートウェイです。sXGP (1.9GHz 帯 LTE) の eNB を 5G SA コアネットワーク (Open5GS) に接続することを可能にします。

### 用語解説

| 用語 | 正式名称 | 説明 |
|------|---------|------|
| **eNB** | evolved Node B | 4G LTE の基地局。UE (端末) と無線通信を行う。 |
| **gNB** | next generation Node B | 5G NR の基地局。S1N2 では eNB を仮想的に gNB として見せる。 |
| **AMF** | Access and Mobility Management Function | 5G コアの接続・モビリティ管理機能。4G の MME に相当。 |
| **UPF** | User Plane Function | 5G コアのユーザーデータ転送機能。4G の S-GW/P-GW に相当。 |
| **S1AP** | S1 Application Protocol | eNB と MME 間の制御プロトコル (4G)。 |
| **NGAP** | NG Application Protocol | gNB と AMF 間の制御プロトコル (5G)。 |
| **NAS** | Non-Access Stratum | UE とコアネットワーク間の制御メッセージ。認証・セキュリティ等を担当。 |
| **GTP-U** | GPRS Tunneling Protocol - User plane | ユーザーデータを転送するトンネリングプロトコル。 |
| **SCTP** | Stream Control Transmission Protocol | 制御プレーン (S1AP/NGAP) で使用する信頼性のあるトランスポート。 |
| **TEID** | Tunnel Endpoint Identifier | GTP トンネルを識別する ID。送受信ペアで通信経路を特定。 |

### ネットワーク構成

```
┌─────────────┐     S1AP/SCTP      ┌──────────────┐     NGAP/SCTP      ┌─────────────┐
│   eNB       │◄──────────────────►│ S1N2         │◄──────────────────►│   AMF       │
│172.24.0.111 │     Port 36412     │ Converter    │     Port 38412     │172.24.0.12  │
│             │                    │ 172.24.0.30  │                    │             │
└─────────────┘                    └──────────────┘                    └─────────────┘
       │                                  │                                   │
       │         GTP-U/UDP               │          GTP-U/UDP               │
       │         Port 2152               │          Port 2152               │
       ▼                                  ▼                                   ▼
┌─────────────┐                    ┌──────────────┐                    ┌─────────────┐
│   eNB       │◄──────────────────►│ S1N2         │◄──────────────────►│   UPF       │
│(S1-U側)     │                    │ (GTP Proxy)  │                    │172.24.0.21  │
└─────────────┘                    └──────────────┘                    └─────────────┘
```

## 1. eNB 接続シーケンス (S1 Setup)

**目的**: eNB (基地局) が起動時にコアネットワークへ接続を確立する手順です。これにより、eNB は UE (端末) からの接続要求をコアネットワークへ転送できるようになります。

**なぜ必要か**: 基地局とコアネットワークが互いの存在を認識し、対応するエリア情報 (TAC: Tracking Area Code) やセキュリティ機能を交換する必要があるためです。

### フロー

```
eNB                      S1N2 Converter                    AMF
 │                              │                            │
 │  S1SetupRequest (S1AP)       │                            │
 │ ─────────────────────────────►                            │
 │  proc=17, Global-ENB-ID,     │                            │
 │  SupportedTAs, ENBname       │                            │
 │                              │                            │
 │                              │  NGSetupRequest (NGAP)     │
 │                              │ ───────────────────────────►
 │                              │  proc=21, Global-gNB-ID,   │
 │                              │  SupportedTAList, RANname  │
 │                              │                            │
 │                              │  NGSetupResponse (NGAP)    │
 │                              │ ◄───────────────────────────
 │                              │  AMF Name, Served GUAMIs,  │
 │                              │  PLMN Support List         │
 │                              │                            │
 │  S1SetupResponse (S1AP)      │                            │
 │ ◄─────────────────────────────                            │
 │  MME Name, ServedGUMMEIs,    │                            │
 │  RelativeMMECapacity         │                            │
```

### 変換内容

| S1AP パラメータ | NGAP パラメータ | 意味・目的 | 変換ロジック |
|----------------|----------------|-----------|---------------|
| Global-ENB-ID | Global-gNB-ID | **基地局の一意識別子**。PLMN (通信事業者ID) + 基地局番号で構成。ネットワーク内で基地局を特定する。 | PLMN IDはそのままコピー。<br>eNB-ID (20bit) は gNB-ID (22-32bit) に左詰めまたはパディングしてマッピング。 |
| SupportedTAs | SupportedTAList | **対応エリア情報**。この基地局がカバーする Tracking Area (位置登録エリア) のリスト。UE の位置管理に使用。 | TACはそのままコピー。<br>Broadcast PLMNs は S1AP のリストを NGAP の BroadcastPLMNItem に変換。 |
| ENBname | RANNodeName | **基地局の名前**。運用管理用の識別名 (例: "eNB-Tokyo-01")。 | 文字列をそのままコピー (UTF-8)。 |
| PagingDRX | DefaultPagingDRX | **ページング周期**。Idle 状態の UE を呼び出す間隔。省電力と応答速度のバランスを決定。 | Enum値を 1:1 でマッピング (v32 -> v32, v64 -> v64 等)。 |

## 2. UE アタッチシーケンス (Registration)

**目的**: UE (端末) がネットワークに接続し、通信サービスを利用開始するための手順です。「電源ON後に圏内に入る」「機内モード解除後」などに実行されます。

**なぜ必要か**:
- ネットワークが UE を識別・認証する (不正端末の排除)
- UE にIPアドレスを割り当てる
- 通信経路 (ベアラ) を確立する
- 位置登録を行い、着信時に UE を見つけられるようにする

### フロー

```
UE        eNB                S1N2 Converter                AMF
 │         │                        │                        │
 │ RRC     │                        │                        │
 │ ────────►                        │                        │
 │         │                        │                        │
 │         │ InitialUEMessage(S1AP) │                        │
 │         │ ────────────────────────►                        │
 │         │ proc=12                │                        │
 │         │ NAS: Attach Request    │                        │
 │         │ (EPS Mobile Identity,  │                        │
 │         │  PDN Connectivity Req) │                        │
 │         │                        │                        │
 │         │                        │ InitialUEMessage(NGAP) │
 │         │                        │ ────────────────────────►
 │         │                        │ proc=15                │
 │         │                        │ NAS: Registration Req  │
 │         │                        │ (5G-GUTI/SUCI,         │
 │         │                        │  UE Security Cap)      │
 │         │                        │                        │
```

### NAS メッセージ変換 (4G → 5G)

**NAS (Non-Access Stratum)** は、UE とコアネットワーク間で直接やり取りされる制御メッセージです。基地局は中身を解釈せず透過的に転送しますが、S1N2 Converter は 4G NAS ⇔ 5G NAS の変換を行います。

| 4G EPS NAS | 5G NAS | 意味・目的 | 変換ロジック |
|------------|--------|-----------|--------------|
| Attach Request (0x41) | Registration Request (0x41) | **接続要求**。UE がネットワークへの接続を開始する最初のメッセージ。 | メッセージタイプは同一 (0x41)。<br>EPS Attach Type -> 5GS Registration Type (Initial)。 |
| IMSI (EPS Mobile Identity) | SUCI (5GS Mobile Identity) | **端末識別子**。SIM カードに記録された世界で一意の番号 (15桁)。加入者を特定する。 | **IMSI -> SUCI 変換**: <br>Protection Scheme = 0 (Null)<br>Home Network Public Key ID = 0<br>MCC/MNC + MSIN をそのまま格納。 |
| UE Network Capability | UE Security Capability | **対応セキュリティ機能**。UE が対応する暗号化・完全性保護アルゴリズムのリスト。 | **アルゴリズムビットマップ変換**: <br>EEA0 -> NEA0<br>128-EEA1 -> 128-NEA1<br>128-EEA2 -> 128-NEA2<br>128-EIA1 -> 128-NIA1<br>128-EIA2 -> 128-NIA2 |
| PDN Connectivity Request | (Pending) | **データ接続要求**。インターネット接続用の IP アドレス割り当てを要求。 | Registration Request には含めず、Registration Complete 後に<br>PDU Session Establishment Request として送信するためにフラグをセット。 |
| ESM Message Container | (Dropped) | **セッション管理コンテナ**。4G固有の形式のため 5G では不要。 | Registration Request では使用しないため削除。 |

## 3. 認証シーケンス

**目的**: UE が正規の加入者であることを確認し、不正端末のネットワーク利用を防止します。同時に、通信を暗号化するための鍵を生成します。

**なぜ必要か**:
- **相互認証**: ネットワークが UE を認証するだけでなく、UE もネットワークが正規であることを確認 (偽基地局対策)
- **鍵共有**: 盗聴・改ざん防止のため、UE とネットワークが同じ暗号鍵を安全に共有する
- **リプレイ攻撃防止**: 過去の認証情報を再利用した攻撃を防ぐ (SQN: シーケンス番号で管理)

### フロー

```
UE        eNB                S1N2 Converter                AMF
 │         │                        │                        │
 │         │                        │ DL NASTransport(NGAP)  │
 │         │                        │ ◄────────────────────────
 │         │                        │ NAS: Auth Request      │
 │         │                        │ (RAND, AUTN, ngKSI)    │
 │         │                        │                        │
 │         │ DL NASTransport(S1AP)  │                        │
 │         │ ◄────────────────────────                        │
 │         │ proc=11                │                        │
 │         │ NAS: Auth Request      │                        │
 │         │ (RAND, AUTN, eKSI)     │                        │
 │         │                        │                        │
 │ Auth    │                        │                        │
 │ ◄────────                        │                        │
 │         │                        │                        │
 │ RES     │                        │                        │
 │ ────────►                        │                        │
 │         │                        │                        │
 │         │ UL NASTransport(S1AP)  │                        │
 │         │ ────────────────────────►                        │
 │         │ proc=13                │                        │
 │         │ NAS: Auth Response     │                        │
 │         │ (RES)                  │                        │
 │         │                        │                        │
 │         │                        │ UL NASTransport(NGAP)  │
 │         │                        │ ────────────────────────►
 │         │                        │ proc=46                │
 │         │                        │ NAS: Auth Response     │
 │         │                        │ (RES*)                 │
```

### 認証パラメータ変換

| 4G パラメータ | 5G パラメータ | 意味・目的 | 変換ロジック |
|--------------|--------------|-----------|--------------|
| RAND (16 bytes) | RAND (16 bytes) | **乱数チャレンジ**。ネットワークが生成するランダム値。UE はこれを使って応答を計算。毎回異なる値で盗聴・リプレイを防止。 | そのままコピー。内部キャッシュに保存 (RES*計算用)。 |
| AUTN (16 bytes) | AUTN (16 bytes) | **認証トークン**。ネットワークの正当性を UE が検証するための情報 (SQN, MAC 等を含む)。偽基地局対策。 | そのままコピー。内部キャッシュに保存。 |
| eKSI (3 bits) | ngKSI (4 bits) | **鍵セット識別子**。複数のセキュリティコンテキストを管理する番号。同じ鍵を再利用する際に参照。 | 下位3ビットをマッピング。TSC=0 (Native security context)。 |
| RES (4-16 bytes) | RES* (16 bytes) | **認証応答**。UE が秘密鍵 (Ki) と RAND を使って計算した値。正しい値ならば認証成功。 | **RES* 計算ロジック**: <br>1. 4G RES, RAND, AUTN, SQN^AK (キャッシュ) を使用。<br>2. `s1n2_auth_compute_res_star_with_imsi` 関数で計算。<br>3. 4G RES から 5G RES* を導出 (KDF使用)。 |

### 鍵導出 (Key Derivation)

**鍵導出とは**: 認証成功後、通信を保護するための複数の暗号鍵を生成するプロセスです。1つの元鍵から KDF (Key Derivation Function) を使って目的別の鍵を導出します。

S1N2 Converter は、認証成功時に以下の鍵を内部で導出・保持します。

1. **共通鍵**: `CK` (Cipher Key: 暗号化用), `IK` (Integrity Key: 完全性保護用) - Milenage アルゴリズム等で計算
2. **4G 鍵階層**:
   - `K_ASME` (Access Security Management Entity Key): MME との通信を保護するマスター鍵
   - `K_NAS_int` (NAS Integrity Key): NAS メッセージの改ざん検出用
   - `K_NAS_enc` (NAS Encryption Key): NAS メッセージの暗号化用
   - `KeNB` (eNB Key): 基地局との無線通信を保護する鍵 (Security Mode Complete 後に導出)
3. **5G 鍵階層**:
   - `K_ausf` (AUSF Key): 認証サーバー用の鍵
   - `K_seaf` (SEAF Key): セキュリティアンカー機能用の鍵
   - `K_amf` (AMF Key): AMF との通信を保護するマスター鍵
   - `K_NAS_int_5g`, `K_NAS_enc_5g`: 5G NAS メッセージ保護用の鍵

## 4. セキュリティモードシーケンス

**目的**: 認証で生成した鍵を使って、実際の通信保護を開始するための手順です。どの暗号化・完全性保護アルゴリズムを使うかをネットワークが決定し、UE に通知します。

**なぜ必要か**:
- **アルゴリズム合意**: UE とネットワークの双方が対応するアルゴリズムの中から最適なものを選択
- **セキュリティ開始点の同期**: どのメッセージから暗号化を開始するかを明確にする
- **IMEISV 取得**: 端末の製造番号 (改ざん検知、盗難端末ブロック等に利用)

### フロー

```
UE        eNB                S1N2 Converter                AMF
 │         │                        │                        │
 │         │                        │ DL NASTransport(NGAP)  │
 │         │                        │ ◄────────────────────────
 │         │                        │ NAS: Security Mode Cmd │
 │         │                        │ (Selected NAS Security │
 │         │                        │  Algorithm, ngKSI)     │
 │         │                        │                        │
 │         │ DL NASTransport(S1AP)  │                        │
 │         │ ◄────────────────────────                        │
 │         │ NAS: Security Mode Cmd │                        │
 │         │ (Selected NAS Security │                        │
 │         │  Algorithm, eKSI)      │                        │
 │         │                        │                        │
 │ SMC     │                        │                        │
 │ ◄────────                        │                        │
 │         │                        │                        │
 │ SMC Cmp │                        │                        │
 │ ────────►                        │                        │
 │         │                        │                        │
 │         │ UL NASTransport(S1AP)  │                        │
 │         │ ────────────────────────►                        │
 │         │ NAS: Security Mode Cmp │                        │
 │         │ (IMEISV, NAS MAC)      │                        │
 │         │                        │                        │
 │         │                        │ UL NASTransport(NGAP)  │
 │         │                        │ ────────────────────────►
 │         │                        │ NAS: Security Mode Cmp │
 │         │                        │ (IMEISV)               │
```

### セキュリティアルゴリズムマッピング

**暗号化アルゴリズム (EEA/NEA)**: データの内容を第三者から隠すための暗号化方式
**完全性保護アルゴリズム (EIA/NIA)**: データが改ざんされていないことを検証するための方式

| 4G アルゴリズム (S1AP/NAS) | 5G アルゴリズム (NGAP/NAS) | 説明 | 変換ロジック |
|----------------|----------------|------|--------------|
| EEA0 (NULL) | NEA0 (NULL) | 暗号化なし (テスト・デバッグ用) | 0x00 <-> 0x00 |
| 128-EEA1 (SNOW3G) | 128-NEA1 (SNOW3G) | ストリーム暗号 (3GPP 標準) | 0x01 <-> 0x01 |
| 128-EEA2 (AES) | 128-NEA2 (AES) | AES ブロック暗号 (最も一般的) | 0x02 <-> 0x02 |
| 128-EIA1 (SNOW3G) | 128-NIA1 (SNOW3G) | SNOW3G ベース完全性保護 | 0x01 <-> 0x01 |
| 128-EIA2 (AES) | 128-NIA2 (AES) | AES-CMAC ベース完全性保護 (最も一般的) | 0x02 <-> 0x02 |

### Security Mode Complete 変換 (4G → 5G)

**Security Mode Complete** は、UE がセキュリティ設定を受け入れたことを通知する応答メッセージです。

1. **NAS Message Container (IEI 0x71) の付与**:
   - キャッシュしておいた **Registration Request** (Initial UE Message で受信したもの) を、Security Mode Complete メッセージの `NAS Message Container` IE に格納します (Piggybacking)。
   - これにより、AMF はセキュリティ確立後に Registration Request の内容を検証できます。

2. **IMEISV 変換**:
   - 4G IEI `0x23` (Mobile Identity) を 5G IEI `0x77` (5GS Mobile Identity) に変換します。

3. **Integrity Protection (完全性保護)**:
   - 変換後の 5G NAS メッセージに対し、導出した `K_NAS_int_5g` を使用して MAC を計算します。
   - Security Header Type = 0x03 (Integrity Protected with New 5G Security Context) を付与して送信します。

## 5. Initial Context Setup シーケンス (PDU Session Establishment)

**目的**: 認証・セキュリティ確立後、実際にデータ通信を行うための「通信経路 (ベアラ/PDUセッション)」を確立する手順です。UE に IP アドレスが割り当てられ、インターネット通信が可能になります。

**なぜ必要か**:
- **IP アドレス割当**: UE がインターネットと通信するための IP アドレスを取得
- **QoS 設定**: 通信品質 (优先度、帯域制限等) を設定
- **トンネル確立**: データを転送するための GTP トンネル (TEID) を確立

S1N2 Converter は、4G の Attach 手順と 5G の PDU Session Establishment 手順のタイミングの違いを吸収するため、独自のシーケンスを採用しています。

### 独自シーケンスの特徴
1. **Registration Accept のインターセプト**: AMF からの Registration Accept を受信した時点で、PDU セッション確立を待たずに eNB へ `InitialContextSetupRequest` (Attach Accept 相当) を送信します。
2. **Early S1AP Setup**: この際、S1N2 は自身の GTP Proxy TEID を eNB に通知し、S1-U ベアラを先行して確立させます。
3. **遅延 PDU Session Establishment**: Registration Complete 送信後に、キャッシュしておいた PDN Connectivity Request を元に `PDU Session Establishment Request` を AMF へ送信します。
4. **TEID 更新**: その後 AMF から PDU Session Resource Setup を受信したタイミングで、UPF の TEID を学習し、GTP Proxy のマッピングを更新します。

### フロー詳細

```
UE        eNB                S1N2 Converter                AMF/SMF/UPF
 │         │                        │                        │
 │         │                        │ DL NASTransport(NGAP)  │
 │         │                        │ ◄────────────────────────
 │         │                        │ NAS: Registration Acc  │
 │         │                        │                        │
 │         │ InitialContextSetup    │                        │
 │         │ Request (S1AP)         │                        │
 │         │ ◄────────────────────────                        │
 │         │ proc=9                 │                        │
 │         │ NAS: Attach Accept     │                        │
 │         │ E-RAB ToBeSetup List   │                        │
 │         │ (S1N2 Proxy TEID)      │                        │
 │         │                        │                        │
 │ Bearer  │                        │                        │
 │ Setup   │                        │                        │
 │ ◄────────                        │                        │
 │         │                        │                        │
 │         │ InitialContextSetup    │                        │
 │         │ Response (S1AP)        │                        │
 │         │ ────────────────────────►                        │
 │         │ proc=9                 │                        │
 │         │ E-RAB Setup List       │                        │
 │         │ (eNB TEID, IP)         │                        │
 │         │                        │                        │
 │         │ UplinkNASTransport     │                        │
 │         │ (S1AP)                 │                        │
 │         │ ────────────────────────►                        │
 │         │ NAS: Attach Complete   │                        │
 │         │                        │                        │
 │         │                        │ UplinkNASTransport     │
 │         │                        │ (NGAP)                 │
 │         │                        │ ────────────────────────►
 │         │                        │ NAS: Registration Cmp  │
 │         │                        │                        │
 │         │                        │ UplinkNASTransport     │
 │         │                        │ (NGAP)                 │
 │         │                        │ ────────────────────────►
 │         │                        │ NAS: PDU Session Est   │
 │         │                        │ Request                │
 │         │                        │                        │
 │         │                        │ InitialContextSetup    │
 │         │                        │ Request (NGAP)         │
 │         │                        │ ◄────────────────────────
 │         │                        │ proc=14                │
 │         │                        │ PDU Session Resource   │
 │         │                        │ Setup Request          │
 │         │                        │ (UPF TEID)             │
 │         │                        │                        │
 │         │                        │ InitialContextSetup    │
 │         │                        │ Response (NGAP)        │
 │         │                        │ ────────────────────────►
 │         │                        │ proc=14                │
 │         │                        │ PDU Session Resource   │
 │         │                        │ Setup Response List    │
```

### ベアラ/PDU セッション変換

**ベアラ (E-RAB)** と **PDU セッション** は、それぞれ 4G と 5G における「データ通信経路」のことです。1つの UE が複数のベアラ/セッションを持つこともできます (例: インターネット用 + 音声通話用)。

| S1AP (E-RAB) | NGAP (PDU Session) | 意味・目的 | 変換ロジック |
|--------------|-------------------|-----------|--------------|
| E-RAB ID | PDU Session ID | **データ経路の識別番号**。複数ベアラを区別するための ID。 | ID マッピング (通常 5) |
| QCI | 5QI | **通信品質クラス**。優先度や遅延要件を定義 (9=インターネット, 1=音声等)。 | QCI → 5QI マッピング |
| ARP | ARP | **優先度レベル**。輻輳時にどのベアラを優先するかを決定。 | Priority Level 保持 |
| S1-U GTP TEID | N3 GTP TEID | **トンネル識別子**。データパケットを送受信する際の経路を特定。 | **S1N2 Proxy TEID** (初期) → **UPF TEID** (更新) |
| S1-U Transport Layer Address | N3 Transport Layer Address | **データ転送先 IP アドレス**。GTP-U パケットの宛先。 | IP アドレス変換 |

## 6. TAU (Tracking Area Update) シーケンス

**目的**: UE が移動したり、定期的に「まだ接続中であること」をネットワークに通知する手順です。着信時に UE を見つけられるように位置情報を更新します。

**なぜ必要か**:
- **位置管理**: UE がどの Tracking Area にいるかを管理し、着信時に正しいエリアで呼び出せるようにする
- **接続維持**: 定期的に TAU を送ることで、ネットワークが UE の存在を確認 (タイムアウト防止)
- **CS Fallback 対応**: Combined TA/LA 更新で 2G/3G の位置情報も同時に更新 (音声通話用)

UE が接続維持のために送信する TAU Request に対し、S1N2 Converter は **ローカルで TAU Accept を生成** して eNB に返却します（AMF へは転送しません）。

### フロー

```
UE        eNB                S1N2 Converter                AMF
 │         │                        │                        │
 │ TAU Req │                        │                        │
 │ ────────►                        │                        │
 │         │ UL NASTransport(S1AP)  │                        │
 │         │ ────────────────────────►                        │
 │         │ NAS: TAU Request       │                        │
 │         │ (EPS update type,      │                        │
 │         │  Old GUTI)             │                        │
 │         │                        │                        │
 │         │                        │ (ローカル処理)         │
 │         │                        │ TAU Accept 生成        │
 │         │                        │                        │
 │         │ DL NASTransport(S1AP)  │                        │
 │         │ ◄────────────────────────                        │
 │         │ NAS: TAU Accept        │                        │
 │         │ (EPS update result,    │                        │
 │         │  T3412 timer, TAI list)│                        │
 │         │                        │                        │
 │ TAU Acc │                        │                        │
 │ ◄────────                        │                        │
```

### TAU パラメータ変換

| 入力 (TAU Request) | 出力 (TAU Accept) | 意味・目的 | 変換ロジック |
|-------------------|-------------------|-----------|--------------|
| EPS Update Type (bits 1-3) | EPS Update Result | **更新種別**。TAのみ / TA+LA同時 / 定期更新 の別を示す。 | **Type → Result マッピング**: <br>Type 0 (TA updating) → Result 0<br>Type 1 (Combined TA/LA) → Result 1<br>Type 2 (Combined + IMSI attach) → Result 1<br>Type 3 (Periodic) → Result 0 |
| - | T3412 Timer | **定期 TAU タイマー**。次の定期 TAU を送るまでの時間 (アイドル時)。 | デフォルト値 0x29 (約9分) を設定。 |
| - | TAI List | **Tracking Area リスト**。TAU なしで移動できるエリアのリスト。 | キャッシュされた TAC/PLMN から生成。 |
| EPS Update Type = 1 or 2 | LAI (Location Area Identity) | **2G/3G 位置情報**。CS Fallback 用の Location Area。 | Combined TA/LA の場合のみ付与。 |
| - | EPS Bearer Context Status | **アクティブベアラ状態**。現在有効なベアラのビットマスク。 | アクティブベアラのビットマスクを付与 (IEI 0x57)。 |

### TAU Accept のビット構造 (重要)

```
+-------+-------+-------+-------+-------+-------+-------+-------+
| Octet 1: Protocol Discriminator (0x07 = EPS Mobility Management)
+-------+-------+-------+-------+-------+-------+-------+-------+
| Octet 2: Message Type (0x49 = TAU Accept)
+-------+-------+-------+-------+-------+-------+-------+-------+
| Octet 3: EPS Update Result
|   Bits 5-8: Spare (0)
|   Bits 1-3: EPS update result value (0=TA only, 1=Combined TA/LA)
+-------+-------+-------+-------+-------+-------+-------+-------+
| Octet 4: T3412 Timer value (e.g., 0x29 = 9 minutes)
+-------+-------+-------+-------+-------+-------+-------+-------+
| ...TAI List, LAI (optional), EPS Bearer Context Status...
+-------+-------+-------+-------+-------+-------+-------+-------+
```

**2024-12-04 修正**: EPS Update Type の抽出で `octet >> 4` (上位4ビット) を使用していたバグを `octet & 0x07` (下位3ビット) に修正。これにより TAU ループが解消。

## 7. GTP-U データプレーン

**目的**: 制御プレーン (S1AP/NGAP) で確立した通信経路を使って、実際のユーザーデータ (ウェブページ、動画、メール等) を転送します。

**なぜ必要か**:
- **データカプセル化**: UE の IP パケットを GTP ヘッダーでカプセル化し、モバイルネットワーク内を転送
- **経路切替**: ハンドオーバー時に TEID を更新することで、データの転送先を切り替え
- **QoS 制御**: ベアラごとに異なる優先度でデータを処理

### ベアラパラメータ変換

**GTP-U (GPRS Tunneling Protocol - User Plane)** は、ユーザーデータをトンネルで転送するプロトコルです。UE の IP パケットを GTP ヘッダーで包んで、基地局とコアネットワーク間を転送します。

| 5G パラメータ (NGAP/NAS) | 4G パラメータ (S1AP/NAS) | 意味・目的 | 変換ロジック |
|----------------|----------------|-----------|--------------|
| PDU Session ID | E-RAB ID | **データ経路の ID**。1つの UE が複数の経路を持つ場合に区別。 | PDU Session ID + 4 (例: ID 1 -> E-RAB 5) |
| QFI / 5QI | QCI (QoS Class Identifier) | **通信品質クラス/フロー識別子**。QCI=4G QoS、5QI=5G QoS、QFI=QoS Flow ID。 | **現状 (MVP)**: <br>- **4G 側 (S1AP/ESM)** はデフォルトで **QCI=9** を固定設定 (動的マッピングは未実装)<br>- **5G 側 (NGAP)** に付与する **QFI/5QI** は、QCI が 1..9 なら同値、それ以外/不明なら **9 にフォールバック**<br>- **AMF から受信した QFI** は UE コンテキストに保存し、InitialContextSetupResponse の `associatedQosFlowList` に反映 |
| UPF Transport Layer Address | S-GW Transport Layer Address | **データ転送先の IP アドレス**。GTP-U パケットの宛先。 | UPF の IP アドレスをそのまま S-GW アドレスとして通知。 |
| UPF GTP-TEID | S-GW GTP-TEID | **トンネル識別子**。経路を特定するための 32bit の ID。 | UPF の TEID をそのまま S-GW TEID として通知。 |
| PDU Session Establishment Accept | Activate Default EPS Bearer Context Request | **セッション確立応答**。IP アドレス等を UE に通知。 | **NAS 変換**: <br>APN -> Access Point Name<br>PDU Address -> PDN Address<br>Protocol Config Options -> Protocol Config Options |

### TEID マッピング

```
eNB                    S1N2 Converter                    UPF
 │                            │                            │
 │  GTP-U (S1-U TEID)         │                            │
 │ ───────────────────────────►                            │
 │  Inner: UE IP packet       │                            │
 │                            │  GTP-U (N3 TEID)           │
 │                            │ ───────────────────────────►
 │                            │  Inner: UE IP packet       │
 │                            │                            │
 │                            │  GTP-U (N3 TEID)           │
 │                            │ ◄───────────────────────────
 │                            │  Inner: UE IP packet       │
 │  GTP-U (S1-U TEID)         │                            │
 │ ◄───────────────────────────                            │
 │  Inner: UE IP packet       │                            │
```

### TEID 管理

- **eNB S1-U TEID/IP**: eNB が生成し、S1AP InitialContextSetupResponse で通知（下り側で使用される TEID として扱う）
- **S1N2 Proxy (uplink) TEID**: S1N2 が自身用に割り当て、eNB へ通知（上りパケットはこの TEID 宛に到着）
- **UPF N3 TEID/IP**: UPF が生成し、NGAP InitialContextSetupRequest の PDU Session Resource で通知
- **転送動作（実装）**:
   - Uplink (S1-U→N3): GTP-U ヘッダ内 TEID をキーにマッピングを参照し、TEID を UPF 側 N3 TEID に書き換えて UPF へ送出
   - Downlink (N3→S1-U): Transparent proxy として TEID を書き換えず、UE コンテキストに保持した eNB の S1-U IP 宛に送出

## 8. UE ID マッピング

**目的**: 同じ UE を識別するための各種 ID を管理し、S1AP と NGAP の間で正しく対応付けます。

**なぜ必要か**: 1つの UE に対して複数の ID が付与されるため、S1N2 Converter が「この S1AP メッセージはどの NGAP コネクションに対応するか」を管理する必要があります。

### ID 対応関係

| S1AP ID | NGAP ID | 意味・目的 | 管理方法 |
|---------|---------|-----------|----------|
| ENB-UE-S1AP-ID | RAN-UE-NGAP-ID | **基地局側の UE 識別子**。eNB/gNB が割り当てるローカル ID。 | 同一値を使用 |
| MME-UE-S1AP-ID | AMF-UE-NGAP-ID | **コア側の UE 識別子**。MME/AMF が割り当てる ID。 | Converter がマッピング管理 |
| IMSI | SUCI | **恒久的な加入者識別子**。SIM カードに記録された世界で一意の番号。 | NAS 変換時に変換 |
| GUTI | 5G-GUTI | **一時的な UE 識別子**。IMSI を隠すために使用する一時 ID。 | NAS 変換時に変換 |

## 9. エラーハンドリング

**目的**: 認証失敗、セキュリティ拒否、UE 切断などの異常系シナリオに対応し、リソースを適切に解放します。

### Authentication Failure (Sync Failure / AUTS)

**目的**: 認証時に SQN (シーケンス番号) の不整合が発生した場合、UE が AUTS (再同期トークン) を返し、ネットワーク側の SQN を修正して認証を再試行します。

**なぜ必要か**:
- SQN はリプレイ攻撃防止のため、UE とネットワークの双方でインクリメントされる
- SIM カードの入れ替え、長期間の電源オフ等で SQN がずれることがある
- AUTS を使って UE 側の SQN をネットワークに通知し、同期を取る

認証時に SQN 不整合が発生した場合、UE は Authentication Failure を返します。S1N2 Converter はこれを 5G へ透過的に転送します。

```
UE        eNB                S1N2 Converter                AMF/AUSF
 │         │                        │                        │
 │ Auth    │                        │                        │
 │ Fail    │                        │                        │
 │ ────────►                        │                        │
 │         │ UL NASTransport(S1AP)  │                        │
 │         │ ────────────────────────►                        │
 │         │ NAS: Auth Failure      │                        │
 │         │ (cause=21, AUTS)       │                        │
 │         │                        │                        │
 │         │                        │ UL NASTransport(NGAP)  │
 │         │                        │ ────────────────────────►
 │         │                        │ NAS: Auth Failure      │
 │         │                        │ (cause=21, AUTS)       │
 │         │                        │                        │
 │         │                        │ (AUSF re-sync)         │
 │         │                        │                        │
 │         │                        │ DL NASTransport(NGAP)  │
 │         │                        │ ◄────────────────────────
 │         │                        │ NAS: Auth Request (new)│
```

**パラメータ変換**:

| 4G パラメータ | 5G パラメータ | 意味・目的 | 変換ロジック |
|--------------|--------------|-----------|--------------|
| EMM Cause (21 = Synch failure) | 5GMM Cause | **失敗理由**。21=SQN同期失敗, 他にも各種原因コードがある。 | そのままコピー。 |
| Auth Failure Parameter (IEI 0x30) | Auth Failure Parameter (IEI 0x30) | **AUTS (再同期トークン)**。14バイトの再同期情報。UE が保持する SQN を暗号化して通知。 | **AUTS (14 bytes)** をそのままコピー。<br>AUSF が SQN 再同期を実行。 |

### Security Mode Reject

**目的**: UE がセキュリティ設定を拒否した場合の処理です。アルゴリズムの不一致、セキュリティコンテキストの問題などが原因になります。

UE が Security Mode Command を拒否した場合：
1. UE → eNB: Security Mode Reject (4G NAS)
2. eNB → S1N2: UplinkNASTransport (S1AP)
3. S1N2 → AMF: UplinkNASTransport (NGAP) + NAS: Security Mode Reject
4. AMF: 認証手順を再試行または UE コンテキスト解放

### UE Context Release

**目的**: UE の接続が終了した際に、関連するリソース (ベアラ、TEID マッピング、UE コンテキスト) を解放します。電波圈外移動、電源オフ、タイムアウトなどで発生します。

UE が切断された場合：
1. eNB → S1N2: UEContextReleaseRequest (S1AP)
2. S1N2 → AMF: UEContextReleaseRequest (NGAP)
3. AMF → S1N2: UEContextReleaseCommand (NGAP)
4. S1N2 → eNB: UEContextReleaseCommand (S1AP)
5. S1N2: TEID マッピングと UE コンテキストをクリーンアップ

## 10. pcap サンプル解析 (20251203_9.pcap)

### 成功シーケンス (Frame 3383-3726)

| Time (s) | Direction | Protocol | Message |
|----------|-----------|----------|---------|
| 86.927 | eNB→S1N2 | S1AP | InitialUEMessage (Attach Request) |
| 86.927 | S1N2→AMF | NGAP | InitialUEMessage (Registration Request) |
| 86.934 | AMF→S1N2 | NGAP | DownlinkNASTransport (Auth Request) |
| 86.934 | S1N2→eNB | S1AP | DownlinkNASTransport (Auth Request) |
| 87.012 | eNB→S1N2 | S1AP | UplinkNASTransport (Auth Response) |
| 87.012 | S1N2→AMF | NGAP | UplinkNASTransport (Auth Response) |
| 87.020 | AMF→S1N2 | NGAP | DownlinkNASTransport (Security Mode Cmd) |
| 87.020 | S1N2→eNB | S1AP | DownlinkNASTransport (Security Mode Cmd) |
| 87.052 | eNB→S1N2 | S1AP | UplinkNASTransport (Security Mode Complete) |
| 87.052 | S1N2→AMF | NGAP | UplinkNASTransport (Security Mode Complete + Reg Request) |
| 87.078 | AMF→S1N2 | NGAP | InitialContextSetupRequest |
| 87.078 | S1N2→eNB | S1AP | InitialContextSetupRequest |
| 87.372 | eNB→S1N2 | S1AP | InitialContextSetupResponse |
| 87.373 | eNB→S1N2 | S1AP | UplinkNASTransport (Attach Complete) |
| 87.373 | S1N2→AMF | NGAP | UplinkNASTransport (Registration Complete) |
| 87.396 | S1N2→AMF | NGAP | InitialContextSetupResponse |

### データ通信 (Frame 3860-)

| Time (s) | Direction | Protocol | Message |
|----------|-----------|----------|---------|
| 90.592 | eNB→S1N2 | GTP-U | Echo Request (ICMP to 8.8.8.8) |
| 90.592 | S1N2→UPF | GTP-U | Echo Request (TEID変換済み) |
| 90.597 | UPF→S1N2 | GTP-U | Echo Reply |
| 90.597 | S1N2→eNB | GTP-U | Echo Reply (TEID変換済み) |

### 成功シーケンス (20251204_5.pcap + dockerログ突合)

対象:
- pcap: `log/20251204_5.pcap`
- s1n2ログ: `log/docker/s1n2_follow_20251204_203753.log`

#### Control Plane (MME-UE-S1AP-ID=4 / ENB-UE-S1AP-ID=32, PDU Session ID=5)

| Time (s) | Frame | Direction | Protocol | Message / Key fields |
|----------|-------|-----------|----------|----------------------|
| 78.400 | 4029 | S1N2→eNB | S1AP (proc=9) | InitialContextSetupRequest: `gTP-TEID=0x00000001`, `transportLayerAddress=172.24.0.30`, `e-RAB-ID=5`, `QCI=9` |
| 78.689 | 4059 | eNB→S1N2 | S1AP (proc=9) | InitialContextSetupResponse: `gTP-TEID=0x01000608`, `transportLayerAddress=172.24.0.111` |
| 78.690 | 4064 | S1N2→AMF | NGAP (proc=46) | UplinkNASTransport: NAS 5GMM `Registration complete (0x43)` |
| 78.692 | 4066 | S1N2→AMF | NGAP (proc=46) | UplinkNASTransport: NAS 5GSM `PDU Session Establishment Request (0xC1)`, `PDU session identity=5` |
| 78.719 | 4176 | AMF→S1N2 | NGAP (proc=14) | InitialContextSetupRequest (PDUSessionResourceSetupListCxtReq含む) |
| 78.720 | 4179 | S1N2→AMF | NGAP (proc=14) | InitialContextSetupResponse |

対応する s1n2 ログ（行番号）:
- `1529`: `[ICS-TRIGGER]` Attach Accept 検知
- `1541`: `Bridged 5G Registration Accept -> S1AP InitialContextSetupRequest (MME-UE=4, ENB-UE=32, NAS=48 bytes)`
- `1594`: `[ICS] Marked ICS completed`
- `1664`: `[PDU Session] Detected Registration Complete, sending PDU Session Establishment Request`
- `1719`: `NGAP InitialContextSetupRequest detected (proc=14)`

関連コード（ログ出力・分岐点の代表）:
- `sXGP-5G/src/s1n2_converter.c:2496` ICS送信ログ
- `sXGP-5G/src/s1n2_converter.c:4555` Registration Complete 検知→PDU Session送信
- `sXGP-5G/src/s1n2_converter.c:5324` NGAP ICS(proc=14) 検知

#### User Plane (GTP-U, Hybrid Proxy: ULはTEID変換 / DLは透過)

| Time (s) | Frame | Direction | GTP-U TEID | 観測 |
|----------|-------|-----------|------------|------|
| 81.769 | 4250 | eNB→S1N2 | 0x00000001 | UL (S1-U) 到来 |
| 81.769 | 4251 | S1N2→UPF | 0x0000e2ad | UL (N3) へ転送（TEID変換） |
| 81.773 | 4254 | UPF→S1N2 | 0x01000608 | DL (N3) 到来 |
| 81.773 | 4255 | S1N2→eNB | 0x01000608 | DL (S1-U) へ転送（TEID透過） |

対応する s1n2 ログ（代表例）:
- `1734`: `Added explicit TEID mapping: S1-U 0x00000001 ↔ N3 0x0000e2ad`
- `1772-1773`: `S1-U→N3 lookup` / `S1-U→N3 GTP-U conversion: TEID 0x00000001 -> 0x0000e2ad`
- `1779`: `Downlink N3→S1-U: Transparent proxy (no TEID translation), TEID 0x01000608`

関連コード（代表）:
- `sXGP-5G/src/transport/gtp_tunnel.c:334` `Added explicit TEID mapping`
- `sXGP-5G/src/transport/gtp_tunnel.c:360` `S1-U→N3 lookup`
- `sXGP-5G/src/transport/gtp_tunnel.c:578` `S1-U→N3 GTP-U conversion`
- `sXGP-5G/src/transport/gtp_tunnel.c:630` `Downlink ... Transparent proxy`

## 11. 関連ソースコード

| ファイル | 機能 |
|---------|------|
| `src/s1n2_converter.c` | メイン変換ロジック |
| `src/s1n2_nas_converter.c` | NAS メッセージ変換 (4G↔5G) |
| `src/s1n2_gtp.c` | GTP-U プロキシ、TEID 管理 |
| `src/s1n2_auth.c` | 認証パラメータ変換 |
| `src/s1n2_security.c` | セキュリティコンテキスト管理 |
| `include/s1n2_converter.h` | 公開 API 定義 |

## 12. 主要な変換関数

```c
// S1AP → NGAP 変換
int s1n2_convert_s1setup_to_ngsetup(...)      // S1SetupRequest → NGSetupRequest
int s1n2_convert_initial_ue_message(...)      // InitialUEMessage 変換
int s1n2_convert_uplink_nas_transport(...)    // UplinkNASTransport 変換
int s1n2_convert_initial_context_setup_response(...)  // ICS Response 変換

// NGAP → S1AP 変換
int s1n2_convert_ngsetup_to_s1setup(...)      // NGSetupResponse → S1SetupResponse
int s1n2_convert_ngap_downlink_nas_transport(...)  // DownlinkNASTransport 変換

// NAS 変換
int convert_4g_nas_to_5g(...)                 // 4G EPS NAS → 5G NAS
int convert_5g_nas_to_4g(...)                 // 5G NAS → 4G EPS NAS
int s1n2_build_tau_accept_nas(...)            // TAU Accept 生成 (ローカル)

// メッセージハンドラ
int s1n2_handle_s1c_message(...)              // S1AP メッセージ受信処理
int s1n2_handle_n2_message(...)               // NGAP メッセージ受信処理
```

## 13. 未実装機能 (Future Work)

以下の機能は現時点で未実装であり、将来的な拡張候補です。

### 13.1 Detach / Deregistration

| 4G 手順 | 5G 手順 | 現状の対応 |
|---------|---------|-----------|
| Detach Request (UE initiated) | Deregistration Request | **未実装**: UE Context Release で代替。 |
| Detach Request (Network initiated) | Deregistration Request | **未実装**: UE Context Release で代替。 |
| Detach Accept | Deregistration Accept | **未実装** |

**必要な実装**:
- Detach Request (0x45) の検出と 5G Deregistration Request への変換
- Detach Accept (0x46) の生成

### 13.2 Service Request

| 4G 手順 | 5G 手順 | 現状の対応 |
|---------|---------|-----------|
| Service Request | Service Request | **部分実装**: TAU で代替処理。 |
| Extended Service Request | Service Request | **未実装** |

**必要な実装**:
- Service Request (0x4C) の検出と変換
- Extended Service Request (0x4D) の検出と変換
- CSFB (Circuit Switched Fallback) 関連 IE の処理

### 13.3 Paging

| 4G 手順 | 5G 手順 | 現状の対応 |
|---------|---------|-----------|
| S1AP Paging | NGAP Paging | **未実装**: Idle Mode 未対応。 |

**必要な実装**:
- NGAP Paging メッセージの受信
- S1AP Paging メッセージへの変換
  - UE Paging Identity (5G-S-TMSI → S-TMSI)
  - TAI List の変換
  - Paging DRX の変換

**備考**: Idle Mode からの復帰には Service Request の実装も必要。

### 13.4 Handover

| 4G 手順 | 5G 手順 | 現状の対応 |
|---------|---------|-----------|
| S1 Handover | Xn/N2 Handover | **未実装** |
| X2 Handover | Xn Handover | **対象外** (eNB間直接通信) |

**必要な実装**:
- Handover Required (S1AP) → Handover Required (NGAP)
- Handover Request (NGAP) → Handover Request (S1AP)
- Handover Command/Notify の変換
- ターゲットセル情報 (E-UTRAN CGI → NR CGI) の変換

**備考**: Inter-RAT Handover (4G↔5G) ではなく、同一 RAT 内での S1N2 経由 Handover を想定。

### 13.5 E-RAB Modification / Bearer Modification

| 4G 手順 | 5G 手順 | 現状の対応 |
|---------|---------|-----------|
| E-RAB Modify Request | PDU Session Modification Request | **未実装** |
| E-RAB Release Command | PDU Session Release Command | **未実装** |

**必要な実装**:
- QoS パラメータ変更の変換
- ベアラ/セッションの動的追加・削除

### 13.6 NAS Ciphering (Encryption)

| 機能 | 現状の対応 |
|------|-----------|
| Downlink NAS Ciphering | **未実装**: 完全性保護のみ対応。 |
| Uplink NAS Deciphering | **未実装**: 完全性検証のみ対応。 |

**必要な実装**:
- `NEA1/NEA2` (5G) ⇔ `EEA1/EEA2` (4G) の暗号化/復号処理
- 現状は NULL 暗号 (NEA0/EEA0) で運用可能な環境を前提。

### 13.7 Multi-PDU Session

| 機能 | 現状の対応 |
|------|-----------|
| 複数 PDU Session | **未実装**: 単一セッションのみ対応。 |

**必要な実装**:
- 複数 E-RAB / PDU Session ID のマッピング管理
- GTP-U TEID の複数ベアラ対応

---

*Document generated: 2024-12-09*
*Based on pcap analysis: 20251204_3.pcap (TAU fix verified)*
*Last updated: 2024-12-09 - Added TAU sequence, Auth Failure/AUTS handling, Future Work*
