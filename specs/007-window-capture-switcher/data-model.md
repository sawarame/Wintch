# データモデル設計 (Data Model): ウィンドウキャプチャ表示型スイッチャー

**Feature**: `007-window-capture-switcher`  
**Date**: 2026-11-15  
**Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/007-window-capture-switcher/spec.md)

## 1. ドメインモデル（`Sources/WintchCore/Domain/`）

### 1.1 `SwitcherDisplayStyle`（新規）
通常スイッチャー（ホールド式）の表示形式を表す値型。

| プロパティ / ケース | 型 / 値 | 説明 |
|---|---|---|
| `.list` | `String` rawValue: `"list"` | 従来の縦型リスト表示（デフォルト値、画面収録権限不要） |
| `.capture` | `String` rawValue: `"capture"` | Windows Alt+Tab 風のカードグリッド表示（オプトインで画面収録権限を使用） |
| `default` (static) | `SwitcherDisplayStyle` | `.list` を返す |
| `displayName` | `String` | UI 表示ラベル（`"リスト型"` / `"キャプチャ表示型"`） |

- **適合プロトコル**: `String, Codable, CaseIterable, Equatable, Sendable`
- **バリデーションルール**: `PreferencesStore` 読み込み時に未知の値・破損データが存在する場合は安全に `.list` へフォールバックする。

---

### 1.2 `ScreenRecordingPermissionStatus`（新規）
画面収録権限の現在状態を表す列挙型（`AccessibilityPermissionStatus` と対になるドメインモデル）。

| ケース | 説明 |
|---|---|
| `.granted` | 画面収録権限が許可済み（`CGPreflightScreenCaptureAccess() == true`） |
| `.denied` | 画面収録権限が未許可または取り消し済み |

- **適合プロトコル**: `Equatable, Sendable`
- **制約**: `SwitcherDisplayStyle == .list` の間は評価・参照しない（FR-003）。

---

### 1.3 `SwitcherGridLayout`（新規・純粋ロジック）
キャプチャ表示型グリッドの列数計算と 4 方向カーソル移動を行う純粋ロジック型。

#### 計算入力・出力仕様
- **定数／レイアウト基準値**:
  - `cardWidth: CGFloat`（例: `216`）
  - `cardHeight: CGFloat`（例: `164` — プレビュー領域 + 下部アプリアイコン・タイトル領域）
  - `cardSpacing: CGFloat`（例: `10`）
  - `gridPadding: CGFloat`（例: `14`）
  - `maxColumnsLimit: Int`（例: `5` — 1 行に並びすぎない上限）
- **`columnsCount(itemCount:availableScreenWidth:)`**:
  - `itemCount <= 0` の場合 `1`
  - 画面幅の上限比率（例: `availableScreenWidth * 0.85`）内に収まる最大列数 `fitColumns = max(1, min(maxColumnsLimit, floor((maxPanelWidth - gridPadding * 2 + cardSpacing) / (cardWidth + cardSpacing))))`
  - 実列数 = `min(itemCount, fitColumns)`（少ないウィンドウ数では不要な余白を作らない）
- **`moveIndex(current:direction:count:columns:)`**:
  - `count <= 0` → `0`
  - `.right`: `(current + 1) % count`（MRU 順で次へ・循環）
  - `.left`: `(current - 1 + count) % count`（MRU 順で前へ・循環）
  - `.down`:
    - 現在行 `row = current / columns`、現在列 `col = current % columns`、総行数 `rows = (count + columns - 1) / columns`
    - `nextRow = (row + 1) % rows`
    - 次の行の先頭 `rowStart = nextRow * columns`、次の行の件数 `rowLength = min(columns, count - rowStart)`
    - 移動先 = `rowStart + min(col, rowLength - 1)`
  - `.up`:
    - `prevRow = (row - 1 + rows) % rows`
    - 前の行の先頭 `rowStart = prevRow * columns`、前の行の件数 `rowLength = min(columns, count - rowStart)`
    - 移動先 = `rowStart + min(col, rowLength - 1)`

---

### 1.4 `ArrowDirection`（既存 `HotKeyMonitoring.swift` 拡張）
既存の `.up`, `.down` に加えて `.left`, `.right` を定義する。

| ケース | 通常のリスト/ランチャーでの挙動 | キャプチャ表示型グリッドでの挙動 |
|---|---|---|
| `.up` | 前の項目へ移動（循環） | 1 つ上の行の同列（または末尾）へ移動（循環） |
| `.down` | 次の項目へ移動（循環） | 1 つ下の行の同列（または末尾）へ移動（循環） |
| `.left` | 前の項目へ移動（循環）※通常モードのみ横取り | 1 つ前のカード（MRU 前項目）へ移動（循環） |
| `.right` | 次の項目へ移動（循環）※通常モードのみ横取り | 1 つ次のカード（MRU 次項目）へ移動（循環） |

---

## 2. キャプチャ・キャッシュモデル（`Services/` および `ViewModels/`）

### 2.1 `WindowCaptureResult`（内部・サービス間受け渡し）
非同期キャプチャ取得の結果を表す値。

| フィールド | 型 | 説明 |
|---|---|---|
| `cgWindowID` | `UInt32` | 対象ウィンドウの CoreGraphics ウィンドウ ID |
| `image` | `NSImage` | 縮小済みサムネイル画像（メモリ上のみ） |

- **Sendable 境界**: `WindowCaptureService` のバックグラウンド処理では `CGImage`（macOS 標準の `Sendable` / CoreGraphics 不変ビットマップ）を受け渡し、MainActor 上の `NSImage(cgImage:size:)` 生成およびキャッシュ格納時に安全に変換する。

### 2.2 一時メモリキャッシュ（`WindowCaptureService` 内）
- **キー**: `cgWindowID: UInt32`
- **値**: `NSImage` + LRU アクセス順序配列
- **容量上限**: 最大 `50` ウィンドウ分（超過時は最も古いエントリを破棄）
- **永続化**: 禁止（ディスク・UserDefaults・ログへの出力なし）
- **破棄トリガー**:
  1. 表示形式が `.capture` → `.list` へ変更されたとき（全消去）
  2. ウィンドウ終了操作でウィンドウ／アプリが閉じられたとき（対象 `cgWindowID` を削除）
  3. 上限件数超過時の LRU 追い出し
  4. アプリ終了時（`quit()`）

---

## 3. 状態遷移（`SwitcherViewModel` / `SettingsViewModel`）

### 3.1 通常スイッチャー表示セッション状態遷移（キャプチャ表示型）

```text
[Inactive]
   │ (1) Option + Tab 押下（アクセシビリティ許可済み・有効ウィンドウ ≥ 1）
   ▼
[Normal + Capture Presenting (即時表示)]
   ├─ displayedResults = MRU順ウィンドウ一覧
   ├─ capturedThumbnails = キャッシュ済み CGWindowID 分を即時セット（未キャッシュは nil → アイコンプレースホルダー）
   ├─ screenRecordingStatus = 権限チェック（.granted / .denied）
   │
   ├──(screenRecordingStatus == .granted)──▶ [非同期キャプチャ取得タスク起動 (generation = N)]
   │                                            ├─ 1件完了ごとに generation == N && mode == .normal を検証
   │                                            └─ 一致した WindowEntry.id へ最新サムネイルを反映
   │
   ├──(screenRecordingStatus == .denied)────▶ [権限未許可バナー表示 + プレースホルダーのまま継続]
   │
   ├──(Mod + Q でウィンドウクローズ)────────▶ 対象を一覧・キャッシュから除外、indexAfterRemoval で補正、
   │                                            残余0件なら [Inactive] へ遷移
   │
   └──(修飾キー解放 / クリック / Esc / 外部クリック)
          ▼
       [Inactive] (進行中のキャプチャタスクを即時 cancel()、generation インクリメント)
```

### 3.2 設定画面表示形式切り替え遷移（`SettingsViewModel`）

```text
[List Style (Default)]
   │ ユーザーが「キャプチャ表示型」を選択
   ▼
[Capture Style]
   ├─ PreferencesStore.saveNormalDisplayStyle(.capture)
   ├─ OnDisplayStyleChanged(.capture) → SwitcherViewModel へ即時反映
   └─ ScreenRecordingPermissionService.currentStatus() を確認
        ├─ .granted → 「許可済み」表示
        └─ .denied  → 権限要求ボタン（「権限をリクエスト」/「システム設定を開く」）＋案内表示

[Capture Style]
   │ ユーザーが「リスト型」を選択
   ▼
[List Style]
   ├─ PreferencesStore.saveNormalDisplayStyle(.list)
   ├─ OnDisplayStyleChanged(.list) → SwitcherViewModel へ即時反映 & キャプチャキャッシュ全消去
   └─ 画面収録権限 UI・確認処理を即時非表示（FR-003）
```
